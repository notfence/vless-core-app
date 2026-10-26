#import "main_screen.h"

@implementation MainVC (VCMainTerminal)

- (void)terminalPressed {
    VCRecordAppEvent(@"ui", _showingTerminal ? @"Log viewer closed" : @"Log viewer opened", nil);
    if (_reorderingSection >= 0) {
        [self setMainReorderingSection:-1 showStatus:NO];
    }
    if (_connectedWithProtectedLogs || [self selectedSubscriptionIsHappEncrypted]) {
        [self showStatus:@"Logs are unavailable for encrypted HAPP subscriptions" ok:NO];
        return;
    }
    _showingTerminal = !_showingTerminal;

    _tableView.hidden = _showingTerminal;
    _mainSwitchView.hidden = _showingTerminal || ([_configs count] == 0 && [_subscriptions count] == 0);
    _logSelector.hidden = !_showingTerminal;
    _logView.hidden = !_showingTerminal;
    [UIView animateWithDuration:0.18
                     animations:^{
                         [self updatePhoneConnectionLayout];
                     }];

    if (_showingTerminal) {
        [self refreshLogs];
        if (!_logTimer) {
            _logTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(refreshLogsTick:)
                                                        userInfo:nil
                                                         repeats:YES] retain];
        }
    } else {
        _logReadGeneration++;
        _logReadPending = NO;
        [self rememberActiveLogPosition];
        [_logTimer invalidate];
        [_logTimer release];
        _logTimer = nil;
    }

    [self updateTopButtonsIcons];
}

- (CGFloat)maximumLogOffsetY {
    CGFloat maxOffsetY = _logView.contentSize.height - _logView.bounds.size.height;
    return (maxOffsetY > 0.0f) ? maxOffsetY : 0.0f;
}

- (void)rememberActiveLogPosition {
    if (_activeLogIndex < 0 || _activeLogIndex > 1 || !_logView) return;

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    _logContentOffsets[_activeLogIndex] = _logView.contentOffset;
    _logContentOffsetsValid[_activeLogIndex] = YES;
    _logFollowsTail[_activeLogIndex] = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
}

- (void)displayLogText:(NSString *)text
               atIndex:(NSInteger)index
                offset:(CGPoint)savedOffset
            followTail:(BOOL)followTail {
    if (index < 0 || index > 1) return;

    NSString *copiedText = [(text ? text : @"") copy];
    [_logTexts[index] release];
    _logTexts[index] = copiedText;
    if ([_logView respondsToSelector:@selector(setAttributedText:)]) {
        _logView.attributedText = VCFormattedLogText(_logTexts[index]);
    } else {
        _logView.text = _logTexts[index];
    }
    [_logView setNeedsLayout];
    [_logView layoutIfNeeded];

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    CGPoint targetOffset = savedOffset;
    targetOffset.x = 0.0f;
    if (followTail) {
        targetOffset.y = maxOffsetY;
    } else {
        if (targetOffset.y < 0.0f) targetOffset.y = 0.0f;
        if (targetOffset.y > maxOffsetY) targetOffset.y = maxOffsetY;
    }
    [_logView setContentOffset:targetOffset animated:NO];

    _logContentOffsets[index] = _logView.contentOffset;
    _logContentOffsetsValid[index] = YES;
    _logFollowsTail[index] = followTail || maxOffsetY <= 0.0f;
}

- (void)updateLogSelectorAnimated:(BOOL)animated {
    if (!_logSelector || !_logSelectionIndicator) return;

    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = _logSelectorButtons[i];
        [button setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
        [button setTitleColor:VCAccentColor() forState:UIControlStateSelected];
        [button setTitleColor:VCPrimaryTextColor() forState:UIControlStateHighlighted];
        button.selected = (i == _activeLogIndex);
    }

    _logSelectionIndicator.backgroundColor = VCAccentColor();
    CGFloat segmentWidth = _logSelector.bounds.size.width * 0.5f;
    CGRect indicatorFrame = _logSelectionIndicator.frame;
    indicatorFrame.origin.x = segmentWidth * _activeLogIndex + (segmentWidth - indicatorFrame.size.width) * 0.5f;
    void (^updates)(void) = ^{
        _logSelectionIndicator.frame = indicatorFrame;
    };
    if (animated) {
        [UIView animateWithDuration:0.16 animations:updates];
    } else {
        updates();
    }
}

