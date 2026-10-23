#import "main_screen.h"
#import "settings.h"
#import "subscription_info.h"

@implementation MainVC (VCMainSubscriptions)

- (BOOL)preserveCustomSubscriptionNames {
    return _preserveCustomSubscriptionNames;
}

- (NSTimeInterval)subscriptionUpdateTimestamp {
    return [[NSDate date] timeIntervalSince1970];
}

- (NSString *)decodedSubscriptionTitleValue:(NSString *)rawValue {
    return [VCProfiles() decodedSubscriptionTitleValue:rawValue];
}

- (NSString *)subscriptionTitleFromMetadataText:(NSString *)text {
    return [VCProfiles() subscriptionTitleFromMetadataText:text];
}

- (NSString *)subscriptionTitleFromData:(NSData *)data {
    return [VCProfiles() subscriptionTitleFromData:data];
}

- (NSString *)subscriptionTitleFromHTTPHeaders:(NSDictionary *)headers {
    return [VCProfiles() subscriptionTitleFromHTTPHeaders:headers];
}

- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromMetadataText:(NSString *)text {
    return [VCProfiles() subscriptionHeaderValueNamed:headerName fromMetadataText:text];
}

- (NSString *)subscriptionHeaderValueNamed:(NSString *)headerName fromHTTPHeaders:(NSDictionary *)headers {
    return [VCProfiles() subscriptionHeaderValueNamed:headerName fromHTTPHeaders:headers];
}

- (NSNumber *)subscriptionUnsignedNumberFromString:(NSString *)text {
    return [VCProfiles() subscriptionUnsignedNumberFromString:text];
}

- (NSDictionary *)subscriptionUserInfoFromHeaderValue:(NSString *)headerValue {
    return [VCProfiles() subscriptionUserInfoFromHeaderValue:headerValue];
}

- (NSDictionary *)subscriptionUserInfoFromMetadataText:(NSString *)text {
    return [VCProfiles() subscriptionUserInfoFromMetadataText:text];
}

- (NSDictionary *)subscriptionUserInfoFromData:(NSData *)data {
    return [VCProfiles() subscriptionUserInfoFromData:data];
}

- (NSDictionary *)subscriptionUserInfoFromHTTPHeaders:(NSDictionary *)headers {
    return [VCProfiles() subscriptionUserInfoFromHTTPHeaders:headers];
}

- (NSDictionary *)subscriptionMetadataFromMetadataText:(NSString *)text {
    return [VCProfiles() subscriptionMetadataFromMetadataText:text];
}

- (NSDictionary *)subscriptionMetadataFromData:(NSData *)data {
    return [VCProfiles() subscriptionMetadataFromData:data];
}

- (NSDictionary *)subscriptionMetadataFromHTTPHeaders:(NSDictionary *)headers {
    return [VCProfiles() subscriptionMetadataFromHTTPHeaders:headers];
}

- (NSString *)formattedSubscriptionBytes:(unsigned long long)bytes {
    return [VCProfiles() formattedSubscriptionBytes:bytes];
}

- (NSString *)subscriptionTrafficTextFromDictionary:(NSDictionary *)sub {
    return [VCProfiles() subscriptionTrafficTextFromDictionary:sub];
}

