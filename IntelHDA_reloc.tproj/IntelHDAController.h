#ifndef _INTEL_HDA_CONTROLLER_H_
#define _INTEL_HDA_CONTROLLER_H_

#import <objc/objc.h>

#define HDA_BDL_ENTRIES 32
#define HDA_DMA_ALIGN   128
#define HDA_PAGE_SIZE   4096
#define HDA_PAGE_MASK   (HDA_PAGE_SIZE - 1)

struct hda_dma_area {
    void *alloc;
    unsigned char *vaddr;
    unsigned int paddr;
    unsigned int allocSize;
    unsigned int size;
};

struct hda_bdl_entry {
    unsigned int addrLow;
    unsigned int addrHigh;
    unsigned int length;
    unsigned int flags;
};

struct hda_state {
    unsigned int magic;
    unsigned short vendor;
    unsigned short device;
    unsigned char rev;
    unsigned short subsystemVendor;
    unsigned short subsystemDevice;
    unsigned int irq;

    unsigned int mmioPhys;
    unsigned int mmioSize;
    volatile unsigned char *regs;

    unsigned short gcap;
    unsigned int inputStreams;
    unsigned int outputStreams;
    unsigned int outputStreamIndex;
    unsigned int outputStreamBase;
    unsigned int outputIntMask;
    unsigned int streamTag;

    struct hda_dma_area corb;
    struct hda_dma_area rirb;
    struct hda_dma_area bdl;
    unsigned int corbEntries;
    unsigned int rirbEntries;
    unsigned int corbWp;
    unsigned int rirbRp;

    unsigned int codecAddress;
    unsigned int codecVendor;
    unsigned int afg;
    unsigned int dac;
    unsigned int pin;
    unsigned int path[8];
    unsigned int pathSelect[8];
    unsigned int pathLength;
    unsigned int streamFormat;
    unsigned int pcmCaps;
    unsigned int streamCaps;

    unsigned int dmaBufferPhys;
    unsigned int dmaBufferVirt;
    unsigned int dmaBufferSize;
    unsigned int periodBytes;

    volatile BOOL outputInterrupt;
    BOOL running;
    BOOL initialized;
};

int hdaInitController(struct hda_state *s);
void hdaShutdownController(struct hda_state *s);
int hdaStartOutput(struct hda_state *s, unsigned int phys, unsigned int bytes,
                   unsigned int interruptBytes, unsigned int sampleRate,
                   unsigned int bits, unsigned int channels);
void hdaStopOutput(struct hda_state *s);
int hdaHandleInterrupt(struct hda_state *s);
void hdaSetOutputVolume(struct hda_state *s, BOOL mute, int leftAttenuation,
                        int rightAttenuation);
unsigned int hdaFormatForParams(unsigned int rate, unsigned int bits,
                                unsigned int channels);
int hdaRateIsSupported(struct hda_state *s, unsigned int rate);
int hdaRateIsKnown(unsigned int rate);
int hdaBitsAreSupported(struct hda_state *s, unsigned int bits);
int hdaBitsAreKnown(unsigned int bits);
void hdaGetSupportedRates(struct hda_state *s, int *rates,
                          unsigned int *numRates);
unsigned int hdaDefaultFormat(struct hda_state *s);

#endif
