#import "subscription_info.h"

@class SubscriptionInfoVC;

@implementation SubscriptionInfoVC

- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode
                  delegate:(id<SubscriptionInfoVCDelegate>)delegate {
    self = [super init];
    if (!self) return nil;

    _subscription = [subscription copy];
    _subscriptionIndex = index;
    _stealthMode = stealthMode;
    _delegate = delegate;
    return self;
}

- (void)dealloc {
    [_tableView release];
    [_subscription release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail action:(NSString *)action {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    [row setObject:(title ? title : @"") forKey:@"title"];
    if ([detail isKindOfClass:[NSString class]] && [detail length] > 0) {
        [row setObject:detail forKey:@"detail"];
    }
    if ([action isKindOfClass:[NSString class]] && [action length] > 0) {
        [row setObject:action forKey:@"action"];
    }
    return row;
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            (title ? title : @""), @"title",
            (rows ? rows : [NSArray array]), @"rows",
            nil];
}

- (NSString *)formattedBytes:(unsigned long long)bytes {
    static NSString *const units[] = {@"B", @"KB", @"MB", @"GB", @"TB", @"PB"};
    double value = (double)bytes;
    NSUInteger unit = 0;
    while (value >= 1024.0 && unit < 5) {
        value /= 1024.0;
        unit++;
    }
    if (unit == 0 || value >= 10.0) {
        return [NSString stringWithFormat:@"%.0f %@", value, units[unit]];
    }
    return [NSString stringWithFormat:@"%.1f %@", value, units[unit]];
}

- (NSString *)formattedTimestamp:(unsigned long long)timestamp includeTime:(BOOL)includeTime {
    if (timestamp == 0) return nil;
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)timestamp];
    if (!date) return nil;

    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
    [formatter setDateFormat:(includeTime ? @"dd.MM.yyyy HH:mm" : @"dd.MM.yyyy")];
    return [formatter stringFromDate:date];
}

