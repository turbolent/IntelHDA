#define MACH_USER_API 1

#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>
#import <mach/message.h>
#import <string.h>

#import "IntelHDAController.h"
#import "IntelHDADriver.h"

#define PCI_COMMAND_MEMORY_ENABLE   0x0002U
#define PCI_COMMAND_MASTER_ENABLE   0x0004U
#define PCI_BASE_IO_BIT             0x00000001U
#define PCI_BASE_MEMORY(addr)       ((addr) & 0xfffffff0U)
#define HDA_MMIO_SIZE               0x4000U
#define INTEL_VENDOR_ID             0x8086U
#define INTEL_ICH6_HDA_DEVICE_ID    0x2668U
#define INTEL_6SERIES_HDA_DEVICE_ID 0x1c20U
#define INTEL_Q270_HDA_DEVICE_ID 0xa2f0U
#define INTEL_SCH_HDA_DEVC          0x78U
#define INTEL_SCH_HDA_DEVC_NOSNOOP  0x00000800U
#define HDA_IOAUDIO_DMA_SIZE        0x8000U
#define HDA_IOAUDIO_DESCRIPTOR_SIZE 0x1000U
#define HDA_WORKER_MS               4U

static void hdaInterruptWorker(void *argument);
static const char codecDeviceName[] = "IntelHDA";
static const char codecDeviceKind[] = "Audio";
static struct hda_state *gHDA = NULL;
static BOOL attachedController = NO;
static BOOL reservingOutputBuffer = NO;

extern msg_return_t msg_send_from_kernel(msg_header_t *, msg_option_t, msg_timeout_t);
static msg_header_t hdaInterruptMessageTemplate = {
    0, 1, sizeof(msg_header_t), MSG_TYPE_NORMAL,
    PORT_NULL, PORT_NULL, IO_DEVICE_INTERRUPT_MSG
};
static unsigned atomicExchangeUnsigned(volatile unsigned *p, unsigned v) {
    __asm__ volatile("xchgl %0,%1" : "=r" (v), "=m" (*p)
                     : "0" (v), "m" (*p) : "memory");
    return v;
}
static unsigned saveRawInterrupts(void) {
    unsigned flags;
    __asm__ volatile("pushfl; popl %0; cli" : "=r" (flags) : : "memory");
    return flags;
}
static void restoreRawInterrupts(unsigned flags) {
    __asm__ volatile("pushl %0; popfl" : : "r" (flags) : "memory", "cc");
}
@interface IOAudio (IntelHDAAudioPrivate)
- _outputChannel;
- (void)_interruptOccurred;
- (void)_stopDMAForChannel:channel;
- (void)_dataPendingForChannel:channel;
@end
@interface Object (IntelHDAAudioChannelPrivate)
- (void)setDMASize:(unsigned)size;
- (unsigned)setDescriptorSize:(unsigned)size;
- (BOOL)createChannelBuffer;
- (unsigned)enqueueCount;
- (unsigned)dmaCount;
@end
@interface IntelHDADriver (IntelHDAPrivate)
- (BOOL)_readPCIConfigImage:(unsigned *)image;
- (BOOL)_auditPCIInterruptCapabilities;
- (BOOL)_setPCIInterruptDisabled;
- (BOOL)_disableMSI;
- (IOReturn)_allocatePCIMSI;
- (BOOL)_releasePCIMSI;
- (BOOL)_disableAndReleasePCIMSI;
- (BOOL)_activateMSI;
- (int)_servicePlaybackPass;
- (int)_samplePlayback:(unsigned *)periods;
- (unsigned)_queuedOutputPeriods;
- (void)_completeOutputPeriod;
- (int)_resynchronizeOutput;
- (int)_outputReady;
- (int)_finishMSIPass:(int)acknowledge pending:(unsigned *)pending;
- (void)_containPlayback:(const char *)reason;
@end
static int servicePass(void *context) {
    return [(IntelHDADriver *)context _servicePlaybackPass];
}
static int outputReady(void *context) {
    return [(IntelHDADriver *)context _outputReady];
}
static int finishPass(void *context, int acknowledge, unsigned *pending) {
    return [(IntelHDADriver *)context _finishMSIPass:acknowledge pending:pending];
}
static int refillSample(void *context, unsigned *periods) {
    return [(IntelHDADriver *)context _samplePlayback:periods];
}
static unsigned refillQueued(void *context) {
    return [(IntelHDADriver *)context _queuedOutputPeriods];
}
static void refillComplete(void *context) {
    [(IntelHDADriver *)context _completeOutputPeriod];
}
static const IntelHDARefillOps refillOps = {
    refillSample, refillQueued, refillComplete
};
static const IntelHDAMSIEpochOps epochOps = {servicePass, outputReady, finishPass};
static const char *encodingName(unsigned int encoding) {
    switch (encoding) {
    case NX_SoundStreamDataEncoding_Linear8: return "linear8";
    case NX_SoundStreamDataEncoding_Linear16: return "linear16";
    case NX_SoundStreamDataEncoding_Mulaw8: return "mulaw8";
    case NX_SoundStreamDataEncoding_Alaw8: return "alaw8";
    default: return "unknown";
    }
}

