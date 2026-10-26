#import "main_screen.h"

static void VCPingNetworkChanged(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info) {
    (void)target; (void)flags;
    [(MainVC *)info refreshPingNetworkState];
}

@implementation MainVC (VCMainPing)

- (void)startPingNetworkObservation {
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;
    _pingNetworkReachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (struct sockaddr *)&address);
    if (_pingNetworkReachability) {
        SCNetworkReachabilityContext context = {0, self, NULL, NULL, NULL};
        if (SCNetworkReachabilitySetCallback(_pingNetworkReachability, VCPingNetworkChanged, &context))
            SCNetworkReachabilityScheduleWithRunLoop(_pingNetworkReachability, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    }
    _pingNetworkDirty = YES;
}

- (void)refreshPingNetworkState {
    _pingNetworkDirty = YES;
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) return;
    if (_pingNetworkCheckInFlight) { _pingNetworkCheckPending = YES; return; }
    _pingNetworkCheckInFlight = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *signature = [VCPingNetworkSignature() copy];
        dispatch_async(dispatch_get_main_queue(), ^{
            _pingNetworkCheckInFlight = NO;
            if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
                _pingNetworkDirty = YES;
                _pingNetworkCheckPending = NO;
                [signature release];
                return;
            }
            BOOL available = signature != nil;
            _publishingPingNetwork = YES;
            BOOL changed = signature && VCPingUpdateNetwork(self,signature,&_pingNetworkSignature,&_pingNetworkGeneration,_pingDisplayByURI);
            _publishingPingNetwork = NO;
            if (changed) {
                if (_sortSubscriptionsByPing) [self scheduleSubscriptionPingSort];
                [self refreshVisiblePingAccessoriesForURI:nil];
                [self refreshVisibleSubscriptionHeaderAccessories];
                VCRecordAppEvent(@"ping", @"Network changed; ping results cleared", nil);
            }
            [signature release];
            if (_pingNetworkCheckPending) {
                _pingNetworkCheckPending = NO;
                [self refreshPingNetworkState];
                return;
            }
            _pingNetworkDirty = !available;
            if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) {
                _pingNetworkDirty = YES;
                return;
            }
            NSArray *starts = [[_pingNetworkStarts copy] autorelease];
            [_pingNetworkStarts removeAllObjects];
            if (!_pingNetworkDirty) {
                NSArray *results = [[_pingNetworkResults copy] autorelease];
                [_pingNetworkResults removeAllObjects];
                for (NSDictionary *result in results) [self pingResultOnMain:result];
                for (NSDictionary *start in starts) {
                    NSString *uri = [start objectForKey:@"uri"];
                    NSDictionary *options = [start objectForKey:@"options"];
                    if (uri) [self beginPingForURI:uri type:[[options objectForKey:@"type"] integerValue] options:options];
                    else {
                        NSInteger index = [[start objectForKey:@"index"] integerValue];
                        if ([[start objectForKey:@"identifier"] isEqual:[self subscriptionPingIdentifierAtIndex:index]] &&
                            [start objectForKey:@"items"] == [self subscriptionItemsAtIndex:index])
                            [self beginSubscriptionPingAtIndex:index options:options];
                    }
                }
                [self pumpSubscriptionPings];
            } else if ([starts count]) [self showStatus:@"Cannot check network state" ok:NO];
            [self refreshVisibleSubscriptionHeaderAccessories];
        });
        [pool drain];
    });
}

- (NSDictionary *)pingOptionsForType:(VCPingType)type {
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        @(type), @"type", @(VCPingTimeoutSecondsInDefaults([NSUserDefaults standardUserDefaults])*1000), @"timeout_ms", nil];
    [payload setObject:[[VCSelectedProxyPingURL() copy] autorelease] forKey:@"probe_url"];
    [payload setObject:@(VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults])) forKey:@"use_xmux"];
    NSString *xrayVersion = VCActiveXrayVersion();
    if (xrayVersion) [payload setObject:xrayVersion forKey:@"xray_version"];
    return payload;
}

