#import "main_screen.h"

@implementation MainVC (VCMainState)

static BOOL gVCSecureStoreWritable = YES;

- (NSString *)safeTrim:(NSString *)s {
    return [VCProfiles() safeTrim:s];
}

- (NSString *)decodedFragmentFromURI:(NSString *)uri {
    return [[VCProfiles() metadataForURI:uri] objectForKey:@"title"];
}

- (NSString *)hostFromVLESSURI:(NSString *)uri {
    return [self hostFromConfigURI:uri];
}

- (NSString *)schemeFromURIString:(NSString *)uri {
    return [VCProfiles() schemeFromURIString:uri];
}

- (BOOL)parseSOCKS5Host:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    return [VCProfiles() parseSOCKS5Host:hostOut port:portOut fromURI:uri];
}

- (NSString *)hostFromConfigURI:(NSString *)uri {
    NSDictionary *metadata=[VCProfiles() metadataForURI:uri];
    return [metadata objectForKey:@"host"] ?: [metadata objectForKey:@"protocol"] ?: @"server";
}

- (NSString *)displayNameForURI:(NSString *)uri index:(NSInteger)index {
    NSString *name = [self decodedFragmentFromURI:uri];
    if (name) return name;

    NSString *host = [self hostFromConfigURI:uri];
    return [NSString stringWithFormat:@"Config %ld (%@)", (long)(index + 1), host];
}

- (NSString *)displayNameForSubscriptionURI:(NSString *)uri
                                      index:(NSInteger)index
                               subscription:(NSDictionary *)subscription {
    if (!SubscriptionDictionaryIsHappEncrypted(subscription)) {
        return [self displayNameForURI:uri index:index];
    }

    NSString *name = [self decodedFragmentFromURI:uri];
    return [name length] > 0 ? name : [NSString stringWithFormat:@"Config %ld", (long)(index + 1)];
}

- (NSString *)hostFromURLString:(NSString *)urlString {
    NSURL *u = [NSURL URLWithString:urlString];
    NSString *h = [u host];
    if (!h || [h length] == 0) return @"subscription";
    return h;
}

- (NSString *)decodedURLComponent:(NSString *)component {
    return [VCProfiles() decodedURLComponent:component];
}

- (NSString *)strictDecodedConfigQueryComponent:(NSString *)component {
    return [VCProfiles() strictDecodedConfigQueryComponent:component];
}

- (NSString *)canonicalConfigQueryKey:(NSString *)encodedKey {
    return [VCProfiles() canonicalConfigQueryKey:encodedKey];
}

- (NSString *)configURIQueryValidationReason:(NSString *)uri {
    return [VCProfiles() configURIQueryValidationReason:uri];
}

- (NSString *)queryValueForURLString:(NSString *)urlString key:(NSString *)key {
    return [VCProfiles() queryValueForURLString:urlString key:key];
}

- (NSString *)transportTypeFromURI:(NSString *)uri {
    return [VCProfiles() transportTypeFromURI:uri];
}

- (NSString *)securityTypeFromURI:(NSString *)uri {
    return [VCProfiles() securityTypeFromURI:uri];
}

- (NSString *)realityFlowFromURI:(NSString *)uri {
    return [VCProfiles() realityFlowFromURI:uri];
}

- (NSString *)realityFingerprintFromURI:(NSString *)uri {
    return [VCProfiles() realityFingerprintFromURI:uri];
}

- (BOOL)isSupportedRealityFingerprint:(NSString *)fp {
    return [VCProfiles() isSupportedRealityFingerprint:fp];
}

- (NSString *)subscriptionNameFromURLString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        return @"subscription";
    }

    NSArray *queryKeys = [NSArray arrayWithObjects:@"profile-title", @"title", @"name", @"subname", @"tag", @"remark", nil];
    for (NSString *key in queryKeys) {
        NSString *value = [self queryValueForURLString:urlString key:key];
        if ([value length] > 0) return value;
    }

    return [self hostFromURLString:urlString];
}

