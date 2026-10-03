#import "app_support.h"

@class VCConnectionPowerView;

@interface VCConnectionPowerView : UIView {
    CALayer *_scaleLayer;
    CAShapeLayer *_symbolLayer;
    CGPathRef _powerPath;
    CGPathRef _spinnerPath;
    BOOL _loadingRequested;
    CFTimeInterval _loadingStartedAt;
    NSUInteger _transitionGeneration;
}
- (void)setLoading:(BOOL)loading;
- (void)animateLoading:(BOOL)loading;
@end