- (NSString *)subscriptionExpiryTextFromDictionary:(NSDictionary *)sub {
    return [VCProfiles() subscriptionExpiryTextFromDictionary:sub];
}

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut insecureRetryAvailable:(BOOL *)insecureRetryAvailableOut {
    if (errorTextOut) *errorTextOut = nil;
    if (insecureRetryAvailableOut) *insecureRetryAvailableOut = NO;
    if (![sub isKindOfClass:[NSDictionary class]]) {
        if (errorTextOut) *errorTextOut = @"Subscription entry is invalid";
        return nil;
    }

    NSString *urlString = [sub objectForKey:@"url"];
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is missing";
        return nil;
    }

    BOOL useHappHeaders = SubscriptionDictionaryUsesHappHeaders(sub);
    NSString *fetchURLString = urlString;
    if (useHappHeaders && [self isHappEncryptedLink:urlString]) {
        NSString *decryptError = nil;
        fetchURLString = [self decryptedHappLink:urlString errorText:&decryptError];
        if (![fetchURLString isKindOfClass:[NSString class]] || [fetchURLString length] == 0) {
            if (errorTextOut) {
                *errorTextOut = ([decryptError length] > 0) ? decryptError : @"HAPP link decryption failed";
            }
            return nil;
        }
    }

    NSURL *url = [NSURL URLWithString:fetchURLString];
    if (!url) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is invalid";
        return nil;
    }

    NSString *nameFromURL = useHappHeaders ? @"HAPP subscription" : [self subscriptionNameFromURLString:fetchURLString];
    NSString *hostName = useHappHeaders ? @"HAPP subscription" : [self hostFromURLString:fetchURLString];
    NSString *nameFromMeta = nil;
    NSDictionary *userInfoFromMeta = nil;
    NSDictionary *metadataFromMeta = nil;
    BOOL allowInsecureFetch = SubscriptionDictionaryAllowsInsecureFetch(sub);
    BOOL allowPlainHTTP = SubscriptionDictionaryAllowsPlainHTTP(sub);

    NSString *fetchErr = nil;
    NSString *curlHeaders = nil;
    NSString *userAgent = AppUserAgent();
    int curlExitCode = -1;
    NSData *data = FetchURLViaVlessCoreCurl(fetchURLString,
                                            allowInsecureFetch,
                                            allowPlainHTTP,
                                            useHappHeaders,
                                            YES,
                                            userAgent,
                                            &fetchErr,
                                            &curlHeaders,
                                            &curlExitCode);
    if (!data && !allowInsecureFetch && CurlExitCodeCanRetryInsecurely(curlExitCode)) {
        if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
    }
    if ([nameFromMeta length] == 0 && [curlHeaders length] > 0) {
        nameFromMeta = [self subscriptionTitleFromMetadataText:curlHeaders];
    }
    if ([curlHeaders length] > 0) {
        userInfoFromMeta = [self subscriptionUserInfoFromMetadataText:curlHeaders];
        metadataFromMeta = [self subscriptionMetadataFromMetadataText:curlHeaders];
    }
    if (useHappHeaders && !data && !allowInsecureFetch &&
        (!fetchErr || [fetchErr hasPrefix:@"vless-core-curl not found"])) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20.0];
        NSString *hwid = SubscriptionHWID();
        if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
            [req setValue:hwid forHTTPHeaderField:@"X-HWID"];
        }
        if (useHappHeaders) {
            [req setValue:kHappSubscriptionUserAgent forHTTPHeaderField:@"User-Agent"];
            UIDevice *device = [UIDevice currentDevice];
            NSString *locale = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
            NSString *systemVersion = TrimSimpleString([device systemVersion]);
            NSString *model = DeviceModelName();
            if ([locale length] > 0) [req setValue:locale forHTTPHeaderField:@"X-Device-Locale"];
            [req setValue:@"iOS" forHTTPHeaderField:@"X-Device-OS"];
            if ([systemVersion length] > 0) [req setValue:systemVersion forHTTPHeaderField:@"X-Ver-OS"];
            if ([model length] > 0) [req setValue:model forHTTPHeaderField:@"X-Device-Model"];
        }
        NSURLResponse *resp = nil;
        NSError *err = nil;
        data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        if (!data || err) {
            fetchErr = [err localizedDescription];
            if (!allowInsecureFetch && NSURLErrorCanRetryInsecurely(err)) {
                if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
            }
        } else if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSDictionary *headers = [(NSHTTPURLResponse *)resp allHeaderFields];
            nameFromMeta = [self subscriptionTitleFromHTTPHeaders:headers];
            userInfoFromMeta = [self subscriptionUserInfoFromHTTPHeaders:headers];
            metadataFromMeta = [self subscriptionMetadataFromHTTPHeaders:headers];
        }
    }

    if (!data) {
        if (![fetchErr isKindOfClass:[NSString class]] || [fetchErr length] == 0) {
            fetchErr = @"unknown error";
        }
        if (errorTextOut) *errorTextOut = [NSString stringWithFormat:@"Subscription fetch failed: %@", fetchErr];
        return nil;
    }

    return [VCProfiles() updatedSubscriptionFromSource:sub
                                                 data:data
                                     nameFromMetadata:nameFromMeta
                                 userInfoFromMetadata:userInfoFromMeta
                                 metadataFromResponse:metadataFromMeta
                                          nameFromURL:nameFromURL
                                             hostName:hostName
                                              options:self
                                            errorText:errorTextOut];
}

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut {
    return [self updatedSubscriptionDictionaryFromSource:sub errorText:errorTextOut insecureRetryAvailable:NULL];
}

