#ifndef VC_QR_PHOTO_H
#define VC_QR_PHOTO_H
#include <stddef.h>
#include <stdint.h>
typedef struct { char *text; size_t length; int x,y; } VCQRPhotoEntry;
typedef struct { VCQRPhotoEntry *entries; size_t count; } VCQRPhotoResult;
typedef enum { VCQRPhotoOK,VCQRPhotoEmpty,VCQRPhotoCancelled,VCQRPhotoInvalid,VCQRPhotoMemory } VCQRPhotoStatus;
typedef int (*VCQRPhotoCancellation)(void *);
VCQRPhotoStatus VCQRPhotoDecode(const uint8_t *,size_t,size_t,size_t,VCQRPhotoCancellation,void *,VCQRPhotoResult *);
void VCQRPhotoResultClear(VCQRPhotoResult *);
#endif
