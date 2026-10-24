#import "main_screen.h"
#import "connection_button.h"

@implementation MainVC

- (void)viewDidLoad {
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActiveNotification:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    [self loadData];
    _pingDisplayByURI = [[NSMutableDictionary alloc] init];
    _standalonePingCancellationsByURI = [[NSMutableDictionary alloc] init];
    _subscriptionPingPendingByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingOperationsByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingPreviousDisplayByIdentifier = [[NSMutableDictionary alloc] init];
    _subscriptionPingTokenByIdentifier = [[NSMutableDictionary alloc] init];
    _pingQueue = [[NSOperationQueue alloc] init];
    _pingQueue.maxConcurrentOperationCount = 4;

    CGRect b = self.view.bounds;
    BOOL collapsiblePhoneLayout = !IsPadDevice();
    CGFloat topInset = VCMainStatusBarInset();
    CGFloat listY = topInset + (collapsiblePhoneLayout ? kVCMainCompactContentStartY : kVCMainContentStartY) +
                    kVCMainSectionHeaderHeight;
    UIColor *bg = VCBackgroundColor();
    self.view.backgroundColor = bg;

    CGFloat topButtonY = topInset + 4.0f;
    CGFloat topButtonWidth = 34.0f;
    CGFloat topButtonHeight = 40.0f;
    CGFloat right = b.size.width - 9.0f;

    CGFloat settingsX = right - topButtonWidth;
    CGFloat refreshX = settingsX - topButtonWidth;
    CGFloat terminalX = refreshX - topButtonWidth;
    CGFloat plusX = terminalX - topButtonWidth;
    CGFloat clearLogsY = topInset + 44.0f;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, topInset + 6.0f, plusX - 20, 28)];
    _titleLabel.text = @"vless-core";
    _titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    _titleLabel.textColor = VCPrimaryTextColor();
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_titleLabel];

    CGFloat updateX = CGRectGetMinX(_titleLabel.frame) +
                      ceilf([_titleLabel.text sizeWithFont:_titleLabel.font].width) + 4.0f;
    _updateBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _updateBtn.frame = CGRectMake(updateX, topInset + 6.0f, 28.0f, 28.0f);
    _updateBtn.hidden = YES;
    [_updateBtn addTarget:self action:@selector(updateIndicatorPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_updateBtn];
    [self.view addSubview:_updateBtn];

    _plusBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plusBtn.frame = CGRectMake(plusX, topButtonY, topButtonWidth, topButtonHeight);
    _plusBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_plusBtn addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self.view addSubview:_plusBtn];

    _terminalBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _terminalBtn.frame = CGRectMake(terminalX, topButtonY, topButtonWidth, topButtonHeight);
    _terminalBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_terminalBtn addTarget:self action:@selector(terminalPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self.view addSubview:_terminalBtn];

    _clearLogsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _clearLogsBtn.frame = CGRectMake(settingsX + 3.0f, clearLogsY, 28.0f, 28.0f);
    _clearLogsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _clearLogsBtn.hidden = YES;
    [_clearLogsBtn addTarget:self action:@selector(clearLogsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self.view addSubview:_clearLogsBtn];

    _refreshBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _refreshBtn.frame = CGRectMake(refreshX, topButtonY, topButtonWidth, topButtonHeight);
    _refreshBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_refreshBtn addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self.view addSubview:_refreshBtn];

    _settingsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _settingsBtn.frame = CGRectMake(settingsX, topButtonY, topButtonWidth, topButtonHeight);
    _settingsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_settingsBtn addTarget:self action:@selector(settingsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self.view addSubview:_settingsBtn];

    CGFloat btnSize = 112.0f;
    _connectGlowView = [[UIImageView alloc] initWithFrame:CGRectMake((b.size.width - btnSize) * 0.5f - 18.0f,
                                                                     topInset + 36.0f,
                                                                     btnSize + 36.0f, btnSize + 36.0f)];
    _connectGlowView.userInteractionEnabled = NO;
    [self.view addSubview:_connectGlowView];

    _compactConnectGlowView = [[UIView alloc] initWithFrame:CGRectMake((b.size.width - btnSize) * 0.5f,
                                                                         topInset + 54.0f, btnSize, btnSize)];
    _compactConnectGlowView.userInteractionEnabled = NO;
    _compactConnectGlowView.layer.shadowOffset = CGSizeZero;
    _compactConnectGlowView.layer.shadowRadius = 11.0f;
    _compactConnectGlowView.layer.shadowOpacity = 0.72f;
    _compactConnectGlowView.alpha = 0.0f;
    [self.view addSubview:_compactConnectGlowView];

    _connectBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _connectBtn.frame = CGRectMake((b.size.width - btnSize) * 0.5f, topInset + 54.0f, btnSize, btnSize);
    _connectBtn.layer.cornerRadius = btnSize * 0.5f;
    _connectBtn.layer.borderWidth = 2.0f;
    _connectBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.95f].CGColor;
    _connectBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    VCApplyTouchFeedbackToButton(_connectBtn, self);
    [_connectBtn addTarget:self action:@selector(togglePressed) forControlEvents:UIControlEventTouchUpInside];
    _connectPowerIcon = [[VCConnectionPowerView alloc] initWithFrame:CGRectZero];
    [_connectBtn addSubview:_connectPowerIcon];
    _connectButtonTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    _connectButtonTitle.backgroundColor = [UIColor clearColor];
    _connectButtonTitle.textColor = [UIColor whiteColor];
    _connectButtonTitle.textAlignment = NSTextAlignmentCenter;
    _connectButtonTitle.adjustsFontSizeToFitWidth = YES;
    VCSetLabelMinimumScaleFactor(_connectButtonTitle, 0.75f);
    [_connectBtn addSubview:_connectButtonTitle];
    [self.view addSubview:_connectBtn];

    _connectionStateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _connectionStateLabel.font = [UIFont boldSystemFontOfSize:15.0f];
    _connectionStateLabel.backgroundColor = [UIColor clearColor];
    _connectionStateLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_connectionStateLabel];

    _selectionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _selectionLabel.font = [UIFont systemFontOfSize:13.0f];
    _selectionLabel.backgroundColor = [UIColor clearColor];
    _selectionLabel.adjustsFontSizeToFitWidth = YES;
    VCSetLabelMinimumScaleFactor(_selectionLabel, 0.75f);
    _selectionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_selectionLabel];

    _uptimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, topInset + 221.0f,
                                                            b.size.width - 32.0f, 20.0f)];
    _uptimeLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    _uptimeLabel.text = @"00:00:00";
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _uptimeLabel.textAlignment = NSTextAlignmentCenter;
    _uptimeLabel.backgroundColor = [UIColor clearColor];
    _uptimeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_uptimeLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16.0f, topInset + 237.0f,
                                                            b.size.width - 32.0f, 30.0f)];
    _statusLabel.font = [UIFont systemFontOfSize:12.5f];
    _statusLabel.numberOfLines = 2;
    _statusLabel.text = @"Ready";
    _statusOK = YES;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_statusLabel];

    CGFloat listH = b.size.height - listY;
    if (listH < 120.0f) listH = 120.0f;

    UITableViewStyle listStyle = ([[UIDevice currentDevice].systemVersion integerValue] < 7)
        ? UITableViewStyleGrouped : UITableViewStylePlain;
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, listY, b.size.width, listH) style:listStyle];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.opaque = YES;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.separatorColor = [UIColor clearColor];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    _tableView.tableFooterView = footer;
    if (collapsiblePhoneLayout) {
        CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
        _tableView.contentInset = UIEdgeInsetsMake(collapseDistance, 0.0f, 0.0f, 0.0f);
        _tableView.scrollIndicatorInsets = _tableView.contentInset;
        _tableView.contentOffset = CGPointMake(0.0f, -collapseDistance);
    }
    [self.view addSubview:_tableView];

    _mainSwitchView = [[self createMainSwitcherWithWidth:b.size.width - 20.0f] retain];
    _mainSwitchView.frame = CGRectMake(10.0f,
                                       topInset + (collapsiblePhoneLayout ? kVCMainCompactContentStartY
                                                                         : kVCMainContentStartY),
                                       b.size.width - 20.0f, kVCMainSectionHeaderHeight);
    [self updateMainSwitcherView:_mainSwitchView];
    [self.view addSubview:_mainSwitchView];

    CGFloat logY = topInset + kVCMainContentStartY;
    CGFloat logH = b.size.height - logY;
    if (logH < 120.0f) logH = 120.0f;
    CGFloat logSelectorWidth = 188.0f;
    if (logSelectorWidth > b.size.width - 24.0f) logSelectorWidth = b.size.width - 24.0f;
    _logSelector = [[UIView alloc] initWithFrame:CGRectZero];
    _logSelector.frame = CGRectMake((b.size.width - logSelectorWidth) * 0.5f,
                                    logY + 2.0f,
                                    logSelectorWidth,
                                    28.0f);
    _logSelector.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                    UIViewAutoresizingFlexibleRightMargin;
    _logSelector.backgroundColor = [UIColor clearColor];
    _logSelector.hidden = YES;

    NSArray *logTitles = [NSArray arrayWithObjects:@"vpnctld", @"vless-core", nil];
    CGFloat logButtonWidth = logSelectorWidth * 0.5f;
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(logButtonWidth * i, 0.0f, logButtonWidth, 26.0f);
        button.tag = i;
        button.titleLabel.font = [UIFont systemFontOfSize:12.0f];
        [button setTitle:[logTitles objectAtIndex:i] forState:UIControlStateNormal];
        [button addTarget:self
                   action:@selector(logSourceChanged:)
         forControlEvents:UIControlEventTouchUpInside];
        _logSelectorButtons[i] = button;
        [_logSelector addSubview:button];
    }

    _logSelectionIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 26.0f, 32.0f, 2.0f)];
    _logSelectionIndicator.layer.cornerRadius = 1.0f;
    [_logSelector addSubview:_logSelectionIndicator];
    [self.view addSubview:_logSelector];

    _activeLogIndex = 0;
    _logFollowsTail[0] = YES;
    _logFollowsTail[1] = YES;
    [self updateLogSelectorAnimated:NO];
    CGRect logFrame = CGRectMake(0.0f, logY + 32.0f, b.size.width, logH - 32.0f);
    _logView = [[UITextView alloc] initWithFrame:logFrame];
    _logView.editable = NO;
    _logView.font = VCLogRegularFont();
    _logView.backgroundColor = bg;
    _logView.textColor = VCPrimaryTextColor();
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    _logView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logView.hidden = YES;
    _logView.text = @"";
    _logView.delegate = self;
    [self.view addSubview:_logView];

    [self.view bringSubviewToFront:_connectBtn];
    [self.view bringSubviewToFront:_connectionStateLabel];
    [self.view bringSubviewToFront:_selectionLabel];
    [self.view bringSubviewToFront:_uptimeLabel];
    [self.view bringSubviewToFront:_statusLabel];
    [self.view bringSubviewToFront:_mainSwitchView];
    if (IsPadDevice()) [self updatePadConnectionLayout];
    else [self updatePhoneConnectionLayout];

    [self updateConnectButton];
    [self applyTheme];
    [self refreshUpdateIndicatorFromCache];
    [self queryInitialStatus];
    if (_configurationLoading) {
        _plusBtn.enabled=NO; _refreshBtn.enabled=NO; _settingsBtn.enabled=NO;
    }
    VCRecordAppEvent(@"ui", @"Main screen initialized",
                     [NSString stringWithFormat:@"width=%.0f height=%.0f configs=%lu subscriptions=%lu ipad=%d",
                      b.size.width,
                      b.size.height,
                      (unsigned long)[_configs count],
                      (unsigned long)[_subscriptions count],
                      IsPadDevice() ? 1 : 0]);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    if ([_subscriptionTask cancelWithReason:[_subscriptionTask.cancellationReason stringByAppendingString:@": low memory"]]) {
        _refreshBtn.enabled=NO;
        [self subscriptionTaskProgress:_subscriptionTask];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self refreshUpdateIndicatorFromCache];
    [self startLaunchAutoUpdateIfNeeded];
    if (!_didScheduleAutomaticUpdateCheck) {
        _didScheduleAutomaticUpdateCheck = YES;
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:1.5];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (IsPadDevice()) {
        [self updatePadConnectionLayout];
    } else {
        [self updatePhoneConnectionScrollInsets];
        [self updatePhoneConnectionLayout];
    }
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
    if (_configurationQueue) dispatch_release(_configurationQueue);
    [_pendingProfileMetadata release];
    [_deferredImportURL release];
    [_configurationWriter release];
    [_configurationDraft release];
    if (_configurationDraftCompletion) Block_release(_configurationDraftCompletion);
    [_subscriptionTask finish]; [_subscriptionTask release];
    [_connectAfterSubscriptionURL release];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startLaunchAutoUpdateIfNeeded)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startAutomaticUpdateCheckIfNeeded)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(beginPendingReconnect)
                                               object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushMainStateDefaults)
                                               object:nil];
    [self flushMainStateDefaults];
    _updateChecker.delegate = nil;
    [_updateChecker release];
    [_availableReleaseURL release];
    [_availableUpdateVersion release];
    [_pendingReconnectURI release];
    [_logTimer invalidate];
    [_logTimer release];
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    [_statusBaseText release];

    [_connectBtn release];
    [_connectGlowView release];
    [_compactConnectGlowView release];
    [_connectPowerIcon release];
    [_connectButtonTitle release];
    [_connectionStateLabel release];
    [_selectionLabel release];
    [_plusBtn release];
    [_terminalBtn release];
    [_clearLogsBtn release];
    [_refreshBtn release];
    [_settingsBtn release];
    [_updateBtn release];
    [_statusLabel release];
    [_uptimeLabel release];
    [_titleLabel release];

    [_tableView release];
    [_logSelector release];
    [_logSelectionIndicator release];
    [_logView release];
    [_logTexts[0] release];
    [_logTexts[1] release];
    [_mainSwitchView release];
    [_pendingImportRefreshIndices release];
    [_pendingInsecureImportURLs release];
    if (_pendingPlainHTTPConfirmation) Block_release(_pendingPlainHTTPConfirmation);
    if (_pendingPlainHTTPCancellation) Block_release(_pendingPlainHTTPCancellation);
    [_subscriptionToReexpandAfterReorder release];

    [_configs release];
    [_subscriptions release];
    [_pingDisplayByURI release];
    [_pingNetworkSignature release];
    [_pingNetworkTimer invalidate];
    [_pingNetworkTimer release];
    [_standalonePingCancellationsByURI release];
    [_subscriptionPingPendingByIdentifier release];
    [_subscriptionPingOperationsByIdentifier release];
    [_subscriptionPingPreviousDisplayByIdentifier release];
    [_subscriptionPingTokenByIdentifier release];
    [_pingQueue cancelAllOperations];
    [_pingQueue release];

    [super dealloc];
}

@end