- (BOOL)subscriptionNeedsPlainHTTPApproval:(NSDictionary *)sub {
    if (![sub isKindOfClass:[NSDictionary class]] || SubscriptionDictionaryUsesHappHeaders(sub)) return NO;
    return URLStringUsesPlainHTTP([sub objectForKey:@"url"]) &&
           !SubscriptionDictionaryAllowsPlainHTTP(sub);
}

- (BOOL)approvePlainHTTPForSubscriptionAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return NO;
    NSDictionary *sub = [_subscriptions objectAtIndex:index];
    if (![self subscriptionNeedsPlainHTTPApproval:sub]) {
        return SubscriptionDictionaryAllowsPlainHTTP(sub);
    }

    NSMutableDictionary *approved = [NSMutableDictionary dictionaryWithDictionary:sub];
    [approved setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
    [_subscriptions replaceObjectAtIndex:index withObject:approved];
    return YES;
}

- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus {
    if (idx < 0 || idx >= (NSInteger)[_subscriptions count]) return NO;
    if ([self isConnectionActionInProgress]) {
        if (showStatus) [self showStatus:@"Busy" ok:NO];
        return NO;
    }
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"subscription", @"Single subscription update started", nil);

    NSDictionary *sub = [_subscriptions objectAtIndex:idx];
    if ([self subscriptionNeedsPlainHTTPApproval:sub]) {
        [self showPlainHTTPSubscriptionWarningForCount:1 confirmation:^{
            if ([self approvePlainHTTPForSubscriptionAtIndex:idx]) {
                [self saveData];
                if ([self refreshSubscriptionAtIndex:idx showStatus:YES]) {
                    [self reloadMainTableDataAfterExternalChange];
                }
            }
        }];
        return NO;
    }

    NSString *errorText = nil;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
    if (![updated isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"subscription", @"Single subscription update failed",
                         [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                          VCDiagnosticErrorSummary(errorText),
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        if (showStatus) {
            [self showStatus:([errorText length] > 0 ? errorText : @"Subscription update failed") ok:NO];
            [self showSubscriptionUpdateFailures:[NSArray arrayWithObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]]];
        }
        return NO;
    }

    NSArray *uris = [updated objectForKey:@"items"];
    [_subscriptions replaceObjectAtIndex:idx withObject:updated];
    [self showProfileImportWarnings:@[updated]];
    if (_selectedSubIndex == idx) {
        if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
            _selectedSubItemIndex = -1;
        } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
            _selectedSubItemIndex = 0;
        }
    }
    [self saveData];
    VCRecordAppEvent(@"subscription", @"Single subscription update finished",
                     [NSString stringWithFormat:@"configs=%lu duration_ms=%.0f",
                      (unsigned long)[uris count],
                      ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
    if (showStatus) {
        [self showStatus:[NSString stringWithFormat:@"Subscription updated (%lu configs)", (unsigned long)[uris count]] ok:YES];
    }
    return YES;
}

- (BOOL)subscriptionsMatchSnapshotForLaunchAutoUpdate:(NSArray *)snapshot {
    if (![snapshot isKindOfClass:[NSArray class]]) return NO;
    if ((NSInteger)[snapshot count] != (NSInteger)[_subscriptions count]) return NO;

    for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
        NSDictionary *oldSub = [snapshot objectAtIndex:i];
        NSDictionary *curSub = [_subscriptions objectAtIndex:i];
        NSString *oldURL = [oldSub objectForKey:@"url"];
        NSString *curURL = [curSub objectForKey:@"url"];
        if (![oldURL isKindOfClass:[NSString class]]) oldURL = @"";
        if (![curURL isKindOfClass:[NSString class]]) curURL = @"";
        if (![oldURL isEqualToString:curURL]) return NO;

        NSString *oldName = [oldSub objectForKey:@"name"];
        NSString *curName = [curSub objectForKey:@"name"];
        if (![oldName isKindOfClass:[NSString class]]) oldName = @"";
        if (![curName isKindOfClass:[NSString class]]) curName = @"";
        if (![oldName isEqualToString:curName]) return NO;

        NSString *oldCustomName = [oldSub objectForKey:kSubscriptionCustomNameKey];
        NSString *curCustomName = [curSub objectForKey:kSubscriptionCustomNameKey];
        if (![oldCustomName isKindOfClass:[NSString class]]) oldCustomName = @"";
        if (![curCustomName isKindOfClass:[NSString class]]) curCustomName = @"";
        if (![oldCustomName isEqualToString:curCustomName]) return NO;
    }
    return YES;
}

