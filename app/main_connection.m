#import "main_screen.h"

@implementation MainVC (VCMainConnection)

- (NSString *)sanitizeDaemonText:(NSString *)text {
    if (!text) return @"";
    NSString *s = [text stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)formatDuration:(NSTimeInterval)seconds {
    return VCFormatDuration(seconds);
}

- (void)refreshStatusText {
    NSString *base = _statusBaseText ? _statusBaseText : @"";
    if ([base isEqualToString:@"Ready"] && [_availableUpdateVersion length] > 0) {
        _statusLabel.text = [NSString stringWithFormat:@"Ready (New version available: %@)",
                            _availableUpdateVersion];
    } else {
        _statusLabel.text = base;
    }
}

- (void)refreshUptimeText {
    if (![self isMainUIActive]) return;
    if (_connected && _connectedSince > 0) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - _connectedSince;
        _uptimeLabel.text = [self formatDuration:delta];
    } else {
        _uptimeLabel.text = @"00:00:00";
    }
}

- (void)startUptimeTimerWithDaemonResponse:(NSString *)response {
    BOOL hadTimer = _uptimeTimer != nil;
    _connectedSince = VCConnectedSince(response, [[NSDate date] timeIntervalSince1970]);
    [self updatePeriodicUIActivity];
    if (hadTimer) [self refreshUptimeText];
}

- (void)stopUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;
    _connectedSince = 0;
    [self refreshUptimeText];
}

- (void)uptimeTick:(NSTimer *)timer {
    (void)timer;
    if (![self isMainUIActive]) return;
    [self refreshUptimeText];
    [self reconcileConnectionStateWithDaemon];
}

- (void)reconcileConnectionStateWithDaemon {
    if (![self isMainUIActive] || !_connected || [self isConnectionActionInProgress] || _daemonStatusCheckInFlight) return;

    _daemonStatusCheckInFlight = YES;
    NSTimeInterval expectedConnectedSince = _connectedSince;
    NSUInteger generation = _connectionActionGeneration;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *response = [self sanitizeDaemonText:VCReadDaemonStatus()];
        BOOL disconnected = [response hasPrefix:@"OK disconnected"];

        dispatch_async(dispatch_get_main_queue(), ^{
            _daemonStatusCheckInFlight = NO;
            if (![self isMainUIActive]) return;
            if (!VCConnectionLossApplies(disconnected, _connected, generation, _connectionActionGeneration,
                                         [self isConnectionActionInProgress], expectedConnectedSince, _connectedSince)) {
                return;
            }

            _connected = NO;
            _connectedWithProtectedLogs = NO;
            [self stopUptimeTimer];
            [self updateConnectButton];
            [self showStatus:@"Connection lost" ok:NO];
            VCRecordAppEvent(@"connection", @"Daemon reported connection lost", nil);
        });
        [pool drain];
    });
}

- (void)applicationDidBecomeActiveNotification:(NSNotification *)notification {
    (void)notification;
    [self refreshPingNetworkState];
    if (!_pingNetworkTimer && ([_pingDisplayByURI count] || [_standalonePingCancellationsByURI count] ||
        [_subscriptionPingTokenByIdentifier count] || [_pingNetworkStarts count])) {
        _pingNetworkTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(pingNetworkTick:)
                                                        userInfo:nil repeats:YES] retain];
    }
    [self updatePeriodicUIActivity];
    if (_mainScreenVisible) [self queryInitialStatus];
}

- (BOOL)isMainUIActive {
    return _mainScreenVisible && [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
}

- (void)updatePeriodicUIActivity {
    BOOL active = [self isMainUIActive];
    if (!active || !_connected) {
        [_uptimeTimer invalidate]; [_uptimeTimer release]; _uptimeTimer = nil;
    } else if (!_uptimeTimer) {
        [self refreshUptimeText];
        _uptimeTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(uptimeTick:)
                                                     userInfo:nil repeats:YES] retain];
    }
    if (!active || !_showingTerminal) {
        [_logTimer invalidate]; [_logTimer release]; _logTimer = nil;
    } else if (!_logTimer) {
        [self refreshLogs];
        _logTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(refreshLogsTick:)
                                                  userInfo:nil repeats:YES] retain];
    }
    if (_periodicUIActive && !active) {
        _logReadGeneration++;
        _logReadPending = NO;
    }
    _periodicUIActive = active;
}

