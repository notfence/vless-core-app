#import "settings.h"
#import "update_checker.h"
#import "diagnostics.h"
#import "appearance.h"
#import "help_controllers.h"
#import "routing.h"

@class SettingsVC;

@implementation XrayVersionSpoofVC

- (void)dealloc {
    [_tableView release];
    [_enabledSwitch release];
    [_versionField release];
    [super dealloc];
}

- (BOOL)saveVersion {
    NSString *value = [_versionField.text
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!VCXrayVersionIsValid(value)) {
        _versionField.text = VCSelectedXrayVersion();
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid version"
                                                        message:@"Use x.y.z; each number must be from 0 to 255."
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil] autorelease];
        [error show];
        return NO;
    }

    _versionField.text = value;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:value forKey:kDefaultsXrayVersionKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"Xray spoof version saved", nil);
    return YES;
}

- (void)enabledSwitchChanged:(UISwitch *)sender {
    if ([sender isOn] && ![self saveVersion]) {
        [sender setOn:NO animated:YES];
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:[sender isOn] forKey:kDefaultsXrayVersionSpoofEnabledKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"Xray version spoof changed",
                     [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    (void)textField;
    [self saveVersion];
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _enabledSwitch.onTintColor = VCAccentColor();
    _versionField.textColor = VCPrimaryTextColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Xray version spoof";

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    _enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_enabledSwitch setOn:VCXrayVersionSpoofEnabled() animated:NO];
    [_enabledSwitch addTarget:self
                       action:@selector(enabledSwitchChanged:)
             forControlEvents:UIControlEventValueChanged];

    CGFloat fieldWidth = IsPadDevice() ? 220.0f : 150.0f;
    _versionField = [[UITextField alloc] initWithFrame:CGRectMake(0.0f, 0.0f, fieldWidth, 30.0f)];
    _versionField.borderStyle = UITextBorderStyleNone;
    _versionField.backgroundColor = [UIColor clearColor];
    _versionField.textAlignment = NSTextAlignmentRight;
    _versionField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _versionField.text = VCSelectedXrayVersion();
    _versionField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    _versionField.returnKeyType = UIReturnKeyDone;
    _versionField.autocorrectionType = UITextAutocorrectionTypeNo;
    _versionField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _versionField.clearButtonMode = UITextFieldViewModeNever;
    _versionField.delegate = self;

    [self applyTheme];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return @"Xray version";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [NSString stringWithFormat:
            @"When disabled, vless-core-cli reports Xray version %@. Changes apply on the next connection.",
            kDefaultXrayVersion];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat width = MAX(1.0f, tableView.bounds.size.width - 36.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14.0f]
                   constrainedToSize:CGSizeMake(width, 1000.0f)
                       lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height) + 14.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    UIView *footer = [[[UIView alloc] initWithFrame:
                       CGRectMake(0.0f, 0.0f, tableView.bounds.size.width, height)] autorelease];
    footer.backgroundColor = [UIColor clearColor];

    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(18.0f, 4.0f, tableView.bounds.size.width - 36.0f, height - 8.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:14.0f];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.text = text;
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"XrayVersionSpoofCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:cellIdentifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = (indexPath.row == 0) ? @"Enabled" : @"Version";
    cell.accessoryView = (indexPath.row == 0) ? (UIView *)_enabledSwitch : (UIView *)_versionField;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

@end

@implementation VCAccentColorVC

- (id)initWithDelegate:(id<VCAccentColorVCDelegate>)delegate {
    self = [super init];
    if (!self) return nil;
    _delegate = delegate;
    return self;
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    [_tableView reloadData];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Accent Color";
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
    [self applyTheme];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [VCAppearanceAccentNames() count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"AccentColorCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                       reuseIdentifier:cellIdentifier] autorelease];
    }

    NSInteger index = indexPath.row;
    BOOL selected = index == VCAppearanceAccentIndex();
    VCAppearanceApplyCell(cell);
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.text = [VCAppearanceAccentNames() objectAtIndex:index];
    cell.imageView.image = VCAppearanceAccentSwatchImage(
        VCAppearanceAccentColorAtIndex(index, VCAppearanceIsDark()));
    cell.accessoryType = selected ? UITableViewCellAccessoryCheckmark
                                  : UITableViewCellAccessoryNone;
    cell.accessibilityValue = selected ? @"Selected" : nil;
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger previousIndex = VCAppearanceAccentIndex();
    NSInteger selectedIndex = indexPath.row;
    if (selectedIndex != previousIndex) {
        VCAppearanceSetAccentIndex(selectedIndex);
        VCRecordAppEvent(@"settings", @"Accent color changed",
                         [NSString stringWithFormat:@"color=%@",
                          [VCAppearanceAccentIdentifiers() objectAtIndex:selectedIndex]]);
        [self applyTheme];
        if ([_delegate respondsToSelector:@selector(accentColorVCDidChange)]) {
            [_delegate accentColorVCDidChange];
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    _delegate = nil;
    [_tableView release];
    [super dealloc];
}

@end

@implementation SettingsVC
@synthesize autoUpdate = _autoUpdate;
@synthesize preserveCustomNames = _preserveCustomNames;
@synthesize stealthMode = _stealthMode;
@synthesize darkTheme = _darkTheme;
@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize delegate = _delegate;

- (void)closePressed {
    VCRecordAppEvent(@"ui", @"Settings closed", nil);
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)autoUpdateSwitchChanged:(UISwitch *)sw {
    _autoUpdate = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeAutoUpdate:)]) {
        [_delegate settingsVC:self didChangeAutoUpdate:_autoUpdate];
    }
}