- (void)startBackgroundSubscriptionRefreshWithStatus:(NSString *)startStatus {
    if ([_subscriptions count] == 0) {
        if (_pendingImportDoneStatus) {
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        }
        if (_pendingImportRefreshIndices) {
            [_pendingImportRefreshIndices release];
            _pendingImportRefreshIndices = nil;
        }
        [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }
    BOOL updateInProgress = _launchAutoUpdateInProgress;
    BOOL connectionActionInProgress = [self isConnectionActionInProgress];
    if (updateInProgress || connectionActionInProgress) {
        [_pendingImportDoneStatus release];
        _pendingImportDoneStatus = nil;
        [_pendingImportRefreshIndices release];
        _pendingImportRefreshIndices = nil;
        if (updateInProgress) {
            [self showStatus:@"Subscriptions update is already running" ok:YES];
        } else {
            VCRecordAppEvent(@"subscription", @"Subscription update blocked", @"connection action in progress");
            [self showStatus:@"Busy" ok:NO];
        }
        return;
    }

    NSMutableArray *plainHTTPIndices = [NSMutableArray array];
    if ([_pendingImportRefreshIndices count] > 0) {
        for (id indexValue in _pendingImportRefreshIndices) {
            NSInteger index = [indexValue integerValue];
            if (index >= 0 && index < (NSInteger)[_subscriptions count] &&
                [self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
                [plainHTTPIndices addObject:[NSNumber numberWithInteger:index]];
            }
        }
    } else {
        for (NSInteger index = 0; index < (NSInteger)[_subscriptions count]; index++) {
            if ([self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
                [plainHTTPIndices addObject:[NSNumber numberWithInteger:index]];
            }
        }
    }
    if ([plainHTTPIndices count] > 0) {
        [self showPlainHTTPSubscriptionWarningForCount:[plainHTTPIndices count] confirmation:^{
            BOOL changed = NO;
            for (NSNumber *indexValue in plainHTTPIndices) {
                changed |= [self approvePlainHTTPForSubscriptionAtIndex:[indexValue integerValue]];
            }
            if (changed) [self saveData];
            [self startBackgroundSubscriptionRefreshWithStatus:startStatus];
        }];
        return;
    }

    NSArray *requestedIndices = nil;
    if (_pendingImportRefreshIndices && [_pendingImportRefreshIndices count] > 0) {
        requestedIndices = [_pendingImportRefreshIndices copy];
    }
    [_pendingImportRefreshIndices release];
    _pendingImportRefreshIndices = nil;

    NSArray *snapshot = [[NSArray alloc] initWithArray:_subscriptions copyItems:YES];
    NSUInteger sourceRevision=_configurationRevision;
    NSMutableArray *refreshIndicesMutable = [NSMutableArray array];
    if ([requestedIndices count] > 0) {
        for (id idxObj in requestedIndices) {
            NSInteger idx = [idxObj integerValue];
            if (idx >= 0 && idx < (NSInteger)[snapshot count]) {
                [refreshIndicesMutable addObject:[NSNumber numberWithInteger:idx]];
            }
        }
    } else {
        for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
            [refreshIndicesMutable addObject:[NSNumber numberWithInteger:i]];
        }
    }
    [requestedIndices release];

    if ([refreshIndicesMutable count] == 0) {
        if (_pendingImportDoneStatus) {
            [self showStatus:_pendingImportDoneStatus ok:YES];
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        } else {
            [self showStatus:@"No subscriptions to update" ok:NO];
        }
        [snapshot release];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    [self setSubscriptionRefreshInProgress:YES];
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];

    NSArray *refreshIndices = [[NSArray alloc] initWithArray:refreshIndicesMutable];
    VCRecordAppEvent(@"subscription", @"Subscription update batch started",
                     [NSString stringWithFormat:@"requested=%lu", (unsigned long)[refreshIndices count]]);
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Updating subscriptions...";
    [self showStatus:startText ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *updatedSubs = [[NSMutableArray alloc] initWithArray:snapshot];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSMutableDictionary *failureCategories = [[NSMutableDictionary alloc] init];
        NSUInteger okCount = 0;
        for (NSNumber *idxObj in refreshIndices) {
            NSAutoreleasePool *entryPool=[[NSAutoreleasePool alloc] init];
            @try {
            NSInteger i = [idxObj integerValue];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self setUpdatingSubscriptionIndex:i];
            });

            NSDictionary *sub = [snapshot objectAtIndex:i];
            NSString *errorText = nil;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
            if (updated) {
                [updatedSubs replaceObjectAtIndex:i withObject:updated];
                okCount++;
            } else {
                [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
                VCIncrementDiagnosticCategory(failureCategories, errorText);
            }
            } @finally { [entryPool drain]; }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (sourceRevision != _configurationRevision || ![self subscriptionsMatchSnapshotForLaunchAutoUpdate:snapshot]) {
                [self setUpdatingSubscriptionIndex:-1];
                _launchAutoUpdateInProgress=NO;
                [self setSubscriptionRefreshInProgress:NO];
                VCRecordAppEvent(@"subscription", @"Subscription update batch discarded",
                                 @"reason=list_changed_during_update");
                [self showStatus:@"Auto-update skipped: subscriptions changed" ok:YES];
                if (_pendingImportDoneStatus) {
                    [_pendingImportDoneStatus release];
                    _pendingImportDoneStatus = nil;
                }
                [failureTexts release];
                [failureCategories release];
                [updatedSubs release];
                [refreshIndices release];
                [snapshot release];
                return;
            }

            [self commitConfigurations:_configs subscriptions:updatedSubs completion:^(BOOL saved) {
            [self setUpdatingSubscriptionIndex:-1];
            _launchAutoUpdateInProgress=NO;
            [self setSubscriptionRefreshInProgress:NO];
            if (!saved) {
                [failureTexts release]; [failureCategories release]; [updatedSubs release]; [refreshIndices release]; [snapshot release];
                [_pendingImportDoneStatus release]; _pendingImportDoneStatus=nil;
                return;
            }
            [self showProfileImportWarnings:updatedSubs];

            [self normalizeSelection];
            [self reloadMainTableDataAfterExternalChange];
            [self saveData];
            [self refreshPresentedSubscriptionInfoIfNeeded];

            BOOL ok = okCount > 0;
            if (_pendingImportDoneStatus) {
                [self showStatus:_pendingImportDoneStatus ok:YES];
                [_pendingImportDoneStatus release];
                _pendingImportDoneStatus = nil;
            } else {
	                [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
	                                  (unsigned long)okCount,
	                                  (unsigned long)[refreshIndices count]]
	                         ok:ok];
            }

            if ([failureTexts count] > 0) {
                [self showSubscriptionUpdateFailures:failureTexts];
            }
            VCRecordAppEvent(@"subscription", @"Subscription update batch finished",
                             [NSString stringWithFormat:@"requested=%lu updated=%lu failed=%lu failure_types=%@ duration_ms=%.0f",
                              (unsigned long)[refreshIndices count],
                              (unsigned long)okCount,
                              (unsigned long)[failureTexts count],
                              VCDiagnosticCategoryCountsText(failureCategories),
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);

            [failureTexts release];
            [failureCategories release];
            [updatedSubs release];
            [refreshIndices release];
            [snapshot release];
            }];
        });

        [pool drain];
    });
}