- (void)applicationDidEnterBackgroundNotification:(NSNotification *)notification {
    (void)notification;
    [self updatePeriodicUIActivity];
    [_pingNetworkTimer invalidate]; [_pingNetworkTimer release]; _pingNetworkTimer = nil;
    _pingNetworkDirty = YES;
}

- (void)showStatus:(NSString *)text ok:(BOOL)ok {
    [_statusBaseText release];
    _statusBaseText = [[self sanitizeDaemonText:text] copy];
    _statusOK = ok;
    _statusLabel.textColor = ok ? VCSuccessColor() : VCErrorColor();
    [self refreshStatusText];
}

- (BOOL)isXHTTPTransportURI:(NSString *)uri {
    return [[VCProfiles() transportTypeFromURI:uri] isEqual:@"xhttp"];
}

- (NSString *)xhttpPinKeyFromURI:(NSString *)uri {
    NSString *host = nil;
    uint16_t port = 443;
    if (![VCProfiles() parseServerHost:&host port:&port fromURI:uri]) return nil;
    NSString *trimmedHost = [[self safeTrim:host] lowercaseString];
    if (![trimmedHost isKindOfClass:[NSString class]] || [trimmedHost length] == 0) return nil;
    return [NSString stringWithFormat:@"%@:%u", trimmedHost, (unsigned int)port];
}

- (NSString *)xhttpTOFUPinMismatchStatusForURI:(NSString *)uri {
    NSString *tail = ReadDaemonLog(1, 12288);
    if (![tail isKindOfClass:[NSString class]] || [tail length] == 0) return nil;

    NSString *lowerTail = [tail lowercaseString];
    if ([lowerTail rangeOfString:@"tofu pin mismatch"].location == NSNotFound) return nil;

    NSString *pinKey = [self xhttpPinKeyFromURI:uri];
    if ([pinKey length] > 0) {
        NSString *needle = [NSString stringWithFormat:@"tofu pin mismatch for %@", pinKey];
        if ([lowerTail rangeOfString:needle].location == NSNotFound &&
            [lowerTail rangeOfString:pinKey].location == NSNotFound) {
            return nil;
        }
        return [NSString stringWithFormat:@"Error: TOFU pin mismatch for %@ (clear old entry in xhttp-pins.txt)", pinKey];
    }

    return @"Error: TOFU pin mismatch (clear old entry in xhttp-pins.txt)";
}

- (NSInteger)socksPortFromDaemonStatusText:(NSString *)statusText {
    if (![statusText isKindOfClass:[NSString class]] || [statusText length] == 0) return -1;
    NSRange marker = [statusText rangeOfString:@"socks="];
    if (marker.location == NSNotFound) return -1;

    NSUInteger start = marker.location + marker.length;
    NSUInteger end = start;
    while (end < [statusText length]) {
        unichar c = [statusText characterAtIndex:end];
        if (c < '0' || c > '9') break;
        end++;
    }
    if (end <= start) return -1;

    NSInteger p = [[statusText substringWithRange:NSMakeRange(start, end - start)] integerValue];
    if (p <= 0 || p > 65535) return -1;
    return p;
}

- (NSInteger)currentDaemonSocksPort {
    NSString *status = [self sanitizeDaemonText:VCReadDaemonStatus()];
    if (![status hasPrefix:@"OK connected"]) return -1;
    return [self socksPortFromDaemonStatusText:status];
}

- (void)xhttpConnectHealthCheckWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];

    BOOL ok = NO;
    for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        NSInteger socksPort = [self currentDaemonSocksPort];
        if (socksPort > 0 && socksPort <= 65535) {
            int ms = 0;
            if (TunnelConnectOnceMs((uint16_t)socksPort, 3500, &ms) == 0) {
                ok = YES;
                break;
            }
        }
        usleep(250 * 1000);
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:3];
    [out setObject:(ok ? @"1" : @"0") forKey:@"ok"];
    if (![uri isKindOfClass:[NSString class]]) uri = @"";
    [out setObject:uri forKey:@"uri"];
    [out setObject:[payload objectForKey:@"generation"] forKey:@"generation"];
    [out setObject:[payload objectForKey:@"since"] forKey:@"since"];

    if (!ok) {
        NSString *reason = [self xhttpTOFUPinMismatchStatusForURI:uri];
        if (![reason isKindOfClass:[NSString class]] || [reason length] == 0) {
            reason = @"Error: xhttp tunnel failed health-check";
        }
        [out setObject:reason forKey:@"reason"];
    }

    [self performSelectorOnMainThread:@selector(xhttpConnectHealthCheckResultOnMain:) withObject:out waitUntilDone:NO];
    [pool drain];
}