- (void)preserveCustomNamesSwitchChanged:(UISwitch *)sw {
    _preserveCustomNames = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangePreserveCustomSubscriptionNames:)]) {
        [_delegate settingsVC:self didChangePreserveCustomSubscriptionNames:_preserveCustomNames];
    }
}

- (void)stealthSwitchChanged:(UISwitch *)sw {
    _stealthMode = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeStealthMode:)]) {
        [_delegate settingsVC:self didChangeStealthMode:_stealthMode];
    }
}

- (void)automaticUpdateChecksSwitchChanged:(UISwitch *)sw {
    _automaticUpdateChecks = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeAutomaticUpdateChecks:)]) {
        [_delegate settingsVC:self didChangeAutomaticUpdateChecks:_automaticUpdateChecks];
    }
}

- (void)preferGitHubLegacySwitchChanged:(UISwitch *)sw {
    BOOL enabled = [sw isOn];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDefaultsPreferGitHubLegacyKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings", @"GitHub Legacy priority changed",
                     enabled ? @"enabled=1" : @"enabled=0");
}

- (NSString *)updateCheckDetailText {
    if (_updateChecker) return @"Checking GitHub Releases...";

    NSString *latest = [[NSUserDefaults standardUserDefaults] objectForKey:kDefaultsLatestVersionKey];
    if ([latest isKindOfClass:[NSString class]] &&
        VCCompareVersions(AppShortVersion(), latest) == NSOrderedAscending) {
        return [NSString stringWithFormat:@"%@ is available", latest];
    }
    return [NSString stringWithFormat:@"Installed version %@", AppShortVersion()];
}

- (NSString *)displaySubscriptionHWID {
    NSString *hwid = SubscriptionHWID();
    NSRange separator = [hwid rangeOfString:@"-" options:NSBackwardsSearch];
    if (separator.location == NSNotFound) {
        return ([hwid length] > 12) ? [hwid substringFromIndex:([hwid length] - 12)] : hwid;
    }
    if (NSMaxRange(separator) >= [hwid length]) return hwid;
    return [hwid substringFromIndex:NSMaxRange(separator)];
}

- (void)copySubscriptionHWID {
    [[UIPasteboard generalPasteboard] setString:SubscriptionHWID()];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"HWID copied"
                                                     message:nil
                                                    delegate:nil
                                           cancelButtonTitle:@"OK"
                                           otherButtonTitles:nil] autorelease];
    [alert show];
}

