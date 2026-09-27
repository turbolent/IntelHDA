#include "IntelHDAMSIPCI.h"

static void
clearCapabilities(IntelHDAPCIInterruptCapabilities *capabilities)
{
    capabilities->msiFound = 0;
    capabilities->msiOffset = 0;
    capabilities->msiControl = 0;
    capabilities->msixFound = 0;
    capabilities->msixOffset = 0;
    capabilities->msixControl = 0;
}

int
IntelHDAMSIBuildLayout(unsigned capabilityOffset, unsigned control,
                       IntelHDAMSILayout *layout)
{
    if (layout == 0 || capabilityOffset < HDA_PCI_CAP_MIN ||
        capabilityOffset > HDA_PCI_CAP_MAX ||
        (capabilityOffset & 3U) != 0)
        return 0;
    layout->capabilityOffset = capabilityOffset;
    layout->control = control;
    layout->is64Bit = (control & HDA_MSI_CONTROL_64BIT) != 0;
    layout->hasPerVectorMask = (control & HDA_MSI_CONTROL_PVM) != 0;
    layout->addressLowOffset = capabilityOffset + 4U;
    layout->addressHighOffset = layout->is64Bit ?
                                capabilityOffset + 8U : 0;
    layout->dataOffset = capabilityOffset +
                         (layout->is64Bit ? 12U : 8U);
    layout->maskOffset = layout->hasPerVectorMask ?
                         capabilityOffset +
                         (layout->is64Bit ? 16U : 12U) : 0;
    /* Per-vector masking is followed by a read-only pending-bits dword. */
    layout->lastOffset = layout->hasPerVectorMask ? layout->maskOffset + 4U :
                         layout->dataOffset;
    return layout->lastOffset <= HDA_PCI_CAP_MAX;
}

int
IntelHDAPCIDecodeCapabilities(
    const unsigned config[HDA_PCI_CONFIG_DWORDS],
    IntelHDAPCIInterruptCapabilities *capabilities)
{
    unsigned visited[2];
    unsigned offsets[48];
    unsigned offsetCount;
    unsigned status;
    unsigned headerType;
    unsigned offset;
    unsigned slot;
    unsigned entry;
    unsigned capabilityID;
    unsigned next;
    unsigned iterations;
    unsigned i;
    unsigned firstBody;
    unsigned lastBody;
    IntelHDAMSILayout layout;

    if (config == 0 || capabilities == 0)
        return HDA_PCI_CAPS_BAD_ENTRY;
    clearCapabilities(capabilities);
    status = (config[1] >> 16) & 0xffffU;
    if ((status & HDA_PCI_STATUS_CAP_LIST) == 0)
        return HDA_PCI_CAPS_NO_LIST;
    headerType = (config[3] >> 16) & 0xffU;
    if ((headerType & 0x7fU) != 0)
        return HDA_PCI_CAPS_BAD_HEADER;

    offset = config[HDA_PCI_CAP_POINTER / 4U] & 0xffU;
    visited[0] = 0;
    visited[1] = 0;
    offsetCount = 0;
    for (iterations = 0; iterations < 48U; iterations++) {
        if (offset < HDA_PCI_CAP_MIN || offset > HDA_PCI_CAP_MAX ||
            (offset & 3U) != 0)
            return HDA_PCI_CAPS_BAD_POINTER;
        slot = offset / 4U;
        if ((visited[slot / 32U] & (1U << (slot & 31U))) != 0)
            return HDA_PCI_CAPS_LOOP;
        visited[slot / 32U] |= 1U << (slot & 31U);
        offsets[offsetCount++] = offset;

        entry = config[slot];
        if (entry == 0xffffffffU)
            return HDA_PCI_CAPS_BAD_ENTRY;
        capabilityID = entry & 0xffU;
        next = (entry >> 8) & 0xffU;
        if (capabilityID == 0 || capabilityID == 0xffU)
            return HDA_PCI_CAPS_BAD_ENTRY;
        if (capabilityID == HDA_PCI_CAP_MSI) {
            if (capabilities->msiFound)
                return HDA_PCI_CAPS_BAD_ENTRY;
            capabilities->msiFound = 1;
            capabilities->msiOffset = offset;
            capabilities->msiControl = (entry >> 16) & 0xffffU;
        } else if (capabilityID == HDA_PCI_CAP_MSIX) {
            if (capabilities->msixFound)
                return HDA_PCI_CAPS_BAD_ENTRY;
            capabilities->msixFound = 1;
            capabilities->msixOffset = offset;
            capabilities->msixControl = (entry >> 16) & 0xffffU;
        }
        if (next == 0)
            break;
        offset = next;
    }
    if (iterations == 48U)
        return HDA_PCI_CAPS_LOOP;

    if (capabilities->msiFound) {
        if (!IntelHDAMSIBuildLayout(capabilities->msiOffset,
                                    capabilities->msiControl, &layout))
            return HDA_PCI_CAPS_BAD_LAYOUT;
        firstBody = capabilities->msiOffset + 4U;
        lastBody = layout.lastOffset;
        for (i = 0; i < offsetCount; i++) {
            if (offsets[i] >= firstBody && offsets[i] <= lastBody)
                return HDA_PCI_CAPS_BAD_LAYOUT;
        }
    }
    if (capabilities->msixFound) {
        if (capabilities->msixOffset > HDA_PCI_CAP_MAX - 8U)
            return HDA_PCI_CAPS_BAD_LAYOUT;
        firstBody = capabilities->msixOffset + 4U;
        lastBody = capabilities->msixOffset + 8U;
        for (i = 0; i < offsetCount; i++) {
            if (offsets[i] >= firstBody && offsets[i] <= lastBody)
                return HDA_PCI_CAPS_BAD_LAYOUT;
        }
    }
    return HDA_PCI_CAPS_OK;
}