- (void)xhttpConnectHealthCheckResultOnMain:(NSDictionary *)payload {
    BOOL ok = [[payload objectForKey:@"ok"] isEqualToString:@"1"];
    if (ok) return;
    if (!VCConnectionLossApplies(YES,_connected,[[payload objectForKey:@"generation"] unsignedIntegerValue],_connectionActionGeneration,
                                [self isConnectionActionInProgress],[[payload objectForKey:@"since"] doubleValue],_connectedSince)) return;
    if (![[payload objectForKey:@"uri"] isEqual:[self uriForCurrentSelection]]) return;

    NSString *reason = [payload objectForKey:@"reason"];
    if ([reason rangeOfString:@"TOFU pin mismatch"].location == NSNotFound) {
        return;
    }

    _connectionActionInProgress = YES;
    NSUInteger generation = ++_connectionActionGeneration;
    [self updateConnectButton];
    VCSendCommandAsync(@"DISCONNECT\n", ^(NSString *response) {
        if (generation != _connectionActionGeneration) return;
        _connectionActionInProgress = NO;
        NSString *text = [self sanitizeDaemonText:response];
        if ([text hasPrefix:@"OK"]) {
            _connected = NO;
            _connectedWithProtectedLogs = NO;
            [self stopUptimeTimer];
            [self showStatus:reason ok:NO];
        } else {
            [self showStatus:[NSString stringWithFormat:@"%@ (disconnect failed: %@)", reason, text] ok:NO];
        }
        [self updateConnectButton];
    });
}

- (void)scheduleXHTTPConnectHealthCheckForURI:(NSString *)uri {
    if (![self isXHTTPTransportURI:uri]) return;
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             (uri ? uri : @""), @"uri",
                             @(_connectionActionGeneration), @"generation", @(_connectedSince), @"since",
                             nil];
    [NSThread detachNewThreadSelector:@selector(xhttpConnectHealthCheckWorker:) toTarget:self withObject:payload];
}

- (void)setSubscriptionRefreshInProgress:(BOOL)inProgress {
    if (_subscriptionRefreshInProgress == inProgress) return;
    _subscriptionRefreshInProgress = inProgress;
    [self updateConnectButton];
}

- (BOOL)isConnectionActionInProgress {
    if ([self configurationMutationBlocked]) return YES;
    return VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0);
}

- (NSString *)uriForCurrentSelection {
    if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        NSDictionary *cfg = [_configs objectAtIndex:_selectedConfigIndex];
        NSString *uri = [cfg objectForKey:@"uri"];
        if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
            return uri;
        }
    }

    if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        NSDictionary *sub = [_subscriptions objectAtIndex:_selectedSubIndex];
        NSArray *items = [sub objectForKey:@"items"];
        if (![items isKindOfClass:[NSArray class]] || [items count] == 0) {
            if (![self refreshSubscriptionAtIndex:_selectedSubIndex showStatus:NO]) {
                return nil;
            }
            sub = [_subscriptions objectAtIndex:_selectedSubIndex];
            items = [sub objectForKey:@"items"];
        }

        if ([items isKindOfClass:[NSArray class]] && [items count] > 0) {
            NSInteger idx = _selectedSubItemIndex;
            if (idx < 0 || idx >= (NSInteger)[items count]) idx = 0;
            NSString *uri = [items objectAtIndex:idx];
            if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
                return uri;
            }
        }
    }

    return nil;
}

- (BOOL)selectedSubscriptionIsHappEncrypted {
    if (_selectedSubIndex < 0 || _selectedSubIndex >= (NSInteger)[_subscriptions count]) {
        return NO;
    }
    return SubscriptionDictionaryIsHappEncrypted([_subscriptions objectAtIndex:_selectedSubIndex]);
}

