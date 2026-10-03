#include "helper_monitor.h"

int VCRestoreNetworkBeforeStoppingHelpers(int proxyEnabled, int pfEnabled, const VCNetworkRestoreOperations *operations) {
    if (operations->restoreDNS() != 0 || operations->restoreRoutes() != 0) {
        operations->error("failed to restore iOS 5 DNS/routes; keeping VPN helpers alive");
        return -1;
    }

    if (proxyEnabled && operations->restoreProxy() != 0) {
        operations->error("failed to restore system PAC settings; keeping VPN helpers alive");
        operations->event("PAC restore failed; disconnect postponed");
        return -1;
    }

    if (pfEnabled) {
        if (operations->clearPF() != 0) {
            operations->error("failed to clear PF rules; keeping VPN helpers alive");
            operations->event("PF cleanup failed; disconnect postponed");
            return -1;
        }
    }
    return 0;
}

int VCMonitorHelpers(int connected, pid_t *core, pid_t *redsocks, pid_t *dns, const VCHelperMonitorOperations *operations) {
    if (!connected) return 0;
    int core_healthy = operations->running(core, "vless-core");
    int redsocks_healthy = operations->running(redsocks, "redsocks");
    int dns_healthy = operations->running(dns, "dns proxy");
    int healthy = core_healthy && redsocks_healthy && dns_healthy;
    if (!healthy) {
        if (!core_healthy) operations->event("Core helper stopped unexpectedly");
        if (!redsocks_healthy) operations->event("Traffic redirector stopped unexpectedly");
        if (!dns_healthy) operations->event("DNS helper stopped unexpectedly");
        operations->error("VPN helper exited unexpectedly; restoring PAC settings and clearing PF rules");
        if (operations->disconnect() != 0) operations->warning("VPN cleanup will be retried while system proxy restoration is pending");
        return 0;
    }
    return 1;
}