- (BOOL)isLikelyLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trim = [self safeTrim:text];
    if ([trim length] == 0) return NO;

    NSString *lower = [trim lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"vless://"] || [lower hasPrefix:@"socks5://"] || [lower hasPrefix:@"happ://"] || VCIncyIsLink(trim)) return YES;
    if ([trim rangeOfString:@"/"].location != NSNotFound) return YES;
    if ([trim rangeOfString:@"."].location != NSNotFound) return YES;
    if ([trim rangeOfString:@":"].location != NSNotFound) return YES;
    return NO;
}

- (NSString *)maskedLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *trim = [self safeTrim:text];
    NSUInteger len = [trim length];
    if (len == 0) return @"";

    if (!_stealthModeEnabled || ![self isLikelyLinkText:trim]) {
        return trim;
    }
    return kHiddenLinkText;
}

- (BOOL)isSubscriptionURL:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
}

- (BOOL)isVLESSURI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"vless://"];
}

- (BOOL)isSOCKS5URI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"socks5://"];
}

- (BOOL)isDirectConfigURI:(NSString *)s {
    return [VCProfiles() isConfigurationURI:[self safeTrim:s]];
}

- (void)saveMainState {
    if (_configurationLoading) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *lastSelection = nil;
    if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        lastSelection = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"config", @"kind",
                         [NSNumber numberWithInteger:_selectedConfigIndex], @"index",
                         nil];
    } else if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        lastSelection = [NSDictionary dictionaryWithObjectsAndKeys:
                         @"subscription", @"kind",
                         [NSNumber numberWithInteger:_selectedSubIndex], @"subscription_index",
                         [NSNumber numberWithInteger:_selectedSubItemIndex], @"item_index",
                         nil];
    }
    if (lastSelection) [ud setObject:lastSelection forKey:kDefaultsLastSelectionKey];
    else [ud removeObjectForKey:kDefaultsLastSelectionKey];
    [ud setBool:_configurationsSectionExpanded forKey:kDefaultsConfigurationsExpandedKey];
    [ud setBool:_subscriptionsSectionExpanded forKey:kDefaultsSubscriptionsExpandedKey];
    NSInteger expandedSubscription = _expandedSubscription;
    if (_reorderingSection == 1 && _subscriptionToReexpandAfterReorder) {
        NSUInteger index = [_subscriptions indexOfObjectIdenticalTo:_subscriptionToReexpandAfterReorder];
        expandedSubscription = (index == NSNotFound) ? -1 : (NSInteger)index;
    }
    [ud setInteger:expandedSubscription forKey:kDefaultsExpandedSubscriptionKey];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushMainStateDefaults)
                                               object:nil];
    [self performSelector:@selector(flushMainStateDefaults) withObject:nil afterDelay:0.5];
    [self updateConnectionSummary];
}

- (void)flushMainStateDefaults {
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)saveData {
    if (_configurationLoading) return;
    if (![_subscriptionPingOrder matchesItems:[self subscriptionItemsAtIndex:[self subscriptionRowsExpandedIndex]]]) {
        [_subscriptionPingOrder release];
        _subscriptionPingOrder = nil;
    }
    if (!_applyingConfigurationDraft && !_configurationCommitInProgress) {
        _configurationRevision++;
        [self prepareProfileMetadata];
        if (gVCSecureStoreWritable) {
            [self keepConfigurationWriteAlive];
            [_configurationWriter enqueueConfigurations:_configs subscriptions:_subscriptions revision:++_storeSequence target:self selector:@selector(configurationStoreFinished:) context:nil];
        }
    }
    [self saveSettings];
    [self updateMainEmptyState];
    [self refreshMainSwitcher];
}

- (void)saveSettings {
    if (_configurationLoading) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:_autoUpdateSubscriptions forKey:kDefaultsAutoUpdateSubsKey];
    [ud setBool:_preserveCustomSubscriptionNames forKey:kDefaultsPreserveCustomSubscriptionNamesKey];
    [ud setBool:_stealthModeEnabled forKey:kDefaultsStealthModeKey];
    [ud setBool:_darkThemeEnabled forKey:kDefaultsDarkThemeKey];
    [ud setBool:_automaticUpdateChecksEnabled forKey:kDefaultsAutomaticUpdateChecksKey];
    [self saveMainState];
}