- (void)startLaunchAutoUpdateIfNeeded {
    if (_configurationLoading) return;
    if (_didRunLaunchAutoUpdate) return;
    if (!_autoUpdateSubscriptions || [_subscriptions count] == 0) {
        _didRunLaunchAutoUpdate = YES;
        return;
    }
    if ([self isConnectionActionInProgress]) {
        [self performSelector:@selector(startLaunchAutoUpdateIfNeeded) withObject:nil afterDelay:0.5];
        return;
    }
    _didRunLaunchAutoUpdate = YES;

    [self startBackgroundSubscriptionRefreshWithStatus:@"Auto-updating subscriptions in background..."];
}

- (void)refreshAllSubscriptions:(BOOL)showStatus {
    if ([self isConnectionActionInProgress]) {
        if (showStatus) [self showStatus:@"Busy" ok:NO];
        return;
    }
    if ([_subscriptions count] == 0) {
        if (showStatus) [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }

    NSUInteger okCount = 0;
    NSMutableArray *failureTexts = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *sub = [_subscriptions objectAtIndex:i];
        NSString *errorText = nil;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            NSArray *uris = [updated objectForKey:@"items"];
            [_subscriptions replaceObjectAtIndex:i withObject:updated];
            [self showProfileImportWarnings:@[updated]];
            if (_selectedSubIndex == i) {
                if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
                    _selectedSubItemIndex = -1;
                } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
                    _selectedSubItemIndex = 0;
                }
            }
            [self saveData];
            okCount++;
        } else {
            [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
        }
    }

    [self normalizeSelection];
    [self reloadMainTableDataAfterExternalChange];
    [self refreshPresentedSubscriptionInfoIfNeeded];

    if (showStatus) {
        BOOL ok = okCount > 0;
        [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
                          (unsigned long)okCount,
                          (unsigned long)[_subscriptions count]]
                     ok:ok];
        if ([failureTexts count] > 0) {
            [self showSubscriptionUpdateFailures:failureTexts];
        }
    }
}

