#import <driverkit/generalFuncs.h>
#import <driverkit/i386/kernelDriver.h>
#import <driverkit/kernelDriver.h>
#import <kernserv/prototypes.h>

#import "IntelHDAController.h"
#import "IntelHDADriver.h"
#import "IntelHDAPlaybackCore.h"
#import "IntelHDACodecCore.h"

#define HDA_REG_GCAP      0x00
#define HDA_REG_VMIN      0x02
#define HDA_REG_VMAJ      0x03
#define HDA_REG_GCTL      0x08
#define HDA_REG_WAKEEN    0x0c
#define HDA_REG_STATESTS  0x0e
#define HDA_REG_INTCTL    0x20
#define HDA_REG_INTSTS    0x24
#define HDA_REG_WALLCLK   0x30
#define HDA_REG_CORBLBASE 0x40
#define HDA_REG_CORBUBASE 0x44
#define HDA_REG_CORBWP    0x48
#define HDA_REG_CORBRP    0x4a
#define HDA_REG_CORBCTL   0x4c
#define HDA_REG_CORBSTS   0x4d
#define HDA_REG_CORBSIZE  0x4e
#define HDA_REG_RIRBLBASE 0x50
#define HDA_REG_RIRBUBASE 0x54
#define HDA_REG_RIRBWP    0x58
#define HDA_REG_RINTCNT   0x5a
#define HDA_REG_RIRBCTL   0x5c
#define HDA_REG_RIRBSTS   0x5d
#define HDA_REG_RIRBSIZE  0x5e

#define HDA_GCTL_CRST   0x00000001
#define HDA_INT_GLOBAL  0x80000000
#define HDA_CORBCTL_RUN 0x02
#define HDA_RIRBCTL_RUN 0x02
#define HDA_RIRBCTL_RESPONSE_STATUS 0x01

#define HDA_SD_CTL       0x00
#define HDA_SD_STS       0x03
#define HDA_SD_LPIB      0x04
#define HDA_SD_CBL       0x08
#define HDA_SD_LVI       0x0c
#define HDA_SD_FORMAT    0x12
#define HDA_SD_BDLPL     0x18
#define HDA_SD_BDLPU     0x1c
#define HDA_SD_CTL_RUN   0x00000002
#define HDA_SD_CTL_IOCE  0x00000004
#define HDA_SD_CTL_FEIE  0x00000008
#define HDA_SD_CTL_DEIE  0x00000010
#define HDA_SD_CTL_SRST  0x00000001
#define HDA_SD_STS_BCIS  0x04
#define HDA_SD_STS_FIFOE 0x08
#define HDA_SD_STS_DESE  0x10

#define HDA_VERB_GET_PARAM          0xf00
#define HDA_VERB_GET_CONN_SELECT    0xf01
#define HDA_VERB_GET_CONN_ENTRY     0xf02
#define HDA_VERB_GET_PIN_CONTROL    0xf07
#define HDA_VERB_GET_PIN_SENSE      0xf09
#define HDA_VERB_GET_AMP_GAIN_MUTE  0x0b00
#define HDA_VERB_GET_STREAM_FORMAT  0xa00
#define HDA_VERB_GET_STREAM_CHANNEL 0xf06
#define HDA_VERB_GET_EAPD           0xf0c
#define HDA_VERB_SET_STREAM_FORMAT  0x200
#define HDA_VERB_SET_AMP_GAIN_MUTE  0x300
#define HDA_VERB_SET_CONN_SELECT    0x701
#define HDA_VERB_SET_PIN_CONTROL    0x707
#define HDA_VERB_SET_STREAM_CHANNEL 0x706
#define HDA_VERB_SET_EAPD           0x70c

#define HDA_PARAM_VENDOR_ID         0x00
#define HDA_PARAM_SUB_NODE_COUNT    0x04
#define HDA_PARAM_FUNCTION_TYPE     0x05
#define HDA_PARAM_PCM               0x0a
#define HDA_PARAM_STREAM            0x0b
#define HDA_PARAM_AUDIO_WIDGET_CAPS 0x09
#define HDA_PARAM_PIN_CAPS          0x0c
#define HDA_PARAM_CONN_LIST_LEN     0x0e
#define HDA_PARAM_OUTPUT_AMP_CAPS   0x12

#define HDA_WIDGET_AUDIO_OUTPUT   0x0
#define HDA_WIDGET_AUDIO_MIXER    0x2
#define HDA_WIDGET_AUDIO_SELECTOR 0x3
#define HDA_WIDGET_PIN_COMPLEX    0x4

#define HDA_AWCAP_OUT_AMP         0x00000004
#define HDA_AWCAP_AMP_OVERRIDE    0x00000008
#define HDA_AWCAP_FORMAT_OVERRIDE 0x00000010
#define HDA_AWCAP_CONN_LIST       0x00000100
#define HDA_AWCAP_DIGITAL         0x00000200
#define HDA_AMPCAP_NUM_STEPS      0x00007f00
#define HDA_AMPCAP_MUTE           0x80000000
#define HDA_PINCAP_HEADPHONE      0x00000008
#define HDA_PINCAP_OUTPUT         0x00000010
#define HDA_PINCAP_PRESENCE       0x00000004
#define HDA_PINCAP_EAPD           0x00010000
#define HDA_PINCTL_OUT_ENABLE     0x40
#define HDA_PINCTL_HP_ENABLE      0x80
#define HDA_PIN_SENSE_PRESENCE    0x80000000

#define HDA_SUPPCM_BITS_8  0x00010000
#define HDA_SUPPCM_BITS_16 0x00020000
#define HDA_SUPFMT_PCM     0x00000001

#define HDA_FMT_BITS_8   0x0000
#define HDA_FMT_BITS_16  0x0010
#define HDA_FMT_BASE_44K 0x4000
#define HDA_FMT_BASE_48K 0x0000
#define HDA_FMT_RATE(base, mult, div)                                          \
    ((base) | (((mult) - 1) << 11) | (((div) - 1) << 8))

#define HDA_JACK_LINE_OUT 0x0
#define HDA_JACK_SPEAKER  0x1
#define HDA_JACK_HP_OUT   0x2

#define HDA_DEFCFG_SEQUENCE(cfg)  ((cfg) & 0x0f)
#define HDA_DEFCFG_ASSOC(cfg)     (((cfg) >> 4) & 0x0f)
#define HDA_DEFCFG_COLOR(cfg)     (((cfg) >> 12) & 0x0f)
#define HDA_DEFCFG_DEVICE(cfg)    (((cfg) >> 20) & 0x0f)
#define HDA_DEFCFG_LOCATION(cfg)  (((cfg) >> 24) & 0x3f)
#define HDA_DEFCFG_PORT_CONN(cfg) (((cfg) >> 30) & 0x03)

#define HDA_AMP_SET_OUTPUT 0x8000
#define HDA_AMP_SET_LEFT   0x2000
#define HDA_AMP_SET_RIGHT  0x1000
#define HDA_AMP_GET_OUTPUT 0x8000
#define HDA_AMP_GET_LEFT   0x2000
#define HDA_AMP_GET_RIGHT  0x0000

#define HDA_POLL_COUNT 10000

struct hda_rate_info {
    unsigned int rate;
    unsigned int capBit;
    unsigned int format;
};

static const struct hda_rate_info hdaRateTable[] = {
    {8000, 0x0001, HDA_FMT_RATE(HDA_FMT_BASE_48K, 1, 6)},
    {16000, 0x0004, HDA_FMT_RATE(HDA_FMT_BASE_48K, 1, 3)},
    {22050, 0x0008, HDA_FMT_RATE(HDA_FMT_BASE_44K, 1, 2)},
    {32000, 0x0010, HDA_FMT_RATE(HDA_FMT_BASE_48K, 2, 3)},
    {44100, 0x0020, HDA_FMT_RATE(HDA_FMT_BASE_44K, 1, 1)},
    {48000, 0x0040, HDA_FMT_RATE(HDA_FMT_BASE_48K, 1, 1)},
    {88200, 0x0080, HDA_FMT_RATE(HDA_FMT_BASE_44K, 2, 1)},
    {96000, 0x0100, HDA_FMT_RATE(HDA_FMT_BASE_48K, 2, 1)},
    {176400, 0x0200, HDA_FMT_RATE(HDA_FMT_BASE_44K, 4, 1)},
    {192000, 0x0400, HDA_FMT_RATE(HDA_FMT_BASE_48K, 4, 1)},
    {0, 0, 0}};

