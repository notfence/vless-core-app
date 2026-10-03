#import "main_screen.h"

@implementation MainVC (VCMainPing)

- (void)pingWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VCPingCancellation *cancellation = [payload objectForKey:@"cancellation"];
    if ([cancellation isCancelled]) {
        [pool drain];
        return;
    }
    NSString *uri = [payload objectForKey:@"uri"];
    VCPingType pingType = (VCPingType)[[payload objectForKey:@"type"] integerValue];
    NSString *host = nil;
    uint16_t port = 0;
    int latencyMs = -1;
    BOOL ok = NO;
    NSString *scheme = [self schemeFromURIString:uri];
    BOOL isSOCKS5Config = [scheme isEqualToString:@"socks5"];
    BOOL parsed = isSOCKS5Config
        ? [self parseSOCKS5Host:&host port:&port fromURI:uri]
        : [self parseVLESSHost:&host port:&port fromURI:uri];
    if (parsed) {
        int rc = -1;

        if (pingType == VCPingTypeProxyGET) {
            NSString *xrayVersion = VCActiveXrayVersion();
            rc = ProxyGetViaTempCoreMs([uri UTF8String], [xrayVersion UTF8String],
                                       5000, 2, &latencyMs, cancellation);
        } else if (pingType == VCPingTypeTCP) {
            rc = ConnectLatencyBestOfNMs([host UTF8String], port, 3500, 2, &latencyMs, cancellation);
        } else if (pingType == VCPingTypeICMP) {
            rc = ICMPLatencyBestOfNMs([host UTF8String], 3500, 2, &latencyMs, cancellation);
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
    [self performSelectorOnMainThread:@selector(pingResultOnMain:) withObject:out waitUntilDone:NO];

    [pool drain];
}

- (void)pingResultOnMain:(NSDictionary *)payload {
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
        : kVCPingFailureValue;
    [_pingDisplayByURI setObject:display forKey:uri];
    if (!batchIdentifier) {
        VCRecordAppEvent(@"ping", @"Configuration ping finished",
                         ok ? [NSString stringWithFormat:@"success=1 latency_ms=%d", [[payload objectForKey:@"ms"] intValue]]
                            : @"success=0");
    }

    BOOL completedSubscriptionPing = NO;
    if (batchIdentifier) {
        NSMutableSet *pending = [_subscriptionPingPendingByIdentifier objectForKey:batchIdentifier];
        [pending removeObject:uri];
        if ([pending count] == 0) {
            [_subscriptionPingPendingByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingOperationsByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:batchIdentifier];
            [_subscriptionPingTokenByIdentifier removeObjectForKey:batchIdentifier];
            completedSubscriptionPing = YES;
        }
    }

    [self refreshVisiblePingAccessoriesForURI:uri];
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
        [payload setObject:batchIdentifier forKey:@"batch_identifier"];
        [payload setObject:batchToken forKey:@"batch_token"];
    } else {
        cancellation.previousDisplay = [_pingDisplayByURI objectForKey:uri];
        [_standalonePingCancellationsByURI setObject:cancellation forKey:uri];
    }
    [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
    VCPingOperation *operation = [[[VCPingOperation alloc]
        initWithTarget:self payload:payload cancellation:cancellation] autorelease];
    operation.queuePriority = priority;
    [_pingQueue addOperation:operation];
    return operation;
}

- (void)startPingForURI:(NSString *)uri type:(VCPingType)pingType {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return;
    if ([_standalonePingCancellationsByURI objectForKey:uri]) return;
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
    NSInteger tag = sender.tag;
    NSString *uri = nil;

    if (tag >= 10000 && tag < 20000) {
        NSInteger idx = tag - 10000;
        if (idx >= 0 && idx < (NSInteger)[_configs count]) {
            NSDictionary *cfg = [_configs objectAtIndex:idx];
            uri = [cfg objectForKey:@"uri"];
        }
    } else if (tag >= 20000) {
        NSInteger code = tag - 20000;
        NSInteger subIdx = code / 1000;
        NSInteger itemIdx = code % 1000;
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
    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if ([items count] == 0 || [self isSubscriptionPingInProgressAtIndex:subIdx]) return;

    NSMutableArray *urisToPing = [NSMutableArray arrayWithCapacity:[items count]];
    NSMutableSet *seenURIs = [NSMutableSet setWithCapacity:[items count]];
    for (NSString *uri in items) {
        if (![uri isKindOfClass:[NSString class]] || [uri length] == 0 ||
            [seenURIs containsObject:uri]) {
            continue;
        }
        [seenURIs addObject:uri];
        [urisToPing addObject:uri];
    }
    if ([urisToPing count] == 0) return;

    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;
    [_subscriptionPingPendingByIdentifier setObject:[NSMutableSet setWithArray:urisToPing]
                                             forKey:identifier];

    _nextSubscriptionPingToken++;
    if (_nextSubscriptionPingToken == 0) _nextSubscriptionPingToken++;
    NSNumber *batchToken = [NSNumber numberWithUnsignedInteger:_nextSubscriptionPingToken];
    [_subscriptionPingTokenByIdentifier setObject:batchToken forKey:identifier];

    NSMutableDictionary *previousDisplay = [NSMutableDictionary dictionaryWithCapacity:[urisToPing count]];
    NSMutableArray *operations = [NSMutableArray arrayWithCapacity:[urisToPing count]];
    [_subscriptionPingPreviousDisplayByIdentifier setObject:previousDisplay forKey:identifier];
    [_subscriptionPingOperationsByIdentifier setObject:operations forKey:identifier];

    VCPingType pingType = VCSelectedPingType();
    VCRecordAppEvent(@"ping", @"Subscription ping batch started",
                     [NSString stringWithFormat:@"configs=%lu type=%ld",
                      (unsigned long)[urisToPing count], (long)pingType]);
    for (NSString *uri in urisToPing) {
        NSString *previous = [_pingDisplayByURI objectForKey:uri];
        if ([previous length] > 0 && ![previous isEqualToString:kVCPingLoadingValue]) {
            [previousDisplay setObject:previous forKey:uri];
        }
        NSOperation *operation = [self enqueuePingForURI:uri
                                                    type:pingType
                                                priority:NSOperationQueuePriorityNormal
                                         batchIdentifier:identifier
                                              batchToken:batchToken];
        if (operation) [operations addObject:operation];
    }
    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
}

- (BOOL)isURIInActiveSubscriptionPing:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    for (NSString *identifier in _subscriptionPingPendingByIdentifier) {
        NSSet *pending = [_subscriptionPingPendingByIdentifier objectForKey:identifier];
        if ([pending containsObject:uri]) return YES;
    }
    return NO;
}

- (void)stopSubscriptionPingAtIndex:(NSInteger)subIdx {
    NSString *identifier = [self subscriptionPingIdentifierAtIndex:subIdx];
    if (!identifier) return;

    NSArray *operations = [[_subscriptionPingOperationsByIdentifier objectForKey:identifier] copy];
    NSSet *pending = [[_subscriptionPingPendingByIdentifier objectForKey:identifier] copy];
    NSUInteger pendingCount = [pending count];
    NSDictionary *previousDisplay = [[_subscriptionPingPreviousDisplayByIdentifier objectForKey:identifier] copy];

    [_subscriptionPingPendingByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingOperationsByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingPreviousDisplayByIdentifier removeObjectForKey:identifier];
    [_subscriptionPingTokenByIdentifier removeObjectForKey:identifier];

    for (NSOperation *operation in operations) {
        [operation cancel];
    }

    for (NSString *uri in pending) {
        if (![[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) continue;
        if ([self isURIInActiveSubscriptionPing:uri] || [_standalonePingCancellationsByURI objectForKey:uri]) {
            continue;
        }
        NSString *previous = [previousDisplay objectForKey:uri];
        if ([previous length] > 0) {
            [_pingDisplayByURI setObject:previous forKey:uri];
        } else {
            [_pingDisplayByURI removeObjectForKey:uri];
        }
    }

    [operations release];
    [pending release];
    [previousDisplay release];

    [self refreshVisibleSubscriptionPingAccessories];
    [self refreshVisibleSubscriptionHeaderAccessories];
    [self showStatus:@"Subscription ping stopped" ok:YES];
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
        [_subscriptionPingPendingByIdentifier count] == 0) return;

    NSMutableDictionary *previousDisplay = [NSMutableDictionary dictionary];
    for (NSDictionary *previous in [_subscriptionPingPreviousDisplayByIdentifier allValues]) {
        [previousDisplay addEntriesFromDictionary:previous];
    }
    for (NSString *uri in _standalonePingCancellationsByURI) {
        VCPingCancellation *cancellation = [_standalonePingCancellationsByURI objectForKey:uri];
        if ([cancellation.previousDisplay length] > 0) {
            [previousDisplay setObject:cancellation.previousDisplay forKey:uri];
        }
        [cancellation cancel];
    }
    [_pingQueue cancelAllOperations];
    [_standalonePingCancellationsByURI removeAllObjects];
    [_subscriptionPingPendingByIdentifier removeAllObjects];
    [_subscriptionPingOperationsByIdentifier removeAllObjects];
    [_subscriptionPingPreviousDisplayByIdentifier removeAllObjects];
    [_subscriptionPingTokenByIdentifier removeAllObjects];

    NSArray *uris = [_pingDisplayByURI allKeys];
    NSUInteger stoppedCount = 0;
    for (NSString *uri in uris) {
        if (![[_pingDisplayByURI objectForKey:uri] isEqualToString:kVCPingLoadingValue]) continue;
        NSString *previous = [previousDisplay objectForKey:uri];
        if ([previous length] > 0) [_pingDisplayByURI setObject:previous forKey:uri];
        else [_pingDisplayByURI removeObjectForKey:uri];
        stoppedCount++;
    }
    [self refreshVisiblePingAccessoriesForURI:nil];
    [self refreshVisibleSubscriptionHeaderAccessories];
    VCRecordAppEvent(@"ping", @"All pings canceled",
                     [NSString stringWithFormat:@"pending=%lu", (unsigned long)stoppedCount]);
}

@end