static BOOL enablePCHSnoop(id deviceDescription, unsigned deviceID) {
    unsigned long oldValue, value;
    if (deviceID != INTEL_6SERIES_HDA_DEVICE_ID &&
        deviceID != INTEL_Q270_HDA_DEVICE_ID) return YES;
    if ([IODirectDevice getPCIConfigData:&oldValue atRegister:INTEL_SCH_HDA_DEVC
            withDeviceDescription:deviceDescription] != IO_R_SUCCESS) return NO;
    value = oldValue & ~INTEL_SCH_HDA_DEVC_NOSNOOP;
    if ([IODirectDevice setPCIConfigData:value atRegister:INTEL_SCH_HDA_DEVC
            withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        [IODirectDevice getPCIConfigData:&value atRegister:INTEL_SCH_HDA_DEVC
            withDeviceDescription:deviceDescription] != IO_R_SUCCESS ||
        (value & INTEL_SCH_HDA_DEVC_NOSNOOP)) return NO;
    IOLog("%s: PCH snoop enabled DEVC %08x -> %08x\n", DRV_TITLE,
          (unsigned)oldValue, (unsigned)value);
    return YES;
}
@implementation IntelHDADriver

- (BOOL)isEISAPresent {
    if (reservingOutputBuffer)
        return YES;
    return [super isEISAPresent];
}

+ (BOOL)probe:deviceDescription {
    IntelHDADriver *driver;
    if (attachedController) {
        IOLog("%s: refusing additional controller\n", DRV_TITLE);
        return NO;
    }
    driver = [self alloc];
    if (driver == nil)
        return NO;
    return [driver initFromDeviceDescription:deviceDescription] != nil;
}

/* IOAudio registers itself before returning from super init. Publish only
 * after the output buffer and interrupt transport are ready. */
- registerDevice {
    if (_initializing) return self;
    return [super registerDevice];
}
- initFromDeviceDescription:deviceDescription {
    IOReturn result;
    IOPCIConfigSpace pci;
    IORange memoryRange;
    id configTable;
    const char *value;
    id outputChannel;
    BOOL outputBufferOK;
    unsigned classCode;
    unsigned bar0;

    _initializing = YES;
    _msiRequested = YES;
    _msiTestFault = HDA_MSI_TEST_NONE;
    configTable = [deviceDescription configTable];
    value = [configTable valueForStringKey:"Interrupt Mode"];
    if (value != 0) {
        if (strcmp(value, "MSI") == 0)
            _msiRequested = YES;
        else if (strcmp(value, "Polling") == 0)
            _msiRequested = NO;
        else {
            IOLog("%s: unsupported Interrupt Mode '%s'; only MSI and Polling are valid\n",
                  DRV_TITLE, value);
            [configTable freeString:value];
            return nil;
        }
        [configTable freeString:value];
    }
    value = [configTable valueForStringKey:"MSI Test Mode"];
    if (value != 0) {
        if (strcmp(value, "YES") == 0)
            _msiTestMode = YES;
        else if (strcmp(value, "NO") != 0) {
            IOLog("%s: MSI Test Mode accepts only YES or NO\n", DRV_TITLE);
            [configTable freeString:value];
            return nil;
        }
        [configTable freeString:value];
    }
    value = [configTable valueForStringKey:"MSI Test Fault"];
    if (value != 0) {
        if (!_msiTestMode) {
            IOLog("%s: MSI Test Fault requires MSI Test Mode=YES\n", DRV_TITLE);
            [configTable freeString:value];
            return nil;
        }
        _msiTestFault = IntelHDAMSITestFaultForName(value);
        if (_msiTestFault == HDA_MSI_TEST_INVALID) {
            IOLog("%s: unknown MSI Test Fault '%s'\n", DRV_TITLE, value);
            [configTable freeString:value];
            return nil;
        }
        [configTable freeString:value];
    }
    if (_msiTestMode && !_msiRequested) {
        IOLog("%s: MSI Test Mode requires Interrupt Mode=MSI\n", DRV_TITLE);
        return nil;
    }

    bzero(&pci, sizeof(pci));
    result = [IODirectDevice getPCIConfigSpace:&pci
                         withDeviceDescription:deviceDescription];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: cannot read PCI configuration (%s)\n", DRV_TITLE,
              [IODirectDevice stringFromReturn:result]);
        return nil;
    }
    classCode = pci.ClassCode;
    if (!((pci.VendorID == INTEL_VENDOR_ID &&
           (pci.DeviceID == INTEL_ICH6_HDA_DEVICE_ID ||
            pci.DeviceID == INTEL_Q270_HDA_DEVICE_ID ||
            pci.DeviceID == INTEL_6SERIES_HDA_DEVICE_ID)) ||
          classCode == 0x040300U)) {
        IOLog("%s: unsupported PCI device %04x:%04x class %06x\n",
              DRV_TITLE, pci.VendorID, pci.DeviceID, classCode);
        return nil;
    }
    bar0 = pci.BaseAddress[0];
    if ((bar0 & PCI_BASE_IO_BIT) != 0 || PCI_BASE_MEMORY(bar0) == 0) {
        IOLog("%s: invalid HDA MMIO BAR0 0x%08x\n", DRV_TITLE, bar0);
        return nil;
    }

    gHDA = IOMalloc(sizeof(*gHDA));
    if (gHDA == NULL)
        return nil;
    bzero(gHDA, sizeof(*gHDA));
    gHDA->magic = 0x48444131U;
    gHDA->vendor = pci.VendorID;
    gHDA->device = pci.DeviceID;
    gHDA->rev = pci.RevisionID;
    gHDA->subsystemVendor = pci.SubVendorID;
    gHDA->subsystemDevice = pci.SubDeviceID;
    gHDA->firmwareInterruptLine = pci.InterruptLine;
    gHDA->mmioPhys = PCI_BASE_MEMORY(bar0);
    gHDA->mmioSize = HDA_MMIO_SIZE;
    IOLog("%s %s milestone %s: PCI %04x:%04x SVID %04x SID %04x rev %02x class %06x\n",
          DRV_TITLE, DRV_VERSION, DRV_MILESTONE, gHDA->vendor, gHDA->device,
          gHDA->subsystemVendor, gHDA->subsystemDevice, gHDA->rev, classCode);
    IOLog("%s: MMIO BAR0 0x%08x; firmware InterruptLine %u is informational\n",
          DRV_TITLE, gHDA->mmioPhys, gHDA->firmwareInterruptLine);
    IOLog("%s: requested interrupt mode %s\n", DRV_TITLE,
          _msiRequested ? "MSI" : "Polling");

    memoryRange.start = gHDA->mmioPhys;
    memoryRange.size = gHDA->mmioSize;
    result = [deviceDescription setMemoryRangeList:&memoryRange num:1];
    if (result != IO_R_SUCCESS) {
        IOLog("%s: cannot claim MMIO range (%s)\n", DRV_TITLE,
              [IODirectDevice stringFromReturn:result]);
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
        return nil;
    }
    _stateLock = [[NXLock alloc] init];
    if (_stateLock == nil) {
        IOFree(gHDA, sizeof(*gHDA)); gHDA = NULL;
        return nil;
    }
    /* reset is called synchronously by IOAudio, before it creates channels. */
    _ioAudioMayBeLive = YES;
    if ([super initFromDeviceDescription:deviceDescription] == nil) {
        [self free];
        return nil;
    }
    outputChannel = [self _outputChannel];
    [outputChannel setDMASize:HDA_IOAUDIO_DMA_SIZE];
    (void)[outputChannel setDescriptorSize:HDA_IOAUDIO_DESCRIPTOR_SIZE];
    reservingOutputBuffer = YES;
    outputBufferOK = [outputChannel createChannelBuffer];
    reservingOutputBuffer = NO;
    if (!outputChannel || !outputBufferOK || !gHDA->dmaBufferVirt ||
        !gHDA->dmaBufferPhys || !gHDA->dmaBufferSize) {
        IOLog("%s: cannot reserve boot output DMA buffer\n", DRV_TITLE);
        [self free]; return nil;
    }
    IOLog("%s: reserved output DMA virt %08x phys %08x bytes %u period %u\n",
          DRV_TITLE, gHDA->dmaBufferVirt, gHDA->dmaBufferPhys,
          gHDA->dmaBufferSize, HDA_IOAUDIO_DESCRIPTOR_SIZE);
    if (_msiRequested) {
        if (![self _activateMSI]) {
            IOLog("%s: MSI initialization failed; no Polling fallback\n", DRV_TITLE);
            [self free]; return nil;
        }
    } else {
        _interruptPortKern = IOConvertPort([self interruptPort], IO_KernelIOTask, IO_Kernel);
        if (_interruptPortKern == PORT_NULL) { [self free]; return nil; }
        _workerRunning = 1;
        _workerThread = IOForkThread(hdaInterruptWorker, self);
        if (!_workerThread) { _workerRunning = 0; [self free]; return nil; }
        IOLog("%s: explicit 4 ms Polling, no PCIMSI allocation\n", DRV_TITLE);
    }
    _initializing = NO;
    _ready = YES;
    attachedController = YES;
    if (![self registerDevice]) { [self free]; return nil; }
    return self;
}

