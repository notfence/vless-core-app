#import <Foundation/Foundation.h>
#include "support/objc/blocks_runtime.h"
#include "check.h"
#include <math.h>
typedef double CGFloat;
typedef struct { double x,y; } CGPoint;
typedef struct { double width,height; } CGSize;
typedef struct { CGPoint origin; CGSize size; } CGRect;
static CGRect CGRectMake(double x,double y,double w,double h) { return (CGRect){{x,y},{w,h}}; }
static CGPoint CGPointMake(double x,double y) { return (CGPoint){x,y}; }
enum { UIPopoverArrowDirectionAny=0 };
enum { UIControlStateNormal=0 };
static void (^queues[2][32])(void);
static NSUInteger counts[2],deliveries,cancellations,cameraStarts,photoReads;
static int dispatch_get_main_queue(void) { return 1; }
static void dispatch_async(int queue,void (^block)(void)) { CHECK("photo-life/queue-bound",counts[queue]<32); queues[queue][counts[queue]++]=Block_copy(block); }
static void run(int queue) { CHECK("photo-life/callback",counts[queue]>0); void (^block)(void)=queues[queue][0]; memmove(queues[queue],queues[queue]+1,--counts[queue]*sizeof(block)); block(); Block_release(block); }
static double CACurrentMediaTime(void) { return 100; }
static NSArray *VCReadPhotoQR(NSURL *url,NSOperation *operation,NSString **error) { (void)operation; (void)error; photoReads++; return url ? @[@"socks5://127.0.0.1:1080"] : nil; }
static NSString *UIImagePickerControllerImageURL=@"imageURL",*UIImagePickerControllerReferenceURL=@"referenceURL";
@interface Control : NSObject { BOOL enabled,running; id window; CGRect frame,bounds; CGPoint center; }
@property BOOL enabled,running;
@property(retain) id window;
@property(nonatomic) CGRect frame,bounds;
@property CGPoint center;
- (void)startAnimating;
- (void)stopAnimating;
- (void)setImage:(id)image forState:(int)state;
@end
@implementation Control
@synthesize enabled,running,window,frame,bounds,center;
- (void)setFrame:(CGRect)value { frame=value; bounds=CGRectMake(0,0,value.size.width,value.size.height); }
- (void)startAnimating { running=YES; }
- (void)stopAnimating { running=NO; }
- (void)setImage:(id)image forState:(int)state { (void)image; (void)state; }
- (void)dealloc { [window release]; [super dealloc]; }
@end
@interface UIApplication : NSObject
+ (UIApplication *)sharedApplication;
- (CGRect)statusBarFrame;
@end
@implementation UIApplication
+ (UIApplication *)sharedApplication { static id value; if (!value) value=[[self alloc] init]; return value; }
- (CGRect)statusBarFrame { return CGRectMake(0,0,320,20); }
@end
@interface UIDevice : NSObject
+ (UIDevice *)currentDevice;
- (NSString *)systemVersion;
@end
@implementation UIDevice
+ (UIDevice *)currentDevice { static id value; if (!value) value=[[self alloc] init]; return value; }
- (NSString *)systemVersion { return @"11"; }
@end
@interface UIImagePickerController : NSObject { id delegate; }
@property(assign) id delegate;
@end
@implementation UIImagePickerController
@synthesize delegate;
@end
@interface UIPopoverController : UIImagePickerController
@property BOOL popoverVisible;
- (void)dismissPopoverAnimated:(BOOL)animated;
- (void)presentPopoverFromRect:(CGRect)rect inView:(id)view permittedArrowDirections:(int)directions animated:(BOOL)animated;
@end
@implementation UIPopoverController
- (BOOL)popoverVisible { return NO; }
- (void)setPopoverVisible:(BOOL)value { (void)value; }
- (void)dismissPopoverAnimated:(BOOL)animated { (void)animated; }
- (void)presentPopoverFromRect:(CGRect)rect inView:(id)view permittedArrowDirections:(int)directions animated:(BOOL)animated { (void)rect; (void)view; (void)directions; (void)animated; }
@end
@interface Delegate : NSObject
@end
@implementation Delegate
- (void)qrScanVC:(id)vc didScanTexts:(id)texts { (void)vc; deliveries+=[texts count]; }
- (void)qrScanVCDidCancel:(id)vc { (void)vc; cancellations++; }
@end
@interface VCBaseController : NSObject
- (void)viewDidLayoutSubviews;
@end
@implementation VCBaseController
- (void)viewDidLayoutSubviews {}
@end
@interface QRScanVC : VCBaseController {
@public BOOL _photoReading,_photoPickerOpen,_scannerBackground,_didFinish,_scannerVisible;
    NSUInteger _photoGeneration;
    NSOperation *_photoOperation;
    int _photoQueue;
    Control *_photoIndicator,*_photoButton,*_cancelButton,*_torchButton,*view;
    Control *_previewLayer,*_hintLabel,*_cancelButtonLabel;
    UIImagePickerController *_photoPicker;
    UIPopoverController *_photoPopover;
    id _delegate,_captureSession;
    double _scanEnabledAt,_nextZBarScanAt;
    NSString *_pendingScanResult;
    id _photoIcon,_photoErrorAlert;
}
@property(retain) Control *view;
- (void)setScannerHintText:(id)text;
- (void)setCaptureSessionRunning:(BOOL)running;
- (void)setTorchEnabled:(BOOL)enabled;
- (void)finishCaptureSessionConfigurationWithError:(id)error;
- (void)beginCaptureSessionConfiguration;
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion;
- (void)showPhotoError:(id)error;
- (void)updateCaptureConnectionOrientations;
@end
@implementation QRScanVC
@synthesize view;
- (id)init { if ((self=[super init])) { view=[[Control alloc] init]; view.window=@"window"; _photoIndicator=[[Control alloc] init]; _photoButton=[[Control alloc] init]; _cancelButton=[[Control alloc] init]; _torchButton=[[Control alloc] init]; _delegate=[[Delegate alloc] init]; } return self; }
- (void)dealloc { [_photoOperation cancel]; [_photoOperation release]; [_photoPicker release]; [_photoPopover release]; [view release]; [_photoIndicator release]; [_photoButton release]; [_cancelButton release]; [_torchButton release]; [_delegate release]; [_pendingScanResult release]; [NSObject cancelPreviousPerformRequestsWithTarget:self]; [super dealloc]; }
- (void)setScannerHintText:(id)text { (void)text; }
- (void)setCaptureSessionRunning:(BOOL)running { (void)running; }
- (void)setTorchEnabled:(BOOL)enabled { (void)enabled; }
- (void)finishCaptureSessionConfigurationWithError:(id)error { (void)error; cameraStarts++; }
- (void)beginCaptureSessionConfiguration { cameraStarts++; }
- (void)dismissViewControllerAnimated:(BOOL)animated completion:(void (^)(void))completion { (void)animated; if (completion) dispatch_async(1,completion); }
- (void)showPhotoError:(id)error { (void)error; [self resumeScannerAfterPhoto]; }
- (void)updateCaptureConnectionOrientations {}
#include "qr_lifecycle.inc"
@end

