#import <Foundation/Foundation.h>
typedef NS_ENUM(NSInteger, ALAuthorizationStatus) {
    ALAuthorizationStatusNotDetermined,
    ALAuthorizationStatusRestricted,
    ALAuthorizationStatusDenied,
    ALAuthorizationStatusAuthorized
};
extern NSString *const ALAssetsLibraryErrorDomain;
enum {
    ALAssetsLibraryDataUnavailableError=-3310,
    ALAssetsLibraryAccessUserDeniedError=-3311,
    ALAssetsLibraryAccessGloballyDeniedError=-3312
};
@interface ALAssetRepresentation : NSObject
- (long long)size;
- (NSUInteger)getBytes:(uint8_t *)bytes fromOffset:(long long)offset length:(NSUInteger)length error:(NSError **)error;
@end
@interface ALAsset : NSObject
- (ALAssetRepresentation *)defaultRepresentation;
@end
@interface ALAssetsLibrary : NSObject
+ (ALAuthorizationStatus)authorizationStatus;
- (void)assetForURL:(NSURL *)url resultBlock:(void (^)(ALAsset *))result failureBlock:(void (^)(NSError *))failure;
@end
