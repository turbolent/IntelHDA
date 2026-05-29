#import <driverkit/generalFuncs.h>
#import <driverkit/i386/IOPCIDeviceDescription.h>
#import <driverkit/i386/IOPCIDirectDevice.h>
#import <driverkit/i386/PCI.h>
#import <driverkit/i386/directDevice.h>
#import <driverkit/interruptMsg.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

#import "IntelHDAController.h"
#import "IntelHDADriver.h"

#define PCI_COMMAND_IO_ENABLE       0x0001
#define PCI_COMMAND_MEMORY_ENABLE   0x0002
#define PCI_COMMAND_MASTER_ENABLE   0x0004
#define PCI_BASE_IO_BIT             0x00000001
#define PCI_BASE_MEMORY(addr)       ((addr) & 0xfffffff0)
#define HDA_MMIO_SIZE               0x4000
#define INTEL_VENDOR_ID             0x8086
#define INTEL_ICH6_HDA_DEVICE_ID    0x2668
#define INTEL_6SERIES_HDA_DEVICE_ID 0x1c20
#define INTEL_SCH_HDA_DEVC          0x78
#define INTEL_SCH_HDA_DEVC_NOSNOOP  0x00000800

static const char codecDeviceName[] = "IntelHDA";
static const char codecDeviceKind[] = "Audio";

static struct hda_state *gHDA = NULL;
static IOInterruptHandler oldHandler = NULL;
static BOOL attachedController = NO;

static const char *encodingName(unsigned int encoding) {
    switch (encoding) {
    case NX_SoundStreamDataEncoding_Linear8:
        return "linear8";
    case NX_SoundStreamDataEncoding_Linear16:
        return "linear16";
    case NX_SoundStreamDataEncoding_Mulaw8:
        return "mulaw8";
    case NX_SoundStreamDataEncoding_Alaw8:
        return "alaw8";
    default:
        return "unknown";
    }
}

static void enablePCHSnoop(id deviceDescription, unsigned short deviceID) {
    IOReturn irtn;
    unsigned long devc;
    unsigned long newDevc;
    unsigned long verifyDevc;

    if (deviceID != INTEL_6SERIES_HDA_DEVICE_ID)
        return;

    irtn = [IODirectDevice getPCIConfigData:&devc
                                 atRegister:INTEL_SCH_HDA_DEVC
                      withDeviceDescription:deviceDescription];
    if (irtn != IO_R_SUCCESS) {
        IOLog("%s: cannot read Intel PCH snoop control 0x%02x (%s)\n",
              DRV_TITLE, INTEL_SCH_HDA_DEVC,
              [IODirectDevice stringFromReturn:irtn]);
        return;
    }

    newDevc = devc & ~INTEL_SCH_HDA_DEVC_NOSNOOP;
    if (newDevc != devc) {
        irtn = [IODirectDevice setPCIConfigData:newDevc
                                     atRegister:INTEL_SCH_HDA_DEVC
                          withDeviceDescription:deviceDescription];
        if (irtn != IO_R_SUCCESS) {
            IOLog("%s: cannot enable Intel PCH snoop DEVC 0x%08x (%s)\n",
                  DRV_TITLE, (unsigned int)devc,
                  [IODirectDevice stringFromReturn:irtn]);
            return;
        }
    }

    verifyDevc = newDevc;
    irtn = [IODirectDevice getPCIConfigData:&verifyDevc
                                 atRegister:INTEL_SCH_HDA_DEVC
                      withDeviceDescription:deviceDescription];
    if (irtn != IO_R_SUCCESS)
        verifyDevc = newDevc;

    IOLog("%s: Intel PCH snoop %s DEVC 0x%08x -> 0x%08x\n", DRV_TITLE,
          (verifyDevc & INTEL_SCH_HDA_DEVC_NOSNOOP) ? "disabled" : "enabled",
          (unsigned int)devc, (unsigned int)verifyDevc);
}

@implementation IntelHDADriver

