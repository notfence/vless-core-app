#import "subscription_info.h"
#import "flag_label.h"
#import "settings_icons.h"

static CGRect VCSubscriptionMenuFrame(CGRect bounds, CGRect anchor) {
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) ||
        bounds.size.width<=20 || bounds.size.height<=20) return CGRectZero;
    CGFloat width=MIN(224.0f,bounds.size.width-20.0f),height=MIN(192.0f,bounds.size.height-20.0f);
    CGFloat right=CGRectGetMaxX(bounds)-10.0f,bottom=CGRectGetMaxY(bounds)-10.0f;
    if (!isfinite(anchor.origin.x) || !isfinite(anchor.origin.y) || !isfinite(anchor.size.width) || !isfinite(anchor.size.height)) anchor=CGRectMake(right,bounds.origin.y+10,0,0);
    CGFloat x=MAX(bounds.origin.x+10.0f,MIN(right-width,CGRectGetMaxX(anchor)-width));
    CGFloat y=CGRectGetMaxY(anchor)+8.0f;
    if (y+height>bottom) y=anchor.origin.y-height-8.0f;
    y=MAX(bounds.origin.y+10.0f,MIN(bottom-height,y));
    return CGRectMake(floorf(x),floorf(y),width,height);
}

static UIImage *VCSubscriptionMenuIcon(VCSubscriptionMenuAction action) {
    UIColor *color=action==VCSubscriptionMenuDelete ? VCErrorColor() : VCPrimaryTextColor();
    if (action==VCSubscriptionMenuInformation) return TintImageWithColor(VCSettingsIconImage(VCSettingsIconAbout),color);
    if (action==VCSubscriptionMenuUpdate) return LoadBundledIconTinted(@"icon-refresh",22,color);
    if (action==VCSubscriptionMenuDelete) return LoadBundledIconTinted(@"icon-trash",22,color);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(24,24),NO,0);
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    if (ctx) {
        CGContextSetStrokeColorWithColor(ctx,color.CGColor);
        CGContextSetLineWidth(ctx,1.8f); CGContextSetLineCap(ctx,kCGLineCapRound); CGContextSetLineJoin(ctx,kCGLineJoinRound);
        CGContextMoveToPoint(ctx,4,20); CGContextAddLineToPoint(ctx,5,14);
        CGContextAddLineToPoint(ctx,16,3); CGContextAddLineToPoint(ctx,21,8);
        CGContextAddLineToPoint(ctx,10,19); CGContextClosePath(ctx);
        CGContextMoveToPoint(ctx,13,6); CGContextAddLineToPoint(ctx,18,11);
        CGContextStrokePath(ctx);
    }
    UIImage *image=UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return image;
}

@interface VCSubscriptionMenu ()
- (void)finishDismissalWithAction:(NSInteger)action;
- (void)dismissWithAction:(NSInteger)action;
@end

