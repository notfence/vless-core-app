#import "main_screen.h"
#import "qr_scanner.h"
#import "import_browser.h"

@implementation MainVC (VCMainImport)

- (NSArray *)extractConfigURIsFromText:(NSString *)text {
    return [VCProfiles() extractConfigURIsFromText:text];
}

- (NSArray *)extractImportLinksFromText:(NSString *)text {
    return [VCProfiles() extractImportLinksFromText:text];
}

- (NSString *)happJSONStringValue:(id)value {
    return [VCProfiles() happJSONStringValue:value];
}

- (NSDictionary *)happJSONDictionaryValue:(id)value {
    return [VCProfiles() happJSONDictionaryValue:value];
}

- (NSArray *)happJSONArrayValue:(id)value {
    return [VCProfiles() happJSONArrayValue:value];
}

- (NSString *)percentEncodedHappURIValue:(NSString *)value {
    return [VCProfiles() percentEncodedHappURIValue:value];
}

- (NSString *)happJSONStringFromDictionary:(NSDictionary *)dictionary {
    return [VCProfiles() happJSONStringFromDictionary:dictionary];
}

- (void)addHappURIQueryValue:(NSString *)value key:(NSString *)key toParts:(NSMutableArray *)parts {
    [VCProfiles() addHappURIQueryValue:value key:key toParts:parts];
}

- (NSString *)vlessURIFromHappJSONConfig:(NSDictionary *)config {
    return [VCProfiles() vlessURIFromHappJSONConfig:config];
}

- (NSArray *)extractConfigURIsFromHappJSONData:(NSData *)data {
    return [VCProfiles() extractConfigURIsFromHappJSONData:data];
}

- (NSArray *)parseSubscriptionData:(NSData *)data {
    return [VCProfiles() parseSubscriptionData:data];
}

- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri {
    return [VCProfiles() isLikelySubscriptionPlaceholderURI:uri];
}

- (NSArray *)sanitizeSubscriptionURIs:(NSArray *)uris {
    return [VCProfiles() sanitizeSubscriptionURIs:uris];
}

- (NSInteger)existingConfigIndexForURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_configs count]; i++) {
        NSDictionary *it = [_configs objectAtIndex:i];
        NSString *existingURI = [it objectForKey:@"uri"];
        if ([existingURI isKindOfClass:[NSString class]] && [existingURI isEqualToString:uri]) {
            return i;
        }
    }
    return -1;
}

- (NSInteger)existingSubscriptionIndexForURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *it = [_subscriptions objectAtIndex:i];
        NSString *existingURL = [it objectForKey:@"url"];
        if ([existingURL isKindOfClass:[NSString class]] && [existingURL isEqualToString:urlString]) {
            return i;
        }
    }
    return -1;
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                 allowPlainHTTP:(BOOL)allowPlainHTTP
                                     happSource:(BOOL)happSource {
    NSString *name = happSource ? @"HAPP subscription" : [self subscriptionNameFromURLString:urlString];
    NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                name, @"name",
                                urlString, @"url",
                                [NSArray array], @"items",
                                nil];
    if (allowInsecureFetch) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
    }
    if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(urlString)) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
    }
    if (happSource) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
    }
    return sub;
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString
                             allowInsecureFetch:(BOOL)allowInsecureFetch
                                     happSource:(BOOL)happSource {
    return [self subscriptionDictionaryForURL:urlString
                           allowInsecureFetch:allowInsecureFetch
                               allowPlainHTTP:NO
                                   happSource:happSource];
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    return [self subscriptionDictionaryForURL:urlString
                           allowInsecureFetch:allowInsecureFetch
                                   happSource:NO];
}

- (void)selectSubscriptionAtIndex:(NSInteger)subIndex {
    _subscriptionsSectionExpanded = YES;
    _configurationsSectionExpanded = NO;
    _expandedSubscription = subIndex;
    _selectedConfigIndex = -1;
    _selectedSubIndex = subIndex;
    _selectedSubItemIndex = 0;
    [self normalizeSelection];
    [self saveMainState];
    [_tableView reloadData];
}

- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation {
    [self showPlainHTTPSubscriptionWarningForCount:count
                                      confirmation:confirmation
                                        cancellation:nil];
}

- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count
                                      confirmation:(void (^)(void))confirmation
                                        cancellation:(void (^)(void))cancellation {
    if (!confirmation || count == 0) return;

    if (_pendingPlainHTTPConfirmation) {
        Block_release(_pendingPlainHTTPConfirmation);
        _pendingPlainHTTPConfirmation = NULL;
    }
    if (_pendingPlainHTTPCancellation) {
        Block_release(_pendingPlainHTTPCancellation);
        _pendingPlainHTTPCancellation = NULL;
    }
    _pendingPlainHTTPConfirmation = Block_copy(confirmation);
    if (cancellation) _pendingPlainHTTPCancellation = Block_copy(cancellation);

    NSString *message = count == 1
        ? @"This subscription uses unencrypted HTTP. Its access token and configurations can be read or changed by anyone on the network. Continue and allow HTTP for this subscription?"
        : [NSString stringWithFormat:@"%lu subscriptions use unencrypted HTTP. Their access tokens and configurations can be read or changed by anyone on the network. Continue and allow HTTP for them?",
                                     (unsigned long)count];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Unencrypted Subscription"
                                                    message:message
                                                   delegate:self
                                          cancelButtonTitle:@"Cancel"
                                          otherButtonTitles:@"Continue", nil] autorelease];
    alert.tag = VCAlertTagPlainHTTPSubscription;
    [alert show];
    [self showStatus:@"HTTP subscription requires confirmation" ok:NO];
}

- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings
                                    fromBatchImport:(BOOL)fromBatchImport
                                         happSource:(BOOL)happSource {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        VCRecordAppEvent(@"import", @"Batch subscription import rejected", @"reason=no_valid_entries");
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    [_pendingInsecureImportURLs release];
    _pendingInsecureImportURLs = [cleanURLs copy];
    _pendingInsecureImportUsesHappHeaders = happSource;

    NSUInteger count = [cleanURLs count];
    NSString *detail = nil;
    if (!fromBatchImport && count == 1) {
        detail = @"This subscription cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for this subscription. Continue?";
    } else {
        detail = @"One of your subscriptions cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for subscriptions that need it. Continue?";
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Warning"
                                                  message:detail
                                                 delegate:self
                                        cancelButtonTitle:@"No"
                                        otherButtonTitles:@"Yes", nil] autorelease];
    av.tag = VCAlertTagImportInsecureSubscription;
    [av show];
    [self showStatus:((!fromBatchImport && count == 1) ? @"Subscription requires insecure fetch confirmation"
                                                       : @"Some subscriptions require insecure fetch confirmation")
                  ok:NO];
}

- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings fromBatchImport:(BOOL)fromBatchImport {
    [self showInsecureSubscriptionImportPromptForURLs:urlStrings
                                      fromBatchImport:fromBatchImport
                                           happSource:NO];
}

- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString {
    [self showInsecureSubscriptionImportPromptForURLs:[NSArray arrayWithObject:urlString] fromBatchImport:NO];
}

- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString happSource:(BOOL)happSource {
    [self showInsecureSubscriptionImportPromptForURLs:[NSArray arrayWithObject:urlString]
                                      fromBatchImport:NO
                                           happSource:happSource];
}

