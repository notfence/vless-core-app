#import "settings.h"
#import "update_checker.h"
#import "diagnostics.h"
#import "appearance.h"
#import "help_controllers.h"
#import "routing.h"
#import "settings_icons.h"

@class SettingsVC;
static NSInteger const kVCSettingsProxyPingURLAlertTag=7101;

static VCMarqueeLabel *VCSettingsMarqueeForCell(UITableViewCell *cell, NSInteger tag) {
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[cell.contentView viewWithTag:tag];
    if (!marquee) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = tag;
        marquee.userInteractionEnabled = NO;
        marquee.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:marquee];
    }
    return marquee;
}

typedef struct {
    CGRect icon, title, detail, accessory;
    CGFloat height;
    BOOL expanded;
} VCSettingsRowLayout;

static CGSize VCSettingsTextSize(NSString *text, UIFont *font, CGFloat width) {
    if (![text length] || !font || width <= 0.0f) return CGSizeZero;
    CGSize size = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, CGFLOAT_MAX)
                      lineBreakMode:NSLineBreakByWordWrapping];
    return CGSizeMake(ceil(size.width), ceil(size.height));
}

static VCSettingsRowLayout VCSettingsMeasureRow(CGFloat width, CGFloat textLeft, CGFloat inset,
                                               CGSize accessory, NSString *title, UIFont *titleFont,
                                               NSString *detail, UIFont *detailFont) {
    VCSettingsRowLayout layout = {0};
    layout.height = 44.0f;
    CGFloat gap = accessory.width > 0.0f ? 8.0f : 0.0f;
    CGFloat titleWidth = width - inset - textLeft - accessory.width - gap;
    CGFloat detailWidth = width - inset - textLeft;
    if (!isfinite(width) || !isfinite(titleWidth) || !isfinite(detailWidth) ||
        titleWidth <= 0.0f || detailWidth <= 0.0f) return layout;
    CGSize titleSize = VCSettingsTextSize(title, titleFont, titleWidth);
    CGSize detailSize = VCSettingsTextSize(detail, detailFont, titleWidth);
    layout.expanded = titleSize.height > ceil(titleFont.lineHeight) + 0.5f ||
                      detailSize.height > ceil(detailFont.lineHeight) + 0.5f;
    CGFloat center;
    if (layout.expanded) {
        detailSize = VCSettingsTextSize(detail, detailFont, detailWidth);
        CGFloat headerHeight = MAX(24.0f, MAX(accessory.height, titleSize.height));
        CGFloat detailTop = 8.0f + headerHeight + ([detail length] ? 4.0f : 0.0f);
        layout.height = MAX(44.0f, ceil(detailTop + detailSize.height + 8.0f));
        center = 8.0f + headerHeight * 0.5f;
        layout.title = CGRectMake(textLeft, center - titleSize.height * 0.5f, titleWidth, titleSize.height);
        layout.detail = CGRectMake(textLeft, detailTop, detailWidth, detailSize.height);
    } else {
        CGFloat textHeight = titleSize.height + detailSize.height;
        layout.height = MAX(44.0f, ceil(MAX(accessory.height + 8.0f, textHeight + 6.0f)));
        center = layout.height * 0.5f;
        layout.title = CGRectMake(textLeft, center - textHeight * 0.5f, titleWidth, titleSize.height);
        layout.detail = CGRectMake(textLeft, center - textHeight * 0.5f + titleSize.height, titleWidth, detailSize.height);
    }
    layout.icon = CGRectMake(inset, center - 12.0f, 24.0f, 24.0f);
    if (accessory.width > 0.0f) {
        layout.accessory = CGRectMake(width - inset - accessory.width, center - accessory.height * 0.5f,
                                     accessory.width, accessory.height);
    }
    return layout;
}

@interface VCSettingsTableCell : UITableViewCell {
    VCSettingsIconType _settingsIconType;
    UIColor *_settingsIconColor;
    CGFloat _settingsIconScale;
    UILabel *_settingsTitleLabel, *_settingsDetailLabel;
    VCSettingsRowLayout _settingsRowLayout;
    CGFloat _settingsLayoutWidth, _settingsTextLeft, _settingsRightInset;
    CGSize _settingsAccessorySize;
    BOOL _settingsLayoutValid;
}
- (void)applySettingsIcon:(VCSettingsIconType)icon;
- (void)applyAdaptiveTitle:(NSString *)title detail:(NSString *)detail;
- (CGFloat)settingsTextLeft;
- (CGFloat)settingsRightInset;
@end