- (void)openSubscriptionProviderURLAtIndex:(NSInteger)index
                               metadataKey:(NSString *)metadataKey
                                 eventName:(NSString *)eventName {
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;
    NSDictionary *subscription = [_subscriptions objectAtIndex:index];
    NSString *urlString = VCSubscriptionProviderURL(subscription, metadataKey);
    if ([urlString length] == 0) return;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL opened = [[UIApplication sharedApplication] openURL:[NSURL URLWithString:urlString]];
#pragma clang diagnostic pop
    VCRecordAppEvent(@"ui", eventName, opened ? @"opened=1" : @"opened=0");
    if (opened) return;
    [self showStatus:@"Provider link could not be opened" ok:NO];
}

- (void)subscriptionWebPageButtonPressed:(UIButton *)sender {
    NSInteger index = sender.tag - kVCSubscriptionWebPageButtonTagBase;
    [self openSubscriptionProviderURLAtIndex:index
                                 metadataKey:kSubscriptionWebPageURLKey
                                   eventName:@"Subscription web page opened"];
}

- (void)subscriptionSupportButtonPressed:(UIButton *)sender {
    NSInteger index = sender.tag - kVCSubscriptionSupportButtonTagBase;
    [self openSubscriptionProviderURLAtIndex:index
                                 metadataKey:kSubscriptionSupportURLKey
                                   eventName:@"Subscription support opened"];
}