- (void)reconnectToURIIfNeededFrom:(NSString *)oldURI to:(NSString *)newURI {
    if (!_connected) return;
    if (![oldURI isKindOfClass:[NSString class]] || ![newURI isKindOfClass:[NSString class]]) return;
    if ([oldURI length] == 0 || [newURI length] == 0) return;
    BOOL protectLogs = [self selectedSubscriptionIsHappEncrypted];
    if (!VCConfigSwitchNeeded(_connected, oldURI, newURI, _connectedWithProtectedLogs, protectLogs)) return;
    if (![self isSupportedConfigTupleForURI:newURI]) {
        [self showStatus:[self unsupportedConfigStatusTextForURI:newURI] ok:NO];
        return;
    }

    NSString *preparationError = nil;
    NSString *runtimeURI = [VCProfiles() runtimeURI:newURI useXmux:VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults]) error:&preparationError];
    if (!runtimeURI) {
        [self showStatus:preparationError ok:NO];
        return;
    }

    [self stopAllPings];
    [_pendingReconnectURI release];
    _pendingReconnectURI = [newURI copy];
    [_pendingReconnectRuntimeURI release];
    _pendingReconnectRuntimeURI = [runtimeURI copy];
    _pendingReconnectProtectLogs = protectLogs;
    VCRecordAppEvent(@"connection", @"Configuration switch queued", protectLogs ? @"protected_logs=1" : @"protected_logs=0");
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(beginPendingReconnect)
                                               object:nil];
    if (!_reconnectInProgress) {
        [self performSelector:@selector(beginPendingReconnect) withObject:nil afterDelay:0.2];
    }
    [self showStatus:@"Switching to selected config..." ok:YES];
    [self updateConnectButton];
}

- (void)beginPendingReconnect {
    if (_reconnectInProgress || ![_pendingReconnectURI length]) return;
    VCRecordAppEvent(@"connection", @"Configuration switch started", nil);

    NSString *uri = [_pendingReconnectURI copy];
    NSString *runtimeURI = [_pendingReconnectRuntimeURI copy];
    BOOL protectLogs = _pendingReconnectProtectLogs;
    [_pendingReconnectURI release];
    _pendingReconnectURI = nil;
    [_pendingReconnectRuntimeURI release];
    _pendingReconnectRuntimeURI = nil;
    _pendingReconnectProtectLogs = NO;
    _reconnectInProgress = YES;
    ++_connectionActionGeneration;

    NSString *routingCommand = [[NSString stringWithFormat:@"ROUTING\t%@\n", RoutingPolicyText()] copy];
    NSString *connectCommand = [ConnectCommandForURI(runtimeURI, protectLogs) copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        VCWaitForDaemonUICommands();
        NSString *disconnectResponse = [SendCommand(@"DISCONNECT\n") copy];
        NSString *routingResponse = nil;
        NSString *connectResponse = nil;
        if ([disconnectResponse hasPrefix:@"OK"]) {
            routingResponse = [SendCommand(routingCommand) copy];
            if ([routingResponse hasPrefix:@"OK"]) {
                connectResponse = [SendCommand(connectCommand) copy];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *disconnectText = [self sanitizeDaemonText:disconnectResponse];
            NSString *routingText = [self sanitizeDaemonText:routingResponse];
            NSString *connectText = [self sanitizeDaemonText:connectResponse];
            BOOL disconnected = [disconnectText hasPrefix:@"OK"];
            BOOL routingSaved = disconnected && [routingText hasPrefix:@"OK"];
            BOOL connected = routingSaved && [connectText hasPrefix:@"OK"];

            if (connected) {
                VCRecordAppEvent(@"connection", @"Configuration switch completed", nil);
                _connected = YES;
                _connectedWithProtectedLogs = protectLogs;
                [self startUptimeTimerWithDaemonResponse:connectText];
                [self showStatus:@"Connected (switched config)" ok:YES];
            } else if (!disconnected) {
                VCRecordAppEvent(@"connection", @"Configuration switch failed", @"stage=disconnect");
                [self showStatus:[NSString stringWithFormat:@"Reconnect failed (disconnect): %@", disconnectText] ok:NO];
            } else {
                _connected = NO;
                _connectedWithProtectedLogs = NO;
                [self stopUptimeTimer];
                NSString *stage = routingSaved ? @"connect" : @"routing";
                VCRecordAppEvent(@"connection", @"Configuration switch failed",
                                 [NSString stringWithFormat:@"stage=%@", stage]);
                NSString *detail = routingSaved ? connectText : routingText;
                [self showStatus:[NSString stringWithFormat:@"Reconnect failed (%@): %@", stage, detail] ok:NO];
            }

            _reconnectInProgress = NO;
            if ([_pendingReconnectURI isEqualToString:uri] &&
                [_pendingReconnectRuntimeURI isEqualToString:runtimeURI] &&
                _pendingReconnectProtectLogs == protectLogs) {
                [_pendingReconnectURI release];
                _pendingReconnectURI = nil;
                [_pendingReconnectRuntimeURI release];
                _pendingReconnectRuntimeURI = nil;
                _pendingReconnectProtectLogs = NO;
            }
            if ([_pendingReconnectURI length]) {
                [self performSelector:@selector(beginPendingReconnect) withObject:nil afterDelay:0.05];
            } else if (connected) {
                [self scheduleXHTTPConnectHealthCheckForURI:uri];
            }
            [self updateConnectButton];

            [disconnectResponse release];
            [routingResponse release];
            [connectResponse release];
            [routingCommand release];
            [connectCommand release];
            [runtimeURI release];
            [uri release];
        });
        [pool drain];
    });
}

