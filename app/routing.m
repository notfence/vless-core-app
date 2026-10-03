#import "routing.h"

static NSInteger const kRoutingAddActionSheetTag = 6101;
static NSInteger const kRoutingAddTypeSheetTag = 6102;
static NSInteger const kRoutingValueAlertTag = 6103;
static NSInteger const kRoutingRuleActionSheetTagBase = 6200;

@implementation RoutingVC

- (NSString *)defaultAction {
    NSString *value = [[[NSUserDefaults standardUserDefaults] stringForKey:kDefaultsRoutingDefaultKey] lowercaseString];
    if (![value isEqualToString:@"proxy"] &&
        ![value isEqualToString:@"direct"] &&
        ![value isEqualToString:@"block"]) {
        return @"proxy";
    }
    return value;
}

- (BOOL)bypassLAN {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    return [ud objectForKey:kDefaultsRoutingBypassLANKey] == nil
        ? YES
        : [ud boolForKey:kDefaultsRoutingBypassLANKey];
}

- (void)saveRules {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:_rules forKey:kDefaultsRoutingRulesKey];
    [ud synchronize];
    VCRecordAppEvent(@"settings", @"Routing rules saved",
                     [NSString stringWithFormat:@"rules=%lu", (unsigned long)[_rules count]]);
}

- (void)enabledChanged:(UISwitch *)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender isOn] forKey:kDefaultsRoutingEnabledKey];
    [ud synchronize];
    [_tableView reloadData];
    VCRecordAppEvent(@"settings", @"Routing changed", [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (void)bypassLANChanged:(UISwitch *)sender {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:[sender isOn] forKey:kDefaultsRoutingBypassLANKey];
    [ud synchronize];
    VCRecordAppEvent(@"settings", @"LAN bypass changed", [sender isOn] ? @"enabled=1" : @"enabled=0");
}

- (void)setDefaultAction:(NSString *)action {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:action forKey:kDefaultsRoutingDefaultKey];
    [ud synchronize];
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
              withRowAnimation:UITableViewRowAnimationNone];
    VCRecordAppEvent(@"settings", @"Routing default action changed",
                     [NSString stringWithFormat:@"action=%@", action]);
}

- (NSString *)displayNameForAction:(NSString *)action {
    if ([action isEqualToString:@"direct"]) return @"Direct";
    if ([action isEqualToString:@"block"]) return @"Block";
    return @"Proxy";
}

- (NSString *)displayNameForType:(NSString *)type {
    if ([type isEqualToString:@"domain"]) return @"Domain";
    if ([type isEqualToString:@"suffix"]) return @"Domain suffix";
    if ([type isEqualToString:@"cidr"]) return @"IP / CIDR";
    return @"Port";
}

