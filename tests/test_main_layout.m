#import <Foundation/Foundation.h>
#include "../common/main_geometry.h"
#include "check.h"
#include <math.h>

typedef struct { CGFloat top, left, bottom, right; } UIEdgeInsets;
#ifndef VC_PHONE_LAYOUT_STATE
typedef struct { int valid; } VCPhoneLayoutState;
#endif
static BOOL CGRectEqualToRect(CGRect a, CGRect b) { return a.origin.x==b.origin.x && a.origin.y==b.origin.y && a.size.width==b.size.width && a.size.height==b.size.height; }
enum { NSTextAlignmentCenter, NSTextAlignmentLeft };
static unsigned transactions, shadowPaths;
static BOOL pad;
static CGFloat statusInset;
static BOOL IsPadDevice(void) { return pad; }
static CGFloat VCMainStatusBarInset(void) { return statusInset; }
static CGRect CGRectInset(CGRect r, CGFloat x, CGFloat y) {
    return CGRectMake(r.origin.x + x, r.origin.y + y, r.size.width - 2*x, r.size.height - 2*y);
}
static BOOL CGSizeEqualToSize(CGSize a, CGSize b) { return a.width == b.width && a.height == b.height; }

@interface UIFont : NSObject { CGFloat _pointSize; }
@property(readonly) CGFloat pointSize;
+ (id)boldSystemFontOfSize:(CGFloat)size;
+ (id)systemFontOfSize:(CGFloat)size;
@end
@implementation UIFont
@synthesize pointSize = _pointSize;
+ (id)systemFontOfSize:(CGFloat)size {
    UIFont *font = [[[self alloc] init] autorelease]; font->_pointSize = size; return font;
}
+ (id)boldSystemFontOfSize:(CGFloat)size { return [self systemFontOfSize:size]; }
@end

@interface CALayer : NSObject { CGFloat _cornerRadius; void *_shadowPath; }
@property CGFloat cornerRadius;
@property void *shadowPath;
@end
@implementation CALayer
@synthesize cornerRadius = _cornerRadius;
- (void *)shadowPath { return _shadowPath; }
- (void)setShadowPath:(void *)path { _shadowPath = path; shadowPaths++; }
@end

@interface UIView : NSObject {
    CGRect _frame;
    CALayer *_layer;
    UIFont *_font;
    CGFloat _alpha;
    NSInteger _textAlignment;
    CGPoint _contentOffset;
    UIEdgeInsets _scrollIndicatorInsets;
}
@property CGRect frame;
@property(readonly) CGRect bounds;
@property(readonly) CALayer *layer;
@property(retain) UIFont *font;
@property CGFloat alpha;
@property NSInteger textAlignment;
@property CGPoint contentOffset;
@property UIEdgeInsets scrollIndicatorInsets;
@end
@implementation UIView
@synthesize frame = _frame, layer = _layer, font = _font, alpha = _alpha;
@synthesize textAlignment = _textAlignment, contentOffset = _contentOffset, scrollIndicatorInsets = _scrollIndicatorInsets;
- (id)init { if ((self = [super init])) _layer = [[CALayer alloc] init]; return self; }
- (CGRect)bounds { return CGRectMake(0, 0, _frame.size.width, _frame.size.height); }
- (void)dealloc { [_layer release]; [_font release]; [super dealloc]; }
@end

@interface UIBezierPath : NSObject
+ (UIBezierPath *)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius;
@property(readonly) void *CGPath;
@end
@implementation UIBezierPath
+ (UIBezierPath *)bezierPathWithRoundedRect:(CGRect)rect cornerRadius:(CGFloat)radius {
    (void)rect; (void)radius; return [[[self alloc] init] autorelease];
}
- (void *)CGPath { return (void *)1; }
@end