- (void)pingNetworkTick:(NSTimer *)timer {
    (void)timer;
    if (![_pingDisplayByURI count] && ![_standalonePingCancellationsByURI count] &&
        ![_subscriptionPingTokenByIdentifier count] && ![_pingNetworkStarts count]) {
        [_pingNetworkTimer invalidate];
        [_pingNetworkTimer release];
        _pingNetworkTimer = nil;
        return;
    }
    [self refreshPingNetworkState];
}

- (void)pingWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VCPingCancellation *cancellation = [payload objectForKey:@"cancellation"];
    if ([cancellation isCancelled]) {
        [pool drain];
        return;
    }
    NSString *uri = [payload objectForKey:@"uri"];
    VCPingType pingType = (VCPingType)[[payload objectForKey:@"type"] integerValue];
    int timeoutMs=[[payload objectForKey:@"timeout_ms"] intValue];
    NSString *host = nil;
    uint16_t port = 0;
    int latencyMs = -1;
    BOOL ok = NO;
    BOOL parsed = [VCProfiles() parseServerHost:&host port:&port fromURI:uri];
    if (parsed) {
        int rc = -1;

        if (pingType == VCPingTypeProxyGET) {
            NSString *xrayVersion = [payload objectForKey:@"xray_version"];
            NSString *runtimeURI = [VCProfiles() runtimeURI:uri useXmux:[[payload objectForKey:@"use_xmux"] boolValue] error:NULL];
            if (runtimeURI) rc = ProxyGetViaTempCoreMs([runtimeURI UTF8String], [xrayVersion UTF8String],
                                       timeoutMs, 2, &latencyMs, cancellation, [payload objectForKey:@"probe_url"]);
        } else if (pingType == VCPingTypeTCP) {
            rc = ConnectLatencyBestOfNMs([host UTF8String], port, timeoutMs, 2, &latencyMs, cancellation);
        } else if (pingType == VCPingTypeICMP) {
            rc = ICMPLatencyBestOfNMs([host UTF8String], timeoutMs, 2, &latencyMs, cancellation);
        }
        ok = (rc == 0 && latencyMs >= 0);
    }

    if ([cancellation isCancelled]) {
        [pool drain];
        return;
    }
    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:6];
    [out setObject:cancellation forKey:@"cancellation"];
    [out setObject:([uri isKindOfClass:[NSString class]] ? uri : @"") forKey:@"uri"];
    [out setObject:[NSNumber numberWithBool:ok] forKey:@"ok"];
    NSString *batchIdentifier = [payload objectForKey:@"batch_identifier"];
    NSNumber *batchToken = [payload objectForKey:@"batch_token"];
    if (batchIdentifier && batchToken) {
        [out setObject:batchIdentifier forKey:@"batch_identifier"];
        [out setObject:batchToken forKey:@"batch_token"];
    }
    if (ok) {
        [out setObject:[NSNumber numberWithInt:latencyMs] forKey:@"ms"];
    }
    if (cancellation.diagnosticReport) [out setObject:cancellation.diagnosticReport forKey:@"diagnostics"];
    [out setObject:[payload objectForKey:@"network_generation"] forKey:@"network_generation"];
    [self performSelectorOnMainThread:@selector(pingResultOnMain:) withObject:out waitUntilDone:NO];

    [pool drain];
}

