#import "app_support.h"

@class QRScanVC;

@protocol QRScanVCDelegate <NSObject>
- (void)qrScanVCDidCancel:(UIViewController *)vc;
- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text;
@end

@interface QRScanVC : UIViewController <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate> {
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
    UILabel *_cancelButtonLabel;
    UIView *_focusIndicator;
    UITapGestureRecognizer *_focusGesture;
    zbar_image_scanner_t *_qrScanner;
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
