#ifndef INTEL_HDA_RATE_CORE_H
#define INTEL_HDA_RATE_CORE_H

typedef struct IntelHDARateConverter {
    unsigned channels, periodBytes, periods, nextPeriod, primed;
    int previous[2];
} IntelHDARateConverter;

/* Convert the IOAudio 16-bit ring to a separate ring at twice the rate.
 * Calls follow enqueue order, including wraparound, never DMA retire order. */
int IntelHDARateStart(IntelHDARateConverter *converter, unsigned sourceBytes,
    unsigned periodBytes, unsigned channels);
void IntelHDARateConvertPeriod(IntelHDARateConverter *converter,
    void *destination, const void *source);

#endif
