#import "main_screen.h"

@implementation MainVC (VCMainPing)

- (void)refreshPingNetworkState {
    NSString *signature = VCPingNetworkSignature();
    if (!signature) return;
    BOOL changed = VCPingUpdateNetwork(self,signature,&_pingNetworkSignature,&_pingNetworkGeneration,_pingDisplayByURI);
    if (changed) {
        if (_sortSubscriptionsByPing) [self scheduleSubscriptionPingSort];
        [self refreshVisiblePingAccessoriesForURI:nil];
        [self refreshVisibleSubscriptionHeaderAccessories];
        VCRecordAppEvent(@"ping", @"Network changed; ping results cleared", nil);
    }
    if ([_pingDisplayByURI count] == 0 && _pingNetworkTimer) {
        [_pingNetworkTimer invalidate];
        [_pingNetworkTimer release];
        _pingNetworkTimer = nil;
    }
}

- (void)pingNetworkTick:(NSTimer *)timer {
    (void)timer;
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
            NSString *xrayVersion = VCActiveXrayVersion();
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
    [self refreshPingNetworkState];
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
                        batchToken:(NSNumber *)batchToken {
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
        [payload setObject:[NSNumber numberWithUnsignedInteger:_pingNetworkGeneration] forKey:@"network_generation"];
        [payload setObject:@(VCPingTimeoutSecondsInDefaults([NSUserDefaults standardUserDefaults])*1000) forKey:@"timeout_ms"];
        if (pingType == VCPingTypeProxyGET) {
            [payload setObject:[[VCSelectedProxyPingURL() copy] autorelease] forKey:@"probe_url"];
            [payload setObject:@(VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults])) forKey:@"use_xmux"];
        }
        cancellation.previousDisplay = [_pingDisplayByURI objectForKey:uri];
        [_standalonePingCancellationsByURI setObject:cancellation forKey:uri];
    }
    [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
    if (!_pingNetworkTimer) {
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
    [self refreshPingNetworkState];
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
                 batchToken:nil];
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
    [self refreshPingNetworkState];
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([items count] == 0 || [self isSubscriptionPingInProgressAtIndex:subIdx]) return;

    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;

    _nextSubscriptionPingToken++;
    if (_nextSubscriptionPingToken == 0) _nextSubscriptionPingToken++;
    NSNumber *batchToken = [NSNumber numberWithUnsignedInteger:_nextSubscriptionPingToken];
    [_subscriptionPingTokenByIdentifier setObject:batchToken forKey:identifier];

    VCPingType pingType = VCSelectedPingType();
    NSDictionary *options = @{@"type":@(pingType), @"network_generation":@(_pingNetworkGeneration),
        @"timeout_ms":@(VCPingTimeoutSecondsInDefaults([NSUserDefaults standardUserDefaults])*1000),
        @"probe_url":[[VCSelectedProxyPingURL() copy] autorelease],
        @"use_xmux":@(VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults]))};
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
            batchToken:[_subscriptionPingTokenByIdentifier objectForKey:identifier]];
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

    NSArray *operations = [[_subscriptionPingOperationsByIdentifier objectForKey:identifier] copy];
    VCPingBatch *batch = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
    NSUInteger pendingCount = [batch.pending count];
    NSDictionary *previousDisplay = [[_subscriptionPingPreviousDisplayByIdentifier objectForKey:identifier] copy];

    [_subscriptionPingPendingByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingOperationsByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingTokenByIdentifier removeObjectForKey:identifier];
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
    [self showStatus:@"Subscription ping stopped" ok:YES];
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

@end