- (void)logSourceChanged:(UIButton *)sender {
    NSInteger newIndex = sender.tag;
    if (newIndex < 0 || newIndex > 1 || newIndex == _activeLogIndex) return;

    [self rememberActiveLogPosition];
    _logReadGeneration++;
    _activeLogIndex = newIndex;
    [self updateLogSelectorAnimated:YES];

    CGPoint savedOffset = _logContentOffsetsValid[newIndex]
        ? _logContentOffsets[newIndex]
        : CGPointZero;
    BOOL followTail = _logContentOffsetsValid[newIndex]
        ? _logFollowsTail[newIndex]
        : YES;
    NSString *text = _logTexts[newIndex] ? _logTexts[newIndex] : @"";
    [self displayLogText:text
                 atIndex:newIndex
                  offset:savedOffset
              followTail:followTail];
    [self refreshLogs];
}

- (void)refreshLogs {
    if ([self isConnectionActionInProgress] || !_showingTerminal || _activeLogIndex < 0 || _activeLogIndex > 1) {
        return;
    }
    if (_logView.tracking || _logView.dragging || _logView.decelerating ||
        _logView.selectedRange.length > 0) {
        return;
    }

    [self requestLogRefresh];
}

- (void)requestLogRefresh {
    if (!_showingTerminal || _logClearInFlight || [self isConnectionActionInProgress] ||
        _connectedWithProtectedLogs || [self selectedSubscriptionIsHappEncrypted] ||
        [[UIApplication sharedApplication] applicationState] != UIApplicationStateActive ||
        _activeLogIndex < 0 || _activeLogIndex > 1) return;
    if (_logReadInFlight) { _logReadPending = YES; return; }
    _logReadInFlight = YES;
    _logReadPending = NO;
    NSUInteger generation = _logReadGeneration;
    NSUInteger connectionGeneration = _connectionActionGeneration;
    NSInteger index = _activeLogIndex;
    ReadLogAtIndexAsync(index, ^(NSString *text) {
        _logReadInFlight = NO;
        if (generation == _logReadGeneration && connectionGeneration == _connectionActionGeneration &&
            _showingTerminal && index == _activeLogIndex && !_logClearInFlight &&
            !_connectedWithProtectedLogs && ![self selectedSubscriptionIsHappEncrypted] &&
            ![self isConnectionActionInProgress] &&
            [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive &&
            !_logView.tracking && !_logView.dragging && !_logView.decelerating && _logView.selectedRange.length == 0) {
            if (![text isEqualToString:_logTexts[index] ? _logTexts[index] : @""]) {
                CGPoint offset = _logView.contentOffset;
                BOOL tail = offset.y >= [self maximumLogOffsetY] - 20.0f;
                [self displayLogText:text atIndex:index offset:offset followTail:tail];
            }
        }
        BOOL pending = _logReadPending;
        _logReadPending = NO;
        if (pending) [self refreshLogs];
    });
}

- (void)forceRefreshLogs {
    _logReadGeneration++;
    for (NSInteger i = 0; i < 2; i++) {
        [_logTexts[i] release];
        _logTexts[i] = nil;
        _logContentOffsets[i] = CGPointZero;
        _logContentOffsetsValid[i] = NO;
        _logFollowsTail[i] = YES;
    }
    [self displayLogText:@""
                 atIndex:_activeLogIndex
                  offset:CGPointZero
              followTail:NO];
    [self refreshLogs];
}

- (void)clearLogsPressed {
    VCRecordAppEvent(@"ui", @"Clear logs button pressed", nil);
    if (_logClearInFlight || [self isConnectionActionInProgress]) {
        [self showStatus:@"Busy" ok:NO];
        return;
    }
    _logClearInFlight = YES;
    _logReadGeneration++;
    _logReadPending = NO;
    NSUInteger connectionGeneration = _connectionActionGeneration;
    VCSendCommandAsync(@"CLEAR_LOGS\n", ^(NSString *response) {
        _logClearInFlight = NO;
        if (connectionGeneration != _connectionActionGeneration || _connectedWithProtectedLogs ||
            [self selectedSubscriptionIsHappEncrypted]) return;
        [self forceRefreshLogs];
        NSString *text = [self sanitizeDaemonText:response];
        [self showStatus:[text hasPrefix:@"OK"] ? @"Logs cleared" : ([text length] ? text : @"Failed to clear logs")
                     ok:[text hasPrefix:@"OK"]];
    });
}

- (void)refreshLogsTick:(NSTimer *)timer {
    (void)timer;
    [self refreshLogs];
}

@end
