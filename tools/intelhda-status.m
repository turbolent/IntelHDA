#import <driverkit/IODeviceMaster.h>
#import <driverkit/driverTypes.h>
#import <driverkit/return.h>
#import <stdio.h>
#import "IntelHDAStats.h"

static const char *modeName(unsigned mode) {
    if (mode == INTEL_HDA_MODE_MSI)
        return "conventional MSI";
    if (mode == INTEL_HDA_MODE_POLLING)
        return "explicit Polling";
    return "unknown";
}

int main(int argc, char **argv) {
    IODeviceMaster *master;
    IOObjectNumber objectNumber;
    IOString deviceKind;
    unsigned values[INTEL_HDA_STATS_COUNT];
    unsigned count;
    IOReturn result;
    const char *deviceName;

    deviceName = argc > 1 ? argv[1] : "IntelHDA";
    master = [IODeviceMaster new];
    if (master == nil)
        return 1;
    result = [master lookUpByDeviceName:(char *)deviceName
                           objectNumber:&objectNumber
                             deviceKind:&deviceKind];
    if (result != IO_R_SUCCESS) {
        fprintf(stderr, "%s lookup failed (%d)\n", deviceName, result);
        [master free];
        return 1;
    }
    count = INTEL_HDA_STATS_COUNT;
    result = [master getIntValues:values
                      forParameter:INTEL_HDA_STATS_PARAMETER
                      objectNumber:objectNumber count:&count];
    if (result != IO_R_SUCCESS || count != INTEL_HDA_STATS_COUNT ||
        values[INTEL_HDA_STAT_SCHEMA] != INTEL_HDA_STATS_SCHEMA_VERSION) {
        fprintf(stderr, "IntelHDA interrupt statistics unavailable\n");
        [master free];
        return 1;
    }
    printf("mode %s, running %u, firmware IRQ %u\n",
           modeName(values[INTEL_HDA_STAT_MODE]),
           values[INTEL_HDA_STAT_RUNNING],
           values[INTEL_HDA_STAT_FIRMWARE_INTERRUPT_LINE]);
    printf("MSI vector 0x%02x, MSI cap 0x%02x, MSI-X cap 0x%02x, "
           "allocated %u enabled %u active %u\n",
           values[INTEL_HDA_STAT_MSI_VECTOR],
           values[INTEL_HDA_STAT_MSI_CAP],
           values[INTEL_HDA_STAT_MSIX_CAP],
           values[INTEL_HDA_STAT_MSI_ALLOCATED],
           values[INTEL_HDA_STAT_MSI_ENABLED],
           values[INTEL_HDA_STAT_MSI_ACTIVE]);
    printf("notifications %u\n", values[INTEL_HDA_STAT_NOTIFICATIONS]);
    printf("service passes %u\n", values[INTEL_HDA_STAT_SERVICE_PASSES]);
    printf("consumes %u\n", values[INTEL_HDA_STAT_CONSUMES]);
    printf("acknowledgments %u\n", values[INTEL_HDA_STAT_ACKNOWLEDGMENTS]);
    printf("consumed messages %u\n", values[INTEL_HDA_STAT_CONSUMED_MESSAGES]);
    printf("epoch failures %u\n", values[INTEL_HDA_STAT_EPOCH_FAILURES]);
    printf("gate result %u\n", values[INTEL_HDA_STAT_GATE_RESULT]);
    printf("completed periods %u\n", values[INTEL_HDA_STAT_COMPLETED_PERIODS]);
    printf("stream errors %u\n", values[INTEL_HDA_STAT_STREAM_ERRORS]);
    printf("ignored messages %u\n", values[INTEL_HDA_STAT_IGNORED_MESSAGES]);
    printf("quarantined %u\n", values[INTEL_HDA_STAT_QUARANTINED]);
    printf("poll ticks %u\n", values[INTEL_HDA_STAT_POLL_TICKS]);
    printf("poll completions %u\n", values[INTEL_HDA_STAT_POLL_COMPLETIONS]);
    printf("prompt requested %u\n", values[INTEL_HDA_STAT_PROMPT_REQUESTED]);
    printf("prompt active %u\n", values[INTEL_HDA_STAT_PROMPT_ACTIVE]);
    printf("prompt result %u\n", values[INTEL_HDA_STAT_PROMPT_RESULT]);
    printf("reboot required %u\n", values[INTEL_HDA_STAT_REBOOT_REQUIRED]);
    printf("disable failures %u\n", values[INTEL_HDA_STAT_DISABLE_FAILURES]);
    printf("release failures %u\n", values[INTEL_HDA_STAT_RELEASE_FAILURES]);
    printf("PCI %04x:%04x codec %08x pin 0x%x DAC 0x%x\n",
           values[INTEL_HDA_STAT_PCI_ID] & 0xffffU,
           values[INTEL_HDA_STAT_PCI_ID] >> 16,
           values[INTEL_HDA_STAT_CODEC_ID], values[INTEL_HDA_STAT_PIN],
           values[INTEL_HDA_STAT_DAC]);
    printf("DMA bytes %u period bytes %u INTCTL 0x%08x\n",
           values[INTEL_HDA_STAT_DMA_BYTES], values[INTEL_HDA_STAT_PERIOD_BYTES],
           values[INTEL_HDA_STAT_INTCTL]);
    printf("PCI command 0x%04x MSI control 0x%04x MSI-X control 0x%04x\n",
           values[INTEL_HDA_STAT_PCI_COMMAND], values[INTEL_HDA_STAT_MSI_CONTROL],
           values[INTEL_HDA_STAT_MSIX_CONTROL]);
    [master free];
    return 0;
}