- free {
    _ready = NO;
    _stopping = YES;
    _workerRunning = 0;
    if (_workerThread) {
        while (!_workerExited) IOSleep(1);
        _workerThread = NULL;
    }
    if (_stateLock) {
        [_stateLock lock];
        if (gHDA && gHDA->regs) {
            hdaQuiesceInterrupts(gHDA);
            if (!hdaStopOutput(gHDA)) _msiUnsafeToFree = YES;
            hdaAcknowledgePending(gHDA);
        }
        _msiActive = NO;
        [_stateLock unlock];
    }
    /* Release may sleep: never call it under a consumer lock. */
    if (_pciConfigured && ![self _disableAndReleasePCIMSI]) _msiUnsafeToFree = YES;
    if (_ioAudioMayBeLive || _msiEverAllocated || _msiUnsafeToFree) {
        attachedController = YES;
        IOLog("%s: stopped; owner/ports/DMA retained until reboot (allocated=%u)\n",
              DRV_TITLE, _msiAllocated);
        return self;
    }
    if (gHDA) {
        hdaShutdownController(gHDA);
        if (gHDA->regs) [self unmapMemoryRange:0 from:(vm_address_t)gHDA->regs];
        IOFree(gHDA, sizeof(*gHDA)); gHDA = NULL;
    }
    if (_stateLock) { [_stateLock free]; _stateLock = nil; }
    attachedController = NO;
    return [super free];
}

- (BOOL)reset {
    IOReturn result;
    BOOL ok;
    if (!_stateLock || _stopping || _quarantined) return NO;
    [_stateLock lock];
    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];
    ok = gHDA != NULL;
    if (ok && !gHDA->initialized) {
        /* IODirectDevice is initialized and its interrupt port is attached. */
        ok = [self _setPCIInterruptDisabled] && [self _auditPCIInterruptCapabilities];
        if (ok) { _pciConfigured = YES; ok = [self _disableMSI]; }
        if (ok && _msiRequested)
            ok = _pciInterruptCapabilities.msiFound &&
                 IntelHDAMSIBuildLayout(_pciInterruptCapabilities.msiOffset,
                    _pciInterruptCapabilities.msiControl, &_msiLayout);
        if (_msiTestFault == HDA_MSI_TEST_MISSING_CAP) ok = NO;
        if (ok && gHDA->vendor == INTEL_VENDOR_ID)
            ok = enablePCHSnoop([self deviceDescription], gHDA->device);
        if (ok && !gHDA->regs) {
            result = [self mapMemoryRange:0 to:(vm_address_t *)&gHDA->regs
                               findSpace:YES cache:IO_CacheOff];
            ok = result == IO_R_SUCCESS;
        }
        if (ok) ok = hdaInitController(gHDA) == 0;
    } else if (ok) {
        ok = hdaStopOutput(gHDA);
    }
    [_stateLock unlock];
    return ok;
}

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                               length:(unsigned int)numBytes
                                 read:(BOOL)isRead
                       needsLowMemory:(BOOL)lowerMem
                            limitSize:(BOOL)limitSize {
    IOReturn result;
    unsigned physAddr;
    if (isRead || gHDA == NULL)
        return NULL;
    result = IOPhysicalFromVirtual(IOVmTaskSelf(),
                                   (vm_address_t)*physicalAddress, &physAddr);
    if (result != IO_R_SUCCESS) {
        IOLog("%s: cannot resolve IOAudio DMA buffer\n", DRV_TITLE);
        return NULL;
    }
    gHDA->dmaBufferPhys = physAddr;
    gHDA->dmaBufferVirt = *physicalAddress;
    gHDA->dmaBufferSize = numBytes;
    return (IOEISADMABuffer)physAddr;
}

- (BOOL)startDMAForChannel:(unsigned int)localChannel
                       read:(BOOL)isRead
                     buffer:(IOEISADMABuffer)buffer
    bufferSizeForInterrupts:(unsigned int)bufferSize {
    unsigned encoding;
    unsigned channels;
    unsigned rate;
    unsigned bits;
    int startResult;
    BOOL ok;
    if (isRead || _stateLock == nil)
        return NO;
    [_stateLock lock];
    if (!_ready || _stopping || _quarantined || gHDA == NULL || !gHDA->initialized ||
        (_msiRequested && !_msiActive)) {
        IOLog("%s: rejecting playback while interrupt delivery is unavailable\n", DRV_TITLE);
        [_stateLock unlock];
        return NO;
    }
    encoding = [self dataEncoding];
    channels = [self channelCount];
    rate = [self sampleRate];
    bits = encoding == NX_SoundStreamDataEncoding_Linear16 ? 16U : 0U;
    if (bits == 0 || channels < 1 || channels > 2 || !hdaRateIsKnown(rate)) {
        IOLog("%s: rejecting playback encoding %s(%u), channels %u, rate %u\n",
              DRV_TITLE, encodingName(encoding), encoding, channels, rate);
        [_stateLock unlock];
        return NO;
    }
    if (!hdaBitsAreSupported(gHDA, bits))
        HDA_VLOG(("%s: trying unadvertised PCM width %u\n", DRV_TITLE, bits));
    if (!hdaRateIsSupported(gHDA, rate)) {
        IOLog("%s: rejecting unverified sample rate %u\n", DRV_TITLE, rate);
        [_stateLock unlock];
        return NO;
    }
    hdaSetOutputInterrupts(gHDA, _msiRequested && _msiActive);
    startResult = hdaStartOutput(gHDA, (unsigned)buffer, gHDA->dmaBufferSize,
                        bufferSize, rate, bits, channels, [self isOutputMuted],
                        [self outputAttenuationLeft],
                        [self outputAttenuationRight],
                        [[self _outputChannel] enqueueCount]);
    ok = startResult == 0;
    if (!ok)
        IOLog("%s: failed to start output stream\n", DRV_TITLE);
    _lastServiceEndTick = hdaWallClock(gHDA);
    _lastServiceTailTicks = 0;
    _lastRefillTicks = 0;
    [_stateLock unlock];
    if (!ok && startResult != HDA_START_CONFIG_REJECTED)
        [self _containPlayback:"stream start/reset failed"];
    /* VirtualBox recreates its host mixer at RUN and loses the volume set
     * before RUN. Reapply after startup as well; physical hardware already
     * had the requested mute/attenuation before its first DMA fetch. */
    if (ok) [self updateOutputSettings];
    return ok;
}