- (void)loadData {
    _configurationLoading=YES;
    _configurationBackgroundTask=UIBackgroundTaskInvalid;
    _configurationQueue=dispatch_queue_create("com.vlesscore.configuration", DISPATCH_QUEUE_SERIAL);
    VCStoragePaths paths=VCMainStoragePaths();
    _configurationWriter=[[VCConfigurationStoreWriter alloc] initWithPaths:&paths];
    _configs=[[NSMutableArray alloc] init];
    _subscriptions=[[NSMutableArray alloc] init];
    _selectedConfigIndex=_selectedSubIndex=_selectedSubItemIndex=_expandedSubscription=-1;
    _updatingSubscriptionIndex=_reorderingSection=-1;
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    _autoUpdateSubscriptions=[defaults objectForKey:kDefaultsAutoUpdateSubsKey] ? [defaults boolForKey:kDefaultsAutoUpdateSubsKey] : YES;
    _preserveCustomSubscriptionNames=[defaults boolForKey:kDefaultsPreserveCustomSubscriptionNamesKey];
    _sortSubscriptionsByPing=[defaults boolForKey:kDefaultsSortSubscriptionsByPingKey];
    _stealthModeEnabled=[defaults boolForKey:kDefaultsStealthModeKey];
    _darkThemeEnabled=[defaults boolForKey:kDefaultsDarkThemeKey];
    _automaticUpdateChecksEnabled=[defaults objectForKey:kDefaultsAutomaticUpdateChecksKey] ? [defaults boolForKey:kDefaultsAutomaticUpdateChecksKey] : YES;
    NSArray *legacyConfigs=[[defaults objectForKey:kDefaultsConfigsKey] retain];
    NSArray *legacySubscriptions=[[defaults objectForKey:kDefaultsSubsKey] retain];
    BOOL writable=gVCSecureStoreWritable;
    dispatch_async(_configurationQueue, ^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        BOOL exists=NO;
        NSDictionary *protectedData=VCLoadProtectedConfigurationData(&exists);
        VCConfigurationDataSelection selected=VCInitialConfigurationData(protectedData,exists,legacyConfigs,legacySubscriptions,writable);
        NSArray *configs=selected.configs ?: @[],*subscriptions=selected.subscriptions ?: @[];
        BOOL migrated=NO;
        if (!protectedData && selected.writable && (legacyConfigs || legacySubscriptions)) migrated=VCSaveProtectedConfigurationData(configs,subscriptions);
        NSDictionary *metadata=[VCProfiles() preparedMetadataForConfigurations:configs subscriptions:subscriptions additionalMetadata:nil];
        NSDictionary *loaded=[[NSDictionary alloc] initWithObjectsAndKeys:configs,@"configs",subscriptions,@"subscriptions",metadata,@"metadata",@(selected.writable),@"writable",@(protectedData != nil),@"secure",@(migrated),@"migrated",nil];
        dispatch_async(dispatch_get_main_queue(), ^{ [self completeConfigurationLoad:loaded]; [loaded release]; });
        [legacyConfigs release]; [legacySubscriptions release]; [pool drain];
    });
}