@interface MainVC : NSObject {
@public NSMutableArray *_photoQRQueue; id _subscriptionTask,_configurationDraft,_pendingPlainHTTPConfirmation,_pendingInsecureImportURLs,_pendingCompatibilityImport;
    BOOL _configurationCommitInProgress,_photoQRCancelled;
    NSUInteger _photoQRAdded,_photoQRDuplicates,_photoQRRejected,_photoQRFailures,starts,specials;
    NSString *lastStatus; BOOL statusOK;
}
@end
@implementation MainVC
- (void)startTextImports:(id)texts filePath:(id)path separateQR:(BOOL)separate { (void)texts; (void)path; CHECK("photo-batch/separate-boundaries",separate); starts++; _subscriptionTask=@"busy"; }
- (void)receiveKaringBackupWithDescriptor:(id)descriptor { (void)descriptor; specials++; _subscriptionTask=@"busy"; }
- (void)showStatus:(id)text ok:(BOOL)ok { [lastStatus release]; lastStatus=[text copy]; statusOK=ok; }
- (void)dealloc { [_photoQRQueue release]; [lastStatus release]; [NSObject cancelPreviousPerformRequestsWithTarget:self]; [super dealloc]; }
#include "qr_batch.inc"
@end

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    QRScanVC *vc=[[[QRScanVC alloc] init] autorelease];
    for (unsigned i=0;i<4;i++) {
        double width=(double[]){320,375,768,1024}[i];
        vc.view.bounds=CGRectMake(0,0,width,460);
        [vc viewDidLayoutSubviews];
        CHECK("photo-life/gallery-square",vc->_photoButton.frame.size.width==62 && vc->_photoButton.frame.size.height==62 && vc->_photoButton.frame.origin.x==14);
        CHECK("photo-life/gap-and-right-margin",vc->_cancelButton.frame.origin.x==88 && vc->_cancelButton.frame.size.width==width-102 && vc->_cancelButton.frame.origin.y==vc->_photoButton.frame.origin.y);
    }
    vc->_photoPicker=[[UIImagePickerController alloc] init]; vc->_photoPickerOpen=YES;
    [vc imagePickerControllerDidCancel:vc->_photoPicker]; run(1);
    CHECK("photo-life/picker-cancel-keeps-scanner",!vc->_didFinish && vc->_scannerVisible && !cancellations && cameraStarts==1);
    vc->_photoPicker=[[UIImagePickerController alloc] init]; vc->_photoPickerOpen=YES;
    [vc imagePickerController:vc->_photoPicker didFinishPickingMediaWithInfo:@{UIImagePickerControllerImageURL:[NSURL fileURLWithPath:@"/synthetic.png"]}];
    CHECK("photo-life/reading-before-return",vc->_photoReading && !vc->_photoButton.enabled);
    CHECK("photo-life/no-camera-result-during-photo",![vc canScanWithCamera]);
    [vc scannerBecameActive:nil];
    CHECK("photo-life/permission-return-keeps-reading-state",vc->_photoReading && !vc->_photoButton.enabled);
    run(1); CHECK("photo-life/worker-queued-not-delivered",counts[0]==1 && !deliveries);
    [vc scannerEnteredBackground:nil]; run(0); run(1);
    CHECK("photo-life/background-rejects-late-result",!deliveries && !vc->_photoReading && !vc->_photoOperation);
    [vc scannerBecameActive:nil]; CHECK("photo-life/foreground-does-not-reimport",vc->_scannerVisible && !deliveries);
    vc->_photoErrorAlert=@"error"; CHECK("photo-life/no-camera-result-behind-error",![vc canScanWithCamera]); vc->_photoErrorAlert=nil;
    vc->_pendingScanResult=[@"pending camera value" copy]; vc->_didFinish=YES;
    [vc scannerEnteredBackground:nil]; [vc scannerBecameActive:nil];
    CHECK("photo-life/background-clears-delayed-camera-result",!vc->_pendingScanResult && !vc->_didFinish && vc->_cancelButton.enabled);
    vc->_photoPicker=[[UIImagePickerController alloc] init]; vc->_photoPickerOpen=YES;
    [vc imagePickerController:vc->_photoPicker didFinishPickingMediaWithInfo:@{UIImagePickerControllerImageURL:[NSURL fileURLWithPath:@"/synthetic.png"]}];
    run(1); [vc cancelPressed]; run(0); run(1);
    CHECK("photo-life/quick-cancel-rejects-worker",cancellations==1 && !deliveries && vc->_didFinish);
    [vc cancelPressed]; CHECK("photo-life/cancel-once",cancellations==1);
    vc=[[[QRScanVC alloc] init] autorelease];
    vc->_photoPicker=[[UIImagePickerController alloc] init]; vc->_photoPickerOpen=YES;
    [vc imagePickerController:vc->_photoPicker didFinishPickingMediaWithInfo:@{UIImagePickerControllerImageURL:[NSURL fileURLWithPath:@"/synthetic.png"]}];
    run(1); run(0); run(1);
    CHECK("photo-life/success-delivered-once",deliveries==1 && vc->_didFinish && !vc->_photoOperation);
    MainVC *main=[[[MainVC alloc] init] autorelease];
    main->_photoQRQueue=[[NSMutableArray alloc] initWithObjects:@[@"first",@"second"],@{@"hosts":@[@"127.0.0.1"]},nil];
    [main advancePhotoQRImport]; [main advancePhotoQRImport];
    CHECK("photo-batch/one-operation",main->starts==1 && !main->specials && [main->_photoQRQueue count]==1);
    main->_subscriptionTask=nil; main->_pendingPlainHTTPConfirmation=@"prompt";
    [main advancePhotoQRImport]; CHECK("photo-batch/permission-pauses-next",!main->specials);
    main->_pendingPlainHTTPConfirmation=nil; [main advancePhotoQRImport];
    CHECK("photo-batch/karing-is-sequential",main->specials==1);
    main->_subscriptionTask=nil; main->_photoQRAdded=2; main->_photoQRFailures=1;
    [main advancePhotoQRImport]; CHECK("photo-batch/failed-source-not-success",!main->statusOK && [main->lastStatus rangeOfString:@"2 added"].location!=NSNotFound && !main->_photoQRQueue);
    main->_photoQRQueue=[[NSMutableArray alloc] initWithObjects:@[@"ignored"],nil]; main->_photoQRCancelled=YES;
    [main advancePhotoQRImport]; CHECK("photo-batch/cancel-does-not-start-next",main->starts==1 && [main->lastStatus rangeOfString:@"cancelled"].location!=NSNotFound);
    FINISH("photo QR lifecycle"); [pool drain]; return 0;
}