@implementation VCSubscriptionMenu
@synthesize subscription=_subscription,anchor=_anchor;
- (id)initWithSubscription:(NSDictionary *)subscription anchor:(CGRect)anchor delegate:(id<VCSubscriptionMenuDelegate>)delegate {
    if ((self=[super initWithFrame:CGRectZero])) {
        _subscription=[subscription copy]; _anchor=anchor; _delegate=delegate;
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.accessibilityViewIsModal=YES;
        UIButton *outside=[UIButton buttonWithType:UIButtonTypeCustom]; outside.tag=1;
        outside.accessibilityLabel=@"Close subscription menu";
        [outside addTarget:self action:@selector(cancelMenu) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:outside];
        _panel=[[UIView alloc] initWithFrame:CGRectZero];
        _panel.layer.shadowColor=[UIColor blackColor].CGColor; _panel.layer.shadowOpacity=0.28f;
        _panel.layer.shadowRadius=12; _panel.layer.shadowOffset=CGSizeMake(0,4);
        [self addSubview:_panel];
        UIView *card=[[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        card.tag=2; card.backgroundColor=VCCellBackgroundColor(); card.layer.cornerRadius=12; card.clipsToBounds=YES;
        [_panel addSubview:card];
        NSArray *titles=@[@"Edit",@"Information",@"Update",@"Delete"];
        for (NSInteger i=0;i<4;i++) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom]; button.tag=10+i;
            [button setTitle:[titles objectAtIndex:i] forState:UIControlStateNormal];
            [button setTitleColor:i==VCSubscriptionMenuDelete ? VCErrorColor() : VCPrimaryTextColor() forState:UIControlStateNormal];
            button.titleLabel.font=[UIFont systemFontOfSize:17]; button.titleLabel.textAlignment=NSTextAlignmentLeft;
            button.contentHorizontalAlignment=UIControlContentHorizontalAlignmentLeft;
            button.contentEdgeInsets=UIEdgeInsetsMake(0,16,0,50); button.showsTouchWhenHighlighted=NO;
            [button addTarget:self action:@selector(actionPressed:) forControlEvents:UIControlEventTouchUpInside];
            [button addTarget:self action:@selector(highlightAction:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
            [button addTarget:self action:@selector(unhighlightAction:) forControlEvents:UIControlEventTouchCancel | UIControlEventTouchDragExit | UIControlEventTouchUpInside];
            UIImageView *icon=[[[UIImageView alloc] initWithImage:VCSubscriptionMenuIcon((VCSubscriptionMenuAction)i)] autorelease];
            icon.tag=20; icon.contentMode=UIViewContentModeScaleAspectFit; [button addSubview:icon];
            [card addSubview:button];
            if (i) { UIView *line=[[[UIView alloc] initWithFrame:CGRectZero] autorelease]; line.tag=30+i; line.backgroundColor=VCSeparatorColor(); [card addSubview:line]; }
        }
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissForEnvironmentChange:) name:UIApplicationWillResignActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(dismissForEnvironmentChange:) name:UIApplicationWillChangeStatusBarOrientationNotification object:nil];
    }
    return self;
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_subscription release]; [_panel release]; [super dealloc]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    [self viewWithTag:1].frame=self.bounds;
    CGRect frame=VCSubscriptionMenuFrame(self.bounds,_anchor);
    _panel.bounds=CGRectMake(0,0,frame.size.width,frame.size.height);
    _panel.center=CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame));
    UIView *card=[_panel viewWithTag:2]; card.frame=_panel.bounds;
    CGFloat height=card.bounds.size.height/4.0f,width=card.bounds.size.width;
    CGFloat line=1.0f/[UIScreen mainScreen].scale;
    for (NSInteger i=0;i<4;i++) {
        UIView *button=[card viewWithTag:10+i]; button.frame=CGRectMake(0,i*height,width,height);
        [button viewWithTag:20].frame=CGRectMake(width-40,(height-24)/2,24,24);
        if (i) [card viewWithTag:30+i].frame=CGRectMake(0,i*height,width,line);
    }
    _panel.layer.shadowPath=[UIBezierPath bezierPathWithRoundedRect:_panel.bounds cornerRadius:12].CGPath;
}
- (void)showInView:(UIView *)view {
    self.frame=view.bounds; [view addSubview:self]; [self setNeedsLayout]; [self layoutIfNeeded];
    _panel.alpha=0; _panel.transform=CGAffineTransformMakeScale(0.96f,0.96f);
    [UIView animateWithDuration:0.16 animations:^{ _panel.alpha=1; _panel.transform=CGAffineTransformIdentity; } completion:^(BOOL finished) {
        (void)finished;
        if (!_closing && !_dismissed) UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,[_panel viewWithTag:10]);
    }];
}
- (void)highlightAction:(UIButton *)button { button.backgroundColor=VCSelectedCellColor(); }
- (void)unhighlightAction:(UIButton *)button { button.backgroundColor=[UIColor clearColor]; }
- (void)actionPressed:(UIButton *)button { [self dismissWithAction:button.tag-10]; }
- (void)cancelMenu { [self dismissWithAction:-1]; }
- (BOOL)accessibilityPerformEscape { [self cancelMenu]; return YES; }
- (void)dismissForEnvironmentChange:(NSNotification *)notification {
    (void)notification; _delegate=nil;
    [self finishDismissalWithAction:-1];
}
- (void)dismissWithAction:(NSInteger)action {
    if (_closing || _dismissed) return;
    _closing=YES; self.userInteractionEnabled=NO;
    [UIView animateWithDuration:0.12 animations:^{ _panel.alpha=0; } completion:^(BOOL finished) {
        (void)finished; [self finishDismissalWithAction:action];
    }];
}
- (void)finishDismissalWithAction:(NSInteger)action {
    if (_dismissed) return;
    [self retain]; _dismissed=YES;
    [self removeFromSuperview];
    if (action>=VCSubscriptionMenuEdit && action<=VCSubscriptionMenuDelete) [_delegate subscriptionMenu:self selectedAction:(VCSubscriptionMenuAction)action];
    else UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification,nil);
    [self release];
}
@end

