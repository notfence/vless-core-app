#import "qr_scanner.h"
#import "qr_photo_source.h"
#import <AssetsLibrary/AssetsLibrary.h>

static UIImage *VCQRPhotoIcon(void) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(28,28),NO,0);
    CGContextRef context=UIGraphicsGetCurrentContext();
    if (!context) { UIGraphicsEndImageContext(); return nil; }
    CGContextSetStrokeColorWithColor(context,[UIColor whiteColor].CGColor);
    CGContextSetLineWidth(context,2); CGContextSetLineCap(context,kCGLineCapRound); CGContextSetLineJoin(context,kCGLineJoinRound);
    UIBezierPath *border=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(2,4,24,20) cornerRadius:3];
    [border setLineWidth:2]; [border stroke];
    CGContextStrokeEllipseInRect(context,CGRectMake(7,8,4,4));
    CGContextMoveToPoint(context,3,21); CGContextAddLineToPoint(context,11,14);
    CGContextAddLineToPoint(context,16,18); CGContextAddLineToPoint(context,20,14); CGContextAddLineToPoint(context,25,19); CGContextStrokePath(context);
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext(); return image;
}

@implementation QRScanVC

@synthesize delegate = _delegate;

- (BOOL)canScanWithCamera {
    return _scannerVisible && !_didFinish && !_photoPickerOpen && !_photoReading && !_scannerBackground && !_photoErrorAlert;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (void)setScannerHintText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) text = @"";
    _hintLabel.text = text;
}

- (void)updateTorchButtonAppearance {
    if (!_torchButton) return;

    _torchButton.selected = _torchEnabled;
    _torchButton.backgroundColor = _torchEnabled
        ? [UIColor colorWithWhite:0.0f alpha:0.68f]
        : [UIColor colorWithWhite:0.0f alpha:0.28f];
    _torchButton.accessibilityValue = _torchEnabled ? @"On" : @"Off";
}

- (void)setTorchEnabled:(BOOL)enabled {
    if (!_camera || ![_camera hasTorch] ||
        ![_camera isTorchModeSupported:(enabled ? AVCaptureTorchModeOn : AVCaptureTorchModeOff)]) {
        _torchEnabled = NO;
        [self updateTorchButtonAppearance];
        return;
    }

    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    @try {
        [_camera setTorchMode:(enabled ? AVCaptureTorchModeOn : AVCaptureTorchModeOff)];
        _torchEnabled = enabled;
    }
    @catch (NSException *exception) {
        (void)exception;
        _torchEnabled = NO;
    }
    [_camera unlockForConfiguration];
    [self updateTorchButtonAppearance];
}

- (void)torchPressed {
    if (![self canScanWithCamera]) return;
    [self setTorchEnabled:!_torchEnabled];
}

