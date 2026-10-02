#include "IntelHDARateCore.h"

int IntelHDARateStart(IntelHDARateConverter *c, unsigned bytes,
    unsigned period, unsigned channels)
{
    if (!c || !bytes || bytes > 32768U || !period ||
        channels < 1U || channels > 2U || bytes % period ||
        period % (channels * 2U) || bytes / period < 2U) return 0;
    c->channels = channels;
    c->periodBytes = period;
    c->periods = bytes / period;
    c->nextPeriod = c->primed = 0;
    c->previous[0] = c->previous[1] = 0;
    return 1;
}

void IntelHDARateConvertPeriod(IntelHDARateConverter *c,
    void *destination, const void *source)
{
    const short *in;
    short *out;
    unsigned frame, channel, frames, offset;
    int current;
    offset = c->nextPeriod * c->periodBytes;
    in = (const short *)((const char *)source + offset);
    out = (short *)((char *)destination + offset * 2U);
    frames = c->periodBytes / (c->channels * 2U);
    for (frame = 0; frame < frames; frame++) {
        for (channel = 0; channel < c->channels; channel++) {
            current = in[frame * c->channels + channel];
            if (!c->primed) c->previous[channel] = current;
            out[(frame * 2U) * c->channels + channel] =
                (short)((c->previous[channel] + current) / 2);
            out[(frame * 2U + 1U) * c->channels + channel] = (short)current;
            c->previous[channel] = current;
        }
        c->primed = 1;
    }
    c->nextPeriod = (c->nextPeriod + 1U) % c->periods;
}