- (void)stopDMAForChannel:(unsigned)localChannel read:(BOOL)isRead {
    BOOL stopped;
    if (isRead || !_stateLock) return;
    [_stateLock lock];
    stopped = !gHDA || hdaStopOutput(gHDA);
    if (gHDA) gHDA->outputInterrupt = NO;
    _completionTimestamp = 0;
    if (!stopped) { _quarantined = YES; _stopping = YES; _msiUnsafeToFree = YES; }
    [_stateLock unlock];
}

- (void)interruptOccurredForInput:(BOOL *)input forOutput:(BOOL *)output {
    *input = NO; *output = NO;
    [_stateLock lock];
    if (!_stopping && gHDA && gHDA->outputInterrupt) {
        gHDA->outputInterrupt = NO;
        *output = YES;
    }
    [_stateLock unlock];
}

/* OPENSTEP IOAudio's setter copies its legacy ISR's global timestamp,
 * ignoring the argument (kernel method 0x001b64a8 in the reference image).
 * MSI and polling never enter that ISR. Keep both accessors local instead. */
- (void)_setLastInterruptTimeStamp:(ns_time_t)unused {
    if (gHDA && gHDA->running) IOGetTimestamp(&_completionTimestamp);
    else _completionTimestamp = 0;
}
- (ns_time_t)_lastInterruptTimeStamp { return _completionTimestamp; }

/* The queue and all completion calls belong to IOAudio's one service thread.
 * The lock protects hardware/status access, never a superclass callback. */
- (int)_samplePlayback:(unsigned *)periods {
    int result;
    [_stateLock lock];
    if (_stopping || !gHDA || !gHDA->running) result = -1;
    else {
        result = hdaOutputPeriods(gHDA, periods);
        if (result && *periods > _maxPeriodBatch) _maxPeriodBatch = *periods;
    }
    [_stateLock unlock];
    return result;
}

- (unsigned)_queuedOutputPeriods {
    id channel = [self _outputChannel];
    unsigned queued = [channel enqueueCount];
    [_stateLock lock];
    _lastQueueDepth = queued;
    [_stateLock unlock];
    return queued <= [channel dmaCount] ? queued : 0;
}

- (void)_completeOutputPeriod {
    unsigned tick, elapsed, queuedBefore, queuedAfter, generation;
    id channel = [self _outputChannel];
    queuedBefore = [channel enqueueCount];
    [_stateLock lock];
    gHDA->outputInterrupt = YES;
    generation = gHDA->streamGeneration;
    tick = hdaWallClock(gHDA);
    [_stateLock unlock];
    /* IOAudio may reenter stopDMAForChannel:read:. */
    [super _interruptOccurred];
    queuedAfter = [channel enqueueCount];
    [_stateLock lock];
    /* IOAudio retires one descriptor, then attempts one enqueue at its tail.
     * Convert that newly enqueued slot, which is ahead of the retired slot.
     * A reentrant stop/start already rebuilt and converted the new queue. */
    if (gHDA->running && generation == gHDA->streamGeneration &&
        queuedBefore && queuedAfter == queuedBefore)
        hdaRefillConvertedOutput(gHDA);
    _completedPeriods++;
    if (!_msiRequested) _pollCompletions++;
    elapsed = hdaWallClock(gHDA) - tick;
    if (elapsed > _maxRefillTicks) _maxRefillTicks = elapsed;
    [_stateLock unlock];
}

- (int)_resynchronizeOutput {
    id channel = [self _outputChannel];
    int ok;
    [_stateLock lock];
    ok = !_stopping && hdaStopOutput(gHDA);
    if (ok) _queueResynchronizations++;
    [_stateLock unlock];
    if (!ok) return 0;
    /* Stop first. Retire/discard the old software queue and reset its physical
     * ordering using IOAudio's own method, not private structure writes.
     * Its pending-data message starts remaining regions from a fresh queue.
     * A short silence/drop is preferable to endlessly replaying stale PCM. */
    [super _stopDMAForChannel:channel];
    [_stateLock lock];
    ok = !_stopping;
    _completionTimestamp = 0;
    [_stateLock unlock];
    if (ok) [self _dataPendingForChannel:channel];
    return ok;
}

- (int)_servicePlaybackPass {
    IntelHDAInterruptResult service;
    unsigned entryTick, lockedTick, sampledTick, refillTick;
    int ok, refillResult;
    entryTick = hdaWallClock(gHDA);
    [_stateLock lock];
    if (_stopping || !_ready || !gHDA) { [_stateLock unlock]; return 0; }
    lockedTick = hdaWallClock(gHDA);
    bzero(&service, sizeof(service));
    (void)hdaServiceOutput(gHDA, &service);
    if (_msiTestFault == HDA_MSI_TEST_STREAM_ERROR)
        service.errors |= HDA_INTERRUPT_STREAM_DESE;
    ok = !service.errors && !service.exhausted;
    sampledTick = hdaWallClock(gHDA);
    gHDA->outputInterrupt = NO;
    if (!ok) {
        _streamErrors++;
        IOLog("%s: service latency ticks: outside %u lock %u status %u previous tail %u refill %u (24 MHz)\n",
              DRV_TITLE, entryTick - _lastServiceEndTick,
              lockedTick - entryTick, sampledTick - lockedTick,
              _lastServiceTailTicks, _lastRefillTicks);
    }
    [_stateLock unlock];
    if (!ok) return 0;
    refillTick = hdaWallClock(gHDA);
    refillResult = IntelHDARefillRun(self, &refillOps);
    if (refillResult == HDA_REFILL_RESYNC && ![self _resynchronizeOutput])
        return 0;
    [_stateLock lock];
    _lastRefillTicks = hdaWallClock(gHDA) - refillTick;
    if (!_stopping) hdaSetOutputInterrupts(gHDA, _msiRequested && _msiActive);
    ok = !_stopping;
    _lastServiceEndTick = hdaWallClock(gHDA);
    _lastServiceTailTicks = _lastServiceEndTick - gHDA->progress.tick;
    [_stateLock unlock];
    return ok;
}

