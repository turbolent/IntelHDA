#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>
#import <machkit/NXLock.h>
#import "PCIMSI/PCIMSIClient.h"
#import "IntelHDAMSIPCI.h"
#import "IntelHDAMSIWork.h"
#import "IntelHDAStats.h"
#import "IntelHDARefillCore.h"

#define DRV_TITLE     "IntelHDA"
#define DRV_VERSION   "v0.19"
#define DRV_MILESTONE "rate-conversion-r19"

#ifndef HDA_VERBOSE_LOGS
#define HDA_VERBOSE_LOGS 0
#endif

#if HDA_VERBOSE_LOGS
#define HDA_VLOG(x) IOLog x
#else
#define HDA_VLOG(x)
#endif

@interface IntelHDADriver : IOAudio
{
    NXLock *_stateLock;
    port_t _interruptPortKern;
    void *_workerThread;
    volatile unsigned _workerRunning, _workerExited, _pollMessagePending;
    BOOL _initializing, _ready, _ioAudioMayBeLive, _pciConfigured;
    BOOL _msiRequested, _quarantined;
    volatile BOOL _stopping;
    BOOL _msiAllocated, _msiEverAllocated, _msiEnabled, _msiActive, _msiUnsafeToFree;
    id _msiProvider;
    PCIMSIMessage _msiMessage;
    IntelHDAPCIInterruptCapabilities _pciInterruptCapabilities;
    IntelHDAMSILayout _msiLayout;
    IntelHDAMSIEpochStats _msiEpochStats;
    unsigned _msiNotifications, _msiEpochFailures, _ignoredMessages;
    unsigned _completedPeriods, _streamErrors, _pollTicks, _pollCompletions;
    unsigned _lastServiceEndTick, _lastServiceTailTicks, _lastRefillTicks;
    unsigned _queueResynchronizations, _maxPeriodBatch, _maxRefillTicks;
    unsigned _lastQueueDepth;
    ns_time_t _completionTimestamp;
    unsigned _msiDisableFailures, _msiReleaseFailures;
    BOOL _msiPromptRequested, _msiPromptActive;
    IOReturn _msiPromptResult, _msiGateResult;
    BOOL _msiTestMode;
    unsigned _msiTestFault;
}

+ (BOOL)probe:deviceDescription;

- initFromDeviceDescription:deviceDescription;
- free;

- (BOOL)reset;

- (IOEISADMABuffer)createDMABufferFor:(unsigned int *)physicalAddress
                               length:(unsigned int)numBytes
                                 read:(BOOL)isRead
                       needsLowMemory:(BOOL)lowerMem
                            limitSize:(BOOL)limitSize;
- (BOOL)startDMAForChannel:(unsigned int)localChannel
                       read:(BOOL)isRead
                     buffer:(IOEISADMABuffer)buffer
    bufferSizeForInterrupts:(unsigned int)bufferSize;
- (void)stopDMAForChannel:(unsigned int)localChannel read:(BOOL)isRead;

- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput;
- (void)_interruptOccurred;
- (void)timeoutOccurred;
- (void)runInterruptWorker;
- (IOReturn)getIntValues:(unsigned *)values
            forParameter:(IOParameterName)parameterName
                   count:(unsigned *)count;

- (void)updateSampleRate;
- (BOOL)acceptsContinuousSamplingRates;
- (void)getSamplingRatesLow:(int *)lowRate high:(int *)highRate;
- (void)getSamplingRates:(int *)rates count:(unsigned int *)numRates;
- (void)getDataEncodings:(NXSoundParameterTag *)encodings
                   count:(unsigned int *)numEncodings;
- (unsigned int)channelCountLimit;

- (void)updateOutputMute;
- updateOutputSettings;
- (void)updateOutputAttenuationLeft;
- (void)updateOutputAttenuationRight;
- (void)updateInputGainLeft;
- (void)updateInputGainRight;

@end