- (void)commitUpdatedSubscription:(NSDictionary *)updated existingIndex:(NSInteger)existingIndex {
    if (![updated isKindOfClass:[NSDictionary class]]) return;

    NSArray *uris = [updated objectForKey:@"items"];
    NSInteger subIndex = existingIndex;
    if (existingIndex >= 0 && existingIndex < (NSInteger)[_subscriptions count]) {
        [_subscriptions replaceObjectAtIndex:existingIndex withObject:updated];
    } else {
        [_subscriptions addObject:updated];
        subIndex = [_subscriptions count] - 1;
    }

    [self saveData];
    [self showProfileImportWarnings:@[updated]];
    VCRecordAppEvent(@"subscription",
                     existingIndex >= 0 ? @"Subscription replaced" : @"Subscription added",
                     [NSString stringWithFormat:@"configs=%lu subscriptions=%lu",
                      (unsigned long)[uris count],
                      (unsigned long)[_subscriptions count]]);
    [self selectSubscriptionAtIndex:subIndex];

    NSString *verb = (existingIndex >= 0) ? @"updated" : @"imported";
    [self showStatus:[NSString stringWithFormat:@"Subscription %@ (%lu configs)",
                      verb,
                      (unsigned long)[uris count]]
                 ok:YES];
}

- (NSString *)subscriptionImportCountText:(NSUInteger)count {
    return [NSString stringWithFormat:@"%lu subscription%@",
            (unsigned long)count,
            (count == 1 ? @"" : @"s")];
}

- (NSString *)shortSubscriptionFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText defaultReason:(NSString *)defaultReason {
    NSString *host = [self hostFromURLString:urlString];
    if (![host isKindOfClass:[NSString class]] || [host length] == 0) {
        host = @"subscription";
    }

    NSString *reason = [self safeTrim:errorText];
    NSString *prefix = @"Subscription fetch failed: ";
    if ([reason hasPrefix:prefix] && [reason length] > [prefix length]) {
        reason = [reason substringFromIndex:[prefix length]];
    }
    if ([reason length] == 0) {
        reason = ([defaultReason isKindOfClass:[NSString class]] && [defaultReason length] > 0)
                     ? defaultReason
                     : @"failed";
    }
    if ([reason length] > 120) {
        reason = [[reason substringToIndex:120] stringByAppendingString:@"..."];
    }

    return [NSString stringWithFormat:@"%@: %@", host, reason];
}

- (NSString *)shortImportFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText {
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"import failed"];
}

- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText {
    NSString *urlString = [sub objectForKey:@"url"];
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"update failed"];
}

- (void)showSubscriptionFailureAlertWithTitle:(NSString *)title failureTexts:(NSArray *)failureTexts {
    if (![failureTexts isKindOfClass:[NSArray class]] || [failureTexts count] == 0) return;

    NSMutableString *message = [NSMutableString string];
    NSUInteger limit = MIN((NSUInteger)[failureTexts count], (NSUInteger)5);
    for (NSUInteger i = 0; i < limit; i++) {
        id obj = [failureTexts objectAtIndex:i];
        if (![obj isKindOfClass:[NSString class]] || [(NSString *)obj length] == 0) continue;
        if ([message length] > 0) [message appendString:@"\n"];
        [message appendFormat:@"- %@", (NSString *)obj];
    }
    if ([failureTexts count] > limit) {
        [message appendFormat:@"\n- ... and %lu more", (unsigned long)([failureTexts count] - limit)];
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil] autorelease];
    [av show];
}

- (void)showSubscriptionImportFailures:(NSArray *)failureTexts {
    [self showSubscriptionFailureAlertWithTitle:@"Some subscriptions were not imported" failureTexts:failureTexts];
}

- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts {
    NSString *title = ([failureTexts count] == 1) ? @"Subscription was not updated" : @"Some subscriptions were not updated";
    [self showSubscriptionFailureAlertWithTitle:title failureTexts:failureTexts];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart {
    [self startBackgroundSubscriptionImportForURLs:urlStrings
                               allowInsecureFetch:allowInsecureFetch
                                      startStatus:startStatus
                               importedPrefixPart:importedPrefixPart
                      fallbackSubscriptionsByURL:nil];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL {
    [self startBackgroundSubscriptionImportForURLs:urlStrings
                               allowInsecureFetch:allowInsecureFetch
                                      startStatus:startStatus
                               importedPrefixPart:importedPrefixPart
                      fallbackSubscriptionsByURL:fallbackSubscriptionsByURL
                                   allowPlainHTTP:NO];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart
                     fallbackSubscriptionsByURL:(NSDictionary *)fallbackSubscriptionsByURL
                                  allowPlainHTTP:(BOOL)allowPlainHTTP {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        [self showStatus:@"No subscriptions to import" ok:NO];
        return;
    }

    if (!allowPlainHTTP) {
        NSUInteger plainHTTPCount = 0;
        for (NSString *urlString in cleanURLs) {
            if (![self isHappAddLink:urlString] && ![self isHappEncryptedLink:urlString] &&
                URLStringUsesPlainHTTP(urlString)) {
                plainHTTPCount++;
            }
        }
        if (plainHTTPCount > 0) {
            [self showPlainHTTPSubscriptionWarningForCount:plainHTTPCount confirmation:^{
                [self startBackgroundSubscriptionImportForURLs:cleanURLs
                                           allowInsecureFetch:allowInsecureFetch
                                                  startStatus:startStatus
                                           importedPrefixPart:importedPrefixPart
                                  fallbackSubscriptionsByURL:fallbackSubscriptionsByURL
                                               allowPlainHTTP:YES];
            }];
            return;
        }
    }

    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Batch subscription import started",
                     [NSString stringWithFormat:@"requested=%lu insecure=%d",
                      (unsigned long)[cleanURLs count], allowInsecureFetch ? 1 : 0]);
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Importing subscriptions...";
    [self showStatus:startText ok:YES];

    NSArray *urlsToImport = [[NSArray alloc] initWithArray:cleanURLs];
    NSString *prefixPart = [importedPrefixPart copy];
    NSDictionary *fallbackSubscriptions = [fallbackSubscriptionsByURL copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *importedSubs = [[NSMutableArray alloc] init];
        NSMutableArray *insecureURLs = [[NSMutableArray alloc] init];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSMutableDictionary *failureCategories = [[NSMutableDictionary alloc] init];
        NSUInteger failedCount = 0;
        NSUInteger fallbackCount = 0;

        for (NSString *urlString in urlsToImport) {
            BOOL happAddSource = [self isHappAddLink:urlString];
            BOOL happSource = happAddSource || [self isHappEncryptedLink:urlString];
            NSString *subscriptionURL = happAddSource ? [self targetFromHappAddLink:urlString] : urlString;
            if (happAddSource &&
                (![subscriptionURL isKindOfClass:[NSString class]] ||
                 ![self isSubscriptionURL:subscriptionURL])) {
                failedCount++;
                VCIncrementDiagnosticCategory(failureCategories, @"invalid HAPP add link");
                [failureTexts addObject:[self shortImportFailureTextForURL:urlString
                                                                errorText:@"HAPP add link does not contain a valid subscription URL"]];
                continue;
            }
            NSDictionary *sub = [self subscriptionDictionaryForURL:subscriptionURL
                                                 allowInsecureFetch:allowInsecureFetch
                                                     allowPlainHTTP:(allowPlainHTTP && !happSource &&
                                                                     URLStringUsesPlainHTTP(subscriptionURL))
                                                         happSource:happSource];
            NSString *errorText = nil;
            BOOL insecureRetryAvailable = NO;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                        errorText:&errorText
                                                           insecureRetryAvailable:&insecureRetryAvailable];
            if ([updated isKindOfClass:[NSDictionary class]]) {
                [importedSubs addObject:updated];
            } else if (!allowInsecureFetch && insecureRetryAvailable) {
                [insecureURLs addObject:urlString];
            } else if ([[fallbackSubscriptions objectForKey:subscriptionURL] isKindOfClass:[NSDictionary class]]) {
                NSDictionary *fallback = [fallbackSubscriptions objectForKey:subscriptionURL];
                if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(subscriptionURL)) {
                    NSMutableDictionary *approvedFallback = [NSMutableDictionary dictionaryWithDictionary:fallback];
                    [approvedFallback setObject:[NSNumber numberWithBool:YES]
                                         forKey:kSubscriptionAllowPlainHTTPKey];
                    fallback = approvedFallback;
                }
                [importedSubs addObject:fallback];
                fallbackCount++;
            } else {
                failedCount++;
                VCIncrementDiagnosticCategory(failureCategories, errorText);
                [failureTexts addObject:[self shortImportFailureTextForURL:urlString errorText:errorText]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;

            NSUInteger addedCount = 0;
            NSInteger lastAddedIndex = -1;
            BOOL savedPlainHTTPApproval = NO;
            for (NSDictionary *sub in importedSubs) {
                NSString *urlString = [sub objectForKey:@"url"];
                if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) continue;
                NSInteger existingIndex = [self existingSubscriptionIndexForURL:urlString];
                if (existingIndex >= 0) {
                    NSDictionary *existingSub = [_subscriptions objectAtIndex:existingIndex];
                    if (SubscriptionDictionaryAllowsPlainHTTP(sub) &&
                        !SubscriptionDictionaryAllowsPlainHTTP(existingSub)) {
                        NSMutableDictionary *approved = [NSMutableDictionary dictionaryWithDictionary:existingSub];
                        [approved setObject:[NSNumber numberWithBool:YES]
                                    forKey:kSubscriptionAllowPlainHTTPKey];
                        [_subscriptions replaceObjectAtIndex:existingIndex withObject:approved];
                        savedPlainHTTPApproval = YES;
                    }
                    continue;
                }

                [_subscriptions addObject:sub];
                addedCount++;
                lastAddedIndex = [_subscriptions count] - 1;
            }

            if (addedCount > 0 || savedPlainHTTPApproval) {
                [self saveData];
                [self showProfileImportWarnings:importedSubs];
            }
            if (addedCount > 0) {
                [self selectSubscriptionAtIndex:lastAddedIndex];
            } else {
                [self normalizeSelection];
                [_tableView reloadData];
            }

            NSMutableArray *parts = [NSMutableArray array];
            if ([prefixPart isKindOfClass:[NSString class]] && [prefixPart length] > 0) {
                [parts addObject:prefixPart];
            }
            if (addedCount > 0) {
                [parts addObject:[self subscriptionImportCountText:addedCount]];
            }

            NSString *status = nil;
            if ([parts count] > 0) {
                status = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            } else {
                status = @"No subscriptions imported";
            }
            if (failedCount > 0) {
                status = [NSString stringWithFormat:@"%@ (failed: %@)",
                          status,
                          [self subscriptionImportCountText:failedCount]];
            }
            if (fallbackCount > 0) {
                status = [NSString stringWithFormat:@"%@ (%lu restored from backup cache)",
                          status,
                          (unsigned long)fallbackCount];
            }
            if ([insecureURLs count] > 0) {
                status = [NSString stringWithFormat:@"%@; %@ require insecure mode",
                          status,
                          [self subscriptionImportCountText:[insecureURLs count]]];
            }
            [self showStatus:status ok:([parts count] > 0 || [insecureURLs count] > 0)];

            if ([insecureURLs count] > 0) {
                BOOL allHappSources = YES;
                for (NSString *urlString in insecureURLs) {
                    if (![self isHappEncryptedLink:urlString] && ![self isHappAddLink:urlString]) {
                        allHappSources = NO;
                        break;
                    }
                }
                [self showInsecureSubscriptionImportPromptForURLs:insecureURLs
                                                   fromBatchImport:([urlsToImport count] > 1)
                                                        happSource:allHappSources];
            }
            if ([failureTexts count] > 0) {
                [self showSubscriptionImportFailures:failureTexts];
            }
            VCRecordAppEvent(@"import", @"Batch subscription import finished",
                             [NSString stringWithFormat:@"requested=%lu added=%lu failed=%lu failure_types=%@ fallback=%lu pending_insecure=%lu duration_ms=%.0f",
                              (unsigned long)[urlsToImport count],
                              (unsigned long)addedCount,
                              (unsigned long)failedCount,
                              VCDiagnosticCategoryCountsText(failureCategories),
                              (unsigned long)fallbackCount,
                              (unsigned long)[insecureURLs count],
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);

            [importedSubs release];
            [insecureURLs release];
            [failureTexts release];
            [failureCategories release];
            [urlsToImport release];
            [prefixPart release];
            [fallbackSubscriptions release];
        });

        [pool drain];
    });
}

- (void)importDirectURI:(NSString *)uri {
    VCRecordAppEvent(@"import", @"Configuration import started", @"type=direct");
    NSString *normalizedURI = [self safeTrim:uri];
    if (![normalizedURI isKindOfClass:[NSString class]] || [normalizedURI length] == 0) {
        VCRecordAppEvent(@"import", @"Configuration import failed", @"reason=empty");
        [self showStatus:@"Invalid configuration link" ok:NO];
        return;
    }
    if (![self isSupportedConfigTupleForURI:normalizedURI]) {
        VCRecordAppEvent(@"import", @"Configuration import failed", @"reason=unsupported");
        [self showStatus:[self unsupportedConfigStatusTextForURI:normalizedURI] ok:NO];
        return;
    }

    NSInteger existing = [self existingConfigIndexForURI:normalizedURI];
    if (existing >= 0) {
        VCRecordAppEvent(@"import", @"Configuration import skipped", @"reason=duplicate");
        _configurationsSectionExpanded = YES;
        _subscriptionsSectionExpanded = NO;
        _selectedConfigIndex = existing;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        [self normalizeSelection];
        [self saveData];
        [_tableView reloadData];
        [self showStatus:@"Configuration already exists (skipped)" ok:YES];
        return;
    }

    NSString *name = [self displayNameForURI:normalizedURI index:[_configs count]];
    NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                         name, @"name",
                         normalizedURI, @"uri",
                         nil];
    [_configs addObject:cfg];
    VCRecordAppEvent(@"import", @"Configuration imported",
                     [NSString stringWithFormat:@"configs=%lu", (unsigned long)[_configs count]]);

    _configurationsSectionExpanded = YES;
    _subscriptionsSectionExpanded = NO;
    _selectedConfigIndex = [_configs count] - 1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    [self saveData];
    [_tableView reloadData];
    [self showStatus:@"Configuration imported" ok:YES];
}

- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
               allowPlainHTTP:(BOOL)allowPlainHTTP
                   happSource:(BOOL)happSource {
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Subscription import started",
                     [NSString stringWithFormat:@"happ=%d insecure=%d plain_http=%d",
                      happSource ? 1 : 0, allowInsecureFetch ? 1 : 0, allowPlainHTTP ? 1 : 0]);
    NSString *normalizedURL = [self safeTrim:urlString];
    if (![normalizedURL isKindOfClass:[NSString class]] || [normalizedURL length] == 0) {
        VCRecordAppEvent(@"import", @"Subscription import failed", @"reason=empty");
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    NSInteger existing = [self existingSubscriptionIndexForURL:normalizedURL];
    if (!happSource && URLStringUsesPlainHTTP(normalizedURL) && !allowPlainHTTP) {
        if (existing >= 0 &&
            SubscriptionDictionaryAllowsPlainHTTP([_subscriptions objectAtIndex:existing])) {
            allowPlainHTTP = YES;
        } else {
            VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=plain_http_confirmation");
            [self showPlainHTTPSubscriptionWarningForCount:1 confirmation:^{
                [self importSubscriptionURL:normalizedURL
                         allowInsecureFetch:allowInsecureFetch
                             allowPlainHTTP:YES
                                  happSource:NO];
            }];
            return;
        }
    }

    if (existing >= 0) {
        NSArray *items = [self subscriptionItemsAtIndex:existing];
        if (!allowInsecureFetch && [items count] > 0) {
            NSDictionary *existingSubscription = [_subscriptions objectAtIndex:existing];
            BOOL needsHappFlag = happSource && !SubscriptionDictionaryUsesHappHeaders(existingSubscription);
            BOOL needsPlainHTTPFlag = allowPlainHTTP && !happSource &&
                                      URLStringUsesPlainHTTP(normalizedURL) &&
                                      !SubscriptionDictionaryAllowsPlainHTTP(existingSubscription);
            if (needsHappFlag || needsPlainHTTPFlag) {
                NSMutableDictionary *stored = [NSMutableDictionary dictionaryWithDictionary:existingSubscription];
                if (needsHappFlag) {
                    [stored setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
                }
                if (needsPlainHTTPFlag) {
                    [stored setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
                }
                [_subscriptions replaceObjectAtIndex:existing withObject:stored];
                [self saveData];
            }
            [self selectSubscriptionAtIndex:existing];
            VCRecordAppEvent(@"import", @"Subscription import skipped", @"reason=duplicate");
            [self showStatus:@"Subscription already exists (skipped)" ok:YES];
            return;
        }

        NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithDictionary:[_subscriptions objectAtIndex:existing]];
        [sub setObject:normalizedURL forKey:@"url"];
        if (allowInsecureFetch) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
        }
        if (allowPlainHTTP && !happSource && URLStringUsesPlainHTTP(normalizedURL)) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowPlainHTTPKey];
        }
        if (happSource) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionHappSourceKey];
        }

        NSString *errorText = nil;
        BOOL insecureRetryAvailable = NO;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                    errorText:&errorText
                                                       insecureRetryAvailable:&insecureRetryAvailable];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            VCRecordAppEvent(@"import", @"Subscription fetched",
                             [NSString stringWithFormat:@"result=update configs=%lu duration_ms=%.0f",
                              (unsigned long)[[updated objectForKey:@"items"] count],
                              ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
            [self commitUpdatedSubscription:updated existingIndex:existing];
            return;
        }

        if (!allowInsecureFetch &&
            !SubscriptionDictionaryAllowsInsecureFetch(sub) &&
            insecureRetryAvailable) {
            VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=insecure_confirmation");
            [self showInsecureSubscriptionImportPromptForURL:normalizedURL
                                                  happSource:SubscriptionDictionaryUsesHappHeaders(sub)];
            return;
        }

        VCRecordAppEvent(@"import", @"Subscription import failed",
                         [NSString stringWithFormat:@"stage=fetch error=%@ duration_ms=%.0f",
                          VCDiagnosticErrorSummary(errorText),
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
        return;
    }

    NSDictionary *sub = [self subscriptionDictionaryForURL:normalizedURL
                                         allowInsecureFetch:allowInsecureFetch
                                             allowPlainHTTP:allowPlainHTTP
                                                 happSource:happSource];
    NSString *errorText = nil;
    BOOL insecureRetryAvailable = NO;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                errorText:&errorText
                                                   insecureRetryAvailable:&insecureRetryAvailable];
    if ([updated isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"import", @"Subscription fetched",
                         [NSString stringWithFormat:@"result=new configs=%lu duration_ms=%.0f",
                          (unsigned long)[[updated objectForKey:@"items"] count],
                          ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
        [self commitUpdatedSubscription:updated existingIndex:-1];
        return;
    }

    if (!allowInsecureFetch && insecureRetryAvailable) {
        VCRecordAppEvent(@"import", @"Subscription import paused", @"reason=insecure_confirmation");
        [self showInsecureSubscriptionImportPromptForURL:normalizedURL happSource:happSource];
        return;
    }

    VCRecordAppEvent(@"import", @"Subscription import failed",
                     [NSString stringWithFormat:@"stage=fetch error=%@ duration_ms=%.0f",
                      VCDiagnosticErrorSummary(errorText),
                      ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
    [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
}

- (void)importSubscriptionURL:(NSString *)urlString
           allowInsecureFetch:(BOOL)allowInsecureFetch
                   happSource:(BOOL)happSource {
    [self importSubscriptionURL:urlString
             allowInsecureFetch:allowInsecureFetch
                 allowPlainHTTP:NO
                      happSource:happSource];
}

- (void)importSubscriptionURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    [self importSubscriptionURL:urlString allowInsecureFetch:allowInsecureFetch happSource:NO];
}

- (void)importSubscriptionURL:(NSString *)urlString {
    [self importSubscriptionURL:urlString allowInsecureFetch:NO];
}

- (BOOL)isHappEncryptedLink:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;
    const char *utf8 = [text UTF8String];
    return utf8 && VCHappIsEncryptedLink(utf8);
}

- (BOOL)isHappAddLink:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;
    return [[text lowercaseString] hasPrefix:kHappAddPrefix];
}

- (NSString *)targetFromHappAddLink:(NSString *)link {
    if (![self isHappAddLink:link] || [link length] <= [kHappAddPrefix length]) return nil;
    return [self safeTrim:[link substringFromIndex:[kHappAddPrefix length]]];
}

- (NSString *)decryptedHappLink:(NSString *)link errorText:(NSString **)errorTextOut {
    if (errorTextOut) *errorTextOut = nil;

    const char *utf8 = [link UTF8String];
    if (!utf8) {
        if (errorTextOut) *errorTextOut = @"HAPP link is not valid UTF-8";
        return nil;
    }

    unsigned char *plaintext = NULL;
    size_t plaintextLength = 0;
    char error[256];
    char mode[16];
    memset(error, 0, sizeof(error));
    memset(mode, 0, sizeof(mode));
    int result = VCHappDecryptLink(utf8,
                                   &plaintext,
                                   &plaintextLength,
                                   mode,
                                   sizeof(mode),
                                   error,
                                   sizeof(error));
    if (result != 1 || !plaintext || plaintextLength == 0) {
        if (plaintext) VCHappFreePlaintext(plaintext);
        if (errorTextOut) {
            NSString *detail = (error[0] != '\0') ? [NSString stringWithUTF8String:error] : nil;
            *errorTextOut = ([detail length] > 0)
                                ? [NSString stringWithFormat:@"Invalid HAPP link: %@", detail]
                                : @"Invalid HAPP link";
        }
        return nil;
    }

    NSString *decoded = [[[NSString alloc] initWithBytes:plaintext
                                                   length:plaintextLength
                                                 encoding:NSUTF8StringEncoding] autorelease];
    VCHappFreePlaintext(plaintext);
    decoded = [self safeTrim:decoded];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        if (errorTextOut) *errorTextOut = @"HAPP payload is not valid UTF-8";
        return nil;
    }
    return decoded;
}

- (void)importHappEncryptedLink:(NSString *)link {
    NSString *errorText = nil;
    NSString *decoded = [self decryptedHappLink:link errorText:&errorText];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        [self showStatus:([errorText length] > 0 ? errorText : @"Invalid HAPP link") ok:NO];
        return;
    }

    if ([self isDirectConfigURI:decoded]) {
        [self importDirectURI:decoded];
        return;
    }
    if ([self isSubscriptionURL:decoded]) {
        [self importSubscriptionURL:link allowInsecureFetch:NO happSource:YES];
        return;
    }

    [self showStatus:@"HAPP link does not contain a supported config or subscription URL" ok:NO];
}