@implementation VCSubscriptionActionSheet
@synthesize subscription=_subscription;
- (id)initWithSubscription:(NSDictionary *)subscription delegate:(id<UIActionSheetDelegate>)delegate {
    if ((self=[super initWithTitle:@"Delete the subscription and all of its configurations?" delegate:delegate cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil])) {
        _subscription=[subscription copy];
        self.destructiveButtonIndex=[self addButtonWithTitle:@"Delete"];
        self.cancelButtonIndex=[self addButtonWithTitle:@"Cancel"];
    }
    return self;
}
- (void)dealloc { [_subscription release]; [super dealloc]; }
@end

static CGRect VCSubscriptionInputFrame(CGRect bounds, CGFloat textLeft) {
    if (!isfinite(textLeft) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) || bounds.size.width<=0 || bounds.size.height<=0) return CGRectZero;
    CGFloat inset=MAX(0.0f,MIN(bounds.size.width/2.0f,textLeft-bounds.origin.x));
    return CGRectMake(bounds.origin.x+inset,bounds.origin.y,MAX(0.0f,bounds.size.width-2*inset),bounds.size.height);
}

@interface VCSubscriptionInputCell : UITableViewCell {
    UITextField *_inputField;
}
- (void)setInputField:(UITextField *)field;
@end

@implementation VCSubscriptionInputCell
- (void)setInputField:(UITextField *)field {
    if (_inputField==field) return;
    [_inputField removeFromSuperview]; [_inputField release]; _inputField=[field retain];
    [self.contentView addSubview:field];
    self.isAccessibilityElement=NO; self.textLabel.isAccessibilityElement=NO;
    self.textLabel.text=field.placeholder; self.textLabel.font=field.font;
    self.textLabel.textColor=[UIColor clearColor];
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect title=[self.textLabel convertRect:self.textLabel.bounds toView:self.contentView];
    _inputField.frame=VCSubscriptionInputFrame(self.contentView.bounds,title.origin.x);
    self.textLabel.textColor=[UIColor clearColor];
}
- (void)dealloc { [_inputField release]; [super dealloc]; }
@end