- (void)togglePressed {
    VCRecordAppEvent(@"ui", _connected ? @"Disconnect button pressed" : @"Connect button pressed", nil);
    if (VCConnectionToggleGate(_subscriptionRefreshInProgress, _connectionActionInProgress, _reconnectInProgress) == VCConnectionGateBusy) {
        VCRecordAppEvent(@"connection", @"Connection action blocked",
                         _subscriptionRefreshInProgress ? @"subscription update in progress" : @"connection action in progress");
        [self showStatus:@"Busy" ok:NO];
        return;
    }
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    if (_reconnectInProgress) {
        VCRecordAppEvent(@"connection", @"Connection action blocked", @"config switch in progress");
        [self showStatus:@"Config switch is still in progress" ok:YES];
        return;
    }
    if (_pendingReconnectURI) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(beginPendingReconnect)
                                                   object:nil];
        [_pendingReconnectURI release];
        _pendingReconnectURI = nil;
        [_pendingReconnectRuntimeURI release];
        _pendingReconnectRuntimeURI = nil;
        _pendingReconnectProtectLogs = NO;
    }
    BOOL disconnecting = _connected;
    NSString *uri = nil;
    NSString *runtimeURI = nil;
    BOOL protectLogs = NO;
    if (!disconnecting) {
        uri = [self uriForCurrentSelection];
        if (!uri) {
            if (_subscriptionTask && _selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
                _connectAfterSubscriptionTask=_subscriptionTask;
                [_connectAfterSubscriptionURL release]; _connectAfterSubscriptionURL=[[[_subscriptions objectAtIndex:_selectedSubIndex] objectForKey:@"url"] copy];
                return;
            }
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=selection reason=none_selected");
            [self showStatus:@"Select/import a configuration first" ok:NO];
            return;
        }
        if (![self isSupportedConfigTupleForURI:uri]) {
            VCRecordAppEvent(@"connection", @"Connection failed", @"stage=validation reason=unsupported_config");
            [self showStatus:[self unsupportedConfigStatusTextForURI:uri] ok:NO];
            return;
        }

        protectLogs = [self selectedSubscriptionIsHappEncrypted];
        NSString *preparationError = nil;
        runtimeURI = [VCProfiles() runtimeURI:uri useXmux:VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults]) error:&preparationError];
        if (!runtimeURI) {
            [self showStatus:preparationError ok:NO];
            return;
        }
    }

    NSString *routingCommand = disconnecting ? nil : [NSString stringWithFormat:@"ROUTING\t%@\n", RoutingPolicyText()];
    NSString *command = disconnecting ? @"DISCONNECT\n" : ConnectCommandForURI(runtimeURI, protectLogs);
    _connectionActionInProgress = YES;
    ++_connectionActionGeneration;
    [self updateConnectButton];
    [self showStatus:disconnecting ? @"Disconnecting..." : @"Connecting..." ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        VCWaitForDaemonUICommands();
        NSString *routingResponse = disconnecting ? nil : [SendCommand(routingCommand) copy];
        NSString *response = (disconnecting || [routingResponse hasPrefix:@"OK"])
            ? [SendCommand(command) copy] : nil;

        dispatch_async(dispatch_get_main_queue(), ^{
            _connectionActionInProgress = NO;
            NSString *routingText = [self sanitizeDaemonText:routingResponse];
            NSString *text = [self sanitizeDaemonText:response];
            if (!disconnecting && ![routingText hasPrefix:@"OK"]) {
                VCRecordAppEvent(@"connection", @"Connection failed", @"stage=routing_sync");
                [self showStatus:[NSString stringWithFormat:@"Routing sync failed: %@", routingText] ok:NO];
            } else if ([text hasPrefix:@"OK"]) {
                _connected = !disconnecting;
                _connectedWithProtectedLogs = !disconnecting && protectLogs;
                if (disconnecting) {
                    VCRecordAppEvent(@"connection", @"VPN disconnected", nil);
                    [self stopUptimeTimer];
                    [self showStatus:@"Ready" ok:YES];
                } else {
                    VCRecordAppEvent(@"connection", @"VPN connected", protectLogs ? @"protected_logs=1" : @"protected_logs=0");
                    [self startUptimeTimerWithDaemonResponse:text];
                    [self showStatus:@"Connected" ok:YES];
                    [self scheduleXHTTPConnectHealthCheckForURI:uri];
                }
            } else {
                VCRecordAppEvent(@"connection", disconnecting ? @"Disconnect failed" : @"Connection failed",
                                 disconnecting ? nil : @"stage=daemon_connect");
                [self showStatus:text ok:NO];
            }
            [self updateConnectButton];
            [routingResponse release];
            [response release];
        });
        [pool drain];
    });
}