- (void)importHappAddLink:(NSString *)link {
    NSString *target = [self targetFromHappAddLink:link];
    if (![target isKindOfClass:[NSString class]] || [target length] == 0) {
        [self showStatus:@"HAPP add link does not contain an import URL" ok:NO];
        return;
    }

    if ([self isDirectConfigURI:target]) {
        [self importDirectURI:target];
        return;
    }
    if ([self isSubscriptionURL:target]) {
        [self importSubscriptionURL:target allowInsecureFetch:NO happSource:YES];
        return;
    }

    [self showStatus:@"HAPP add link does not contain a supported config or subscription URL" ok:NO];
}

- (void)importTextEntry:(NSString *)rawText {
    NSString *text = [self safeTrim:rawText];
    if ([text length] == 0) {
        VCRecordAppEvent(@"import", @"Import rejected", @"reason=empty_text");
        [self showStatus:@"Import text is empty" ok:NO];
        return;
    }
    if ([text hasPrefix:@"{"] || [text hasPrefix:@"["]) {
        NSDictionary *report=[VCProfiles() importReportFromHappJSONData:[text dataUsingEncoding:NSUTF8StringEncoding]];
        NSArray *uris=[report objectForKey:@"uris"];
        if ([uris count]) [self importTextEntry:[uris componentsJoinedByString:@"\n"]];
        else [self showStatus:@"JSON contains no supported configurations" ok:NO];
        [self showProfileImportWarnings:@[report]];
        return;
    }

    NSString *karingError = nil;
    NSDictionary *karingDescriptor = VCKaringLANDownloadDescriptor(text, &karingError);
    if ([karingDescriptor isKindOfClass:[NSDictionary class]]) {
        VCRecordAppEvent(@"import", @"Karing LAN import recognized", nil);
        [self receiveKaringBackupWithDescriptor:karingDescriptor];
        return;
    }
    if ([karingError length] > 0) {
        VCRecordAppEvent(@"import", @"Import rejected", @"type=karing reason=invalid_descriptor");
        [self showStatus:karingError ok:NO];
        return;
    }

    if ([self isHappEncryptedLink:text]) {
        VCRecordAppEvent(@"import", @"HAPP encrypted import recognized", nil);
        [self importHappEncryptedLink:text];
        return;
    }

    if ([self isHappAddLink:text]) {
        VCRecordAppEvent(@"import", @"HAPP add import recognized", nil);
        [self importHappAddLink:text];
        return;
    }

    if ([[text lowercaseString] hasPrefix:@"happ://"]) {
        VCRecordAppEvent(@"import", @"Import rejected", @"type=happ reason=unsupported_format");
        [self showStatus:@"Unsupported HAPP link format (use happ://add/, crypt4/ or crypt5/)" ok:NO];
        return;
    }

    BOOL hasWhitespace = ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound);
    if (!hasWhitespace && [self isDirectConfigURI:text]) {
        [self importDirectURI:text];
        return;
    }

    if (!hasWhitespace && [self isSubscriptionURL:text]) {
        [self importSubscriptionURL:text];
        return;
    }

    NSArray *links = [self extractImportLinksFromText:text];
    if ([links count] > 0) {
        if ([links count] == 1) {
            NSString *single = [links objectAtIndex:0];
            if ([self isHappEncryptedLink:single]) {
                [self importHappEncryptedLink:single];
            } else if ([self isHappAddLink:single]) {
                [self importHappAddLink:single];
            } else if ([self isDirectConfigURI:single]) {
                [self importDirectURI:single];
            } else if ([self isSubscriptionURL:single]) {
                [self importSubscriptionURL:single];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
            return;
        }

        NSInteger importedConfigs = 0;
        NSInteger pendingSubs = 0;
        NSInteger skippedConfigs = 0;
        NSInteger skippedSubs = 0;
        NSMutableArray *subscriptionURLsToImport = [NSMutableArray array];

        for (NSString *link in links) {
            NSString *importLink = link;
            BOOL happEncryptedLink = [self isHappEncryptedLink:link];
            BOOL happAddLink = [self isHappAddLink:link];
            BOOL happLink = happEncryptedLink || happAddLink;
            if (happEncryptedLink) {
                NSString *decryptError = nil;
                NSString *decoded = [self decryptedHappLink:link errorText:&decryptError];
                if ([self isDirectConfigURI:decoded]) {
                    importLink = decoded;
                } else if ([self isSubscriptionURL:decoded]) {
                    importLink = link;
                } else {
                    skippedSubs++;
                    continue;
                }
            } else if (happAddLink) {
                NSString *target = [self targetFromHappAddLink:link];
                if ([self isDirectConfigURI:target] || [self isSubscriptionURL:target]) {
                    importLink = target;
                } else {
                    skippedSubs++;
                    continue;
                }
            }

            if ([self isDirectConfigURI:importLink]) {
                if (![self isSupportedConfigTupleForURI:importLink]) {
                    skippedConfigs++;
                    continue;
                }
                if ([self existingConfigIndexForURI:importLink] >= 0) {
                    skippedConfigs++;
                    continue;
                }

                NSString *name = [self displayNameForURI:importLink index:[_configs count]];
                NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                                     name, @"name",
                                     importLink, @"uri",
                                     nil];
                [_configs addObject:cfg];
                importedConfigs++;
            } else if ([self isSubscriptionURL:importLink] || happLink) {
                if ([self existingSubscriptionIndexForURL:importLink] >= 0) {
                    skippedSubs++;
                    continue;
                }

                NSString *queuedLink = happAddLink ? link : importLink;
                if (![subscriptionURLsToImport containsObject:queuedLink]) {
                    [subscriptionURLsToImport addObject:queuedLink];
                    pendingSubs++;
                }
            }
        }

        if (importedConfigs > 0 || pendingSubs > 0) {
            if (importedConfigs > 0) {
                _configurationsSectionExpanded = YES;
                _subscriptionsSectionExpanded = NO;
                _selectedConfigIndex = [_configs count] - 1;
                _selectedSubIndex = -1;
                _selectedSubItemIndex = -1;
                [self normalizeSelection];
                [self saveData];
                [_tableView reloadData];
            }
        }

        NSMutableArray *parts = [NSMutableArray array];
        if (importedConfigs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld config%@", (long)importedConfigs, (importedConfigs == 1 ? @"" : @"s")]];
        }
        if (pendingSubs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)pendingSubs, (pendingSubs == 1 ? @"" : @"s")]];
        }

        if ([parts count] > 0) {
            VCRecordAppEvent(@"import", @"Text import parsed",
                             [NSString stringWithFormat:@"configs=%ld subscriptions=%ld skipped_configs=%ld skipped_subscriptions=%ld",
                              (long)importedConfigs,
                              (long)pendingSubs,
                              (long)skippedConfigs,
                              (long)skippedSubs]);
            NSString *importText = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                importText = [NSString stringWithFormat:@"%@ (skipped duplicates: %@)",
                              importText,
                              [skippedParts componentsJoinedByString:@", "]];
            }

            if ([subscriptionURLsToImport count] > 0) {
                NSString *configPart = nil;
                if (importedConfigs > 0) {
                    configPart = [NSString stringWithFormat:@"%ld config%@",
                                  (long)importedConfigs,
                                  (importedConfigs == 1 ? @"" : @"s")];
                }
                [self startBackgroundSubscriptionImportForURLs:subscriptionURLsToImport
                                            allowInsecureFetch:NO
                                                   startStatus:@"Importing subscriptions from file..."
                                            importedPrefixPart:configPart];
            } else {
                [self showStatus:importText ok:YES];
            }
        } else {
            VCRecordAppEvent(@"import", @"Text import produced no new entries",
                             [NSString stringWithFormat:@"skipped_configs=%ld skipped_subscriptions=%ld",
                              (long)skippedConfigs,
                              (long)skippedSubs]);
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                [self showStatus:[NSString stringWithFormat:@"Nothing imported: all links already exist (%@)",
                                  [skippedParts componentsJoinedByString:@", "]]
                             ok:YES];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
        }
        return;
    }

    VCRecordAppEvent(@"import", @"Import rejected", @"reason=unsupported_format");
    [self showStatus:@"Unsupported import format (use vless://, socks5://, happ://, karing://sync-download/, or an HTTP(S) subscription)" ok:NO];
}