- (void)configureContinuousCameraFocus {
    if (!_camera) return;

    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    if ([_camera isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        [_camera setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
    }
    if ([_camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [_camera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_camera unlockForConfiguration];
}

- (void)showFocusIndicatorAtPoint:(CGPoint)point {
    if (!_focusIndicator) return;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    _focusIndicator.center = point;
    _focusIndicator.alpha = 1.0f;
    _focusIndicator.transform = CGAffineTransformMakeScale(1.25f, 1.25f);
    [UIView animateWithDuration:0.18f animations:^{
        _focusIndicator.transform = CGAffineTransformIdentity;
    }];
    [self performSelector:@selector(hideFocusIndicator) withObject:nil afterDelay:0.8f];
}

- (void)hideFocusIndicator {
    [UIView animateWithDuration:0.2f animations:^{
        _focusIndicator.alpha = 0.0f;
    }];
}

- (void)focusTapped:(UITapGestureRecognizer *)gesture {
    if (![self canScanWithCamera]) return;
    if (!_camera || !_previewLayer || [gesture state] != UIGestureRecognizerStateEnded) return;

    CGPoint viewPoint = [gesture locationInView:self.view];
    if (CGRectContainsPoint(_hintLabel.frame, viewPoint) ||
        CGRectContainsPoint(_photoButton.frame, viewPoint) ||
        CGRectContainsPoint(_cancelButton.frame, viewPoint) ||
        (!_torchButton.hidden && CGRectContainsPoint(_torchButton.frame, viewPoint))) {
        return;
    }
    if (![_camera isFocusPointOfInterestSupported] ||
        ![_camera isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        return;
    }

    if (![_previewLayer respondsToSelector:@selector(captureDevicePointOfInterestForPoint:)]) return;
    CGPoint devicePoint = [_previewLayer captureDevicePointOfInterestForPoint:viewPoint];
    NSError *error = nil;
    if (![_camera lockForConfiguration:&error]) return;
    [_camera setFocusPointOfInterest:devicePoint];
    [_camera setFocusMode:AVCaptureFocusModeAutoFocus];
    if ([_camera isExposurePointOfInterestSupported] &&
        [_camera isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        [_camera setExposurePointOfInterest:devicePoint];
        [_camera setExposureMode:AVCaptureExposureModeContinuousAutoExposure];
    }
    [_camera unlockForConfiguration];

    [self showFocusIndicatorAtPoint:viewPoint];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [self performSelector:@selector(configureContinuousCameraFocus) withObject:nil afterDelay:1.2f];
}

- (AVCaptureVideoOrientation)captureVideoOrientationForCurrentInterfaceOrientation {
    UIInterfaceOrientation ui = CurrentInterfaceOrientation();
    switch (ui) {
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationPortrait:
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (void)updateCaptureConnectionOrientations {
    AVCaptureVideoOrientation v = [self captureVideoOrientationForCurrentInterfaceOrientation];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([_previewLayer respondsToSelector:@selector(connection)]) {
        AVCaptureConnection *previewConn = [_previewLayer connection];
        if (previewConn && [previewConn isVideoOrientationSupported]) {
            [previewConn setVideoOrientation:v];
        }
    } else if ([_previewLayer isOrientationSupported]) {
        [_previewLayer setOrientation:v];
    }
#pragma clang diagnostic pop

    AVCaptureConnection *metadataConn = [_metadataOutput connectionWithMediaType:AVMediaTypeVideo];
    if (metadataConn && [metadataConn isVideoOrientationSupported]) {
        [metadataConn setVideoOrientation:v];
    }

    AVCaptureConnection *videoConn = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConn && [videoConn isVideoOrientationSupported]) {
        [videoConn setVideoOrientation:v];
    }
}

- (void)setCaptureSessionRunning:(BOOL)running {
    if (!_sessionQueue) return;

    __block QRScanVC *controller = [self retain];
    dispatch_async(_sessionQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        AVCaptureSession *session = controller->_captureSession;
        if (running) {
            [controller->_videoOutput setSampleBufferDelegate:controller queue:controller->_videoQueue];
            [controller->_metadataOutput setMetadataObjectsDelegate:controller queue:dispatch_get_main_queue()];
            if (![session isRunning]) [session startRunning];
        } else {
            [controller->_videoOutput setSampleBufferDelegate:nil queue:NULL];
            [controller->_metadataOutput setMetadataObjectsDelegate:nil queue:NULL];
            if ([session isRunning]) [session stopRunning];
            if (controller->_videoQueue) dispatch_sync(controller->_videoQueue, ^{});
        }
        [pool drain];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (running) [controller applyNativeQRMetadataType];
            [controller release];
        });
    });
}

- (void)notifyDelegateOfScanResult {
    if (![_pendingScanResult isKindOfClass:[NSString class]] || [_pendingScanResult length] == 0) return;

    NSString *value = [[_pendingScanResult retain] autorelease];
    [_pendingScanResult release];
    _pendingScanResult = nil;
    if ([_delegate respondsToSelector:@selector(qrScanVC:didScanText:)]) {
        [_delegate qrScanVC:self didScanText:value];
    }
}

- (void)deliverScanResult:(NSString *)rawValue {
    if (![self canScanWithCamera]) return;
    NSString *value = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;

    _didFinish = YES;
    _pendingScanResult = [value copy];
    _cancelButton.enabled = NO;
    _photoButton.enabled = NO;
    _torchButton.enabled = NO;
    [self setScannerHintText:@"Succeeded ✅"];
    _hintLabel.backgroundColor = [UIColor colorWithRed:0.08f green:0.55f blue:0.22f alpha:0.9f];
    _hintLabel.alpha = 0.0f;
    _hintLabel.transform = CGAffineTransformMakeScale(0.86f, 0.86f);
    [UIView animateWithDuration:0.16f animations:^{
        _hintLabel.alpha = 1.0f;
        _hintLabel.transform = CGAffineTransformIdentity;
    }];
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
    [self performSelector:@selector(notifyDelegateOfScanResult) withObject:nil afterDelay:0.45];
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED < 110000
- (BOOL)tryDecodeFrameWithZBar:(CMSampleBufferRef)sampleBuffer decodedText:(NSString **)decodedText {
    if (!sampleBuffer || !decodedText) return NO;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return NO;

    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t width = 0;
    size_t height = 0;
    size_t bytesPerRow = 0;
    const uint8_t *source = NULL;
    BOOL isPlanar = CVPixelBufferIsPlanar(imageBuffer);

    if (isPlanar && CVPixelBufferGetPlaneCount(imageBuffer) > 0) {
        width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        source = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    } else {
        width = CVPixelBufferGetWidth(imageBuffer);
        height = CVPixelBufferGetHeight(imageBuffer);
        bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        source = (const uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    }

    if (!source || width < 40 || height < 40 ||
        width > UINT_MAX || height > UINT_MAX || height > (SIZE_MAX / width)) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    size_t imageLength = width * height;
    uint8_t *luma = (uint8_t *)malloc(imageLength);
    if (!luma) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    if (isPlanar) {
        for (size_t y = 0; y < height; y++) {
            memcpy(luma + (y * width), source + (y * bytesPerRow), width);
        }
    } else {
        OSType pixelType = CVPixelBufferGetPixelFormatType(imageBuffer);
        if (pixelType == kCVPixelFormatType_32BGRA || pixelType == kCVPixelFormatType_32ARGB) {
            for (size_t y = 0; y < height; y++) {
                const uint8_t *row = source + (y * bytesPerRow);
                uint8_t *dstRow = luma + (y * width);
                for (size_t x = 0; x < width; x++) {
                    const uint8_t *px = row + (x * 4);
                    unsigned int red = (pixelType == kCVPixelFormatType_32BGRA) ? px[2] : px[1];
                    unsigned int green = (pixelType == kCVPixelFormatType_32BGRA) ? px[1] : px[2];
                    unsigned int blue = (pixelType == kCVPixelFormatType_32BGRA) ? px[0] : px[3];
                    dstRow[x] = (uint8_t)((red * 77U + green * 150U + blue * 29U) >> 8);
                }
            }
        } else {
            for (size_t y = 0; y < height; y++) {
                memcpy(luma + (y * width), source + (y * bytesPerRow), width);
            }
        }
    }

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    if (!_qrScanner) {
        _qrScanner = zbar_image_scanner_create();
        if (_qrScanner) {
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_ENABLE, 0);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_QRCODE, ZBAR_CFG_ENABLE, 1);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_TEST_INVERTED, 0);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_X_DENSITY, 1);
            zbar_image_scanner_set_config(_qrScanner, ZBAR_NONE, ZBAR_CFG_Y_DENSITY, 1);
        }
    }
    if (!_qrScanner) {
        free(luma);
        return NO;
    }

    size_t centerX0 = width / 4;
    size_t centerX1 = width - centerX0;
    size_t centerY0 = height / 4;
    size_t centerY1 = height - centerY0;
    uint64_t centerLuma = 0;
    size_t centerSamples = 0;
    for (size_t y = centerY0; y < centerY1; y += 8) {
        for (size_t x = centerX0; x < centerX1; x += 8) {
            centerLuma += luma[y * width + x];
            centerSamples++;
        }
    }

    NSUInteger pass = _zbarPassIndex++ & 3U;
    BOOL preferInverted = (centerSamples > 0 && centerLuma / centerSamples < 110U);
    BOOL inverted = ((pass & 1U) == 0U) ? preferInverted : !preferInverted;
    BOOL useUpscaledCenter = (pass >= 2U);
    uint8_t *pixels = luma;
    uint8_t *upscaled = NULL;
    size_t scanWidth = width;
    size_t scanHeight = height;
    size_t scanLength = imageLength;

    if (useUpscaledCenter) {
        size_t cropSide = MIN(width, height) / 2;
        scanWidth = cropSide * 2;
        scanHeight = scanWidth;
        if (cropSide < 80 || scanHeight > (SIZE_MAX / scanWidth)) {
            free(luma);
            return NO;
        }
        scanLength = scanWidth * scanHeight;
        upscaled = (uint8_t *)malloc(scanLength);
        if (!upscaled) {
            free(luma);
            return NO;
        }

        size_t cropX = (width - cropSide) / 2;
        size_t cropY = (height - cropSide) / 2;
        for (size_t y = 0; y < scanHeight; y++) {
            const uint8_t *sourceRow = luma + ((cropY + y / 2) * width) + cropX;
            uint8_t *targetRow = upscaled + y * scanWidth;
            for (size_t x = 0; x < scanWidth; x++) {
                uint8_t value = sourceRow[x / 2];
                targetRow[x] = inverted ? (uint8_t)(255U - value) : value;
            }
        }
        pixels = upscaled;
    } else if (inverted) {
        for (size_t i = 0; i < imageLength; i++) luma[i] = (uint8_t)(255U - luma[i]);
    }

    zbar_image_t *image = zbar_image_create();
    if (!image) {
        free(upscaled);
        free(luma);
        return NO;
    }
    zbar_image_set_format(image, zbar_fourcc('Y', '8', '0', '0'));
    zbar_image_set_size(image, (unsigned int)scanWidth, (unsigned int)scanHeight);
    zbar_image_set_data(image, pixels, scanLength, NULL);

    NSString *text = nil;
    if (zbar_scan_image(_qrScanner, image) > 0) {
        const zbar_symbol_t *symbol = zbar_image_first_symbol(image);
        for (; symbol; symbol = zbar_symbol_next(symbol)) {
            if (zbar_symbol_get_type(symbol) != ZBAR_QRCODE) continue;
            const char *payload = zbar_symbol_get_data(symbol);
            unsigned int payloadLength = zbar_symbol_get_data_length(symbol);
            if (!payload || payloadLength == 0) continue;

            text = [[[NSString alloc] initWithBytes:payload
                                             length:(NSUInteger)payloadLength
                                           encoding:NSUTF8StringEncoding] autorelease];
            if (!text) {
                text = [[[NSString alloc] initWithBytes:payload
                                                 length:(NSUInteger)payloadLength
                                               encoding:NSISOLatin1StringEncoding] autorelease];
            }
            if (text && [text length] > 0) break;
        }
    }

    zbar_image_set_data(image, NULL, 0, NULL);
    zbar_image_destroy(image);
    free(upscaled);
    free(luma);

    if (text && [text length] > 0) {
        *decodedText = text;
        return YES;
    }

    return NO;
}
#endif

- (NSString *)configureCaptureSession {
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!camera) return @"Camera is unavailable on this device";

    _camera = [camera retain];
    [self configureContinuousCameraFocus];

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (!input) return @"Failed to access camera";

    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    } else if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    } else if ([_captureSession canSetSessionPreset:AVCaptureSessionPresetHigh]) {
        _captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    } else {
        [_captureSession release];
        _captureSession = nil;
        return @"Camera input is not supported";
    }

    if ([[UIDevice currentDevice].systemVersion integerValue] >= 11) {
        _metadataOutput = [[AVCaptureMetadataOutput alloc] init];
        if ([_captureSession canAddOutput:_metadataOutput]) {
            [_captureSession addOutput:_metadataOutput];
            [_metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        } else {
            [_metadataOutput release];
            _metadataOutput = nil;
            return @"Native QR recognition is unavailable";
        }
    }
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 110000
    else {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        _videoOutput.alwaysDiscardsLateVideoFrames = YES;
        NSDictionary *settings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                                             forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [_videoOutput setVideoSettings:settings];
        _videoQueue = dispatch_queue_create("com.vlesscore.qrscan.video", DISPATCH_QUEUE_SERIAL);
        dispatch_set_target_queue(_videoQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
        if ([_captureSession canAddOutput:_videoOutput]) {
            [_captureSession addOutput:_videoOutput];
        } else {
            [_videoOutput release];
            _videoOutput = nil;
            return @"Legacy QR recognition is unavailable";
        }
    }
#endif
    return nil;
}

- (void)applyNativeQRMetadataType {
    if (!_metadataOutput || _didFinish || !_scannerVisible) return;

    NSArray *availableTypes = [_metadataOutput availableMetadataObjectTypes];
    if (![availableTypes containsObject:kVCQRMetadataType]) return;
    @try {
        [_metadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:kVCQRMetadataType]];
    }
    @catch (NSException *exception) {
        (void)exception;
    }
}

