#ifndef INTEL_HDA_REFILL_CORE_H
#define INTEL_HDA_REFILL_CORE_H

/* All callbacks run on IOAudio's serialized service thread. sample returns
 * 1 for progress, 0 for an ambiguous position, -1 when DMA has stopped. */
typedef struct IntelHDARefillOps {
    int (*sample)(void *context, unsigned *periods);
    unsigned (*queued)(void *context);
    void (*complete)(void *context);
} IntelHDARefillOps;

#define HDA_REFILL_OK 0
#define HDA_REFILL_RESYNC 1
#define HDA_REFILL_LIMIT 64U

int IntelHDARefillRun(void *context, const IntelHDARefillOps *ops);

#endif
