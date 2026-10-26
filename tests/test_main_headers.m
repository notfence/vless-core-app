#import <Foundation/Foundation.h>
#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
#import "../common/app_constants.h"
#include "../common/main_geometry.h"
#include "check.h"
@interface NSIndexPath (TableRows)
+ (id)indexPathForRow:(NSInteger)row inSection:(NSInteger)section;
@property (readonly) NSInteger row;
@property (readonly) NSInteger section;
@end
@implementation NSIndexPath (TableRows)
+ (id)indexPathForRow:(NSInteger)row inSection:(NSInteger)section { NSUInteger indexes[]={(NSUInteger)section,(NSUInteger)row}; return [self indexPathWithIndexes:indexes length:2]; }
- (NSInteger)row { return [self indexAtPosition:1]; }
- (NSInteger)section { return [self indexAtPosition:0]; }
@end
@interface VCHeaderLabel : NSObject { NSString *_text; }
@property(copy) NSString *text;
@end
@implementation VCHeaderLabel
@synthesize text=_text;
- (void)dealloc { [_text release]; [super dealloc]; }
@end
@interface UITableViewCell : NSObject { id _accessoryView; }
@property(retain) id accessoryView;
@end
@implementation UITableViewCell
@synthesize accessoryView=_accessoryView;
- (void)dealloc { [_accessoryView release]; [super dealloc]; }
@end
static NSUInteger measurements;
static CGFloat VCSubscriptionDescriptionHeight(NSString *text,CGFloat width) { measurements++; return [text length]*12/MAX(1,width); }
@interface VCSubscriptionHeaderCell : UITableViewCell {
@public
    VCHeaderLabel *_providerDescriptionLabel;
    BOOL _showsDescription,_descriptionMeasureValid;
    CGFloat _descriptionMeasuredWidth,_descriptionMeasuredHeight;
    NSArray *_headerPresentationInputs;
    NSDictionary *_headerPresentation,*output;
    BOOL lastLoading;
}
- (void)updateDescriptionText:(NSString *)text;
- (CGFloat)descriptionHeightForWidth:(CGFloat)width;
- (NSDictionary *)headerPresentationForInputs:(NSArray *)inputs;
- (void)rememberHeaderPresentation:(NSDictionary *)presentation inputs:(NSArray *)inputs;
- (void)configureDescription:(NSString *)description configCount:(NSString *)count traffic:(NSString *)traffic expiry:(NSString *)expiry lastUpdated:(NSString *)updated showDescription:(BOOL)show pingLoading:(BOOL)loading canPing:(BOOL)canPing showActions:(BOOL)actions hasWebPage:(BOOL)web hasSupport:(BOOL)support index:(NSInteger)index target:(id)target;
@end
@implementation VCSubscriptionHeaderCell
- (id)init { if ((self=[super init])) _providerDescriptionLabel=[[VCHeaderLabel alloc] init]; return self; }
- (void)dealloc { [_providerDescriptionLabel release]; [_headerPresentationInputs release]; [_headerPresentation release]; [output release]; [super dealloc]; }
- (void)configureDescription:(NSString *)description configCount:(NSString *)count traffic:(NSString *)traffic expiry:(NSString *)expiry lastUpdated:(NSString *)updated showDescription:(BOOL)show pingLoading:(BOOL)loading canPing:(BOOL)canPing showActions:(BOOL)actions hasWebPage:(BOOL)web hasSupport:(BOOL)support index:(NSInteger)index target:(id)target {
    (void)show; (void)canPing; (void)actions; (void)web; (void)support; (void)index; (void)target;
    [output release]; output=[@{@"description":description,@"count":count,@"traffic":traffic,@"expiry":expiry,@"updated":updated} retain]; lastLoading=loading;
}
#include "main_header_description.inc"
@end
@interface VCTestTable : NSObject {
@public
    NSMutableDictionary *cells;
    NSUInteger lookups;
}
- (NSArray *)indexPathsForVisibleRows;
- (UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)path;
@end
@implementation VCTestTable
- (id)init { if ((self=[super init])) cells=[[NSMutableDictionary alloc] init]; return self; }
- (NSArray *)indexPathsForVisibleRows { return [cells allKeys]; }
- (UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)path { lookups++; return [cells objectForKey:path]; }
- (void)dealloc { [cells release]; [super dealloc]; }
@end
@interface MainVC : NSObject {
@public
    VCTestTable *_tableView;
    NSArray *_subscriptions;
    BOOL _subscriptionsSectionExpanded;
    NSInteger _reorderingSection,_updatingSubscriptionIndex;
    NSUInteger rowLookups,configured;
}
- (void)refreshVisibleSubscriptionHeaderAccessories;
- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)index;
- (NSInteger)subscriptionHeaderExpandedIndex;
- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)index itemIndex:(NSInteger *)item isHeader:(BOOL *)header;
- (id)subscriptionHeaderAccessoryExpanded:(BOOL)expanded loading:(BOOL)loading;
- (void)configureSubscriptionHeaderCell:(UITableViewCell *)cell atIndex:(NSInteger)index;
@end
@implementation MainVC
- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)index { rowLookups++; return index*2; }
- (NSInteger)subscriptionHeaderExpandedIndex { return 1; }
- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)index itemIndex:(NSInteger *)item isHeader:(BOOL *)header { *index=row/2; *item=0; *header=row%2==0; return row>=0 && row/2<(NSInteger)[_subscriptions count]; }
- (id)subscriptionHeaderAccessoryExpanded:(BOOL)expanded loading:(BOOL)loading { return @[@(expanded),@(loading)]; }
- (void)configureSubscriptionHeaderCell:(UITableViewCell *)cell atIndex:(NSInteger)index { (void)cell; CHECK("headers/only-visible-header-data",index==1 || index==500); configured++; }
#include "main_header_visible.inc"
@end
@interface VCTestPresentationOwner : MainVC {
@public
    VCProfileLogic *logic;
    NSUInteger formats;
    BOOL pinging;
}
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index;
- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub;
- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub;
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index;
@end
#include "main_header_inputs.inc"
@implementation VCTestPresentationOwner
- (id)init { if ((self=[super init])) logic=[[VCProfileLogic alloc] init]; return self; }
- (void)dealloc { [logic release]; [super dealloc]; }
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index { return [[_subscriptions objectAtIndex:index] objectForKey:@"items"]; }
- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub { formats++; return [logic subscriptionTrafficTextFromDictionary:sub]; }
- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub { return [logic subscriptionExpiryTextFromDictionary:sub]; }
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index { (void)index; return pinging; }
#include "main_header_configure.inc"
@end
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MainVC *owner=[[[MainVC alloc] init] autorelease];
    NSMutableArray *subscriptions=[NSMutableArray array];
    for (NSUInteger i=0;i<20000;i++) [subscriptions addObject:@{}];
    owner->_subscriptions=subscriptions;
    owner->_tableView=[[[VCTestTable alloc] init] autorelease];
    owner->_subscriptionsSectionExpanded=YES; owner->_reorderingSection=-1;
    [owner->_tableView->cells setObject:[[[VCSubscriptionHeaderCell alloc] init] autorelease] forKey:[NSIndexPath indexPathForRow:2 inSection:1]];
    [owner->_tableView->cells setObject:[[[VCSubscriptionHeaderCell alloc] init] autorelease] forKey:[NSIndexPath indexPathForRow:1000 inSection:1]];
    [owner->_tableView->cells setObject:[[[UITableViewCell alloc] init] autorelease] forKey:[NSIndexPath indexPathForRow:3 inSection:1]];
    [owner refreshVisibleSubscriptionHeaderAccessories];
    CHECK("headers/visits-visible-not-all",owner->rowLookups==0 && owner->_tableView->lookups<=3 && owner->configured==2);
    owner->_reorderingSection=1; [owner refreshVisibleSubscriptionHeaderAccessories];
    CHECK("headers/reorder-does-not-refresh",owner->configured==2);
    VCSubscriptionHeaderCell *cell=[[[VCSubscriptionHeaderCell alloc] init] autorelease];
    CHECK("headers/description-cache-implemented",[cell respondsToSelector:@selector(descriptionHeightForWidth:)]);
    [cell updateDescriptionText:@"Synthetic description"];
    CHECK("headers/hidden-is-not-measured",[cell descriptionHeightForWidth:200]==0 && !measurements);
    cell->_showsDescription=YES;
    CGFloat height=[cell descriptionHeightForWidth:200];
    for (NSUInteger i=0;i<1000;i++) CHECK("headers/description-reuses-width",[cell descriptionHeightForWidth:200]==height && measurements==1);
    [cell descriptionHeightForWidth:180];
    CHECK("headers/description-width-invalidates",measurements==2);
    cell->_showsDescription=NO; [cell descriptionHeightForWidth:180];
    CHECK("headers/hidden-keeps-no-work",measurements==2);
    [cell updateDescriptionText:@"Replacement description"];
    cell->_showsDescription=YES; [cell descriptionHeightForWidth:180];
    CHECK("headers/description-text-invalidates",measurements==3);
    VCTestPresentationOwner *formatOwner=[[[VCTestPresentationOwner alloc] init] autorelease];
    NSDictionary *subscription=@{@"items":@[@"synthetic"],kSubscriptionUserInfoKey:@{kSubscriptionUploadKey:@100,kSubscriptionDownloadKey:@200,kSubscriptionTotalKey:@1000,kSubscriptionExpireKey:@1700000000},kSubscriptionMetadataKey:@{kSubscriptionDescriptionKey:@"Synthetic",kSubscriptionLastUpdatedKey:@1700000000}};
    formatOwner->_subscriptions=@[subscription];
    formatOwner->_reorderingSection=-1;
    for (NSUInteger i=0;i<1000;i++) [formatOwner configureSubscriptionHeaderCell:cell atIndex:0];
    CHECK("headers/presentation-formats-once",formatOwner->formats==1);
    CHECK("headers/presentation-preserves-format",[[cell->output objectForKey:@"traffic"] isEqual:[formatOwner->logic subscriptionTrafficTextFromDictionary:subscription]] && [[cell->output objectForKey:@"updated"] isEqual:VCSubscriptionLastUpdatedText(subscription)]);
    formatOwner->pinging=YES; [formatOwner configureSubscriptionHeaderCell:cell atIndex:0];
    CHECK("headers/ping-does-not-reformat",formatOwner->formats==1 && cell->lastLoading);
    NSTimeZone *savedZone=[[NSTimeZone defaultTimeZone] retain];
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:[[savedZone name] isEqual:@"GMT"] ? @"Asia/Tokyo" : @"GMT"]];
    [formatOwner configureSubscriptionHeaderCell:cell atIndex:0];
    CHECK("headers/timezone-reformats",formatOwner->formats==2 && [[cell->output objectForKey:@"updated"] isEqual:VCSubscriptionLastUpdatedText(subscription)]);
    [NSTimeZone setDefaultTimeZone:savedZone]; [savedZone release];
    NSDictionary *replacement=@{@"items":@[@"a",@"b"],kSubscriptionMetadataKey:@{kSubscriptionDescriptionKey:@"Replacement"}};
    formatOwner->_subscriptions=@[replacement]; [formatOwner configureSubscriptionHeaderCell:cell atIndex:0];
    CHECK("headers/source-change-reformats",formatOwner->formats==3 && [[cell->output objectForKey:@"count"] isEqual:@"2"] && [[cell->output objectForKey:@"description"] isEqual:@"Replacement"]);
    [pool drain]; FINISH("visible headers and description"); return 0;
}
