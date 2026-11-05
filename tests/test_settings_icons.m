#import <Foundation/Foundation.h>
#include "../common/main_geometry.h"
#include "check.h"
#include <math.h>
#include "settings_icon_types.inc"
;

typedef NSString UIColor;
typedef NSString UIImage;
@interface NSString (VCIconColor)
- (const void *)CGColor;
+ (NSString *)clearColor;
@end
@implementation NSString (VCIconColor)
- (const void *)CGColor { return self; }
+ (NSString *)clearColor { return @"clear"; }
@end

static unsigned renders, strokes, points, ellipses, failRender;
static BOOL failContext, dark;
static NSInteger accent;
static CGFloat screenScale=2;
static CGPoint current, origin;
static NSMutableString *path;
static const void *strokeColor;
static CGSize contextSize;
static CGFloat lineWidth;
static int lineCap,lineJoin;
typedef void *CGContextRef;
enum { kCGLineCapRound=1,kCGLineJoinRound=1 };
static CGSize CGSizeMake(CGFloat w,CGFloat h) { return (CGSize){w,h}; }
static const CGSize CGSizeZero={0,0};
static const CGRect CGRectZero={{0,0},{0,0}};
static BOOL CGSizeEqualToSize(CGSize a,CGSize b) { return a.width==b.width && a.height==b.height; }
static UIColor *VCAccentColor(void) { return [NSString stringWithFormat:@"%d/%ld",dark,(long)accent]; }
static UIColor *VCPrimaryTextColor(void) { return dark ? @"primary-dark" : @"primary-light"; }
static UIColor *VCSecondaryTextColor(void) { return dark ? @"secondary-dark" : @"secondary-light"; }
static void UIGraphicsBeginImageContextWithOptions(CGSize size,BOOL opaque,CGFloat scale) {
    CHECK("settings-icons/context-transparent-and-native-scale",!opaque && scale==0);
    contextSize=size; renders++; strokes=points=ellipses=0;
    [path setString:@""];
}
static CGContextRef UIGraphicsGetCurrentContext(void) { return failContext ? NULL : (void *)1; }
static void UIGraphicsEndImageContext(void) {}
static UIImage *UIGraphicsGetImageFromCurrentImageContext(void) {
    if (renders==failRender) return nil;
    return [NSString stringWithFormat:@"render-%u",renders];
}
static void CGContextSetStrokeColorWithColor(CGContextRef ctx,const void *color) { (void)ctx; strokeColor=color; }
static void CGContextSetLineWidth(CGContextRef ctx,CGFloat width) { (void)ctx; lineWidth=width; }
static void CGContextSetLineCap(CGContextRef ctx,int cap) { (void)ctx; lineCap=cap; }
static void CGContextSetLineJoin(CGContextRef ctx,int join) { (void)ctx; lineJoin=join; }
static void point(CGFloat x,CGFloat y) {
    CHECK("settings-icons/path-finite-and-unclipped",isfinite(x) && isfinite(y) && x>=1.49 && y>=1.49 && x<=22.51 && y<=22.51);
    points++;
}
static void CGContextBeginPath(CGContextRef ctx) { (void)ctx; }
static void CGContextMoveToPoint(CGContextRef ctx,CGFloat x,CGFloat y) {
    (void)ctx; current=origin=(CGPoint){x,y}; point(x,y); [path appendFormat:@"M%.6f,%.6f",(double)x,(double)y];
}
static void CGContextAddLineToPoint(CGContextRef ctx,CGFloat x,CGFloat y) {
    (void)ctx; current=(CGPoint){x,y}; point(x,y); [path appendFormat:@"L%.6f,%.6f",(double)x,(double)y];
}
static void CGContextAddCurveToPoint(CGContextRef ctx,CGFloat x1,CGFloat y1,CGFloat x2,CGFloat y2,CGFloat x,CGFloat y) {
    (void)ctx;
    for (unsigned i=1;i<=32;i++) {
        double t=i/32.0,u=1-t;
        point(u*u*u*current.x+3*u*u*t*x1+3*u*t*t*x2+t*t*t*x,
              u*u*u*current.y+3*u*u*t*y1+3*u*t*t*y2+t*t*t*y);
    }
    current=(CGPoint){x,y};
    [path appendFormat:@"C%.6f,%.6f,%.6f,%.6f,%.6f,%.6f",(double)x1,(double)y1,(double)x2,(double)y2,(double)x,(double)y];
}
static void CGContextClosePath(CGContextRef ctx) { (void)ctx; current=origin; [path appendString:@"Z"]; }
static void CGContextAddEllipseInRect(CGContextRef ctx,CGRect r) {
    (void)ctx;
    ellipses++;
    point(r.origin.x,r.origin.y); point(r.origin.x+r.size.width,r.origin.y+r.size.height);
    [path appendFormat:@"E%.6f,%.6f,%.6f,%.6f",(double)r.origin.x,(double)r.origin.y,(double)r.size.width,(double)r.size.height];
}
static void CGContextStrokePath(CGContextRef ctx) { (void)ctx; strokes++; [path appendString:@";"]; }
#include "settings_icon_draw.inc"

