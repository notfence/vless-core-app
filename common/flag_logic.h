#ifndef VC_FLAG_LOGIC_H
#define VC_FLAG_LOGIC_H
#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t codepoints[8];
    uint8_t count;
    const char *asset;
} VCFlagSequence;

typedef struct {
    size_t location;
    size_t length;
    const char *asset;
} VCFlagMatch;

size_t VCFlagSequenceCount(void);
const VCFlagSequence *VCFlagSequenceAt(size_t index);
int VCFlagNext(const uint16_t *text, size_t length, size_t *cursor, VCFlagMatch *match);
#endif