- (UIView *)settingsFooterForWidth:(CGFloat)width {
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, width, 64.0f)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIButton *hwidButton = [UIButton buttonWithType:UIButtonTypeCustom];
    hwidButton.frame = CGRectMake(16.0f, 6.0f, width - 32.0f, 48.0f);
    hwidButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    hwidButton.titleLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    hwidButton.titleLabel.numberOfLines = 2;
    hwidButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    [hwidButton setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
    [hwidButton setTitle:[NSString stringWithFormat:@"HWID:\n%@", [self displaySubscriptionHWID]]
                 forState:UIControlStateNormal];
    hwidButton.accessibilityLabel = [NSString stringWithFormat:@"Subscription HWID: %@", SubscriptionHWID()];
    hwidButton.accessibilityHint = @"Copies the full HWID";
    [hwidButton addTarget:self action:@selector(copySubscriptionHWID) forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:hwidButton];

    return footer;
}

- (void)updateSettingsFooterForWidth:(CGFloat)width {
    if (width <= 0.0f) return;
    _footerWidth = width;
    _tableView.tableFooterView = [self settingsFooterForWidth:width];
}

- (void)startManualUpdateCheck {
    if (_updateChecker) return;

    _updateChecker = [[VCUpdateChecker alloc] initWithDelegate:self];
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:3];
    [_tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                      withRowAnimation:UITableViewRowAnimationNone];
    [_updateChecker start];
}

- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result {
    if (checker != _updateChecker) return;

    checker.delegate = nil;
    [_updateChecker release];
    _updateChecker = nil;

    NSString *status = [result objectForKey:@"status"];
    if (VCUpdateResultIsSuccessful(result)) {
        VCCacheSuccessfulUpdateResult(result);
    }

    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:1 inSection:3];
    [_tableView reloadRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                      withRowAnimation:UITableViewRowAnimationNone];

    if ([status isEqualToString:@"update"]) {
        [_availableReleaseURL release];
        _availableReleaseURL = [[result objectForKey:@"release_url"] copy];
        VCShowUpdateAvailableAlert(result, self, kVCSettingsUpdateAlertTag);
    } else if ([status isEqualToString:@"current"]) {
        NSString *message = [NSString stringWithFormat:@"Version %@ is the latest release.", AppShortVersion()];
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Up to Date"
                                                         message:message
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
    } else {
        NSString *error = [result objectForKey:@"error"];
        if (![error isKindOfClass:[NSString class]] || [error length] == 0) {
            error = @"Unable to check for updates.";
        }
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Update Check Failed"
                                                         message:error
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
    }
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _autoUpdateSwitch.onTintColor = VCAccentColor();
    _preserveCustomNamesSwitch.onTintColor = VCAccentColor();
    _stealthSwitch.onTintColor = VCAccentColor();
    _automaticUpdateChecksSwitch.onTintColor = VCAccentColor();
    _preferGitHubLegacySwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    [self updateSettingsFooterForWidth:_tableView.bounds.size.width];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
}

