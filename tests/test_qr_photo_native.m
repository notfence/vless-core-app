#import <Vision/Vision.h>
#define VC_QR_NATIVE_TEST
#include "test_qr_photo_source.m"
#undef VC_QR_NATIVE_TEST

static NSArray *nativeObservations;
static BOOL nativeFailure;
static NSOperation *cancelDuringVision;
static unsigned nativeCalls,liveNativeRequests,liveNativeHandlers;
static CGImageAlphaInfo nativeAlpha=kCGImageAlphaNone;
CGImageAlphaInfo CGImageGetAlphaInfo(CGImageRef image) { (void)image; return nativeAlpha; }
CGImageRef CGBitmapContextCreateImage(CGContextRef context) { CHECK("photo-native/alpha-composite-context",context!=NULL); return [[NSDictionary alloc] initWithObjectsAndKeys:@(fixtureSide*6),@"side",nil]; }
@implementation VNBarcodeObservation
@synthesize payloadStringValue=_payloadStringValue,symbology=_symbology,boundingBox=_boundingBox;
- (void)dealloc { [_payloadStringValue release]; [_symbology release]; [super dealloc]; }
@end
@implementation VNDetectBarcodesRequest
@synthesize symbologies=_symbologies,preferBackgroundProcessing=_preferBackgroundProcessing;
- (id)init { if ((self=[super init])) liveNativeRequests++; return self; }
- (NSArray *)results { return _results; }
- (void)dealloc { liveNativeRequests--; [_results release]; [_symbologies release]; [super dealloc]; }
@end
@implementation VNImageRequestHandler
- (id)initWithCGImage:(CGImageRef)image options:(NSDictionary *)options {
    if ((self=[super init])) { liveNativeHandlers++; _image=[image retain]; }
    CHECK("photo-native/prepared-image",image!=nil && [options count]==0);
    return self;
}
- (BOOL)performRequests:(NSArray *)requests error:(NSError **)error {
    (void)error; nativeCalls++;
    CHECK("photo-native/one-request",[requests count]==1);
    VNDetectBarcodesRequest *request=[requests objectAtIndex:0];
    CHECK("photo-native/QR-only",[request.symbologies isEqual:@[VNBarcodeSymbologyQR]]);
    CHECK("photo-native/background-hint",request.preferBackgroundProcessing);
    [cancelDuringVision cancel];
    request->_results=[nativeObservations copy];
    return !nativeFailure;
}
- (void)dealloc { liveNativeHandlers--; [_image release]; [super dealloc]; }
@end
static VNBarcodeObservation *observation(NSString *text,NSString *type,double x,double y) {
    VNBarcodeObservation *value=[[[VNBarcodeObservation alloc] init] autorelease];
    value.payloadStringValue=text; value.symbology=type; value.boundingBox=CGRectMake(x,y,.1,.1); return value;
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; fixtureSide=37;
    char path[]="/tmp/vless-native-photo-XXXXXX"; int fd=mkstemp(path);
    CHECK("photo-native/file",fd>=0 && write(fd,"x",1)==1); close(fd);
    NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:path]];
    NSOperation *operation=[[[NSOperation alloc] init] autorelease]; NSString *error=nil;
    nativeObservations=@[observation(@"third",VNBarcodeSymbologyQR,.1,.1),observation(@"second",VNBarcodeSymbologyQR,.7,.8),observation(@"first",VNBarcodeSymbologyQR,.1,.8),observation(@"first",VNBarcodeSymbologyQR,.5,.1),observation(@"ignored",@"EAN13",.1,.9),observation(nil,VNBarcodeSymbologyQR,.1,.9),@"not an observation"];
    NSArray *texts=VCReadPhotoQR(url,operation,&error);
    CHECK("photo-native/sorted-unique-texts",[texts isEqual:@[@"first",@"second",@"third"]] && !error);
    CHECK("photo-native/no-gray-conversion",drawCalls==0);
    CHECK("photo-native/released",!liveNativeRequests && !liveNativeHandlers);
    nativeAlpha=kCGImageAlphaPremultipliedLast;
    CHECK("photo-native/transparent-background",[VCReadPhotoQR(url,operation,&error) count]==3 && !error && drawCalls==1);
    fault=3; unsigned previousCalls=nativeCalls;
    CHECK("photo-native/composite-failure",!VCReadPhotoQR(url,operation,&error) && nativeCalls==previousCalls && !liveNativeHandlers && !liveNativeRequests);
    fault=0;
    nativeAlpha=kCGImageAlphaNone;
    NSString *unicode=@"https://example.test/sub?a=b+c%25#🇳🇱 Конфиг";
    nativeObservations=@[observation(unicode,VNBarcodeSymbologyQR,.1,.8)];
    CHECK("photo-native/original-text-preserved",[VCReadPhotoQR(url,operation,&error) isEqual:@[unicode]] && !error);
    nativeObservations=@[observation(@"bad bounds",VNBarcodeSymbologyQR,NAN,.8)];
    CHECK("photo-native/invalid-observation",!VCReadPhotoQR(url,operation,&error) && [error isEqual:@"Unable to read QR codes from this photo"]);
    nativeObservations=@[];
    CHECK("photo-native/no-code",!VCReadPhotoQR(url,operation,&error) && [error isEqual:@"No QR codes found in this photo"]);
    nativeFailure=YES;
    CHECK("photo-native/safe-framework-error",!VCReadPhotoQR(url,operation,&error) && [error isEqual:@"Unable to read QR codes from this photo"]);
    CHECK("photo-native/no-fallback-or-leaks",drawCalls==1 && !liveNativeRequests && !liveNativeHandlers);
    nativeFailure=NO;
    nativeObservations=@[observation(@"late",VNBarcodeSymbologyQR,.1,.8)]; cancelDuringVision=operation;
    CHECK("photo-native/late-result-rejected",!VCReadPhotoQR(url,operation,&error)); cancelDuringVision=nil;
    unsigned calls=nativeCalls;
    CHECK("photo-native/cancel-before-read",!VCReadPhotoQR(url,operation,&error) && nativeCalls==calls);
    CHECK("photo-native/cancel-releases",!liveNativeRequests && !liveNativeHandlers);
    operation=[[[NSOperation alloc] init] autorelease];
    nativeObservations=@[observation(@"legacy-source-native-decoder",VNBarcodeSymbologyQR,.1,.8)];
    CHECK("photo-native/asset-source",[VCReadPhotoQR([NSURL URLWithString:@"assets-library://selected-photo"],operation,&error) isEqual:@[@"legacy-source-native-decoder"]] && !error && !liveLibraries);
    fault=2; calls=nativeCalls;
    CHECK("photo-native/image-error-before-vision",!VCReadPhotoQR(url,operation,&error) && nativeCalls==calls); fault=0;
    unlink(path); FINISH("native photo QR"); [pool drain]; return 0;
}