@interface CATransaction : NSObject
+ (void)begin;
+ (void)setDisableActions:(BOOL)disable;
+ (void)commit;
@end
@implementation CATransaction
+ (void)begin { transactions++; }
+ (void)setDisableActions:(BOOL)disable { CHECK("layout/implicit-actions-disabled", disable); }
+ (void)commit {}
@end
static void VCSetLabelMinimumScaleFactor(UIView *label, CGFloat value) { (void)label; (void)value; }
#define VC_PERF_SCOPE(...) ((void)0)
#define VC_PERF_COUNT(...) ((void)0)

@interface MainVC : NSObject {
@public
    UIView *_view, *_tableView, *_connectBtn, *_uptimeLabel, *_statusLabel, *_mainSwitchView;
    UIView *_connectGlowView, *_compactConnectGlowView, *_connectPowerIcon, *_connectButtonTitle;
    UIView *_connectionStateLabel, *_selectionLabel, *_logSelector, *_logView;
    BOOL _mainSectionTransitionInProgress, _showingTerminal, _phoneConnectionCompact;
    VCPhoneLayoutState _phoneLayoutState;
}
@property(readonly) UIView *view;
- (void)updatePhoneConnectionLayout;
@end
@implementation MainVC
@synthesize view = _view;
- (id)init {
    if ((self = [super init])) {
        UIView **views[] = {&_view, &_connectBtn, &_uptimeLabel, &_statusLabel, &_connectGlowView,
            &_compactConnectGlowView, &_connectPowerIcon, &_connectButtonTitle, &_connectionStateLabel, &_selectionLabel};
        for (unsigned i = 0; i < sizeof(views)/sizeof(views[0]); i++) *views[i] = [[UIView alloc] init];
        _view.frame = CGRectMake(0, 0, 320, 480);
    }
    return self;
}
- (void)dealloc {
    UIView *views[] = {_view, _tableView, _connectBtn, _uptimeLabel, _statusLabel, _mainSwitchView,
        _connectGlowView, _compactConnectGlowView, _connectPowerIcon, _connectButtonTitle,
        _connectionStateLabel, _selectionLabel, _logSelector, _logView};
    for (unsigned i = 0; i < sizeof(views)/sizeof(views[0]); i++) [views[i] release];
    [super dealloc];
}
#include "main_phone_layout.inc"
@end