- (void)queryInitialStatus {
    if (_daemonStatusCheckInFlight) return;
    _daemonStatusCheckInFlight = YES;
    BOOL initial = !_didQueryInitialDaemonStatus;
    if (initial) {
        [self showStatus:@"Checking daemon..." ok:YES];
    }
    NSUInteger generation = _connectionActionGeneration;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *resp = [self sanitizeDaemonText:VCReadDaemonStatus()];
        BOOL connectedNow = [resp hasPrefix:@"OK connected"];
        BOOL disconnectedNow = [resp hasPrefix:@"OK disconnected"];
        BOOL protectedLogsNow = connectedNow &&
            [resp rangeOfString:@"protected=1"].location != NSNotFound;

        dispatch_async(dispatch_get_main_queue(), ^{
            _daemonStatusCheckInFlight = NO;
            if (![self isMainUIActive]) return;
            if (generation != _connectionActionGeneration || VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0)) return;
            if (!connectedNow && !disconnectedNow) {
                if (initial) [self showStatus:[resp length] ? resp : @"Daemon unavailable" ok:NO];
                return;
            }
            BOOL wasConnected = _connected;
            BOOL changed = connectedNow != _connected || protectedLogsNow != _connectedWithProtectedLogs ||
                (connectedNow && _connectedSince != VCConnectedSince(resp, [[NSDate date] timeIntervalSince1970]));
            _didQueryInitialDaemonStatus = YES;
            if (!initial && !changed) return;
            if (connectedNow) {
                VCRecordAppEvent(@"connection", @"Existing VPN session detected", protectedLogsNow ? @"protected_logs=1" : @"protected_logs=0");
                _connected = YES;
                _connectedWithProtectedLogs = protectedLogsNow;
                [self startUptimeTimerWithDaemonResponse:resp];
                [self showStatus:@"Connected" ok:YES];
            } else {
                VCRecordAppEvent(@"connection", !initial && wasConnected ? @"Daemon reported connection lost" : @"No existing VPN session", nil);
                _connected = NO;
                _connectedWithProtectedLogs = NO;
                [self stopUptimeTimer];
                [self showStatus:!initial && wasConnected ? @"Connection lost" : @"Ready" ok:initial || !wasConnected];
            }
            [self updateConnectButton];
        });
        [pool drain];
    });
}

@end