- (void)pingResultOnMain:(NSDictionary *)payload {
    if ([[payload objectForKey:@"cancellation"] isCancelled] ||
        !VCPingResultIsCurrent([[payload objectForKey:@"network_generation"] unsignedIntegerValue],_pingNetworkGeneration)) return;
    NSString *resultURI = [payload objectForKey:@"uri"];
    if (![resultURI isKindOfClass:[NSString class]] || ![resultURI length]) return;
    if (_pingOwnedMetadata && _pingOwnershipRevision == _metadataRevision &&
        ![_pingOwnedMetadata objectForKey:resultURI]) return;
    if (_pingNetworkDirty || _pingNetworkCheckInFlight) {
        [_pingNetworkResults addObject:payload];
        return;
    }
    if (!VCPingResultIsCurrent([[payload objectForKey:@"network_generation"] unsignedIntegerValue],_pingNetworkGeneration)) return;
    VCPingCancellation *cancellation = [payload objectForKey:@"cancellation"];
    if ([cancellation isCancelled]) return;
    NSString *uri = [payload objectForKey:@"uri"];
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return;

    NSString *batchIdentifier = [payload objectForKey:@"batch_identifier"];
    NSNumber *batchToken = [payload objectForKey:@"batch_token"];
    if (batchIdentifier && batchToken) {
        NSNumber *currentToken = [_subscriptionPingTokenByIdentifier objectForKey:batchIdentifier];
        if (![currentToken isEqualToNumber:batchToken]) {
            return;
        }
    }
    if (!batchIdentifier) {
        if ([_standalonePingCancellationsByURI objectForKey:uri] != cancellation) return;
        [_standalonePingCancellationsByURI removeObjectForKey:uri];
    }

    BOOL ok = [[payload objectForKey:@"ok"] boolValue];
    NSString *display = ok
        ? [NSString stringWithFormat:@"%d ms", [[payload objectForKey:@"ms"] intValue]]
        : VCProbeFailureDisplay([payload objectForKey:@"diagnostics"]);
    if (![_pingOwnedMetadata objectForKey:uri]) _pingDisplayMayContainUnowned = YES;
    [_pingDisplayByURI setObject:display forKey:uri];
    VCRecordAppEvent(@"ping", @"Probe stages",
                     [NSString stringWithFormat:@"network_generation=%lu %@",(unsigned long)_pingNetworkGeneration,
                      VCProbeSummary([payload objectForKey:@"diagnostics"])]);
    if (!batchIdentifier) {
        VCRecordAppEvent(@"ping", @"Configuration ping finished",
                         ok ? [NSString stringWithFormat:@"success=1 latency_ms=%d", [[payload objectForKey:@"ms"] intValue]]
                            : @"success=0");
    }

    BOOL completedSubscriptionPing = NO;
    if (batchIdentifier) {
        VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:batchIdentifier];
        NSMutableSet *pending = batch.pending;
        [pending removeObject:uri];
        [batch.previousDisplays removeObjectForKey:uri];
        if ([pending count] == 0) {
            [_subscriptionPingPendingByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingOperationsByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingTokenByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingItemsByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingReadyIdentifiers removeObject:batchIdentifier];
            completedSubscriptionPing = YES;
        }
    }

    [self refreshVisiblePingAccessoriesForURI:uri];
    if (_sortSubscriptionsByPing && (!batchIdentifier || completedSubscriptionPing)) [self scheduleSubscriptionPingSort];
    if (completedSubscriptionPing) {
        VCRecordAppEvent(@"ping", @"Subscription ping batch finished", nil);
        [self refreshVisibleSubscriptionPingAccessories];
        [self refreshVisibleSubscriptionHeaderAccessories];
    }
}

- (NSOperation *)enqueuePingForURI:(NSString *)uri
                              type:(VCPingType)pingType
                          priority:(NSOperationQueuePriority)priority
                   batchIdentifier:(NSString *)batchIdentifier
                        batchToken:(NSNumber *)batchToken
                           options:(NSDictionary *)options {
    VCPingCancellation *cancellation = [[[VCPingCancellation alloc] init] autorelease];
    NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    uri, @"uri",
                                    [NSNumber numberWithInteger:pingType], @"type",
                                    cancellation, @"cancellation",
                                    nil];
    if (batchIdentifier && batchToken) {
        VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:batchIdentifier];
        [payload addEntriesFromDictionary:batch.options];
        [payload setObject:batchIdentifier forKey:@"batch_identifier"];
        [payload setObject:batchToken forKey:@"batch_token"];
    } else {
        [payload addEntriesFromDictionary:options];
        [payload setObject:[NSNumber numberWithUnsignedInteger:_pingNetworkGeneration] forKey:@"network_generation"];
        cancellation.previousDisplay = [_pingDisplayByURI objectForKey:uri];
        [_standalonePingCancellationsByURI setObject:cancellation forKey:uri];
    }
    if (![_pingOwnedMetadata objectForKey:uri]) _pingDisplayMayContainUnowned = YES;
    [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
    if (!_pingNetworkTimer && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
        _pingNetworkTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(pingNetworkTick:)
                                                         userInfo:nil repeats:YES] retain];
    }
    VCPingOperation *operation = [[[VCPingOperation alloc]
        initWithTarget:self payload:payload cancellation:cancellation] autorelease];
    operation.queuePriority = priority;
    [operation setCompletionBlock:^{
        [self performSelectorOnMainThread:@selector(pingOperationFinished:) withObject:cancellation waitUntilDone:NO];
    }];
    [_pingQueue addOperation:operation];
    return operation;
}

