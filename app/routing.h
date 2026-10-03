#import "app_support.h"

@class RoutingVC;

@interface RoutingVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate> {
    UITableView *_tableView;
    UISwitch *_enabledSwitch;
    UISwitch *_bypassLANSwitch;
    NSMutableArray *_rules;
    NSString *_pendingAction;
    NSString *_pendingType;
}
@end
