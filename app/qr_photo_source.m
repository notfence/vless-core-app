#import "qr_photo_source.h"
#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 110000
#import <Vision/Vision.h>
#else
#include "../common/qr_photo.h"
#endif
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <math.h>
#include <stdlib.h>

@interface VCQRAssetRequest : NSObject {
@public NSCondition *condition; ALAssetRepresentation *representation; BOOL done;
}
@end
@implementation VCQRAssetRequest
- (id)init { if ((self=[super init])) condition=[[NSCondition alloc] init]; return self; }
- (void)dealloc { [condition release]; [representation release]; [super dealloc]; }
@end

typedef struct { int fd; ALAssetRepresentation *asset; ALAssetsLibrary *library; off_t length; NSOperation *operation; } VCQRPhotoSource;
static size_t photoRead(void *info,void *buffer,off_t offset,size_t count) {
    VCQRPhotoSource *source=info;
    if ([source->operation isCancelled] || offset<0 || offset>=source->length) return 0;
    if (count>(uint64_t)(source->length-offset)) count=(size_t)(source->length-offset);
    if (source->asset) return [source->asset getBytes:buffer fromOffset:offset length:count error:NULL];
    ssize_t result;
    do { result=pread(source->fd,buffer,count,offset); } while (result<0 && errno==EINTR && ![source->operation isCancelled]);
    return result>0 ? (size_t)result : 0;
}
static void photoRelease(void *info) {
    VCQRPhotoSource *source=info;
    if (source->fd>=0) close(source->fd);
    [source->asset release]; [source->library release]; [source->operation release]; free(source);
}
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 110000
static NSComparisonResult photoNativeOrder(id left,id right,void *context) {
    (void)context;
    CGRect a=[left boundingBox],b=[right boundingBox];
    double ay=CGRectGetMaxY(a),by=CGRectGetMaxY(b),ax=CGRectGetMinX(a),bx=CGRectGetMinX(b);
    if (ay!=by) return ay>by ? NSOrderedAscending : NSOrderedDescending;
    return ax<bx ? NSOrderedAscending : ax>bx ? NSOrderedDescending : NSOrderedSame;
}
static NSArray *photoNativeTexts(CGImageRef image,NSOperation *operation,NSString **error) {
    if (error) *error=@"Unable to read QR codes from this photo";
    VNDetectBarcodesRequest *request=nil;
    VNImageRequestHandler *handler=nil;
    NSArray *requests=nil;
    CGContextRef context=NULL;
    CGImageRef prepared=image;
    uint8_t *gray=NULL;
    size_t w=CGImageGetWidth(image),h=CGImageGetHeight(image),total=0;
    NSMutableArray *texts=nil;
    CGImageAlphaInfo alpha=CGImageGetAlphaInfo(image);
    if ([operation isCancelled]) goto done;
    if (alpha!=kCGImageAlphaNone && alpha!=kCGImageAlphaNoneSkipFirst && alpha!=kCGImageAlphaNoneSkipLast) {
        gray=calloc(w,h);
        CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
        context=gray && space ? CGBitmapContextCreate(gray,w,h,8,w,space,kCGImageAlphaNone) : NULL;
        if (space) CGColorSpaceRelease(space);
        if (!context) goto done;
        CGContextSetGrayFillColor(context,1,1); CGContextFillRect(context,CGRectMake(0,0,w,h));
        CGContextDrawImage(context,CGRectMake(0,0,w,h),image);
        prepared=CGBitmapContextCreateImage(context);
        if (!prepared) goto done;
    }
    request=[[VNDetectBarcodesRequest alloc] init];
    if (!request) goto done;
    request.symbologies=@[VNBarcodeSymbologyQR]; request.preferBackgroundProcessing=YES;
    handler=[[VNImageRequestHandler alloc] initWithCGImage:prepared options:@{}];
    requests=[[NSArray alloc] initWithObjects:request,nil];
    if (!handler || !requests || [operation isCancelled] || ![handler performRequests:requests error:NULL] || [operation isCancelled]) goto done;
    NSMutableArray *observations=[NSMutableArray array];
    for (id value in request.results) {
        if ([operation isCancelled]) goto done;
        if (![value isKindOfClass:[VNBarcodeObservation class]] || ![[value symbology] isEqual:VNBarcodeSymbologyQR]) continue;
        NSString *text=[value payloadStringValue];
        if (![text isKindOfClass:[NSString class]] || ![text length]) continue;
        CGRect box=[value boundingBox];
        if (!isfinite(CGRectGetMinX(box)) || !isfinite(CGRectGetMaxY(box))) goto done;
        [observations addObject:value];
    }
    [observations sortUsingFunction:photoNativeOrder context:NULL];
    NSMutableSet *seen=[NSMutableSet set];
    texts=[NSMutableArray array];
    for (VNBarcodeObservation *value in observations) {
        if ([operation isCancelled]) { texts=nil; goto done; }
        NSString *text=value.payloadStringValue;
        if ([seen containsObject:text]) continue;
        NSUInteger length=[text lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (length>32U*1024U*1024U-total) { texts=nil; goto done; }
        total+=length; [seen addObject:text]; [texts addObject:text];
    }
    if (![texts count]) { texts=nil; if (error) *error=@"No QR codes found in this photo"; }
    else if (error) *error=nil;
done:
    [requests release]; [handler release]; [request release];
    if (prepared && prepared!=image) CGImageRelease(prepared);
    if (context) CGContextRelease(context);
    if (gray) { volatile uint8_t *clear=gray; for (size_t i=0;i<w*h;i++) clear[i]=0; free(gray); }
    return [operation isCancelled] ? nil : texts;
}
#else
static int photoCancelled(void *context) { return [(NSOperation *)context isCancelled]; }
#endif

NSArray *VCReadPhotoQR(NSURL *url,NSOperation *operation,NSString **error) {
    if (error) *error=@"Unable to read the selected photo";
    if (!url || [operation isCancelled]) { if (error) *error=@"Selected photo has no readable source"; return nil; }
    VCQRPhotoSource *input=calloc(1,sizeof(*input));
    if (!input) return nil;
    input->fd=-1; input->operation=[operation retain];
    if ([url isFileURL]) {
        input->fd=open([[url path] fileSystemRepresentation],O_RDONLY|O_NOFOLLOW);
        struct stat st;
        if (input->fd<0 || fstat(input->fd,&st)!=0 || !S_ISREG(st.st_mode)) { if (error) *error=@"Unable to open the selected photo file"; photoRelease(input); return nil; }
        input->length=st.st_size;
    } else if ([[[url scheme] lowercaseString] isEqual:@"assets-library"]) {
        VCQRAssetRequest *request=[[VCQRAssetRequest alloc] init];
        ALAssetsLibrary *library=[[ALAssetsLibrary alloc] init];
        input->library=library;
        [library assetForURL:url resultBlock:^(ALAsset *asset) {
            [request->condition lock];
            request->representation=[[asset defaultRepresentation] retain]; request->done=YES;
            [request->condition signal]; [request->condition unlock];
        } failureBlock:^(NSError *failure) {
            (void)failure; [request->condition lock]; request->done=YES;
            [request->condition signal]; [request->condition unlock];
        }];
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
        [request->condition lock];
        while (!request->done && ![operation isCancelled] && [deadline timeIntervalSinceNow]>0)
            [request->condition waitUntilDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        input->asset=[request->representation retain];
        [request->condition unlock];
        input->length=[input->asset size];
        [request release];
    }
    if (input->length>32LL*1024*1024) {
        if (error) *error=@"The selected photo exceeds 32 MiB. Choose a smaller image.";
        photoRelease(input); return nil;
    }
    if (input->length<=0 || [operation isCancelled]) { if (error) *error=@"Photo library did not provide image data"; photoRelease(input); return nil; }
    CGDataProviderDirectCallbacks callbacks={0,NULL,NULL,photoRead,photoRelease};
    CGDataProviderRef provider=CGDataProviderCreateDirect(input,input->length,&callbacks);
    if (!provider) { if (error) *error=@"Unable to create the photo data reader"; photoRelease(input); return nil; }
    NSDictionary *options=@{(id)kCGImageSourceShouldCache:@(NO)};
    CGImageSourceRef source=CGImageSourceCreateWithDataProvider(provider,(CFDictionaryRef)options);
    CGDataProviderRelease(provider);
    if (!source) { if (error) *error=@"Unable to open photo image data"; return nil; }
    NSDictionary *properties=(NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source,0,NULL);
    double width=[[properties objectForKey:(id)kCGImagePropertyPixelWidth] doubleValue];
    double height=[[properties objectForKey:(id)kCGImagePropertyPixelHeight] doubleValue];
    [properties release];
    if (!isfinite(width) || !isfinite(height) || width<1 || height<1 || width>32768 || height>32768 || width>100000000.0/height || [operation isCancelled]) {
        if (error) *error=@"Invalid or unsupported photo dimensions";
        CFRelease(source); return nil;
    }
    NSDictionary *thumbnailOptions=@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@(YES),(id)kCGImageSourceCreateThumbnailWithTransform:@(YES),
        (id)kCGImageSourceThumbnailMaxPixelSize:@2048,(id)kCGImageSourceShouldCache:@(NO)};
    CGImageRef image=CGImageSourceCreateThumbnailAtIndex(source,0,(CFDictionaryRef)thumbnailOptions);
    if (error) *error=@"Unable to decode the selected photo";
    CGImageSourceStatus sourceStatus=CGImageSourceGetStatus(source),frameStatus=CGImageSourceGetStatusAtIndex(source,0);
    if (image && (sourceStatus!=kCGImageStatusComplete || frameStatus<=kCGImageStatusUnknownType)) {
        if (error) *error=[NSString stringWithFormat:@"Unable to decode photo data (source %d, image %d)",(int)sourceStatus,(int)frameStatus];
        CGImageRelease(image); image=NULL;
    }
    CFRelease(source);
    if (!image) return nil;
    size_t w=CGImageGetWidth(image),h=CGImageGetHeight(image);
    if (!w || !h || w>2048 || h>2048 || [operation isCancelled]) { if (error) *error=@"Invalid photo preview dimensions"; CGImageRelease(image); return nil; }
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 110000
    NSArray *texts=photoNativeTexts(image,operation,error);
    CGImageRelease(image);
    return texts;
#else
    uint8_t *gray=calloc(w,h);
    CGColorSpaceRef space=CGColorSpaceCreateDeviceGray();
    CGContextRef context=gray && space ? CGBitmapContextCreate(gray,w,h,8,w,space,kCGImageAlphaNone) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) { if (error) *error=@"Unable to create the photo pixel buffer"; free(gray); CGImageRelease(image); return nil; }
    CGContextSetGrayFillColor(context,1,1); CGContextFillRect(context,CGRectMake(0,0,w,h));
    CGContextDrawImage(context,CGRectMake(0,0,w,h),image);
    CGContextRelease(context); CGImageRelease(image);
    VCQRPhotoResult result={0};
    VCQRPhotoStatus status=VCQRPhotoDecode(gray,w,h,w,photoCancelled,operation,&result);
    volatile uint8_t *clear=gray; for (size_t i=0;i<w*h;i++) clear[i]=0;
    free(gray);
    NSMutableArray *texts=nil;
    if (status==VCQRPhotoOK) {
        texts=[NSMutableArray array];
        for (size_t i=0;i<result.count;i++) {
            NSString *text=[[[NSString alloc] initWithBytes:result.entries[i].text length:result.entries[i].length encoding:NSUTF8StringEncoding] autorelease];
            if (!text) text=[[[NSString alloc] initWithBytes:result.entries[i].text length:result.entries[i].length encoding:NSISOLatin1StringEncoding] autorelease];
            if ([text length]) [texts addObject:text];
        }
    }
    if (error) *error=status==VCQRPhotoEmpty ? @"No QR codes found in this photo" : texts ? nil : @"Unable to read QR codes from this photo";
    VCQRPhotoResultClear(&result);
    return [operation isCancelled] ? nil : texts;
#endif
}