- (void)startPingForURI:(NSString *)uri type:(VCPingType)pingType {
    if (![uri isKindOfClass:[NSString class]] || ![uri length]) return;
    for (NSDictionary *start in _pingNetworkStarts) if ([[start objectForKey:@"uri"] isEqual:uri]) return;
    [_pingNetworkStarts addObject:@{@"uri":uri, @"options":[self pingOptionsForType:pingType]}];
    [self refreshPingNetworkState];
}

- (void)beginPingForURI:(NSString *)uri type:(VCPingType)pingType options:(NSDictionary *)options {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return;
    if ([_standalonePingCancellationsByURI objectForKey:uri]) return;
    if ([self isURIInActiveSubscriptionPing:uri]) return;
    if ([[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) return;

    VCRecordAppEvent(@"ping", @"Configuration ping started",
                     [NSString stringWithFormat:@"type=%ld", (long)pingType]);
    [self enqueuePingForURI:uri
                       type:pingType
                   priority:NSOperationQueuePriorityHigh
            batchIdentifier:nil
                 batchToken:nil options:options];
    [self refreshVisiblePingAccessoriesForURI:uri];
}

- (void)pingButtonPressed:(UIButton *)sender {
    UIView *view = sender;
    while (view && ![view isKindOfClass:[UITableViewCell class]]) view = view.superview;
    if (!view) return;
    NSIndexPath *indexPath = [_tableView indexPathForCell:(UITableViewCell *)view];
    if (!indexPath) return;
    NSString *uri = nil;

    if (indexPath.section == 0) {
        NSInteger idx = indexPath.row;
        if (idx >= 0 && idx < (NSInteger)[_configs count]) {
            NSDictionary *cfg = [_configs objectAtIndex:idx];
            uri = [cfg objectForKey:@"uri"];
        }
    } else if (indexPath.section == 1) {
        NSInteger subIdx = -1, itemIdx = -1;
        BOOL isHeader = YES;
        if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader] || isHeader) return;
        if ([self isSubscriptionPingInProgressAtIndex:subIdx]) return;
        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        if (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) {
            uri = [items objectAtIndex:itemIdx];
        }
    }

    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) {
        return;
    }
    if ([_standalonePingCancellationsByURI objectForKey:uri]) return;
    if ([[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) return;

    sender.enabled = NO;
    [self startPingForURI:uri type:VCSelectedPingType()];
}

- (void)startSubscriptionPingAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if (!identifier || ![items count] || [self isSubscriptionPingInProgressAtIndex:subIdx]) return;
    [_pingNetworkStarts addObject:@{@"index":@(subIdx), @"identifier":identifier, @"items":items,
        @"options":[self pingOptionsForType:VCSelectedPingType()]}];
    [self refreshVisibleSubscriptionHeaderAccessories];
    [self refreshPingNetworkState];
}