- (void)completeConfigurationLoad:(NSDictionary *)loaded {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *legacyConfigs = [ud objectForKey:kDefaultsConfigsKey];
    NSArray *legacySubscriptions = [ud objectForKey:kDefaultsSubsKey];
    NSArray *cfg=[loaded objectForKey:@"configs"],*subs=[loaded objectForKey:@"subscriptions"];
    gVCSecureStoreWritable=[[loaded objectForKey:@"writable"] boolValue];
    [_configs release]; [_subscriptions release];

    if ([cfg isKindOfClass:[NSArray class]]) {
        _configs = [[NSMutableArray alloc] initWithArray:cfg];
    } else {
        _configs = [[NSMutableArray alloc] init];
    }

    if ([subs isKindOfClass:[NSArray class]]) {
        _subscriptions = [[NSMutableArray alloc] initWithArray:subs];
    } else {
        _subscriptions = [[NSMutableArray alloc] init];
    }

    [VCProfiles() installPreparedMetadata:[loaded objectForKey:@"metadata"]];

    if ([[loaded objectForKey:@"secure"] boolValue] &&
        ([legacyConfigs isKindOfClass:[NSArray class]] || [legacySubscriptions isKindOfClass:[NSArray class]])) {
        [ud removeObjectForKey:kDefaultsConfigsKey];
        [ud removeObjectForKey:kDefaultsSubsKey];
        [ud synchronize];
    } else if ([[loaded objectForKey:@"migrated"] boolValue]) {
        [ud removeObjectForKey:kDefaultsConfigsKey];
        [ud removeObjectForKey:kDefaultsSubsKey];
        [ud synchronize];
    }

    if ([ud objectForKey:kDefaultsAutoUpdateSubsKey] == nil) {
        _autoUpdateSubscriptions = YES;
    } else {
        _autoUpdateSubscriptions = [ud boolForKey:kDefaultsAutoUpdateSubsKey];
    }

    _preserveCustomSubscriptionNames = [ud boolForKey:kDefaultsPreserveCustomSubscriptionNamesKey];
    _sortSubscriptionsByPing = [ud boolForKey:kDefaultsSortSubscriptionsByPingKey];

    if ([ud objectForKey:kDefaultsStealthModeKey] == nil) {
        _stealthModeEnabled = NO;
    } else {
        _stealthModeEnabled = [ud boolForKey:kDefaultsStealthModeKey];
    }

    _darkThemeEnabled = [ud boolForKey:kDefaultsDarkThemeKey];

    if ([ud objectForKey:kDefaultsAutomaticUpdateChecksKey] == nil) {
        _automaticUpdateChecksEnabled = YES;
    } else {
        _automaticUpdateChecksEnabled = [ud boolForKey:kDefaultsAutomaticUpdateChecksKey];
    }

    _selectedConfigIndex = -1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    NSNumber *savedExpandedValue = [ud objectForKey:kDefaultsExpandedSubscriptionKey];
    NSInteger savedExpandedSubscription = [savedExpandedValue isKindOfClass:[NSNumber class]]
        ? [savedExpandedValue integerValue] : -1;
    _expandedSubscription = (savedExpandedSubscription >= 0 &&
                             savedExpandedSubscription < (NSInteger)[_subscriptions count])
        ? savedExpandedSubscription : -1;
    _updatingSubscriptionIndex = -1;
    _reorderingSection = -1;
    BOOL savedConfigurations = [ud boolForKey:kDefaultsConfigurationsExpandedKey];
    BOOL savedSubscriptions = [ud boolForKey:kDefaultsSubscriptionsExpandedKey];

    NSDictionary *lastSelection = [ud objectForKey:kDefaultsLastSelectionKey];
    NSString *selectionKind = [lastSelection isKindOfClass:[NSDictionary class]]
        ? [lastSelection objectForKey:@"kind"] : nil;
    if ([selectionKind isEqualToString:@"config"]) {
        NSInteger index = [[lastSelection objectForKey:@"index"] integerValue];
        if (index >= 0 && index < (NSInteger)[_configs count]) _selectedConfigIndex = index;
    } else if ([selectionKind isEqualToString:@"subscription"]) {
        NSInteger subIndex = [[lastSelection objectForKey:@"subscription_index"] integerValue];
        if (subIndex >= 0 && subIndex < (NSInteger)[_subscriptions count]) {
            NSDictionary *subscription = [_subscriptions objectAtIndex:subIndex];
            NSArray *items = [subscription objectForKey:@"items"];
            if (![items isKindOfClass:[NSArray class]]) items = [NSArray array];
            NSInteger itemIndex = [[lastSelection objectForKey:@"item_index"] integerValue];
            _selectedSubIndex = subIndex;
            _selectedSubItemIndex = ([items count] == 0) ? -1
                : ((itemIndex >= 0 && itemIndex < (NSInteger)[items count]) ? itemIndex : 0);
        }
    }
    if (_selectedConfigIndex < 0 && _selectedSubIndex < 0 && [_configs count] > 0) {
        _selectedConfigIndex = 0;
    }
    _subscriptionsSectionExpanded = (savedConfigurations == savedSubscriptions)
        ? (_selectedSubIndex >= 0) : savedSubscriptions;
    _configurationsSectionExpanded = !_subscriptionsSectionExpanded;
    VCRecordAppEvent(@"storage",
                     @"Configuration store loaded",
                     [NSString stringWithFormat:@"configs=%lu subscriptions=%lu secure=%d writable=%d",
                      (unsigned long)[_configs count],
                      (unsigned long)[_subscriptions count],
                      [[loaded objectForKey:@"secure"] boolValue] ? 1 : 0,
                      gVCSecureStoreWritable ? 1 : 0]);
    _configurationLoading=NO;
    _plusBtn.enabled=YES; _refreshBtn.enabled=YES; _settingsBtn.enabled=YES;
    [self normalizeSelection];
    [self reloadMainTableDataAfterExternalChange];
    [self updateConnectButton];
    [self showStatus:gVCSecureStoreWritable ? (_connected ? @"Connected" : @"Ready") : @"Configuration store is unavailable" ok:gVCSecureStoreWritable];
    if (_deferredImportURL) {
        NSURL *url=[_deferredImportURL autorelease]; _deferredImportURL=nil;
        [self importFileAtURL:url];
    } else [self startLaunchAutoUpdateIfNeeded];
}

