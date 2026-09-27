#ifndef INTEL_HDA_MSI_PCI_H
#define INTEL_HDA_MSI_PCI_H

#define HDA_PCI_CONFIG_DWORDS       64U
#define HDA_PCI_STATUS_CAP_LIST     0x0010U
#define HDA_PCI_CAP_POINTER         0x34U
#define HDA_PCI_CAP_MIN             0x40U
#define HDA_PCI_CAP_MAX             0xfcU
#define HDA_PCI_CAP_MSI             0x05U
#define HDA_PCI_CAP_MSIX            0x11U

#define HDA_MSI_CONTROL_ENABLE      0x0001U
#define HDA_MSI_CONTROL_MMC_MASK    0x000eU
#define HDA_MSI_CONTROL_MME_MASK    0x0070U
#define HDA_MSI_CONTROL_64BIT       0x0080U
#define HDA_MSI_CONTROL_PVM         0x0100U

#define HDA_MSIX_CONTROL_FUNCTION_MASK 0x4000U
#define HDA_MSIX_CONTROL_ENABLE        0x8000U

#define HDA_PCI_COMMAND_INT_DISABLE 0x0400U

#define HDA_PCI_CAPS_OK             0
#define HDA_PCI_CAPS_NO_LIST        1
#define HDA_PCI_CAPS_BAD_HEADER    -1
#define HDA_PCI_CAPS_BAD_POINTER   -2
#define HDA_PCI_CAPS_LOOP          -3
#define HDA_PCI_CAPS_BAD_ENTRY     -4
#define HDA_PCI_CAPS_BAD_LAYOUT    -5

typedef struct IntelHDAPCIInterruptCapabilities {
    unsigned msiFound;
    unsigned msiOffset;
    unsigned msiControl;
    unsigned msixFound;
    unsigned msixOffset;
    unsigned msixControl;
} IntelHDAPCIInterruptCapabilities;

typedef struct IntelHDAMSILayout {
    unsigned capabilityOffset;
    unsigned control;
    unsigned addressLowOffset;
    unsigned addressHighOffset;
    unsigned dataOffset;
    unsigned maskOffset;
    unsigned lastOffset;
    unsigned is64Bit;
    unsigned hasPerVectorMask;
} IntelHDAMSILayout;

int IntelHDAPCIDecodeCapabilities(
    const unsigned config[HDA_PCI_CONFIG_DWORDS],
    IntelHDAPCIInterruptCapabilities *capabilities);
int IntelHDAMSIBuildLayout(unsigned capabilityOffset, unsigned control,
                           IntelHDAMSILayout *layout);
unsigned IntelHDAMSIControlDword(unsigned capabilityDword, int enabled);
int IntelHDAMSIControlIsState(unsigned capabilityDword, int enabled);
unsigned IntelHDAMSIXDisabledControlDword(unsigned capabilityDword);
int IntelHDAMSIXControlIsDisabled(unsigned capabilityDword);
unsigned IntelHDAMSIMessageDataDword(unsigned oldDword, unsigned data);
unsigned IntelHDAMSIPerVectorMaskDword(unsigned oldDword, int masked);
unsigned IntelHDAPCICommandWithINTxDisabled(unsigned commandDword);
int IntelHDAPCICommandHasINTxDisabled(unsigned commandDword);
int IntelHDAMSIMessageMatches(
    const unsigned config[HDA_PCI_CONFIG_DWORDS],
    const IntelHDAMSILayout *layout, unsigned addressLow,
    unsigned addressHigh, unsigned data);
int IntelHDAPCIMSIMessageIsValid(unsigned vector, unsigned addressLow,
                                 unsigned addressHigh, unsigned data,
                                 unsigned firstVector, unsigned lastVector,
                                 unsigned addressBase);

#endif
