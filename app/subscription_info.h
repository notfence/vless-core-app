#import "app_support.h"

@class SubscriptionEditVC, VCSubscriptionMenu;

typedef NS_ENUM(NSInteger, VCSubscriptionMenuAction) {
    VCSubscriptionMenuEdit,
    VCSubscriptionMenuInformation,
    VCSubscriptionMenuUpdate,
    VCSubscriptionMenuDelete,
};

@protocol VCSubscriptionMenuDelegate <NSObject>
- (void)subscriptionMenu:(VCSubscriptionMenu *)menu selectedAction:(VCSubscriptionMenuAction)action;
@end

@interface VCSubscriptionMenu : UIView {
    NSDictionary *_subscription;
    CGRect _anchor;
    UIView *_panel;
    BOOL _closing, _dismissed;
    id<VCSubscriptionMenuDelegate> _delegate;
}
@property (nonatomic, readonly) NSDictionary *subscription;
@property (nonatomic, readonly) CGRect anchor;
- (id)initWithSubscription:(NSDictionary *)subscription anchor:(CGRect)anchor delegate:(id<VCSubscriptionMenuDelegate>)delegate;
- (void)showInView:(UIView *)view;
@end

@interface VCSubscriptionActionSheet : UIActionSheet {
    NSDictionary *_subscription;
}
@property (nonatomic, readonly) NSDictionary *subscription;
- (id)initWithSubscription:(NSDictionary *)subscription delegate:(id<UIActionSheetDelegate>)delegate;
@end

@protocol SubscriptionEditVCDelegate <NSObject>
- (void)subscriptionEditVC:(SubscriptionEditVC *)vc requestedSave:(NSDictionary *)subscription;
- (void)subscriptionEditVC:(SubscriptionEditVC *)vc didSaveSubscription:(NSDictionary *)subscription;
@end

@interface SubscriptionEditVC : UITableViewController <UITextFieldDelegate> {
    NSDictionary *_subscription;
    UITextField *_nameField,*_linkField,*_agentField;
    NSInteger _agentMode;
    BOOL _stealthMode,_saving;
    id<SubscriptionEditVCDelegate> _delegate;
}
@property (nonatomic, readonly) NSDictionary *subscription;
- (id)initWithSubscription:(NSDictionary *)subscription stealthMode:(BOOL)stealth delegate:(id<SubscriptionEditVCDelegate>)delegate;
- (void)finishSavingWithSubscription:(NSDictionary *)subscription errorText:(NSString *)error;
@end

@interface SubscriptionInfoVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSDictionary *_subscription;
    NSArray *_sections;
    NSInteger _subscriptionIndex;
    BOOL _stealthMode;
}
- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode;
- (NSInteger)subscriptionIndex;
- (void)reloadWithSubscription:(NSDictionary *)subscription;
@end