+ (BOOL)probe:deviceDescription {
    IntelHDADriver *dev;

    if (attachedController) {
        IOLog("%s: refusing additional controller\n", DRV_TITLE);
        return NO;
    }

    dev = [self alloc];
    if (dev == nil)
        return NO;

    return ([dev initFromDeviceDescription:deviceDescription] != nil);
}

- initFromDeviceDescription:deviceDescription {
    IOReturn irtn;
    IOPCIConfigSpace configSpace;
    IORange memRange;
    unsigned long regLong;
    unsigned int classCode;
    unsigned int bar0;

    bzero(&configSpace, sizeof(configSpace));
    irtn = [IODirectDevice getPCIConfigSpace:&configSpace
                       withDeviceDescription:deviceDescription];
    if (irtn) {
        IOLog("%s: cannot read PCI config space (%s)\n", DRV_TITLE,
              [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    classCode = configSpace.ClassCode;
    if (!((configSpace.VendorID == INTEL_VENDOR_ID &&
           (configSpace.DeviceID == INTEL_ICH6_HDA_DEVICE_ID ||
            configSpace.DeviceID == INTEL_6SERIES_HDA_DEVICE_ID)) ||
          classCode == 0x040300)) {
        IOLog("%s: unsupported PCI device VID 0x%04x DID 0x%04x class 0x%06x\n",
              DRV_TITLE, configSpace.VendorID, configSpace.DeviceID, classCode);
        return nil;
    }

    bar0 = configSpace.BaseAddress[0];
    if ((bar0 & PCI_BASE_IO_BIT) || PCI_BASE_MEMORY(bar0) == 0) {
        IOLog("%s: invalid HDA MMIO BAR0 0x%08x\n", DRV_TITLE, bar0);
        return nil;
    }

    gHDA = IOMalloc(sizeof(*gHDA));
    if (gHDA == NULL) {
        IOLog("%s: cannot allocate driver state\n", DRV_TITLE);
        return nil;
    }
    bzero(gHDA, sizeof(*gHDA));
    gHDA->magic = 0x48444131;
    gHDA->vendor = configSpace.VendorID;
    gHDA->device = configSpace.DeviceID;
    gHDA->rev = configSpace.RevisionID;
    gHDA->subsystemVendor = configSpace.SubVendorID;
    gHDA->subsystemDevice = configSpace.SubDeviceID;
    gHDA->irq = configSpace.InterruptLine;
    gHDA->mmioPhys = PCI_BASE_MEMORY(bar0);
    gHDA->mmioSize = HDA_MMIO_SIZE;

    if (gHDA->irq == 0 || gHDA->irq == 0xff) {
        IOLog("%s: no usable IRQ in PCI config\n", DRV_TITLE);
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
        return nil;
    }

    IOLog("%s %s milestone %s: PCI VID 0x%04x DID 0x%04x SVID 0x%04x SID "
          "0x%04x rev 0x%02x class 0x%06x\n",
          DRV_TITLE, DRV_VERSION, DRV_MILESTONE, gHDA->vendor, gHDA->device,
          gHDA->subsystemVendor, gHDA->subsystemDevice, gHDA->rev, classCode);
    IOLog("%s: MMIO BAR0 0x%08x IRQ %d\n", DRV_TITLE, gHDA->mmioPhys,
          gHDA->irq);

    irtn = [deviceDescription setInterruptList:&(gHDA->irq) num:1];
    if (irtn) {
        IOLog("%s: cannot set IRQ %d (%s)\n", DRV_TITLE, gHDA->irq,
              [IODirectDevice stringFromReturn:irtn]);
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
        return nil;
    }

    memRange.start = gHDA->mmioPhys;
    memRange.size = gHDA->mmioSize;
    irtn = [deviceDescription setMemoryRangeList:&memRange num:1];
    if (irtn) {
        IOLog("%s: cannot set MMIO range 0x%x (%s)\n", DRV_TITLE,
              memRange.start, [IODirectDevice stringFromReturn:irtn]);
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
        return nil;
    }

    irtn = [IODirectDevice getPCIConfigData:&regLong
                                 atRegister:0x04
                      withDeviceDescription:deviceDescription];
    if (irtn == IO_R_SUCCESS) {
        regLong |= PCI_COMMAND_MEMORY_ENABLE | PCI_COMMAND_MASTER_ENABLE;
        (void)[IODirectDevice setPCIConfigData:regLong
                                    atRegister:0x04
                         withDeviceDescription:deviceDescription];
    }
    enablePCHSnoop(deviceDescription, configSpace.DeviceID);

    if (![super initFromDeviceDescription:deviceDescription]) {
        IOLog("%s: failed in IOAudio init\n", DRV_TITLE);
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
        return nil;
    }

    irtn = [self mapMemoryRange:0
                             to:(vm_address_t *)&gHDA->regs
                      findSpace:YES
                          cache:IO_CacheOff];
    if (irtn) {
        IOLog("%s: cannot map HDA MMIO (%s)\n", DRV_TITLE,
              [IODirectDevice stringFromReturn:irtn]);
        return nil;
    }

    if (hdaInitController(gHDA)) {
        IOLog("%s: controller initialization failed\n", DRV_TITLE);
        [self unmapMemoryRange:0 from:(vm_address_t)gHDA->regs];
        gHDA->regs = NULL;
        return nil;
    }

    attachedController = YES;
    return self;
}

- free {
    if (gHDA != NULL) {
        hdaShutdownController(gHDA);
        if (gHDA->regs != NULL)
            [self unmapMemoryRange:0 from:(vm_address_t)gHDA->regs];
        [self releaseInterrupt:0];
        IOFree(gHDA, sizeof(*gHDA));
        gHDA = NULL;
    }
    attachedController = NO;
    return [super free];
}

- (BOOL)reset {
    [self setName:codecDeviceName];
    [self setDeviceKind:codecDeviceKind];

    if (gHDA != NULL && gHDA->regs != NULL && !gHDA->initialized)
        return (hdaInitController(gHDA) == 0);

    return YES;
}

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                               length:(unsigned int)numBytes
                                 read:(BOOL)isRead
                       needsLowMemory:(BOOL)lowerMem
                            limitSize:(BOOL)limitSize {
    IOReturn irtn;
    unsigned int physAddr;

    if (isRead || gHDA == NULL)
        return NULL;

    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)*physicalAddress,
                                 &physAddr);
    if (irtn) {
        IOLog("%s: cannot get physical address for IOAudio buffer\n",
              DRV_TITLE);
        return NULL;
    }

    gHDA->dmaBufferPhys = physAddr;
    gHDA->dmaBufferVirt = *physicalAddress;
    gHDA->dmaBufferSize = numBytes;
    HDA_VLOG(("%s: IOAudio DMA buffer virt 0x%08x phys 0x%08x bytes %d\n",
              DRV_TITLE, *physicalAddress, physAddr, numBytes));
    return (IOEISADMABuffer)physAddr;
}

- (BOOL)startDMAForChannel:(unsigned int)localChannel
                       read:(BOOL)isRead
                     buffer:(IOEISADMABuffer)buffer
    bufferSizeForInterrupts:(unsigned int)bufferSize {
    unsigned int encoding;
    unsigned int channels;
    unsigned int rate;
    unsigned int bits;

    if (isRead) {
        IOLog("%s: rejecting input DMA request channel %d buffer 0x%08x "
              "interruptBytes %d\n",
              DRV_TITLE, localChannel, (unsigned int)buffer, bufferSize);
        return NO;
    }
    if (gHDA == NULL || !gHDA->initialized) {
        IOLog(
            "%s: rejecting playback request before controller initialization\n",
            DRV_TITLE);
        return NO;
    }

    encoding = [self dataEncoding];
    channels = [self channelCount];
    rate = [self sampleRate];

    HDA_VLOG(("%s: playback request channel %d encoding %s(%d) channels %d "
              "rate %d buffer 0x%08x dmaBytes %d interruptBytes %d\n",
              DRV_TITLE, localChannel, encodingName(encoding), encoding,
              channels, rate, (unsigned int)buffer, gHDA->dmaBufferSize,
              bufferSize));

    if (encoding == NX_SoundStreamDataEncoding_Linear16)
        bits = 16;
    else
        bits = 0;

    if (bits == 0) {
        IOLog("%s: rejecting playback request: unsupported encoding %s(%d), "
              "only linear16 is enabled\n",
              DRV_TITLE, encodingName(encoding), encoding);
        return NO;
    }
    if (!hdaBitsAreKnown(bits)) {
        IOLog("%s: rejecting playback request: unsupported PCM width %d\n",
              DRV_TITLE, bits);
        return NO;
    }
    if (!hdaBitsAreSupported(gHDA, bits))
        HDA_VLOG(
            ("%s: playback request uses unadvertised codec PCM width %d "
             "(pcmCaps 0x%08x streamCaps 0x%08x); trying standard HDA format\n",
             DRV_TITLE, bits, gHDA->pcmCaps, gHDA->streamCaps));
    if (channels < 1 || channels > 2) {
        IOLog("%s: rejecting playback request: unsupported channel count %d, "
              "only mono/stereo are enabled\n",
              DRV_TITLE, channels);
        return NO;
    }
    if (!hdaRateIsKnown(rate)) {
        IOLog("%s: rejecting playback request: unsupported sample rate %d\n",
              DRV_TITLE, rate);
        return NO;
    }
    if (!hdaRateIsSupported(gHDA, rate))
        HDA_VLOG(("%s: playback request uses unadvertised codec sample rate %d "
                  "(pcmCaps 0x%08x); trying standard HDA format\n",
                  DRV_TITLE, rate, gHDA->pcmCaps));

    (void)[self enableAllInterrupts];
    if (hdaStartOutput(gHDA, (unsigned int)buffer, gHDA->dmaBufferSize,
                       bufferSize, rate, bits, channels)) {
        IOLog("%s: failed to start output stream\n", DRV_TITLE);
        return NO;
    }
    [self updateOutputSettings];

    return YES;
}

- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead {
    if (!isRead && gHDA != NULL)
        hdaStopOutput(gHDA);
    (void)[self disableAllInterrupts];
}

static void clearInterrupts(void) {
    if (gHDA != NULL)
        (void)hdaHandleInterrupt(gHDA);
}

- (IOAudioInterruptClearFunc)interruptClearFunc {
    return clearInterrupts;
}

- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput {
    *serviceInput = NO;
    *serviceOutput = NO;

    if (gHDA != NULL && gHDA->outputInterrupt) {
        gHDA->outputInterrupt = NO;
        *serviceOutput = YES;
    }
}

static void hdaInterrupt(void *identity, void *state, unsigned int arg) {
    if (gHDA != NULL && hdaHandleInterrupt(gHDA)) {
        if (oldHandler != NULL)
            (*oldHandler)(identity, state, arg);
    }
    IOEnableInterrupt(identity);
}

- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt {
    [super getHandler:&oldHandler
                level:ipl
             argument:arg
         forInterrupt:localInterrupt];
    *handler = hdaInterrupt;
    return YES;
}

- (void)timeoutOccurred {
    IOLog("%s: timeout waiting for playback interrupt\n", DRV_TITLE);
}

- (void)updateSampleRate {
    if (gHDA != NULL && gHDA->initialized)
        [self updateOutputSettings];
}

- (BOOL)acceptsContinuousSamplingRates {
    return NO;
}

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
    unsigned int count;

    count = 0;
    encodings[count++] = NX_SoundStreamDataEncoding_Linear16;
    *numEncodings = count;
}

- (unsigned int)channelCountLimit {
    return 2;
}

- updateOutputSettings {
    if (gHDA != NULL && gHDA->initialized)
        hdaSetOutputVolume(gHDA, [self isOutputMuted],
                           [self outputAttenuationLeft],
                           [self outputAttenuationRight]);
    return self;
}

- (void)updateOutputMute {
    [self updateOutputSettings];
}

- (void)updateOutputAttenuationLeft {
    [self updateOutputSettings];
}

- (void)updateOutputAttenuationRight {
    [self updateOutputSettings];
}

- (void)updateInputGainLeft {
}

- (void)updateInputGainRight {
}

@end