- (void)profileMetadataPrepared:(NSDictionary *)metadata {
    if (![metadata count]) return;
    @synchronized(self) {
        if (!_pendingProfileMetadata) _pendingProfileMetadata=[[NSMutableDictionary alloc] init];
        [_pendingProfileMetadata addEntriesFromDictionary:metadata];
    }
}

- (void)prepareProfileMetadata {
    _metadataRevision++;
    if (_metadataPreparationRunning) { _metadataPreparationPending=YES; return; }
    _metadataPreparationRunning=YES;
    _metadataPreparationPending=NO;
    NSUInteger revision=_metadataRevision;
    NSArray *configs=[_configs copy],*subscriptions=[_subscriptions copy];
    NSDictionary *additional=nil;
    @synchronized(self) { additional=_pendingProfileMetadata; _pendingProfileMetadata=nil; }
    dispatch_async(_configurationQueue, ^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        NSDictionary *metadata=[[VCProfiles() preparedMetadataForConfigurations:configs subscriptions:subscriptions additionalMetadata:additional] retain];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (revision == _metadataRevision) [VCProfiles() installPreparedMetadata:metadata];
            _metadataPreparationRunning=NO;
            if (_metadataPreparationPending) [self prepareProfileMetadata];
            [metadata release];
        });
        [additional release]; [configs release]; [subscriptions release]; [pool drain];
    });
}

- (BOOL)configurationMutationBlocked {
    return _configurationLoading || _configurationCommitInProgress;
}

- (void)keepConfigurationWriteAlive {
    if (_configurationBackgroundTask != UIBackgroundTaskInvalid) return;
    _configurationBackgroundTask=[[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        if (_configurationBackgroundTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:_configurationBackgroundTask];
            _configurationBackgroundTask=UIBackgroundTaskInvalid;
        }
    }];
}

