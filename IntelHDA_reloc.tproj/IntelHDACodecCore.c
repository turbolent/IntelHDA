#include "IntelHDACodecCore.h"

int IntelHDACodecWriteVerified(void *context, IntelHDACodecCommand command,
    unsigned nid, unsigned setVerb, unsigned payload, unsigned getVerb,
    unsigned getPayload, unsigned expected, unsigned mask, unsigned *observed)
{
    unsigned response;
    if (observed) *observed = ~0U;
    if (!command || !mask) return 0;
    if (command(context, nid, setVerb, payload, 0)) return 0;
    if (command(context, nid, getVerb, getPayload, &response)) return 0;
    if (observed) *observed = response;
    return (response & mask) == (expected & mask);
}
