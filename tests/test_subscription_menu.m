#import <Foundation/Foundation.h>
#include "../common/main_geometry.h"
#include "check.h"
#include <math.h>

static CGSize CGSizeMake(CGFloat w,CGFloat h) { return (CGSize){w,h}; }
static const CGRect CGRectZero={0};
static CGFloat CGRectGetMaxX(CGRect r) { return r.origin.x+r.size.width; }
static CGFloat CGRectGetMaxY(CGRect r) { return r.origin.y+r.size.height; }
typedef NS_ENUM(NSInteger, VCSubscriptionMenuAction) { VCSubscriptionMenuEdit, VCSubscriptionMenuInformation, VCSubscriptionMenuUpdate, VCSubscriptionMenuDelete };
enum { UIAccessibilityScreenChangedNotification=1 };
static void UIAccessibilityPostNotification(NSInteger notification,id value) { (void)notification; (void)value; }
#include "subscription_menu_layout.inc"
enum { NSLineBreakByWordWrapping=0,UIViewAutoresizingFlexibleWidth=1,UIViewAutoresizingFlexibleHeight=2,
    UITableViewCellAccessoryNone=0,UITableViewCellAccessoryCheckmark=3,UITextAutocapitalizationTypeNone=0,
    UITextAutocorrectionTypeNo=0,UITextFieldViewModeWhileEditing=1,UIControlContentVerticalAlignmentCenter=0,UIReturnKeyDone=1 };
