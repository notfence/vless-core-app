#import "app_support.h"

@class SubscriptionInfoVC;

@protocol SubscriptionInfoVCDelegate <NSObject>
- (void)subscriptionInfoVCRequestedRefresh:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
- (void)subscriptionInfoVCRequestedDelete:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index;
- (void)subscriptionInfoVC:(SubscriptionInfoVC *)vc requestedRenameTo:(NSString *)name atIndex:(NSInteger)index;
@end

@interface SubscriptionInfoVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    NSDictionary *_subscription;
    NSArray *_sections;
    NSInteger _subscriptionIndex;
    BOOL _stealthMode;
    BOOL _refreshing;
    id<SubscriptionInfoVCDelegate> _delegate;
}
- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode
                  delegate:(id<SubscriptionInfoVCDelegate>)delegate;
- (NSInteger)subscriptionIndex;
- (void)reloadWithSubscription:(NSDictionary *)subscription;
- (void)cancelRefresh;
- (void)finishRefreshWithSubscription:(NSDictionary *)subscription errorText:(NSString *)errorText;
@end
