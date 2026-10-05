/* List cached hardware readbacks, or request a live route and await commit. */
#import <driverkit/IODeviceMaster.h>
#import <driverkit/driverTypes.h>
#import <driverkit/return.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern unsigned int sleep(unsigned int);
#include "IntelHDARouteStatus.h"

static int readRoutes(id master, IOObjectNumber number, unsigned *v) {
    unsigned count = HDA_ROUTE_STATUS_MAX;
    IOReturn result = [master getIntValues:v forParameter:INTEL_HDA_ROUTES_PARAMETER
                            objectNumber:number count:&count];
    if (result || count < HDA_ROUTE_HEADER || v[HDA_RS_SCHEMA] != INTEL_HDA_ROUTE_SCHEMA ||
        v[HDA_RS_COUNT] > 16 || count != HDA_ROUTE_HEADER + v[HDA_RS_COUNT] * HDA_ROUTE_ROW) {
        fprintf(stderr, "Live routing unavailable (result %d); requires the routing driver.\n", result);
        return 0;
    }
    return 1;
}
int main(int argc, char **argv) {
    id master;
    IOObjectNumber number;
    IOString kind;
    unsigned v[HDA_ROUTE_STATUS_MAX], pin = 0, request, i, *r;
    unsigned long parsed;
    int result = 0;
    char *end;
    if (argc > 2) { fprintf(stderr, "usage: intelhda-route [auto|PIN]\n"); return 2; }
    if (argc == 2 && strcmp(argv[1], "auto")) {
        parsed = strtoul(argv[1], &end, 0);
        if (!argv[1][0] || *end || parsed < 1 || parsed > 127) return 2;
        pin = parsed;
    }
    master = [IODeviceMaster new];
    if (!master) return 1;
    if ([master lookUpByDeviceName:"IntelHDA" objectNumber:&number deviceKind:&kind] ||
        !readRoutes(master, number, v)) { [master free]; return 1; }
    if (argc == 2) {
        request = v[HDA_RS_REQUEST] + 1U;
        if ([master setIntValues:&pin forParameter:INTEL_HDA_ROUTE_PARAMETER
                   objectNumber:number count:1]) {
            fprintf(stderr, "Route request rejected (invalid pin, busy, or driver unavailable).\n");
            [master free]; return 1;
        }
        for (i = 0; i < 8; i++) {
            sleep(1);
            if (!readRoutes(master, number, v)) { result = 1; break; }
            if (v[HDA_RS_COMPLETED] == request) break;
        }
        if (v[HDA_RS_COMPLETED] != request || v[HDA_RS_RESULT] != 1 ||
            v[HDA_RS_APPLIED_PIN] != pin || (pin && v[HDA_RS_ACTIVE_PIN] != pin)) {
            fprintf(stderr, "Route did not commit; inspect failure/rollback counters.\n"); result = 1;
        }
    }
    printf("policy requested 0x%x applied 0x%x (0=auto), active pin 0x%x, request %u completed %u result %d\n",
        v[HDA_RS_REQUESTED_PIN], v[HDA_RS_APPLIED_PIN], v[HDA_RS_ACTIVE_PIN],
        v[HDA_RS_REQUEST], v[HDA_RS_COMPLETED], (int)v[HDA_RS_RESULT]);
    printf("changes %u failures %u rollbacks %u unsafe %u sense errors %u\n",
        v[HDA_RS_CHANGES], v[HDA_RS_FAILURES], v[HDA_RS_ROLLBACKS], v[HDA_RS_UNSAFE], v[HDA_RS_SENSE_ERRORS]);
    printf("hardware readback valid %u tick %u, running %u format 0x%04x mute %u attenuation %d/%d\n",
        v[HDA_RS_READ_OK], v[HDA_RS_READ_TICK], v[HDA_RS_RUNNING], v[HDA_RS_FORMAT],
        v[HDA_RS_MUTE], (int)v[HDA_RS_LEFT], (int)v[HDA_RS_RIGHT]);
    for (i = 0; i < v[HDA_RS_COUNT]; i++) {
        r = &v[HDA_ROUTE_HEADER + i * HDA_ROUTE_ROW];
        printf("pin 0x%02x DAC 0x%02x %s detectable %u present %d sense %08x control %02x "
               "format %04x stream/channel %02x EAPD %08x amp 0x%x L/R %02x/%02x rates %04x\n",
            r[HDA_RR_PIN], r[HDA_RR_DAC], r[HDA_RR_DEVICE] == 2 ? "headphone" :
            r[HDA_RR_DEVICE] == 1 ? "speaker" : "line-out", r[HDA_RR_DETECTABLE],
            (int)r[HDA_RR_PRESENT], r[HDA_RR_SENSE], r[HDA_RR_CONTROL], r[HDA_RR_FORMAT],
            r[HDA_RR_CHANNEL], r[HDA_RR_EAPD], r[HDA_RR_VOLUME_NID],
            r[HDA_RR_AMP_LEFT], r[HDA_RR_AMP_RIGHT], r[HDA_RR_RATES]);
        printf("  mute amp 0x%x L/R %02x/%02x\n", r[HDA_RR_MUTE_NID], r[HDA_RR_MUTE_LEFT], r[HDA_RR_MUTE_RIGHT]);
    }
    if (!v[HDA_RS_READ_OK] || v[HDA_RS_UNSAFE]) result = 1;
    [master free];
    return result;
}