@protocol UIActionSheetDelegate @end
@interface UIFont : NSObject { CGFloat _pointSize; BOOL _bold; }
@property CGFloat pointSize;
@property BOOL bold;
+ (id)systemFontOfSize:(CGFloat)size;
+ (id)boldSystemFontOfSize:(CGFloat)size;
@end
@implementation UIFont
@synthesize pointSize=_pointSize,bold=_bold;
+ (id)systemFontOfSize:(CGFloat)size { UIFont *font=[[[self alloc] init] autorelease]; font.pointSize=size; return font; }
+ (id)boldSystemFontOfSize:(CGFloat)size { UIFont *font=[self systemFontOfSize:size]; font.bold=YES; return font; }
@end
@interface UIColor : NSObject
+ (id)clearColor;
@end
@implementation UIColor
+ (id)clearColor { return @"clear"; }
@end
static id VCPrimaryTextColor(void) { return @"primary"; }
static id VCSecondaryTextColor(void) { return @"secondary"; }
static NSString *const NSForegroundColorAttributeName=@"NSColor";
static NSString *const NSFontAttributeName=@"NSFont";
static BOOL placeholderAPIAvailable=YES;
@interface UIView : NSObject { CGRect _frame,_bounds; NSMutableArray *_subviews; id _backgroundColor; NSUInteger _autoresizingMask; }
@property(nonatomic) CGRect frame,bounds;
@property(retain) id backgroundColor;
@property NSUInteger autoresizingMask;
@property(readonly) NSArray *subviews;
- (id)initWithFrame:(CGRect)frame;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
@end
@implementation UIView
@synthesize frame=_frame,bounds=_bounds,backgroundColor=_backgroundColor,autoresizingMask=_autoresizingMask;
- (id)initWithFrame:(CGRect)frame { if ((self=[super init])) { _frame=frame; _bounds=CGRectMake(0,0,frame.size.width,frame.size.height); _subviews=[[NSMutableArray alloc] init]; } return self; }
- (void)setFrame:(CGRect)frame { _frame=frame; _bounds.size=frame.size; }
- (NSArray *)subviews { return _subviews; }
- (void)addSubview:(UIView *)view { [_subviews addObject:view]; }
- (void)removeFromSuperview {}
- (void)dealloc { [_subviews release]; [_backgroundColor release]; [super dealloc]; }
@end
static CGFloat nativeFooterInset=18;
static BOOL nativeFooterAvailable=YES;
static BOOL readableGuideAvailable=YES;
@interface UILabel : UIView { NSString *_text; UIFont *_font; id _textColor; NSInteger _numberOfLines,_lineBreakMode; }
@property(copy) NSString *text;
@property(retain) UIFont *font;
@property(retain) id textColor;
@property NSInteger numberOfLines,lineBreakMode;
@end
@interface UITableViewHeaderFooterView : UIView { UIView *_contentView,*_backgroundView; UILabel *_textLabel; }
@property(retain) UIView *backgroundView;
@property(readonly) UIView *contentView;
@property(readonly) UILabel *textLabel;
- (id)initWithReuseIdentifier:(NSString *)identifier;
@end
@implementation UITableViewHeaderFooterView
@synthesize backgroundView=_backgroundView;
- (id)initWithReuseIdentifier:(NSString *)identifier {
    (void)identifier;
    if ((self=[super initWithFrame:CGRectZero])) {
        _contentView=[[UIView alloc] initWithFrame:CGRectZero]; [self addSubview:_contentView];
        _textLabel=[[UILabel alloc] initWithFrame:CGRectZero]; [_contentView addSubview:_textLabel];
    }
    return self;
}
- (UIView *)contentView { return _contentView; }
- (UILabel *)textLabel { return _textLabel; }
- (void)setFrame:(CGRect)frame {
    [super setFrame:frame]; _contentView.frame=self.bounds;
    _textLabel.frame=CGRectMake(nativeFooterInset,4,MAX(0,frame.size.width-2*nativeFooterInset),MAX(0,frame.size.height-8));
}
- (void)dealloc { [_contentView release]; [_textLabel release]; [_backgroundView release]; [super dealloc]; }
@end
@interface UILayoutGuide : NSObject { CGRect _layoutFrame; }
@property CGRect layoutFrame;
@end
@implementation UILayoutGuide
@synthesize layoutFrame=_layoutFrame;
@end
@implementation UILabel
@synthesize text=_text,font=_font,textColor=_textColor,numberOfLines=_numberOfLines,lineBreakMode=_lineBreakMode;
- (void)dealloc { [_text release]; [_font release]; [_textColor release]; [super dealloc]; }
@end
@interface UITextField : UILabel {
    NSString *_placeholder;
    NSAttributedString *_attributedPlaceholder;
    NSInteger _autocapitalizationType,_autocorrectionType,_clearButtonMode,_contentVerticalAlignment,_returnKeyType;
    id _delegate; BOOL _enabled;
@public NSUInteger focusCalls,resignCalls;
}
@property(copy) NSString *placeholder;
@property(copy) NSAttributedString *attributedPlaceholder;
@property NSInteger autocapitalizationType,autocorrectionType,clearButtonMode,contentVerticalAlignment,returnKeyType;
@property(assign) id delegate;
@property BOOL enabled;
- (BOOL)resignFirstResponder;
- (BOOL)becomeFirstResponder;
@end
@implementation UITextField
@synthesize placeholder=_placeholder,attributedPlaceholder=_attributedPlaceholder,autocapitalizationType=_autocapitalizationType,autocorrectionType=_autocorrectionType,clearButtonMode=_clearButtonMode,contentVerticalAlignment=_contentVerticalAlignment,returnKeyType=_returnKeyType,delegate=_delegate,enabled=_enabled;
- (BOOL)respondsToSelector:(SEL)selector { if (sel_isEqual(selector,@selector(setAttributedPlaceholder:))) return placeholderAPIAvailable; return [super respondsToSelector:selector]; }
- (BOOL)resignFirstResponder { resignCalls++; return YES; }
- (BOOL)becomeFirstResponder { focusCalls++; return YES; }
- (void)dealloc { [_placeholder release]; [_attributedPlaceholder release]; [super dealloc]; }
@end
@interface NSIndexPath (SubscriptionUI)
+ (id)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
- (NSInteger)row;
@end
@implementation NSIndexPath (SubscriptionUI)
+ (id)indexPathForRow:(NSInteger)row inSection:(NSInteger)section { NSUInteger indexes[]={(NSUInteger)section,(NSUInteger)row}; return [self indexPathWithIndexes:indexes length:2]; }
- (NSInteger)row { return [self indexAtPosition:1]; }
@end
@interface UITableViewCell : NSObject { NSInteger _accessoryType; }
@property NSInteger accessoryType;
@end
@implementation UITableViewCell
@synthesize accessoryType=_accessoryType;
@end
@interface UITableView : UIView { NSArray *_cells; UILayoutGuide *_readableContentGuide; BOOL _cellLayoutMarginsFollowReadableWidth; }
@property(retain) NSArray *cells;
@property(retain) UILayoutGuide *readableContentGuide;
@property BOOL cellLayoutMarginsFollowReadableWidth;
- (void)deselectRowAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated;
- (id)cellForRowAtIndexPath:(NSIndexPath *)path;
@end
@implementation UITableView
@synthesize cells=_cells,readableContentGuide=_readableContentGuide,cellLayoutMarginsFollowReadableWidth=_cellLayoutMarginsFollowReadableWidth;
- (BOOL)respondsToSelector:(SEL)selector { if (sel_isEqual(selector,@selector(readableContentGuide))) return readableGuideAvailable; return [super respondsToSelector:selector]; }
- (void)deselectRowAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated { (void)path; (void)animated; }
- (id)cellForRowAtIndexPath:(NSIndexPath *)path { return [_cells objectAtIndex:path.row]; }
- (void)dealloc { [_cells release]; [_readableContentGuide release]; [super dealloc]; }
@end
@interface NSString (SubscriptionUI)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode;
@end
@implementation NSString (SubscriptionUI)
- (CGSize)sizeWithFont:(UIFont *)font constrainedToSize:(CGSize)size lineBreakMode:(NSInteger)mode { (void)mode; return CGSizeMake(size.width,ceil(self.length*font.pointSize/2/MAX(1,size.width))*(font.pointSize+3)); }
@end
static void VCAppearanceApplyHeaderView(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) ((UILabel *)view).textColor=VCSecondaryTextColor();
    for (UIView *child in view.subviews) VCAppearanceApplyHeaderView(child);
}
static Class SubscriptionUIClass(NSString *name) {
    if ([name isEqual:@"UITableViewHeaderFooterView"] && !nativeFooterAvailable) return Nil;
    return NSClassFromString(name);
}
#define NSClassFromString SubscriptionUIClass
#include "settings_footer.inc"
#undef NSClassFromString

