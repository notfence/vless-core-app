#import <CoreGraphics/CoreGraphics.h>
typedef id CGImageSourceRef;
typedef int CGImageSourceStatus;
enum { kCGImageStatusComplete=0,kCGImageStatusIncomplete=-1,kCGImageStatusReadingHeader=-2,kCGImageStatusUnknownType=-3,kCGImageStatusInvalidData=-4,kCGImageStatusUnexpectedEOF=-5 };
int CGImageSourceGetStatus(CGImageSourceRef);
int CGImageSourceGetStatusAtIndex(CGImageSourceRef,size_t);
#define kCGImageSourceShouldCache @"cache"
#define kCGImagePropertyPixelWidth @"width"
#define kCGImagePropertyPixelHeight @"height"
#define kCGImageSourceCreateThumbnailFromImageAlways @"fromImage"
#define kCGImageSourceCreateThumbnailWithTransform @"transform"
#define kCGImageSourceThumbnailMaxPixelSize @"maximum"
CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef,CFDictionaryRef);
CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef,size_t,CFDictionaryRef);
CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef,size_t,CFDictionaryRef);
