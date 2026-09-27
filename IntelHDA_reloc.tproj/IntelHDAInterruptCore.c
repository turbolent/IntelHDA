#include "IntelHDAInterruptCore.h"

#define HDA_CORE_REG_INTCTL 0x20U
#define HDA_CORE_REG_INTSTS 0x24U
#define HDA_CORE_SD_STS     0x03U

static int validStream(const IntelHDARegisterOps *ops, unsigned base)
{
    return ops && ops->read8 && ops->write8 && ops->read32 && ops->write32 &&
           base >= 0x80U && base <= 0x3fe0U && !(base & 0x1fU);
}

static int waitControl(const IntelHDARegisterOps *ops, unsigned base,
                       unsigned mask, unsigned value, unsigned attempts,
                       IntelHDADelay delay)
{
    unsigned i;
    for (i = 0; i < attempts; i++) {
        if ((ops->read8(ops->context, base) & mask) == value) return 1;
        if (delay) delay(ops->context);
    }
    return 0;
}

int IntelHDAStartStream(const IntelHDARegisterOps *ops, unsigned base,
                       unsigned attempts, IntelHDADelay delay)
{
    unsigned ctl;
    if (!validStream(ops, base) || !attempts) return 0;
    ctl = ops->read8(ops->context, base);
    if (ctl & 1U) return 0;
    ops->write8(ops->context, base, ctl | 2U);
    return waitControl(ops, base, 2U, 2U, attempts, delay);
}

int IntelHDAStopStream(const IntelHDARegisterOps *ops, unsigned base,
                      unsigned attempts, IntelHDADelay delay)
{
    unsigned ctl;
    if (!validStream(ops, base) || !attempts) return 0;
    ops->write32(ops->context, HDA_CORE_REG_INTCTL, 0);
    ctl = ops->read8(ops->context, base) & ~0x1eU;
    ops->write8(ops->context, base, ctl);
    if (!waitControl(ops, base, 0x1eU, 0, attempts, delay)) return 0;
    ops->write8(ops->context, base + HDA_CORE_SD_STS, 0x1cU);
    return ops->read32(ops->context, HDA_CORE_REG_INTCTL) == 0;
}

int IntelHDAResetStream(const IntelHDARegisterOps *ops, unsigned base,
                       unsigned attempts, IntelHDADelay delay)
{
    unsigned ctl;
    if (!IntelHDAStopStream(ops, base, attempts, delay)) return 0;
    ctl = ops->read8(ops->context, base);
    ops->write8(ops->context, base, ctl | 1U);
    if (!waitControl(ops, base, 1U, 1U, attempts, delay)) return 0;
    ops->write8(ops->context, base, ctl & ~1U);
    if (!waitControl(ops, base, 1U, 0, attempts, delay)) return 0;
    ops->write8(ops->context, base + HDA_CORE_SD_STS, 0x1cU);
    return 1;
}

static void
clearResult(IntelHDAInterruptResult *result)
{
    result->intsts = 0;
    result->streamStatus = 0;
    result->passes = 0;
    result->completion = 0;
    result->errors = 0;
    result->handled = 0;
    result->exhausted = 0;
}

int
IntelHDAServiceStreamInterrupt(const IntelHDARegisterOps *ops,
                               unsigned streamBase,
                               unsigned outputInterruptMask,
                               IntelHDAInterruptResult *result)
{
    unsigned pass;
    unsigned intsts;
    unsigned status;
    unsigned relevant;

    if (result == 0 || !validStream(ops, streamBase))
        return 0;
    clearResult(result);
    ops->write32(ops->context, HDA_CORE_REG_INTCTL, 0);
    for (pass = 0; pass < HDA_INTERRUPT_SERVICE_MAX_PASSES; pass++) {
        intsts = ops->read32(ops->context, HDA_CORE_REG_INTSTS);
        status = ops->read8(ops->context, streamBase + HDA_CORE_SD_STS);
        relevant = status & HDA_INTERRUPT_STREAM_STATUS_MASK;
        result->intsts = intsts;
        result->streamStatus |= relevant;
        result->passes = pass + 1U;
        if (relevant != 0) {
            ops->write8(ops->context, streamBase + HDA_CORE_SD_STS,
                        relevant);
            result->handled = 1;
            if ((relevant & HDA_INTERRUPT_STREAM_BCIS) != 0)
                result->completion = 1;
            result->errors |= relevant &
                (HDA_INTERRUPT_STREAM_FIFOE | HDA_INTERRUPT_STREAM_DESE);
            continue;
        }
        if ((intsts & outputInterruptMask) == 0)
            return 1;
        /* INTSTS is status, never an acknowledgement target. */
        return 1;
    }
    result->exhausted = 1;
    return 1;
}