@implementation VCSettingsTableCell

- (void)applySettingsIcon:(VCSettingsIconType)icon {
    UIColor *color = VCAccentColor();
    CGFloat scale = [UIScreen mainScreen].scale;
    if (self.imageView.image && _settingsIconType == icon &&
        [_settingsIconColor isEqual:color] && _settingsIconScale == scale) return;
    self.imageView.image = VCSettingsIconImage(icon);
    self.imageView.isAccessibilityElement = NO;
    [_settingsIconColor release];
    _settingsIconColor = [color retain];
    _settingsIconType = icon;
    _settingsIconScale = scale;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!_settingsTitleLabel || !_settingsDetailLabel) return;
    CGRect nativeTitle = [self.textLabel convertRect:self.textLabel.bounds toView:self];
    CGRect nativeIcon = [self.imageView convertRect:self.imageView.bounds toView:self];
    CGFloat width = self.bounds.size.width;
    CGFloat left = nativeTitle.origin.x;
    CGFloat inset = self.imageView.image ? nativeIcon.origin.x : left;
    CGSize accessory = self.accessoryView ? self.accessoryView.bounds.size :
        CGSizeMake(self.accessoryType == UITableViewCellAccessoryCheckmark ? 24.0f : 0.0f,
                   self.accessoryType == UITableViewCellAccessoryCheckmark ? 24.0f : 0.0f);
    if (!_settingsLayoutValid || _settingsLayoutWidth != width || _settingsTextLeft != left ||
        _settingsRightInset != inset || !CGSizeEqualToSize(_settingsAccessorySize, accessory)) {
        _settingsRowLayout = VCSettingsMeasureRow(width, left, inset, accessory,
            _settingsTitleLabel.text, _settingsTitleLabel.font, _settingsDetailLabel.text, _settingsDetailLabel.font);
        _settingsLayoutWidth = width;
        _settingsTextLeft = left;
        _settingsRightInset = inset;
        _settingsAccessorySize = accessory;
        _settingsLayoutValid = YES;
    }
    CGFloat offset = MAX(0.0f, (self.bounds.size.height - _settingsRowLayout.height) * 0.5f);
    CGRect title = _settingsRowLayout.title, detail = _settingsRowLayout.detail;
    title.origin.y += offset;
    detail.origin.y += offset;
    _settingsTitleLabel.frame = title;
    _settingsDetailLabel.frame = detail;
    if (title.size.width <= 0.0f) return;
    CGRect icon = _settingsRowLayout.icon;
    icon.origin.y += offset;
    self.imageView.frame = [self.imageView.superview convertRect:icon fromView:self];
    if (self.accessoryView) {
        CGRect frame = _settingsRowLayout.accessory;
        frame.origin.y += offset;
        self.accessoryView.frame = [self.accessoryView.superview convertRect:frame fromView:self];
    }
}

- (void)applyAdaptiveTitle:(NSString *)title detail:(NSString *)detail {
    if (!_settingsTitleLabel) {
        _settingsTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _settingsDetailLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        for (UILabel *label in [NSArray arrayWithObjects:_settingsTitleLabel, _settingsDetailLabel, nil]) {
            label.backgroundColor = [UIColor clearColor];
            label.userInteractionEnabled = NO;
            label.isAccessibilityElement = NO;
            label.numberOfLines = 0;
            label.lineBreakMode = NSLineBreakByWordWrapping;
            label.adjustsFontSizeToFitWidth = NO;
            [self addSubview:label];
        }
    }
    if (![_settingsTitleLabel.text isEqualToString:title] || ![_settingsDetailLabel.text isEqualToString:detail] ||
        ![_settingsTitleLabel.font isEqual:self.textLabel.font] || ![_settingsDetailLabel.font isEqual:self.detailTextLabel.font]) {
        _settingsLayoutValid = NO;
    }
    _settingsTitleLabel.font = self.textLabel.font;
    _settingsDetailLabel.font = self.detailTextLabel.font;
    _settingsTitleLabel.text = title;
    _settingsDetailLabel.text = detail;
    _settingsTitleLabel.textColor = _settingsTitleLabel.highlightedTextColor = VCPrimaryTextColor();
    _settingsDetailLabel.textColor = _settingsDetailLabel.highlightedTextColor = VCSecondaryTextColor();
    _settingsTitleLabel.hidden = ![title length];
    _settingsDetailLabel.hidden = ![detail length];
    self.textLabel.textColor = self.detailTextLabel.textColor = [UIColor clearColor];
    self.textLabel.highlightedTextColor = self.detailTextLabel.highlightedTextColor = [UIColor clearColor];
    [self setNeedsLayout];
}

