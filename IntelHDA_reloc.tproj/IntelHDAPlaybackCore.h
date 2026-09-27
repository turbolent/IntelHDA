#ifndef INTEL_HDA_PLAYBACK_CORE_H
#define INTEL_HDA_PLAYBACK_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct IntelHDAPlaybackProgress {
    unsigned bufferBytes, periodBytes, ringTicks;
    unsigned frameBytes, ticksPerFrame, positionSlack;
    unsigned position, tick, remainder;
} IntelHDAPlaybackProgress;
int IntelHDAPlaybackProgressStart(IntelHDAPlaybackProgress *p,
    unsigned bytes, unsigned period, unsigned rate, unsigned frameBytes,
    unsigned tick);
int IntelHDAPlaybackProgressSample(IntelHDAPlaybackProgress *p,
    unsigned position, unsigned tick, unsigned *periods);
unsigned IntelHDAPlaybackPositionSlack(unsigned vendor, unsigned device,
    unsigned subsystemVendor, unsigned subsystemDevice, unsigned codec,
    unsigned period);
unsigned int IntelHDAPlaybackFormat(unsigned int rate, unsigned int bits,
                                    unsigned int channels);
int IntelHDAPlanBDLChunk(unsigned int virtualAddress, unsigned int offset,
                         unsigned int remaining,
                         unsigned int periodRemaining,
                         unsigned int *chunkOut, unsigned int *iocOut);

#ifdef __cplusplus
}
#endif

#endif
