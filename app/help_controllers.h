#import "app_support.h"

@class FAQVC, AboutVC, LicenseDocumentVC, CreditsVC;

@interface FAQVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
}
@end

@interface AboutVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
    CGFloat _headerWidth;
}
@end

@interface LicenseDocumentVC : UIViewController {
    UITextView *_textView;
    NSString *_documentText;
    NSString *_resourceName;
    NSString *_marker;
    BOOL _didScrollToMarker;
}
- (id)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName marker:(NSString *)marker;
@end

@interface CreditsVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
}
@end