- (int)_outputReady {
    int ready;
    [_stateLock lock];
    ready = !_stopping && gHDA && hdaOutputStatusPending(gHDA);
    [_stateLock unlock];
    return ready;
}

- (int)_finishMSIPass:(int)acknowledge pending:(unsigned *)pending {
    unsigned flags;
    IOReturn result;
    [_stateLock lock];
    if (_stopping || !_msiActive || !_msiAllocated) {
        [_stateLock unlock]; return 0;
    }
    if (_msiTestFault == HDA_MSI_TEST_GATE_FAILURE) {
        _msiGateResult = IO_R_NOT_READY;
        [_stateLock unlock];
        return 0;
    }
    /* Raw IF exclusion encloses only the provider gate call. */
    flags = saveRawInterrupts();
    if (acknowledge)
        result = [_msiProvider acknowledgeMSIVector:_msiMessage.vector owner:self];
    else
        result = [_msiProvider consumeAcknowledgedMSIVector:_msiMessage.vector
                                  owner:self pending:pending];
    restoreRawInterrupts(flags);
    _msiGateResult = result;
    [_stateLock unlock];
    return result == IO_R_SUCCESS;
}

- (void)_containPlayback:(const char *)reason {
    [_stateLock lock];
    _quarantined = YES; _stopping = YES; _ready = NO; _msiActive = NO;
    if (gHDA) {
        hdaQuiesceInterrupts(gHDA);
        if (!hdaStopOutput(gHDA)) _msiUnsafeToFree = YES;
        gHDA->outputInterrupt = NO;
    }
    [_stateLock unlock];
    IOLog("%s: playback stopped: %s; reboot required\n", DRV_TITLE, reason);
    /* Clear IOAudio's active state and descriptors on its own service thread.
     * Its callback can reenter stopDMAForChannel, so remain outside the lock. */
    [super _stopDMAForChannel:[self _outputChannel]];
    if (![self _disableAndReleasePCIMSI]) _msiUnsafeToFree = YES;
}

- (void)_interruptOccurred {
    int result;
    if (!_msiRequested) (void)atomicExchangeUnsigned(&_pollMessagePending, 0);
    if (_initializing || !_ready || _stopping) { _ignoredMessages++; return; }
    if (_msiRequested) {
        if (!_msiActive || !_msiAllocated) { _ignoredMessages++; return; }
        _msiNotifications++;
        if (_msiTestFault == HDA_MSI_TEST_DROP_NOTIFICATION) return;
        if (_msiTestFault == HDA_MSI_TEST_DELAY_SERVICE) IOSleep(150);
        result = IntelHDAMSIRunEpoch(self, &epochOps, &_msiEpochStats);
        if (result != HDA_MSI_EPOCH_OK) {
            _msiEpochFailures++;
            if (result == HDA_MSI_EPOCH_GATE_FAILED) _msiUnsafeToFree = YES;
            [self _containPlayback:"acknowledged service epoch failed"];
        }
    } else {
        _pollTicks++;
        if (![self _servicePlaybackPass]) [self _containPlayback:"polling service failed"];
    }
}

- (void)timeoutOccurred {
    /* Stock IOAudio invokes this on its I/O thread. Stop, never poll or
     * manufacture a completion when interrupt delivery has disappeared. */
    if (_ready && !_stopping && gHDA && gHDA->running)
        [self _containPlayback:"IOAudio interrupt timeout"];
}

- (BOOL)_readPCIConfigImage:(unsigned *)image {
    unsigned offset;
    unsigned long value;
    if (image == 0)
        return NO;
    for (offset = 0; offset < 256U; offset += 4U) {
        if ([self getPCIConfigData:&value atRegister:(unsigned char)offset] !=
            IO_R_SUCCESS)
            return NO;
        image[offset / 4U] = (unsigned)value;
    }
    return YES;
}

- (BOOL)_auditPCIInterruptCapabilities {
    unsigned image[HDA_PCI_CONFIG_DWORDS];
    int decoded;
    if (![self _readPCIConfigImage:image])
        return NO;
    decoded = IntelHDAPCIDecodeCapabilities(image,
                                             &_pciInterruptCapabilities);
    if (decoded == HDA_PCI_CAPS_NO_LIST) {
        IOLog("%s: PCI Status reports no capability list\n", DRV_TITLE);
        return YES;
    }
    if (decoded != HDA_PCI_CAPS_OK) {
        IOLog("%s: malformed PCI capability list (%d)\n", DRV_TITLE, decoded);
        return NO;
    }
    if (_pciInterruptCapabilities.msiFound)
        IOLog("%s: MSI capability 0x%02x control 0x%04x\n", DRV_TITLE,
              _pciInterruptCapabilities.msiOffset,
              _pciInterruptCapabilities.msiControl);
    if (_pciInterruptCapabilities.msixFound)
        IOLog("%s: MSI-X capability 0x%02x control 0x%04x\n", DRV_TITLE,
              _pciInterruptCapabilities.msixOffset,
              _pciInterruptCapabilities.msixControl);
    return YES;
}

- (BOOL)_setPCIInterruptDisabled {
    unsigned long value;
    unsigned desired;
    if ([self getPCIConfigData:&value atRegister:0x04] != IO_R_SUCCESS)
        return NO;
    desired = IntelHDAPCICommandWithINTxDisabled((unsigned)value) |
              PCI_COMMAND_MEMORY_ENABLE | PCI_COMMAND_MASTER_ENABLE;
    if ([self setPCIConfigData:desired atRegister:0x04] != IO_R_SUCCESS ||
        [self getPCIConfigData:&value atRegister:0x04] != IO_R_SUCCESS)
        return NO;
    return ((unsigned)value & 0xffffU) == (desired & 0xffffU) &&
           IntelHDAPCICommandHasINTxDisabled((unsigned)value) &&
           (((unsigned)value & (PCI_COMMAND_MEMORY_ENABLE |
                                PCI_COMMAND_MASTER_ENABLE)) ==
            (PCI_COMMAND_MEMORY_ENABLE | PCI_COMMAND_MASTER_ENABLE));
}

