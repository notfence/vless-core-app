#import "app_support.h"
#import "update_checker.h"

@class VCAccentColorVC, SettingsVC, XrayVersionSpoofVC, SettingsNavController, VCPingSettingsVC;

@protocol SettingsVCDelegate <NSObject>
- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeSortSubscriptionsByPing:(BOOL)enabled;
- (void)settingsVCDidChangePingSettings:(SettingsVC *)vc;
- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled;
- (void)settingsVCDidChangeAccentColor:(SettingsVC *)vc;
@end

@protocol VCAccentColorVCDelegate <NSObject>
- (void)accentColorVCDidChange;
@end

@protocol VCPingSettingsVCDelegate <NSObject>
- (void)pingSettingsVCDidChangeProbeSettings:(VCPingSettingsVC *)vc;
@end

@interface VCPingSettingsVC : UITableViewController <UIActionSheetDelegate, UIAlertViewDelegate> {
    id<VCPingSettingsVCDelegate> _delegate;
    UISlider *_timeoutSlider;
}
- (id)initWithDelegate:(id<VCPingSettingsVCDelegate>)delegate;
@end

@interface VCAccentColorVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    id<VCAccentColorVCDelegate> _delegate;
}
- (id)initWithDelegate:(id<VCAccentColorVCDelegate>)delegate;
@end

@interface SettingsVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIAlertViewDelegate, VCUpdateCheckerDelegate, VCAccentColorVCDelegate, VCPingSettingsVCDelegate> {
    UITableView *_tableView;
    UISwitch *_autoUpdateSwitch;
    UISwitch *_preserveCustomNamesSwitch;
    UISwitch *_sortSubscriptionsByPingSwitch;
    UISwitch *_stealthSwitch;
    UISwitch *_automaticUpdateChecksSwitch;
    UISwitch *_preferGitHubLegacySwitch;
    VCUpdateChecker *_updateChecker;
    NSString *_availableReleaseURL;
    BOOL _autoUpdate;
    BOOL _preserveCustomNames;
    BOOL _sortSubscriptionsByPing;
    BOOL _stealthMode;
    BOOL _darkTheme;
    BOOL _automaticUpdateChecks;
    CGFloat _footerWidth;
    id<SettingsVCDelegate> _delegate;
}
@property (nonatomic, assign) BOOL autoUpdate;
@property (nonatomic, assign) BOOL preserveCustomNames;
@property (nonatomic, assign) BOOL sortSubscriptionsByPing;
@property (nonatomic, assign) BOOL stealthMode;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, assign) BOOL automaticUpdateChecks;
@property (nonatomic, assign) id<SettingsVCDelegate> delegate;
@end

@interface XrayVersionSpoofVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    UITableView *_tableView;
    UISwitch *_enabledSwitch;
    UITextField *_versionField;
}
@end

@interface SettingsNavController : UINavigationController
@end