unsigned
IntelHDAMSIControlDword(unsigned capabilityDword, int enabled)
{
    unsigned control;

    control = (capabilityDword >> 16) & 0xffffU;
    control &= ~(HDA_MSI_CONTROL_ENABLE | HDA_MSI_CONTROL_MME_MASK);
    if (enabled)
        control |= HDA_MSI_CONTROL_ENABLE;
    return (capabilityDword & 0x0000ffffU) | (control << 16);
}

int
IntelHDAMSIControlIsState(unsigned capabilityDword, int enabled)
{
    unsigned control;

    control = (capabilityDword >> 16) & 0xffffU;
    if ((control & HDA_MSI_CONTROL_MME_MASK) != 0)
        return 0;
    return ((control & HDA_MSI_CONTROL_ENABLE) != 0) == (enabled != 0);
}

unsigned
IntelHDAMSIXDisabledControlDword(unsigned capabilityDword)
{
    unsigned control;

    control = (capabilityDword >> 16) & 0xffffU;
    control |= HDA_MSIX_CONTROL_FUNCTION_MASK;
    control &= ~HDA_MSIX_CONTROL_ENABLE;
    return (capabilityDword & 0x0000ffffU) | (control << 16);
}

int
IntelHDAMSIXControlIsDisabled(unsigned capabilityDword)
{
    unsigned control;

    control = (capabilityDword >> 16) & 0xffffU;
    return (control & HDA_MSIX_CONTROL_ENABLE) == 0 &&
           (control & HDA_MSIX_CONTROL_FUNCTION_MASK) != 0;
}

unsigned
IntelHDAMSIMessageDataDword(unsigned oldDword, unsigned data)
{
    return (oldDword & 0xffff0000U) | (data & 0xffffU);
}

unsigned
IntelHDAMSIPerVectorMaskDword(unsigned oldDword, int masked)
{
    if (masked)
        return oldDword | 1U;
    return oldDword & ~1U;
}

unsigned
IntelHDAPCICommandWithINTxDisabled(unsigned commandDword)
{
    /* PCI Status is W1C.  Preserve Command only and write zero to Status. */
    return (commandDword & 0xffffU) | HDA_PCI_COMMAND_INT_DISABLE;
}

int
IntelHDAPCICommandHasINTxDisabled(unsigned commandDword)
{
    return (commandDword & HDA_PCI_COMMAND_INT_DISABLE) != 0;
}

int
IntelHDAMSIMessageMatches(
    const unsigned config[HDA_PCI_CONFIG_DWORDS],
    const IntelHDAMSILayout *layout, unsigned addressLow,
    unsigned addressHigh, unsigned data)
{
    if (config == 0 || layout == 0)
        return 0;
    if (config[layout->addressLowOffset / 4U] != addressLow)
        return 0;
    if (layout->is64Bit &&
        config[layout->addressHighOffset / 4U] != addressHigh)
        return 0;
    return (config[layout->dataOffset / 4U] & 0xffffU) ==
           (data & 0xffffU);
}

int
IntelHDAPCIMSIMessageIsValid(unsigned vector, unsigned addressLow,
                             unsigned addressHigh, unsigned data,
                             unsigned firstVector, unsigned lastVector,
                             unsigned addressBase)
{
    if (vector < firstVector || vector > lastVector)
        return 0;
    if ((addressLow & 0xfff00fffU) != addressBase || addressHigh != 0)
        return 0;
    if ((data & ~0xffffU) != 0 || data != vector)
        return 0;
    return 1;
}