- (void)showProfileImportWarnings:(NSArray *)reports {
    NSUInteger skipped=0; NSMutableArray *issues=[NSMutableArray array];
    for (NSDictionary *report in reports) {
        skipped+=[[report objectForKey:@"import_skipped"] ?: [report objectForKey:@"skipped"] unsignedIntegerValue];
        NSArray *reasons=[report objectForKey:@"import_issues"] ?: [report objectForKey:@"issues"];
        for (NSString *reason in reasons) if ([issues count] < 5 && ![issues containsObject:reason]) [issues addObject:reason];
    }
    if (!skipped) return;
    NSString *message=[NSString stringWithFormat:@"Skipped %lu configuration(s).\n%@",(unsigned long)skipped,[issues componentsJoinedByString:@"\n"]];
    UIAlertView *alert=[[[UIAlertView alloc] initWithTitle:@"Import warnings" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease];
    [alert show];
}

- (void)importKaringSubscriptionEntries:(NSArray *)entries {
    [self showProfileImportWarnings:entries];
    if (![entries isKindOfClass:[NSArray class]] || [entries count] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup contained no entries", nil);
        [self showStatus:@"The Karing backup has no supported subscriptions" ok:NO];
        return;
    }

    NSMutableArray *urls = [NSMutableArray array];
    NSMutableDictionary *cachedSubscriptions = [NSMutableDictionary dictionary];
    NSUInteger duplicateCount = 0;
    for (id value in entries) {
        if (![value isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = [self safeTrim:[value objectForKey:@"url"]];
        if (![self isSubscriptionURL:url] || [urls containsObject:url]) continue;
        if ([self existingSubscriptionIndexForURL:url] >= 0) {
            duplicateCount++;
            continue;
        }
        [urls addObject:url];

        NSArray *storedItems = [value objectForKey:@"items"];
        NSMutableArray *supportedItems = [NSMutableArray array];
        if ([storedItems isKindOfClass:[NSArray class]]) {
            for (id item in storedItems) {
                if (![item isKindOfClass:[NSString class]]) continue;
                if ([self isSupportedConfigTupleForURI:item] && ![supportedItems containsObject:item]) {
                    [supportedItems addObject:item];
                }
            }
        }
        if ([supportedItems count] > 0) {
            NSMutableDictionary *subscription =
                [NSMutableDictionary dictionaryWithDictionary:
                 [self subscriptionDictionaryForURL:url allowInsecureFetch:NO]];
            [subscription setObject:supportedItems forKey:@"items"];
            for (NSString *key in @[@"import_skipped",@"import_issues"]) if ([value objectForKey:key]) [subscription setObject:[value objectForKey:key] forKey:key];
            [cachedSubscriptions setObject:subscription forKey:url];
        }
    }

    if ([urls count] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup produced no new subscriptions",
                         [NSString stringWithFormat:@"entries=%lu duplicates=%lu",
                          (unsigned long)[entries count],
                          (unsigned long)duplicateCount]);
        [self showStatus:(duplicateCount > 0
                          ? @"All Karing subscriptions already exist"
                          : @"The Karing backup has no supported subscriptions")
                     ok:(duplicateCount > 0)];
        return;
    }

    VCRecordAppEvent(@"import", @"Karing subscriptions parsed",
                     [NSString stringWithFormat:@"entries=%lu queued=%lu duplicates=%lu cached=%lu",
                      (unsigned long)[entries count],
                      (unsigned long)[urls count],
                      (unsigned long)duplicateCount,
                      (unsigned long)[cachedSubscriptions count]]);
    [self startBackgroundSubscriptionImportForURLs:urls
                               allowInsecureFetch:NO
                                      startStatus:@"Importing Karing subscriptions..."
                               importedPrefixPart:nil
                      fallbackSubscriptionsByURL:cachedSubscriptions];
}

- (void)importKaringBackupData:(NSData *)data {
    if (![data isKindOfClass:[NSData class]] || [data length] == 0) {
        VCRecordAppEvent(@"import", @"Karing backup read failed", @"reason=empty_data");
        [self showStatus:@"Unable to read the Karing backup" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Karing backup parsing started",
                     [NSString stringWithFormat:@"bytes=%lu", (unsigned long)[data length]]);
    [self showStatus:@"Reading Karing backup..." ok:YES];
    NSData *copiedData = [data copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *errorText = nil;
        NSArray *entries = VCKaringSubscriptionsFromBackupData(copiedData, &errorText);
        NSArray *copiedEntries = [entries copy];
        NSString *copiedError = [errorText copy];

        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;
            if ([copiedEntries isKindOfClass:[NSArray class]]) {
                VCRecordAppEvent(@"import", @"Karing backup parsed",
                                 [NSString stringWithFormat:@"entries=%lu duration_ms=%.0f",
                                  (unsigned long)[copiedEntries count],
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self importKaringSubscriptionEntries:copiedEntries];
            } else {
                VCRecordAppEvent(@"import", @"Karing backup parsing failed",
                                 [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                                  VCDiagnosticErrorSummary(copiedError),
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self showStatus:([copiedError length] > 0
                                  ? copiedError
                                  : @"Unable to read the Karing backup")
                             ok:NO];
            }
            [copiedEntries release];
            [copiedError release];
            [copiedData release];
        });
        [pool drain];
    });
}

- (void)receiveKaringBackupWithDescriptor:(NSDictionary *)descriptor {
    NSArray *hosts = [descriptor objectForKey:@"hosts"];
    NSInteger port = [[descriptor objectForKey:@"port"] integerValue];
    if (![hosts isKindOfClass:[NSArray class]] || [hosts count] == 0 ||
        port < 1 || port > 65535) {
        VCRecordAppEvent(@"import", @"Karing LAN sync rejected", @"reason=invalid_descriptor");
        [self showStatus:@"Invalid Karing LAN sync address" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSTimeInterval diagnosticStarted = [NSDate timeIntervalSinceReferenceDate];
    VCRecordAppEvent(@"import", @"Karing LAN sync started",
                     [NSString stringWithFormat:@"candidate_hosts=%lu", (unsigned long)[hosts count]]);
    [self showStatus:@"Receiving Karing backup..." ok:YES];
    NSDictionary *copiedDescriptor = [descriptor copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSArray *downloadHosts = [copiedDescriptor objectForKey:@"hosts"];
        NSInteger downloadPort = [[copiedDescriptor objectForKey:@"port"] integerValue];
        NSArray *entries = nil;
        NSString *lastError = nil;

        for (NSString *host in downloadHosts) {
            NSString *routeAdd = [NSString stringWithFormat:@"ROUTE_DIRECT_ADD\t%@\n", host];
            NSString *routeRemove = [NSString stringWithFormat:@"ROUTE_DIRECT_REMOVE\t%@\n", host];
            (void)SendCommand(routeAdd);

            NSString *baseURLText = [NSString stringWithFormat:@"http://%@:%ld",
                                     host, (long)downloadPort];
            NSMutableURLRequest *probe =
                [NSMutableURLRequest requestWithURL:
                 [NSURL URLWithString:[baseURLText stringByAppendingString:@"/"]]
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:3.0];
            [probe setValue:@"close" forHTTPHeaderField:@"Connection"];

            NSURLResponse *response = nil;
            NSError *requestError = nil;
            (void)[NSURLConnection sendSynchronousRequest:probe
                                         returningResponse:&response
                                                     error:&requestError];
            NSInteger probeStatus = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                probeStatus = [(NSHTTPURLResponse *)response statusCode];
            }
            if (requestError || (probeStatus != 200 && probeStatus != 404)) {
                lastError = requestError
                    ? [requestError localizedDescription]
                    : [NSString stringWithFormat:@"Karing probe returned HTTP %ld",
                       (long)probeStatus];
                (void)SendCommand(routeRemove);
                continue;
            }

            NSMutableURLRequest *request =
                [NSMutableURLRequest requestWithURL:
                 [NSURL URLWithString:[baseURLText stringByAppendingString:@"/sync-download"]]
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:20.0];
            [request setValue:@"close" forHTTPHeaderField:@"Connection"];
            response = nil;
            requestError = nil;
            NSData *data = [NSURLConnection sendSynchronousRequest:request
                                                 returningResponse:&response
                                                             error:&requestError];
            (void)SendCommand(routeRemove);

            NSInteger statusCode = 0;
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                statusCode = [(NSHTTPURLResponse *)response statusCode];
            }
            if (requestError || !data || [data length] == 0 || statusCode != 200) {
                if (requestError) {
                    lastError = [requestError localizedDescription];
                } else if (statusCode != 0) {
                    lastError = [NSString stringWithFormat:@"Karing returned HTTP %ld", (long)statusCode];
                } else {
                    lastError = @"Karing returned an empty response";
                }
                continue;
            }
            if ([data length] > 32U * 1024U * 1024U) {
                lastError = @"The Karing backup is too large";
                continue;
            }

            NSString *parseError = nil;
            entries = VCKaringSubscriptionsFromBackupData(data, &parseError);
            if ([entries isKindOfClass:[NSArray class]]) break;
            lastError = parseError;
        }

        NSArray *copiedEntries = [entries copy];
        NSString *copiedError = [lastError copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;
            if ([copiedEntries isKindOfClass:[NSArray class]]) {
                VCRecordAppEvent(@"import", @"Karing LAN sync finished",
                                 [NSString stringWithFormat:@"entries=%lu duration_ms=%.0f",
                                  (unsigned long)[copiedEntries count],
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                [self importKaringSubscriptionEntries:copiedEntries];
            } else {
                VCRecordAppEvent(@"import", @"Karing LAN sync failed",
                                 [NSString stringWithFormat:@"error=%@ duration_ms=%.0f",
                                  VCDiagnosticErrorSummary(copiedError),
                                  ([NSDate timeIntervalSinceReferenceDate] - diagnosticStarted) * 1000.0]);
                NSString *message = ([copiedError length] > 0)
                    ? [NSString stringWithFormat:@"Karing sync failed: %@", copiedError]
                    : @"Karing sync failed: no LAN address responded";
                [self showStatus:message ok:NO];
            }
            [copiedEntries release];
            [copiedError release];
            [copiedDescriptor release];
        });
        [pool drain];
    });
}

- (NSString *)decodeImportTextData:(NSData *)data {
    return [VCProfiles() decodeImportTextData:data];
}

- (void)importTextFileAtPath:(NSString *)rawPath {
    VCRecordAppEvent(@"import", @"File import started", nil);
    NSString *path = [self safeTrim:rawPath];
    if ([path hasPrefix:@"\""] && [path hasSuffix:@"\""] && [path length] >= 2) {
        path = [path substringWithRange:NSMakeRange(1, [path length] - 2)];
        path = [self safeTrim:path];
    }
    path = [path stringByExpandingTildeInPath];
    if ([path length] == 0) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=path_validation");
        [self showStatus:@"File path is empty" ok:NO];
        return;
    }

    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (exists && isDir) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=file_selection");
        [self showStatus:@"Import file not found" ok:NO];
        return;
    }

    [self showStatus:@"Importing data from file..." ok:YES];

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] == 0) {
        if (!exists) {
            VCRecordAppEvent(@"import", @"File import failed", @"stage=file_missing");
            [self showStatus:@"Import file not found" ok:NO];
            return;
        }
        VCRecordAppEvent(@"import", @"File import failed", @"stage=file_read");
        [self showStatus:@"Failed to read import file" ok:NO];
        return;
    }

    if (VCKaringBackupDataLooksLikeZip(data)) {
        VCRecordAppEvent(@"import", @"Karing backup detected", nil);
        [self importKaringBackupData:data];
        return;
    }

    NSString *text = [self decodeImportTextData:data];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
        VCRecordAppEvent(@"import", @"File import failed", @"stage=text_decode");
        [self showStatus:@"Unsupported text encoding" ok:NO];
        return;
    }

    [self importTextEntry:text];
}

