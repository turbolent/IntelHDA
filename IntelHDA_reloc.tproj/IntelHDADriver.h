#import <driverkit/IOAudio.h>
#import <driverkit/i386/ioPorts.h>

#define DRV_TITLE     "IntelHDA"
#define DRV_VERSION   "v0.14"
#define DRV_MILESTONE "quiet-default-logging"

#ifndef HDA_VERBOSE_LOGS
#define HDA_VERBOSE_LOGS 0
#endif

#if HDA_VERBOSE_LOGS
#define HDA_VLOG(x) IOLog x
#else
#define HDA_VLOG(x)
#endif

@interface IntelHDADriver : IOAudio
{}

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

- (IOAudioInterruptClearFunc)interruptClearFunc;
- (void)interruptOccurredForInput:(BOOL *)serviceInput
                        forOutput:(BOOL *)serviceOutput;
- (BOOL)getHandler:(IOInterruptHandler *)handler
             level:(unsigned int *)ipl
          argument:(unsigned int *)arg
      forInterrupt:(unsigned int)localInterrupt;
- (void)timeoutOccurred;

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
