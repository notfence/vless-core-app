#ifndef VC_CORE_CONFIG_H
#define VC_CORE_CONFIG_H
#include <stdint.h>
#include <stddef.h>

typedef struct { char primary[512], download[512], bypass[512]; } VCCoreAddresses;
typedef struct {
    uint64_t (*now)(void *);
    int (*inspect)(void *, const char *, uint64_t, char *, size_t);
    int (*resolve)(void *, const char *, uint64_t, char *, size_t);
    void *context;
} VCCorePrepareOperations;

uint64_t vc_core_now_ms(void);
int vc_core_prepare(const char *, const VCCorePrepareOperations *, VCCoreAddresses *, char *, size_t);
int vc_core_inspect_run(const char *, const char *, char *const *, int, uint64_t,
                        int (*)(void *), void *, char *, size_t);
#endif