@implementation SubscriptionEditVC
@synthesize subscription=_subscription;
- (id)initWithSubscription:(NSDictionary *)subscription stealthMode:(BOOL)stealth delegate:(id<SubscriptionEditVCDelegate>)delegate {
    if ((self=[super initWithStyle:UITableViewStyleGrouped])) {
        _subscription=[subscription copy]; _stealthMode=stealth; _delegate=delegate;
        _agentMode=[subscription objectForKey:kSubscriptionUserAgentKey] ? 2 : ([VCSubscriptionUserAgent(subscription,AppUserAgent()) isEqual:kHappSubscriptionUserAgent] ? 1 : 0);
    }
    return self;
}
- (void)dealloc { [_subscription release]; [_nameField release]; [_linkField release]; [_agentField release]; [super dealloc]; }
- (UITextField *)newFieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field=[[UITextField alloc] initWithFrame:CGRectZero];
    field.text=[text isKindOfClass:[NSString class]] ? text : @""; field.placeholder=placeholder;
    field.font=[UIFont boldSystemFontOfSize:17]; field.textColor=VCPrimaryTextColor();
    if ([field respondsToSelector:@selector(setAttributedPlaceholder:)]) {
        field.attributedPlaceholder=[[[NSAttributedString alloc] initWithString:placeholder
            attributes:@{NSForegroundColorAttributeName:VCSecondaryTextColor(),NSFontAttributeName:field.font}] autorelease];
    }
    field.autocapitalizationType=UITextAutocapitalizationTypeNone; field.autocorrectionType=UITextAutocorrectionTypeNo;
    field.clearButtonMode=UITextFieldViewModeWhileEditing; field.contentVerticalAlignment=UIControlContentVerticalAlignmentCenter;
    field.returnKeyType=UIReturnKeyDone; field.delegate=self;
    return field;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Edit Subscription";
    _nameField=[self newFieldWithText:[_subscription objectForKey:@"name"] placeholder:@"Subscription name"];
    _linkField=[self newFieldWithText:[_subscription objectForKey:@"url"] placeholder:@"Subscription link"];
    _linkField.keyboardType=UIKeyboardTypeURL;
    _linkField.secureTextEntry=_stealthMode || SubscriptionDictionaryIsHappEncrypted(_subscription);
    _agentField=[self newFieldWithText:[_subscription objectForKey:kSubscriptionUserAgentKey] placeholder:@"Custom User-Agent"];
    _agentField.keyboardType=UIKeyboardTypeASCIICapable;
    self.navigationItem.leftBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"Cancel" style:UIBarButtonItemStyleBordered target:self action:@selector(cancelPressed)] autorelease];
    self.navigationItem.rightBarButtonItem=[[[UIBarButtonItem alloc] initWithTitle:@"Save" style:UIBarButtonItemStyleDone target:self action:@selector(savePressed)] autorelease];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; self.view.backgroundColor=VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar); VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(self.tableView); [self.tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(self.tableView);
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section==2 ? 4 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return [@[@"Name",@"Subscription link",@"User-Agent"] objectAtIndex:section]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section==1) return @"Changing the link clears downloaded configurations.";
    if (section==2) return @"Default: vless-core-app own user-agent.";
    return nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    NSString *text=[self tableView:tableView titleForFooterInSection:section];
    if (![text length]) return 0.01f;
    CGFloat width=MAX(1.0f,tableView.bounds.size.width-36.0f);
    if ([tableView respondsToSelector:@selector(readableContentGuide)] && tableView.cellLayoutMarginsFollowReadableWidth) {
        CGFloat readableWidth=tableView.readableContentGuide.layoutFrame.size.width;
        if (readableWidth>0) width=MAX(1.0f,MIN(width,readableWidth));
    }
    CGSize size=[text sizeWithFont:[UIFont systemFontOfSize:14] constrainedToSize:CGSizeMake(width,1000) lineBreakMode:NSLineBreakByWordWrapping];
    return ceilf(size.height)+14.0f;
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *text=[self tableView:tableView titleForFooterInSection:section];
    if (![text length]) return nil;
    CGFloat height=[self tableView:tableView heightForFooterInSection:section];
    Class nativeClass=[tableView respondsToSelector:@selector(readableContentGuide)] ? NSClassFromString(@"UITableViewHeaderFooterView") : Nil;
    if (nativeClass) {
        UITableViewHeaderFooterView *footer=[[[nativeClass alloc] initWithReuseIdentifier:nil] autorelease];
        footer.frame=CGRectMake(0,0,tableView.bounds.size.width,height);
        footer.backgroundView=[[[UIView alloc] initWithFrame:footer.bounds] autorelease];
        footer.backgroundView.backgroundColor=[UIColor clearColor];
        footer.contentView.backgroundColor=[UIColor clearColor];
        footer.textLabel.font=[UIFont systemFontOfSize:14]; footer.textLabel.numberOfLines=0;
        footer.textLabel.lineBreakMode=NSLineBreakByWordWrapping; footer.textLabel.text=text;
        VCAppearanceApplyHeaderView(footer);
        return footer;
    }
    UIView *footer=[[[UIView alloc] initWithFrame:CGRectMake(0,0,tableView.bounds.size.width,height)] autorelease];
    footer.backgroundColor=[UIColor clearColor];
    UILabel *label=[[[UILabel alloc] initWithFrame:CGRectMake(18,4,MAX(1.0f,tableView.bounds.size.width-36.0f),height-8)] autorelease];
    label.autoresizingMask=UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor=[UIColor clearColor]; label.font=[UIFont systemFontOfSize:14];
    label.numberOfLines=0; label.lineBreakMode=NSLineBreakByWordWrapping; label.text=text;
    [footer addSubview:label]; VCAppearanceApplyHeaderView(footer);
    return footer;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)path { (void)tableView; (void)path; return 44; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    BOOL input=path.section<2 || path.row==3;
    NSString *identifier=input ? [NSString stringWithFormat:@"SubscriptionField-%ld",(long)path.section] : @"SubscriptionAgent";
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        Class cellClass=input ? [VCSubscriptionInputCell class] : [UITableViewCell class];
        cell=[[[cellClass alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    }
    VCAppearanceApplyCell(cell); cell.accessoryType=UITableViewCellAccessoryNone;
    cell.selectionStyle=input || _saving ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    if (input) {
        UITextField *field=path.section==0 ? _nameField : (path.section==1 ? _linkField : _agentField);
        field.enabled=!_saving && (path.section!=2 || _agentMode==2);
        field.textColor=field.enabled ? VCPrimaryTextColor() : VCSecondaryTextColor();
        [(VCSubscriptionInputCell *)cell setInputField:field];
    } else {
        cell.textLabel.font=[UIFont boldSystemFontOfSize:17];
        cell.textLabel.text=[@[@"Default",@"HAPP",@"Custom"] objectAtIndex:path.row];
        cell.accessoryType=path.row==_agentMode ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView; (void)path; VCAppearanceApplyCell(cell);
    if ([cell isKindOfClass:[VCSubscriptionInputCell class]]) cell.textLabel.textColor=[UIColor clearColor];
}
- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section { (void)section; VCAppearanceApplyHeaderView(view); VCAppearanceScheduleVisibleTableHeadersRefresh(tableView); }
- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)section;
    if ([view isKindOfClass:NSClassFromString(@"UITableViewHeaderFooterView")]) {
        ((UITableViewHeaderFooterView *)view).textLabel.font=[UIFont systemFontOfSize:14];
    }
    VCAppearanceApplyHeaderView(view); VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (_saving || path.section!=2 || path.row>2) return;
    [_agentField resignFirstResponder]; _agentMode=path.row;
    for (NSInteger row=0;row<3;row++) {
        UITableViewCell *cell=[tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:2]];
        cell.accessoryType=row==_agentMode ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    }
    _agentField.enabled=_agentMode==2;
    _agentField.textColor=_agentField.enabled ? VCPrimaryTextColor() : VCSecondaryTextColor();
}
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }
- (void)cancelPressed { if (_saving) return; [self.view endEditing:YES]; [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)savePressed {
    if (_saving) return;
    [self.view endEditing:YES]; NSString *error=nil;
    NSString *agent=_agentMode==0 ? nil : (_agentMode==1 ? kHappSubscriptionUserAgent : _agentField.text);
    NSDictionary *updated=[VCProfiles() subscriptionByEditingSource:_subscription name:_nameField.text link:_linkField.text userAgent:agent error:&error];
    if (!updated) { [self finishSavingWithSubscription:nil errorText:error]; return; }
    _saving=YES; self.navigationItem.rightBarButtonItem.enabled=NO; self.navigationItem.leftBarButtonItem.enabled=NO;
    [self.tableView reloadData]; [_delegate subscriptionEditVC:self requestedSave:updated];
}
- (void)finishSavingWithSubscription:(NSDictionary *)subscription errorText:(NSString *)error {
    _saving=NO; self.navigationItem.rightBarButtonItem.enabled=YES; self.navigationItem.leftBarButtonItem.enabled=YES;
    if (subscription) {
        [self dismissViewControllerAnimated:YES completion:^{ [_delegate subscriptionEditVC:self didSaveSubscription:subscription]; }];
        return;
    }
    [self.tableView reloadData];
    UIAlertView *alert=[[[UIAlertView alloc] initWithTitle:@"Subscription was not saved" message:error ?: @"Please check the subscription settings and try again." delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease]; [alert show];
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { return IsPadDevice() ? orientation!=UIInterfaceOrientationPortraitUpsideDown : orientation==UIInterfaceOrientationPortrait; }
- (BOOL)shouldAutorotate { return IsPadDevice(); }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait; }
@end

@implementation SubscriptionInfoVC

- (id)initWithSubscription:(NSDictionary *)subscription
                     index:(NSInteger)index
               stealthMode:(BOOL)stealthMode {
    self = [super init];
    if (!self) return nil;

    _subscription = [subscription copy];
    _subscriptionIndex = index;
    _stealthMode = stealthMode;
    return self;
}

- (void)dealloc {
    [_tableView release];
    [_subscription release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    NSMutableDictionary *row = [NSMutableDictionary dictionary];
    [row setObject:(title ? title : @"") forKey:@"title"];
    if ([detail isKindOfClass:[NSString class]] && [detail length] > 0) {
        [row setObject:detail forKey:@"detail"];
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
    [generalRows addObject:[self rowWithTitle:@"Name" detail:name]];

    NSString *url = [_subscription objectForKey:@"url"];
    if (![url isKindOfClass:[NSString class]]) url = @"";
    BOOL encryptedHappSubscription = SubscriptionDictionaryIsHappEncrypted(_subscription);
    NSString *shownURL = (_stealthMode || encryptedHappSubscription) ? kHiddenLinkText : url;
    if ([shownURL length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Subscription Link" detail:shownURL]];
    }
    [generalRows addObject:[self rowWithTitle:@"User-Agent" detail:VCSubscriptionUserAgent(_subscription,AppUserAgent()) ?: @"Invalid User-Agent"]];

    NSDictionary *metadata = [_subscription objectForKey:kSubscriptionMetadataKey];
    if (![metadata isKindOfClass:[NSDictionary class]]) metadata = nil;
    NSString *description = [metadata objectForKey:kSubscriptionDescriptionKey];
    if ([description isKindOfClass:[NSString class]] && [description length] > 0) {
        [generalRows addObject:[self rowWithTitle:@"Description" detail:description]];
    }
    [newSections addObject:[self sectionWithTitle:@"Subscription" rows:generalRows]];

    NSArray *items = [_subscription objectForKey:@"items"];
    NSUInteger itemCount = [items isKindOfClass:[NSArray class]] ? [items count] : 0;
    [usageRows addObject:[self rowWithTitle:@"Configurations"
                                    detail:[NSString stringWithFormat:@"%lu", (unsigned long)itemCount]]];

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
            [usageRows addObject:[self rowWithTitle:@"Traffic Used" detail:[self formattedBytes:used]]];
        }
        if (hasUpload) {
            [usageRows addObject:[self rowWithTitle:@"Uploaded" detail:[self formattedBytes:upload]]];
        }
        if (hasDownload) {
            [usageRows addObject:[self rowWithTitle:@"Downloaded" detail:[self formattedBytes:download]]];
        }
        if ([totalNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long total = [totalNumber unsignedLongLongValue];
            NSString *limit = (total == 0) ? @"Unlimited" : [self formattedBytes:total];
            [usageRows addObject:[self rowWithTitle:@"Traffic Limit" detail:limit]];
        }
        if ([expireNumber isKindOfClass:[NSNumber class]]) {
            unsigned long long expire = [expireNumber unsignedLongLongValue];
            NSString *expiry = (expire == 0) ? @"No expiration" : [self formattedTimestamp:expire includeTime:NO];
            if ([expiry length] > 0) {
                [usageRows addObject:[self rowWithTitle:@"Expires" detail:expiry]];
            }
        }
    }

    NSNumber *refillNumber = [metadata objectForKey:kSubscriptionRefillDateKey];
    if ([refillNumber isKindOfClass:[NSNumber class]]) {
        NSString *refill = [self formattedTimestamp:[refillNumber unsignedLongLongValue] includeTime:NO];
        if ([refill length] > 0) {
            [usageRows addObject:[self rowWithTitle:@"Traffic Refill" detail:refill]];
        }
    }
    [newSections addObject:[self sectionWithTitle:@"Usage" rows:usageRows]];

    NSString *webPageURL = [metadata objectForKey:kSubscriptionWebPageURLKey];
    if ([webPageURL isKindOfClass:[NSString class]] && [webPageURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Web Page"
                                            detail:(_stealthMode ? kHiddenLinkText : webPageURL)]];
    }
    NSString *supportURL = [metadata objectForKey:kSubscriptionSupportURLKey];
    if ([supportURL isKindOfClass:[NSString class]] && [supportURL length] > 0) {
        [providerRows addObject:[self rowWithTitle:@"Support"
                                            detail:(_stealthMode ? kHiddenLinkText : supportURL)]];
    }
    NSNumber *intervalNumber = [metadata objectForKey:kSubscriptionUpdateIntervalKey];
    if ([intervalNumber isKindOfClass:[NSNumber class]]) {
        unsigned long long hours = [intervalNumber unsignedLongLongValue];
        NSString *interval = [NSString stringWithFormat:@"%llu hour%@", hours, (hours == 1 ? @"" : @"s")];
        [providerRows addObject:[self rowWithTitle:@"Suggested Update Interval" detail:interval]];
    }
    NSNumber *lastUpdatedNumber = [metadata objectForKey:kSubscriptionLastUpdatedKey];
    if ([lastUpdatedNumber isKindOfClass:[NSNumber class]]) {
        NSString *lastUpdated = [self formattedTimestamp:[lastUpdatedNumber unsignedLongLongValue] includeTime:YES];
        if ([lastUpdated length] > 0) {
            [providerRows addObject:[self rowWithTitle:@"Last Updated" detail:lastUpdated]];
        }
    }
    [providerRows addObject:[self rowWithTitle:@"Source"
                                       detail:(encryptedHappSubscription
                                                   ? @"HAPP (encrypted)"
                                                   : (VCIncyIsLink(url) ? @"INCY" : (SubscriptionDictionaryUsesHappHeaders(_subscription) ? @"HAPP" : @"URL")))]];
    [newSections addObject:[self sectionWithTitle:@"Provider" rows:providerRows]];

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
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [[row objectForKey:@"title"] isEqualToString:@"Name"]
        ? VCFlagTextSize(detail,[UIFont systemFontOfSize:13.0f],CGSizeMake(width,1000.0f),NSLineBreakByWordWrapping)
        : [detail sizeWithFont:[UIFont systemFontOfSize:13.0f] constrainedToSize:CGSizeMake(width,1000.0f) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    BOOL nameRow=[[row objectForKey:@"title"] isEqualToString:@"Name"];
    NSString *reuseID = nameRow ? @"SubscriptionNameCell" : @"SubscriptionInfoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        Class cellClass=nameRow ? [VCFlagTableCell class] : [UITableViewCell class];
        cell = [[[cellClass alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID] autorelease];
    }

    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);

    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
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
