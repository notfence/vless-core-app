#ifndef VC_QR_HOST_GRAPHICS_H
#define VC_QR_HOST_GRAPHICS_H
#import <Foundation/Foundation.h>
#include <sys/types.h>
#import <CoreFoundation/CoreFoundation.h>
typedef id CGDataProviderRef;
typedef id CGImageRef;
typedef void *CGContextRef;
typedef void *CGColorSpaceRef;
typedef struct { double x,y,width,height; } CGRect;
static inline CGRect CGRectMake(double x,double y,double w,double h) { return (CGRect){x,y,w,h}; }
static inline double CGRectGetMinX(CGRect rect) { return rect.x; }
static inline double CGRectGetMaxY(CGRect rect) { return rect.y+rect.height; }
typedef struct { unsigned version; const void *(*getBytePointer)(void *); void (*releaseBytePointer)(void *,const void *); size_t (*getBytesAtPosition)(void *,void *,off_t,size_t); void (*releaseInfo)(void *); } CGDataProviderDirectCallbacks;
typedef unsigned CGImageAlphaInfo;
enum { kCGImageAlphaNone=0,kCGImageAlphaPremultipliedLast=1,kCGImageAlphaNoneSkipLast=5,kCGImageAlphaNoneSkipFirst=6 };
CGDataProviderRef CGDataProviderCreateDirect(void *,off_t,const CGDataProviderDirectCallbacks *);
void CGDataProviderRelease(CGDataProviderRef);
size_t CGImageGetWidth(CGImageRef);
size_t CGImageGetHeight(CGImageRef);
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef);
void CGImageRelease(CGImageRef);
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void);
void CGColorSpaceRelease(CGColorSpaceRef);
CGContextRef CGBitmapContextCreate(void *,size_t,size_t,size_t,size_t,CGColorSpaceRef,unsigned);
CGImageRef CGBitmapContextCreateImage(CGContextRef);
void CGContextSetGrayFillColor(CGContextRef,double,double);
void CGContextFillRect(CGContextRef,CGRect);
void CGContextDrawImage(CGContextRef,CGRect,CGImageRef);
void CGContextRelease(CGContextRef);
#endif
