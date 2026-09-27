#include "IntelHDAPlaybackCore.h"

#define HDA_PLAYBACK_PAGE_SIZE 4096U
#define HDA_PLAYBACK_PAGE_MASK (HDA_PLAYBACK_PAGE_SIZE - 1U)

struct hda_playback_rate {
    unsigned int rate;
    unsigned int format;
};

static const struct hda_playback_rate playbackRates[] = {
    {8000U, 0x0500U},  {16000U, 0x0200U}, {22050U, 0x4100U},
    {32000U, 0x0a00U}, {44100U, 0x4000U}, {48000U, 0x0000U},
    {0U, 0U}};

unsigned int IntelHDAPlaybackFormat(unsigned int rate, unsigned int bits,
                                    unsigned int channels) {
    unsigned int i;
    unsigned int format;
    int found;

    if (channels == 0U || channels > 16U)
        return 0U;
    format = 0U;
    found = 0;
    for (i = 0U; playbackRates[i].rate != 0U; ++i) {
        if (playbackRates[i].rate == rate) {
            format = playbackRates[i].format;
            found = 1;
            break;
        }
    }
    if (!found)
        return 0U;
    if (bits == 16U)
        format |= 0x0010U;
    else if (bits != 8U)
        return 0U;
    return format | (channels - 1U);
}

int IntelHDAPlanBDLChunk(unsigned int virtualAddress, unsigned int offset,
                         unsigned int remaining,
                         unsigned int periodRemaining,
                         unsigned int *chunkOut, unsigned int *iocOut) {
    unsigned int chunk;
    unsigned int pageRemaining;

    if (remaining == 0U || periodRemaining == 0U || chunkOut == 0 ||
        iocOut == 0)
        return 0;
    pageRemaining = HDA_PLAYBACK_PAGE_SIZE -
                    ((virtualAddress + offset) & HDA_PLAYBACK_PAGE_MASK);
    chunk = remaining;
    if (chunk > pageRemaining)
        chunk = pageRemaining;
    if (chunk > periodRemaining)
        chunk = periodRemaining;
    chunk &= ~3U;
    if (chunk == 0U)
        return 0;
    *chunkOut = chunk;
    *iocOut = (chunk == periodRemaining) ? 1U : 0U;
    return 1;
}

unsigned IntelHDAPlaybackPositionSlack(unsigned vendor, unsigned device,
    unsigned subsystemVendor, unsigned subsystemDevice, unsigned codec,
    unsigned period) {
    /* QEMU slews its codec timer to fill an 8192-byte host-audio FIFO. */
    if ((codec >> 16) == 0x1af4U) return 8192U;
    /* VirtualBox's STAC9221 model fetches a whole period at a time, including
     * at stream start. Match the full emulated identity, not all Intel HDA. */
    if (vendor == 0x8086U && device == 0x2668U &&
        subsystemVendor == 0x8384U && subsystemDevice == 0x7680U &&
        codec == 0x83847680U) return period + 256U;
    return 256U;
}

int IntelHDAPlaybackProgressStart(IntelHDAPlaybackProgress *p,
    unsigned bytes, unsigned period, unsigned rate, unsigned frameBytes,
    unsigned tick) {
    if (!p || !bytes || !period || !frameBytes || rate < 8000U ||
        rate > 48000U || bytes > 65536U || bytes % period ||
        period % frameBytes || bytes / period < 2U)
        return 0;
    p->bufferBytes = bytes;
    p->periodBytes = period;
    /* Conservative full-lap bound; multiplication fits 32-bit C89. */
    p->ringTicks = (bytes / frameBytes) * (24000000U / rate);
    p->frameBytes = frameBytes;
    p->ticksPerFrame = 24000000U / rate;
    p->positionSlack = 256U;
    p->position = 0;
    p->tick = tick;
    p->remainder = 0;
    return 1;
}
int IntelHDAPlaybackProgressSample(IntelHDAPlaybackProgress *p,
    unsigned position, unsigned tick, unsigned *periods) {
    unsigned delta, bytes, elapsed, maximumAdvance;
    if (periods) *periods = 0;
    if (!p || !periods || !p->periodBytes || position > p->bufferBytes)
        return 0;
    /* Q270 can expose CBL itself at the wrap boundary. It aliases zero,
     * including on a repeated read; do not count an additional whole lap. */
    if (position == p->bufferBytes) position = 0;
    /* A whole unobserved lap cannot be recovered from a modulo position. */
    elapsed = tick - p->tick;
    if (elapsed >= p->ringTicks) return 0;
    delta = position >= p->position ? position - p->position :
            p->bufferBytes - p->position + position;
    /* Reject backwards/stale register jumps disguised as almost a full lap.
     * Include the bounded register/FIFO lead in both the advance bound and
     * the ambiguity check: a prefetched full lap is equally unrecoverable. */
    if (p->positionSlack >= p->bufferBytes) return 0;
    maximumAdvance = (elapsed / p->ticksPerFrame) * p->frameBytes + p->positionSlack;
    /* LPIB is a byte position; Q270 can expose an individual sample between
     * the channels of a stereo frame. Carry partial periods as bytes. */
    if (maximumAdvance >= p->bufferBytes || delta > maximumAdvance) return 0;
    bytes = p->remainder + delta;
    /* A carried partial period can make a sub-lap advance complete every
     * descriptor. DMA has then entered an unreplenished descriptor. Reject
     * before publishing completions or changing the diagnostic baseline. */
    if (bytes / p->periodBytes >= p->bufferBytes / p->periodBytes) return 0;
    *periods = bytes / p->periodBytes;
    p->remainder = bytes % p->periodBytes;
    p->position = position;
    p->tick = tick;
    return 1;
}
