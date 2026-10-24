#import "app_support.h"

@class VCConnectionPowerView;

@interface VCConnectionPowerView : UIView {
    CALayer *_scaleLayer;
    CAShapeLayer *_symbolLayer;
    CGPathRef _powerPath;
    CGPathRef _spinnerPath;
    CGPathRef _progressPath;
    BOOL _loadingRequested;
    BOOL _progressRequested;
    CFTimeInterval _loadingStartedAt;
    NSUInteger _transitionGeneration;
}
- (void)setLoading:(BOOL)loading;
- (void)setProgress:(CGFloat)progress;
- (void)animateLoading:(BOOL)loading;
@end