- (CGFloat)settingsTextLeft {
    return _settingsTextLeft;
}

- (CGFloat)settingsRightInset {
    return _settingsRightInset;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _settingsTitleLabel.text = _settingsDetailLabel.text = @"";
    _settingsTitleLabel.hidden = _settingsDetailLabel.hidden = YES;
    _settingsLayoutValid = NO;
}

- (void)dealloc {
    [_settingsIconColor release];
    [_settingsTitleLabel release];
    [_settingsDetailLabel release];
    [super dealloc];
}

@end

static void VCApplyStaticSettingsCell(UITableViewCell *cell, NSString *title, NSString *detail) {
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
}

static void VCApplySettingsCell(UITableViewCell *cell, NSString *title, NSString *detail) {
    if (!cell) return;
    VCApplyStaticSettingsCell(cell,title,detail);
    NSString *titleText = cell.textLabel.text;
    NSString *detailText = cell.detailTextLabel.text;
    UIColor *titleColor = cell.textLabel.textColor;
    UIColor *detailColor = cell.detailTextLabel.textColor;
    if ([cell isKindOfClass:[VCSettingsTableCell class]]) {
        [(VCSettingsTableCell *)cell applyAdaptiveTitle:titleText detail:detailText];
        return;
    }
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    VCMarqueeLabel *titleMarquee = VCSettingsMarqueeForCell(cell,kVCSettingsTitleMarqueeTag);
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
    VCMarqueeLabel *detailMarquee = VCSettingsMarqueeForCell(cell,kVCSettingsDetailMarqueeTag);
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

@implementation VCPingSettingsVC

- (id)initWithDelegate:(id<VCPingSettingsVCDelegate>)delegate {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) _delegate = delegate;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ping";
    [_timeoutSlider release];
    _timeoutSlider = [[UISlider alloc] initWithFrame:CGRectMake(0.0f,0.0f,IsPadDevice() ? 220.0f : 140.0f,31.0f)];
    _timeoutSlider.minimumValue = kVCPingTimeoutMinimumSeconds;
    _timeoutSlider.maximumValue = kVCPingTimeoutMaximumSeconds;
    _timeoutSlider.value = VCPingTimeoutSecondsInDefaults([NSUserDefaults standardUserDefaults]);
    _timeoutSlider.accessibilityLabel = @"Ping timeout";
    _timeoutSlider.accessibilityValue = [self detailForSection:2];
    [_timeoutSlider addTarget:self action:@selector(timeoutChanged:) forControlEvents:UIControlEventValueChanged];
    [_timeoutSlider addTarget:self action:@selector(savePingTimeout:) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside|UIControlEventTouchCancel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(self.tableView);
    _timeoutSlider.minimumTrackTintColor = VCAccentColor();
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self savePingTimeout:_timeoutSlider];
    [super viewWillDisappear:animated];
}

- (void)dealloc {
    [_timeoutSlider release];
    [super dealloc];
}

- (NSString *)titleForSection:(NSInteger)section {
    return section == 0 ? @"Ping type" : section == 1 ? @"URL" : @"Timeout";
}

- (NSString *)detailForSection:(NSInteger)section {
    if (section == 0) return VCSelectedPingTypeText();
    if (section == 1) return VCSelectedProxyPingURL();
    return [NSString stringWithFormat:@"%ld seconds",(long)VCNormalizedPingTimeoutSeconds(_timeoutSlider.value)];
}

- (void)timeoutChanged:(UISlider *)sender {
    sender.value = VCNormalizedPingTimeoutSeconds(sender.value);
    NSString *detail=[self detailForSection:2];
    sender.accessibilityValue=detail;
    NSIndexPath *indexPath=[NSIndexPath indexPathForRow:0 inSection:2];
    UITableViewCell *cell=[self.tableView cellForRowAtIndexPath:indexPath];
    if (![cell.detailTextLabel.text isEqualToString:detail]) VCApplyStaticSettingsCell(cell,[self titleForSection:2],detail);
    if (!sender.tracking) [self savePingTimeout:sender];
}