@interface UIActionSheet : NSObject { NSMutableArray *_buttons; NSInteger _destructiveButtonIndex,_cancelButtonIndex; }
@property NSInteger destructiveButtonIndex,cancelButtonIndex;
@property(readonly) NSArray *buttons;
- (id)initWithTitle:(NSString *)title delegate:(id)delegate cancelButtonTitle:(NSString *)cancel destructiveButtonTitle:(NSString *)destructive otherButtonTitles:(NSString *)other,...;
- (NSInteger)addButtonWithTitle:(NSString *)title;
@end
@implementation UIActionSheet
@synthesize destructiveButtonIndex=_destructiveButtonIndex,cancelButtonIndex=_cancelButtonIndex;
- (id)initWithTitle:(NSString *)title delegate:(id)delegate cancelButtonTitle:(NSString *)cancel destructiveButtonTitle:(NSString *)destructive otherButtonTitles:(NSString *)other,... { (void)title; (void)delegate; (void)cancel; (void)destructive; (void)other; if ((self=[super init])) _buttons=[[NSMutableArray alloc] init]; return self; }
- (NSInteger)addButtonWithTitle:(NSString *)title { [_buttons addObject:title]; return [_buttons count]-1; }
- (NSArray *)buttons { return _buttons; }
- (void)dealloc { [_buttons release]; [super dealloc]; }
@end
@interface VCSubscriptionActionSheet : UIActionSheet { NSDictionary *_subscription; }
@end
@interface MenuDelegate : NSObject { @public NSUInteger calls; NSInteger lastAction; }
- (void)subscriptionMenu:(id)menu selectedAction:(VCSubscriptionMenuAction)action;
@end
@implementation MenuDelegate
- (void)subscriptionMenu:(id)menu selectedAction:(VCSubscriptionMenuAction)action { (void)menu; calls++; lastAction=action; }
@end
@interface VCSubscriptionMenu : UIView { @public BOOL _dismissed; MenuDelegate *_delegate; }
@end
@implementation VCSubscriptionMenu
#include "subscription_menu_dismiss.inc"
@end
@implementation VCSubscriptionActionSheet
#include "subscription_menu_sheet.inc"
- (void)dealloc { [_subscription release]; [super dealloc]; }
@end
@interface SubscriptionEditVC : NSObject {
@public NSInteger _agentMode; BOOL _saving; UITextField *_agentField;
}
@end
@implementation SubscriptionEditVC
#include "subscription_menu_editor.inc"
- (void)dealloc { [_agentField release]; [super dealloc]; }
@end
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    UITableView *table=[[[UITableView alloc] initWithFrame:CGRectMake(0,0,320,480)] autorelease];
    table.cells=@[[[[UITableViewCell alloc] init] autorelease],[[[UITableViewCell alloc] init] autorelease],[[[UITableViewCell alloc] init] autorelease]];
    SubscriptionEditVC *editor=[[[SubscriptionEditVC alloc] init] autorelease];
    editor->_agentField=[editor newFieldWithText:@"Custom/1.0" placeholder:@"Custom User-Agent"];
    CHECK("subscription-menu/input-font-matches-settings",editor->_agentField.font.bold && editor->_agentField.font.pointSize==17);
    NSAttributedString *placeholder=editor->_agentField.attributedPlaceholder;
    CHECK("subscription-menu/placeholder-explicit-color",placeholder && [[placeholder string] isEqual:@"Custom User-Agent"] && [[placeholder attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL] isEqual:VCSecondaryTextColor()]);
    CHECK("subscription-menu/placeholder-font-matches-input",[placeholder attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL]==editor->_agentField.font);
    placeholderAPIAvailable=NO;
    UITextField *legacy=[editor newFieldWithText:@"" placeholder:@"Custom User-Agent"];
    CHECK("subscription-menu/ios5-keeps-native-placeholder",[legacy.placeholder isEqual:@"Custom User-Agent"] && !legacy.attributedPlaceholder);
    [legacy release]; placeholderAPIAvailable=YES;
    for (NSInteger mode=0;mode<3;mode++) {
        editor->_agentMode=mode;
        CHECK("subscription-menu/custom-row-always-present",[editor tableView:table numberOfRowsInSection:2]==4);
        [editor tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:mode inSection:2]];
        CHECK("subscription-menu/selection-updates-without-reload-scroll-or-focus",editor->_agentMode==mode && !editor->_agentField->focusCalls && editor->_agentField.enabled==(mode==2));
        CHECK("subscription-menu/placeholder-preserved-when-disabled-or-enabled",[editor->_agentField.attributedPlaceholder isEqual:placeholder]);
        for (NSInteger row=0;row<3;row++) CHECK("subscription-menu/checkmark-current-choice",[[table.cells objectAtIndex:row] accessoryType]==(row==mode ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone));
    }
    editor->_saving=YES;
    [editor tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:2]];
    CHECK("subscription-menu/saving-prevents-agent-change",editor->_agentMode==2);
    CHECK("subscription-menu/retains-custom-text",[editor->_agentField.text isEqual:@"Custom/1.0"]);
    CHECK("subscription-menu/default-description",[[editor tableView:table titleForFooterInSection:2] isEqual:@"Default: vless-core-app own user-agent."]);
    for (NSUInteger width=240;width<=768;width+=48) {
        table.bounds=CGRectMake(0,0,width,480);
        for (NSInteger section=0;section<3;section++) {
            UIView *footer=[editor tableView:table viewForFooterInSection:section];
            CHECK("subscription-menu/only-real-footers",(footer!=nil)==(section!=0));
            if (!footer) continue;
            UILabel *label=[footer isKindOfClass:[UITableViewHeaderFooterView class]] ? [(UITableViewHeaderFooterView *)footer textLabel] : [footer.subviews objectAtIndex:0];
            CHECK("subscription-menu/footer-wraps-inside-table",label.frame.origin.x>=0 && label.frame.origin.x+label.frame.size.width<=width && label.frame.origin.y+label.frame.size.height<=footer.frame.size.height && label.numberOfLines==0);
            CHECK("subscription-menu/footer-uses-common-theme",[label.textColor isEqual:VCSecondaryTextColor()] && label.font.pointSize==14);
        }
    }
    table.cellLayoutMarginsFollowReadableWidth=YES;
    table.readableContentGuide=[[[UILayoutGuide alloc] init] autorelease];
    CGFloat editorWidths[]={320,768,1024,768,320};
    CGFloat textInsets[]={16,48,176,48,16};
    for (NSUInteger i=0;i<5;i++) {
        CGFloat width=editorWidths[i],inset=textInsets[i]; nativeFooterInset=inset;
        table.bounds=CGRectMake(0,0,width,480);
        table.readableContentGuide.layoutFrame=CGRectMake(inset,0,width-2*inset,480);
        CGRect input=VCSubscriptionInputFrame(CGRectMake(0,0,width,44),inset);
        CHECK("subscription-menu/input-follows-native-phone-pad-and-rotation-insets",input.origin.x==inset && input.size.width==width-2*inset && input.size.height==44);
        for (NSInteger section=1;section<3;section++) {
            UITableViewHeaderFooterView *footer=(id)[editor tableView:table viewForFooterInSection:section];
            CHECK("subscription-menu/footer-uses-native-layout",[footer isKindOfClass:[UITableViewHeaderFooterView class]]);
            CHECK("subscription-menu/footer-and-fields-align",footer.textLabel.frame.origin.x==input.origin.x && footer.textLabel.frame.size.width==input.size.width);
            CHECK("subscription-menu/footer-height-uses-readable-width",footer.frame.size.height>0 && footer.textLabel.frame.size.height>=17);
        }
    }
    readableGuideAvailable=NO;
    for (NSInteger section=1;section<3;section++) {
        UIView *footer=[editor tableView:table viewForFooterInSection:section];
        CHECK("subscription-menu/ios6-to8-keeps-left-aligned-footer",![footer isKindOfClass:[UITableViewHeaderFooterView class]] && [(UIView *)[footer.subviews objectAtIndex:0] frame].origin.x==18);
    }
    nativeFooterAvailable=NO;
    UIView *legacyFooter=[editor tableView:table viewForFooterInSection:2];
    CHECK("subscription-menu/ios5-footer-fallback",legacyFooter && ![legacyFooter isKindOfClass:[UITableViewHeaderFooterView class]] && [[(UILabel *)[legacyFooter.subviews objectAtIndex:0] text] isEqual:@"Default: vless-core-app own user-agent."]);
    nativeFooterAvailable=YES; readableGuideAvailable=YES;
    NSString *footerTexts[] = {
        @"When disabled, all supported traffic uses the selected proxy.",
        @"Target for Proxy GET and tunnel checks. Not used by TCP or ICMP. Only HTTP is supported. Redirects are not followed. Empty restores the default URL.",
        @"When disabled, vless-core-cli reports Xray version 26.6.27. Changes apply on the next connection.",
        @"Up to 250 recent events are kept only on this device. URLs, IP addresses, UUIDs, names and secrets are omitted. Nothing is sent automatically."
    };
    for (NSUInteger i=0;i<5;i++) {
        CGFloat width=editorWidths[i],inset=textInsets[i]; nativeFooterInset=inset;
        table.bounds=CGRectMake(0,0,width,480);
        table.readableContentGuide.layoutFrame=CGRectMake(inset,0,width-2*inset,480);
        for (NSUInteger screen=0;screen<4;screen++) {
            CGFloat fontSize=screen==3 ? 13 : 14,minimum=screen==3 ? 82 : 0.01f;
            NSString *text=footerTexts[screen];
            CGFloat height=VCAppearanceTableFooterHeight(table,text,fontSize,minimum);
            UITableViewHeaderFooterView *footer=(id)VCAppearanceTableFooterView(table,text,fontSize,height);
            CHECK("settings-footer/native-column-on-phone-ipad-and-rotation",[footer isKindOfClass:[UITableViewHeaderFooterView class]] && footer.textLabel.frame.origin.x==inset && footer.textLabel.frame.size.width==width-2*inset);
            CHECK("settings-footer/preserves-description-and-font",[footer.textLabel.text isEqual:text] && footer.textLabel.font.pointSize==fontSize);
            CHECK("settings-footer/wrapped-text-fits-height",height>=minimum && footer.textLabel.numberOfLines==0 && footer.textLabel.lineBreakMode==NSLineBreakByWordWrapping && height>=ceilf([text sizeWithFont:footer.textLabel.font constrainedToSize:CGSizeMake(width-2*inset,1000) lineBreakMode:NSLineBreakByWordWrapping].height)+8);
            footer.textLabel.font=[UIFont systemFontOfSize:17]; footer.textLabel.numberOfLines=1;
            VCAppearanceApplyFooterView(footer,fontSize);
            CHECK("settings-footer/reapplies-font-wrap-and-theme-before-display",footer.textLabel.font.pointSize==fontSize && footer.textLabel.numberOfLines==0 && [footer.textLabel.textColor isEqual:VCSecondaryTextColor()]);
        }
    }
    CHECK("settings-footer/empty-sections-keep-spacing",VCAppearanceTableFooterHeight(table,nil,14,0.01f)==0.01f && VCAppearanceTableFooterHeight(table,@"",13,18)==18 && !VCAppearanceTableFooterView(table,nil,14,18));
    readableGuideAvailable=NO;
    for (NSUInteger screen=0;screen<4;screen++) {
        CGFloat fontSize=screen==3 ? 13 : 14;
        CGFloat height=VCAppearanceTableFooterHeight(table,footerTexts[screen],fontSize,0.01f);
        UIView *footer=VCAppearanceTableFooterView(table,footerTexts[screen],fontSize,height);
        UILabel *label=[footer.subviews objectAtIndex:0];
        CHECK("settings-footer/ios5-to8-stays-left-aligned",![footer isKindOfClass:[UITableViewHeaderFooterView class]] && label.frame.origin.x==18 && label.font.pointSize==fontSize && [label.text isEqual:footerTexts[screen]]);
    }
    readableGuideAvailable=YES;
    VCSubscriptionActionSheet *sheet=[[[VCSubscriptionActionSheet alloc] initWithSubscription:@{} delegate:nil] autorelease];
    CHECK("subscription-menu/delete-confirmation",[sheet.buttons isEqual:@[@"Delete",@"Cancel"]] && sheet.destructiveButtonIndex==0 && sheet.cancelButtonIndex==1);
    CGRect bounds=CGRectMake(0,0,320,460);
    CGRect below=VCSubscriptionMenuFrame(bounds,CGRectMake(260,20,30,30));
    CGRect above=VCSubscriptionMenuFrame(bounds,CGRectMake(260,400,30,30));
    CHECK("subscription-menu/opens-below-top-anchor",below.origin.y==58 && below.size.width==224 && below.size.height==192);
    CHECK("subscription-menu/opens-above-bottom-anchor",CGRectGetMaxY(above)==392);
    CGFloat widths[]={240,320,375,768,1024},heights[]={320,460,568,768,1024};
    for (NSUInteger w=0;w<5;w++) for (NSUInteger h=0;h<5;h++) for (NSInteger x=-100;x<=1200;x+=100) for (NSInteger y=-100;y<=1200;y+=100) {
        CGRect area=CGRectMake(0,0,widths[w],heights[h]);
        CGRect frame=VCSubscriptionMenuFrame(area,CGRectMake(x,y,30,30));
        CHECK("subscription-menu/within-phone-and-pad",frame.origin.x>=10 && frame.origin.y>=10 && CGRectGetMaxX(frame)<=area.size.width-10 && CGRectGetMaxY(frame)<=area.size.height-10);
        CHECK("subscription-menu/four-usable-rows",frame.size.height/4>=44 && frame.size.width>=220);
    }
    for (NSUInteger scenario=0;scenario<4;scenario++) {
        CGRect bad=scenario==0 ? CGRectMake(0,0,NAN,460) : scenario==1 ? CGRectMake(0,0,320,INFINITY) : scenario==2 ? CGRectMake(0,0,0,460) : CGRectMake(0,0,320,0);
        CGRect frame=VCSubscriptionMenuFrame(bad,CGRectZero);
        CHECK("subscription-menu/invalid-geometry-safe",frame.size.width==0 && frame.size.height==0);
    }
    MenuDelegate *delegate=[[[MenuDelegate alloc] init] autorelease];
    for (NSInteger action=-1;action<=4;action++) {
        VCSubscriptionMenu *menu=[[[VCSubscriptionMenu alloc] initWithFrame:CGRectZero] autorelease]; menu->_delegate=delegate;
        NSUInteger before=delegate->calls;
        [menu finishDismissalWithAction:action]; [menu finishDismissalWithAction:action];
        BOOL valid=action>=0 && action<4;
        CHECK("subscription-menu/one-callback-for-valid-action-only",delegate->calls==before+(valid ? 1 : 0));
        if (valid) CHECK("subscription-menu/action-preserved",delegate->lastAction==action);
    }
    VCSubscriptionMenu *menu=[[[VCSubscriptionMenu alloc] initWithFrame:CGRectZero] autorelease]; menu->_delegate=delegate;
    NSUInteger before=delegate->calls;
    [menu dismissForEnvironmentChange:nil]; [menu finishDismissalWithAction:VCSubscriptionMenuDelete];
    CHECK("subscription-menu/background-discards-late-action",menu->_dismissed && delegate->calls==before);
    for (NSInteger action=-1;action<4;action++) {
        VCSubscriptionMenu *rotating=[[[VCSubscriptionMenu alloc] initWithFrame:CGRectZero] autorelease]; rotating->_delegate=delegate;
        before=delegate->calls;
        [rotating dismissForEnvironmentChange:[NSNotification notificationWithName:@"UIApplicationWillChangeStatusBarOrientationNotification" object:nil]];
        CHECK("subscription-menu/rotation-immediately-dismisses",rotating->_dismissed && !rotating->_delegate);
        [rotating finishDismissalWithAction:action];
        [rotating dismissForEnvironmentChange:nil];
        CHECK("subscription-menu/rotation-discards-pending-action",delegate->calls==before);
    }
    FINISH("subscription menu UI logic"); [pool drain]; return 0;
}
