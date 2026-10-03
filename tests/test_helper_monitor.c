#include "../common/helper_monitor.h"
#include "check.h"
static unsigned fail_mask, calls, events, errors, warnings, cleanups;
static int cleanup_failure;
static int running(pid_t *pid, const char *name) { (void)name; unsigned bit = 1U << calls++; if (fail_mask & bit) { *pid = 0; return 0; } return 1; }
static void event(const char *format, ...) { (void)format; events++; }
static void error(const char *format, ...) { (void)format; errors++; }
static void warning(const char *format, ...) { (void)format; warnings++; }
static int disconnect(void) { cleanups++; return cleanup_failure ? -1 : 0; }
static unsigned restore_failure, restore_count;
static unsigned restore_order[4];
static int restore(unsigned step) { restore_order[restore_count++] = step; return restore_failure == step ? -1 : 0; }
static int restoreDNS(void) { return restore(1); }
static int restoreRoutes(void) { return restore(2); }
static int restoreProxy(void) { return restore(3); }
static int clearPF(void) { return restore(4); }

static void restoreTests(void) {
    VCNetworkRestoreOperations operations = {restoreDNS, restoreRoutes, restoreProxy, clearPF, event, error};
    for (unsigned proxy = 0; proxy < 2; proxy++) {
        for (unsigned pf = 0; pf < 2; pf++) {
            for (unsigned failure = 0; failure <= 4; failure++) {
                restore_failure = failure;
                restore_count = events = errors = 0;
                int expected_failure = failure == 1 || failure == 2 || (failure == 3 && proxy) || (failure == 4 && pf);
                CHECK("restore/failure-at-every-active-step", (VCRestoreNetworkBeforeStoppingHelpers(proxy, pf, &operations) != 0) == expected_failure);
                unsigned expected_order[4] = {1, 2, 3, 4};
                unsigned expected_count = 0;
                for (unsigned step = 1; step <= 4; step++) {
                    if ((step == 3 && !proxy) || (step == 4 && !pf)) continue;
                    expected_order[expected_count++] = step;
                    if (failure == step) break;
                }
                CHECK("restore/short-circuit-before-stopping-helpers", restore_count == expected_count);
                for (unsigned i = 0; i < restore_count; i++)
                    CHECK("restore/dns-routes-proxy-pf-order", restore_order[i] == expected_order[i]);
                CHECK("restore/error-report", errors == (unsigned)expected_failure);
                CHECK("restore/pac-pf-failure-diagnosed", events == (unsigned)(expected_failure && failure >= 3));
            }
        }
    }
    restore_failure = restore_count = events = errors = 0;
    CHECK("restore/retry-succeeds", VCRestoreNetworkBeforeStoppingHelpers(1, 1, &operations) == 0 && restore_count == 4);
}
int main(void) {
    VCHelperMonitorOperations operations = {running, event, error, warning, disconnect}; pid_t core = 1, redir = 2, dns = 3;
    CHECK("helpers/disconnected-session-not-polled", !VCMonitorHelpers(0, &core, &redir, &dns, &operations) && calls == 0);
    CHECK("helpers/healthy-session", VCMonitorHelpers(1, &core, &redir, &dns, &operations) && cleanups == 0);
    for (unsigned mask = 1; mask < 8; mask++) for (unsigned failure = 0; failure < 2; failure++) {
        fail_mask = mask; cleanup_failure = failure; calls = events = errors = warnings = cleanups = 0;
        CHECK("helpers/every-helper-failure-disconnects", !VCMonitorHelpers(1, &core, &redir, &dns, &operations) && cleanups == 1 && errors == 1 && calls == 3);
        CHECK("helpers/cleanup-failure-reported-for-retry", warnings == failure);
        unsigned expected = !!(mask & 1) + !!(mask & 2) + !!(mask & 4);
        CHECK("helpers/failed-components-diagnosed", events == expected);
    }
    restoreTests();
    FINISH("helper failure recovery"); return 0;
}