- (UIColor *)colorForAction:(NSString *)action {
    if ([action isEqualToString:@"direct"]) return VCSuccessColor();
    if ([action isEqualToString:@"block"]) return VCErrorColor();
    return VCDefaultAccentColor();
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Routing";
    self.view.backgroundColor = VCBackgroundColor();

    NSArray *saved = [[NSUserDefaults standardUserDefaults] arrayForKey:kDefaultsRoutingRulesKey];
    _rules = saved ? [[NSMutableArray alloc] initWithArray:saved copyItems:YES]
                   : [[NSMutableArray alloc] init];

    _enabledSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_enabledSwitch setOn:[[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsRoutingEnabledKey] animated:NO];
    [_enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    _bypassLANSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_bypassLANSwitch setOn:[self bypassLAN] animated:NO];
    [_bypassLANSwitch addTarget:self action:@selector(bypassLANChanged:) forControlEvents:UIControlEventValueChanged];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];

    self.navigationItem.rightBarButtonItem = self.editButtonItem;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _enabledSwitch.onTintColor = VCAccentColor();
    _bypassLANSwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    [_tableView setEditing:editing animated:animated];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 4;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0 || section == 2) return 1;
    if (section == 1) return 3;
    return (NSInteger)[_rules count] + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Routing";
    if (section == 1) return @"Default action";
    if (section == 2) return @"Local network";
    return @"Rules — first match wins";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return @"When disabled, all supported traffic uses the selected proxy.";
    }
    if (section == 2) {
        return @"Keeps private, link-local and carrier-grade NAT addresses outside the proxy.";
    }
    if (section == 3) {
        return @"Reconnect the VPN to apply routing changes.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text) return 0.01f;

    CGFloat width = MAX(1.0f, tableView.bounds.size.width - 36.0f);
    CGSize size = [text sizeWithFont:[UIFont systemFontOfSize:14.0f]
                   constrainedToSize:CGSizeMake(width, 1000.0f)
                       lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height) + 14.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text = [self tableView:tableView titleForFooterInSection:section];
    if (!text) return nil;

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
    label.textColor = VCSecondaryTextColor();
    label.text = text;
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"RoutingCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID] autorelease];
    }
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.detailTextLabel.text = nil;
    VCAppearanceApplyCell(cell);

    if (indexPath.section == 0) {
        cell.textLabel.text = @"Enable routing";
        cell.detailTextLabel.text = @"Apply ordered Proxy, Direct and Block rules";
        cell.accessoryView = _enabledSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.section == 1) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        NSString *action = [actions objectAtIndex:indexPath.row];
        cell.textLabel.text = [self displayNameForAction:action];
        cell.detailTextLabel.text = indexPath.row == 0
            ? @"Use the selected configuration"
            : (indexPath.row == 1 ? @"Connect without the proxy" : @"Reject the connection");
        cell.textLabel.textColor = [self colorForAction:action];
        cell.accessoryType = [[self defaultAction] isEqualToString:action]
            ? UITableViewCellAccessoryCheckmark
            : UITableViewCellAccessoryNone;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"Bypass local networks";
        cell.detailTextLabel.text = @"LAN, link-local and CGNAT";
        cell.accessoryView = _bypassLANSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (indexPath.row < (NSInteger)[_rules count]) {
        NSDictionary *rule = [_rules objectAtIndex:indexPath.row];
        NSString *action = [rule objectForKey:@"action"];
        NSString *type = [rule objectForKey:@"type"];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ · %@",
                               [self displayNameForAction:action],
                               [rule objectForKey:@"value"]];
        cell.detailTextLabel.text = [self displayNameForType:type];
        cell.textLabel.textColor = [self colorForAction:action];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = VCCreateDisclosureAccessoryView();
    } else {
        cell.textLabel.text = @"Add Rule";
        cell.detailTextLabel.text = @"Domain, IP/CIDR or port";
        cell.textLabel.textColor = VCDefaultAccentColor();
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    cell.backgroundColor = VCCellBackgroundColor();
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
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 3 && indexPath.row < (NSInteger)[_rules count];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    return indexPath.section == 3 && indexPath.row < (NSInteger)[_rules count];
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    (void)tableView;
    (void)sourceIndexPath;
    if (proposedDestinationIndexPath.section != 3) {
        return [NSIndexPath indexPathForRow:0 inSection:3];
    }
    NSInteger last = (NSInteger)[_rules count] - 1;
    if (proposedDestinationIndexPath.row > last) {
        return [NSIndexPath indexPathForRow:last inSection:3];
    }
    return proposedDestinationIndexPath;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView;
    NSDictionary *rule = [[_rules objectAtIndex:sourceIndexPath.row] retain];
    [_rules removeObjectAtIndex:sourceIndexPath.row];
    [_rules insertObject:rule atIndex:destinationIndexPath.row];
    [rule release];
    [self saveRules];
}

