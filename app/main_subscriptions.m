#import "main_screen.h"
#import "settings.h"
#import "subscription_info.h"

static BOOL SubscriptionResponseIsForbidden(NSString *headers) {
    BOOL forbidden=NO;
    for (NSString *line in [headers componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        if (![line hasPrefix:@"HTTP/"]) continue;
        NSRange space=[line rangeOfString:@" "];
        NSUInteger start=NSMaxRange(space);
        forbidden=space.location!=NSNotFound && start<=[line length] && [line length]-start>=3 &&
            [[line substringWithRange:NSMakeRange(start,3)] isEqual:@"403"] &&
            ([line length]-start==3 || [line characterAtIndex:start+3]==' ' || [line characterAtIndex:start+3]=='\t');
    }
    return forbidden;
}

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
    NSDictionary *incy=nil;
    if (VCIncyIsLink(urlString)) {
        incy=VCIncySubscriptionDescriptor(urlString,errorTextOut);
        if (!incy) return nil;
        fetchURLString=[incy objectForKey:@"value"];
    }
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

    NSString *nameFromURL = incy ? ([[incy objectForKey:@"name"] length] ? [incy objectForKey:@"name"] : @"INCY subscription") : (useHappHeaders ? @"HAPP subscription" : [self subscriptionNameFromURLString:fetchURLString]);
    NSString *hostName = incy ? @"INCY subscription" : (useHappHeaders ? @"HAPP subscription" : [self hostFromURLString:fetchURLString]);
    NSString *nameFromMeta = nil;
    NSDictionary *userInfoFromMeta = nil;
    NSDictionary *metadataFromMeta = nil;
    BOOL allowInsecureFetch = SubscriptionDictionaryAllowsInsecureFetch(sub);
    BOOL allowPlainHTTP = SubscriptionDictionaryAllowsPlainHTTP(sub);

    NSString *fetchErr = nil;
    NSString *curlHeaders = nil;
    NSString *userAgent=VCSubscriptionUserAgent(sub,AppUserAgent());
    if (!VCSubscriptionUserAgentIsValid(userAgent)) {
        if (errorTextOut) *errorTextOut=@"Invalid subscription User-Agent. Open the subscription menu and choose Edit to change it.";
        return nil;
    }
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
    if (VCCurrentSubscriptionTask().isCancelled) { if (errorTextOut) *errorTextOut=VCCurrentSubscriptionTask().cancellationReason; return nil; }
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
            [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
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
        data = VCFetchSubscriptionRequest(req,20,&resp,&err);
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
        if (incy) fetchErr=VCIncySafeFetchError(fetchErr);
        if (SubscriptionDictionaryIsHappEncrypted(sub)) fetchErr=@"Could not download the encrypted HAPP subscription.";
        if (curlExitCode==22 && SubscriptionResponseIsForbidden(curlHeaders)) {
            fetchErr=@"HTTP 403. The server rejected the subscription download.";
        }
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
                                              options:VCCurrentSubscriptionTask() ?: self
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

- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus {
    if (idx < 0 || idx >= (NSInteger)[_subscriptions count]) return NO;
    if ([self isConnectionActionInProgress] || _subscriptionTask) {
        if (showStatus) [self showStatus:@"Busy" ok:NO];
        return NO;
    }
    [_pendingImportRefreshIndices release];
    _pendingImportRefreshIndices=[@[ @(idx) ] copy];
    [self startBackgroundSubscriptionRefresh];
    return NO;
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

- (void)startBackgroundSubscriptionRefresh {
    [self startBackgroundSubscriptionRefreshAllowPlainHTTP:NO];
}

- (void)startBackgroundSubscriptionRefreshAllowPlainHTTP:(BOOL)allowPlainHTTP {
    if ([_subscriptions count] == 0) {
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
        [_pendingImportRefreshIndices release];
        _pendingImportRefreshIndices = nil;
        if (updateInProgress) {
            [self showStatus:@"A subscription update is already running" ok:YES];
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
    if ([plainHTTPIndices count] > 0 && !allowPlainHTTP) {
        NSUInteger revision=_configurationRevision;
        [self showPlainHTTPSubscriptionWarningForCount:[plainHTTPIndices count] confirmation:^{
            if (revision != _configurationRevision) { [self showStatus:@"Update skipped: subscriptions changed" ok:NO]; return; }
            [self startBackgroundSubscriptionRefreshAllowPlainHTTP:YES];
        }];
        return;
    }

    NSArray *requestedIndices = nil;
    if (_pendingImportRefreshIndices && [_pendingImportRefreshIndices count] > 0) {
        requestedIndices = [_pendingImportRefreshIndices copy];
    }
    [_pendingImportRefreshIndices release];
    _pendingImportRefreshIndices = nil;

    NSMutableArray *approvedSubscriptions=[NSMutableArray arrayWithArray:_subscriptions];
    if (allowPlainHTTP) for (NSNumber *indexValue in plainHTTPIndices) {
        NSUInteger index=[indexValue unsignedIntegerValue];
        NSMutableDictionary *approved=[NSMutableDictionary dictionaryWithDictionary:[approvedSubscriptions objectAtIndex:index]];
        [approved setObject:@(YES) forKey:kSubscriptionAllowPlainHTTPKey];
        [approvedSubscriptions replaceObjectAtIndex:index withObject:approved];
    }
    NSArray *snapshot = [approvedSubscriptions copy];
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
        [self showStatus:@"No subscriptions to update" ok:NO];
        [snapshot release];
        return;
    }

    VCSubscriptionTask *task=[self beginSubscriptionTaskWithKind:VCSubscriptionTaskUpdate];
    if (!task) { [snapshot release]; return; }
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];

    NSArray *refreshIndices = [[NSArray alloc] initWithArray:refreshIndicesMutable];
    VCRecordAppEvent(@"subscription", @"Subscription update batch started",
                     [NSString stringWithFormat:@"requested=%lu", (unsigned long)[refreshIndices count]]);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        VCSubscriptionTask *previous=[VCSetCurrentSubscriptionTask(task) retain];
        @try {

        NSMutableArray *updatedSubs = [[NSMutableArray alloc] initWithArray:snapshot];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSMutableDictionary *failureCategories = [[NSMutableDictionary alloc] init];
        NSUInteger okCount = 0;
        for (NSNumber *idxObj in refreshIndices) {
            if (task.isCancelled) break;
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
            if (task != _subscriptionTask || task.isCancelled) {
                [self finishSubscriptionTask:task success:NO];
                [failureTexts release]; [failureCategories release]; [updatedSubs release]; [refreshIndices release]; [snapshot release]; return;
            }
            if (sourceRevision != _configurationRevision || ![self subscriptionsMatchSnapshotForLaunchAutoUpdate:snapshot]) {
                [self setUpdatingSubscriptionIndex:-1];
                _launchAutoUpdateInProgress=NO;
                [self setSubscriptionRefreshInProgress:NO];
                VCRecordAppEvent(@"subscription", @"Subscription update batch discarded",
                                 @"reason=list_changed_during_update");
                [self showStatus:@"Auto-update skipped: subscriptions changed" ok:YES];
                [self finishSubscriptionTask:task success:NO];
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
                [self finishSubscriptionTask:task success:NO];
                [failureTexts release]; [failureCategories release]; [updatedSubs release]; [refreshIndices release]; [snapshot release];
                return;
            }

            [self normalizeSelection];
            [self reloadMainTableDataAfterExternalChange];
            [self saveData];
            [self refreshPresentedSubscriptionInfoIfNeeded];

            BOOL ok = okCount > 0;
            [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
                              (unsigned long)okCount,
                              (unsigned long)[refreshIndices count]]
                         ok:ok];

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

            [self finishSubscriptionTask:task success:ok];
            [failureTexts release];
            [failureCategories release];
            [updatedSubs release];
            [refreshIndices release];
            [snapshot release];
            }];
        });

        } @finally { VCSetCurrentSubscriptionTask(previous); [previous release]; [pool drain]; }
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

    [self startBackgroundSubscriptionRefresh];
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
    if (self.presentedViewController) return;
    CGRect anchor=[sender convertRect:sender.bounds toView:self.view];
    VCSubscriptionMenu *menu=[[[VCSubscriptionMenu alloc] initWithSubscription:[_subscriptions objectAtIndex:index] anchor:anchor delegate:self] autorelease];
    [menu showInView:self.view];
}