- (void)subscriptionInfoButtonPressed:(UIButton *)sender {
    NSInteger index = sender.tag - kVCSubscriptionInfoButtonTagBase;
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;
    VCRecordAppEvent(@"ui", @"Subscription details opened", nil);

    NSDictionary *subscription = [_subscriptions objectAtIndex:index];
    SubscriptionInfoVC *info = [[[SubscriptionInfoVC alloc] initWithSubscription:subscription
                                                                           index:index
                                                                     stealthMode:_stealthModeEnabled
                                                                        delegate:self] autorelease];
    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:info] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)refreshPresentedSubscriptionInfoIfNeeded {
    UIViewController *presented = self.presentedViewController;
    if (![presented isKindOfClass:[UINavigationController class]]) return;
    UIViewController *top = [(UINavigationController *)presented topViewController];
    if (![top isKindOfClass:[SubscriptionInfoVC class]]) return;

    SubscriptionInfoVC *info = (SubscriptionInfoVC *)top;
    NSInteger index = [info subscriptionIndex];
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;
    [info reloadWithSubscription:[_subscriptions objectAtIndex:index]];
}

- (void)subscriptionInfoVCRequestedRefresh:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index {
    if (_launchAutoUpdateInProgress) {
        [vc finishRefreshWithSubscription:nil errorText:@"Another subscription update is already running"];
        return;
    }
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) {
        [vc finishRefreshWithSubscription:nil errorText:@"Subscription no longer exists"];
        return;
    }
    if ([self isConnectionActionInProgress]) {
        VCRecordAppEvent(@"subscription", @"Subscription update blocked", @"connection action in progress");
        [self showStatus:@"Busy" ok:NO];
        [vc finishRefreshWithSubscription:nil errorText:@"Connection action is in progress"];
        return;
    }
    if ([self subscriptionNeedsPlainHTTPApproval:[_subscriptions objectAtIndex:index]]) {
        [self showPlainHTTPSubscriptionWarningForCount:1
                                          confirmation:^{
                                              if ([self approvePlainHTTPForSubscriptionAtIndex:index]) {
                                                  [self saveData];
                                                  [self subscriptionInfoVCRequestedRefresh:vc atIndex:index];
                                              }
                                          }
                                            cancellation:^{
                                                [vc cancelRefresh];
                                            }];
        return;
    }

    NSDictionary *snapshot = [[_subscriptions objectAtIndex:index] copy];
    NSUInteger sourceRevision=_configurationRevision;
    NSString *expectedURL = [[snapshot objectForKey:@"url"] copy];
    SubscriptionInfoVC *infoVC = [vc retain];
    _launchAutoUpdateInProgress = YES;
    [self setSubscriptionRefreshInProgress:YES];
    [self setUpdatingSubscriptionIndex:index];
    [self showStatus:@"Updating subscription..." ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = nil;
        NSDictionary *updated = [[self updatedSubscriptionDictionaryFromSource:snapshot errorText:&errorText] retain];
        NSString *copiedError = [errorText copy];

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL stillExists = (index >= 0 && index < (NSInteger)[_subscriptions count]);
            NSString *currentURL = stillExists ? [[_subscriptions objectAtIndex:index] objectForKey:@"url"] : nil;
            BOOL unchanged = sourceRevision == _configurationRevision && stillExists && [expectedURL isKindOfClass:[NSString class]] &&
                             [currentURL isKindOfClass:[NSString class]] && [currentURL isEqualToString:expectedURL];

            void (^finishRefresh)(BOOL)=^(BOOL saved) {
            [self setUpdatingSubscriptionIndex:-1];
            _launchAutoUpdateInProgress=NO;
            [self setSubscriptionRefreshInProgress:NO];
            if (updated && unchanged && saved) {
                [self showProfileImportWarnings:@[updated]];
                [self normalizeSelection];
                [self saveData];
                [self reloadMainTableDataAfterExternalChange];
                NSArray *items = [updated objectForKey:@"items"];
                [self showStatus:[NSString stringWithFormat:@"Subscription updated (%lu configs)",
                                  (unsigned long)([items isKindOfClass:[NSArray class]] ? [items count] : 0)]
                              ok:YES];
                [infoVC finishRefreshWithSubscription:updated errorText:nil];
            } else {
                NSString *message = copiedError;
                if (!unchanged) message = @"Subscription changed while it was updating";
                else if (updated && !saved) message=@"Subscription was not saved; previous configurations are unchanged";
                if (![message isKindOfClass:[NSString class]] || [message length] == 0) {
                    message = @"Subscription update failed";
                }
                [self showStatus:message ok:NO];
                [infoVC finishRefreshWithSubscription:nil errorText:message];
            }

            [updated release];
            [copiedError release];
            [expectedURL release];
            [snapshot release];
            [infoVC release];
            };
            if (updated && unchanged) {
                NSMutableArray *draft=[NSMutableArray arrayWithArray:_subscriptions];
                [draft replaceObjectAtIndex:index withObject:updated];
                [self commitConfigurations:_configs subscriptions:draft completion:finishRefresh];
            } else finishRefresh(NO);
        });
        [pool drain];
    });
}