- (void)finishCaptureSessionConfigurationWithError:(NSString *)errorText {
    if (![self canScanWithCamera]) return;
    if ([errorText length] > 0) {
        [self setScannerHintText:errorText];
        return;
    }
    if (!_captureSession || _didFinish || !_scannerVisible) return;

    if (!_previewLayer) {
        _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self.view.layer insertSublayer:_previewLayer atIndex:0];
    }
    _previewLayer.frame = self.view.bounds;
    _torchButton.hidden = !(_camera && [_camera hasTorch] &&
                            [_camera isTorchModeSupported:AVCaptureTorchModeOn] &&
                            [_camera isTorchModeSupported:AVCaptureTorchModeOff]);
    [self updateCaptureConnectionOrientations];
    [self setCaptureSessionRunning:YES];
}

- (void)beginCaptureSessionConfiguration {
    if (_captureConfigurationStarted) return;
    _captureConfigurationStarted = YES;
    dispatch_async(_sessionQueue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = [[self configureCaptureSession] retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishCaptureSessionConfigurationWithError:errorText];
            [errorText release];
        });
        [pool drain];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.58f];
    _hintLabel.textColor = [UIColor whiteColor];
    _hintLabel.font = [UIFont boldSystemFontOfSize:16.0];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.numberOfLines = 1;
    _hintLabel.layer.cornerRadius = 8.0f;
    _hintLabel.layer.masksToBounds = YES;
    [self setScannerHintText:@"Scan a QR code"];
    [self.view addSubview:_hintLabel];

    _torchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_torchButton retain];
    _torchButton.hidden = YES;
    _torchButton.accessibilityLabel = @"Flashlight";
    _torchButton.adjustsImageWhenHighlighted = YES;
    UIImage *flashlightIcon = LoadBundledIconScaled(@"icon-flashlight", 32.0f);
    [_torchButton setImage:flashlightIcon forState:UIControlStateNormal];
    [_torchButton setImage:flashlightIcon forState:UIControlStateSelected];
    _torchButton.layer.cornerRadius = 22.0f;
    [_torchButton addTarget:self action:@selector(torchPressed) forControlEvents:UIControlEventTouchUpInside];
    [self updateTorchButtonAppearance];
    [self.view addSubview:_torchButton];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setTitle:@"" forState:UIControlStateNormal];
    _cancelButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _cancelButton.layer.cornerRadius = 8.0f;
    _cancelButton.layer.borderWidth = 1.0f;
    _cancelButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    _cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [_cancelButton addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    _photoButton=[UIButton buttonWithType:UIButtonTypeCustom];
    _photoButton.backgroundColor=_cancelButton.backgroundColor;
    _photoButton.layer.cornerRadius=8; _photoButton.layer.borderWidth=1;
    _photoButton.layer.borderColor=_cancelButton.layer.borderColor;
    _photoIcon=[VCQRPhotoIcon() retain];
    [_photoButton setImage:_photoIcon forState:UIControlStateNormal];
    _photoButton.accessibilityLabel=@"Import QR from photo";
    [_photoButton addTarget:self action:@selector(photoPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_photoButton];
    _photoIndicator=[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    _photoIndicator.hidesWhenStopped=YES;
    [_photoButton addSubview:_photoIndicator];

    _cancelButtonLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _cancelButtonLabel.backgroundColor = [UIColor clearColor];
    _cancelButtonLabel.text = @"Cancel";
    _cancelButtonLabel.font = [UIFont boldSystemFontOfSize:17.0];
    _cancelButtonLabel.textAlignment = NSTextAlignmentCenter;
    _cancelButtonLabel.textColor = [UIColor whiteColor];
    _cancelButtonLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _cancelButtonLabel.shadowOffset = CGSizeMake(0.0f, -1.0f);
    _cancelButtonLabel.userInteractionEnabled = NO;
    [_cancelButton addSubview:_cancelButtonLabel];

    _focusIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 72.0f, 72.0f)];
    _focusIndicator.userInteractionEnabled = NO;
    _focusIndicator.backgroundColor = [UIColor clearColor];
    _focusIndicator.layer.cornerRadius = 8.0f;
    _focusIndicator.layer.borderWidth = 2.0f;
    _focusIndicator.layer.borderColor = [UIColor colorWithRed:1.0f green:0.82f blue:0.18f alpha:1.0f].CGColor;
    _focusIndicator.alpha = 0.0f;
    [self.view addSubview:_focusIndicator];

    _focusGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(focusTapped:)];
    _focusGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:_focusGesture];

    _sessionQueue = dispatch_queue_create("com.vlesscore.qrscan.session", DISPATCH_QUEUE_SERIAL);
    _photoQueue=dispatch_queue_create("com.vlesscore.qrscan.photo",DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(_photoQueue,dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW,0));
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scannerEnteredBackground:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(scannerBecameActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    _previewLayer.frame = b;
    [self updateCaptureConnectionOrientations];

    CGFloat pad = 14.0f;
    CGFloat top = 28.0f;
    CGRect sb = [UIApplication sharedApplication].statusBarFrame;
    CGFloat statusInset = MIN(sb.size.width, sb.size.height);
    if (statusInset > 0.0f && statusInset < 64.0f) {
        top = statusInset + 8.0f;
    }
    CGFloat hintWidth = MIN(190.0f, b.size.width - (pad * 2.0f) - 56.0f);
    _hintLabel.frame = CGRectMake(floor((b.size.width - hintWidth) * 0.5f), top, hintWidth, 42.0f);
    _torchButton.frame = CGRectMake(b.size.width - pad - 44.0f, top, 44.0f, 44.0f);
    _photoButton.frame=CGRectMake(pad,b.size.height-62.0f-pad,62,62);
    _photoIndicator.center=CGPointMake(31,31);
    _cancelButton.frame = CGRectMake(pad+74, b.size.height - 62.0f - pad, b.size.width - (pad * 2.0f)-74, 62.0f);
    _cancelButtonLabel.frame = _cancelButton.bounds;
    if (_photoPopover.popoverVisible) [_photoPopover presentPopoverFromRect:_photoButton.frame inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_didFinish || _photoReading || _photoPickerOpen || _photoErrorAlert) return;
    _zbarPassIndex = 0;
    _scanEnabledAt = HUGE_VAL;
    _nextZBarScanAt = HUGE_VAL;
    [_pendingScanResult release];
    _pendingScanResult = nil;
    _cancelButton.enabled = YES;
    _photoButton.enabled = YES;
    _torchButton.enabled = YES;
    [self setScannerHintText:@"Scan a QR code"];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0.0f alpha:0.58f];
    _hintLabel.alpha = 1.0f;
    _hintLabel.transform = CGAffineTransformIdentity;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_didFinish || _photoReading || _photoPickerOpen || _photoErrorAlert || _scannerBackground) return;
    _scannerVisible = YES;
    _scanEnabledAt = CACurrentMediaTime() + 1.0;
    _nextZBarScanAt = _scanEnabledAt;
    if (_captureSession) {
        [self finishCaptureSessionConfigurationWithError:nil];
    } else {
        [self beginCaptureSessionConfiguration];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _scannerVisible = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyDelegateOfScanResult) object:nil];
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
}