- (void)accentColorVCDidChange {
    [self applyTheme];
    if ([_delegate respondsToSelector:@selector(settingsVCDidChangeAccentColor:)]) {
        [_delegate settingsVCDidChangeAccentColor:self];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VCBackgroundColor();
    self.title = @"Settings";

    UIBarButtonItem *close = [[[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                style:UIBarButtonItemStyleBordered
                                                               target:self
                                                               action:@selector(closePressed)] autorelease];
    self.navigationItem.leftBarButtonItem = close;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    _autoUpdateSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
    [_autoUpdateSwitch addTarget:self action:@selector(autoUpdateSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _preserveCustomNamesSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_preserveCustomNamesSwitch setOn:_preserveCustomNames animated:NO];
    [_preserveCustomNamesSwitch addTarget:self
                                   action:@selector(preserveCustomNamesSwitchChanged:)
                         forControlEvents:UIControlEventValueChanged];

    _stealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_stealthSwitch setOn:_stealthMode animated:NO];
    [_stealthSwitch addTarget:self action:@selector(stealthSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _automaticUpdateChecksSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_automaticUpdateChecksSwitch setOn:_automaticUpdateChecks animated:NO];
    [_automaticUpdateChecksSwitch addTarget:self
                                     action:@selector(automaticUpdateChecksSwitchChanged:)
                           forControlEvents:UIControlEventValueChanged];

    _preferGitHubLegacySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_preferGitHubLegacySwitch setOn:VCPreferGitHubLegacy() animated:NO];
    [_preferGitHubLegacySwitch addTarget:self
                                  action:@selector(preferGitHubLegacySwitchChanged:)
                        forControlEvents:UIControlEventValueChanged];

    [self applyTheme];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = _tableView.bounds.size.width;
    if (fabs(_footerWidth - width) > 0.5f) {
        [self updateSettingsFooterForWidth:width];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_tableView reloadData];
    [_tableView layoutIfNeeded];

    for (NSIndexPath *indexPath in [_tableView indexPathsForVisibleRows]) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        [self applySettingsMarqueesToCell:cell
                                    title:[self settingsTitleTextForIndexPath:indexPath]
                                   detail:[self settingsDetailTextForIndexPath:indexPath]];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 7;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 3;
    if (section == 1) return 3;
    if (section == 2) return 3;
    if (section == 3) return 2;
    if (section == 4 || section == 5) return 1;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Subscriptions";
    if (section == 1) return @"Network";
    if (section == 2) return @"Appearance";
    if (section == 3) return @"Updates";
    if (section == 4) return @"Debug";
    if (section == 5) return @"Advanced";
    return @"About";
}

- (VCMarqueeLabel *)settingsMarqueeForCell:(UITableViewCell *)cell
                                        tag:(NSInteger)tag
                              createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[cell.contentView viewWithTag:tag];
    if (!marquee && createIfNeeded) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = tag;
        marquee.userInteractionEnabled = NO;
        marquee.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:marquee];
    }
    return marquee;
}

- (void)applySettingsMarqueesToCell:(UITableViewCell *)cell
                               title:(NSString *)title
                              detail:(NSString *)detail {
    if (!cell) return;
    NSString *titleText = ([title isKindOfClass:[NSString class]] ? title : @"");
    NSString *detailText = ([detail isKindOfClass:[NSString class]] ? detail : @"");
    UIColor *titleColor = VCPrimaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();

    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = titleColor;
    cell.detailTextLabel.textColor = detailColor;
    cell.textLabel.text = titleText;
    cell.detailTextLabel.text = detailText;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    VCMarqueeLabel *titleMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsTitleMarqueeTag createIfNeeded:YES];
    if ([titleText length] > 0) {
        titleMarquee.hidden = NO;
        titleMarquee.frame = cell.textLabel.frame;
        titleMarquee.font = cell.textLabel.font;
        titleMarquee.textColor = titleColor;
        titleMarquee.text = titleText;
        cell.textLabel.textColor = [UIColor clearColor];
    } else {
        [titleMarquee stopMarquee];
        titleMarquee.text = @"";
        titleMarquee.hidden = YES;
    }

    VCMarqueeLabel *detailMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsDetailMarqueeTag createIfNeeded:YES];
    if ([detailText length] > 0) {
        detailMarquee.hidden = NO;
        detailMarquee.frame = cell.detailTextLabel.frame;
        detailMarquee.font = cell.detailTextLabel.font;
        detailMarquee.textColor = detailColor;
        detailMarquee.text = detailText;
        cell.detailTextLabel.textColor = [UIColor clearColor];
    } else {
        [detailMarquee stopMarquee];
        detailMarquee.text = @"";
        detailMarquee.hidden = YES;
    }
}