enum { NSLineBreakByWordWrapping=0,UITableViewCellAccessoryCheckmark=3 };
static NSUInteger measurements;
@interface UIFont : NSObject {
    CGFloat _lineHeight,_glyphWidth;
}
@property CGFloat lineHeight,glyphWidth;
@end
@implementation UIFont
@synthesize lineHeight=_lineHeight,glyphWidth=_glyphWidth;
@end
@interface NSString (VCSettingsMeasure)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode;
@end
@implementation NSString (VCSettingsMeasure)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode {
    (void)mode; measurements++;
    CGFloat lines=self.length ? ceil(self.length*font.glyphWidth/MAX(1.0,size.width)) : 0;
    return CGSizeMake(MIN(size.width,self.length*font.glyphWidth),lines*font.lineHeight);
}
@end
#include "settings_row_type.inc"
VCSettingsRowLayout;
#include "settings_row_layout.inc"

@interface UIView : NSObject {
    CGRect _frame;
    BOOL _hidden,_isAccessibilityElement,_userInteractionEnabled,_needsLayout;
    UIColor *_backgroundColor;
    UIView *_superview;
    NSMutableArray *_children;
}
@property CGRect frame;
@property(readonly) CGRect bounds;
@property BOOL hidden,isAccessibilityElement,userInteractionEnabled;
@property(retain) UIColor *backgroundColor;
@property(readonly) UIView *superview;
- (id)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;
- (void)setNeedsLayout;
- (void)layoutIfNeeded;
- (void)layoutSubviews;
@end
@implementation UIView
@synthesize frame=_frame,hidden=_hidden,isAccessibilityElement=_isAccessibilityElement,userInteractionEnabled=_userInteractionEnabled,backgroundColor=_backgroundColor,superview=_superview;
- (id)init { if ((self=[super init])) { _children=[[NSMutableArray alloc] init]; _userInteractionEnabled=YES; } return self; }
- (id)initWithFrame:(CGRect)frame { if ((self=[self init])) _frame=frame; return self; }
- (CGRect)bounds { return CGRectMake(0,0,_frame.size.width,_frame.size.height); }
- (void)dealloc { for (UIView *view in _children) view->_superview=nil; [_children release]; [_backgroundColor release]; [super dealloc]; }
- (void)addSubview:(UIView *)view { [view retain]; [view removeFromSuperview]; [_children addObject:view]; view->_superview=self; [view release]; }
- (void)removeFromSuperview { [self retain]; if (_superview) [_superview->_children removeObjectIdenticalTo:self]; _superview=nil; [self release]; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {
    for (UIView *parent=self;parent;parent=parent.superview) { rect.origin.x+=parent.frame.origin.x; rect.origin.y+=parent.frame.origin.y; }
    for (UIView *parent=view;parent;parent=parent.superview) { rect.origin.x-=parent.frame.origin.x; rect.origin.y-=parent.frame.origin.y; }
    return rect;
}
- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view { return [view convertRect:rect toView:self]; }
- (void)setNeedsLayout { _needsLayout=YES; }
- (void)layoutIfNeeded { if (_needsLayout) { _needsLayout=NO; [self layoutSubviews]; } }
- (void)layoutSubviews {}
@end
@interface UILabel : UIView {
    NSString *_text;
    UIFont *_font;
    UIColor *_textColor,*_highlightedTextColor;
    NSInteger _numberOfLines,_lineBreakMode;
    BOOL _adjustsFontSizeToFitWidth;
}
@property(copy) NSString *text;
@property(retain) UIFont *font;
@property(retain) UIColor *textColor,*highlightedTextColor;
@property NSInteger numberOfLines,lineBreakMode;
@property BOOL adjustsFontSizeToFitWidth;
@end
@implementation UILabel
@synthesize text=_text,font=_font,textColor=_textColor,highlightedTextColor=_highlightedTextColor,numberOfLines=_numberOfLines,lineBreakMode=_lineBreakMode,adjustsFontSizeToFitWidth=_adjustsFontSizeToFitWidth;
- (void)dealloc { [_text release]; [_font release]; [_textColor release]; [_highlightedTextColor release]; [super dealloc]; }
@end
@interface UIImageView : UIView {
    UIImage *_image;
}
@property(retain) UIImage *image;
@end
@implementation UIImageView
@synthesize image=_image;
- (void)dealloc { [_image release]; [super dealloc]; }
@end
@interface UIScreen : NSObject
+ (UIScreen *)mainScreen;
- (CGFloat)scale;
@end
@implementation UIScreen
+ (UIScreen *)mainScreen { return [[[self alloc] init] autorelease]; }
- (CGFloat)scale { return screenScale; }
@end
@interface UITableViewCell : UIView {
    UILabel *_textLabel,*_detailTextLabel;
    UIImageView *_imageView;
    UIView *_contentView;
    UIView *_accessoryView;
    NSInteger _accessoryType;
@public
    unsigned layouts,reuses;
}
@property(readonly) UILabel *textLabel,*detailTextLabel;
@property(readonly) UIImageView *imageView;
@property(readonly) UIView *contentView;
@property(nonatomic,retain) UIView *accessoryView;
@property NSInteger accessoryType;
- (void)layoutSubviews;
- (void)prepareForReuse;
@end
@implementation UITableViewCell
@synthesize textLabel=_textLabel,detailTextLabel=_detailTextLabel,imageView=_imageView,contentView=_contentView;
@synthesize accessoryView=_accessoryView,accessoryType=_accessoryType;
- (id)init {
    if ((self=[super init])) {
        _textLabel=[[UILabel alloc] init]; _detailTextLabel=[[UILabel alloc] init];
        _imageView=[[UIImageView alloc] init]; _contentView=[[UIView alloc] init];
        UIFont *title=[[[UIFont alloc] init] autorelease],*detail=[[[UIFont alloc] init] autorelease];
        title.lineHeight=21; title.glyphWidth=8.5; detail.lineHeight=17; detail.glyphWidth=7;
        _textLabel.font=title; _detailTextLabel.font=detail;
        [self addSubview:_contentView]; [_contentView addSubview:_textLabel];
        [_contentView addSubview:_detailTextLabel]; [_contentView addSubview:_imageView];
        self.frame=CGRectMake(0,0,300,100);
    }
    return self;
}
- (void)dealloc { [_textLabel release]; [_detailTextLabel release]; [_imageView release]; [_contentView release]; [_accessoryView release]; [super dealloc]; }
- (void)setAccessoryView:(UIView *)view {
    [view retain]; [_accessoryView removeFromSuperview]; [_accessoryView release]; _accessoryView=view;
    if (view) [self addSubview:view];
}
- (void)layoutSubviews {
    layouts++;
    CGFloat width=self.bounds.size.width, height=self.bounds.size.height;
    CGFloat left=_imageView.image ? 49 : 15, reserved=_accessoryView ? _accessoryView.bounds.size.width+8 : _accessoryType==UITableViewCellAccessoryCheckmark ? 32 : 0;
    _contentView.frame=CGRectMake(0,0,MAX(0,width-reserved),height);
    _textLabel.frame=CGRectMake(left,6,MAX(0,width-left-reserved-15),21);
    _detailTextLabel.frame=CGRectMake(left,27,MAX(0,width-left-reserved-15),17);
    _imageView.frame=CGRectMake(15,(height-24)/2,24,24);
    if (_accessoryView) _accessoryView.frame=CGRectMake(width-15-_accessoryView.bounds.size.width,(height-_accessoryView.bounds.size.height)/2,_accessoryView.bounds.size.width,_accessoryView.bounds.size.height);
}
- (void)prepareForReuse { reuses++; }
@end
@interface VCSettingsTableCell : UITableViewCell {
@public
    VCSettingsIconType _settingsIconType;
    UIColor *_settingsIconColor;
    CGFloat _settingsIconScale;
    UILabel *_settingsTitleLabel,*_settingsDetailLabel;
    VCSettingsRowLayout _settingsRowLayout;
    CGFloat _settingsLayoutWidth,_settingsTextLeft,_settingsRightInset;
    CGSize _settingsAccessorySize;
    BOOL _settingsLayoutValid;
}
- (void)applySettingsIcon:(VCSettingsIconType)icon;
- (void)applyAdaptiveTitle:(NSString *)title detail:(NSString *)detail;
- (CGFloat)settingsTextLeft;
- (CGFloat)settingsRightInset;
@end
@implementation VCSettingsTableCell
#include "settings_icon_cell.inc"
@end

static BOOL equalRect(CGRect a,CGRect b) {
    return a.origin.x==b.origin.x && a.origin.y==b.origin.y && a.size.width==b.size.width && a.size.height==b.size.height;
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; path=[[NSMutableString alloc] init];
    NSMutableSet *unique=[NSMutableSet set];
    unsigned rowCounts[]={4,4,3,2,1,1,4},ordinal=0;
    for (unsigned section=0;section<7;section++) {
        for (unsigned row=0;row<rowCounts[section];row++) {
            VCSettingsIconType icon=VCSettingsIconForRow(section,row);
            CHECK("settings-icons/ordered-main-menu-mapping",icon==(VCSettingsIconType)ordinal++);
            CHECK("settings-icons/rendered",VCSettingsIconImage(icon)!=nil && points>0 && strokes>0);
            CHECK("settings-icons/24pt-two-unit-rounded-strokes",contextSize.width==24 && contextSize.height==24 && lineWidth==2 && lineCap==kCGLineCapRound && lineJoin==kCGLineJoinRound);
            CHECK("settings-icons/current-accent-used",[(id)strokeColor isEqual:VCAccentColor()]);
            CHECK("settings-icons/distinct-path",![unique containsObject:path]); [unique addObject:[[path copy] autorelease]];
            if (icon==VCSettingsIconPreserveNames) CHECK("settings-icons/tag-without-pencil",strokes==2 && ellipses==1);
            if (icon==VCSettingsIconRouting) CHECK("settings-icons/three-route-nodes",strokes==4 && ellipses==3);
            if (icon==VCSettingsIconXrayVersion) CHECK("settings-icons/version-badge",strokes==2 && [path rangeOfString:@"M14.000000,11.000000L16.000000,9.000000L16.000000,15.000000"].location!=NSNotFound);
            if (icon==VCSettingsIconXmux) CHECK("settings-icons/preserve-existing-xmux",strokes==1 && [path rangeOfString:@"C10.000000,5.000000,10.000000,12.000000,14.000000,12.000000"].location!=NSNotFound);
            if (icon==VCSettingsIconGitHubLegacy) CHECK("settings-icons/git-app-without-clock",strokes==5 && ellipses==3);
        }
        CHECK("settings-icons/invalid-row",VCSettingsIconForRow(section,rowCounts[section])==VCSettingsIconNone);
    }
    CHECK("settings-icons/all-nineteen",ordinal==19 && unique.count==19 && VCSettingsIconCount==19);
    CHECK("settings-icons/invalid-section",VCSettingsIconForRow(-1,0)==VCSettingsIconNone && VCSettingsIconForRow(7,0)==VCSettingsIconNone && VCSettingsIconForRow(0,-1)==VCSettingsIconNone);
    unsigned before=renders;
    CHECK("settings-icons/invalid-type-no-context",!VCSettingsIconImage(VCSettingsIconNone) && !VCSettingsIconImage(VCSettingsIconCount) && renders==before);
    failContext=YES; CHECK("settings-icons/context-failure-safe",!VCSettingsIconImage(VCSettingsIconPing)); failContext=NO;
    VCSettingsTableCell *cell=[[VCSettingsTableCell alloc] init];
    [cell applySettingsIcon:VCSettingsIconPing]; before=renders;
    for (unsigned repeat=0;repeat<1000;repeat++) [cell applySettingsIcon:VCSettingsIconPing];
    CHECK("settings-icons/unchanged-cell-reuses-image",renders==before);
    CHECK("settings-icons/decorative-not-accessible",!cell.imageView.isAccessibilityElement);
    for (unsigned theme=0;theme<2;theme++) {
        dark=theme;
        for (accent=0;accent<6;accent++) {
            before=renders; [cell applySettingsIcon:VCSettingsIconPing];
            CHECK("settings-icons/theme-accent-invalidation",renders==before+((theme==0 && accent==0) ? 0 : 1));
            CHECK("settings-icons/theme-accent-color",[(id)strokeColor isEqual:VCAccentColor()]);
            before=renders; [cell applySettingsIcon:VCSettingsIconPing];
            CHECK("settings-icons/repeated-theme-does-not-render",renders==before);
        }
    }
    before=renders; screenScale=3; [cell applySettingsIcon:VCSettingsIconPing];
    CHECK("settings-icons/scale-invalidation",renders==before+1);
    before=renders; [cell applySettingsIcon:VCSettingsIconRouting]; CHECK("settings-icons/row-rebind-invalidation",renders==before+1);
    cell.textLabel.text=@"Auto-update subscriptions";
    cell.detailTextLabel.text=@"Refresh subscriptions on app open";
    [cell applyAdaptiveTitle:cell.textLabel.text detail:cell.detailTextLabel.text];
    UILabel *title=cell->_settingsTitleLabel,*detail=cell->_settingsDetailLabel;
    CHECK("settings-layout/labels-outside-clipped-content",title.superview==cell && detail.superview==cell && cell.textLabel.superview==cell.contentView);
    CHECK("settings-layout/native-fonts-preserved",title.font==cell.textLabel.font && detail.font==cell.detailTextLabel.font && !title.adjustsFontSizeToFitWidth && !detail.adjustsFontSizeToFitWidth);
    CHECK("settings-layout/multiline-and-touch-through",title.numberOfLines==0 && detail.numberOfLines==0 && !title.userInteractionEnabled && !detail.userInteractionEnabled && !title.isAccessibilityElement && !detail.isAccessibilityElement);
    for (unsigned i=0;i<5;i++) {
        CGFloat width=(CGFloat[]){300,440,0,700,300}[i];
        CGSize size=(CGSize[]){{79,27},{20,20},{79,27},{51,31},{79,27}}[i];
        UIView *control=[[[UIView alloc] initWithFrame:CGRectMake(0,0,size.width,size.height)] autorelease];
        cell.accessoryView=control; cell.frame=CGRectMake(0,0,width,200);
        [cell layoutSubviews];
        cell.frame=CGRectMake(0,0,width,cell->_settingsRowLayout.height); [cell layoutSubviews];
        CHECK("settings-layout/control-not-scaled",CGSizeEqualToSize(control.bounds.size,size));
        CHECK("settings-layout/body-fits-row",detail.frame.origin.y+detail.frame.size.height<=cell.bounds.size.height+0.01);
        if (width>0) {
            CHECK("settings-layout/title-and-body-use-measured-frames",equalRect(title.frame,cell->_settingsRowLayout.title) && equalRect(detail.frame,cell->_settingsRowLayout.detail));
            CHECK("settings-layout/title-before-switch",title.frame.origin.x+title.frame.size.width+7.99<=control.frame.origin.x);
            if (cell->_settingsRowLayout.expanded) CHECK("settings-layout/body-under-switch",detail.frame.origin.y>=control.frame.origin.y+control.frame.size.height+3.99 && detail.frame.origin.x+detail.frame.size.width>control.frame.origin.x);
        }
    }
    NSUInteger measured=measurements;
    for (unsigned i=0;i<1000;i++) [cell layoutSubviews];
    CHECK("settings-layout/unchanged-cell-no-measurements",measurements==measured);
    [cell applyAdaptiveTitle:cell.textLabel.text detail:cell.detailTextLabel.text]; [cell layoutSubviews];
    CHECK("settings-layout/same-text-reuses-layout",measurements==measured);
    CHECK("settings-layout/theme-colors-preserved",[title.textColor isEqual:VCPrimaryTextColor()] && [detail.textColor isEqual:VCSecondaryTextColor()]);
    [cell applyAdaptiveTitle:@"Stealth mode" detail:@"Hide links in configs and subscriptions"]; [cell layoutSubviews];
    CHECK("settings-layout/new-text-remeasured",measurements>measured);
    before=renders; [cell prepareForReuse];
    CHECK("settings-icons/reuse-clears-labels",title.text.length==0 && detail.text.length==0 && title.hidden && detail.hidden && cell->reuses==1 && !cell->_settingsLayoutValid);
    [cell applySettingsIcon:VCSettingsIconRouting]; CHECK("settings-icons/reuse-keeps-valid-image",renders==before);
    cell.imageView.image=nil; before=renders; [cell applySettingsIcon:VCSettingsIconRouting];
    CHECK("settings-icons/missing-image-retried",renders==before+1 && cell.imageView.image);
    failRender=renders+1; [cell applySettingsIcon:VCSettingsIconCredits];
    CHECK("settings-icons/render-failure-no-stale-icon",!cell.imageView.image);
    failRender=0; [cell applySettingsIcon:VCSettingsIconCredits]; CHECK("settings-icons/render-failure-retries",cell.imageView.image!=nil);
    before=renders; [cell applySettingsIcon:VCSettingsIconNone]; CHECK("settings-icons/invalid-rebind-clears",!cell.imageView.image && renders==before);
    [cell release]; [path release]; [pool drain]; FINISH("settings icons"); return 0;
}
