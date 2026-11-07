#import <Foundation/Foundation.h>
@interface ALAssetRepresentation : NSObject
- (long long)size;
- (NSUInteger)getBytes:(uint8_t *)bytes fromOffset:(long long)offset length:(NSUInteger)length error:(NSError **)error;
@end
@interface ALAsset : NSObject
- (ALAssetRepresentation *)defaultRepresentation;
@end
@interface ALAssetsLibrary : NSObject
- (void)assetForURL:(NSURL *)url resultBlock:(void (^)(ALAsset *))result failureBlock:(void (^)(NSError *))failure;
@end