static unsigned char hdaRead8(struct hda_state *s, unsigned int reg) {
    return *((volatile unsigned char *)(s->regs + reg));
}

static unsigned short hdaRead16(struct hda_state *s, unsigned int reg) {
    return *((volatile unsigned short *)(s->regs + reg));
}

static unsigned int hdaRead32(struct hda_state *s, unsigned int reg) {
    return *((volatile unsigned int *)(s->regs + reg));
}

static void hdaWrite8(struct hda_state *s, unsigned int reg,
                      unsigned char val) {
    *((volatile unsigned char *)(s->regs + reg)) = val;
}

static void hdaWrite16(struct hda_state *s, unsigned int reg,
                       unsigned short val) {
    *((volatile unsigned short *)(s->regs + reg)) = val;
}

static void hdaWrite32(struct hda_state *s, unsigned int reg,
                       unsigned int val) {
    *((volatile unsigned int *)(s->regs + reg)) = val;
}

static unsigned int hdaReadStreamControl(struct hda_state *s,
                                         unsigned int base) {
    return hdaRead16(s, base + HDA_SD_CTL) |
           (hdaRead8(s, base + HDA_SD_CTL + 2) << 16);
}

static void hdaWriteStreamControl(struct hda_state *s, unsigned int base,
                                  unsigned int val) {
    hdaWrite16(s, base + HDA_SD_CTL, val & 0xffff);
    hdaWrite8(s, base + HDA_SD_CTL + 2, (val >> 16) & 0xff);
}

static int hdaWait32Set(struct hda_state *s, unsigned int reg,
                        unsigned int mask) {
    int i;

    for (i = 0; i < HDA_POLL_COUNT; i++) {
        if ((hdaRead32(s, reg) & mask) == mask)
            return 0;
        IODelay(10);
    }
    return -1;
}

static int hdaWait32Clear(struct hda_state *s, unsigned int reg,
                          unsigned int mask) {
    int i;

    for (i = 0; i < HDA_POLL_COUNT; i++) {
        if ((hdaRead32(s, reg) & mask) == 0)
            return 0;
        IODelay(10);
    }
    return -1;
}

static unsigned char *hdaAlignPtr(void *p, unsigned int align) {
    unsigned int v;

    v = (unsigned int)p;
    v = (v + align - 1) & ~(align - 1);
    return (unsigned char *)v;
}

static int hdaAllocDMA(struct hda_dma_area *area, unsigned int size) {
    IOReturn irtn;

    area->allocSize = size + HDA_DMA_ALIGN;
    area->alloc = IOMallocLow(area->allocSize);
    if (area->alloc == NULL)
        return -1;

    bzero(area->alloc, area->allocSize);
    area->vaddr = hdaAlignPtr(area->alloc, HDA_DMA_ALIGN);
    area->size = size;

    irtn = IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)area->vaddr,
                                 &area->paddr);
    if (irtn) {
        IOFreeLow(area->alloc, area->allocSize);
        bzero(area, sizeof(*area));
        return -1;
    }

    return 0;
}

static void hdaFreeDMA(struct hda_dma_area *area) {
    if (area->alloc != NULL)
        IOFreeLow(area->alloc, area->allocSize);
    bzero(area, sizeof(*area));
}

static unsigned int hdaMakeVerb(unsigned int cad, unsigned int nid,
                                unsigned int verb, unsigned int payload) {
    return ((cad & 0x0f) << 28) | ((nid & 0x7f) << 20) |
           ((verb & 0x0fff) << 8) | (payload & 0xffff);
}

static int hdaCodecCommand(struct hda_state *s, unsigned int nid,
                           unsigned int verb, unsigned int payload,
                           unsigned int *response) {
    volatile unsigned int *corb;
    volatile unsigned int *rirb;
    unsigned int nextWp;
    unsigned int rp;
    unsigned int wp;
    unsigned int cmd;
    int i;

    corb = (volatile unsigned int *)s->corb.vaddr;
    rirb = (volatile unsigned int *)s->rirb.vaddr;
    nextWp = (s->corbWp + 1) & (s->corbEntries - 1);

    for (i = 0; i < HDA_POLL_COUNT; i++) {
        rp = hdaRead16(s, HDA_REG_CORBRP) & (s->corbEntries - 1);
        if (nextWp != rp)
            break;
        IODelay(10);
    }
    if (i == HDA_POLL_COUNT) {
        IOLog("%s: CORB full before verb nid 0x%x verb 0x%x\n", DRV_TITLE, nid,
              verb);
        return -1;
    }

    cmd = hdaMakeVerb(s->codecAddress, nid, verb, payload);
    corb[nextWp] = cmd;
    s->corbWp = nextWp;
    hdaWrite16(s, HDA_REG_CORBWP, s->corbWp);

    for (i = 0; i < HDA_POLL_COUNT; i++) {
        wp = hdaRead16(s, HDA_REG_RIRBWP) & (s->rirbEntries - 1);
        if (wp != s->rirbRp) {
            s->rirbRp = (s->rirbRp + 1) & (s->rirbEntries - 1);
            if (response != NULL)
                *response = rirb[s->rirbRp * 2];
            hdaWrite8(s, HDA_REG_RIRBSTS, 0x05);
            return 0;
        }
        IODelay(10);
    }

    IOLog("%s: RIRB timeout nid 0x%x verb 0x%x payload 0x%x cmd 0x%08x\n",
          DRV_TITLE, nid, verb, payload, cmd);
    return -1;
}

static int hdaGetParam(struct hda_state *s, unsigned int nid,
                       unsigned int param, unsigned int *response) {
    return hdaCodecCommand(s, nid, HDA_VERB_GET_PARAM, param, response);
}

static unsigned int hdaWidgetType(unsigned int caps) {
    return (caps >> 20) & 0x0f;
}

static unsigned int hdaConnLength(struct hda_state *s, unsigned int nid,
                                  int *longForm) {
    unsigned int len;

    if (hdaGetParam(s, nid, HDA_PARAM_CONN_LIST_LEN, &len))
        return 0;

    if (longForm != NULL)
        *longForm = (len & 0x80) ? 1 : 0;
    return len & 0x7f;
}

static unsigned int hdaConnEntry(struct hda_state *s, unsigned int nid,
                                 unsigned int index, int longForm) {
    unsigned int resp;
    unsigned int payload;

    payload = longForm ? (index >> 1) : (index >> 2);
    if (hdaCodecCommand(s, nid, HDA_VERB_GET_CONN_ENTRY, payload, &resp))
        return 0;

    if (longForm)
        return (resp >> ((index & 1) * 16)) & 0xffff;
    return (resp >> ((index & 3) * 8)) & 0xff;
}

