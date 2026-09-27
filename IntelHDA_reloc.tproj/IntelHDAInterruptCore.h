#ifndef INTEL_HDA_INTERRUPT_CORE_H
#define INTEL_HDA_INTERRUPT_CORE_H

#define HDA_INTERRUPT_SERVICE_MAX_PASSES 10U
#define HDA_INTERRUPT_STREAM_BCIS        0x04U
#define HDA_INTERRUPT_STREAM_FIFOE       0x08U
#define HDA_INTERRUPT_STREAM_DESE        0x10U
#define HDA_INTERRUPT_STREAM_STATUS_MASK 0x1cU

typedef unsigned (*IntelHDARead32)(void *context, unsigned offset);
typedef unsigned (*IntelHDARead8)(void *context, unsigned offset);
typedef void (*IntelHDAWrite32)(void *context, unsigned offset,
                                unsigned value);
typedef void (*IntelHDAWrite8)(void *context, unsigned offset,
                               unsigned value);
typedef void (*IntelHDADelay)(void *context);

typedef struct IntelHDARegisterOps {
    void *context;
    IntelHDARead32 read32;
    IntelHDARead8 read8;
    IntelHDAWrite32 write32;
    IntelHDAWrite8 write8;
} IntelHDARegisterOps;

typedef struct IntelHDAInterruptResult {
    unsigned intsts;
    unsigned streamStatus;
    unsigned passes;
    unsigned completion;
    unsigned errors;
    unsigned handled;
    unsigned exhausted;
} IntelHDAInterruptResult;

int IntelHDAServiceStreamInterrupt(const IntelHDARegisterOps *ops,
                                   unsigned streamBase,
                                   unsigned outputInterruptMask,
                                   IntelHDAInterruptResult *result);
int IntelHDAStopStream(const IntelHDARegisterOps *ops, unsigned streamBase,
                      unsigned attempts, IntelHDADelay delay);
int IntelHDAStartStream(const IntelHDARegisterOps *ops, unsigned streamBase,
                       unsigned attempts, IntelHDADelay delay);
int IntelHDAResetStream(const IntelHDARegisterOps *ops, unsigned streamBase,
                       unsigned attempts, IntelHDADelay delay);

#endif
