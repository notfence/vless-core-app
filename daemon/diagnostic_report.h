#ifndef VC_DIAGNOSTIC_REPORT_H
#define VC_DIAGNOSTIC_REPORT_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint64_t tokens[128];
    size_t count;
} VCDiagnosticPFNames;

int VCDiagnosticEncodeLog(const char *source, size_t length, char *output, size_t capacity);
const char *VCDiagnosticPFText(VCDiagnosticPFNames *names, const char *source, char *output, size_t capacity);

#endif