- (void)tableView:(UITableView *)tableView
commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
 forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete ||
        indexPath.section != 3 ||
        indexPath.row >= (NSInteger)[_rules count]) return;
    [_rules removeObjectAtIndex:indexPath.row];
    [self saveRules];
    [tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath]
                     withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)showRuleTypeSheet {
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Match"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"Exact Domain", @"Domain Suffix", @"IP or CIDR", @"Port or Range", nil] autorelease];
    sheet.tag = kRoutingAddTypeSheetTag;
    [sheet showInView:self.view];
}

- (void)showRuleValuePrompt {
    NSString *title = [self displayNameForType:_pendingType];
    NSString *message = nil;
    if ([_pendingType isEqualToString:@"domain"]) message = @"Example: api.example.com";
    else if ([_pendingType isEqualToString:@"suffix"]) message = @"Example: example.com";
    else if ([_pendingType isEqualToString:@"cidr"]) message = @"Example: 203.0.113.0/24";
    else message = @"Example: 80 or 8000-8999";

    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:title
                                                     message:message
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Add", nil] autorelease];
    alert.tag = kRoutingValueAlertTag;
    alert.alertViewStyle = UIAlertViewStylePlainTextInput;
    [[alert textFieldAtIndex:0] setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [[alert textFieldAtIndex:0] setAutocorrectionType:UITextAutocorrectionTypeNo];
    [alert show];
}

- (NSString *)normalizedRuleValue:(NSString *)input type:(NSString *)type {
    NSString *value = [[[input stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString] copy];
    if ([value length] == 0 || [value length] > 128 ||
        [value rangeOfCharacterFromSet:
         [NSCharacterSet characterSetWithCharactersInString:@";,\r\n\t "]].location != NSNotFound) {
        [value release];
        return nil;
    }

    BOOL valid = NO;
    if ([type isEqualToString:@"domain"] || [type isEqualToString:@"suffix"]) {
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:
                                @"abcdefghijklmnopqrstuvwxyz0123456789-_."] invertedSet];
        valid = [value rangeOfCharacterFromSet:bad].location == NSNotFound &&
                ![value hasPrefix:@"."] && ![value hasSuffix:@"."] &&
                [value rangeOfString:@".."].location == NSNotFound;
    } else if ([type isEqualToString:@"cidr"]) {
        NSArray *parts = [value componentsSeparatedByString:@"/"];
        if ([parts count] == 1 || [parts count] == 2) {
            NSString *address = [parts objectAtIndex:0];
            unsigned char bytes[16];
            BOOL is4 = inet_pton(AF_INET, [address UTF8String], bytes) == 1;
            BOOL is6 = inet_pton(AF_INET6, [address UTF8String], bytes) == 1;
            valid = is4 || is6;
            if (valid && [parts count] == 2) {
                NSString *prefixText = [parts objectAtIndex:1];
                NSInteger prefix = [prefixText integerValue];
                valid = [prefixText length] > 0 &&
                        prefix >= 0 && prefix <= (is4 ? 32 : 128) &&
                        [[NSString stringWithFormat:@"%ld", (long)prefix] isEqualToString:prefixText];
            }
        }
    } else if ([type isEqualToString:@"port"]) {
        NSArray *parts = [value componentsSeparatedByString:@"-"];
        if ([parts count] == 1 || [parts count] == 2) {
            NSString *firstText = [parts objectAtIndex:0];
            NSString *lastText = [parts count] == 2 ? [parts objectAtIndex:1] : firstText;
            NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
            if ([firstText length] > 0 && [lastText length] > 0 &&
                [firstText rangeOfCharacterFromSet:nonDigits].location == NSNotFound &&
                [lastText rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
                NSInteger first = [firstText integerValue];
                NSInteger last = [lastText integerValue];
                valid = first > 0 && first <= 65535 &&
                        last >= first && last <= 65535;
            }
        }
    }

    if (!valid) {
        [value release];
        return nil;
    }
    return [value autorelease];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        [self setDefaultAction:[actions objectAtIndex:indexPath.row]];
        return;
    }
    if (indexPath.section != 3) return;

    if (indexPath.row == (NSInteger)[_rules count]) {
        if ([_rules count] >= 24) {
            UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Rule Limit"
                                                             message:@"A maximum of 24 routing rules is supported."
                                                            delegate:nil
                                                   cancelButtonTitle:@"OK"
                                                   otherButtonTitles:nil] autorelease];
            [alert show];
            return;
        }
        UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Action"
                                                             delegate:self
                                                    cancelButtonTitle:@"Cancel"
                                               destructiveButtonTitle:nil
                                                    otherButtonTitles:@"Proxy", @"Direct", @"Block", nil] autorelease];
        sheet.tag = kRoutingAddActionSheetTag;
        [sheet showInView:self.view];
        return;
    }

    NSDictionary *rule = [_rules objectAtIndex:indexPath.row];
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:
                             [NSString stringWithFormat:@"%@ · %@",
                              [self displayNameForType:[rule objectForKey:@"type"]],
                              [rule objectForKey:@"value"]]
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:@"Delete"
                                                otherButtonTitles:@"Use Proxy", @"Use Direct", @"Use Block", nil] autorelease];
    sheet.tag = kRoutingRuleActionSheetTagBase + indexPath.row;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) return;

    if (actionSheet.tag == kRoutingAddActionSheetTag) {
        NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)[actions count]) return;
        [_pendingAction release];
        _pendingAction = [[actions objectAtIndex:buttonIndex] copy];
        [self showRuleTypeSheet];
        return;
    }
    if (actionSheet.tag == kRoutingAddTypeSheetTag) {
        NSArray *types = [NSArray arrayWithObjects:@"domain", @"suffix", @"cidr", @"port", nil];
        if (buttonIndex < 0 || buttonIndex >= (NSInteger)[types count]) return;
        [_pendingType release];
        _pendingType = [[types objectAtIndex:buttonIndex] copy];
        [self showRuleValuePrompt];
        return;
    }
    if (actionSheet.tag >= kRoutingRuleActionSheetTagBase) {
        NSInteger index = actionSheet.tag - kRoutingRuleActionSheetTagBase;
        if (index < 0 || index >= (NSInteger)[_rules count]) return;
        if (buttonIndex == actionSheet.destructiveButtonIndex) {
            [_rules removeObjectAtIndex:index];
        } else {
            NSArray *actions = [NSArray arrayWithObjects:@"proxy", @"direct", @"block", nil];
            NSInteger actionIndex = buttonIndex - 1;
            if (actionIndex < 0 || actionIndex >= (NSInteger)[actions count]) return;
            NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:
                                             [_rules objectAtIndex:index]];
            [updated setObject:[actions objectAtIndex:actionIndex] forKey:@"action"];
            [_rules replaceObjectAtIndex:index withObject:updated];
        }
        [self saveRules];
        [_tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag != kRoutingValueAlertTag || buttonIndex == alertView.cancelButtonIndex) return;
    NSString *value = [self normalizedRuleValue:[[alertView textFieldAtIndex:0] text]
                                           type:_pendingType];
    if (!value) {
        UIAlertView *error = [[[UIAlertView alloc] initWithTitle:@"Invalid Rule"
                                                         message:@"Check the value and try again."
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [error show];
        return;
    }
    NSDictionary *rule = [NSDictionary dictionaryWithObjectsAndKeys:
                          (_pendingAction ? _pendingAction : @"proxy"), @"action",
                          (_pendingType ? _pendingType : @"domain"), @"type",
                          value, @"value",
                          nil];
    [_rules addObject:rule];
    [self saveRules];
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:3]
              withRowAnimation:UITableViewRowAnimationAutomatic];
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
    [_tableView release];
    [_enabledSwitch release];
    [_bypassLANSwitch release];
    [_rules release];
    [_pendingAction release];
    [_pendingType release];
    [super dealloc];
}

@end