static void checkGeometry(MainVC *controller, CGFloat progress) {
    VCMainGeometry expected = VCPhoneGeometry(320, statusInset, progress);
    CGRect button = controller->_connectBtn.frame, switcher = controller->_mainSwitchView.frame;
    CHECK("layout/actual-button-geometry", memcmp(&button, &expected.button, sizeof(CGRect)) == 0);
    CHECK("layout/actual-switcher-geometry", memcmp(&switcher, &expected.switcher, sizeof(CGRect)) == 0);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    MainVC *controller = [[MainVC alloc] init];
    controller->_tableView = [[UIView alloc] init];
    controller->_tableView.frame = CGRectMake(0, 186, 320, 294);
    [controller updatePhoneConnectionLayout];
    controller->_tableView.contentOffset = (CGPoint){0, -128};
    [controller updatePhoneConnectionLayout];
    BOOL cachedWhileIncomplete = controller->_phoneLayoutState.valid;
    controller->_mainSwitchView = [[UIView alloc] init];
    controller->_mainSwitchView.frame = CGRectMake(10, 138, 300, 48);
    [controller updatePhoneConnectionLayout];
    CHECK("layout/cold-start-switcher-does-not-cover-connect", controller->_mainSwitchView.frame.origin.y >=
        controller->_connectBtn.frame.origin.y + controller->_connectBtn.frame.size.height);
    CHECK("layout/cold-start-does-not-cache-missing-switcher", !cachedWhileIncomplete);
    checkGeometry(controller, 0);
    CHECK("layout/cold-start-only-one-complete-pass", transactions == 1);
    unsigned before = transactions;
    [controller updatePhoneConnectionLayout];
    CHECK("layout/cold-start-second-pass-still-skipped", transactions == before);
    for (unsigned i = 0; i <= 128; i++) {
        controller->_tableView.contentOffset = (CGPoint){0, (CGFloat)i - 128};
        [controller updatePhoneConnectionLayout];
        checkGeometry(controller, i / 128.0);
        before = transactions;
        [controller updatePhoneConnectionLayout];
        CHECK("layout/actual-duplicate-skipped", transactions == before);
    }
    before = transactions;
    controller->_tableView.contentOffset = (CGPoint){0, 1000};
    [controller updatePhoneConnectionLayout];
    CHECK("layout/actual-compact-scroll-skipped", transactions == before);
    unsigned pathsBefore = shadowPaths;
    controller->_view.frame = CGRectMake(0, 0, 320, 500);
    [controller updatePhoneConnectionLayout];
    CHECK("layout/actual-resize-applied", transactions == before + 1);
    CHECK("layout/unchanged-button-size-reuses-shadow", shadowPaths == pathsBefore);
    controller->_compactConnectGlowView.layer.cornerRadius = 99;
    [controller updatePhoneConnectionLayout];
    CHECK("layout/changed-corner-repairs-shadow",shadowPaths==pathsBefore+1 && controller->_compactConnectGlowView.layer.cornerRadius==controller->_connectBtn.layer.cornerRadius);
    controller->_compactConnectGlowView.layer.shadowPath = NULL;
    pathsBefore=shadowPaths;
    [controller updatePhoneConnectionLayout];
    CHECK("layout/missing-shadow-rebuilt",shadowPaths==pathsBefore+1 && controller->_compactConnectGlowView.layer.shadowPath!=NULL);
    UIEdgeInsets insets = controller->_tableView.scrollIndicatorInsets;
    insets.top = 12; insets.bottom = 7;
    controller->_tableView.scrollIndicatorInsets = insets;
    [controller updatePhoneConnectionLayout];
    CHECK("layout/indicator-repaired-without-losing-bottom", controller->_tableView.scrollIndicatorInsets.top == 0 &&
        controller->_tableView.scrollIndicatorInsets.bottom == 7);
    controller->_showingTerminal = YES;
    controller->_logSelector = [[UIView alloc] init]; controller->_logView = [[UIView alloc] init];
    [controller updatePhoneConnectionLayout];
    CHECK("layout/terminal-geometry-ready", controller->_logView.frame.origin.y == 170 &&
        controller->_logView.frame.size.height == 330);
    statusInset = 20;
    [controller updatePhoneConnectionLayout];
    checkGeometry(controller, 1);
    CHECK("layout/terminal-status-bar-change", controller->_logView.frame.origin.y == 190);
    controller->_showingTerminal = NO;
    [controller updatePhoneConnectionLayout];
    before = transactions;
    controller->_mainSectionTransitionInProgress = YES;
    controller->_tableView.contentOffset = (CGPoint){0, -128};
    [controller updatePhoneConnectionLayout];
    CHECK("layout/structural-transition-keeps-layout", transactions == before);
    controller->_mainSectionTransitionInProgress = NO;
    [controller updatePhoneConnectionLayout];
    checkGeometry(controller, 0);
    before = transactions;
    pad = YES; [controller updatePhoneConnectionLayout];
    CHECK("layout/ipad-path-unchanged", transactions == before);
    pad = NO;
    MainVC *terminal = [[MainVC alloc] init];
    terminal->_showingTerminal = YES;
    terminal->_tableView = [[UIView alloc] init];
    terminal->_mainSwitchView = [[UIView alloc] init];
    [terminal updatePhoneConnectionLayout];
    terminal->_logView = [[UIView alloc] init]; terminal->_logSelector = [[UIView alloc] init];
    terminal->_phoneLayoutState.valid = 0;
    [terminal updatePhoneConnectionLayout];
    CHECK("layout/completed-view-refreshes-late-log-controls", terminal->_logView.frame.origin.y == 318 &&
        terminal->_logSelector.frame.origin.y == 288);
    [terminal release];
    [controller release]; [pool drain];
    FINISH("main layout callbacks"); return 0;
}