- (void)commitConfigurations:(NSArray *)configs subscriptions:(NSArray *)subscriptions completion:(void (^)(BOOL))completion {
    if (_configurationLoading || _configurationDraft || !gVCSecureStoreWritable) {
        if (completion) completion(NO);
        return;
    }
    _configurationDraftCompletion=completion ? Block_copy(completion) : NULL;
    NSUInteger token=++_configurationDraftToken,revision=_configurationRevision;
    NSArray *configSnapshot=[configs copy],*subscriptionSnapshot=[subscriptions copy];
    _configurationDraft=[[NSDictionary alloc] initWithObjectsAndKeys:configSnapshot,@"configs",subscriptionSnapshot,@"subscriptions",nil];
    NSDictionary *additional=nil;
    @synchronized(self) { additional=_pendingProfileMetadata; _pendingProfileMetadata=nil; }
    VCSubscriptionTask *task=[_subscriptionTask retain];
    NSDictionary *taskMetadata=[[task takePreparedMetadata] retain];
    dispatch_async(_configurationQueue, ^{
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        VCSubscriptionTask *previous=[VCSetCurrentSubscriptionTask(task) retain];
        NSMutableDictionary *combined=[NSMutableDictionary dictionaryWithDictionary:additional ?: @{}];
        if (taskMetadata) [combined addEntriesFromDictionary:taskMetadata];
        NSDictionary *metadata=[[VCProfiles() preparedMetadataForConfigurations:configSnapshot subscriptions:subscriptionSnapshot additionalMetadata:combined] retain];
        VCSetCurrentSubscriptionTask(previous); [previous release];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (token == _configurationDraftToken && _configurationDraft) {
                if (revision != _configurationRevision || !metadata || (task && ![task beginCommit])) [self finishConfigurationDraft:NO];
                else {
                    NSMutableDictionary *draft=[[_configurationDraft mutableCopy] autorelease];
                    [draft setObject:metadata forKey:@"metadata"];
                    [_configurationDraft release]; _configurationDraft=[draft copy];
                    _configurationCommitInProgress=YES;
                    _plusBtn.enabled=NO; _settingsBtn.enabled=NO; _refreshBtn.enabled=NO;
                    [self setMainReorderingSection:-1 showStatus:NO];
                    [self subscriptionTaskProgress:task];
                    [self keepConfigurationWriteAlive];
                    if (![_configurationWriter enqueueConfigurations:configSnapshot subscriptions:subscriptionSnapshot revision:++_storeSequence target:self selector:@selector(configurationStoreFinished:) context:@(token)]) [self finishConfigurationDraft:NO];
                }
            }
            [metadata release];
        });
        [taskMetadata release]; [task release]; [additional release]; [configSnapshot release]; [subscriptionSnapshot release]; [pool drain];
    });
}

- (void)configurationStoreFinished:(NSDictionary *)result {
    BOOL saved=[[result objectForKey:@"saved"] boolValue];
    id context=[result objectForKey:@"context"];
    if ([context isKindOfClass:[NSNumber class]]) {
        if ([context unsignedIntegerValue] == _configurationDraftToken && _configurationDraft) [self finishConfigurationDraft:saved];
    } else if (!saved && [[result objectForKey:@"revision"] unsignedLongLongValue] == _storeSequence) [self showStatus:@"Configuration store save failed" ok:NO];
    if (saved) {
        NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
        [defaults removeObjectForKey:kDefaultsConfigsKey]; [defaults removeObjectForKey:kDefaultsSubsKey];
    }
    VCRecordAppEvent(@"storage",saved ? @"Configuration store saved" : @"Configuration store save failed",nil);
    if ([[result objectForKey:@"idle"] boolValue] && _configurationWriter.isIdle && _configurationBackgroundTask != UIBackgroundTaskInvalid) {
        [[UIApplication sharedApplication] endBackgroundTask:_configurationBackgroundTask];
        _configurationBackgroundTask=UIBackgroundTaskInvalid;
    }
}