- (void)buildSections {
    NSMutableArray *newSections = [NSMutableArray array];
    NSMutableArray *generalRows = [NSMutableArray array];
    NSMutableArray *usageRows = [NSMutableArray array];
    NSMutableArray *providerRows = [NSMutableArray array];

    NSString *name = [_subscription objectForKey:@"name"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) name = @"Unnamed subscription";
    [generalRows addObject:[self rowWithTitle:@"Name" detail:name action:nil]];

    NSString *url = [_subscription objectForKey:@"url"];
    if (![url isKindOfClass:[NSString class]]) url = @"";
    BOOL encryptedHappSubscription = SubscriptionDictionaryIsHappEncrypted(_subscription);
    NSString *shownURL = (_stealthMode || encryptedHappSubscription) ? kHiddenLinkText : url;
    if ([shownURL length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Subscription Link" detail:shownURL action:nil]];
    }

    NSDictionary *metadata = [_subscription objectForKey:kSubscriptionMetadataKey];
    if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
    NSString *description = [metadata objectForKey:kSubscriptionDescriptionKey];
    if ([description isKindOfClass:[NSString class]] && [description length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Description" detail:description action:nil]];
    }
    [newSections addObject:[self sectionWithTitle:@"Subscription" rows:generalRows]];

    NSArray *items = [_subscription objectForKey:@"items"];
    NSUInteger itemCount = [items isKindOfClass:[NSArray class]] ? [items count] : 0;
    [usageRows addObject:[self rowWithTitle:@"Configurations"
                                    detail:[NSString stringWithFormat:@"%lu", (unsigned long)itemCount]
                                    action:nil]];

    NSDictionary *userInfo = [_subscription objectForKey:kSubscriptionUserInfoKey];
    if ([userInfo isKindOfClass:[NSDictionary class]]) {
        NSNumber *uploadNumber = [userInfo objectForKey:kSubscriptionUploadKey];
        NSNumber *downloadNumber = [userInfo objectForKey:kSubscriptionDownloadKey];
        NSNumber *totalNumber = [userInfo objectForKey:kSubscriptionTotalKey];
        NSNumber *expireNumber = [userInfo objectForKey:kSubscriptionExpireKey];
        BOOL hasUpload = [uploadNumber isKindOfClass:[NSNumber class]];
        BOOL hasDownload = [downloadNumber isKindOfClass:[NSNumber class]];

        unsigned long long upload = hasUpload ? [uploadNumber unsignedLongLongValue] : 0;
        unsigned long long download = hasDownload ? [downloadNumber unsignedLongLongValue] : 0;
        if (hasUpload || hasDownload) {
            unsigned long long used = (ULLONG_MAX - upload < download) ? ULLONG_MAX : upload + download;
            [usageRows addObject:[self rowWithTitle:@"Traffic Used" detail:[self formattedBytes:used] action:nil]];
        }
        if (hasUpload) {
            [usageRows addObject:[self rowWithTitle:@"Uploaded" detail:[self formattedBytes:upload] action:nil]];
        }
        if (hasDownload) {
            [usageRows addObject:[self rowWithTitle:@"Downloaded" detail:[self formattedBytes:download] action:nil]];
        }
        if ([totalNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long total = [totalNumber unsignedLongLongValue];
            NSString *limit = (total == 0) ? @"Unlimited" : [self formattedBytes:total];
            [usageRows addObject:[self rowWithTitle:@"Traffic Limit" detail:limit action:nil]];
        }
        if ([expireNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long expire = [expireNumber unsignedLongLongValue];
            NSString *expiry = (expire == 0) ? @"No expiration" : [self formattedTimestamp:expire includeTime:NO];
            if ([expiry length] > 0) {
                [usageRows addObject:[self rowWithTitle:@"Expires" detail:expiry action:nil]];
            }
        }
    }

    NSNumber *refillNumber = [metadata objectForKey:kSubscriptionRefillDateKey];
    if ([refillNumber isKindOfClass:[NSNumber class]]) {
        NSString *refill = [self formattedTimestamp:[refillNumber unsignedLongLongValue] includeTime:NO];
        if ([refill length] > 0) {
            [usageRows addObject:[self rowWithTitle:@"Traffic Refill" detail:refill action:nil]];
        }
    }
    [newSections addObject:[self sectionWithTitle:@"Usage" rows:usageRows]];

    NSString *webPageURL = [metadata objectForKey:kSubscriptionWebPageURLKey];
    if ([webPageURL isKindOfClass:[NSString class]] && [webPageURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Web Page"
                                            detail:(_stealthMode ? kHiddenLinkText : webPageURL)
                                            action:nil]];
    }
    NSString *supportURL = [metadata objectForKey:kSubscriptionSupportURLKey];
    if ([supportURL isKindOfClass:[NSString class]] && [supportURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Support"
                                            detail:(_stealthMode ? kHiddenLinkText : supportURL)
                                            action:nil]];
    }
    NSNumber *intervalNumber = [metadata objectForKey:kSubscriptionUpdateIntervalKey];
    if ([intervalNumber isKindOfClass:[NSNumber class]]) {
        unsigned long long hours = [intervalNumber unsignedLongLongValue];
        NSString *interval = [NSString stringWithFormat:@"%llu hour%@", hours, (hours == 1 ? @"" : @"s")];
        [providerRows addObject:[self rowWithTitle:@"Suggested Update Interval" detail:interval action:nil]];
    }
    NSNumber *lastUpdatedNumber = [metadata objectForKey:kSubscriptionLastUpdatedKey];
    if ([lastUpdatedNumber isKindOfClass:[NSNumber class]]) {
        NSString *lastUpdated = [self formattedTimestamp:[lastUpdatedNumber unsignedLongLongValue] includeTime:YES];
        if ([lastUpdated length] > 0) {
            [providerRows addObject:[self rowWithTitle:@"Last Updated" detail:lastUpdated action:nil]];
        }
    }
    [providerRows addObject:[self rowWithTitle:@"Source"
                                       detail:(encryptedHappSubscription
                                                   ? @"HAPP (encrypted)"
                                                   : (SubscriptionDictionaryUsesHappHeaders(_subscription) ? @"HAPP" : @"URL"))
                                       action:nil]];
    [newSections addObject:[self sectionWithTitle:@"Provider" rows:providerRows]];

    NSArray *actions = [NSArray arrayWithObjects:
                        [self rowWithTitle:@"Rename Subscription" detail:nil action:@"rename"],
                        [self rowWithTitle:(_refreshing ? @"Updating..." : @"Update Now") detail:nil action:@"refresh"],
                        [self rowWithTitle:@"Delete Subscription" detail:nil action:@"delete"],
                        nil];
    [newSections addObject:[self sectionWithTitle:@"Actions" rows:actions]];

    [_sections release];
    _sections = [[NSArray alloc] initWithArray:newSections];
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
    self.title = @"Subscription Info";
    self.view.backgroundColor = VCBackgroundColor();

    UIBarButtonItem *back = [[[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                              style:UIBarButtonItemStyleBordered
                                                             target:self
                                                             action:@selector(backPressed)] autorelease];
    self.navigationItem.leftBarButtonItem = back;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    [self buildSections];
    [self applyTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyTheme];
}

- (void)backPressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)subscriptionIndex {
    return _subscriptionIndex;
}

- (void)reloadWithSubscription:(NSDictionary *)subscription {
    if (![subscription isKindOfClass:[NSDictionary class]]) return;
    [_subscription release];
    _subscription = [subscription copy];
    [self buildSections];
    [_tableView reloadData];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *section = [_sections objectAtIndex:indexPath.section];
    return [[section objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return [[[_sections objectAtIndex:section] objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    if ([row objectForKey:@"action"]) return 44.0f;

    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                          constrainedToSize:CGSizeMake(width, 1000.0f)
                              lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    NSString *reuseID = action ? @"SubscriptionActionCell" : @"SubscriptionInfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        UITableViewCellStyle style = action ? UITableViewCellStyleDefault : UITableViewCellStyleSubtitle;
        cell = [[[UITableViewCell alloc] initWithStyle:style reuseIdentifier:reuseID] autorelease];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);

    if (action) {
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.textLabel.textColor = [action isEqualToString:@"delete"] ? VCErrorColor() : VCDefaultAccentColor();
        cell.selectionStyle = _refreshing ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
        if ([action isEqualToString:@"refresh"] && _refreshing) {
            UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc]
                initWithActivityIndicatorStyle:(VCAppearanceIsDark() ? UIActivityIndicatorViewStyleWhite
                                                                     : UIActivityIndicatorViewStyleGray)] autorelease];
            [spinner startAnimating];
            cell.accessoryView = spinner;
        }
    } else {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    if ([action isEqualToString:@"delete"]) cell.textLabel.textColor = VCErrorColor();
    else if ([action length] > 0) cell.textLabel.textColor = VCDefaultAccentColor();
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *action = [row objectForKey:@"action"];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_refreshing || !action) return;

    if ([action isEqualToString:@"rename"]) {
        NSString *name = [_subscription objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]]) name = @"";

        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Rename Subscription"
                                                        message:nil
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Save", nil] autorelease];
        alert.tag = kVCSubscriptionRenameAlertTag;
        alert.alertViewStyle = UIAlertViewStylePlainTextInput;
        UITextField *nameField = [alert textFieldAtIndex:0];
        nameField.text = name;
        nameField.placeholder = @"Subscription name";
        nameField.clearButtonMode = UITextFieldViewModeWhileEditing;
        [alert show];
    } else if ([action isEqualToString:@"refresh"]) {
        _refreshing = YES;
        [self buildSections];
        [_tableView reloadData];
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVCRequestedRefresh:atIndex:)]) {
            [_delegate subscriptionInfoVCRequestedRefresh:self atIndex:_subscriptionIndex];
        } else {
            [self finishRefreshWithSubscription:nil errorText:@"Subscription update is unavailable"];
        }
    } else if ([action isEqualToString:@"delete"]) {
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Delete Subscription?"
                                                        message:@"The subscription and all of its configurations will be removed."
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Delete", nil] autorelease];
        alert.tag = kVCSubscriptionDeleteAlertTag;
        [alert show];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;

    if (alertView.tag == kVCSubscriptionRenameAlertTag) {
        NSString *name = [[alertView textFieldAtIndex:0] text];
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([name length] == 0) {
            UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid Name"
                                                            message:@"Subscription name cannot be empty."
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil] autorelease];
            [error show];
            return;
        }
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVC:requestedRenameTo:atIndex:)]) {
            [_delegate subscriptionInfoVC:self requestedRenameTo:name atIndex:_subscriptionIndex];
        }
    } else if (alertView.tag == kVCSubscriptionDeleteAlertTag) {
        if ([_delegate respondsToSelector:@selector(subscriptionInfoVCRequestedDelete:atIndex:)]) {
            [_delegate subscriptionInfoVCRequestedDelete:self atIndex:_subscriptionIndex];
        }
    }
}

- (void)finishRefreshWithSubscription:(NSDictionary *)subscription errorText:(NSString *)errorText {
    _refreshing = NO;
    if ([subscription isKindOfClass:[NSDictionary class]]) [self reloadWithSubscription:subscription];
    else {
        [self buildSections];
        [_tableView reloadData];
    }

    NSString *title = subscription ? @"Updated" : @"Update Failed";
    NSString *message = errorText;
    if (![message isKindOfClass:[NSString class]] || [message length] == 0) {
        NSArray *items = [_subscription objectForKey:@"items"];
        NSUInteger count = [items isKindOfClass:[NSArray class]] ? [items count] : 0;
        message = [NSString stringWithFormat:@"Subscription updated (%lu configs)", (unsigned long)count];
    }
    if (!self.view.window) return;
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:title
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil] autorelease];
    [alert show];
}

- (void)cancelRefresh {
    _refreshing = NO;
    [self buildSections];
    [_tableView reloadData];
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
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

@end