- (void)importFileAtURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]] || ![url isFileURL]) {
        VCRecordAppEvent(@"import", @"File import rejected", @"reason=unsupported_url");
        [self showStatus:@"Unsupported import file URL" ok:NO];
        return;
    }
    NSString *path = [url path];
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) {
        [self showStatus:@"Import file path is empty" ok:NO];
        return;
    }
    [self importTextFileAtPath:path];
}

- (void)startFileBrowserImportFlow {
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:kImportDirectoryPath isDirectory:&isDirectory] || !isDirectory) {
        VCRecordAppEvent(@"import", @"File browser unavailable", nil);
        [self showStatus:@"Import directory is unavailable" ok:NO];
        return;
    }

    VCImportBrowserVC *browser = [[[VCImportBrowserVC alloc] initWithRootPath:kImportDirectoryPath
                                                                directoryPath:kImportDirectoryPath
                                                                     delegate:self] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:browser] autorelease];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:navigation animated:YES completion:nil];
    VCRecordAppEvent(@"ui", @"File browser opened", nil);
}

- (void)importBrowserDidCancel:(UIViewController *)browser {
    (void)browser;
    [self dismissViewControllerAnimated:YES completion:nil];
    VCRecordAppEvent(@"import", @"File browser canceled", nil);
}

- (void)importBrowser:(UIViewController *)browser didSelectFileAtPath:(NSString *)path {
    (void)browser;
    NSString *selectedPath = [path copy];
    VCRecordAppEvent(@"import", @"File selected", nil);
    [self dismissViewControllerAnimated:YES completion:^{
        [self importTextFileAtPath:selectedPath];
        [selectedPath release];
    }];
}

- (void)startQRImportFlow {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        VCRecordAppEvent(@"import", @"QR scanner unavailable", @"reason=camera_unavailable");
        [self showStatus:@"Camera is unavailable" ok:NO];
        return;
    }

    QRScanVC *scanner = [[[QRScanVC alloc] init] autorelease];
    scanner.delegate = self;
    scanner.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:scanner animated:YES completion:nil];
    VCRecordAppEvent(@"ui", @"QR scanner opened", nil);
    [self showStatus:@"Scan QR code to import links..." ok:YES];
}

