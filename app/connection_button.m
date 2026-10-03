#import "connection_button.h"

static void VCAddPowerArc(CGMutablePathRef path, CGPoint center, CGFloat radius,
                          CGFloat start, CGFloat end) {
    CGFloat tangent = (4.0f / 3.0f) * tanf((end - start) * 0.25f);
    CGPathAddCurveToPoint(path, NULL,
                         center.x + radius * (cosf(start) - tangent * sinf(start)),
                         center.y + radius * (sinf(start) + tangent * cosf(start)),
                         center.x + radius * (cosf(end) + tangent * sinf(end)),
                         center.y + radius * (sinf(end) - tangent * cosf(end)),
                         center.x + radius * cosf(end), center.y + radius * sinf(end));
}

static CGPathRef VCCreatePowerPath(BOOL loading) {
    CGPoint center = CGPointMake(18.0f, loading ? 18.0f : 19.8f);
    CGFloat radius = 12.24f;
    CGFloat start = -M_PI * 0.25f;
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, center.x + radius * cosf(start), center.y + radius * sinf(start));
    for (NSInteger i = 0; i < 4; i++) {
        CGFloat a = start + M_PI * 1.5f * i / 4.0f;
        CGFloat b = start + M_PI * 1.5f * (i + 1) / 4.0f;
        VCAddPowerArc(path, center, radius, a, b);
    }
    if (loading) {
        CGFloat a = M_PI * 1.25f;
        CGPathMoveToPoint(path, NULL, center.x + radius * cosf(a), center.y + radius * sinf(a));
        VCAddPowerArc(path, center, radius, a, a + M_PI / 6.0f);
    } else {
        CGPathMoveToPoint(path, NULL, 18.0f, 6.84f);
        CGPathAddCurveToPoint(path, NULL, 18.0f, 10.32f, 18.0f, 13.8f, 18.0f, 17.28f);
    }
    return path;
}

static CFTimeInterval const kVCPowerMorphDuration = 0.28;
static CFTimeInterval const kVCPowerSpinDuration = 0.85;
static CFTimeInterval const kVCPowerMinimumLoadingDuration = 0.65;

@implementation VCConnectionPowerView
- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        _powerPath = VCCreatePowerPath(NO);
        _spinnerPath = VCCreatePowerPath(YES);
        _scaleLayer = [[CALayer alloc] init];
        _scaleLayer.bounds = CGRectMake(0.0f, 0.0f, 36.0f, 36.0f);
        [self.layer addSublayer:_scaleLayer];
        _symbolLayer = [[CAShapeLayer alloc] init];
        _symbolLayer.frame = _scaleLayer.bounds;
        _symbolLayer.contentsScale = [UIScreen mainScreen].scale;
        _symbolLayer.fillColor = NULL;
        _symbolLayer.strokeColor = [UIColor whiteColor].CGColor;
        _symbolLayer.lineWidth = 3.24f;
        _symbolLayer.lineCap = kCALineCapRound;
        _symbolLayer.lineJoin = kCALineJoinRound;
        _symbolLayer.path = _powerPath;
        [_scaleLayer addSublayer:_symbolLayer];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _scaleLayer.position = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    CGFloat scale = MIN(self.bounds.size.width, self.bounds.size.height) / 36.0f;
    _scaleLayer.transform = CATransform3DMakeScale(scale, scale, 1.0f);
    [CATransaction commit];
}

- (void)setLoading:(BOOL)loading {
    if (_loadingRequested == loading) return;
    _loadingRequested = loading;
    NSUInteger generation = ++_transitionGeneration;
    if (loading) {
        _loadingStartedAt = CACurrentMediaTime();
        if (![_symbolLayer animationForKey:@"powerSpin"]) [self animateLoading:YES];
        return;
    }
    CFTimeInterval remaining = kVCPowerMinimumLoadingDuration - (CACurrentMediaTime() - _loadingStartedAt);
    if (remaining > 0.0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation == _transitionGeneration && !_loadingRequested) [self animateLoading:NO];
        });
    } else {
        [self animateLoading:NO];
    }
}

- (void)animateLoading:(BOOL)loading {
    CAShapeLayer *visible = (CAShapeLayer *)(_symbolLayer.presentationLayer ?: _symbolLayer);
    CGPathRef fromPath = CGPathCreateCopy(visible.path ?: _symbolLayer.path);
    CGFloat angle = [[visible valueForKeyPath:@"transform.rotation.z"] floatValue];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [_symbolLayer removeAnimationForKey:@"powerMorph"];
    [_symbolLayer removeAnimationForKey:@"powerSpin"];
    [_symbolLayer removeAnimationForKey:@"powerSettle"];
    _symbolLayer.path = loading ? _spinnerPath : _powerPath;
    _symbolLayer.transform = loading ? CATransform3DMakeRotation(angle, 0.0f, 0.0f, 1.0f) : CATransform3DIdentity;

    CABasicAnimation *morph = [CABasicAnimation animationWithKeyPath:@"path"];
    morph.fromValue = (id)fromPath;
    morph.toValue = (id)_symbolLayer.path;
    morph.duration = kVCPowerMorphDuration;
    morph.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [_symbolLayer addAnimation:morph forKey:@"powerMorph"];

    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = [NSNumber numberWithFloat:angle];
    if (loading) {
        rotation.toValue = [NSNumber numberWithFloat:angle + M_PI * 2.0f];
        rotation.duration = kVCPowerSpinDuration;
        rotation.beginTime = [_symbolLayer convertTime:CACurrentMediaTime() fromLayer:nil] + morph.duration;
        rotation.repeatCount = HUGE_VALF;
        rotation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
        [_symbolLayer addAnimation:rotation forKey:@"powerSpin"];
    } else {
        rotation.toValue = [NSNumber numberWithFloat:0.0f];
        rotation.duration = morph.duration;
        rotation.timingFunction = morph.timingFunction;
        [_symbolLayer addAnimation:rotation forKey:@"powerSettle"];
    }
    [CATransaction commit];
    CGPathRelease(fromPath);
}

- (void)dealloc {
    CGPathRelease(_powerPath);
    CGPathRelease(_spinnerPath);
    [_symbolLayer release];
    [_scaleLayer release];
    [super dealloc];
}
@end

UIImage *VCMakeConnectionGlow(UIColor *color) {
    const CGFloat *rgb = CGColorGetComponents(color.CGColor);
    CGFloat components[] = {
        rgb[0], rgb[1], rgb[2], 0.82f,
        rgb[0], rgb[1], rgb[2], 0.50f,
        rgb[0], rgb[1], rgb[2], 0.0f
    };
    CGFloat locations[] = { 0.0f, 0.58f, 1.0f };
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, locations, 3);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(180.0f, 180.0f), NO, 0.0f);
    CGContextDrawRadialGradient(UIGraphicsGetCurrentContext(), gradient,
                                CGPointMake(90.0f, 90.0f), 0.0f,
                                CGPointMake(90.0f, 90.0f), 90.0f, 0);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    return image;
}