- (NSString *)settingsTitleTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Auto-update subscriptions";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Preserve custom names";
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        return @"Stealth mode";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Routing";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Ping type";
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return @"Xray version spoof";
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"Light";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Dark";
    }
    if (indexPath.section == 2 && indexPath.row == 2) {
        return @"Accent Color";
    }
    if (indexPath.section == 3 && indexPath.row == 0) {
        return @"Automatic checks";
    }
    if (indexPath.section == 3 && indexPath.row == 1) {
        return @"Check for Updates";
    }
    if (indexPath.section == 4 && indexPath.row == 0) {
        return @"Debug and diagnostics";
    }
    if (indexPath.section == 5 && indexPath.row == 0) {
        return @"Prefer GitHub Legacy";
    }
    if (indexPath.section == 6 && indexPath.row == 0) {
        return @"About vless-core";
    }
    if (indexPath.section == 6 && indexPath.row == 1) {
        return @"Credits";
    }
    if (indexPath.section == 6 && indexPath.row == 2) {
        return @"FAQ";
    }
    if (indexPath.section == 6 && indexPath.row == 3) {
        return @"Project on GitHub";
    }
    return @"";
}

- (NSString *)settingsDetailTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Refresh subscriptions on app open";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Keep renamed subscriptions after updates";
    }
    if (indexPath.section == 0 && indexPath.row == 2) {
        return @"Hide links in configs and subscriptions";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Proxy, Direct and Block rules";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return VCSelectedPingTypeText();
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return VCSelectedXrayVersionText();
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"Use the light color scheme";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Use the dark color scheme";
    }
    if (indexPath.section == 2 && indexPath.row == 2) {
        return VCAppearanceAccentName();
    }
    if (indexPath.section == 3 && indexPath.row == 0) {
        return @"Check for new releases once a day";
    }
    if (indexPath.section == 3 && indexPath.row == 1) {
        return [self updateCheckDetailText];
    }
    if (indexPath.section == 4 && indexPath.row == 0) {
        return @"Live state, connection tests, events and reports";
    }
    if (indexPath.section == 5 && indexPath.row == 0) {
        return @"Open GitHub links in the app before the browser";
    }
    if (indexPath.section == 6 && indexPath.row == 0) {
        return @"Version and core binary info";
    }
    if (indexPath.section == 6 && indexPath.row == 1) {
        return @"Dependencies, licenses and special thanks";
    }
    if (indexPath.section == 6 && indexPath.row == 2) {
        return @"Common questions and quick answers";
    }
    if (indexPath.section == 6 && indexPath.row == 3) {
        return @"github.com/notfence/vless-core-app";
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        static NSString *kSwitchCellId = @"SettingsSwitchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSwitchCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
        cell.accessoryView = _autoUpdateSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Auto-update subscriptions"
                                   detail:@"Refresh subscriptions on app open"];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 1) {
        static NSString *kPreserveCustomNamesCellId = @"SettingsPreserveCustomNamesCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPreserveCustomNamesCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kPreserveCustomNamesCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_preserveCustomNamesSwitch setOn:_preserveCustomNames animated:NO];
        cell.accessoryView = _preserveCustomNamesSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Preserve custom names"
                                   detail:@"Keep renamed subscriptions after updates"];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 2) {
        static NSString *kStealthCellId = @"SettingsStealthCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kStealthCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kStealthCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_stealthSwitch setOn:_stealthMode animated:NO];
        cell.accessoryView = _stealthSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Stealth mode"
                                   detail:@"Hide links in configs and subscriptions"];
        return cell;
    }

    if (indexPath.section == 1) {
        static NSString *kNetworkCellId = @"SettingsNetworkCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kNetworkCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kNetworkCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        NSString *title = @"Xray version spoof";
        NSString *detail = VCSelectedXrayVersionText();
        if (indexPath.row == 0) {
            title = @"Routing";
            detail = @"Proxy, Direct and Block rules";
        } else if (indexPath.row == 1) {
            title = @"Ping type";
            detail = VCSelectedPingTypeText();
        }
        [self applySettingsMarqueesToCell:cell
                                    title:title
                                   detail:detail];
        return cell;
    }

    if (indexPath.section == 2) {
        static NSString *kThemeCellId = @"SettingsThemeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kThemeCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kThemeCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.imageView.image = nil;
        if (indexPath.row == 2) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = VCCreateDisclosureAccessoryView();
            cell.imageView.image = VCAppearanceAccentSwatchImage(VCAccentColor());
            [self applySettingsMarqueesToCell:cell
                                        title:@"Accent Color"
                                       detail:VCAppearanceAccentName()];
        } else {
            BOOL darkRow = (indexPath.row == 1);
            cell.accessoryView = nil;
            cell.accessoryType = (_darkTheme == darkRow) ? UITableViewCellAccessoryCheckmark
                                                         : UITableViewCellAccessoryNone;
            [self applySettingsMarqueesToCell:cell
                                        title:(darkRow ? @"Dark" : @"Light")
                                       detail:(darkRow ? @"Use the dark color scheme" : @"Use the light color scheme")];
        }
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 0) {
        static NSString *kAutomaticChecksCellId = @"SettingsAutomaticChecksCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAutomaticChecksCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kAutomaticChecksCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_automaticUpdateChecksSwitch setOn:_automaticUpdateChecks animated:NO];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = _automaticUpdateChecksSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Automatic checks"
                                   detail:@"Check for new releases once a day"];
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 1) {
        static NSString *kUpdateCellId = @"SettingsUpdateCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUpdateCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kUpdateCellId] autorelease];
        }
        cell.selectionStyle = _updateChecker ? UITableViewCellSelectionStyleNone
                                             : UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        if (_updateChecker) {
            UIActivityIndicatorViewStyle style = VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray;
            UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style] autorelease];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        } else {
            cell.accessoryView = VCCreateDisclosureAccessoryView();
        }
        [self applySettingsMarqueesToCell:cell
                                    title:@"Check for Updates"
                                   detail:[self updateCheckDetailText]];
        return cell;
    }

    if (indexPath.section == 4 && indexPath.row == 0) {
        static NSString *kDebugCellId = @"SettingsDebugCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDebugCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kDebugCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"Debug and diagnostics"
                                   detail:@"Live state, connection tests, events and reports"];
        return cell;
    }

    if (indexPath.section == 5 && indexPath.row == 0) {
        static NSString *kGitHubLegacyCellId = @"SettingsGitHubLegacyCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubLegacyCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kGitHubLegacyCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [_preferGitHubLegacySwitch setOn:VCPreferGitHubLegacy() animated:NO];
        cell.accessoryView = _preferGitHubLegacySwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Prefer GitHub Legacy"
                                   detail:@"Open GitHub links in the app before the browser"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 0) {
        static NSString *kAboutCellId = @"SettingsAboutCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"About vless-core"
                                   detail:@"Version and core binary info"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 1) {
        static NSString *kCreditsCellId = @"SettingsCreditsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"Credits"
                                   detail:@"Dependencies, licenses and special thanks"];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 2) {
        static NSString *kFAQCellId = @"SettingsFAQCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsMarqueesToCell:cell
                                    title:@"FAQ"
                                   detail:@"Common questions and quick answers"];
        return cell;
    }

    static NSString *kGitHubCellId = @"SettingsGitHubCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kGitHubCellId] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = VCCreateDisclosureAccessoryView();
    [self applySettingsMarqueesToCell:cell
                                title:@"Project on GitHub"
                               detail:@"github.com/notfence/vless-core-app"];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    [self applySettingsMarqueesToCell:cell
                                title:[self settingsTitleTextForIndexPath:indexPath]
                               detail:[self settingsDetailTextForIndexPath:indexPath]];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row == 0) {
        VCRecordAppEvent(@"ui", @"Routing settings opened", nil);
        RoutingVC *routing = [[[RoutingVC alloc] init] autorelease];
        [self.navigationController pushViewController:routing animated:YES];
    } else if (indexPath.section == 1 && indexPath.row == 1) {
        VCRecordAppEvent(@"ui", @"Ping type menu opened", nil);
        UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Ping type"
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Proxy GET", @"TCP", @"ICMP", nil] autorelease];
        sheet.tag = kVCSettingsPingTypeActionSheetTag;
        [sheet showInView:self.view];
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        VCRecordAppEvent(@"ui", @"Xray version settings opened", nil);
        XrayVersionSpoofVC *spoof = [[[XrayVersionSpoofVC alloc] init] autorelease];
        [self.navigationController pushViewController:spoof animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 2) {
        VCRecordAppEvent(@"ui", @"Accent color settings opened", nil);
        VCAccentColorVC *accent = [[[VCAccentColorVC alloc] initWithDelegate:self] autorelease];
        [self.navigationController pushViewController:accent animated:YES];
    } else if (indexPath.section == 2) {
        BOOL dark = (indexPath.row == 1);
        if (_darkTheme != dark) {
            _darkTheme = dark;
            VCAppearanceSetDark(dark);
            if ([_delegate respondsToSelector:@selector(settingsVC:didChangeDarkTheme:)]) {
                [_delegate settingsVC:self didChangeDarkTheme:dark];
            }
            [self applyTheme];
        }
    } else if (indexPath.section == 3) {
        if (indexPath.row == 1) {
            [self startManualUpdateCheck];
        }
    } else if (indexPath.section == 4) {
        VCRecordAppEvent(@"ui", @"Debug settings opened", nil);
        DebugVC *debug = [[[DebugVC alloc] init] autorelease];
        [self.navigationController pushViewController:debug animated:YES];
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) {
            AboutVC *about = [[[AboutVC alloc] init] autorelease];
            [self.navigationController pushViewController:about animated:YES];
        } else if (indexPath.row == 1) {
            CreditsVC *credits = [[[CreditsVC alloc] init] autorelease];
            [self.navigationController pushViewController:credits animated:YES];
        } else if (indexPath.row == 2) {
            FAQVC *faq = [[[FAQVC alloc] init] autorelease];
            [self.navigationController pushViewController:faq animated:YES];
        } else if (indexPath.row == 3) {
            VCOpenGitHubProject();
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != kVCSettingsPingTypeActionSheetTag ||
        buttonIndex < VCPingTypeProxyGET ||
        buttonIndex > VCPingTypeICMP ||
        buttonIndex == actionSheet.cancelButtonIndex) {
        return;
    }

    VCPingType pingType = (VCPingType)buttonIndex;
    VCRecordAppEvent(@"settings", @"Ping type changed",
                     [NSString stringWithFormat:@"type=%ld", (long)pingType]);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:pingType forKey:kDefaultsPingTypeKey];
    [defaults synchronize];
    [_tableView reloadRowsAtIndexPaths:
        [NSArray arrayWithObject:[NSIndexPath indexPathForRow:1 inSection:1]]
                          withRowAnimation:UITableViewRowAnimationNone];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != kVCSettingsUpdateAlertTag || buttonIndex == alertView.cancelButtonIndex) return;

    VCOpenGitHubLatestRelease(_availableReleaseURL);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    _updateChecker.delegate = nil;
    [_updateChecker release];
    [_availableReleaseURL release];
    [_tableView release];
    [_autoUpdateSwitch release];
    [_preserveCustomNamesSwitch release];
    [_stealthSwitch release];
    [_automaticUpdateChecksSwitch release];
    [_preferGitHubLegacySwitch release];
    [super dealloc];
}

@end

@implementation SettingsNavController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (UIViewController *)childViewControllerForStatusBarStyle {
    return nil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    VCAppearanceApplyNavigationBar(self.navigationBar);
}

- (BOOL)shouldAutorotate {
    return [[self topViewController] shouldAutorotate];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return [[self topViewController] supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[self topViewController] preferredInterfaceOrientationForPresentation];
}

@end
