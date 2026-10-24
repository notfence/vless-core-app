#import "main_screen.h"
#import "update_checker.h"
#import "settings.h"

@implementation MainVC (VCMainSettings)

- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled {
    (void)vc;
    _autoUpdateSubscriptions = enabled;
    VCRecordAppEvent(@"settings", @"Subscription auto-update changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [self showStatus:_autoUpdateSubscriptions ? @"Auto-update subscriptions: ON"
                                           : @"Auto-update subscriptions: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)enabled {
    (void)vc;
    _automaticUpdateChecksEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Application update checks changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];

    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(startAutomaticUpdateCheckIfNeeded)
                                               object:nil];
    if (enabled) {
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:0.5];
    } else if (_updateChecker) {
        _updateChecker.delegate = nil;
        [_updateChecker release];
        _updateChecker = nil;
    }

    [self showStatus:enabled ? @"Automatic update checks: ON"
                             : @"Automatic update checks: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)enabled {
    (void)vc;
    _preserveCustomSubscriptionNames = enabled;
    VCRecordAppEvent(@"settings", @"Preserve custom names changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [self showStatus:_preserveCustomSubscriptionNames ? @"Preserve custom names: ON"
                                                      : @"Preserve custom names: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled {
    (void)vc;
    _stealthModeEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Stealth mode changed", enabled ? @"enabled=1" : @"enabled=0");
    [self saveData];
    [_tableView reloadData];
    [self showStatus:_stealthModeEnabled ? @"Stealth mode: ON"
                                   : @"Stealth mode: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeSortSubscriptionsByPing:(BOOL)enabled {
    (void)vc;
    _sortSubscriptionsByPing = enabled;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDefaultsSortSubscriptionsByPingKey];
    [defaults synchronize];
    [self scheduleSubscriptionPingSort];
    VCRecordAppEvent(@"settings", @"Subscription ping sorting changed", enabled ? @"enabled=1" : @"enabled=0");
}

- (void)settingsVCDidChangePingSettings:(SettingsVC *)vc {
    (void)vc;
    [self stopAllPings];
    ++_pingNetworkGeneration;
    [_pingDisplayByURI removeAllObjects];
    [self scheduleSubscriptionPingSort];
    [self refreshVisiblePingAccessoriesForURI:nil];
    [self refreshVisibleSubscriptionHeaderAccessories];
}

- (void)settingsVC:(SettingsVC *)vc didChangeUseXmux:(BOOL)enabled {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (VCUseXmuxInDefaults(defaults) == enabled) return;
    [defaults setBool:enabled forKey:kDefaultsUseXmuxKey];
    [defaults synchronize];
    if (VCSelectedPingType() == VCPingTypeProxyGET) [self settingsVCDidChangePingSettings:vc];
    VCRecordAppEvent(@"settings", @"XMUX setting changed", enabled ? @"enabled=1" : @"enabled=0");
}

- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled {
    (void)vc;
    _darkThemeEnabled = enabled;
    VCRecordAppEvent(@"settings", @"Appearance changed", enabled ? @"theme=dark" : @"theme=light");
    [self saveData];
    [self applyTheme];
}

- (void)settingsVCDidChangeAccentColor:(SettingsVC *)vc {
    (void)vc;
    [self applyTheme];
}

- (void)refreshPressed {
    if (_subscriptionTask) { [self cancelSubscriptionTask]; return; }
    VCRecordAppEvent(@"ui", @"Refresh subscriptions button pressed", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    [self startBackgroundSubscriptionRefresh];
}

- (void)settingsPressed {
    VCRecordAppEvent(@"ui", @"Settings opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    SettingsVC *settings = [[[SettingsVC alloc] init] autorelease];
    settings.autoUpdate = _autoUpdateSubscriptions;
    settings.preserveCustomNames = _preserveCustomSubscriptionNames;
    settings.sortSubscriptionsByPing = _sortSubscriptionsByPing;
    settings.useXmux = VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults]);
    settings.stealthMode = _stealthModeEnabled;
    settings.darkTheme = _darkThemeEnabled;
    settings.automaticUpdateChecks = _automaticUpdateChecksEnabled;
    settings.delegate = self;

    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:settings] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)refreshUpdateIndicatorFromCache {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *latestVersion = [defaults objectForKey:kDefaultsLatestVersionKey];
    NSString *releaseURL = [defaults objectForKey:kDefaultsLatestReleaseURLKey];
    BOOL available = [latestVersion isKindOfClass:[NSString class]] &&
                     VCCompareVersions(AppShortVersion(), latestVersion) == NSOrderedAscending;

    [_availableUpdateVersion release];
    _availableUpdateVersion = available ? [latestVersion copy] : nil;
    [_availableReleaseURL release];
    _availableReleaseURL = available && [releaseURL isKindOfClass:[NSString class]]
        ? [releaseURL copy]
        : nil;
    [self updateTopButtonsIcons];
    [self refreshStatusText];
}

- (void)updateIndicatorPressed {
    if ([_availableUpdateVersion length] == 0) return;

    NSString *releaseURL = [_availableReleaseURL length] > 0
        ? _availableReleaseURL
        : kUpdateReleasesURL;
    NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"update", @"status",
                            AppShortVersion(), @"current_version",
                            _availableUpdateVersion, @"latest_version",
                            releaseURL, @"release_url",
                            nil];
    VCShowUpdateAvailableAlert(result, self, VCAlertTagUpdateAvailable);
}

- (void)startAutomaticUpdateCheckIfNeeded {
    if (!_automaticUpdateChecksEnabled || _updateChecker || VCAutomaticUpdateCheckIsFresh()) return;

    if (_launchAutoUpdateInProgress || self.presentedViewController || !self.view.window) {
        [self performSelector:@selector(startAutomaticUpdateCheckIfNeeded) withObject:nil afterDelay:1.0];
        return;
    }

    _updateChecker = [[VCUpdateChecker alloc] initWithDelegate:self];
    [_updateChecker start];
}

- (void)updateChecker:(VCUpdateChecker *)checker didFinishWithResult:(NSDictionary *)result {
    if (checker != _updateChecker) return;

    checker.delegate = nil;
    [_updateChecker release];
    _updateChecker = nil;

    if (!VCUpdateResultIsSuccessful(result)) return;
    VCCacheSuccessfulUpdateResult(result);
    [self refreshUpdateIndicatorFromCache];
}

@end
