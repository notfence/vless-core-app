#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#define VNBarcodeSymbologyQR @"QR"
@interface VNBarcodeObservation : NSObject {
    NSString *_payloadStringValue,*_symbology;
    CGRect _boundingBox;
}
@property(copy) NSString *payloadStringValue,*symbology;
@property CGRect boundingBox;
@end
@interface VNDetectBarcodesRequest : NSObject {
@public NSArray *_results;
    NSArray *_symbologies;
    BOOL _preferBackgroundProcessing;
}
@property(copy) NSArray *symbologies;
@property BOOL preferBackgroundProcessing;
@property(readonly) NSArray *results;
@end
@interface VNImageRequestHandler : NSObject {
    CGImageRef _image;
}
- (id)initWithCGImage:(CGImageRef)image options:(NSDictionary *)options;
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error;
@end
