#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>
#include "check.h"
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
static int fault,sourceCalls,thumbnailCalls,drawCalls;
static size_t fixtureSide;
static char matrix[128][130];
static double metadataWidth=4000,metadataHeight=3000;
static NSOperation *cancelDuringRead;
static NSUInteger liveLibraries;
static BOOL modernPhotoAuthorization;
static ALAuthorizationStatus photoAuthorization=ALAuthorizationStatusAuthorized;
NSString *const ALAssetsLibraryErrorDomain=@"ALAssetsLibraryErrorDomain";
@interface Provider : NSObject { @public void *context; CGDataProviderDirectCallbacks callbacks; }
@end
@implementation Provider
- (void)dealloc { callbacks.releaseInfo(context); [super dealloc]; }
@end
@implementation ALAssetRepresentation
- (long long)size { return 32; }
- (NSUInteger)getBytes:(uint8_t *)bytes fromOffset:(long long)offset length:(NSUInteger)length error:(NSError **)error { (void)offset; (void)error; if (!liveLibraries) return 0; memset(bytes,1,length); return length; }
@end
@implementation ALAsset
- (ALAssetRepresentation *)defaultRepresentation { return [[[ALAssetRepresentation alloc] init] autorelease]; }
@end
@implementation ALAssetsLibrary
+ (BOOL)respondsToSelector:(SEL)selector {
    if (sel_isEqual(selector,@selector(authorizationStatus))) return modernPhotoAuthorization;
    return [super respondsToSelector:selector];
}
+ (ALAuthorizationStatus)authorizationStatus { return photoAuthorization; }
- (id)init { if ((self=[super init])) liveLibraries++; return self; }
- (void)dealloc { liveLibraries--; [super dealloc]; }
- (void)assetForURL:(NSURL *)url resultBlock:(void (^)(ALAsset *))result failureBlock:(void (^)(NSError *))failure {
    (void)url;
    if (fault==8) return;
    if (fault==5 || fault==9 || fault==11 || fault==12 || fault==13) {
        NSInteger code=fault==9 ? ALAssetsLibraryDataUnavailableError : fault==12 ? -1 :
            fault==13 ? ALAssetsLibraryAccessUserDeniedError : ALAssetsLibraryAccessGloballyDeniedError;
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        failure([NSError errorWithDomain:fault==11 ? @"unrelated" : ALAssetsLibraryErrorDomain code:code
            userInfo:@{NSLocalizedDescriptionKey:@"private photo reference must not appear"}]);
        [pool drain];
    } else if (fault==10) result(nil);
    else { [cancelDuringRead cancel]; result([[[ALAsset alloc] init] autorelease]); }
}
@end
CGDataProviderRef CGDataProviderCreateDirect(void *info,off_t size,const CGDataProviderDirectCallbacks *callbacks) {
    CHECK("photo-source/provider-positive-size",size>0);
    Provider *provider=[[Provider alloc] init]; provider->context=info; provider->callbacks=*callbacks; return provider;
}
void CGDataProviderRelease(CGDataProviderRef provider) { [provider release]; }
CGImageSourceRef CGImageSourceCreateWithDataProvider(CGDataProviderRef provider,CFDictionaryRef options) {
    sourceCalls++; CHECK("photo-source/no-full-decoded-cache",![[options objectForKey:kCGImageSourceShouldCache] boolValue]);
    uint8_t byte=0; Provider *p=provider;
    CHECK("photo-source/bounded-provider-read",p->callbacks.getBytesAtPosition(p->context,&byte,0,1)==1);
    CHECK("photo-source/negative-offset",p->callbacks.getBytesAtPosition(p->context,&byte,-1,1)==0);
    return fault==1 ? nil : [provider retain];
}
CFDictionaryRef CGImageSourceCopyPropertiesAtIndex(CGImageSourceRef source,size_t index,CFDictionaryRef options) { (void)source; (void)index; (void)options; return [@{kCGImagePropertyPixelWidth:@(metadataWidth),kCGImagePropertyPixelHeight:@(metadataHeight)} retain]; }
CGImageRef CGImageSourceCreateThumbnailAtIndex(CGImageSourceRef source,size_t index,CFDictionaryRef options) {
    (void)source; (void)index; thumbnailCalls++;
    CHECK("photo-source/orientation-transform",[[options objectForKey:kCGImageSourceCreateThumbnailWithTransform] boolValue]);
    CHECK("photo-source/pixel-limit",[[options objectForKey:kCGImageSourceThumbnailMaxPixelSize] intValue]==2048);
    return fault==2 ? nil : [[NSDictionary alloc] initWithObjectsAndKeys:@(fixtureSide*6),@"side",source,@"provider",nil];
}
int CGImageSourceGetStatus(CGImageSourceRef source) { (void)source; return fault==6 ? kCGImageStatusIncomplete : kCGImageStatusComplete; }
int CGImageSourceGetStatusAtIndex(CGImageSourceRef source,size_t index) {
    (void)source; (void)index;
    return fault==4 ? kCGImageStatusUnexpectedEOF : fault==7 ? kCGImageStatusInvalidData : kCGImageStatusIncomplete;
}
size_t CGImageGetWidth(CGImageRef image) { return [[image objectForKey:@"side"] unsignedIntegerValue]; }
size_t CGImageGetHeight(CGImageRef image) { return CGImageGetWidth(image); }
void CGImageRelease(CGImageRef image) { [image release]; }
CGColorSpaceRef CGColorSpaceCreateDeviceGray(void) { return (void *)1; }
void CGColorSpaceRelease(CGColorSpaceRef space) { CHECK("photo-source/gray-space",space==(void *)1); }
CGContextRef CGBitmapContextCreate(void *bytes,size_t w,size_t h,size_t bits,size_t row,CGColorSpaceRef space,unsigned alpha) { (void)h; (void)space; (void)alpha; CHECK("photo-source/gray-not-rgba",bits==8 && row==w); return fault==3 ? NULL : bytes; }
void CGContextSetGrayFillColor(CGContextRef context,double gray,double alpha) { (void)context; CHECK("photo-source/white-alpha-background",gray==1 && alpha==1); }
void CGContextFillRect(CGContextRef context,CGRect rect) { memset(context,255,(size_t)(rect.width*rect.height)); }
void CGContextDrawImage(CGContextRef context,CGRect rect,CGImageRef image) {
    drawCalls++; uint8_t *bytes=context; size_t width=(size_t)rect.width;
    Provider *provider=[image objectForKey:@"provider"]; uint8_t sourceByte=0;
    CHECK("photo-source/deferred-draw-keeps-source-alive",provider->callbacks.getBytesAtPosition(provider->context,&sourceByte,0,1)==1);
    BOOL white=YES;
    for (size_t i=0;i<width*width;i++) if (bytes[i]!=255) { white=NO; break; }
    CHECK("photo-source/transparent-pixels-have-white-background",white);
    for (size_t y=0;y<width;y++) for (size_t x=0;x<width;x++) bytes[y*width+x]=matrix[y/6][x/6]=='1' ? 0 : 255;
}
void CGContextRelease(CGContextRef context) { (void)context; }
#include "../app/qr_photo_source.m"
#ifndef VC_QR_NATIVE_TEST
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    FILE *fixture=fopen("qr_fixture.txt","r"); CHECK("photo-source/fixture",fixture!=NULL);
    while (fixtureSide<128 && fgets(matrix[fixtureSide],sizeof(matrix[fixtureSide]),fixture)) fixtureSide++;
    fclose(fixture);
    char path[]="/tmp/vless-photo-source-XXXXXX"; int fd=mkstemp(path);
    CHECK("photo-source/file",fd>=0 && write(fd,"x",1)==1); close(fd);
    NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    NSOperation *operation=[[[NSOperation alloc] init] autorelease]; NSString *error=nil;
    NSArray *texts=VCReadPhotoQR(url,operation,&error);
    CHECK("photo-source/file-roundtrip",[texts count]==1 && !error && [[texts objectAtIndex:0] isEqual:@"socks5://127.0.0.1:1080#vless-core"]);
    for (fault=1;fault<=4;fault++) CHECK("photo-source/image-failure",!VCReadPhotoQR(url,operation,&error) && [error length]);
    fault=2;
    CHECK("photo-source/damaged-image-message",!VCReadPhotoQR(url,operation,&error) && [error rangeOfString:@"damaged"].location!=NSNotFound);
    fault=6; CHECK("photo-source/incomplete-source-rejected",!VCReadPhotoQR(url,operation,&error));
    fault=7; CHECK("photo-source/invalid-frame-rejected",!VCReadPhotoQR(url,operation,&error));
    fault=0; metadataWidth=1e20; int previous=thumbnailCalls;
    CHECK("photo-source/reject-before-thumbnail",!VCReadPhotoQR(url,operation,&error) && thumbnailCalls==previous);
    metadataWidth=4000;
    char linkPath[256]; snprintf(linkPath,sizeof(linkPath),"%s-link",path); CHECK("photo-source/symlink-created",symlink(path,linkPath)==0);
    CHECK("photo-source/no-symlink-follow",!VCReadPhotoQR([NSURL fileURLWithPath:[NSString stringWithUTF8String:linkPath]],operation,&error)); unlink(linkPath);
    fd=open(path,O_WRONLY); CHECK("photo-source/large-file-created",fd>=0 && ftruncate(fd,33*1024*1024)==0); close(fd);
    previous=sourceCalls; CHECK("photo-source/file-size-before-imageio",!VCReadPhotoQR(url,operation,&error) && sourceCalls==previous);
    unlink(path);
    NSURL *asset=[NSURL URLWithString:@"assets-library://selected-photo"];
    CHECK("photo-source/legacy-selected-asset",[VCReadPhotoQR(asset,operation,&error) count]==1);
    CHECK("photo-source/library-released-after-read",liveLibraries==0);
    for (fault=1;fault<=4;fault++) {
        CHECK("photo-source/legacy-image-failure",!VCReadPhotoQR(asset,operation,&error));
        CHECK("photo-source/library-released-after-image-failure",liveLibraries==0);
    }
    fault=0;
    for (fault=5;fault<=13;fault+=8) {
        CHECK("photo-source/ios5-denied",!VCReadPhotoQR(asset,operation,&error) &&
            [error rangeOfString:@"Settings > Location Services"].location!=NSNotFound &&
            [error rangeOfString:@"allow vless-core"].location!=NSNotFound);
    }
    modernPhotoAuthorization=YES;
    fault=5; photoAuthorization=ALAuthorizationStatusDenied;
    CHECK("photo-source/modern-denied",!VCReadPhotoQR(asset,operation,&error) &&
        [error rangeOfString:@"Settings > Privacy > Photos"].location!=NSNotFound &&
        [error rangeOfString:@"Location Services"].location==NSNotFound);
    photoAuthorization=ALAuthorizationStatusRestricted;
    CHECK("photo-source/restricted",!VCReadPhotoQR(asset,operation,&error) && [error rangeOfString:@"restricted"].location!=NSNotFound);
    photoAuthorization=ALAuthorizationStatusAuthorized; modernPhotoAuthorization=NO;
    fault=9;
    CHECK("photo-source/asset-unavailable",!VCReadPhotoQR(asset,operation,&error) && [error rangeOfString:@"currently unavailable"].location!=NSNotFound);
    fault=10;
    CHECK("photo-source/missing-asset",!VCReadPhotoQR(asset,operation,&error) && [error rangeOfString:@"no longer available"].location!=NSNotFound);
    for (fault=11;fault<=12;fault++) {
        CHECK("photo-source/unrelated-error-safe",!VCReadPhotoQR(asset,operation,&error) &&
            [error rangeOfString:@"Location Services"].location==NSNotFound &&
            [error rangeOfString:@"private photo reference"].location==NSNotFound);
    }
    fault=8;
    NSDate *started=[NSDate date];
    CHECK("photo-source/asset-timeout",!VCReadPhotoQR(asset,operation,&error) && [error rangeOfString:@"did not respond in time"].location!=NSNotFound);
    CHECK("photo-source/asset-timeout-bounded",-[started timeIntervalSinceNow]<12);
    fault=0;
    CHECK("photo-source/library-released-after-denial",liveLibraries==0);
    char original[sizeof(matrix)]; memcpy(original,matrix,sizeof(matrix)); memset(matrix,'0',sizeof(matrix));
    CHECK("photo-source/no-QR-distinct",!VCReadPhotoQR(asset,operation,&error) && [error isEqualToString:@"No QR codes found in this photo"]);
    memcpy(matrix,original,sizeof(matrix));
    fault=5; CHECK("photo-source/denied-without-error-output",!VCReadPhotoQR(asset,operation,NULL)); fault=0;
    cancelDuringRead=operation; CHECK("photo-source/cancel-asset-callback",!VCReadPhotoQR(asset,operation,&error)); cancelDuringRead=nil;
    CHECK("photo-source/library-released-after-cancel",liveLibraries==0);
    CHECK("photo-source/cancel-before-read",!VCReadPhotoQR(url,operation,&error));
    FINISH("photo QR source guards"); [pool drain]; return 0;
}
#endif