- (BOOL)_disableMSI {
    IntelHDAMSILayout layout;
    unsigned long value;
    unsigned desired;
    _msiActive = NO;
    if (gHDA != NULL && gHDA->regs != NULL) {
        hdaQuiesceInterrupts(gHDA);
        hdaAcknowledgePending(gHDA);
    }
    if (_pciInterruptCapabilities.msixFound) {
        if ([self getPCIConfigData:&value atRegister:(unsigned char)_pciInterruptCapabilities.msixOffset] != IO_R_SUCCESS)
            goto failed;
        desired = IntelHDAMSIXDisabledControlDword((unsigned)value);
        if ([self setPCIConfigData:desired atRegister:(unsigned char)_pciInterruptCapabilities.msixOffset] != IO_R_SUCCESS ||
            [self getPCIConfigData:&value atRegister:(unsigned char)_pciInterruptCapabilities.msixOffset] != IO_R_SUCCESS ||
            (unsigned)value != desired ||
            !IntelHDAMSIXControlIsDisabled((unsigned)value))
            goto failed;
    }
    if (_pciInterruptCapabilities.msiFound) {
        if (!IntelHDAMSIBuildLayout(_pciInterruptCapabilities.msiOffset,
                                    _pciInterruptCapabilities.msiControl,
                                    &layout))
            goto failed;
        if (layout.hasPerVectorMask) {
            if ([self getPCIConfigData:&value atRegister:(unsigned char)layout.maskOffset] != IO_R_SUCCESS)
                goto failed;
            desired = IntelHDAMSIPerVectorMaskDword((unsigned)value, 1);
            if ([self setPCIConfigData:desired atRegister:(unsigned char)layout.maskOffset] != IO_R_SUCCESS ||
                [self getPCIConfigData:&value atRegister:(unsigned char)layout.maskOffset] != IO_R_SUCCESS ||
                (unsigned)value != desired || (((unsigned)value & 1U) == 0))
                goto failed;
        }
        if ([self getPCIConfigData:&value atRegister:(unsigned char)layout.capabilityOffset] != IO_R_SUCCESS)
            goto failed;
        desired = IntelHDAMSIControlDword((unsigned)value, 0);
        if ([self setPCIConfigData:desired atRegister:(unsigned char)layout.capabilityOffset] != IO_R_SUCCESS ||
            [self getPCIConfigData:&value atRegister:(unsigned char)layout.capabilityOffset] != IO_R_SUCCESS ||
            (unsigned)value != desired ||
            !IntelHDAMSIControlIsState((unsigned)value, 0))
            goto failed;
    }
    if (![self _setPCIInterruptDisabled])
        goto failed;
    if (_msiAllocated && _msiTestFault == HDA_MSI_TEST_DISABLE_READBACK) {
        IOLog("%s: injected MSI-disable readback failure\n", DRV_TITLE);
        goto failed;
    }
    _msiEnabled = NO;
    return YES;
failed:
    _msiDisableFailures++;
    IOLog("%s: cannot prove PCI MSI/MSI-X disabled\n", DRV_TITLE);
    return NO;
}

- (IOReturn)_allocatePCIMSI {
    IOReturn result;
    unsigned char version[16];
    unsigned count = sizeof(version);
    if (_msiAllocated || _msiEverAllocated) return IO_R_NOT_READY;
    if (_msiTestFault == HDA_MSI_TEST_PROVIDER_LOOKUP) return IO_R_NOT_READY;
    result = IOGetObjectForDeviceName("PCIMSI0", &_msiProvider);
    if (result != IO_R_SUCCESS || !_msiProvider) return IO_R_NOT_READY;
    bzero(version, sizeof(version));
    if (_msiTestFault == HDA_MSI_TEST_PROVIDER_VERSION ||
        [_msiProvider getCharValues:version forParameter:"PCIMSIVersion" count:&count] != IO_R_SUCCESS ||
        count > sizeof(version) || version[15] || strcmp((char *)version, "0.32") ||
        PCIMSI_INTERFACE_VERSION != 5U ||
        [_msiProvider msiInterfaceVersion] != PCIMSI_INTERFACE_VERSION ||
        _msiTestFault == HDA_MSI_TEST_PROVIDER_INACTIVE ||
        ![_msiProvider isMSIServiceActive]) {
        _msiProvider = nil; return IO_R_NOT_READY;
    }
    bzero(&_msiMessage, sizeof(_msiMessage));
    /* OPENSTEP IOAudio's private receive loop recognizes only this ID.
     * API v5 accepts it. One allocation per owner/port lifetime; both remain
     * pinned after release. Never reallocate onto this untagged queue. */
    result = [_msiProvider allocateAcknowledgedMSIVectorFor:self
                  interruptPort:[self interruptPort]
                      messageID:IO_DEVICE_INTERRUPT_MSG message:&_msiMessage];
    if (result != IO_R_SUCCESS) return result;
    _msiAllocated = YES; _msiEverAllocated = YES;
    if (_msiTestFault == HDA_MSI_TEST_MALFORMED_MESSAGE) _msiMessage.data ^= 1U;
    if (!IntelHDAPCIMSIMessageIsValid(_msiMessage.vector, _msiMessage.addressLow,
        _msiMessage.addressHigh, _msiMessage.data, PCIMSI_VECTOR_FIRST,
        PCIMSI_VECTOR_LAST, PCIMSI_MSI_ADDRESS_BASE)) return IO_R_INVALID_ARG;
    _msiPromptRequested = YES;
    _msiPromptResult = _msiTestFault == HDA_MSI_TEST_PROMPT_UNAVAILABLE ?
        IO_R_UNSUPPORTED : [_msiProvider enableMSIPromptRetry:_msiMessage.vector owner:self];
    if (!IntelHDAMSIPromptResultIsSafe([_msiProvider isMSIServiceActive],
        _msiPromptResult == IO_R_SUCCESS,
        _msiPromptResult == IO_R_BUSY || _msiPromptResult == IO_R_RESOURCE ||
        _msiPromptResult == IO_R_UNSUPPORTED)) {
        _msiUnsafeToFree = YES; return IO_R_NOT_READY;
    }
    _msiPromptActive = _msiPromptResult == IO_R_SUCCESS;
    IOLog("%s: PCIMSI 0.32 API 5 vector %02x; prompt requested=1 active=%u result=%d\n",
          DRV_TITLE, _msiMessage.vector, _msiPromptActive, _msiPromptResult);
    return IO_R_SUCCESS;
}

- (BOOL)_releasePCIMSI {
    IOReturn result;
    if (!_msiAllocated)
        return YES;
    if (_msiProvider == nil || _msiUnsafeToFree)
        return NO;
    if (_msiTestFault == HDA_MSI_TEST_RELEASE_FAILURE) {
        _msiReleaseFailures++;
        IOLog("%s: injected PCIMSI release failure; allocation retained\n", DRV_TITLE);
        return NO;
    }
    result = [_msiProvider releaseMSIVector:_msiMessage.vector owner:self];
    if (result != IO_R_SUCCESS) {
        _msiReleaseFailures++;
        IOLog("%s: PCIMSI release failed (%d); allocation retained\n", DRV_TITLE, result);
        return NO;
    }
    _msiAllocated = NO;
    _msiPromptActive = NO;
    _msiProvider = nil;
    IOLog("%s: released PCIMSI vector 0x%02x after MSI-disable readback\n",
          DRV_TITLE, _msiMessage.vector);
    return YES;
}

