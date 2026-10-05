#ifndef INTEL_HDA_ROUTE_CORE_H
#define INTEL_HDA_ROUTE_CORE_H
#include "IntelHDACodecCore.h"

#define HDA_ROUTE_MAX 16U
#define HDA_ROUTE_WRITES 64U
#define HDA_ROUTE_AUTO 0U
#define HDA_ROUTE_COMMITTED 1
#define HDA_ROUTE_REJECTED 0
#define HDA_ROUTE_UNSAFE (-1)

typedef struct IntelHDARouteChoice {
    unsigned pin, device, association, sequence, detectable;
    int present;
} IntelHDARouteChoice;
typedef struct IntelHDARouteDebounce {
    unsigned candidate, samples;
} IntelHDARouteDebounce;
/* Returns an index, or count when no route is eligible. Unknown/absent jacks
 * never displace a fixed speaker. Manual pin selection ignores presence. */
unsigned IntelHDARouteChoose(const IntelHDARouteChoice *routes, unsigned count,
                            unsigned pin);
int IntelHDARouteStable(IntelHDARouteDebounce *state, unsigned choice);

typedef struct IntelHDARouteWrite {
    unsigned nid, setVerb, getVerb, getPayload, prefix, mask, value, before, preserve;
} IntelHDARouteWrite;
typedef struct IntelHDARouteOps {
    IntelHDACodecCommand command;
    int (*pause)(void *context);
    int (*resume)(void *context);
} IntelHDARouteOps;
/* Caller serializes playback and owns the journal (never on a small kernel
 * stack). DMA is paused before snapshotting. Restore every attempted write,
 * including a failed SET, in reverse order before resuming the previous route.
 * No route identity is committed by this helper. */
int IntelHDARouteApply(void *context, const IntelHDARouteOps *ops,
                      IntelHDARouteWrite *writes, unsigned count);
#endif
