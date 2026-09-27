#include "IntelHDAMSIWork.h"
#include <string.h>
int IntelHDAMSIRunEpoch(void *context, const IntelHDAMSIEpochOps *ops,
                        IntelHDAMSIEpochStats *stats)
{
    unsigned pass, pending;
    int last;
    for (pass = 0; pass < HDA_MSI_EPOCH_PASSES; pass++) {
        if (!ops->service(context)) return HDA_MSI_EPOCH_DEVICE_FAILED;
        stats->passes++;
        last = pass + 1U == HDA_MSI_EPOCH_PASSES;
        /* Hardware work and provider MSI counts are independent. */
        if (ops->ready(context)) {
            if (last) return HDA_MSI_EPOCH_EXHAUSTED;
            continue;
        }
        pending = 0;
        if (!ops->gate(context, last, &pending)) return HDA_MSI_EPOCH_GATE_FAILED;
        if (last) {
            stats->acknowledgments++;
            return HDA_MSI_EPOCH_OK;
        }
        stats->consumes++;
        stats->consumedMessages += pending;
        /* consume(0) opens the gate; never acknowledge it twice. */
        if (!pending) return HDA_MSI_EPOCH_OK;
    }
    return HDA_MSI_EPOCH_EXHAUSTED;
}
int IntelHDAMSIPromptResultIsSafe(int active, int success, int unavailable)
{
    return active && (success || unavailable);
}
unsigned IntelHDAMSITestFaultForName(const char *name)
{
    static const char *names[] = {
        "None", "MissingCapability", "ProviderLookup", "ProviderVersion",
        "ProviderInactive", "MalformedMessage", "ProgrammingReadback",
        "GateFailure", "DisableReadback", "ReleaseFailure", "DropNotification",
        "DelayService", "StreamError", "PromptUnavailable"
    };
    unsigned i;
    if (!name) return HDA_MSI_TEST_NONE;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (!strcmp(name, names[i])) return i;
    return HDA_MSI_TEST_INVALID;
}