- (BOOL)_disableAndReleasePCIMSI {
    BOOL disabled;
    [_stateLock lock];
    disabled = [self _disableMSI];
    [_stateLock unlock];
    if (!disabled)
        return NO;
    if (_msiAllocated && ![self _releasePCIMSI])
        return NO;
    return YES;
}

- (BOOL)_activateMSI {
    unsigned image[HDA_PCI_CONFIG_DWORDS];
    unsigned long value;
    unsigned desired;
    BOOL ok;
    ok = NO;
    [_stateLock lock];
    hdaQuiesceInterrupts(gHDA);
    hdaAcknowledgePending(gHDA);
    if (![self _disableMSI] || [self _allocatePCIMSI] != IO_R_SUCCESS)
        goto done;
    if (_msiLayout.hasPerVectorMask) {
        if ([self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS)
            goto done;
        desired = IntelHDAMSIPerVectorMaskDword((unsigned)value, 1);
        if ([self setPCIConfigData:desired atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS ||
            [self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS ||
            (unsigned)value != desired || (((unsigned)value & 1U) == 0))
            goto done;
    }
    if ([self setPCIConfigData:_msiMessage.addressLow atRegister:(unsigned char)_msiLayout.addressLowOffset] != IO_R_SUCCESS)
        goto done;
    if (_msiLayout.is64Bit &&
        [self setPCIConfigData:_msiMessage.addressHigh atRegister:(unsigned char)_msiLayout.addressHighOffset] != IO_R_SUCCESS)
        goto done;
    if ([self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.dataOffset] != IO_R_SUCCESS)
        goto done;
    desired = IntelHDAMSIMessageDataDword((unsigned)value, _msiMessage.data);
    if ([self setPCIConfigData:desired atRegister:(unsigned char)_msiLayout.dataOffset] != IO_R_SUCCESS ||
        ![self _readPCIConfigImage:image] ||
        !IntelHDAMSIMessageMatches(image, &_msiLayout, _msiMessage.addressLow,
                                   _msiMessage.addressHigh, _msiMessage.data) ||
        image[_msiLayout.dataOffset / 4U] != desired)
        goto done;
    if (_msiTestFault == HDA_MSI_TEST_PROGRAM_READBACK) {
        IOLog("%s: injected MSI programming-readback failure\n", DRV_TITLE);
        goto done;
    }
    if ([self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.capabilityOffset] != IO_R_SUCCESS)
        goto done;
    desired = IntelHDAMSIControlDword((unsigned)value, 1);
    if ([self setPCIConfigData:desired atRegister:(unsigned char)_msiLayout.capabilityOffset] != IO_R_SUCCESS ||
        [self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.capabilityOffset] != IO_R_SUCCESS ||
        (unsigned)value != desired ||
        !IntelHDAMSIControlIsState((unsigned)value, 1))
        goto done;
    _msiEnabled = YES;
    if (![self _setPCIInterruptDisabled])
        goto done;
    if (_pciInterruptCapabilities.msixFound &&
        ([self getPCIConfigData:&value atRegister:(unsigned char)_pciInterruptCapabilities.msixOffset] != IO_R_SUCCESS ||
         !IntelHDAMSIXControlIsDisabled((unsigned)value)))
        goto done;
    if (_msiLayout.hasPerVectorMask) {
        if ([self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS)
            goto done;
        desired = IntelHDAMSIPerVectorMaskDword((unsigned)value, 0);
        if ([self setPCIConfigData:desired atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS ||
            [self getPCIConfigData:&value atRegister:(unsigned char)_msiLayout.maskOffset] != IO_R_SUCCESS ||
            (unsigned)value != desired || (((unsigned)value & 1U) != 0))
            goto done;
    }
    hdaSetOutputInterrupts(gHDA, YES);
    if (_msiTestFault == HDA_MSI_TEST_DISABLE_READBACK ||
        _msiTestFault == HDA_MSI_TEST_RELEASE_FAILURE) goto done;
    _msiActive = YES;
    ok = YES;
    IOLog("%s: MSI enabled at capability 0x%02x with MME=0; PCI command interrupt-disable verified\n",
          DRV_TITLE, _msiLayout.capabilityOffset);
done:
    if (!ok) { _msiActive = NO; hdaQuiesceInterrupts(gHDA); }
    [_stateLock unlock];
    /* Initialization cleanup releases outside the lock in free. */
    return ok;
}

- (void)runInterruptWorker {
    msg_header_t message;
    while (_workerRunning) {
        if (!_stopping && gHDA && gHDA->running &&
            !atomicExchangeUnsigned(&_pollMessagePending, 1)) {
            message = hdaInterruptMessageTemplate;
            message.msg_remote_port = _interruptPortKern;
            if (msg_send_from_kernel(&message, SEND_TIMEOUT, 0) != SEND_SUCCESS)
                (void)atomicExchangeUnsigned(&_pollMessagePending, 0);
        }
        IOSleep(HDA_WORKER_MS);
    }
    _workerExited = 1;
    IOExitThread();
}
static void hdaInterruptWorker(void *argument) {
    [(IntelHDADriver *)argument runInterruptWorker];
}

- (IOReturn)getIntValues:(unsigned *)values
            forParameter:(IOParameterName)parameterName count:(unsigned *)count {
    unsigned long pciValue;
    if (strcmp(parameterName, INTEL_HDA_STATS_PARAMETER))
        return [super getIntValues:values forParameter:parameterName count:count];
    if (*count < INTEL_HDA_STATS_COUNT) { *count = INTEL_HDA_STATS_COUNT; return IO_R_INVALID_ARG; }
    [_stateLock lock];
    values[INTEL_HDA_STAT_SCHEMA] = INTEL_HDA_STATS_SCHEMA_VERSION;
    values[INTEL_HDA_STAT_MODE] = _msiRequested ? INTEL_HDA_MODE_MSI : INTEL_HDA_MODE_POLLING;
    values[INTEL_HDA_STAT_RUNNING] = gHDA && gHDA->running;
    values[INTEL_HDA_STAT_FIRMWARE_INTERRUPT_LINE] = gHDA ? gHDA->firmwareInterruptLine : 255U;
    values[INTEL_HDA_STAT_MSI_VECTOR] = _msiMessage.vector;
    values[INTEL_HDA_STAT_MSI_CAP] = _pciInterruptCapabilities.msiOffset;
    values[INTEL_HDA_STAT_MSIX_CAP] = _pciInterruptCapabilities.msixOffset;
    values[INTEL_HDA_STAT_MSI_ALLOCATED] = _msiAllocated;
    values[INTEL_HDA_STAT_MSI_ENABLED] = _msiEnabled;
    values[INTEL_HDA_STAT_MSI_ACTIVE] = _msiActive;
    values[INTEL_HDA_STAT_NOTIFICATIONS] = _msiNotifications;
    values[INTEL_HDA_STAT_SERVICE_PASSES] = _msiEpochStats.passes;
    values[INTEL_HDA_STAT_CONSUMES] = _msiEpochStats.consumes;
    values[INTEL_HDA_STAT_ACKNOWLEDGMENTS] = _msiEpochStats.acknowledgments;
    values[INTEL_HDA_STAT_CONSUMED_MESSAGES] = _msiEpochStats.consumedMessages;
    values[INTEL_HDA_STAT_EPOCH_FAILURES] = _msiEpochFailures;
    values[INTEL_HDA_STAT_GATE_RESULT] = (unsigned)_msiGateResult;
    values[INTEL_HDA_STAT_COMPLETED_PERIODS] = _completedPeriods;
    values[INTEL_HDA_STAT_STREAM_ERRORS] = _streamErrors;
    values[INTEL_HDA_STAT_IGNORED_MESSAGES] = _ignoredMessages;
    values[INTEL_HDA_STAT_QUARANTINED] = _quarantined;
    values[INTEL_HDA_STAT_POLL_TICKS] = _pollTicks;
    values[INTEL_HDA_STAT_POLL_COMPLETIONS] = _pollCompletions;
    values[INTEL_HDA_STAT_PROMPT_REQUESTED] = _msiPromptRequested;
    values[INTEL_HDA_STAT_PROMPT_ACTIVE] = _msiPromptActive;
    values[INTEL_HDA_STAT_PROMPT_RESULT] = (unsigned)_msiPromptResult;
    values[INTEL_HDA_STAT_REBOOT_REQUIRED] = _msiUnsafeToFree || _stopping;
    values[INTEL_HDA_STAT_DISABLE_FAILURES] = _msiDisableFailures;
    values[INTEL_HDA_STAT_RELEASE_FAILURES] = _msiReleaseFailures;
    values[INTEL_HDA_STAT_PCI_ID] = gHDA ? ((unsigned)gHDA->device << 16) | gHDA->vendor : 0;
    values[INTEL_HDA_STAT_CODEC_ID] = gHDA ? gHDA->codecVendor : 0;
    values[INTEL_HDA_STAT_PIN] = gHDA ? gHDA->pin : 0;
    values[INTEL_HDA_STAT_DAC] = gHDA ? gHDA->dac : 0;
    values[INTEL_HDA_STAT_DMA_BYTES] = gHDA ? gHDA->dmaBufferSize : 0;
    values[INTEL_HDA_STAT_PERIOD_BYTES] = gHDA ? gHDA->periodBytes : 0;
    values[INTEL_HDA_STAT_QUEUE_RESYNCHRONIZATIONS] = _queueResynchronizations;
    values[INTEL_HDA_STAT_MAX_PERIOD_BATCH] = _maxPeriodBatch;
    values[INTEL_HDA_STAT_MAX_REFILL_TICKS] = _maxRefillTicks;
    values[INTEL_HDA_STAT_LAST_QUEUE_DEPTH] = _lastQueueDepth;
    values[INTEL_HDA_STAT_CODEC_SETUP_FAILURES] = gHDA ? gHDA->codecSetupFailures : 0;
    values[INTEL_HDA_STAT_STREAM_FORMAT] = gHDA ? gHDA->streamFormat : 0;
    values[INTEL_HDA_STAT_VERIFIED_RATES] = gHDA ? gHDA->verifiedRateMask : 0;
    values[INTEL_HDA_STAT_SOURCE_RATE] = gHDA ? gHDA->sourceRate : 0;
    values[INTEL_HDA_STAT_HARDWARE_RATE] = gHDA ? gHDA->hardwareRate : 0;
    values[INTEL_HDA_STAT_HARDWARE_DMA_BYTES] = gHDA ? gHDA->hardwareBufferBytes : 0;
    values[INTEL_HDA_STAT_INTCTL] = hdaInterruptControl(gHDA);
    values[INTEL_HDA_STAT_PCI_COMMAND] =
        [self getPCIConfigData:&pciValue atRegister:4] == IO_R_SUCCESS ? pciValue & 0xffffU : ~0U;
    values[INTEL_HDA_STAT_MSI_CONTROL] = 0;
    if (_pciInterruptCapabilities.msiFound)
        values[INTEL_HDA_STAT_MSI_CONTROL] =
            [self getPCIConfigData:&pciValue atRegister:(unsigned char)_pciInterruptCapabilities.msiOffset] == IO_R_SUCCESS ? pciValue >> 16 : ~0U;
    values[INTEL_HDA_STAT_MSIX_CONTROL] = 0;
    if (_pciInterruptCapabilities.msixFound)
        values[INTEL_HDA_STAT_MSIX_CONTROL] =
            [self getPCIConfigData:&pciValue atRegister:(unsigned char)_pciInterruptCapabilities.msixOffset] == IO_R_SUCCESS ? pciValue >> 16 : ~0U;
    [_stateLock unlock];
    *count = INTEL_HDA_STATS_COUNT;
    return IO_R_SUCCESS;
}

- (void)updateSampleRate {
    if (gHDA != NULL && gHDA->initialized)
        [self updateOutputSettings];
}
- (BOOL)acceptsContinuousSamplingRates { return NO; }
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate {
    int rates[16];
    unsigned int count;
    hdaGetSupportedRates(gHDA, rates, &count);
    *lowRate = rates[0];
    *highRate = rates[count - 1];
}
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates {
    hdaGetSupportedRates(gHDA, rates, numRates);
}
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings {
    encodings[0] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = 1;
}
- (unsigned int)channelCountLimit { return 2; }
- updateOutputSettings {
    [_stateLock lock];
    if (!_stopping && gHDA != NULL && gHDA->initialized)
        hdaSetOutputVolume(gHDA, [self isOutputMuted],
                           [self outputAttenuationLeft],
                           [self outputAttenuationRight]);
    [_stateLock unlock];
    return self;
}
- (void)updateOutputMute { [self updateOutputSettings]; }
- (void)updateOutputAttenuationLeft { [self updateOutputSettings]; }
- (void)updateOutputAttenuationRight { [self updateOutputSettings]; }
- (void)updateInputGainLeft {}
- (void)updateInputGainRight {}

@end