- (void)savePingTimeout:(UISlider *)sender {
    if (!sender) return;
    NSInteger seconds=VCNormalizedPingTimeoutSeconds(sender.value);
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    if (seconds == VCPingTimeoutSecondsInDefaults(defaults)) return;
    [defaults setInteger:seconds forKey:kDefaultsPingTimeoutSecondsKey];
    [defaults synchronize];
    VCRecordAppEvent(@"settings",@"Ping timeout changed",[NSString stringWithFormat:@"timeout_seconds=%ld",(long)seconds]);
    if ([_delegate respondsToSelector:@selector(pingSettingsVCDidChangeProbeSettings:)]) [_delegate pingSettingsVCDidChangeProbeSettings:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"PingSettingsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier] autorelease];
    }
    cell.selectionStyle = indexPath.section == 2 ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    cell.accessoryView = indexPath.section == 2 ? (UIView *)_timeoutSlider : VCCreateDisclosureAccessoryView();
    VCApplyStaticSettingsCell(cell,[self titleForSection:indexPath.section],[self detailForSection:indexPath.section]);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCApplyStaticSettingsCell(cell,[self titleForSection:indexPath.section],[self detailForSection:indexPath.section]);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Choose how to check a profile.\nProxy GET: an HTTP request through the proxy.\nTCP: a connection to the server port.\nICMP: an echo request to the server. It may be blocked.";
    if (section == 1) return @"Target for Proxy GET and tunnel checks. Not used by TCP or ICMP. Only HTTP is supported. Redirects are not followed. Empty restores the default URL.";
    return @"Maximum wait per attempt for all ping types: 5–15 seconds. Up to two attempts run. The best result is shown. DNS and core startup can add time.";
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    return VCAppearanceTableFooterHeight(tableView, text, 14, 0.01f);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    return VCAppearanceTableFooterView(tableView, text, 14, height);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyFooterView(view, 14);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        VCRecordAppEvent(@"ui", @"Ping type menu opened", nil);
        UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Ping type" delegate:self
            cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Proxy GET", @"TCP", @"ICMP", nil] autorelease];
        sheet.tag = kVCSettingsPingTypeActionSheetTag;
        [sheet showInView:self.view];
    } else if (indexPath.section == 1) {
        UIAlertView *alert=[[[UIAlertView alloc] initWithTitle:@"Proxy GET URL"
            message:@"HTTP only. Empty restores the default."
            delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Save",nil] autorelease];
        alert.tag=kVCSettingsProxyPingURLAlertTag;
        alert.alertViewStyle=UIAlertViewStylePlainTextInput;
        UITextField *field=[alert textFieldAtIndex:0];
        field.text=VCSelectedProxyPingURL();
        field.keyboardType=UIKeyboardTypeURL;
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.clearButtonMode=UITextFieldViewModeWhileEditing;
        [alert show];
    }
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag != kVCSettingsPingTypeActionSheetTag || buttonIndex < VCPingTypeProxyGET ||
        buttonIndex > VCPingTypeICMP || buttonIndex == actionSheet.cancelButtonIndex) return;
    VCPingType pingType = (VCPingType)buttonIndex;
    BOOL changed=pingType != VCSelectedPingType();
    VCRecordAppEvent(@"settings", @"Ping type changed", [NSString stringWithFormat:@"type=%ld", (long)pingType]);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:pingType forKey:kDefaultsPingTypeKey];
    [defaults synchronize];
    if (changed && [_delegate respondsToSelector:@selector(pingSettingsVCDidChangeProbeSettings:)]) [_delegate pingSettingsVCDidChangeProbeSettings:self];
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == kVCSettingsProxyPingURLAlertTag) {
        if (buttonIndex == alertView.cancelButtonIndex) return;
        NSString *value=[alertView textFieldAtIndex:0].text;
        if (![value length]) value=kVCDefaultProxyPingURL;
        if (!VCProxyPingTargetForURL(value)) {
            UIAlertView *error=[[[UIAlertView alloc] initWithTitle:@"Invalid Proxy GET URL"
                message:@"Use an http:// URL up to 2048 characters, without spaces, credentials or a fragment. Use percent-encoding in the path and query; an explicit port must be 1–65535."
                delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
            [error show];
            return;
        }
        BOOL changed=![value isEqualToString:VCSelectedProxyPingURL()];
        NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
        if ([value isEqualToString:kVCDefaultProxyPingURL]) [defaults removeObjectForKey:kDefaultsProxyPingURLKey];
        else [defaults setObject:value forKey:kDefaultsProxyPingURLKey];
        [defaults synchronize];
        if (changed) {
            VCRecordAppEvent(@"settings",@"Proxy GET URL changed",nil);
            if ([_delegate respondsToSelector:@selector(pingSettingsVCDidChangeProbeSettings:)]) [_delegate pingSettingsVCDidChangeProbeSettings:self];
        }
        [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

@end

@implementation XrayVersionSpoofVC

- (void)dealloc {
    [_tableView release];
    [_enabledSwitch release];
    [_versionField release];
    [super dealloc];
}

- (BOOL)saveVersion {
    NSString *value = _versionField.text;
    if (!VCXrayVersionIsValid(value)) {
        _versionField.text = VCSelectedXrayVersion();
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid version"
                                                        message:@"Use x.y.z with decimal numbers from 0 to 255, without signs or spaces."
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
    return VCAppearanceTableFooterHeight(tableView, text, 14, 0.01f);
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    return VCAppearanceTableFooterView(tableView, text, 14, height);
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
    VCAppearanceApplyFooterView(view, 14);
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
@synthesize sortSubscriptionsByPing = _sortSubscriptionsByPing;
@synthesize useXmux = _useXmux;
@synthesize stealthMode = _stealthMode;
@synthesize darkTheme = _darkTheme;
@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize delegate = _delegate;

- (void)prepareSettingsMetricsForTable:(UITableView *)tableView {
    CGFloat width = tableView.bounds.size.width;
    if (width <= 0.0f || !isfinite(width)) return;
    if (!_settingsSizingCell) {
        _settingsSizingCell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
        _settingsSizingCell.imageView.image = VCSettingsIconImage(VCSettingsIconAutoUpdate);
        _settingsSizingCell.textLabel.text = @"Settings";
        _settingsSizingCell.detailTextLabel.text = @"Settings";
    }
    if (_settingsTableWidth == width) return;
    _settingsTableWidth = width;
    _settingsSizingCell.frame = CGRectMake(0.0f, 0.0f, width, 44.0f);
    [_settingsSizingCell setNeedsLayout];
    [_settingsSizingCell layoutIfNeeded];
    CGRect title = [_settingsSizingCell.textLabel convertRect:_settingsSizingCell.textLabel.bounds toView:_settingsSizingCell];
    CGRect icon = [_settingsSizingCell.imageView convertRect:_settingsSizingCell.imageView.bounds toView:_settingsSizingCell];
    _settingsRowWidth = width;
    _settingsTextLeft = title.origin.x;
    _settingsRightInset = icon.origin.x;
}

- (void)scheduleSettingsHeightRefresh {
    if (_settingsHeightRefreshPending) return;
    _settingsHeightRefreshPending = YES;
    [self performSelector:@selector(refreshSettingsRowHeights) withObject:nil afterDelay:0.0];
}

- (void)refreshSettingsRowHeights {
    _settingsHeightRefreshPending = NO;
    BOOL animations = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    [_tableView beginUpdates];
    [_tableView endUpdates];
    [UIView setAnimationsEnabled:animations];
}

- (void)recordSettingsMetricsFromCell:(VCSettingsTableCell *)cell {
    CGFloat width = cell.bounds.size.width, left = [cell settingsTextLeft], inset = [cell settingsRightInset];
    if (width <= 0.0f || left <= 0.0f || inset < 0.0f) return;
    if (fabs(_settingsRowWidth - width) < 0.01f && fabs(_settingsTextLeft - left) < 0.01f &&
        fabs(_settingsRightInset - inset) < 0.01f) return;
    _settingsRowWidth = width;
    _settingsTextLeft = left;
    _settingsRightInset = inset;
    [self scheduleSettingsHeightRefresh];
}

- (CGSize)settingsAccessorySizeForIndexPath:(NSIndexPath *)indexPath {
    UIView *accessory = nil;
    if (indexPath.section == 0) {
        if (indexPath.row == 0) accessory = _autoUpdateSwitch;
        else if (indexPath.row == 1) accessory = _preserveCustomNamesSwitch;
        else if (indexPath.row == 2) accessory = _stealthSwitch;
        else if (indexPath.row == 3) accessory = _sortSubscriptionsByPingSwitch;
    } else if (indexPath.section == 1 && indexPath.row == 3) accessory = _useXmuxSwitch;
    else if (indexPath.section == 3 && indexPath.row == 0) accessory = _automaticUpdateChecksSwitch;
    else if (indexPath.section == 5) accessory = _preferGitHubLegacySwitch;
    if (accessory) return accessory.bounds.size;
    if (indexPath.section == 2 && indexPath.row < 2) {
        BOOL checked = _darkTheme == (indexPath.row == 1);
        return checked ? CGSizeMake(24.0f, 24.0f) : CGSizeZero;
    }
    return CGSizeMake(20.0f, 20.0f);
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    [self prepareSettingsMetricsForTable:tableView];
    VCSettingsRowLayout layout = VCSettingsMeasureRow(_settingsRowWidth, _settingsTextLeft, _settingsRightInset,
        [self settingsAccessorySizeForIndexPath:indexPath], [self settingsTitleTextForIndexPath:indexPath],
        _settingsSizingCell.textLabel.font, [self settingsDetailTextForIndexPath:indexPath],
        _settingsSizingCell.detailTextLabel.font);
    return layout.height;
}

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

- (void)sortSubscriptionsByPingSwitchChanged:(UISwitch *)sw {
    _sortSubscriptionsByPing = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeSortSubscriptionsByPing:)]) {
        [_delegate settingsVC:self didChangeSortSubscriptionsByPing:_sortSubscriptionsByPing];
    }
}

- (void)useXmuxSwitchChanged:(UISwitch *)sw {
    _useXmux = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeUseXmux:)]) {
        [_delegate settingsVC:self didChangeUseXmux:_useXmux];
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
    _sortSubscriptionsByPingSwitch.onTintColor = VCAccentColor();
    _useXmuxSwitch.onTintColor = VCAccentColor();
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

- (void)pingSettingsVCDidChangeProbeSettings:(VCPingSettingsVC *)vc {
    (void)vc;
    if ([_delegate respondsToSelector:@selector(settingsVCDidChangePingSettings:)]) [_delegate settingsVCDidChangePingSettings:self];
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

    _sortSubscriptionsByPingSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_sortSubscriptionsByPingSwitch setOn:_sortSubscriptionsByPing animated:NO];
    [_sortSubscriptionsByPingSwitch addTarget:self action:@selector(sortSubscriptionsByPingSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _useXmuxSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_useXmuxSwitch setOn:_useXmux animated:NO];
    [_useXmuxSwitch addTarget:self action:@selector(useXmuxSwitchChanged:) forControlEvents:UIControlEventValueChanged];

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
    if (_settingsVisibleTableWidth != width) {
        _settingsVisibleTableWidth = width;
        [self prepareSettingsMetricsForTable:_tableView];
        [_tableView layoutIfNeeded];
        for (NSIndexPath *indexPath in [_tableView indexPathsForVisibleRows]) {
            VCSettingsTableCell *cell = (VCSettingsTableCell *)[_tableView cellForRowAtIndexPath:indexPath];
            [cell setNeedsLayout];
            [cell layoutIfNeeded];
            [self recordSettingsMetricsFromCell:cell];
        }
        [self scheduleSettingsHeightRefresh];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshSettingsRowHeights) object:nil];
    _settingsHeightRefreshPending = NO;
    [super viewWillDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    [_tableView reloadData];
    [_tableView layoutIfNeeded];

    for (NSIndexPath *indexPath in [_tableView indexPathsForVisibleRows]) {
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        [self applySettingsCell:cell atIndexPath:indexPath];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 7;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return 4;
    if (section == 1) return 4;
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

- (void)applySettingsCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    [(VCSettingsTableCell *)cell applySettingsIcon:VCSettingsIconForRow(indexPath.section, indexPath.row)];
    VCApplySettingsCell(cell, [self settingsTitleTextForIndexPath:indexPath],
                        [self settingsDetailTextForIndexPath:indexPath]);
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
    if (indexPath.section == 0 && indexPath.row == 3) {
        return @"Sort configs by ping";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Routing";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Ping";
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return @"Xray version spoof";
    }
    if (indexPath.section == 1 && indexPath.row == 3) {
        return @"Use XMUX";
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
    if (indexPath.section == 0 && indexPath.row == 3) {
        return @"Lowest latency first within each subscription";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Proxy, Direct and Block rules";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Ping settings";
    }
    if (indexPath.section == 1 && indexPath.row == 2) {
        return VCSelectedXrayVersionText();
    }
    if (indexPath.section == 1 && indexPath.row == 3) {
        return @"Use XMUX for supported configs";
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
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSwitchCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
        cell.accessoryView = _autoUpdateSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 1) {
        static NSString *kPreserveCustomNamesCellId = @"SettingsPreserveCustomNamesCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPreserveCustomNamesCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kPreserveCustomNamesCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_preserveCustomNamesSwitch setOn:_preserveCustomNames animated:NO];
        cell.accessoryView = _preserveCustomNamesSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 2) {
        static NSString *kStealthCellId = @"SettingsStealthCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kStealthCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kStealthCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_stealthSwitch setOn:_stealthMode animated:NO];
        cell.accessoryView = _stealthSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 3) {
        static NSString *kPingSortCellId = @"SettingsPingSortCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kPingSortCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kPingSortCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_sortSubscriptionsByPingSwitch setOn:_sortSubscriptionsByPing animated:NO];
        cell.accessoryView = _sortSubscriptionsByPingSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 1 && indexPath.row == 3) {
        static NSString *identifier = @"SettingsUseXmuxCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_useXmuxSwitch setOn:_useXmux animated:NO];
        cell.accessoryView = _useXmuxSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 1) {
        static NSString *kNetworkCellId = @"SettingsNetworkCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kNetworkCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kNetworkCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 2) {
        static NSString *kThemeCellId = @"SettingsThemeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kThemeCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kThemeCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        if (indexPath.row == 2) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = VCCreateDisclosureAccessoryView();
            [self applySettingsCell:cell atIndexPath:indexPath];
        } else {
            BOOL darkRow = (indexPath.row == 1);
            cell.accessoryView = nil;
            cell.accessoryType = (_darkTheme == darkRow) ? UITableViewCellAccessoryCheckmark
                                                         : UITableViewCellAccessoryNone;
            [self applySettingsCell:cell atIndexPath:indexPath];
        }
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 0) {
        static NSString *kAutomaticChecksCellId = @"SettingsAutomaticChecksCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAutomaticChecksCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kAutomaticChecksCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_automaticUpdateChecksSwitch setOn:_automaticUpdateChecks animated:NO];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = _automaticUpdateChecksSwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 3 && indexPath.row == 1) {
        static NSString *kUpdateCellId = @"SettingsUpdateCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kUpdateCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kUpdateCellId] autorelease];
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
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 4 && indexPath.row == 0) {
        static NSString *kDebugCellId = @"SettingsDebugCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kDebugCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kDebugCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 5 && indexPath.row == 0) {
        static NSString *kGitHubLegacyCellId = @"SettingsGitHubLegacyCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubLegacyCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                           reuseIdentifier:kGitHubLegacyCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        [_preferGitHubLegacySwitch setOn:VCPreferGitHubLegacy() animated:NO];
        cell.accessoryView = _preferGitHubLegacySwitch;
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 0) {
        static NSString *kAboutCellId = @"SettingsAboutCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 1) {
        static NSString *kCreditsCellId = @"SettingsCreditsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    if (indexPath.section == 6 && indexPath.row == 2) {
        static NSString *kFAQCellId = @"SettingsFAQCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
        if (!cell) {
            cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
        [self applySettingsCell:cell atIndexPath:indexPath];
        return cell;
    }

    static NSString *kGitHubCellId = @"SettingsGitHubCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubCellId];
    if (!cell) {
        cell = [[[VCSettingsTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kGitHubCellId] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = VCCreateDisclosureAccessoryView();
    [self applySettingsCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    [self applySettingsCell:cell atIndexPath:indexPath];
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    [self recordSettingsMetricsFromCell:(VCSettingsTableCell *)cell];
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
        VCRecordAppEvent(@"ui", @"Ping settings opened", nil);
        VCPingSettingsVC *ping = [[[VCPingSettingsVC alloc] initWithDelegate:self] autorelease];
        [self.navigationController pushViewController:ping animated:YES];
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshSettingsRowHeights) object:nil];
    [_settingsSizingCell release];
    [_updateChecker release];
    [_availableReleaseURL release];
    [_tableView release];
    [_autoUpdateSwitch release];
    [_preserveCustomNamesSwitch release];
    [_sortSubscriptionsByPingSwitch release];
    [_useXmuxSwitch release];
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
