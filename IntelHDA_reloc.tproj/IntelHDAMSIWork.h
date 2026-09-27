#ifndef INTEL_HDA_MSI_WORK_H
#define INTEL_HDA_MSI_WORK_H
#define HDA_MSI_EPOCH_PASSES 4U
#define HDA_MSI_EPOCH_OK 0
#define HDA_MSI_EPOCH_DEVICE_FAILED 1
#define HDA_MSI_EPOCH_EXHAUSTED 2
#define HDA_MSI_EPOCH_GATE_FAILED 3

typedef struct IntelHDAMSIEpochOps {
    int (*service)(void *context);
    int (*ready)(void *context);
    int (*gate)(void *context, int acknowledge, unsigned *pending);
} IntelHDAMSIEpochOps;
typedef struct IntelHDAMSIEpochStats {
    unsigned passes, consumes, acknowledgments, consumedMessages;
} IntelHDAMSIEpochStats;
int IntelHDAMSIRunEpoch(void *context, const IntelHDAMSIEpochOps *ops,
                        IntelHDAMSIEpochStats *stats);
int IntelHDAMSIPromptResultIsSafe(int active, int success, int unavailable);
#define HDA_MSI_TEST_NONE 0U
#define HDA_MSI_TEST_MISSING_CAP 1U
#define HDA_MSI_TEST_PROVIDER_LOOKUP 2U
#define HDA_MSI_TEST_PROVIDER_VERSION 3U
#define HDA_MSI_TEST_PROVIDER_INACTIVE 4U
#define HDA_MSI_TEST_MALFORMED_MESSAGE 5U
#define HDA_MSI_TEST_PROGRAM_READBACK 6U
#define HDA_MSI_TEST_GATE_FAILURE 7U
#define HDA_MSI_TEST_DISABLE_READBACK 8U
#define HDA_MSI_TEST_RELEASE_FAILURE 9U
#define HDA_MSI_TEST_DROP_NOTIFICATION 10U
#define HDA_MSI_TEST_DELAY_SERVICE 11U
#define HDA_MSI_TEST_STREAM_ERROR 12U
#define HDA_MSI_TEST_PROMPT_UNAVAILABLE 13U
#define HDA_MSI_TEST_INVALID 0xffffffffU
unsigned IntelHDAMSITestFaultForName(const char *name);
#endif
