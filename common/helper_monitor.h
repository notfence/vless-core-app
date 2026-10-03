#ifndef VC_HELPER_MONITOR_H
#define VC_HELPER_MONITOR_H
#include <sys/types.h>
typedef struct {
    int (*running)(pid_t *, const char *);
    void (*event)(const char *, ...);
    void (*error)(const char *, ...);
    void (*warning)(const char *, ...);
    int (*disconnect)(void);
} VCHelperMonitorOperations;
typedef struct {
    int (*restoreDNS)(void);
    int (*restoreRoutes)(void);
    int (*restoreProxy)(void);
    int (*clearPF)(void);
    void (*event)(const char *, ...);
    void (*error)(const char *, ...);
} VCNetworkRestoreOperations;
int VCMonitorHelpers(int connected, pid_t *core, pid_t *redsocks, pid_t *dns, const VCHelperMonitorOperations *operations);
int VCRestoreNetworkBeforeStoppingHelpers(int proxyEnabled, int pfEnabled, const VCNetworkRestoreOperations *operations);
#endif
