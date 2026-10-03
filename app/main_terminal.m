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
    _activeLogIndex = newIndex;
    [self updateLogSelectorAnimated:YES];

    CGPoint savedOffset = _logContentOffsetsValid[newIndex]
        ? _logContentOffsets[newIndex]
        : CGPointZero;
    BOOL followTail = _logContentOffsetsValid[newIndex]
        ? _logFollowsTail[newIndex]
        : YES;
    NSString *text = [self isConnectionActionInProgress]
        ? (_logTexts[newIndex] ? _logTexts[newIndex] : @"(waiting for connection action...)\n")
        : ReadLogAtIndex(newIndex);
    [self displayLogText:text
                 atIndex:newIndex
                  offset:savedOffset
              followTail:followTail];
}

- (void)refreshLogs {
    if ([self isConnectionActionInProgress] || !_showingTerminal || _activeLogIndex < 0 || _activeLogIndex > 1) {
        return;
    }
    if (_logView.tracking || _logView.dragging || _logView.decelerating ||
        _logView.selectedRange.length > 0) {
        return;
    }

    NSString *newText = ReadLogAtIndex(_activeLogIndex);
    NSString *oldText = _logTexts[_activeLogIndex] ? _logTexts[_activeLogIndex] : @"";
    if ([newText isEqualToString:oldText]) {
        return;
    }

    CGPoint savedOffset = _logView.contentOffset;
    CGFloat maxOffsetY = [self maximumLogOffsetY];
    BOOL wasNearBottom = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
    [self displayLogText:newText
                 atIndex:_activeLogIndex
                  offset:savedOffset
              followTail:wasNearBottom];
}

- (void)forceRefreshLogs {
    for (NSInteger i = 0; i < 2; i++) {
        [_logTexts[i] release];
        _logTexts[i] = nil;
        _logContentOffsets[i] = CGPointZero;
        _logContentOffsetsValid[i] = NO;
        _logFollowsTail[i] = YES;
    }
    [self displayLogText:ReadLogAtIndex(_activeLogIndex)
                 atIndex:_activeLogIndex
                  offset:CGPointZero
              followTail:NO];
}

- (void)clearLogsPressed {
    VCRecordAppEvent(@"ui", @"Clear logs button pressed", nil);
    if ([self isConnectionActionInProgress]) {
        [self showStatus:@"Busy" ok:NO];
        return;
    }
    NSString *resp = [self sanitizeDaemonText:ClearLogsViaDaemon()];
    [self forceRefreshLogs];

    if ([resp hasPrefix:@"OK"]) {
        [self showStatus:@"Logs cleared" ok:YES];
    } else {
        NSString *msg = ([resp length] > 0) ? resp : @"Failed to clear logs";
        [self showStatus:msg ok:NO];
    }
}

- (void)refreshLogsTick:(NSTimer *)timer {
    (void)timer;
    [self refreshLogs];
}

@end
