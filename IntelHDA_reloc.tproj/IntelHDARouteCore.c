#include "IntelHDARouteCore.h"

unsigned IntelHDARouteChoose(const IntelHDARouteChoice *routes, unsigned count,
                            unsigned pin)
{
    unsigned i, best = count, rank, bestRank = ~0U, tie, bestTie = ~0U;
    for (i = 0; i < count; i++) {
        if (pin) { if (routes[i].pin == pin) return i; else continue; }
        if (routes[i].device > 2U) continue;
        if (routes[i].detectable && routes[i].present == 1)
            rank = routes[i].device == 2U ? 0U : 1U;
        else if (routes[i].device == 1U) rank = 2U;
        else if (!routes[i].detectable) rank = routes[i].device == 0U ? 3U : 4U;
        else continue;
        tie = (routes[i].association << 12) | (routes[i].sequence << 8) | routes[i].pin;
        if (rank < bestRank || (rank == bestRank && tie < bestTie)) {
            best = i; bestRank = rank; bestTie = tie;
        }
    }
    return best;
}
int IntelHDARouteStable(IntelHDARouteDebounce *s, unsigned choice)
{
    if (!s->samples || s->candidate != choice) {
        s->candidate = choice; s->samples = 1; return 0;
    }
    if (s->samples < 2U) s->samples++;
    return s->samples == 2U;
}
static int writeValue(void *context, const IntelHDARouteOps *ops,
                      IntelHDARouteWrite *w, unsigned value)
{
    return IntelHDACodecWriteVerified(context, ops->command, w->nid,
        w->setVerb, w->prefix | (value & w->mask), w->getVerb,
        w->getPayload, value, w->mask, 0);
}
int IntelHDARouteApply(void *context, const IntelHDARouteOps *ops,
                      IntelHDARouteWrite *w, unsigned count)
{
    unsigned i, attempted = 0;
    int restored = 1;
    if (!ops || !ops->command || !ops->pause || !ops->resume || !w ||
        !count || count > HDA_ROUTE_WRITES) return HDA_ROUTE_REJECTED;
    if (!ops->pause(context)) return HDA_ROUTE_UNSAFE;
    for (i = 0; i < count; i++) {
        if (ops->command(context, w[i].nid, w[i].getVerb,
                         w[i].getPayload, &w[i].before)) goto rollback;
    }
    for (i = 0; i < count; i++) {
        attempted = i + 1;
        if (!writeValue(context, ops, &w[i],
                        w[i].value | (w[i].before & w[i].preserve))) goto rollback;
    }
    if (ops->resume(context)) return HDA_ROUTE_COMMITTED;
    /* A failed RUN readback is not proof of stopped hardware. */
    if (!ops->pause(context)) return HDA_ROUTE_UNSAFE;
rollback:
    while (attempted) {
        --attempted;
        if (!writeValue(context, ops, &w[attempted], w[attempted].before))
            restored = 0;
    }
    if (!restored) return HDA_ROUTE_UNSAFE;
    return ops->resume(context) ? HDA_ROUTE_REJECTED : HDA_ROUTE_UNSAFE;
}
