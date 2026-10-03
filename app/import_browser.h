#import "app_support.h"

@class VCImportBrowserVC;

@protocol VCImportBrowserDelegate <NSObject>
- (void)importBrowserDidCancel:(UIViewController *)browser;
- (void)importBrowser:(UIViewController *)browser didSelectFileAtPath:(NSString *)path;
@end

@interface VCImportBrowserVC : UITableViewController {
    id<VCImportBrowserDelegate> _browserDelegate;
    NSString *_rootPath;
    NSString *_directoryPath;
    NSArray *_entries;
}
- (id)initWithRootPath:(NSString *)rootPath
         directoryPath:(NSString *)directoryPath
              delegate:(id<VCImportBrowserDelegate>)delegate;
@end