- (NSInteger)indexForSubscriptionSnapshot:(NSDictionary *)subscription {
    NSInteger index=[self existingSubscriptionIndexForURL:[subscription objectForKey:@"url"]];
    return index>=0 && [[_subscriptions objectAtIndex:index] isEqual:subscription] ? index : -1;
}

- (void)subscriptionActionSheet:(VCSubscriptionActionSheet *)sheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex!=sheet.destructiveButtonIndex) return;
    NSInteger index=[self indexForSubscriptionSnapshot:sheet.subscription];
    if (index<0) { [self showStatus:@"Subscription changed; open its menu again" ok:NO]; return; }
    if (_subscriptionTask || _configurationDraft || [self isConnectionActionInProgress]) { [self showStatus:@"Wait for the current operation to finish" ok:NO]; return; }
    if ([self deleteSubscriptionAtIndex:index]) {
        [self reloadMainTableDataAfterExternalChange]; [self showStatus:@"Subscription deleted" ok:YES];
    }
}

- (void)subscriptionMenu:(VCSubscriptionMenu *)menu selectedAction:(VCSubscriptionMenuAction)action {
    NSInteger index=[self indexForSubscriptionSnapshot:menu.subscription];
    if (index<0) { [self showStatus:@"Subscription changed; open its menu again" ok:NO]; return; }
    NSDictionary *subscription=[_subscriptions objectAtIndex:index];
    if (action==VCSubscriptionMenuEdit) { [self presentSubscriptionEditorForSource:subscription]; return; }
    if (action==VCSubscriptionMenuUpdate) { [self refreshSubscriptionAtIndex:index showStatus:YES]; return; }
    if (action==VCSubscriptionMenuDelete) {
        VCSubscriptionActionSheet *confirmation=[[[VCSubscriptionActionSheet alloc] initWithSubscription:subscription delegate:self] autorelease];
        if (IsPadDevice()) [confirmation showFromRect:menu.anchor inView:self.view animated:YES];
        else [confirmation showInView:self.view];
        return;
    }
    if (action!=VCSubscriptionMenuInformation) return;
    SubscriptionInfoVC *info = [[[SubscriptionInfoVC alloc] initWithSubscription:subscription
                                                                           index:index
                                                                     stealthMode:_stealthModeEnabled] autorelease];
    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:info] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)presentSubscriptionEditorForSource:(NSDictionary *)subscription {
    SubscriptionEditVC *editor=[[[SubscriptionEditVC alloc] initWithSubscription:subscription stealthMode:_stealthModeEnabled delegate:self] autorelease];
    SettingsNavController *nav=[[[SettingsNavController alloc] initWithRootViewController:editor] autorelease];
    nav.modalPresentationStyle=UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)subscriptionEditVC:(SubscriptionEditVC *)vc requestedSave:(NSDictionary *)subscription {
    if ([self configurationMutationBlocked] || _configurationDraft || _subscriptionTask || [self isConnectionActionInProgress]) {
        [vc finishSavingWithSubscription:nil errorText:@"Wait for the current operation to finish."]; return;
    }
    NSInteger index=[self indexForSubscriptionSnapshot:vc.subscription];
    if (index<0) { [vc finishSavingWithSubscription:nil errorText:@"The subscription changed. Close the editor and open it again."]; return; }
    NSInteger duplicate=[self existingSubscriptionIndexForURL:[subscription objectForKey:@"url"]];
    if (duplicate>=0 && duplicate!=index) { [vc finishSavingWithSubscription:nil errorText:@"A subscription with this link already exists."]; return; }
    NSMutableArray *draft=[NSMutableArray arrayWithArray:_subscriptions];
    [draft replaceObjectAtIndex:index withObject:subscription];
    [self commitConfigurations:_configs subscriptions:draft completion:^(BOOL saved) {
        if (saved) {
            [self normalizeSelection]; [self saveData]; [self reloadMainTableDataAfterExternalChange];
            [self refreshPresentedSubscriptionInfoIfNeeded];
            [self showStatus:@"Subscription settings saved" ok:YES];
            VCRecordAppEvent(@"subscription",@"Subscription settings saved",nil);
        }
        [vc finishSavingWithSubscription:saved ? subscription : nil errorText:saved ? nil : @"The subscription was not saved. Previous settings are unchanged."];
    }];
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

- (void)subscriptionEditVC:(SubscriptionEditVC *)vc didSaveSubscription:(NSDictionary *)subscription {
    NSDictionary *source=vc.subscription;
    NSString *defaultAgent=AppUserAgent();
    BOOL changed=![[source objectForKey:@"url"] isEqual:[subscription objectForKey:@"url"]] ||
        ![VCSubscriptionUserAgent(source,defaultAgent) isEqual:VCSubscriptionUserAgent(subscription,defaultAgent)];
    if (!changed) return;
    NSInteger index=[self indexForSubscriptionSnapshot:subscription];
    if (index>=0) [self refreshSubscriptionAtIndex:index showStatus:YES];
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

@end
