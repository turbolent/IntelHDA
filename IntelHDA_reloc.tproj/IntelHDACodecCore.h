#ifndef INTEL_HDA_CODEC_CORE_H
#define INTEL_HDA_CODEC_CORE_H

typedef int (*IntelHDACodecCommand)(void *context, unsigned nid,
    unsigned verb, unsigned payload, unsigned *response);

/* Return 1 only after both verbs succeed and the readable bits match. */
int IntelHDACodecWriteVerified(void *context, IntelHDACodecCommand command,
    unsigned nid, unsigned setVerb, unsigned payload, unsigned getVerb,
    unsigned getPayload, unsigned expected, unsigned mask, unsigned *observed);

#endif