- (void)finishConfigurationDraft:(BOOL)saved {
    BOOL cancelled=_subscriptionTask.isCancelled;
    if (saved) {
        [_configs release]; _configs=[[_configurationDraft objectForKey:@"configs"] mutableCopy];
        [_subscriptions release]; _subscriptions=[[_configurationDraft objectForKey:@"subscriptions"] mutableCopy];
        [_subscriptionPingOrder release]; _subscriptionPingOrder=nil;
        [VCProfiles() installPreparedMetadata:[_configurationDraft objectForKey:@"metadata"]];
        _configurationRevision++; _metadataRevision++;
    }
    [_configurationDraft release]; _configurationDraft=nil;
    _configurationCommitInProgress=NO;
    _plusBtn.enabled=YES; _settingsBtn.enabled=YES; _refreshBtn.enabled=YES;
    void (^completion)(BOOL)=_configurationDraftCompletion; _configurationDraftCompletion=NULL;
    _applyingConfigurationDraft=saved;
    if (completion) { completion(saved); Block_release(completion); }
    if (saved) [self saveData];
    else if (!cancelled) [self showStatus:@"Import was not saved; previous configurations are unchanged" ok:NO];
    _applyingConfigurationDraft=NO;
}

- (NSArray *)subscriptionItemsAtIndex:(NSInteger)subIdx {
    return VCSubscriptionItemsAtIndex(_subscriptions, subIdx);
}

- (NSInteger)subscriptionRowsExpandedIndex {
    return _subscriptionExpansionOverridesActive
        ? _subscriptionRowsExpandedOverride
        : _expandedSubscription;
}

- (NSInteger)subscriptionHeaderExpandedIndex {
    return _subscriptionExpansionOverridesActive
        ? _subscriptionHeaderExpandedOverride
        : _expandedSubscription;
}

- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return nil;
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    NSString *url = [sub objectForKey:@"url"];
    if ([url isKindOfClass:[NSString class]] && [url length] > 0) {
        return [@"url:" stringByAppendingString:url];
    }
    return [NSString stringWithFormat:@"object:%p", (void *)sub];
}

- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return NO;
    for (NSDictionary *start in _pingNetworkStarts)
        if ([[start objectForKey:@"identifier"] isEqual:identifier]) return YES;
    return [_subscriptionPingTokenByIdentifier objectForKey:identifier] != nil;
}

- (NSInteger)subscriptionSectionRowCount {
    return VCSubscriptionRowCount(_subscriptions, [self subscriptionRowsExpandedIndex]);
}

- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)subIndex itemIndex:(NSInteger *)itemIndex isHeader:(BOOL *)isHeader {
    NSInteger sub = -1, item = -1;
    BOOL header = YES;
    if (!VCMapSubscriptionRow(_subscriptions, [self subscriptionRowsExpandedIndex], row, &sub, &item, &header)) return NO;
    if (!header) {
        NSArray *items = [self subscriptionItemsAtIndex:sub];
        if (![_subscriptionPingOrder matchesItems:items]) {
            [_subscriptionPingOrder release];
            _subscriptionPingOrder = [[VCSubscriptionPingOrder alloc] initWithItems:items displays:_sortSubscriptionsByPing ? _pingDisplayByURI : nil];
        }
        item = [_subscriptionPingOrder sourceIndexForDisplayIndex:item];
        if (item < 0) return NO;
    }
    if (subIndex) *subIndex = sub;
    if (itemIndex) *itemIndex = item;
    if (isHeader) *isHeader = header;
    return YES;
}

- (void)scheduleSubscriptionPingSort {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applySubscriptionPingSort) object:nil];
    if (_sortSubscriptionsByPing || _subscriptionPingOrder)
        [self performSelector:@selector(applySubscriptionPingSort) withObject:nil afterDelay:0.1];
}

