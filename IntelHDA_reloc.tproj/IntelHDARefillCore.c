#include "IntelHDARefillCore.h"

int IntelHDARefillRun(void *context, const IntelHDARefillOps *ops)
{
    unsigned pending, elapsed, queued, serviced;
    int result;

    pending = 0;
    result = ops->sample(context, &pending);
    if (result < 0) return HDA_REFILL_OK;
    if (!result) return HDA_REFILL_RESYNC;
    for (serviced = 0; serviced < HDA_REFILL_LIMIT; serviced++) {
        queued = ops->queued(context);
        /* IOAudio can fill fewer than half the allocated ring. Its queue
         * includes completed descriptors until we retire them. At its end,
         * stop/reprime before a callback can refill an already played slot. */
        if (!queued || pending >= queued) return HDA_REFILL_RESYNC;
        if (!pending) return HDA_REFILL_OK;
        ops->complete(context);

        /* DMA kept running during the callback. Check against the OLD queue
         * before crediting the refill; a slow callback must not hide an
         * overtake by appending a descriptor and making the queue look full. */
        result = ops->sample(context, &elapsed);
        if (result < 0) return HDA_REFILL_OK;
        if (!result || elapsed >= queued - pending)
            return HDA_REFILL_RESYNC;
        pending += elapsed;
        pending--;
    }
    /* Bound service time, never discard an unserviced completion count. */
    return HDA_REFILL_RESYNC;
}