- (void)resumeScannerAfterPhoto {
    _photoReading=NO;
    [_photoIndicator stopAnimating];
    [_photoButton setImage:_photoIcon forState:UIControlStateNormal];
    _photoButton.enabled=!_didFinish;
    if (!_didFinish) { _cancelButton.enabled=YES; _torchButton.enabled=YES; }
    if (_didFinish || _photoPickerOpen || _photoErrorAlert || _scannerBackground || !self.view.window) return;
    _scannerVisible=YES;
    [self setScannerHintText:@"Scan a QR code"];
    _scanEnabledAt=CACurrentMediaTime()+1; _nextZBarScanAt=_scanEnabledAt;
    if (_captureSession) [self finishCaptureSessionConfigurationWithError:nil];
    else [self beginCaptureSessionConfiguration];
}

- (void)showPhotoError:(NSString *)message {
    if (_didFinish || _scannerBackground) return;
    if (_photoErrorAlert) return;
    _photoErrorAlert=[[UIAlertView alloc] initWithTitle:@"QR import" message:message delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
    _scannerVisible=NO;
    [self setTorchEnabled:NO]; [self setCaptureSessionRunning:NO];
    [self resumeScannerAfterPhoto]; [_photoErrorAlert show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    (void)buttonIndex;
    if (alertView!=_photoErrorAlert) return;
    _photoErrorAlert.delegate=nil; [_photoErrorAlert release]; _photoErrorAlert=nil;
    [self resumeScannerAfterPhoto];
}

- (void)closePhotoPicker:(void (^)(void))completion {
    _photoPicker.delegate=nil;
    _photoPickerOpen=NO;
    if (_photoPopover) {
        _photoPopover.delegate=nil; [_photoPopover dismissPopoverAnimated:YES];
        [_photoPopover release]; _photoPopover=nil;
        [_photoPicker release]; _photoPicker=nil;
        if (completion) completion();
    } else {
        [_photoPicker release]; _photoPicker=nil;
        [self dismissViewControllerAnimated:!_scannerBackground completion:completion];
    }
}

- (void)photoPressed {
    if (_didFinish || _photoReading || _photoPickerOpen || _scannerBackground) return;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        [self showPhotoError:@"Photo library is unavailable"]; return;
    }
    if ([ALAssetsLibrary respondsToSelector:@selector(authorizationStatus)]) {
        ALAuthorizationStatus status=[ALAssetsLibrary authorizationStatus];
        if (status==ALAuthorizationStatusDenied || status==ALAuthorizationStatusRestricted) {
            [self showPhotoError:VCPhotoLibraryAccessError()]; return;
        }
    }
    _photoPickerOpen=YES; _scannerVisible=NO;
    _torchButton.enabled=NO;
    [self setTorchEnabled:NO]; [self setCaptureSessionRunning:NO];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    _focusIndicator.alpha=0;
    _photoPicker=[[UIImagePickerController alloc] init];
    _photoPicker.sourceType=UIImagePickerControllerSourceTypePhotoLibrary;
    _photoPicker.mediaTypes=@[@"public.image"]; _photoPicker.allowsEditing=NO; _photoPicker.delegate=self;
    if (IsPadDevice()) {
        _photoPopover=[[UIPopoverController alloc] initWithContentViewController:_photoPicker];
        _photoPopover.delegate=self;
        [_photoPopover presentPopoverFromRect:_photoButton.frame inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else [self presentViewController:_photoPicker animated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    if (picker!=_photoPicker) return;
    [self closePhotoPicker:^{ [self resumeScannerAfterPhoto]; }];
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popover {
    if (popover!=_photoPopover) return;
    _photoPicker.delegate=nil; [_photoPicker release]; _photoPicker=nil;
    _photoPopover.delegate=nil; [_photoPopover release]; _photoPopover=nil;
    _photoPickerOpen=NO; [self resumeScannerAfterPhoto];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if (picker!=_photoPicker || !_photoPickerOpen || _didFinish) return;
    NSURL *url=nil;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 110000
    if ([[UIDevice currentDevice].systemVersion integerValue]>=11) url=[info objectForKey:UIImagePickerControllerImageURL];
#endif
    if (!url) url=[info objectForKey:UIImagePickerControllerReferenceURL];
    if (![url isKindOfClass:[NSURL class]]) url=nil;
    _photoReading=YES;
    _photoButton.enabled=NO; [_photoButton setImage:nil forState:UIControlStateNormal]; [_photoIndicator startAnimating];
    [self setScannerHintText:@"Reading QR codes…"];
    NSUInteger generation=++_photoGeneration;
    [_photoOperation cancel]; [_photoOperation release];
    _photoOperation=[[NSOperation alloc] init];
    NSOperation *operation=_photoOperation;
    [self closePhotoPicker:^{
        if (_didFinish || _scannerBackground || operation.isCancelled || generation!=_photoGeneration) return;
        dispatch_async(_photoQueue,^{
            NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
            NSString *error=nil;
            NSArray *texts=[VCReadPhotoQR(url,operation,&error) copy];
            NSString *failure=[error copy];
            dispatch_async(dispatch_get_main_queue(),^{
                if (!_didFinish && !_scannerBackground && generation==_photoGeneration && !operation.isCancelled) {
                    [_photoOperation release]; _photoOperation=nil;
                    if ([texts count]) {
                        _didFinish=YES; _photoReading=NO; _cancelButton.enabled=NO;
                        [_photoIndicator stopAnimating];
                        if ([_delegate respondsToSelector:@selector(qrScanVC:didScanTexts:)]) [_delegate qrScanVC:self didScanTexts:texts];
                    } else [self showPhotoError:failure ?: @"Unable to read the selected photo"];
                }
                [texts release]; [failure release];
            });
            [pool drain];
        });
    }];
}

- (void)scannerEnteredBackground:(NSNotification *)notification {
    (void)notification;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(configureContinuousCameraFocus) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideFocusIndicator) object:nil];
    _scannerBackground=YES; _scannerVisible=NO; _photoGeneration++;
    if (_pendingScanResult) { [_pendingScanResult release]; _pendingScanResult=nil; _didFinish=NO; }
    [_photoOperation cancel]; [_photoOperation release]; _photoOperation=nil;
    _photoReading=NO;
    [_photoIndicator stopAnimating];
    [self setTorchEnabled:NO]; [self setCaptureSessionRunning:NO];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(notifyDelegateOfScanResult) object:nil];
    if (_photoPickerOpen) [self closePhotoPicker:nil];
}

- (void)scannerBecameActive:(NSNotification *)notification {
    (void)notification;
    BOOL wasBackground=_scannerBackground; _scannerBackground=NO;
    if (wasBackground) [self resumeScannerAfterPhoto];
}

- (void)cancelPressed {
    if (_didFinish) return;
    _didFinish = YES;
    _photoGeneration++;
    [_photoOperation cancel]; [_photoOperation release]; _photoOperation=nil;
    _photoButton.enabled=NO;
    _cancelButton.enabled = NO;
    _torchButton.enabled = NO;
    [_pendingScanResult release];
    _pendingScanResult = nil;
    [self setTorchEnabled:NO];
    [self setCaptureSessionRunning:NO];
    if ([_delegate respondsToSelector:@selector(qrScanVCDidCancel:)]) {
        [_delegate qrScanVCDidCancel:self];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    if (![self canScanWithCamera] || ![metadataObjects isKindOfClass:[NSArray class]]) return;

    for (id object in metadataObjects) {
        if (![object respondsToSelector:@selector(type)] ||
            ![object respondsToSelector:@selector(stringValue)]) {
            continue;
        }
        NSString *type = [object performSelector:@selector(type)];
        if (![type isEqualToString:kVCQRMetadataType]) continue;
        NSString *value = [object performSelector:@selector(stringValue)];
        if (![value isKindOfClass:[NSString class]] || [value length] == 0) continue;
        [self deliverScanResult:value];
        return;
    }
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED < 110000
- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    NSTimeInterval now = CACurrentMediaTime();
    if (_didFinish || now < _scanEnabledAt || now < _nextZBarScanAt) return;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *decoded = nil;
    BOOL found = [self tryDecodeFrameWithZBar:sampleBuffer decodedText:&decoded];
    _nextZBarScanAt = CACurrentMediaTime() + 0.18;
    if (!found) {
        [pool drain];
        return;
    }
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        [pool drain];
        return;
    }

    NSString *captured = [decoded copy];
    [pool drain];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self deliverScanResult:captured];
        [captured release];
    });
}
#endif

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_photoOperation cancel]; [_photoOperation release];
    _photoPicker.delegate=nil; _photoPopover.delegate=nil;
    [_photoPopover dismissPopoverAnimated:NO]; [_photoPopover release]; [_photoPicker release];
    [_photoIndicator release];
    [_photoIcon release];
    _photoErrorAlert.delegate=nil; [_photoErrorAlert dismissWithClickedButtonIndex:0 animated:NO]; [_photoErrorAlert release];
    if (_photoQueue) dispatch_release(_photoQueue);
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_videoOutput setSampleBufferDelegate:nil queue:NULL];
    [_metadataOutput setMetadataObjectsDelegate:nil queue:NULL];
    [_previewLayer setSession:nil];
    if (_sessionQueue) {
        dispatch_release(_sessionQueue);
        _sessionQueue = NULL;
    }
    if (_videoQueue) {
        dispatch_release(_videoQueue);
        _videoQueue = NULL;
    }
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 110000
    if (_qrScanner) {
        zbar_image_scanner_destroy(_qrScanner);
        _qrScanner = NULL;
    }
#endif
    [_captureSession release];
    [_camera release];
    [_metadataOutput release];
    [_videoOutput release];
    [_previewLayer release];
    [_hintLabel release];
    [_torchButton release];
    [_cancelButtonLabel release];
    [_focusIndicator release];
    [_focusGesture release];
    [_pendingScanResult release];
    [super dealloc];
}

@end
