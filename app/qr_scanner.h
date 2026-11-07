#import "app_support.h"

@class QRScanVC;

@protocol QRScanVCDelegate <NSObject>
- (void)qrScanVCDidCancel:(UIViewController *)vc;
- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text;
- (void)qrScanVC:(UIViewController *)vc didScanTexts:(NSArray *)texts;
@end

@interface QRScanVC : UIViewController <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate, UIAlertViewDelegate> {
    id<QRScanVCDelegate> _delegate;
    AVCaptureSession *_captureSession;
    AVCaptureDevice *_camera;
    AVCaptureMetadataOutput *_metadataOutput;
    AVCaptureVideoDataOutput *_videoOutput;
    dispatch_queue_t _sessionQueue;
    dispatch_queue_t _videoQueue;
    AVCaptureVideoPreviewLayer *_previewLayer;
    UILabel *_hintLabel;
    UIButton *_torchButton;
    UIButton *_cancelButton;
    UIButton *_photoButton;
    UIImage *_photoIcon;
    UIAlertView *_photoErrorAlert;
    UIActivityIndicatorView *_photoIndicator;
    UIImagePickerController *_photoPicker;
    UIPopoverController *_photoPopover;
    NSOperation *_photoOperation;
    dispatch_queue_t _photoQueue;
    NSUInteger _photoGeneration;
    BOOL _photoPickerOpen, _photoReading, _scannerBackground;
    UILabel *_cancelButtonLabel;
    UIView *_focusIndicator;
    UITapGestureRecognizer *_focusGesture;
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 110000
    zbar_image_scanner_t *_qrScanner;
#endif
    NSString *_pendingScanResult;
    NSUInteger _zbarPassIndex;
    NSTimeInterval _scanEnabledAt;
    NSTimeInterval _nextZBarScanAt;
    BOOL _captureConfigurationStarted;
    BOOL _scannerVisible;
    BOOL _didFinish;
    BOOL _torchEnabled;
}
@property (nonatomic, assign) id<QRScanVCDelegate> delegate;
- (void)applyNativeQRMetadataType;
@end