- (void)plusPressed {
    VCRecordAppEvent(@"ui", @"Import menu opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Import"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"Import from Clipboard", @"Import from File", @"Scan QR Code", @"Manual Input", nil] autorelease];
    sheet.tag = VCActionSheetTagImport;
    [sheet showInView:self.view];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == VCActionSheetTagImport) {
        if (buttonIndex == 0) {
            VCRecordAppEvent(@"import", @"Clipboard import selected", nil);
            NSString *clip = [[UIPasteboard generalPasteboard] string];
            [self importTextEntry:clip];
        } else if (buttonIndex == 1) {
            VCRecordAppEvent(@"import", @"File import selected", nil);
            [self startFileBrowserImportFlow];
        } else if (buttonIndex == 2) {
            VCRecordAppEvent(@"import", @"QR import selected", nil);
            [self startQRImportFlow];
        } else if (buttonIndex == 3) {
            VCRecordAppEvent(@"import", @"Manual import selected", nil);
            UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Manual Import"
                                                          message:@"Paste a config or subscription link"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                                otherButtonTitles:@"Import", nil] autorelease];
            av.alertViewStyle = UIAlertViewStylePlainTextInput;
            av.tag = VCAlertTagImportManual;

            UITextField *tf = [av textFieldAtIndex:0];
            tf.placeholder = @"vless://..., or https://..., happ://add/...";
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.keyboardType = UIKeyboardTypeURL;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;

            [av show];
        } else {
            VCRecordAppEvent(@"import", @"Import menu canceled", nil);
        }
        return;
    }

}

- (void)qrScanVCDidCancel:(UIViewController *)vc {
    (void)vc;
    [self dismissViewControllerAnimated:YES completion:nil];
    [self showStatus:@"QR import canceled" ok:YES];
    VCRecordAppEvent(@"import", @"QR scan canceled", nil);
}

- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text {
    (void)vc;
    NSString *payload = [[self safeTrim:text] copy];
    VCRecordAppEvent(@"import", @"QR payload recognized", nil);
    NSString *karingError = nil;
    NSDictionary *karingDescriptor = VCKaringLANDownloadDescriptor(payload, &karingError);
    [self dismissViewControllerAnimated:YES completion:^{
        if (![payload isKindOfClass:[NSString class]] || [payload length] == 0) {
            [self showStatus:@"QR code does not contain import data" ok:NO];
            [payload release];
            return;
        }

        if ([karingDescriptor isKindOfClass:[NSDictionary class]]) {
            [self receiveKaringBackupWithDescriptor:karingDescriptor];
            [payload release];
            return;
        }
        if ([karingError length] > 0) {
            [self showStatus:karingError ok:NO];
            [payload release];
            return;
        }

        NSArray *links = [self extractImportLinksFromText:payload];
        if ([links isKindOfClass:[NSArray class]] && [links count] > 0) {
            NSString *subscriptionURL = nil;
            for (NSString *candidate in links) {
                if ([self isSubscriptionURL:candidate]) {
                    subscriptionURL = candidate;
                    break;
                }
            }

            if ([subscriptionURL isKindOfClass:[NSString class]] && [subscriptionURL length] > 0) {
                [self importSubscriptionURL:subscriptionURL];
                [payload release];
                return;
            }

            if ([links count] == 1) {
                NSString *single = [links objectAtIndex:0];
                [self importTextEntry:single];
                [payload release];
                return;
            }
        }

        [self importTextEntry:payload];
        [payload release];
    }];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == VCAlertTagUpdateAvailable) {
        if (buttonIndex != alertView.cancelButtonIndex) {
            VCOpenGitHubLatestRelease(_availableReleaseURL);
        }
        return;
    }

    if (alertView.tag == VCAlertTagImportManual) {
        if (buttonIndex != 1) {
            VCRecordAppEvent(@"import", @"Manual import canceled", nil);
            return;
        }
        VCRecordAppEvent(@"import", @"Manual import submitted", nil);
        NSString *txt = [[alertView textFieldAtIndex:0] text];
        [self importTextEntry:txt];
        return;
    }

    if (alertView.tag == VCAlertTagPlainHTTPSubscription) {
        void (^confirmation)(void) = _pendingPlainHTTPConfirmation
            ? Block_copy(_pendingPlainHTTPConfirmation)
            : NULL;
        void (^cancellation)(void) = _pendingPlainHTTPCancellation
            ? Block_copy(_pendingPlainHTTPCancellation)
            : NULL;
        if (_pendingPlainHTTPConfirmation) {
            Block_release(_pendingPlainHTTPConfirmation);
            _pendingPlainHTTPConfirmation = NULL;
        }
        if (_pendingPlainHTTPCancellation) {
            Block_release(_pendingPlainHTTPCancellation);
            _pendingPlainHTTPCancellation = NULL;
        }

        if (buttonIndex != alertView.cancelButtonIndex && confirmation) {
            VCRecordAppEvent(@"import", @"Plain HTTP subscription approved", nil);
            confirmation();
        } else {
            VCRecordAppEvent(@"import", @"Plain HTTP subscription declined", nil);
            if (cancellation) cancellation();
            [self showStatus:@"HTTP subscription canceled" ok:YES];
        }
        if (confirmation) Block_release(confirmation);
        if (cancellation) Block_release(cancellation);
        return;
    }

    if (alertView.tag == VCAlertTagImportInsecureSubscription) {
        NSArray *urlStrings = [_pendingInsecureImportURLs retain];
        BOOL useHappHeaders = _pendingInsecureImportUsesHappHeaders;
        [_pendingInsecureImportURLs release];
        _pendingInsecureImportURLs = nil;
        _pendingInsecureImportUsesHappHeaders = NO;

        if (buttonIndex == 1) {
            VCRecordAppEvent(@"import", @"Insecure subscription fetch approved",
                             [NSString stringWithFormat:@"count=%lu", (unsigned long)[urlStrings count]]);
            if ([urlStrings count] == 1) {
                NSString *urlString = [urlStrings objectAtIndex:0];
                if (useHappHeaders && [self isHappAddLink:urlString]) {
                    urlString = [self targetFromHappAddLink:urlString];
                }
                [self importSubscriptionURL:urlString
                         allowInsecureFetch:YES
                             allowPlainHTTP:(!useHappHeaders && URLStringUsesPlainHTTP(urlString))
                                 happSource:useHappHeaders];
            } else if ([urlStrings count] > 1) {
                BOOL includesPlainHTTP = NO;
                for (NSString *urlString in urlStrings) {
                    if (![self isHappEncryptedLink:urlString] && ![self isHappAddLink:urlString] &&
                        URLStringUsesPlainHTTP(urlString)) {
                        includesPlainHTTP = YES;
                        break;
                    }
                }
                [self startBackgroundSubscriptionImportForURLs:urlStrings
                                            allowInsecureFetch:YES
                                                   startStatus:@"Importing insecure subscriptions..."
                                            importedPrefixPart:nil
                                   fallbackSubscriptionsByURL:nil
                                                allowPlainHTTP:includesPlainHTTP];
            }
        } else {
            VCRecordAppEvent(@"import", @"Insecure subscription fetch declined",
                             [NSString stringWithFormat:@"count=%lu", (unsigned long)[urlStrings count]]);
            [self showStatus:([urlStrings count] == 1 ? @"Subscription import canceled"
                                                      : @"Insecure subscriptions skipped")
                          ok:YES];
        }
        [urlStrings release];
        return;
    }
}

@end