- (void)applySubscriptionPingSort {
    if (_sortSubscriptionsByPing && [self isSubscriptionPingInProgressAtIndex:[self subscriptionRowsExpandedIndex]]) return;
    if (_tableView.editing) return;
    if (_mainSectionTransitionInProgress || _mainTabTransitionInProgress ||
        _tableView.dragging || _tableView.decelerating) {
        [self scheduleSubscriptionPingSort];
        return;
    }
    NSArray *items = [self subscriptionItemsAtIndex:[self subscriptionRowsExpandedIndex]];
    if (!_subscriptionsSectionExpanded || ![_subscriptionPingOrder matchesItems:items]) {
        [_subscriptionPingOrder release];
        _subscriptionPingOrder = nil;
        return;
    }
    if ([_subscriptionPingOrder updateWithDisplays:_sortSubscriptionsByPing ? _pingDisplayByURI : nil]) {
        [_tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)subIdx {
    return VCSubscriptionHeaderRow(_subscriptions, [self subscriptionRowsExpandedIndex], subIdx);
}

- (void)setUpdatingSubscriptionIndex:(NSInteger)subIdx {
    if (_updatingSubscriptionIndex == subIdx) return;

    NSInteger oldIdx = _updatingSubscriptionIndex;
    _updatingSubscriptionIndex = subIdx;

    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSInteger oldRow = [self rowForSubscriptionHeaderAtIndex:oldIdx];
    if (oldRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:oldRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            BOOL expanded = [self subscriptionHeaderExpandedIndex] == oldIdx;
            cell.accessoryView = [self subscriptionHeaderAccessoryExpanded:expanded loading:NO];
        }
    }

    NSInteger newRow = [self rowForSubscriptionHeaderAtIndex:subIdx];
    if (newRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:newRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            BOOL expanded = [self subscriptionHeaderExpandedIndex] == subIdx;
            cell.accessoryView = [self subscriptionHeaderAccessoryExpanded:expanded loading:YES];
        }
    }
}

- (void)normalizeSelection {
    VCNormalizeSelection([_configs count], _subscriptions, &_selectedConfigIndex, &_selectedSubIndex, &_selectedSubItemIndex);
}

- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    return [VCProfiles() parseVLESSHost:hostOut port:portOut fromURI:uri];
}

- (NSString *)endpointFromConfigURI:(NSString *)uri {
    NSDictionary *metadata=[VCProfiles() metadataForURI:uri];
    NSString *host=[metadata objectForKey:@"host"];
    NSNumber *port=[metadata objectForKey:@"port"];
    if (![host length]) return @"server";
    if ([host rangeOfString:@":"].location != NSNotFound) host=[NSString stringWithFormat:@"[%@]",host];
    return port ? [NSString stringWithFormat:@"%@:%u",host,[port unsignedIntValue]] : host;
}

- (NSString *)configSecondaryTextFromURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *endpoint = [self configEndpointTextFromURI:uri];
    if ([prefix length] == 0) return endpoint;
    if ([endpoint length] == 0) return prefix;
    return [NSString stringWithFormat:@"%@ %@", prefix, endpoint];
}

- (NSString *)configPrefixTextFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"[socks5]";

    NSString *transport = [self transportTypeFromURI:uri];
    NSString *security = [self securityTypeFromURI:uri];
    return [NSString stringWithFormat:@"[%@/%@/%@]", scheme, transport, security];
}

- (NSString *)configEndpointTextFromURI:(NSString *)uri {
    NSString *endpoint = [self endpointFromConfigURI:uri];
    return [self maskedLinkText:endpoint];
}

- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri {
    return [VCProfiles() unsupportedConfigReasonForURI:uri];
}

- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri {
    return [VCProfiles() isSupportedConfigTupleForURI:uri];
}

- (UIColor *)configPrefixColorForURI:(NSString *)uri {
    if ([self isSupportedConfigTupleForURI:uri]) {
        return VCSecondaryTextColor();
    }
    return VCErrorColor();
}

- (NSString *)unsupportedConfigStatusTextForURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    if (![prefix isKindOfClass:[NSString class]] || [prefix length] == 0) {
        prefix = @"[unknown]";
    }
    NSString *reason = [self unsupportedConfigReasonForURI:uri];
    if ([reason length] > 0) {
        return [NSString stringWithFormat:@"Error: unsupported config %@ (%@)",
                prefix,
                reason];
    }
    return [NSString stringWithFormat:@"Error: unsupported config %@",
            prefix];
}

@end