static int hdaFindPath(struct hda_state *s, unsigned int nid,
                       unsigned int target, unsigned int depth) {
    unsigned int caps;
    unsigned int len;
    unsigned int child;
    unsigned int i;
    int longForm;
    int found;

    if (depth >= 8)
        return 0;

    s->path[depth] = nid;
    if (nid == target) {
        s->pathLength = depth + 1;
        return 1;
    }

    if (hdaGetParam(s, nid, HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
        return 0;
    if ((caps & HDA_AWCAP_CONN_LIST) == 0)
        return 0;

    len = hdaConnLength(s, nid, &longForm);
    for (i = 0; i < len; i++) {
        child = hdaConnEntry(s, nid, i, longForm);
        if (child == 0)
            continue;
        found = hdaFindPath(s, child, target, depth + 1);
        if (found) {
            s->pathSelect[depth] = i;
            return 1;
        }
    }

    return 0;
}

static unsigned int hdaAmpCaps(struct hda_state *s, unsigned int nid,
                               unsigned int widgetCaps) {
    unsigned int cap;

    if ((widgetCaps & HDA_AWCAP_AMP_OVERRIDE) == 0 && s->afg != 0) {
        HDA_VLOG(
            ("%s: using AFG output amp caps for nid 0x%x widgetCaps 0x%08x\n",
             DRV_TITLE, nid, widgetCaps));
        nid = s->afg;
    }

    if (hdaGetParam(s, nid, HDA_PARAM_OUTPUT_AMP_CAPS, &cap))
        return 0;
    return cap;
}

static unsigned int hdaAmpZeroDbGain(unsigned int cap) { return cap & 0x7f; }

static unsigned int hdaAmpGainForAttenuation(unsigned int cap,
                                             int attenuation) {
    int zeroDb;
    int stepQuarterDb;
    int attenuationQuarterDb;
    int stepsDown;
    int gain;

    zeroDb = cap & 0x7f;
    stepQuarterDb = ((cap >> 16) & 0x7f) + 1;
    if (stepQuarterDb <= 0)
        stepQuarterDb = 1;

    if (attenuation > 0)
        attenuation = 0;
    attenuationQuarterDb = -attenuation * 4;
    stepsDown = (attenuationQuarterDb + stepQuarterDb - 1) / stepQuarterDb;
    gain = zeroDb - stepsDown;
    if (gain < 0)
        gain = 0;
    if (gain > 0x7f)
        gain = 0x7f;

    return gain;
}

static unsigned int hdaGetOutputAmpChannel(struct hda_state *s,
                                           unsigned int nid,
                                           unsigned int channel, int *ok) {
    unsigned int payload;
    unsigned int response;

    payload = HDA_AMP_GET_OUTPUT | channel;
    if (hdaCodecCommand(s, nid, HDA_VERB_GET_AMP_GAIN_MUTE, payload,
                        &response)) {
        if (ok != NULL)
            *ok = 0;
        return 0;
    }

    if (ok != NULL)
        *ok = 1;
    return response & 0xff;
}

static void hdaSetOutputAmpChannel(struct hda_state *s, unsigned int nid,
                                   unsigned int channel, unsigned int gain,
                                   BOOL mute) {
    unsigned int payload;
    unsigned int wanted;
    unsigned int readback;
    unsigned int getChannel;
    int ok;

    wanted = gain & 0x7f;
    if (mute)
        wanted |= 0x80;
    payload = HDA_AMP_SET_OUTPUT | channel | (gain & 0x7f);
    if (mute)
        payload |= 0x80;
    (void)hdaCodecCommand(s, nid, HDA_VERB_SET_AMP_GAIN_MUTE, payload, NULL);

    getChannel =
        (channel == HDA_AMP_SET_LEFT) ? HDA_AMP_GET_LEFT : HDA_AMP_GET_RIGHT;
    readback = hdaGetOutputAmpChannel(s, nid, getChannel, &ok);
    if (ok) {
        HDA_VLOG(("%s: amp write/readback nid 0x%x %s wanted 0x%02x payload "
                  "0x%04x readback 0x%02x\n",
                  DRV_TITLE, nid,
                  (channel == HDA_AMP_SET_LEFT) ? "left" : "right", wanted,
                  payload, readback));
    } else {
        IOLog("%s: amp readback failed nid 0x%x %s wanted 0x%02x payload "
              "0x%04x\n",
              DRV_TITLE, nid, (channel == HDA_AMP_SET_LEFT) ? "left" : "right",
              wanted, payload);
    }
}

static void hdaSetOutputAmpZeroDb(struct hda_state *s, unsigned int nid,
                                  unsigned int caps) {
    unsigned int ampCaps;
    unsigned int gain;

    if ((caps & HDA_AWCAP_OUT_AMP) == 0)
        return;

    ampCaps = hdaAmpCaps(s, nid, caps);
    gain = hdaAmpZeroDbGain(ampCaps);
    hdaSetOutputAmpChannel(s, nid, HDA_AMP_SET_LEFT, gain, NO);
    hdaSetOutputAmpChannel(s, nid, HDA_AMP_SET_RIGHT, gain, NO);
}

void hdaSetOutputVolume(struct hda_state *s, BOOL mute, int leftAttenuation,
                        int rightAttenuation) {
    unsigned int caps;
    unsigned int ampCaps;
    unsigned int leftGain;
    unsigned int rightGain;
    int i;
    unsigned int volumeNid;
    unsigned int muteNid;
    unsigned int volumeCaps;
    unsigned int muteCaps;

    if (s == NULL || !s->initialized)
        return;

    volumeNid = 0;
    muteNid = 0;
    volumeCaps = 0;
    muteCaps = 0;

    for (i = (int)s->pathLength - 1; i >= 0; i--) {
        if (hdaGetParam(s, s->path[i], HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
            continue;
        if ((caps & HDA_AWCAP_OUT_AMP) == 0)
            continue;
        ampCaps = hdaAmpCaps(s, s->path[i], caps);
        if (volumeNid == 0 && (ampCaps & HDA_AMPCAP_NUM_STEPS)) {
            volumeNid = s->path[i];
            volumeCaps = caps;
        }
        if (muteNid == 0 && (ampCaps & HDA_AMPCAP_MUTE)) {
            muteNid = s->path[i];
            muteCaps = caps;
        }
    }

    if (volumeNid == 0) {
        IOLog("%s: no output volume amp found for volume update\n", DRV_TITLE);
    } else {
        ampCaps = hdaAmpCaps(s, volumeNid, volumeCaps);
        leftGain = hdaAmpGainForAttenuation(ampCaps, leftAttenuation);
        rightGain = hdaAmpGainForAttenuation(ampCaps, rightAttenuation);
        hdaSetOutputAmpChannel(s, volumeNid, HDA_AMP_SET_LEFT, leftGain,
                               mute && muteNid == volumeNid);
        hdaSetOutputAmpChannel(s, volumeNid, HDA_AMP_SET_RIGHT, rightGain,
                               mute && muteNid == volumeNid);
        HDA_VLOG(("%s: output volume nid 0x%x leftAtten %d rightAtten %d "
                  "leftGain 0x%x rightGain 0x%x ampCaps 0x%08x\n",
                  DRV_TITLE, volumeNid, leftAttenuation, rightAttenuation,
                  leftGain, rightGain, ampCaps));
    }

    if (muteNid == 0) {
        IOLog("%s: no output mute amp found for mute %d\n", DRV_TITLE, mute);
    } else if (muteNid != volumeNid) {
        ampCaps = hdaAmpCaps(s, muteNid, muteCaps);
        leftGain = hdaAmpZeroDbGain(ampCaps);
        rightGain = leftGain;
        hdaSetOutputAmpChannel(s, muteNid, HDA_AMP_SET_LEFT, leftGain, mute);
        hdaSetOutputAmpChannel(s, muteNid, HDA_AMP_SET_RIGHT, rightGain, mute);
        HDA_VLOG(("%s: output mute nid 0x%x mute %d gain 0x%x ampCaps 0x%08x\n",
                  DRV_TITLE, muteNid, mute, leftGain, ampCaps));
    } else {
        HDA_VLOG(("%s: output mute shares volume nid 0x%x mute %d\n", DRV_TITLE,
                  muteNid, mute));
    }

    for (i = 0; i < (int)s->pathLength; i++) {
        if (s->path[i] == volumeNid || s->path[i] == muteNid)
            continue;
        if (hdaGetParam(s, s->path[i], HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
            continue;
        if (caps & HDA_AWCAP_OUT_AMP)
            hdaSetOutputAmpZeroDb(s, s->path[i], caps);
    }
}

static const char *hdaDefaultDeviceName(unsigned int dev) {
    switch (dev) {
    case HDA_JACK_LINE_OUT:
        return "line-out";
    case HDA_JACK_SPEAKER:
        return "speaker";
    case HDA_JACK_HP_OUT:
        return "headphone";
    case 0x8:
        return "line-in";
    case 0xa:
        return "mic-in";
    default:
        return "other";
    }
}

static int hdaOutputPinRank(unsigned int defcfg) {
    unsigned int dev;

    dev = HDA_DEFCFG_DEVICE(defcfg);
    switch (dev) {
    case HDA_JACK_LINE_OUT:
        return 0;
    case HDA_JACK_SPEAKER:
        return 1;
    case HDA_JACK_HP_OUT:
        return 2;
    default:
        return -1;
    }
}

static int hdaAnalogOutputPinInfo(struct hda_state *s, unsigned int nid,
                                  unsigned int *rankOut,
                                  unsigned int *defcfgOut) {
    unsigned int caps;
    unsigned int pinCaps;
    unsigned int defcfg;
    unsigned int portConn;
    unsigned int dev;
    unsigned int pinSense;
    int present;
    int rank;

    if (hdaGetParam(s, nid, HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
        return 0;
    if (hdaWidgetType(caps) != HDA_WIDGET_PIN_COMPLEX)
        return 0;
    if (caps & HDA_AWCAP_DIGITAL)
        return 0;
    if (hdaGetParam(s, nid, HDA_PARAM_PIN_CAPS, &pinCaps))
        return 0;
    if ((pinCaps & HDA_PINCAP_OUTPUT) == 0)
        return 0;

    if (hdaCodecCommand(s, nid, 0xf1c, 0, &defcfg))
        defcfg = 0;
    portConn = HDA_DEFCFG_PORT_CONN(defcfg);
    dev = HDA_DEFCFG_DEVICE(defcfg);
    rank = hdaOutputPinRank(defcfg);
    present = -1;

    if (pinCaps & HDA_PINCAP_PRESENCE) {
        present = 0;
        if (hdaCodecCommand(s, nid, HDA_VERB_GET_PIN_SENSE, 0, &pinSense) ==
                0 &&
            (pinSense & HDA_PIN_SENSE_PRESENCE))
            present = 1;
    }

    if (dev == HDA_JACK_HP_OUT && present == 1)
        rank = 0;

    if (portConn == 1) {
        IOLog("%s: reject output pin nid 0x%x defcfg 0x%08x device %s port "
              "none\n",
              DRV_TITLE, nid, defcfg, hdaDefaultDeviceName(dev));
        return 0;
    }

    if (rank < 0) {
        IOLog("%s: reject output-capable pin nid 0x%x pincap 0x%08x defcfg "
              "0x%08x device %s\n",
              DRV_TITLE, nid, pinCaps, defcfg, hdaDefaultDeviceName(dev));
        return 0;
    }

    IOLog("%s: candidate analog output pin nid 0x%x rank %d device %s "
          "present %d pincap 0x%08x defcfg 0x%08x assoc %d seq %d color "
          "0x%x loc 0x%x\n",
          DRV_TITLE, nid, rank, hdaDefaultDeviceName(dev), present, pinCaps,
          defcfg, HDA_DEFCFG_ASSOC(defcfg), HDA_DEFCFG_SEQUENCE(defcfg),
          HDA_DEFCFG_COLOR(defcfg), HDA_DEFCFG_LOCATION(defcfg));

    if (rankOut != NULL)
        *rankOut = rank;
    if (defcfgOut != NULL)
        *defcfgOut = defcfg;
    return 1;
}

static int hdaSetupPath(struct hda_state *s) {
    unsigned int rootNodes;
    unsigned int fgStart;
    unsigned int fgCount;
    unsigned int fg;
    unsigned int ftype;
    unsigned int subNodes;
    unsigned int nodeStart;
    unsigned int nodeCount;
    unsigned int nid;
    unsigned int caps;
    unsigned int dacList[32];
    unsigned int pinList[32];
    unsigned int pinRank[32];
    unsigned int pinDefcfg[32];
    unsigned int dacCount;
    unsigned int pinCount;
    unsigned int i;
    unsigned int j;

    if (hdaGetParam(s, 0, HDA_PARAM_VENDOR_ID, &s->codecVendor)) {
        IOLog("%s: no codec response at address %d\n", DRV_TITLE,
              s->codecAddress);
        return -1;
    }

    IOLog("%s: codec%d vendor 0x%08x\n", DRV_TITLE, s->codecAddress,
          s->codecVendor);

    if (hdaGetParam(s, 0, HDA_PARAM_SUB_NODE_COUNT, &rootNodes))
        return -1;
    fgStart = (rootNodes >> 16) & 0xff;
    fgCount = rootNodes & 0xff;
    s->afg = 0;

    for (i = 0; i < fgCount; i++) {
        fg = fgStart + i;
        if (hdaGetParam(s, fg, HDA_PARAM_FUNCTION_TYPE, &ftype))
            continue;
        if ((ftype & 0xff) == 1) {
            s->afg = fg;
            break;
        }
    }

    if (s->afg == 0) {
        IOLog("%s: no audio function group found\n", DRV_TITLE);
        return -1;
    }

    if (hdaGetParam(s, s->afg, HDA_PARAM_SUB_NODE_COUNT, &subNodes))
        return -1;
    nodeStart = (subNodes >> 16) & 0xff;
    nodeCount = subNodes & 0xff;
    dacCount = 0;
    pinCount = 0;

    IOLog("%s: AFG nid 0x%x nodes start 0x%x count %d\n", DRV_TITLE, s->afg,
          nodeStart, nodeCount);

    for (i = 0; i < nodeCount; i++) {
        nid = nodeStart + i;
        if (hdaGetParam(s, nid, HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
            continue;

        if (hdaWidgetType(caps) == HDA_WIDGET_AUDIO_OUTPUT &&
            (caps & HDA_AWCAP_DIGITAL) == 0 && dacCount < 32) {
            dacList[dacCount++] = nid;
            IOLog("%s: candidate DAC nid 0x%x caps 0x%08x\n", DRV_TITLE, nid,
                  caps);
        }

        if (pinCount < 32 && hdaAnalogOutputPinInfo(s, nid, &pinRank[pinCount],
                                                    &pinDefcfg[pinCount])) {
            (void)hdaCodecCommand(s, nid, HDA_VERB_SET_PIN_CONTROL, 0, NULL);
            pinList[pinCount++] = nid;
        }
    }

    while (pinCount > 0) {
        unsigned int bestPin;
        unsigned int bestDefcfg;
        unsigned int bestIdx;
        unsigned int bestRank;
        unsigned int bestAssoc;
        unsigned int bestSeq;
        unsigned int rank;
        unsigned int assoc;
        unsigned int seq;

        bestPin = 0;
        bestDefcfg = 0;
        bestIdx = 0;
        bestRank = 0xffffffff;
        bestAssoc = 0xffffffff;
        bestSeq = 0xffffffff;
        for (j = 0; j < pinCount; j++) {
            rank = pinRank[j];
            assoc = HDA_DEFCFG_ASSOC(pinDefcfg[j]);
            seq = HDA_DEFCFG_SEQUENCE(pinDefcfg[j]);
            if (rank < bestRank || (rank == bestRank && assoc < bestAssoc) ||
                (rank == bestRank && assoc == bestAssoc && seq < bestSeq)) {
                bestPin = pinList[j];
                bestDefcfg = pinDefcfg[j];
                bestIdx = j;
                bestRank = rank;
                bestAssoc = assoc;
                bestSeq = seq;
            }
        }
        if (bestPin == 0)
            break;

        for (j = bestIdx; j + 1 < pinCount; j++) {
            pinList[j] = pinList[j + 1];
            pinRank[j] = pinRank[j + 1];
            pinDefcfg[j] = pinDefcfg[j + 1];
        }
        pinCount--;

        for (j = 0; j < dacCount; j++) {
            bzero(s->path, sizeof(s->path));
            bzero(s->pathSelect, sizeof(s->pathSelect));
            s->pathLength = 0;
            if (hdaFindPath(s, bestPin, dacList[j], 0)) {
                s->pin = bestPin;
                s->dac = dacList[j];
                IOLog("%s: selected output path pin 0x%x (%s rank %d assoc %d "
                      "seq %d) -> DAC 0x%x length %d\n",
                      DRV_TITLE, s->pin,
                      hdaDefaultDeviceName(HDA_DEFCFG_DEVICE(bestDefcfg)),
                      bestRank, bestAssoc, bestSeq, s->dac, s->pathLength);
                return 0;
            }
        }
        IOLog("%s: no DAC path for ranked output pin 0x%x (%s rank %d assoc %d "
              "seq %d)\n",
              DRV_TITLE, bestPin,
              hdaDefaultDeviceName(HDA_DEFCFG_DEVICE(bestDefcfg)), bestRank,
              bestAssoc, bestSeq);
    }

    IOLog("%s: no analog pin-to-DAC path found (pins %d dacs %d)\n", DRV_TITLE,
          pinCount, dacCount);
    return -1;
}

static int hdaQuerySelectedPCM(struct hda_state *s) {
    unsigned int caps;
    unsigned int pcmCaps;
    unsigned int streamCaps;

    pcmCaps = 0;
    streamCaps = 0;

    if (hdaGetParam(s, s->dac, HDA_PARAM_AUDIO_WIDGET_CAPS, &caps) == 0 &&
        (caps & HDA_AWCAP_FORMAT_OVERRIDE)) {
        (void)hdaGetParam(s, s->dac, HDA_PARAM_PCM, &pcmCaps);
    }
    if (pcmCaps == 0 || pcmCaps == 0xffffffff)
        (void)hdaGetParam(s, s->afg, HDA_PARAM_PCM, &pcmCaps);

    (void)hdaGetParam(s, s->dac, HDA_PARAM_STREAM, &streamCaps);
    if (streamCaps == 0 || streamCaps == 0xffffffff)
        (void)hdaGetParam(s, s->afg, HDA_PARAM_STREAM, &streamCaps);

    s->pcmCaps = pcmCaps;
    s->streamCaps = streamCaps;

    IOLog("%s: selected PCM caps pcm 0x%08x stream 0x%08x rates%s%s%s%s%s%s%s "
          "bits%s%s\n",
          DRV_TITLE, s->pcmCaps, s->streamCaps,
          (s->pcmCaps & 0x0001) ? " 8000" : "",
          (s->pcmCaps & 0x0002) ? " 11025" : "",
          (s->pcmCaps & 0x0004) ? " 16000" : "",
          (s->pcmCaps & 0x0008) ? " 22050" : "",
          (s->pcmCaps & 0x0010) ? " 32000" : "",
          (s->pcmCaps & 0x0020) ? " 44100" : "",
          (s->pcmCaps & 0x0040) ? " 48000" : "",
          hdaBitsAreSupported(s, 8) ? " 8" : "",
          hdaBitsAreSupported(s, 16) ? " 16" : "");

    if ((s->streamCaps & HDA_SUPFMT_PCM) == 0 ||
        ((s->pcmCaps & (HDA_SUPPCM_BITS_8 | HDA_SUPPCM_BITS_16)) == 0) ||
        ((s->pcmCaps & 0x07ff) == 0)) {
        IOLog("%s: selected DAC does not advertise usable PCM playback caps\n",
              DRV_TITLE);
        return -1;
    }

    return 0;
}

static int hdaCodecCoreCommand(void *context, unsigned nid,
    unsigned verb, unsigned payload, unsigned *response) {
    return hdaCodecCommand((struct hda_state *)context, nid, verb, payload, response);
}

static int hdaVerifySetting(struct hda_state *s, unsigned nid,
    unsigned setVerb, unsigned value, unsigned getVerb, unsigned mask) {
    unsigned observed;
    if (IntelHDACodecWriteVerified(s, hdaCodecCoreCommand, nid,
            setVerb, value, getVerb, 0, value, mask, &observed)) return 1;
    IOLog("%s: codec setting failed nid 0x%x verb 0x%x wanted 0x%x read 0x%x\n",
          DRV_TITLE, nid, setVerb, value, observed);
    return 0;
}

static int hdaProbeOutputRates(struct hda_state *s) {
    unsigned i, format, observed;
    s->verifiedRateMask = 0;
    /* Probe while DMA is stopped. Preserve unadvertised rates only if the
     * converter actually retains them; never promise a format it discards. */
    for (i = 0; hdaRateTable[i].rate; i++) {
        format = hdaFormatForParams(hdaRateTable[i].rate, 16, 2);
        if (!format) continue; /* Capability table also describes rates >48 kHz. */
        if (IntelHDACodecWriteVerified(s, hdaCodecCoreCommand, s->dac,
                HDA_VERB_SET_STREAM_FORMAT, format, HDA_VERB_GET_STREAM_FORMAT,
                0, format, 0xffff, &observed)) {
            s->verifiedRateMask |= hdaRateTable[i].capBit;
        } else {
            IOLog("%s: rate %u format 0x%x readback 0x%x not retained\n",
                  DRV_TITLE, hdaRateTable[i].rate, format, observed);
            if (observed == ~0U) { s->codecSetupFailures++; return -1; }
        }
    }
    IOLog("%s: verified output rate mask 0x%x\n", DRV_TITLE, s->verifiedRateMask);
    return s->verifiedRateMask ? 0 : -1;
}

static int hdaProgramPath(struct hda_state *s, unsigned int format) {
    unsigned int i, nid, caps, pinCaps, pinCtl;

    for (i = 0; i + 1 < s->pathLength; i++) {
        nid = s->path[i];
        if (hdaGetParam(s, nid, HDA_PARAM_AUDIO_WIDGET_CAPS, &caps))
            goto failed;
        if (hdaWidgetType(caps) == HDA_WIDGET_AUDIO_SELECTOR ||
            hdaWidgetType(caps) == HDA_WIDGET_PIN_COMPLEX) {
            if (!hdaVerifySetting(s, nid, HDA_VERB_SET_CONN_SELECT,
                    s->pathSelect[i], HDA_VERB_GET_CONN_SELECT, 0xff)) goto failed;
        }
    }
    if (!hdaVerifySetting(s, s->dac, HDA_VERB_SET_STREAM_FORMAT,
            format, HDA_VERB_GET_STREAM_FORMAT, 0xffff) ||
        !hdaVerifySetting(s, s->dac, HDA_VERB_SET_STREAM_CHANNEL,
            s->streamTag << 4, HDA_VERB_GET_STREAM_CHANNEL, 0xff)) goto failed;

    if (hdaGetParam(s, s->pin, HDA_PARAM_PIN_CAPS, &pinCaps)) goto failed;
    pinCtl = HDA_PINCTL_OUT_ENABLE;
    if (pinCaps & HDA_PINCAP_HEADPHONE) pinCtl |= HDA_PINCTL_HP_ENABLE;
    if ((pinCaps & HDA_PINCAP_EAPD) &&
        !hdaVerifySetting(s, s->pin, HDA_VERB_SET_EAPD,
            0x02, HDA_VERB_GET_EAPD, 0x02)) goto failed;
    if (!hdaVerifySetting(s, s->pin, HDA_VERB_SET_PIN_CONTROL,
            pinCtl, HDA_VERB_GET_PIN_CONTROL, 0xff)) goto failed;
    s->streamFormat = format;
    return 0;
failed:
    s->codecSetupFailures++;
    return -1;
}

static int hdaSetupRings(struct hda_state *s) {
    unsigned int corbSel;
    unsigned int rirbSel;
    unsigned char sizeReg;

    if (hdaAllocDMA(&s->corb, 256 * sizeof(unsigned int)) ||
        hdaAllocDMA(&s->rirb, 256 * 2 * sizeof(unsigned int)) ||
        hdaAllocDMA(&s->bdl, HDA_BDL_ENTRIES * sizeof(struct hda_bdl_entry))) {
        IOLog("%s: failed to allocate DMA command rings\n", DRV_TITLE);
        return -1;
    }

    hdaWrite8(s, HDA_REG_CORBCTL, 0);
    hdaWrite8(s, HDA_REG_RIRBCTL, 0);
    IODelay(100);

    hdaWrite32(s, HDA_REG_CORBLBASE, s->corb.paddr);
    hdaWrite32(s, HDA_REG_CORBUBASE, 0);
    sizeReg = hdaRead8(s, HDA_REG_CORBSIZE);
    if (sizeReg & 0x40) {
        corbSel = 2;
        s->corbEntries = 256;
    } else if (sizeReg & 0x20) {
        corbSel = 1;
        s->corbEntries = 16;
    } else {
        corbSel = 0;
        s->corbEntries = 2;
    }
    hdaWrite8(s, HDA_REG_CORBSIZE, (sizeReg & ~0x03) | corbSel);
    hdaWrite16(s, HDA_REG_CORBRP, 0x8000);
    IODelay(100);
    hdaWrite16(s, HDA_REG_CORBRP, 0);
    hdaWrite16(s, HDA_REG_CORBWP, 0);
    s->corbWp = 0;

    hdaWrite32(s, HDA_REG_RIRBLBASE, s->rirb.paddr);
    hdaWrite32(s, HDA_REG_RIRBUBASE, 0);
    sizeReg = hdaRead8(s, HDA_REG_RIRBSIZE);
    if (sizeReg & 0x40) {
        rirbSel = 2;
        s->rirbEntries = 256;
    } else if (sizeReg & 0x20) {
        rirbSel = 1;
        s->rirbEntries = 16;
    } else {
        rirbSel = 0;
        s->rirbEntries = 2;
    }
    hdaWrite8(s, HDA_REG_RIRBSIZE, (sizeReg & ~0x03) | rirbSel);
    hdaWrite16(s, HDA_REG_RIRBWP, 0x8000);
    hdaWrite16(s, HDA_REG_RINTCNT, 1);
    hdaWrite8(s, HDA_REG_RIRBSTS, 0x05);
    s->rirbRp = hdaRead16(s, HDA_REG_RIRBWP) & (s->rirbEntries - 1);

    /* Keep response status generation enabled so each polled response can
     * be acknowledged. QEMU stops CORB at RINTCNT until that status clears.
     * INTCTL.CIE remains clear, so codec responses never deliver an IRQ. */
    hdaWrite8(s, HDA_REG_RIRBCTL,
              HDA_RIRBCTL_RUN | HDA_RIRBCTL_RESPONSE_STATUS);
    hdaWrite8(s, HDA_REG_CORBCTL, HDA_CORBCTL_RUN);

    IOLog("%s: CORB %d entries phys 0x%08x RIRB %d entries phys 0x%08x\n",
          DRV_TITLE, s->corbEntries, s->corb.paddr, s->rirbEntries,
          s->rirb.paddr);
    return 0;
}

static int hdaSelectCodecAddress(struct hda_state *s, unsigned int statests) {
    unsigned int mask;
    unsigned int i;

    mask = statests & 0x000f;
    if (mask == 0) {
        IOLog("%s: no codec present in STATESTS 0x%04x\n", DRV_TITLE, statests);
        return -1;
    }

    for (i = 0; i < 4; i++) {
        if (mask & (1 << i)) {
            s->codecAddress = i;
            if (mask & ~(1 << i)) {
                IOLog("%s: multiple codecs STATESTS 0x%04x, using address %d\n",
                      DRV_TITLE, statests, i);
            } else {
                IOLog("%s: using codec address %d from STATESTS 0x%04x\n",
                      DRV_TITLE, i, statests);
            }
            return 0;
        }
    }

    return -1;
}

unsigned int hdaFormatForParams(unsigned int rate, unsigned int bits,
                                unsigned int channels) {
    return IntelHDAPlaybackFormat(rate, bits, channels);
}

static int hdaRateIsNative(struct hda_state *s, unsigned int rate) {
    unsigned int i;

    if (s == NULL)
        return 0;
    for (i = 0; hdaRateTable[i].rate != 0; i++) {
        if (hdaRateTable[i].rate == rate)
            return (((s->verifiedRateMask ? s->verifiedRateMask : s->pcmCaps) &
                     hdaRateTable[i].capBit) != 0);
    }
    return 0;
}

int hdaRateIsSupported(struct hda_state *s, unsigned int rate) {
    return hdaRateIsNative(s, rate) ||
        (rate == 22050 && s && s->converted.vaddr && hdaRateIsNative(s, 44100));
}

int hdaRateIsKnown(unsigned int rate) {
    return IntelHDAPlaybackFormat(rate, 16, 2) != 0;
}

int hdaBitsAreSupported(struct hda_state *s, unsigned int bits) {
    if (s == NULL || (s->streamCaps & HDA_SUPFMT_PCM) == 0)
        return 0;
    if (bits == 8)
        return ((s->pcmCaps & HDA_SUPPCM_BITS_8) != 0);
    if (bits == 16)
        return ((s->pcmCaps & HDA_SUPPCM_BITS_16) != 0);
    return 0;
}

int hdaBitsAreKnown(unsigned int bits) { return (bits == 8 || bits == 16); }

void hdaGetSupportedRates(struct hda_state *s, int *rates,
                          unsigned int *numRates) {
    unsigned i, count, mask;
    /* IOAudio may ask during initialization, before the stopped-codec probe. */
    mask = s && s->verifiedRateMask ? s->verifiedRateMask : 0x60;
    if (s && s->converted.vaddr && (mask & 0x20)) mask |= 0x08;
    count = 0;
    for (i = 0; hdaRateTable[i].rate; i++) {
        if (!(mask & hdaRateTable[i].capBit)) continue;
        if (rates) rates[count] = hdaRateTable[i].rate;
        count++;
    }
    if (numRates) *numRates = count;
}

unsigned int hdaDefaultFormat(struct hda_state *s) {
    unsigned int bits;
    unsigned int rate;

    bits = hdaBitsAreSupported(s, 16) ? 16 : 8;
    if (hdaRateIsSupported(s, 48000))
        rate = 48000;
    else if (hdaRateIsSupported(s, 44100))
        rate = 44100;
    else if (hdaRateIsSupported(s, 22050))
        rate = 22050;
    else
        rate = 8000;

    return hdaFormatForParams(rate, bits, 2);
}

int hdaInitController(struct hda_state *s) {
    unsigned int gctl;
    unsigned int statests;
    unsigned int maj;
    unsigned int min;

    if (s == NULL || s->regs == NULL)
        return -1;
    if (s->initialized)
        return 0;

    hdaWrite32(s, HDA_REG_INTCTL, 0);
    hdaWrite16(s, HDA_REG_WAKEEN, 0);

    gctl = hdaRead32(s, HDA_REG_GCTL);
    hdaWrite32(s, HDA_REG_GCTL, gctl & ~HDA_GCTL_CRST);
    if (hdaWait32Clear(s, HDA_REG_GCTL, HDA_GCTL_CRST)) {
        IOLog("%s: controller reset assert timeout GCTL 0x%08x\n", DRV_TITLE,
              hdaRead32(s, HDA_REG_GCTL));
        return -1;
    }
    IODelay(1000);
    hdaWrite32(s, HDA_REG_GCTL, hdaRead32(s, HDA_REG_GCTL) | HDA_GCTL_CRST);
    if (hdaWait32Set(s, HDA_REG_GCTL, HDA_GCTL_CRST)) {
        IOLog("%s: controller reset release timeout GCTL 0x%08x\n", DRV_TITLE,
              hdaRead32(s, HDA_REG_GCTL));
        return -1;
    }
    IODelay(1000);

    s->gcap = hdaRead16(s, HDA_REG_GCAP);
    min = hdaRead8(s, HDA_REG_VMIN);
    maj = hdaRead8(s, HDA_REG_VMAJ);
    s->inputStreams = (s->gcap >> 8) & 0x0f;
    s->outputStreams = (s->gcap >> 12) & 0x0f;
    if (s->outputStreams == 0) {
        IOLog("%s: no output streams GCAP 0x%04x\n", DRV_TITLE, s->gcap);
        return -1;
    }

    s->outputStreamIndex = s->inputStreams;
    s->outputStreamBase = 0x80 + (s->inputStreams * 0x20);
    s->outputIntMask = 1 << s->outputStreamIndex;
    s->streamTag = 1;
    statests = hdaRead16(s, HDA_REG_STATESTS);
    hdaWrite16(s, HDA_REG_STATESTS, statests);

    IOLog("%s: HDA version %d.%d GCAP 0x%04x ISS %d OSS %d STATESTS 0x%04x "
          "outBase 0x%x\n",
          DRV_TITLE, maj, min, s->gcap, s->inputStreams, s->outputStreams,
          statests, s->outputStreamBase);

    if (hdaSelectCodecAddress(s, statests))
        return -1;
    if (hdaSetupRings(s))
        return -1;
    if (hdaSetupPath(s))
        return -1;
    if (hdaQuerySelectedPCM(s))
        return -1;
    if (hdaProbeOutputRates(s)) return -1;

    if (!hdaRateIsNative(s, 22050) && hdaRateIsNative(s, 44100)) {
        /* The BDL translates every page; this ring needs wired kernel memory,
         * not the small ISA low-memory pool used by the command rings. */
        s->converted.allocSize = 65536 + HDA_PAGE_SIZE;
        s->converted.alloc = IOMalloc(s->converted.allocSize);
        if (!s->converted.alloc) {
            IOLog("%s: cannot reserve 22050 Hz conversion buffer\n", DRV_TITLE);
            return -1;
        }
        s->converted.vaddr = hdaAlignPtr(s->converted.alloc, HDA_PAGE_SIZE);
        s->converted.size = 65536;
        bzero(s->converted.vaddr, s->converted.size);
        IOLog("%s: 22050 Hz playback converted to verified 44100 Hz\n", DRV_TITLE);
    }

    if (hdaProgramPath(s, hdaDefaultFormat(s))) return -1;
    s->initialized = YES;
    hdaSetOutputVolume(s, YES, 0, 0);
    IOLog("%s: initialized codec path pin 0x%x DAC 0x%x\n", DRV_TITLE, s->pin,
          s->dac);
    return 0;
}

void hdaShutdownController(struct hda_state *s) {
    if (s == NULL)
        return;

    if (s->regs != NULL) {
        if (s->outputStreamBase >= 0x80 && !hdaStopOutput(s)) return;
        hdaWrite32(s, HDA_REG_INTCTL, 0);
        hdaWrite8(s, HDA_REG_CORBCTL, 0);
        hdaWrite8(s, HDA_REG_RIRBCTL, 0);
        if (hdaRead8(s, HDA_REG_CORBCTL) || hdaRead8(s, HDA_REG_RIRBCTL)) return;
    }

    if (s->converted.alloc)
        IOFree(s->converted.alloc, s->converted.allocSize);
    bzero(&s->converted, sizeof(s->converted));
    hdaFreeDMA(&s->bdl);
    hdaFreeDMA(&s->rirb);
    hdaFreeDMA(&s->corb);
    s->initialized = NO;
}

static IntelHDARegisterOps hdaRegisterOps(struct hda_state *s);
static void hdaStreamDelay(void *context) { (void)context; IODelay(10); }
static int hdaResetStream(struct hda_state *s) {
    IntelHDARegisterOps ops = hdaRegisterOps(s);
    int ok = IntelHDAResetStream(&ops, s->outputStreamBase,
                                HDA_POLL_COUNT, hdaStreamDelay);
    if (!ok)
        IOLog("%s: stream reset failed at 0x%x control 0x%06x\n",
              DRV_TITLE, s->outputStreamBase,
              hdaReadStreamControl(s, s->outputStreamBase));
    return ok;
}

static int hdaSetupOutputBDL(struct hda_state *s, unsigned int virt, unsigned int bytes,
                             unsigned int period, unsigned int *entriesOut) {
    struct hda_bdl_entry *bdl;
    unsigned int offset;
    unsigned int remain;
    unsigned int periodRemain;
    unsigned int entries;

    if (virt == 0)
        return -1;

    bdl = (struct hda_bdl_entry *)s->bdl.vaddr;
    bzero(bdl, s->bdl.size);

    offset = 0;
    remain = bytes;
    periodRemain = period;
    entries = 0;

    while (remain > 0) {
        unsigned int phys;
        unsigned int chunk;
        unsigned int ioc;

        if (entries >= HDA_BDL_ENTRIES) {
            IOLog("%s: BDL exhausted for bytes %d period %d at offset %d\n",
                  DRV_TITLE, bytes, period, offset);
            return -1;
        }

        if (IOPhysicalFromVirtual(IOVmTaskSelf(), (vm_address_t)(virt + offset),
                                  &phys) != IO_R_SUCCESS) {
            IOLog("%s: cannot translate playback buffer virt 0x%08x\n",
                  DRV_TITLE, virt + offset);
            return -1;
        }

        if (phys & 0x03) {
            IOLog("%s: unaligned playback phys 0x%08x virt 0x%08x\n", DRV_TITLE,
                  phys, virt + offset);
            return -1;
        }

        if (!IntelHDAPlanBDLChunk(virt, offset, remain, periodRemain, &chunk,
                                  &ioc)) {
            IOLog(
                "%s: invalid BDL chunk virt 0x%08x remain %d periodRemain %d\n",
                DRV_TITLE, virt + offset, remain, periodRemain);
            return -1;
        }
        bdl[entries].addrLow = phys;
        bdl[entries].addrHigh = 0;
        bdl[entries].length = chunk;
        bdl[entries].flags = ioc;

        if (entries < 4) {
            HDA_VLOG(("%s: BDL[%d] virt 0x%08x phys 0x%08x bytes %d ioc %d\n",
                      DRV_TITLE, entries, virt + offset, phys, chunk, ioc));
        }

        offset += chunk;
        remain -= chunk;
        if (chunk == periodRemain)
            periodRemain = period;
        else
            periodRemain -= chunk;
        entries++;
    }

    if (entriesOut != NULL)
        *entriesOut = entries;
    return 0;
}

int hdaStartOutput(struct hda_state *s, unsigned int phys, unsigned int bytes,
                   unsigned int interruptBytes, unsigned int sampleRate,
                   unsigned int bits, unsigned int channels, BOOL mute,
                   int leftAttenuation, int rightAttenuation,
                   unsigned int queuedPeriods) {
    IntelHDARegisterOps ops;
    unsigned int base;
    unsigned int format;
    unsigned int period;
    unsigned int entries;
    unsigned int ctl;
    unsigned int sourceRate, virt, i;

    if (s == NULL || !s->initialized || phys == 0 || bytes == 0) {
        IOLog("%s: invalid DMA start state phys 0x%08x bytes %u\n",
              DRV_TITLE, phys, bytes);
        return -1;
    }
    if ((bytes & 3U) || bytes != s->dmaBufferSize) {
        IOLog("%s: invalid DMA size %u, reserved %u\n",
              DRV_TITLE, bytes, s->dmaBufferSize);
        return -1;
    }
    if (!hdaStopOutput(s) || !hdaResetStream(s)) return -1;
    s->converting = NO;
    sourceRate = sampleRate;
    virt = s->dmaBufferVirt;
    period = interruptBytes;

    if (!hdaBitsAreKnown(bits)) {
        IOLog("%s: unsupported stream bits %d rate %d channels %d pcmCaps "
              "0x%08x streamCaps 0x%08x\n",
              DRV_TITLE, bits, sampleRate, channels, s->pcmCaps, s->streamCaps);
        return -1;
    }
    if (!hdaRateIsKnown(sampleRate)) {
        IOLog("%s: unsupported stream rate %d bits %d channels %d pcmCaps "
              "0x%08x\n",
              DRV_TITLE, sampleRate, bits, channels, s->pcmCaps);
        return -1;
    }
    if (!hdaRateIsSupported(s, sampleRate)) return HDA_START_CONFIG_REJECTED;
    if (!hdaBitsAreSupported(s, bits))
        HDA_VLOG(("%s: trying unadvertised stream bits %d pcmCaps 0x%08x "
                  "streamCaps 0x%08x\n",
                  DRV_TITLE, bits, s->pcmCaps, s->streamCaps));

    if (sampleRate == 22050 && !hdaRateIsNative(s, sampleRate)) {
        if (bits != 16 || !s->converted.vaddr ||
            !IntelHDARateStart(&s->converter, bytes, period, channels) ||
            !queuedPeriods || queuedPeriods > s->converter.periods)
            return HDA_START_CONFIG_REJECTED;
        bzero(s->converted.vaddr, s->converted.size);
        for (i = 0; i < queuedPeriods; i++)
            IntelHDARateConvertPeriod(&s->converter, s->converted.vaddr,
                                     (void *)s->dmaBufferVirt);
        s->converting = YES;
        virt = (unsigned)s->converted.vaddr;
        bytes *= 2;
        period *= 2;
        sampleRate = 44100;
    }
    format = hdaFormatForParams(sampleRate, bits, channels);
    if (format == 0) {
        IOLog("%s: invalid stream format rate %d bits %d channels %d\n",
              DRV_TITLE, sampleRate, bits, channels);
        return -1;
    }
    if (hdaProgramPath(s, format)) return HDA_START_CONFIG_REJECTED;
    /* Restore the requested levels before RUN can fetch even the first
     * period. Never briefly unmute or raise gain during a stream restart. */
    hdaSetOutputVolume(s, mute, leftAttenuation, rightAttenuation);

    if (!IntelHDAPlaybackProgressStart(&s->progress, bytes, period,
            sampleRate, channels * (bits / 8U), hdaRead32(s, HDA_REG_WALLCLK))) {
        IOLog("%s: invalid playback geometry bytes %u period %u rate %u bits %u channels %u\n",
              DRV_TITLE, bytes, period, sampleRate, bits, channels);
        return -1;
    }

    /* Emulated DMA can lead WALLCLK by a bounded FIFO or whole period.
     * The core shortens the safe observation interval by the same amount. */
    s->progress.positionSlack = IntelHDAPlaybackPositionSlack(s->vendor,
        s->device, s->subsystemVendor, s->subsystemDevice, s->codecVendor, period);

    if (hdaSetupOutputBDL(s, virt, bytes, period, &entries))
        return -1;

    base = s->outputStreamBase;
    hdaWrite32(s, base + HDA_SD_BDLPL, s->bdl.paddr);
    hdaWrite32(s, base + HDA_SD_BDLPU, 0);
    hdaWrite32(s, base + HDA_SD_CBL, bytes);
    hdaWrite16(s, base + HDA_SD_LVI, entries - 1);
    hdaWrite16(s, base + HDA_SD_FORMAT, format);
    if (hdaRead16(s, base + HDA_SD_FORMAT) != format) {
        s->codecSetupFailures++;
        IOLog("%s: controller format readback failed, wanted 0x%x\n", DRV_TITLE, format);
        return HDA_START_CONFIG_REJECTED;
    }
    hdaWrite8(s, base + HDA_SD_STS,
              HDA_SD_STS_BCIS | HDA_SD_STS_FIFOE | HDA_SD_STS_DESE);

    ctl = s->streamTag << 20;
    if (s->interruptDeliveryEnabled)
        ctl |= HDA_SD_CTL_IOCE | HDA_SD_CTL_FEIE | HDA_SD_CTL_DEIE;
    hdaWriteStreamControl(s, base, ctl);
    hdaWrite32(s, HDA_REG_INTCTL,
               s->interruptDeliveryEnabled ?
                   (HDA_INT_GLOBAL | s->outputIntMask) : 0);
    s->progress.tick = hdaRead32(s, HDA_REG_WALLCLK);
    ops = hdaRegisterOps(s);
    /* Real controllers can take several link clocks to report RUN. */
    if (!IntelHDAStartStream(&ops, base, HDA_POLL_COUNT, hdaStreamDelay)) {
        IOLog("%s: stream RUN did not latch, control 0x%06x status 0x%02x\n",
              DRV_TITLE, hdaReadStreamControl(s, base),
              hdaRead8(s, base + HDA_SD_STS));
        hdaStopOutput(s);
        return -1;
    }

    s->running = YES;
    s->outputInterrupt = NO;
    s->dmaBufferPhys = phys;
    s->sourceRate = sourceRate;
    s->hardwareRate = sampleRate;
    s->hardwareBufferBytes = bytes;
    s->streamGeneration++;
    s->periodBytes = period;

    HDA_VLOG(("%s: start output virt 0x%08x phys 0x%08x bytes %d period %d "
              "entries %d rate %d bits %d channels %d fmt 0x%04x bdl 0x%08x\n",
              DRV_TITLE, s->dmaBufferVirt, phys, bytes, period, entries,
              sampleRate, bits, channels, format, s->bdl.paddr));
    return 0;
}

void hdaRefillConvertedOutput(struct hda_state *s) {
    if (s && s->running && s->converting)
        IntelHDARateConvertPeriod(&s->converter, s->converted.vaddr,
                                 (void *)s->dmaBufferVirt);
}

int hdaStopOutput(struct hda_state *s) {
    IntelHDARegisterOps ops;
    int stopped;
    if (!s || !s->regs) return 1;
    s->outputInterrupt = NO;
    hdaWrite32(s, HDA_REG_INTCTL, 0);
    /* Partial initialization has no stream: never touch offset zero as SDn. */
    if (s->outputStreamBase < 0x80) return !s->running;
    ops = hdaRegisterOps(s);
    stopped = IntelHDAStopStream(&ops, s->outputStreamBase,
                               HDA_POLL_COUNT, hdaStreamDelay);
    if (stopped) s->running = NO;
    else IOLog("%s: stream stop readback timed out; retain DMA\n", DRV_TITLE);
    return stopped;
}

int hdaOutputPeriods(struct hda_state *s, unsigned *periods) {
    unsigned position, tick;
    if (!s || !s->regs || !s->running) return 0;
    position = hdaRead32(s, s->outputStreamBase + HDA_SD_LPIB);
    tick = hdaRead32(s, HDA_REG_WALLCLK);
    if (!IntelHDAPlaybackProgressSample(&s->progress, position, tick, periods)) {
        IOLog("%s: ambiguous DMA progress position %u previous %u elapsed %u ring %u carry %u period %u slack %u\n",
              DRV_TITLE, position, s->progress.position,
              tick - s->progress.tick, s->progress.ringTicks,
              s->progress.remainder, s->progress.periodBytes,
              s->progress.positionSlack);
        return 0;
    }
    return 1;
}

int hdaOutputStatusPending(struct hda_state *s) {
    return s && s->regs && s->outputStreamBase >= 0x80 &&
        (hdaRead8(s, s->outputStreamBase + HDA_SD_STS) & 0x1cU);
}

unsigned hdaWallClock(struct hda_state *s) {
    return s && s->regs ? hdaRead32(s, HDA_REG_WALLCLK) : 0;
}

unsigned hdaInterruptControl(struct hda_state *s) {
    return s && s->regs ? hdaRead32(s, HDA_REG_INTCTL) : 0;
}

static unsigned int hdaServiceRead32(void *context, unsigned int offset) {
    return hdaRead32((struct hda_state *)context, offset);
}

static unsigned int hdaServiceRead8(void *context, unsigned int offset) {
    return hdaRead8((struct hda_state *)context, offset);
}

static void hdaServiceWrite32(void *context, unsigned int offset,
                              unsigned int value) {
    hdaWrite32((struct hda_state *)context, offset, value);
}

static void hdaServiceWrite8(void *context, unsigned int offset,
                             unsigned int value) {
    hdaWrite8((struct hda_state *)context, offset, value);
}

static IntelHDARegisterOps hdaRegisterOps(struct hda_state *s) {
    IntelHDARegisterOps ops;
    ops.context = s;
    ops.read32 = hdaServiceRead32;
    ops.read8 = hdaServiceRead8;
    ops.write32 = hdaServiceWrite32;
    ops.write8 = hdaServiceWrite8;
    return ops;
}

void hdaQuiesceInterrupts(struct hda_state *s) {
    unsigned int ctl;

    if (s == NULL || s->regs == NULL)
        return;
    hdaWrite32(s, HDA_REG_INTCTL, 0);
    if (s->outputStreamBase < 0x80) return;
    ctl = hdaReadStreamControl(s, s->outputStreamBase);
    ctl &= ~(HDA_SD_CTL_IOCE | HDA_SD_CTL_FEIE | HDA_SD_CTL_DEIE);
    hdaWriteStreamControl(s, s->outputStreamBase, ctl);
}

void hdaAcknowledgePending(struct hda_state *s) {
    unsigned char status;

    if (s == NULL || s->regs == NULL)
        return;
    if (s->outputStreamBase < 0x80) return;
    status = hdaRead8(s, s->outputStreamBase + HDA_SD_STS);
    status &= HDA_SD_STS_BCIS | HDA_SD_STS_FIFOE | HDA_SD_STS_DESE;
    if (status != 0)
        hdaWrite8(s, s->outputStreamBase + HDA_SD_STS, status);
    /* Response status is enabled, but INTCTL.CIE always stays masked. */
    if ((hdaRead8(s, HDA_REG_RIRBCTL) & 0x01) != 0) {
        status = hdaRead8(s, HDA_REG_RIRBSTS) & 0x05;
        if (status != 0)
            hdaWrite8(s, HDA_REG_RIRBSTS, status);
    }
}

void hdaSetOutputInterrupts(struct hda_state *s, BOOL enabled) {
    unsigned int ctl;

    if (s == NULL || s->regs == NULL)
        return;

    s->interruptDeliveryEnabled = enabled;
    if (s->outputStreamBase < 0x80) return;
    ctl = hdaReadStreamControl(s, s->outputStreamBase);
    if (enabled && s->running)
        ctl |= HDA_SD_CTL_IOCE | HDA_SD_CTL_FEIE | HDA_SD_CTL_DEIE;
    else
        ctl &= ~(HDA_SD_CTL_IOCE | HDA_SD_CTL_FEIE | HDA_SD_CTL_DEIE);
    hdaWriteStreamControl(s, s->outputStreamBase, ctl);
    hdaWrite32(s, HDA_REG_INTCTL,
               enabled && s->running ? (HDA_INT_GLOBAL | s->outputIntMask) : 0);
}

int hdaServiceOutput(struct hda_state *s,
                     IntelHDAInterruptResult *result) {
    IntelHDARegisterOps ops;
    int serviced;

    if (s == NULL || s->regs == NULL || result == NULL)
        return 0;
    ops.context = s;
    ops.read32 = hdaServiceRead32;
    ops.read8 = hdaServiceRead8;
    ops.write32 = hdaServiceWrite32;
    ops.write8 = hdaServiceWrite8;
    serviced = IntelHDAServiceStreamInterrupt(&ops, s->outputStreamBase,
                                               s->outputIntMask, result);
    if (!serviced)
        return 0;
    if (result->errors != 0)
        IOLog("%s: stream error status 0x%02x LPIB 0x%08x INTSTS 0x%08x\n",
              DRV_TITLE, result->streamStatus,
              hdaRead32(s, s->outputStreamBase + HDA_SD_LPIB),
              result->intsts);
    return result->handled != 0;
}
