#import <Foundation/Foundation.h>
#include "../common/main_geometry.h"
#include "check.h"
#ifndef __APPLE__
static BOOL CGRectEqualToRect(CGRect a,CGRect b) { return a.origin.x==b.origin.x && a.origin.y==b.origin.y && a.size.width==b.size.width && a.size.height==b.size.height; }
#endif
typedef NSString UIFont;
typedef NSString UIColor;
@interface VCMainListCell : NSObject {
@public
    NSString *_detailSourceURI,*_detailPrefix,*_detailTail;
    BOOL _detailHidden,_detailStealth,_detailSupported,_detailLayoutValid;
    CGRect _detailLayoutFrame;
    UIFont *_detailLayoutFont;
    NSString *_detailLayoutPrefix,*_detailLayoutTail;
}
@property (readonly) NSString *detailPrefix;
@property (readonly) NSString *detailTail;
@property (readonly) BOOL detailSupported;
- (BOOL)hasDetailForURI:(NSString *)uri hidden:(BOOL)hidden stealth:(BOOL)stealth;
- (void)rememberDetailURI:(NSString *)uri hidden:(BOOL)hidden stealth:(BOOL)stealth prefix:(NSString *)prefix tail:(NSString *)tail supported:(BOOL)supported;
- (BOOL)hasDetailLayoutForFrame:(CGRect)frame font:(UIFont *)font prefix:(NSString *)prefix tail:(NSString *)tail;
- (void)rememberDetailLayoutForFrame:(CGRect)frame font:(UIFont *)font prefix:(NSString *)prefix tail:(NSString *)tail;
- (void)invalidateDetailLayout;
- (void)resetDetailState;
@end
@implementation VCMainListCell
@synthesize detailPrefix=_detailPrefix,detailTail=_detailTail,detailSupported=_detailSupported;
- (void)dealloc { if ([self respondsToSelector:@selector(resetDetailState)]) [self resetDetailState]; [super dealloc]; }
#include "main_detail_cache.inc"
@end
typedef VCMainListCell UITableViewCell;
static NSString *kHiddenLinkText=@"Hidden";
static UIColor *VCSecondaryTextColor(void) { return @"secondary"; }
static UIColor *VCErrorColor(void) { return @"error"; }
@interface MainVC : NSObject {
@public
    BOOL _stealthModeEnabled;
    NSUInteger preparations,applications;
    NSString *lastTail;
}
- (void)applyConfigDetailForURI:(NSString *)uri hidden:(BOOL)hidden toCell:(UITableViewCell *)cell;
- (NSString *)configPrefixTextFromURI:(NSString *)uri;
- (NSString *)configEndpointTextFromURI:(NSString *)uri;
- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri;
- (void)applyDetailPrefix:(NSString *)prefix prefixColor:(UIColor *)color tail:(NSString *)tail toCell:(UITableViewCell *)cell;
@end
@implementation MainVC
- (NSString *)configPrefixTextFromURI:(NSString *)uri { (void)uri; preparations++; return @"[tcp]"; }
- (NSString *)configEndpointTextFromURI:(NSString *)uri { (void)uri; return _stealthModeEnabled ? @"Hidden" : @"endpoint"; }
- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri { (void)uri; return YES; }
- (void)applyDetailPrefix:(NSString *)prefix prefixColor:(UIColor *)color tail:(NSString *)tail toCell:(UITableViewCell *)cell {
    (void)cell; CHECK("detail/controller-prefix-and-color",[prefix isEqual:@"[tcp]"] && [color isEqual:@"secondary"]);
    applications++; [lastTail release]; lastTail=[tail copy];
}
- (void)dealloc { [lastTail release]; [super dealloc]; }
#include "main_detail_apply.inc"
@end
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    VCMainListCell *cell=[[VCMainListCell alloc] init];
    CHECK("detail/cache-implemented",[cell respondsToSelector:@selector(hasDetailForURI:hidden:stealth:)]);
    CHECK("detail/initial-unprepared",![cell hasDetailForURI:@"synthetic" hidden:NO stealth:NO]);
    [cell rememberDetailURI:@"synthetic" hidden:NO stealth:NO prefix:@"[tcp]" tail:@"endpoint" supported:YES];
    CHECK("detail/same-source-reuses",[cell hasDetailForURI:@"synthetic" hidden:NO stealth:NO]);
    CHECK("detail/source-change-invalidates",![cell hasDetailForURI:@"replacement" hidden:NO stealth:NO]);
    CHECK("detail/stealth-change-invalidates",![cell hasDetailForURI:@"synthetic" hidden:NO stealth:YES]);
    CHECK("detail/protected-change-invalidates",![cell hasDetailForURI:@"synthetic" hidden:YES stealth:NO]);
    CHECK("detail/prepared-values",[cell->_detailPrefix isEqual:@"[tcp]"] && [cell->_detailTail isEqual:@"endpoint"] && cell->_detailSupported);
    CGRect frame=CGRectMake(12,22,200,14);
    [cell rememberDetailLayoutForFrame:frame font:@"font11" prefix:@"[tcp]" tail:@"endpoint"];
    for (NSUInteger i=0;i<1000;i++) CHECK("detail/same-layout-reuses",[cell hasDetailLayoutForFrame:frame font:@"font11" prefix:@"[tcp]" tail:@"endpoint"]);
    CHECK("detail/font-change-invalidates",![cell hasDetailLayoutForFrame:frame font:@"font12" prefix:@"[tcp]" tail:@"endpoint"]);
    CHECK("detail/width-change-invalidates",![cell hasDetailLayoutForFrame:CGRectMake(12,22,120,14) font:@"font11" prefix:@"[tcp]" tail:@"endpoint"]);
    CHECK("detail/content-change-invalidates",![cell hasDetailLayoutForFrame:frame font:@"font11" prefix:@"[ws]" tail:@"endpoint"]);
    [cell rememberDetailURI:@"synthetic" hidden:YES stealth:NO prefix:@"[tcp]" tail:@"Hidden" supported:YES];
    CHECK("detail/protected-text-no-endpoint",[cell->_detailTail isEqual:@"Hidden"] && !cell->_detailLayoutValid);
    [cell resetDetailState];
    CHECK("detail/reuse-releases-data",!cell->_detailSourceURI && !cell->_detailPrefix && !cell->_detailTail && !cell->_detailLayoutFont && !cell->_detailLayoutPrefix && !cell->_detailLayoutTail && !cell->_detailLayoutValid);
    CHECK("detail/reuse-reprepares",![cell hasDetailForURI:@"synthetic" hidden:YES stealth:NO]);
    MainVC *owner=[[MainVC alloc] init];
    for (NSUInteger i=0;i<1000;i++) [owner applyConfigDetailForURI:@"synthetic" hidden:NO toCell:cell];
    CHECK("detail/controller-prepares-once",owner->preparations==1 && owner->applications==1000);
    owner->_stealthModeEnabled=YES;
    [owner applyConfigDetailForURI:@"synthetic" hidden:NO toCell:cell];
    CHECK("detail/controller-stealth-reprepares",owner->preparations==2 && [owner->lastTail isEqual:@"Hidden"]);
    [owner applyConfigDetailForURI:@"synthetic" hidden:YES toCell:cell];
    CHECK("detail/controller-protected-reprepares",owner->preparations==3 && [owner->lastTail isEqual:@"Hidden"]);
    [cell resetDetailState];
    [owner applyConfigDetailForURI:@"synthetic" hidden:YES toCell:cell];
    CHECK("detail/controller-reuse-reprepares",owner->preparations==4);
    [owner release];
    [cell release]; [pool drain]; FINISH("main detail state"); return 0;
}
