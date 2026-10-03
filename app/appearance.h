#import "app_support.h"

@class VCMarqueeLabel;

@interface VCMarqueeLabel : UIView {
    UILabel *_label;
    NSString *_text;
    NSTimer *_startTimer;
    NSTimer *_endPauseTimer;
    CGFloat _overflowWidth;
    CGSize _lastBoundsSize;
    BOOL _needsRefresh;
}
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic, retain) UIColor *textColor;
- (void)stopMarquee;
- (void)restartMarquee;
@end