- (void)beginSubscriptionPingAtIndex:(NSInteger)subIdx options:(NSDictionary *)initialOptions {
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([items count] == 0 || [self isSubscriptionPingInProgressAtIndex:subIdx]) return;

    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;

    _nextSubscriptionPingToken++;
    if (_nextSubscriptionPingToken == 0) _nextSubscriptionPingToken++;
    NSNumber *batchToken = [NSNumber numberWithUnsignedInteger:_nextSubscriptionPingToken];
    [_subscriptionPingTokenByIdentifier setObject:batchToken forKey:identifier];
    [_subscriptionPingItemsByIdentifier setObject:items forKey:identifier];

    VCPingType pingType = [[initialOptions objectForKey:@"type"] integerValue];
    NSMutableDictionary *options = [[initialOptions mutableCopy] autorelease];
    [options setObject:@(_pingNetworkGeneration) forKey:@"network_generation"];
    VCPingCancellation *preparation = [[[VCPingCancellation alloc] init] autorelease];
    NSArray *snapshot = [items copy];
    [_subscriptionPingPreparationByIdentifier setObject:preparation forKey:identifier];
    VCRecordAppEvent(@"ping", @"Subscription ping batch started",
                     [NSString stringWithFormat:@"configs=%lu type=%ld",
                      (unsigned long)[items count], (long)pingType]);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        VCPingBatch *batch = [[VCPingBatch alloc] initWithURIs:snapshot options:options cancellation:preparation];
        [snapshot release];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (![preparation isCancelled] &&
                [[_subscriptionPingTokenByIdentifier objectForKey:identifier] isEqual:batchToken]) {
                [_subscriptionPingPreparationByIdentifier removeObjectForKey:identifier];
                if ([batch.pending count]) {
                    [_subscriptionPingPendingByIdentifier setObject:batch forKey:identifier];
                    [_subscriptionPingOperationsByIdentifier setObject:batch.operations forKey:identifier];
                    [_subscriptionPingPreviousDisplayByIdentifier setObject:batch.previousDisplays forKey:identifier];
                    [_subscriptionPingReadyIdentifiers addObject:identifier];
                    [self pumpSubscriptionPings];
                } else {
                    [_subscriptionPingTokenByIdentifier removeObjectForKey:identifier];
                    [_subscriptionPingItemsByIdentifier removeObjectForKey:identifier];
                }
                [self refreshVisibleSubscriptionPingAccessories];
                [self refreshVisibleSubscriptionHeaderAccessories];
            }
            [batch release];
        });
        [pool drain];
    });
    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
}

- (void)pumpSubscriptionPings {
    if (_pingNetworkDirty || _pingNetworkCheckInFlight) return;
    NSUInteger occupied = 0;
    for (NSOperation *operation in [_pingQueue operations]) if (![operation isFinished]) occupied++;
    while (occupied < 4 && [_subscriptionPingReadyIdentifiers count]) {
        NSString *identifier = [[[_subscriptionPingReadyIdentifiers objectAtIndex:0] retain] autorelease];
        [_subscriptionPingReadyIdentifiers removeObjectAtIndex:0];
        VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
        NSString *uri = [batch nextURI];
        if (!uri) continue;
        [_subscriptionPingReadyIdentifiers addObject:identifier];
        id previous = [_pingDisplayByURI objectForKey:uri];
        if ([previous isEqual:kVCPingLoadingValue]) {
            for (NSDictionary *displays in [_subscriptionPingPreviousDisplayByIdentifier allValues]) {
                if ([displays objectForKey:uri]) { previous = [displays objectForKey:uri]; break; }
            }
            VCPingCancellation *standalone = [_standalonePingCancellationsByURI objectForKey:uri];
            if (standalone) previous = standalone.previousDisplay;
        }
        [batch.previousDisplays setObject:(previous ? previous : (id)[NSNull null]) forKey:uri];
        NSOperation *operation = [self enqueuePingForURI:uri type:[[batch.options objectForKey:@"type"] integerValue]
            priority:NSOperationQueuePriorityNormal batchIdentifier:identifier
            batchToken:[_subscriptionPingTokenByIdentifier objectForKey:identifier] options:batch.options];
        [batch.operations addObject:operation];
        occupied++;
    }
}

- (void)pingOperationFinished:(VCPingCancellation *)cancellation {
    for (NSMutableArray *operations in [_subscriptionPingOperationsByIdentifier allValues]) {
        for (NSUInteger i = [operations count]; i > 0; i--) {
            VCPingOperation *operation = [operations objectAtIndex:i - 1];
            if (operation.cancellation == cancellation) [operations removeObjectAtIndex:i - 1];
        }
    }
    [self pumpSubscriptionPings];
}