- (void)subscriptionInfoVC:(SubscriptionInfoVC *)vc requestedRenameTo:(NSString *)name atIndex:(NSInteger)index {
    if ([self configurationMutationBlocked]) return;
    if (index < 0 || index >= (NSInteger)[_subscriptions count]) return;

    NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed length] == 0) return;

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:[_subscriptions objectAtIndex:index]];
    [updated setObject:trimmed forKey:@"name"];
    [updated setObject:trimmed forKey:kSubscriptionCustomNameKey];
    [_subscriptions replaceObjectAtIndex:index withObject:updated];
    VCRecordAppEvent(@"subscription", @"Subscription renamed", nil);

    [self saveData];
    [self reloadMainTableDataAfterExternalChange];
    [vc reloadWithSubscription:updated];
    [self showStatus:@"Subscription renamed" ok:YES];
}

- (BOOL)deleteSubscriptionAtIndex:(NSInteger)subIdx {
    if ([self configurationMutationBlocked]) return NO;
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return NO;
    [_subscriptions removeObjectAtIndex:subIdx];
    VCRecordAppEvent(@"subscription", @"Subscription deleted",
                     [NSString stringWithFormat:@"remaining=%lu", (unsigned long)[_subscriptions count]]);

    if (_expandedSubscription == subIdx) {
        _expandedSubscription = -1;
    } else if (_expandedSubscription > subIdx) {
        _expandedSubscription--;
    }
    if (_selectedSubIndex == subIdx) {
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
    } else if (_selectedSubIndex > subIdx) {
        _selectedSubIndex--;
    }
    [self normalizeSelection];
    [self saveData];
    return YES;
}

- (void)subscriptionInfoVCRequestedDelete:(SubscriptionInfoVC *)vc atIndex:(NSInteger)index {
    if (![self deleteSubscriptionAtIndex:index]) return;
    [self reloadMainTableDataAfterExternalChange];
    [self showStatus:@"Subscription deleted" ok:YES];
    [vc dismissViewControllerAnimated:YES completion:nil];
}

@end