- (BOOL)isURIInActiveSubscriptionPing:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    for (NSString *identifier in _subscriptionPingPendingByIdentifier) {
        VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
        if ([batch.pending containsObject:uri]) return YES;
    }
    return NO;
}

- (void)stopSubscriptionPingAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;
    [self stopSubscriptionPingIdentifier:identifier];
    [self showStatus:@"Subscription ping stopped" ok:YES];
}

- (void)stopSubscriptionPingIdentifier:(NSString *)identifier {
    for (NSUInteger i = [_pingNetworkStarts count]; i > 0; i--)
        if ([[[_pingNetworkStarts objectAtIndex:i - 1] objectForKey:@"identifier"] isEqual:identifier])
            [_pingNetworkStarts removeObjectAtIndex:i - 1];

    NSArray *operations = [[_subscriptionPingOperationsByIdentifier objectForKey:identifier] copy];
    VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
    NSUInteger pendingCount = [batch.pending count];
    NSDictionary *previousDisplay = [[_subscriptionPingPreviousDisplayByIdentifier objectForKey:identifier] copy];

    [_subscriptionPingPendingByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingOperationsByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingTokenByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingItemsByIdentifier removeObjectForKey:identifier];
    [[_subscriptionPingPreparationByIdentifier objectForKey:identifier] cancel];
    [_subscriptionPingPreparationByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingReadyIdentifiers removeObject:identifier];

    for (NSOperation *operation in operations) {
        [operation cancel];
    }

    for (NSString *uri in previousDisplay) {
        if (![[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) continue;
        if ([self isURIInActiveSubscriptionPing:uri] || [_standalonePingCancellationsByURI objectForKey:uri]) {
            continue;
        }
        id previous = [previousDisplay objectForKey:uri];
        if ([previous isKindOfClass:[NSString class]] && [previous length] > 0) {
            [_pingDisplayByURI setObject:previous forKey:uri];
        } else {
            [_pingDisplayByURI removeObjectForKey:uri];
        }
    }

    [operations release];
    [previousDisplay release];
    [self pumpSubscriptionPings];

    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
    if (_sortSubscriptionsByPing) [self scheduleSubscriptionPingSort];
    VCRecordAppEvent(@"ping", @"Subscription ping batch canceled",
                     [NSString stringWithFormat:@"pending=%lu", (unsigned long)pendingCount]);
}

- (void)subscriptionPingButtonPressed:(UIButton *)sender {
    NSInteger subIdx = sender.tag - kVCSubscriptionPingButtonTagBase;
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([self isSubscriptionPingInProgressAtIndex:subIdx]) {
        [self stopSubscriptionPingAtIndex:subIdx];
        return;
    }
    if ([items count] == 0) return;

    [self startSubscriptionPingAtIndex:subIdx];
}

- (void)stopAllPings {
    if (!_publishingPingNetwork) [_pingNetworkStarts removeAllObjects];
    [_pingNetworkResults removeAllObjects];
    if ([_standalonePingCancellationsByURI count] == 0 &&
        [_subscriptionPingTokenByIdentifier count] == 0) return;

    NSMutableDictionary *previousDisplay = [NSMutableDictionary dictionary];
    for (NSDictionary *previous in [_subscriptionPingPreviousDisplayByIdentifier allValues]) {
        [previousDisplay addEntriesFromDictionary:previous];
    }
    for (NSString *uri in _standalonePingCancellationsByURI) {
        VCPingCancellation *cancellation = [_standalonePingCancellationsByURI objectForKey:uri];
        [previousDisplay setObject:(cancellation.previousDisplay ? (id)cancellation.previousDisplay : (id)[NSNull null]) forKey:uri];
        [cancellation cancel];
    }
    [_pingQueue cancelAllOperations];
    for (VCPingCancellation *preparation in [_subscriptionPingPreparationByIdentifier allValues]) [preparation cancel];
    [_subscriptionPingPreparationByIdentifier removeAllObjects];
    [_subscriptionPingReadyIdentifiers removeAllObjects];
    [_standalonePingCancellationsByURI removeAllObjects];
    [_subscriptionPingPendingByIdentifier removeAllObjects];
    [_subscriptionPingOperationsByIdentifier removeAllObjects];
    [_subscriptionPingPreviousDisplayByIdentifier removeAllObjects];
    [_subscriptionPingTokenByIdentifier removeAllObjects];
    [_subscriptionPingItemsByIdentifier removeAllObjects];

    NSUInteger stoppedCount = 0;
    for (NSString *uri in previousDisplay) {
        if (![[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) continue;
        id previous = [previousDisplay objectForKey:uri];
        if ([previous isKindOfClass:[NSString class]] && [previous length] > 0) [_pingDisplayByURI setObject:previous forKey:uri];
        else [_pingDisplayByURI removeObjectForKey:uri];
        stoppedCount++;
    }
    [self refreshVisiblePingAccessoriesForURI:nil];
    [self refreshVisibleSubscriptionHeaderAccessories];
    VCRecordAppEvent(@"ping", @"All pings canceled",
                     [NSString stringWithFormat:@"pending=%lu", (unsigned long)stoppedCount]);
    if (_sortSubscriptionsByPing) [self scheduleSubscriptionPingSort];
}

- (void)prunePingStateForMetadata:(NSDictionary *)metadata {
    if (![metadata isKindOfClass:[NSDictionary class]]) return;
    BOOL unchanged = metadata == _pingOwnedMetadata;
    NSDictionary *snapshot = [metadata copy];
    [_pingOwnedMetadata release]; _pingOwnedMetadata = snapshot;
    _pingOwnershipRevision = _metadataRevision;
    NSMutableDictionary *itemsByIdentifier = [NSMutableDictionary dictionaryWithCapacity:[_subscriptions count]];
    for (NSUInteger index = 0; index < [_subscriptions count]; index++) {
        NSString *identifier = [self subscriptionPingIdentifierAtIndex:index];
        NSArray *items = [[_subscriptions objectAtIndex:index] objectForKey:@"items"];
        if (identifier && [items isKindOfClass:[NSArray class]]) [itemsByIdentifier setObject:items forKey:identifier];
    }
    for (NSString *identifier in [[[_subscriptionPingItemsByIdentifier allKeys] copy] autorelease]) {
        NSArray *current = [itemsByIdentifier objectForKey:identifier];
        NSArray *previous = [_subscriptionPingItemsByIdentifier objectForKey:identifier];
        if (!current || (current != previous && ![current isEqual:previous])) [self stopSubscriptionPingIdentifier:identifier];
    }
    for (NSString *uri in [[[_standalonePingCancellationsByURI allKeys] copy] autorelease]) {
        if ([metadata objectForKey:uri]) continue;
        [[_standalonePingCancellationsByURI objectForKey:uri] cancel];
        [_standalonePingCancellationsByURI removeObjectForKey:uri];
    }
    if (!unchanged || _pingDisplayMayContainUnowned) {
        NSMutableDictionary *displays = [[NSMutableDictionary alloc] initWithCapacity:MIN([metadata count], [_pingDisplayByURI count])];
        NSDictionary *keys = [metadata count] < [_pingDisplayByURI count] ? metadata : _pingDisplayByURI;
        for (NSString *uri in keys) {
            id display = [_pingDisplayByURI objectForKey:uri];
            if (display && [metadata objectForKey:uri]) [displays setObject:display forKey:uri];
        }
        [_pingDisplayByURI release]; _pingDisplayByURI = displays;
    }
    _pingDisplayMayContainUnowned = NO;
    for (NSMutableArray *requests in @[_pingNetworkStarts, _pingNetworkResults]) {
        for (NSUInteger index = [requests count]; index > 0; index--) {
            NSDictionary *request = [requests objectAtIndex:index - 1];
            NSString *uri = [request objectForKey:@"uri"];
            NSString *identifier = [request objectForKey:@"identifier"];
            NSArray *items = identifier ? [itemsByIdentifier objectForKey:identifier] : nil;
            if (uri ? ![metadata objectForKey:uri] : ![items isEqual:[request objectForKey:@"items"]])
                [requests removeObjectAtIndex:index - 1];
        }
    }
}

@end
