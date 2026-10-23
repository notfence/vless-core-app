#import "main_screen.h"
#import "main_cells.h"

@implementation MainVC (VCMainLayout)

- (void)recordMainLayoutEvent:(NSString *)action {
    if (!_tableView) return;
    NSInteger section = _subscriptionsSectionExpanded ? 1 : 0;
    NSString *detail = [NSString stringWithFormat:
                        @"tab=%@ compact=%d offset=%.1f content=%.1f viewport=%.1f rows=%ld switch_y=%.1f button=%.1fx%.1f font=%.1f",
                        section == 0 ? @"configurations" : @"subscriptions",
                        _phoneConnectionCompact ? 1 : 0,
                        _tableView.contentOffset.y,
                        _tableView.contentSize.height,
                        _tableView.bounds.size.height,
                        (long)[_tableView numberOfRowsInSection:section],
                        _mainSwitchView.frame.origin.y,
                        _connectBtn.bounds.size.width,
                        _connectBtn.bounds.size.height,
                        [_connectButtonTitle.font pointSize]];
    VCRecordAppEvent(@"layout", action, detail);
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return VCAppearancePreferredStatusBarStyle();
}

- (UIView *)mainDetailContainerForCell:(UITableViewCell *)cell createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    UIView *container = [cell.contentView viewWithTag:kVCMainDetailContainerTag];
    if (!container && createIfNeeded) {
        container = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        container.tag = kVCMainDetailContainerTag;
        container.backgroundColor = [UIColor clearColor];
        container.userInteractionEnabled = NO;
        container.clipsToBounds = YES;
        [cell.contentView addSubview:container];
    }
    return container;
}

- (UILabel *)mainDetailPrefixLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    UILabel *label = (UILabel *)[container viewWithTag:kVCMainDetailPrefixTag];
    if (!label && createIfNeeded) {
        label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
        label.tag = kVCMainDetailPrefixTag;
        label.backgroundColor = [UIColor clearColor];
        label.numberOfLines = 1;
        label.lineBreakMode = NSLineBreakByClipping;
        [container addSubview:label];
    }
    return label;
}

- (UILabel *)mainDetailTailLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    UILabel *label = (UILabel *)[container viewWithTag:kVCMainDetailTailTag];
    if (!label && createIfNeeded) {
        label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
        label.tag = kVCMainDetailTailTag;
        label.backgroundColor = [UIColor clearColor];
        label.userInteractionEnabled = NO;
        label.numberOfLines = 1;
        label.lineBreakMode = NSLineBreakByClipping;
        [container addSubview:label];
    }
    return label;
}

- (CGRect)mainDetailContentFrameForCell:(UITableViewCell *)cell {
    if (!cell) return CGRectZero;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    CGRect contentBounds = cell.contentView.bounds;
    CGFloat contentW = CGRectGetWidth(contentBounds);
    CGFloat contentH = CGRectGetHeight(contentBounds);
    if (contentW < 1.0f || contentH < 1.0f) return CGRectZero;

    CGRect titleFrame = cell.textLabel.frame;
    CGRect legacyDetailFrame = cell.detailTextLabel.frame;

    CGFloat left = titleFrame.origin.x;
    if (left < 6.0f) {
        left = legacyDetailFrame.origin.x;
    }
    if (left < 6.0f) {
        left = 10.0f;
    }

    CGFloat top = CGRectGetMaxY(titleFrame) + 1.0f;
    if (top < 1.0f || top > contentH - 6.0f) {
        top = legacyDetailFrame.origin.y;
    }
    if (top < 1.0f) {
        top = 24.0f;
    }

    CGFloat right = contentW - 10.0f;
    if (cell.accessoryView && !cell.accessoryView.hidden) {
        CGRect accessoryFrame = cell.accessoryView.frame;
        if (CGRectGetWidth(accessoryFrame) > 1.0f && CGRectGetMinX(accessoryFrame) > 1.0f) {
            right = MIN(right, CGRectGetMinX(accessoryFrame) - 8.0f);
        }
    }
    if (right < left + 12.0f) {
        right = left + 12.0f;
    }

    CGFloat height = contentH - top - 2.0f;
    if (legacyDetailFrame.size.height > 0.0f) {
        height = MAX(height, legacyDetailFrame.size.height);
    }
    if ([cell isKindOfClass:[VCMainListCell class]] &&
        [(VCMainListCell *)cell usesConfigurationItemLayout]) {
        top += 2.0f;
        height = 14.0f;
    }
    if (top + height > contentH) {
        height = contentH - top;
    }
    if (height < 10.0f) {
        height = 14.0f;
        if (top + height > contentH) {
            top = MAX(0.0f, contentH - height);
        }
    }

    return CGRectMake(left, top, right - left, height);
}

- (void)clearDetailTextForCell:(UITableViewCell *)cell {
    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:NO];
    if (!container) return;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:NO];
    UILabel *tailLabel = [self mainDetailTailLabelForContainer:container createIfNeeded:NO];
    if (tailLabel) {
        tailLabel.text = @"";
        tailLabel.hidden = YES;
    }
    if (prefixLabel) {
        prefixLabel.text = @"";
        prefixLabel.hidden = YES;
    }
    container.hidden = YES;
}

- (UIFont *)mainDetailFont:(UIFont *)font
             fittingPrefix:(NSString *)prefix
                      tail:(NSString *)tail
                     width:(CGFloat)width {
    if (!font || width <= 0.0f) return font;

    CGFloat gap = ([prefix length] > 0 && [tail length] > 0) ? kVCDetailLabelGap : 0.0f;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGFloat textWidth = [prefix sizeWithFont:font].width + [tail sizeWithFont:font].width;
#pragma clang diagnostic pop
    CGFloat availableWidth = MAX(1.0f, width - gap - 2.0f);
    if (textWidth <= availableWidth) return font;

    CGFloat pointSize = MAX(1.0f, font.pointSize * availableWidth / textWidth * 0.98f);
    UIFont *fitted = [UIFont fontWithName:font.fontName size:pointSize];
    return fitted ? fitted : [UIFont systemFontOfSize:pointSize];
}

- (void)applyDetailPrefix:(NSString *)prefix
              prefixColor:(UIColor *)prefixColor
                     tail:(NSString *)tail
                   toCell:(UITableViewCell *)cell {
    if (!cell) return;

    NSString *prefixText = ([prefix isKindOfClass:[NSString class]] ? prefix : @"");
    NSString *tailText = ([tail isKindOfClass:[NSString class]] ? tail : @"");
    UIColor *effectivePrefixColor = [prefixColor isKindOfClass:[UIColor class]] ? prefixColor : VCSecondaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();
    UIFont *detailFont = cell.detailTextLabel.font;
    if (!detailFont) detailFont = [UIFont systemFontOfSize:11.0f];

    // Keep subtitle geometry stable: non-empty detail preserves UIKit two-line layout metrics.
    BOOL hasDetail = ([prefixText length] > 0 || [tailText length] > 0);
    cell.detailTextLabel.text = hasDetail ? @" " : @"";
    cell.detailTextLabel.textColor = [UIColor clearColor];

    if ([prefixText length] == 0 && [tailText length] == 0) {
        [self clearDetailTextForCell:cell];
        return;
    }

    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:YES];
    CGRect containerFrame = [self mainDetailContentFrameForCell:cell];
    if (CGRectGetWidth(containerFrame) < 8.0f || CGRectGetHeight(containerFrame) < 8.0f) {
        [self clearDetailTextForCell:cell];
        return;
    }

    container.hidden = NO;
    container.frame = containerFrame;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:YES];
    UILabel *tailLabel = [self mainDetailTailLabelForContainer:container createIfNeeded:YES];
    CGFloat lineH = CGRectGetHeight(container.bounds);
    CGFloat lineW = CGRectGetWidth(container.bounds);
    UIFont *fittedFont = [self mainDetailFont:detailFont
                              fittingPrefix:prefixText
                                       tail:tailText
                                      width:lineW];

    prefixLabel.font = fittedFont;
    prefixLabel.textColor = effectivePrefixColor;
    prefixLabel.backgroundColor = [UIColor clearColor];

    tailLabel.font = fittedFont;
    tailLabel.textColor = detailColor;

    if ([tailText length] == 0) {
        tailLabel.text = @"";
        tailLabel.hidden = YES;

        prefixLabel.hidden = NO;
        prefixLabel.text = prefixText;
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        return;
    }

    if ([prefixText length] == 0) {
        prefixLabel.hidden = YES;
        prefixLabel.text = @"";
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, 0.0f, lineH);

        tailLabel.hidden = NO;
        tailLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        tailLabel.text = tailText;
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize prefixSize = [prefixText sizeWithFont:fittedFont];
#pragma clang diagnostic pop

    CGFloat prefixWidth = ceilf(prefixSize.width);
    CGFloat maxPrefixWidth = lineW - 16.0f;
    if (maxPrefixWidth < 8.0f) maxPrefixWidth = lineW;
    if (prefixWidth > maxPrefixWidth) prefixWidth = maxPrefixWidth;
    if (prefixWidth < 0.0f) prefixWidth = 0.0f;

    CGFloat tailX = prefixWidth + kVCDetailLabelGap;
    CGFloat tailWidth = lineW - tailX;
    if (tailWidth < 8.0f) {
        NSString *combinedText = [NSString stringWithFormat:@"%@ %@", prefixText, tailText];
        prefixLabel.hidden = YES;
        prefixLabel.text = @"";
        tailLabel.hidden = NO;
        tailLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        tailLabel.font = [self mainDetailFont:detailFont
                              fittingPrefix:@""
                                       tail:combinedText
                                      width:lineW];
        tailLabel.text = combinedText;
        return;
    }

    prefixLabel.hidden = NO;
    prefixLabel.text = prefixText;
    prefixLabel.frame = CGRectMake(0.0f, 0.0f, prefixWidth, lineH);

    tailLabel.hidden = NO;
    tailLabel.frame = CGRectMake(tailX, 0.0f, tailWidth, lineH);
    tailLabel.text = tailText;
}

- (void)applyDetailPrefix:(NSString *)prefix tail:(NSString *)tail toCell:(UITableViewCell *)cell {
    [self applyDetailPrefix:prefix
                prefixColor:VCSecondaryTextColor()
                       tail:tail
                     toCell:cell];
}

- (void)updateConnectionSummary {
    _connectionStateLabel.text = _connected ? @"Connected" : @"Not connected";
    _connectionStateLabel.textColor = _connected ? VCSuccessColor() : VCPrimaryTextColor();

    NSString *name = nil;
    if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        NSDictionary *subscription = [_subscriptions objectAtIndex:_selectedSubIndex];
        name = [subscription objectForKey:@"name"];
        if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
            name = [self subscriptionNameFromURLString:[subscription objectForKey:@"url"]];
        }
    } else if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        name = [[_configs objectAtIndex:_selectedConfigIndex] objectForKey:@"name"];
    }
    _selectionLabel.text = ([name isKindOfClass:[NSString class]] && [name length] > 0)
        ? [self maskedLinkText:name] : @"No configuration selected";
}

- (void)updateConnectButton {
    NSString *title = _subscriptionRefreshInProgress ? @"Updating" : (_connected ? @"Disconnect" : @"Connect");
    _connectButtonTitle.text = title;
    _connectBtn.accessibilityLabel = title;
    [_connectPowerIcon setLoading:_subscriptionRefreshInProgress || VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0)];
    UIColor *fill = _connected
        ? [UIColor colorWithRed:0.12f green:0.58f blue:0.20f alpha:1.0f]
        : VCAccentColor();
    _connectBtn.backgroundColor = fill;
    _connectGlowView.image = VCMakeConnectionGlow(fill);
    _compactConnectGlowView.backgroundColor = [fill colorWithAlphaComponent:0.45f];
    _compactConnectGlowView.layer.shadowColor = fill.CGColor;
    [self updateConnectionSummary];
}

- (void)applyTopButtonFeedbackToButton:(UIButton *)btn {
    if (!btn) return;
    btn.showsTouchWhenHighlighted = NO;
    btn.adjustsImageWhenHighlighted = NO;
    btn.layer.cornerRadius = 6.0f;
    btn.layer.masksToBounds = YES;
    [btn setBackgroundImage:SolidImageWithColor([UIColor colorWithWhite:0.0f alpha:0.0f]) forState:UIControlStateNormal];
    UIColor *highlight = VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                               : [UIColor colorWithWhite:0.72f alpha:1.0f];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateHighlighted];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateSelected];
}

- (void)buttonTouchDown:(UIButton *)sender {
    VCConnectionTouchDown(self, sender == _connectBtn);
    sender.layer.shadowColor = [UIColor blackColor].CGColor;
    sender.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
    sender.layer.shadowRadius = 4.0f;
    sender.layer.shadowOpacity = 0.35f;
}

- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.12
                     animations:^{
                         sender.layer.shadowOpacity = 0.0f;
                     }];
}

- (void)updateTopButtonsIcons {
    [_plusBtn setImage:MakeIconImage(VCIconTypeAdd, 20.0f, NO) forState:UIControlStateNormal];
    UIColor *iconColor = VCPrimaryTextColor();
    UIImage *refresh = LoadBundledIconTinted(@"icon-refresh", 20.0f, iconColor);
    UIImage *terminal = _showingTerminal
        ? LoadBundledIconTinted(@"icon-list", 20.0f, iconColor)
        : LoadBundledIconTinted(@"icon-terminal", 20.0f, iconColor);
    UIImage *settings = LoadBundledIconTinted(@"icon-settings", 20.0f, iconColor);
    UIImage *trash = LoadBundledIconTinted(@"icon-trash", 20.0f, iconColor);
    UIImage *update = LoadBundledIconScaled(VCAppearanceIsDark() ? @"update-dark" : @"update-white", 20.0f);

    [_refreshBtn setImage:(refresh ? refresh : MakeIconImage(VCIconTypeRefresh, 20.0f, NO)) forState:UIControlStateNormal];
    [_terminalBtn setImage:(terminal ? terminal : MakeIconImage(_showingTerminal ? VCIconTypeList : VCIconTypeTerminal, 20.0f, _showingTerminal))
                  forState:UIControlStateNormal];
    [_clearLogsBtn setImage:trash forState:UIControlStateNormal];
    _clearLogsBtn.hidden = !_showingTerminal;
    [_settingsBtn setImage:(settings ? settings : MakeIconImage(VCIconTypeSettings, 20.0f, NO)) forState:UIControlStateNormal];
    [_updateBtn setImage:update forState:UIControlStateNormal];
    _updateBtn.hidden = !([_availableUpdateVersion length] > 0);
}

- (UIView *)accessoryChevronExpanded:(BOOL)expanded {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)] autorelease];
    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(2, 2, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];
    return v;
}

- (UIView *)subscriptionHeaderAccessoryExpanded:(BOOL)expanded loading:(BOOL)loading {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 30.0f, 30.0f)] autorelease];
    v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    if (loading) {
        UIActivityIndicatorView *spinner =
            [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray)] autorelease];
        spinner.frame = CGRectMake(5.0f, 5.0f, 20.0f, 20.0f);
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        [v addSubview:spinner];
    } else {
        UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(7.0f, 7.0f, 16.0f, 16.0f)] autorelease];
        iv.tag = kVCSubscriptionHeaderChevronTag;
        iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
        [v addSubview:iv];
    }
    return v;
}

- (UIView *)accessoryPingWithTag:(NSInteger)tag uri:(NSString *)uri {
    NSString *display = ([uri isKindOfClass:[NSString class]] ? [_pingDisplayByURI objectForKey:uri] : nil);
    BOOL loading = [display isEqualToString:kVCPingLoadingValue];
    BOOL hasResult = ([display length] > 0 && !loading);
    BOOL failed = VCPingDisplayIsFailure(display);
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 24.0f, 24.0f)] autorelease];
    v.clipsToBounds = NO;
    v.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;

    if (hasResult) {
        UIFont *font = [UIFont boldSystemFontOfSize:9.0f];
        CGFloat labelWidth = MAX(34.0f, ceilf([display sizeWithFont:font].width) + 2.0f);
        UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(floorf((24.0f - labelWidth) * 0.5f),
                                                                           21.0f,
                                                                           labelWidth,
                                                                           12.0f)] autorelease];
        label.backgroundColor = [UIColor clearColor];
        label.font = font;
        label.textAlignment = NSTextAlignmentCenter;
        label.adjustsFontSizeToFitWidth = NO;
        label.textColor = failed ? VCErrorColor() : VCSuccessColor();
        label.text = display;
        [v addSubview:label];
    }

    if (loading) {
        UIActivityIndicatorView *spinner =
            [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(VCAppearanceIsDark()
                ? UIActivityIndicatorViewStyleWhite
                : UIActivityIndicatorViewStyleGray)] autorelease];
        spinner.frame = CGRectMake(2.0f, 2.0f, 20.0f, 20.0f);
        spinner.hidesWhenStopped = YES;
        [spinner startAnimating];
        [v addSubview:spinner];
        return v;
    }

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0.0f, 0.0f, 24.0f, 24.0f);
    UIImage *pingIcon = LoadBundledIconTinted(@"icon-ping", 20.0f, VCPrimaryTextColor());
    [btn setImage:(pingIcon ? pingIcon : MakeIconImage(VCIconTypeWifi, 18.0f, NO)) forState:UIControlStateNormal];
    btn.tag = tag;
    btn.accessibilityLabel = hasResult ? [NSString stringWithFormat:@"Ping result %@", display]
                                       : @"Check ping";
    NSString *pingTypeName = VCPingTypeName(VCSelectedPingType());
    BOOL subscriptionPingRunning = NO;
    if (tag >= 20000) {
        NSInteger subIdx = (tag - 20000) / 1000;
        subscriptionPingRunning = [self isSubscriptionPingInProgressAtIndex:subIdx];
    }
    btn.enabled = !subscriptionPingRunning;
    btn.adjustsImageWhenDisabled = YES;
    btn.accessibilityHint = subscriptionPingRunning
        ? @"All configurations in this subscription are being pinged"
        : (hasResult
            ? [NSString stringWithFormat:@"Double tap to run %@ again", pingTypeName]
            : [NSString stringWithFormat:@"Runs %@ latency test", pingTypeName]);
    [btn addTarget:self action:@selector(pingButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    btn.showsTouchWhenHighlighted = NO;
    btn.adjustsImageWhenHighlighted = NO;
    [v addSubview:btn];

    return v;
}

- (void)updatePhoneConnectionScrollInsets {
    if (IsPadDevice() || !_tableView || _mainSectionTransitionInProgress) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat requiredBottomInset = _tableView.bounds.size.height - _tableView.contentSize.height;
    if (requiredBottomInset < 0.0f) requiredBottomInset = 0.0f;

    UIEdgeInsets insets = _tableView.contentInset;
    if (fabs(insets.top - collapseDistance) <= 0.5f &&
        fabs(insets.bottom - requiredBottomInset) <= 0.5f) {
        return;
    }
    insets.top = collapseDistance;
    insets.bottom = requiredBottomInset;
    _tableView.contentInset = insets;
}

- (void)updatePhoneConnectionLayout {
    if (IsPadDevice() || !_tableView || !_connectBtn || !_uptimeLabel || !_statusLabel) return;
    if (_mainSectionTransitionInProgress) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat progress = 0.0f;
    if (collapseDistance > 0.0f) {
        progress = _showingTerminal
            ? (_phoneConnectionCompact ? 1.0f : 0.0f)
            : VCClampUnit((_tableView.contentOffset.y + collapseDistance) / collapseDistance);
    }

    CGFloat width = self.view.bounds.size.width;
    CGFloat topInset = VCMainStatusBarInset();
    VCMainGeometry geometry = VCPhoneGeometry(width, topInset, progress);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _mainSwitchView.frame = geometry.switcher;
    _connectBtn.frame = geometry.button;
    _connectBtn.layer.cornerRadius = _connectBtn.bounds.size.height * 0.5f;
    _connectGlowView.frame = CGRectInset(_connectBtn.frame, -18.0f, -18.0f);
    _connectGlowView.alpha = 1.0f - progress;
    _compactConnectGlowView.frame = _connectBtn.frame;
    _compactConnectGlowView.layer.cornerRadius = _connectBtn.layer.cornerRadius;
    _compactConnectGlowView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_compactConnectGlowView.bounds
                                                                          cornerRadius:_compactConnectGlowView.layer.cornerRadius].CGPath;
    _compactConnectGlowView.alpha = progress;
    _connectPowerIcon.frame = geometry.power;
    _connectButtonTitle.frame = geometry.title;
    CGFloat buttonFontSize = 16.0f - 3.5f * progress;
    if (fabs([_connectButtonTitle.font pointSize] - buttonFontSize) > 0.35f) {
        _connectButtonTitle.font = [UIFont boldSystemFontOfSize:buttonFontSize];
        VCSetLabelMinimumScaleFactor(_connectButtonTitle, 0.75f);
    }

    _connectionStateLabel.frame = geometry.state;
    _connectionStateLabel.textAlignment = progress < 0.5f ? NSTextAlignmentCenter : NSTextAlignmentLeft;
    _selectionLabel.frame = geometry.selection;
    _selectionLabel.textAlignment = _connectionStateLabel.textAlignment;
    _uptimeLabel.frame = geometry.uptime;
    CGFloat uptimeFontSize = 13.0f - progress;
    if (fabs([_uptimeLabel.font pointSize] - uptimeFontSize) > 0.35f) {
        _uptimeLabel.font = [UIFont boldSystemFontOfSize:uptimeFontSize];
    }
    _uptimeLabel.textAlignment = _connectionStateLabel.textAlignment;

    _statusLabel.frame = geometry.status;
    CGFloat statusFontSize = 12.5f - progress;
    if (fabs([_statusLabel.font pointSize] - statusFontSize) > 0.35f) {
        _statusLabel.font = [UIFont systemFontOfSize:statusFontSize];
    }

    if (_showingTerminal && _logSelector && _logView) {
        CGFloat logY = topInset + kVCMainContentStartY - collapseDistance * progress;
        CGRect selectorFrame = _logSelector.frame;
        selectorFrame.origin.y = logY + 2.0f;
        _logSelector.frame = selectorFrame;

        CGRect logFrame = _logView.frame;
        logFrame.origin.y = logY + 32.0f;
        logFrame.size.height = self.view.bounds.size.height - logFrame.origin.y;
        if (logFrame.size.height < 120.0f) logFrame.size.height = 120.0f;
        _logView.frame = logFrame;
    }

    CGFloat labelAlpha = fabs(progress * 2.0f - 1.0f);
    _connectionStateLabel.alpha = labelAlpha;
    _selectionLabel.alpha = labelAlpha;
    _uptimeLabel.alpha = labelAlpha;
    _statusLabel.alpha = labelAlpha;

    UIEdgeInsets indicators = _tableView.scrollIndicatorInsets;
    indicators.top = collapseDistance * (1.0f - progress);
    _tableView.scrollIndicatorInsets = indicators;
    [CATransaction commit];

    if (progress <= 0.001f) {
        _phoneConnectionCompact = NO;
    } else if (progress >= 0.999f) {
        _phoneConnectionCompact = YES;
    }
}

- (void)updatePadConnectionLayout {
    if (!IsPadDevice() || !_connectBtn || !_tableView) return;

    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat topInset = VCMainStatusBarInset();
    CGFloat buttonSize = 112.0f;
    VCMainGeometry geometry = VCPadGeometry(width, height, topInset);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _connectBtn.frame = geometry.button;
    _connectBtn.layer.cornerRadius = buttonSize * 0.5f;
    _connectGlowView.frame = CGRectInset(geometry.button, -18.0f, -18.0f);
    _connectGlowView.alpha = 1.0f;
    _compactConnectGlowView.frame = geometry.button;
    _compactConnectGlowView.alpha = 0.0f;
    _connectPowerIcon.frame = CGRectMake(40.5f, 26.0f, 31.0f, 31.0f);
    _connectButtonTitle.frame = CGRectMake(10.0f, 61.0f, 92.0f, 24.0f);
    _connectButtonTitle.font = [UIFont boldSystemFontOfSize:16.0f];
    VCSetLabelMinimumScaleFactor(_connectButtonTitle, 0.75f);
    _connectionStateLabel.frame = geometry.state;
    _selectionLabel.frame = geometry.selection;
    _uptimeLabel.frame = geometry.uptime;
    _connectionStateLabel.textAlignment = NSTextAlignmentCenter;
    _selectionLabel.textAlignment = NSTextAlignmentCenter;
    _uptimeLabel.textAlignment = NSTextAlignmentCenter;
    _connectionStateLabel.alpha = 1.0f;
    _selectionLabel.alpha = 1.0f;
    _uptimeLabel.alpha = 1.0f;
    _statusLabel.frame = CGRectMake(16.0f, topInset + 237.0f, width - 32.0f, 30.0f);
    _statusLabel.alpha = 1.0f;
    _mainSwitchView.frame = CGRectMake(10.0f, topInset + kVCMainContentStartY,
                                       width - 20.0f, kVCMainSectionHeaderHeight);
    _tableView.frame = geometry.table;
    [CATransaction commit];
    [self updateMainSwitcherView:_mainSwitchView];
}

- (CGFloat)maximumMainTableContentOffsetY {
    if (!_tableView) return 0.0f;

    CGFloat minimumOffset = -_tableView.contentInset.top;
    CGFloat maximumOffset = _tableView.contentSize.height - _tableView.bounds.size.height +
                            _tableView.contentInset.bottom;
    return (maximumOffset > minimumOffset) ? maximumOffset : minimumOffset;
}

- (CGFloat)phoneConnectionSnapOffsetForProposedOffset:(CGFloat)proposedOffset
                                         currentOffset:(CGFloat)currentOffset
                                              velocity:(CGFloat)velocity {
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    if (collapseDistance <= 0.0f) return proposedOffset;
    if ([self maximumMainTableContentOffsetY] < -0.5f) return expandedOffset;
    if (proposedOffset <= expandedOffset) return expandedOffset;
    if (proposedOffset >= 0.0f) return proposedOffset;

    if (velocity > 0.05f) return 0.0f;
    if (velocity < -0.05f) return expandedOffset;

    CGFloat movement = proposedOffset - currentOffset;
    if (movement > 3.0f) return 0.0f;
    if (movement < -3.0f) return expandedOffset;

    CGFloat compactTrigger = expandedOffset + collapseDistance * 0.28f;
    return (proposedOffset >= compactTrigger) ? 0.0f : expandedOffset;
}

- (void)animatePhoneConnectionToOffset:(CGFloat)targetOffset {
    if (!_tableView) return;

    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    CGFloat maximumOffset = [self maximumMainTableContentOffsetY];
    if (targetOffset < expandedOffset) targetOffset = expandedOffset;
    if (targetOffset > maximumOffset) targetOffset = maximumOffset;

    CGFloat distance = fabs(targetOffset - _tableView.contentOffset.y);
    _phoneConnectionCompact = targetOffset >= -0.5f;
    if (distance <= 0.5f || collapseDistance <= 0.0f) {
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                            animated:NO];
        [self updatePhoneConnectionLayout];
        return;
    }

    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:YES];
}

- (void)snapPhoneConnectionLayoutIfNeededAnimated:(BOOL)animated {
    if (IsPadDevice() || _showingTerminal || !_tableView) return;

    [_tableView layoutIfNeeded];
    [self updatePhoneConnectionScrollInsets];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    CGFloat currentOffset = _tableView.contentOffset.y;
    if ([self maximumMainTableContentOffsetY] < -0.5f) {
        if (fabs(currentOffset - expandedOffset) > 0.5f) {
            if (animated) {
                [self animatePhoneConnectionToOffset:expandedOffset];
            } else {
                [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, expandedOffset)
                                    animated:NO];
            }
        }
        return;
    }
    if (currentOffset <= expandedOffset + 0.5f) {
        _phoneConnectionCompact = NO;
        return;
    }
    if (currentOffset >= -0.5f) {
        _phoneConnectionCompact = YES;
        return;
    }

    if (_tableView.tracking || _tableView.dragging || _tableView.decelerating) return;

    CGFloat targetOffset = _phoneConnectionCompact ? 0.0f : expandedOffset;
    if (animated) {
        [self animatePhoneConnectionToOffset:targetOffset];
    } else {
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                            animated:NO];
        [self updatePhoneConnectionLayout];
    }
}

- (void)prepareMainTableStructuralTransition {
    if (!_mainSectionTransitionInProgress && !IsPadDevice() && _tableView) {
        _mainTableOffsetBeforeTransition = _tableView.contentOffset.y;
        _phoneConnectionCompactBeforeTransition = (_tableView.contentOffset.y >= -0.5f)
            ? YES
            : _phoneConnectionCompact;
        _mainTableTransitionSnapshotValid = YES;
    }
    _mainSectionTransitionInProgress = YES;
    if (IsPadDevice() || !_tableView) return;

    UIEdgeInsets insets = _tableView.contentInset;
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat positiveOffset = _tableView.contentOffset.y;
    if (positiveOffset < 0.0f) positiveOffset = 0.0f;
    CGFloat safeBottomInset = _tableView.bounds.size.height + positiveOffset + collapseDistance;
    if (insets.bottom < safeBottomInset) {
        insets.bottom = safeBottomInset;
        _tableView.contentInset = insets;
    }
}

- (void)stabilizeMainTableOffsetDuringStructuralTransition {
    if (IsPadDevice() || !_tableView || !_mainSectionTransitionInProgress ||
        !_mainTableTransitionSnapshotValid || !_phoneConnectionCompactBeforeTransition ||
        _compactSubscriptionOffsetAnimationInProgress) {
        return;
    }

    CGFloat targetOffset = _mainTableOffsetBeforeTransition;
    if (targetOffset < 0.0f) targetOffset = 0.0f;
    if (fabs(_tableView.contentOffset.y - targetOffset) <= 0.5f) return;

    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:NO];
}

- (void)restoreMainTableAfterStructuralTransitionCompact:(BOOL)compact
                                          preservedOffset:(CGFloat)preservedOffset {
    if (IsPadDevice() || !_tableView) return;

    [self updatePhoneConnectionScrollInsets];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat targetOffset = -collapseDistance;
    if (compact) {
        targetOffset = preservedOffset;
        if (targetOffset < 0.0f) targetOffset = 0.0f;
        CGFloat maximumOffset = [self maximumMainTableContentOffsetY];
        if (maximumOffset < 0.0f) maximumOffset = 0.0f;
        if (targetOffset > maximumOffset) targetOffset = maximumOffset;
    }

    _phoneConnectionCompact = compact;
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:NO];
    [self updatePhoneConnectionLayout];
}

- (void)completeMainTableStructuralTransition {
    if (!_tableView) {
        _mainSectionTransitionInProgress = NO;
        _mainTableTransitionSnapshotValid = NO;
        return;
    }

    [_tableView layoutIfNeeded];
    BOOL restoreSnapshot = _mainTableTransitionSnapshotValid && !IsPadDevice();
    BOOL restoreCompact = _phoneConnectionCompactBeforeTransition;
    CGFloat restoreOffset = _mainTableOffsetBeforeTransition;

    _mainSectionTransitionInProgress = NO;
    [self updatePhoneConnectionScrollInsets];

    if (restoreSnapshot) {
        [self restoreMainTableAfterStructuralTransitionCompact:restoreCompact
                                                preservedOffset:restoreOffset];

        NSUInteger transitionToken = _mainSectionTransitionToken;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (transitionToken != _mainSectionTransitionToken ||
                _mainSectionTransitionInProgress ||
                _tableView.tracking || _tableView.dragging || _tableView.decelerating) {
                return;
            }
            [_tableView layoutIfNeeded];
            [self restoreMainTableAfterStructuralTransitionCompact:restoreCompact
                                                    preservedOffset:restoreOffset];
        });
    } else {
        [self snapPhoneConnectionLayoutIfNeededAnimated:NO];
    }

    _mainTableTransitionSnapshotValid = NO;
}

- (void)retargetCompactSubscriptionTransitionAnchor {
    if (_compactSubscriptionTransitionAnchorIndex < 0 || !_tableView) return;

    NSInteger anchorRow = [self rowForSubscriptionHeaderAtIndex:
        _compactSubscriptionTransitionAnchorIndex];
    if (anchorRow < 0) return;

    NSIndexPath *anchorPath = [NSIndexPath indexPathForRow:anchorRow inSection:1];
    CGRect anchorFrame = [_tableView rectForRowAtIndexPath:anchorPath];
    CGFloat anchoredOffset = anchorFrame.origin.y -
        _compactSubscriptionTransitionAnchorViewportY;
    _mainTableOffsetBeforeTransition = MAX(0.0f, anchoredOffset);
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x,
                                              _mainTableOffsetBeforeTransition)
                        animated:NO];
}

- (void)animateCompactSubscriptionOffsetToFinalPosition {
    if (_compactSubscriptionTransitionAnchorIndex < 0 || !_tableView) return;

    [_tableView layoutIfNeeded];
    NSInteger anchorRow = [self rowForSubscriptionHeaderAtIndex:
        _compactSubscriptionTransitionAnchorIndex];
    if (anchorRow < 0) return;

    NSIndexPath *anchorPath = [NSIndexPath indexPathForRow:anchorRow inSection:1];
    CGRect anchorFrame = [_tableView rectForRowAtIndexPath:anchorPath];
    CGFloat targetOffset = anchorFrame.origin.y -
        _compactSubscriptionTransitionAnchorViewportY;
    CGFloat maximumOffset = _compactSubscriptionTransitionFinalContentHeight -
        _tableView.bounds.size.height;
    if (maximumOffset < 0.0f) maximumOffset = 0.0f;
    if (targetOffset < 0.0f) targetOffset = 0.0f;
    if (targetOffset > maximumOffset) targetOffset = maximumOffset;
    _mainTableOffsetBeforeTransition = targetOffset;

    if (fabs(_tableView.contentOffset.y - targetOffset) <= 0.5f) return;
    _compactSubscriptionOffsetAnimationInProgress = YES;
    [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, targetOffset)
                        animated:YES];
}

- (void)recoverCompactSubscriptionTransition:(NSNumber *)transitionNumber {
    if ([transitionNumber unsignedIntegerValue] != _mainSectionTransitionToken) return;

    VCRecordAppEvent(@"layout", @"Compact subscription animation recovered",
                     @"reason=table_update_exception");
    BOOL animationsWereEnabled = [UIView areAnimationsEnabled];
    [UIView setAnimationsEnabled:NO];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _subscriptionExpansionOverridesActive = NO;
    [_tableView reloadData];
    [_tableView layoutIfNeeded];
    [self retargetCompactSubscriptionTransitionAnchor];
    [self completeMainTableStructuralTransition];
    [self refreshVisibleSubscriptionHeaderExpansionAppearanceAnimated:NO];
    [self refreshMainSwitcher];
    [CATransaction commit];
    [UIView setAnimationsEnabled:animationsWereEnabled];
    _compactSubscriptionOffsetAnimationInProgress = NO;
    _tableView.userInteractionEnabled = YES;
    [self scheduleMainDetailRelayout];
}

- (void)finishCompactSubscriptionTransition:(NSNumber *)transitionNumber {
    if ([transitionNumber unsignedIntegerValue] != _mainSectionTransitionToken ||
        !_mainSectionTransitionInProgress) {
        return;
    }

    BOOL animatedOffset = _compactSubscriptionOffsetAnimationInProgress;
    _subscriptionExpansionOverridesActive = NO;
    [_tableView layoutIfNeeded];
    if (!animatedOffset) {
        [self retargetCompactSubscriptionTransitionAnchor];
    }
    _compactSubscriptionOffsetAnimationInProgress = NO;
    [self completeMainTableStructuralTransition];
    [self refreshVisibleSubscriptionHeaderExpansionAppearanceAnimated:NO];
    [self refreshMainSwitcher];
    _tableView.userInteractionEnabled = YES;
    [self scheduleMainDetailRelayout];
}

- (void)startCompactSubscriptionTransitionFromHeaderRow:(NSInteger)oldHeaderRow
                                            oldItemCount:(NSInteger)oldItemCount
                                            newItemCount:(NSInteger)newItemCount
                                              anchorIndex:(NSInteger)anchorIndex
                                          anchorViewportY:(CGFloat)anchorViewportY {
    NSUInteger transitionToken = ++_mainSectionTransitionToken;
    NSNumber *transitionNumber = [NSNumber numberWithUnsignedInteger:transitionToken];
    _compactSubscriptionTransitionTarget = _expandedSubscription;
    _compactSubscriptionTransitionAnchorIndex = anchorIndex;
    _compactSubscriptionTransitionAnchorViewportY = anchorViewportY;
    CGFloat oldItemsHeight = oldItemCount > 0 ? (44.0f * oldItemCount + 12.0f) : 0.0f;
    CGFloat newItemsHeight = newItemCount > 0 ? (44.0f * newItemCount + 12.0f) : 0.0f;
    CGFloat collapsedHeaderHeight = VCSubscriptionCardHeight(nil,
                                                             CGRectGetWidth(_tableView.bounds),
                                                             _reorderingSection == 1);
    CGFloat oldHeaderExtra = 0.0f;
    if (_subscriptionHeaderExpandedOverride >= 0 &&
        _subscriptionHeaderExpandedOverride < (NSInteger)[_subscriptions count]) {
        NSDictionary *oldSubscription = [_subscriptions objectAtIndex:
            _subscriptionHeaderExpandedOverride];
        oldHeaderExtra = VCSubscriptionCardHeight(VCSubscriptionDescription(oldSubscription),
                                                   CGRectGetWidth(_tableView.bounds),
                                                   _reorderingSection == 1) -
                         collapsedHeaderHeight;
    }
    CGFloat newHeaderExtra = 0.0f;
    if (_compactSubscriptionTransitionTarget >= 0 &&
        _compactSubscriptionTransitionTarget < (NSInteger)[_subscriptions count]) {
        NSDictionary *newSubscription = [_subscriptions objectAtIndex:
            _compactSubscriptionTransitionTarget];
        newHeaderExtra = VCSubscriptionCardHeight(VCSubscriptionDescription(newSubscription),
                                                   CGRectGetWidth(_tableView.bounds),
                                                   _reorderingSection == 1) -
                         collapsedHeaderHeight;
    }
    _compactSubscriptionTransitionFinalContentHeight = _tableView.contentSize.height -
        oldItemsHeight + newItemsHeight - oldHeaderExtra + newHeaderExtra;
    [self prepareMainTableStructuralTransition];
    _compactSubscriptionOffsetAnimationInProgress = NO;
    _tableView.userInteractionEnabled = NO;

    NSMutableArray *deletedRows = [NSMutableArray arrayWithCapacity:(NSUInteger)oldItemCount];
    for (NSInteger item = 0; item < oldItemCount; item++) {
        [deletedRows addObject:[NSIndexPath indexPathForRow:(oldHeaderRow + 1 + item)
                                                   inSection:1]];
    }

    _subscriptionRowsExpandedOverride = _compactSubscriptionTransitionTarget;
    _subscriptionHeaderExpandedOverride = _compactSubscriptionTransitionTarget;
    NSInteger newHeaderRow = (_compactSubscriptionTransitionTarget >= 0)
        ? [self rowForSubscriptionHeaderAtIndex:_compactSubscriptionTransitionTarget]
        : -1;
    NSMutableArray *insertedRows = [NSMutableArray arrayWithCapacity:(NSUInteger)newItemCount];
    for (NSInteger item = 0; item < newItemCount; item++) {
        [insertedRows addObject:[NSIndexPath indexPathForRow:(newHeaderRow + 1 + item)
                                                    inSection:1]];
    }

    [CATransaction begin];
    [CATransaction setAnimationDuration:0.22];
    [CATransaction setAnimationTimingFunction:
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
    [CATransaction setCompletionBlock:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishCompactSubscriptionTransition:transitionNumber];
        });
    }];
    @try {
        [_tableView beginUpdates];
        if ([deletedRows count] > 0) {
            [_tableView deleteRowsAtIndexPaths:deletedRows
                             withRowAnimation:UITableViewRowAnimationFade];
        }
        if ([insertedRows count] > 0) {
            [_tableView insertRowsAtIndexPaths:insertedRows
                             withRowAnimation:UITableViewRowAnimationFade];
        }
        [_tableView endUpdates];
        [self refreshVisibleSubscriptionHeaderExpansionAppearanceAnimated:YES];
        [self animateCompactSubscriptionOffsetToFinalPosition];
    } @catch (NSException *exception) {
        (void)exception;
        [CATransaction setCompletionBlock:nil];
        [CATransaction commit];
        [self recoverCompactSubscriptionTransition:transitionNumber];
        return;
    }
    [CATransaction commit];
}

- (void)updateMainEmptyState {
    if (!_tableView) return;

    if ([_configs count] > 0 || [_subscriptions count] > 0) {
        _mainSwitchView.hidden = _showingTerminal;
        _tableView.scrollEnabled = YES;
        _tableView.backgroundView = nil;
        return;
    }

    _mainSwitchView.hidden = YES;

    if (!IsPadDevice()) {
        CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
        _phoneConnectionCompact = NO;
        [_tableView setContentOffset:CGPointMake(_tableView.contentOffset.x, -collapseDistance)
                            animated:NO];
        [self updatePhoneConnectionLayout];
    }
    _tableView.scrollEnabled = NO;

    CGRect bounds = _tableView.bounds;
    UIView *background = [[[UIView alloc] initWithFrame:CGRectMake(0.0f,
                                                                   0.0f,
                                                                   bounds.size.width,
                                                                   bounds.size.height)] autorelease];
    background.backgroundColor = VCBackgroundColor();
    background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    CGFloat containerWidth = bounds.size.width - 32.0f;
    if (containerWidth > 300.0f) containerWidth = 300.0f;
    if (containerWidth < 220.0f) containerWidth = 220.0f;
    CGFloat containerHeight = 200.0f;
    CGFloat reservedTop = IsPadDevice() ? 0.0f : (kVCMainContentStartY - kVCMainCompactContentStartY);
    CGFloat availableHeight = bounds.size.height - reservedTop;
    if (availableHeight < containerHeight) availableHeight = containerHeight;
    CGFloat containerY = reservedTop + floorf((availableHeight - containerHeight) * 0.5f);
    if (containerY < 12.0f) containerY = 12.0f;

    UIView *container = [[[UIView alloc] initWithFrame:CGRectMake(floorf((bounds.size.width - containerWidth) * 0.5f),
                                                                         containerY,
                                                                         containerWidth,
                                                                         containerHeight)] autorelease];
    container.backgroundColor = [UIColor clearColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                 UIViewAutoresizingFlexibleRightMargin |
                                 UIViewAutoresizingFlexibleTopMargin |
                                 UIViewAutoresizingFlexibleBottomMargin;

    UIView *iconCircle = [[[UIView alloc] initWithFrame:CGRectMake(floorf((containerWidth - 58.0f) * 0.5f),
                                                                          0.0f,
                                                                          58.0f,
                                                                          58.0f)] autorelease];
    iconCircle.backgroundColor = VCCellBackgroundColor();
    iconCircle.layer.cornerRadius = 29.0f;
    iconCircle.layer.borderWidth = 1.5f;
    iconCircle.layer.borderColor = VCAccentColor().CGColor;

    UIImageView *icon = [[[UIImageView alloc] initWithFrame:CGRectMake(16.0f, 16.0f, 26.0f, 26.0f)] autorelease];
    icon.image = TintImageWithColor(MakeIconImage(VCIconTypeAdd, 26.0f, YES), VCAccentColor());
    icon.contentMode = UIViewContentModeCenter;
    [iconCircle addSubview:icon];
    [container addSubview:iconCircle];

    UILabel *title = [[[UILabel alloc] initWithFrame:CGRectMake(0.0f, 72.0f, containerWidth, 24.0f)] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.textColor = VCPrimaryTextColor();
    title.font = [UIFont boldSystemFontOfSize:17.0f];
    title.textAlignment = NSTextAlignmentCenter;
    title.text = @"Add your first connection";
    [container addSubview:title];

    UILabel *detail = [[[UILabel alloc] initWithFrame:CGRectMake(8.0f, 101.0f, containerWidth - 16.0f, 42.0f)] autorelease];
    detail.backgroundColor = [UIColor clearColor];
    detail.textColor = VCSecondaryTextColor();
    detail.font = [UIFont systemFontOfSize:13.0f];
    detail.textAlignment = NSTextAlignmentCenter;
    detail.numberOfLines = 2;
    detail.text = @"Import a configuration or subscription\nto start using vless-core.";
    [container addSubview:detail];

    UIButton *addButton = [UIButton buttonWithType:UIButtonTypeCustom];
    addButton.frame = CGRectMake(floorf((containerWidth - 164.0f) * 0.5f), 156.0f, 164.0f, 40.0f);
    addButton.titleLabel.font = [UIFont boldSystemFontOfSize:14.0f];
    [addButton setTitle:@"Add connection" forState:UIControlStateNormal];
    [addButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [addButton setBackgroundImage:SolidImageWithColor(VCAccentColor()) forState:UIControlStateNormal];
    [addButton setBackgroundImage:SolidImageWithColor([VCAccentColor() colorWithAlphaComponent:0.72f])
                          forState:UIControlStateHighlighted];
    addButton.layer.cornerRadius = 8.0f;
    addButton.layer.masksToBounds = YES;
    addButton.accessibilityHint = @"Opens configuration and subscription import options";
    [addButton addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:addButton];

    [background addSubview:container];
    _tableView.backgroundView = background;
}

- (void)applyTheme {
    _darkThemeEnabled = VCAppearanceIsDark();
    UIColor *background = VCBackgroundColor();
    self.view.backgroundColor = background;
    _titleLabel.textColor = VCPrimaryTextColor();
    _connectionStateLabel.textColor = VCPrimaryTextColor();
    _selectionLabel.textColor = VCAccentColor();
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _statusLabel.textColor = _statusOK ? VCSuccessColor() : VCErrorColor();
    [self updateConnectButton];
    [self updateLogSelectorAnimated:NO];
    _logView.backgroundColor = background;
    _logView.textColor = VCPrimaryTextColor();
    if (_logView && _activeLogIndex >= 0 && _activeLogIndex <= 1 &&
        _logTexts[_activeLogIndex]) {
        CGPoint savedLogOffset = _logView.contentOffset;
        if ([_logView respondsToSelector:@selector(setAttributedText:)]) {
            _logView.attributedText = VCFormattedLogText(_logTexts[_activeLogIndex]);
        } else {
            _logView.text = _logTexts[_activeLogIndex];
        }
        [_logView setContentOffset:savedLogOffset animated:NO];
    }
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    VCAppearanceApplyTable(_tableView);
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.separatorColor = [UIColor clearColor];
    VCAppearanceApplyStatusBar();

    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self applyTopButtonFeedbackToButton:_updateBtn];
    [self updateTopButtonsIcons];
    [_tableView reloadData];
    [self updateMainEmptyState];
    [self refreshMainSwitcher];
}

- (void)setMainReorderingSection:(NSInteger)section showStatus:(BOOL)showStatus {
    if (section < 0 || section > 1) section = -1;
    if (_reorderingSection == section) return;

    NSInteger previousSection = _reorderingSection;
    if (previousSection >= 0) {
        [_tableView setEditing:NO animated:NO];
    }

    if (previousSection == 1 && section != 1 && _subscriptionToReexpandAfterReorder) {
        NSUInteger index = [_subscriptions indexOfObjectIdenticalTo:_subscriptionToReexpandAfterReorder];
        _expandedSubscription = (index == NSNotFound) ? -1 : (NSInteger)index;
        [_subscriptionToReexpandAfterReorder release];
        _subscriptionToReexpandAfterReorder = nil;
    }

    _reorderingSection = section;
    if (section == 0) {
        _configurationsSectionExpanded = YES;
        _subscriptionsSectionExpanded = NO;
    } else if (section == 1) {
        _subscriptionsSectionExpanded = YES;
        _configurationsSectionExpanded = NO;
        [_subscriptionToReexpandAfterReorder release];
        _subscriptionToReexpandAfterReorder = nil;
        if (_expandedSubscription >= 0 && _expandedSubscription < (NSInteger)[_subscriptions count]) {
            _subscriptionToReexpandAfterReorder = [[_subscriptions objectAtIndex:_expandedSubscription] retain];
        }
        _expandedSubscription = -1;
    }

    [self saveMainState];
    [self reloadMainTableDataAfterExternalChange];
    if (_reorderingSection >= 0) {
        [_tableView setEditing:YES animated:YES];
        if (showStatus) {
            [self showStatus:@"Drag rows. Hold the tab again to save" ok:YES];
        }
    } else if (showStatus && previousSection >= 0) {
        [self showStatus:(previousSection == 0
                              ? @"Configuration order saved"
                              : @"Subscription order saved")
                     ok:YES];
    }
}

- (void)mainTabLongPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan ||
        _mainTabTransitionInProgress || _mainSectionTransitionInProgress) return;
    NSInteger section = gesture.view.tag - kVCMainSectionHeaderButtonTagBase;
    if (section < 0 || section > 1) return;
    if (![self isMainTabSelected:section]) {
        [self showStatus:@"Select the list before reordering" ok:YES];
        return;
    }

    NSArray *items = (section == 0) ? (NSArray *)_configs : (NSArray *)_subscriptions;
    if (_reorderingSection == section) {
        VCRecordAppEvent(@"ui", @"List reordering finished", section == 0 ? @"section=configurations" : @"section=subscriptions");
        [self setMainReorderingSection:-1 showStatus:YES];
        return;
    }
    if ([items count] < 2) {
        [self showStatus:@"At least two items are needed to reorder" ok:YES];
        return;
    }
    if (section == 1 && _launchAutoUpdateInProgress) {
        [self showStatus:@"Wait for the subscription update to finish" ok:YES];
        return;
    }

    [self setMainReorderingSection:section showStatus:YES];
    VCRecordAppEvent(@"ui", @"List reordering started", section == 0 ? @"section=configurations" : @"section=subscriptions");
}

- (void)mainTabPressed:(UIButton *)sender {
    NSInteger section = sender.tag - kVCMainSectionHeaderButtonTagBase;
    if (section < 0 || section > 1 ||
        _mainTabTransitionInProgress || _mainSectionTransitionInProgress) return;
    if ([self isMainTabSelected:section]) return;
    if (_reorderingSection >= 0) {
        [self showStatus:@"Finish reordering first" ok:YES];
        return;
    }
    _configurationsSectionExpanded = (section == 0);
    _subscriptionsSectionExpanded = (section == 1);
    [self saveMainState];
    [self updateMainSwitcherView:_mainSwitchView];
    BOOL compact = !IsPadDevice() && (_phoneConnectionCompact || _tableView.contentOffset.y >= -0.5f);
    CGFloat topOffset = compact ? 0.0f : -(kVCMainContentStartY - kVCMainCompactContentStartY);
    _mainTabTransitionInProgress = YES;
    _tableView.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.10 animations:^{
        _tableView.alpha = 0.0f;
    } completion:^(BOOL finished) {
        (void)finished;
        [_tableView reloadData];
        [_tableView layoutIfNeeded];
        [_tableView setContentOffset:CGPointMake(0.0f, IsPadDevice() ? 0.0f : topOffset)
                                    animated:NO];
        [self updatePhoneConnectionScrollInsets];
        [self updatePhoneConnectionLayout];
        [UIView animateWithDuration:0.16 animations:^{
            _tableView.alpha = 1.0f;
        } completion:^(BOOL shown) {
            (void)shown;
            _mainTabTransitionInProgress = NO;
            _tableView.userInteractionEnabled = YES;
        }];
    }];
    VCRecordAppEvent(@"ui", @"Main list switched", section == 0 ? @"section=configurations" : @"section=subscriptions");
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 0.01f;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 0.01f;
}

- (UIView *)createMainSwitcherWithWidth:(CGFloat)width {
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0.0f,
                                                               0.0f,
                                                               width,
                                                               kVCMainSectionHeaderHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];
    CGFloat switchWidth = width;
    UIView *track = [[[UIView alloc] initWithFrame:CGRectMake(0.0f, 6.0f, switchWidth, 36.0f)] autorelease];
    track.backgroundColor = VCCellBackgroundColor();
    track.layer.cornerRadius = 10.0f;
    track.layer.borderWidth = 1.0f;
    track.layer.borderColor = VCSeparatorColor().CGColor;
    track.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:track];

    for (NSInteger tab = 0; tab < 2; tab++) {
        CGFloat tabWidth = switchWidth * 0.5f;
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(1.0f + tab * (tabWidth - 1.0f), 1.0f,
                                  tabWidth - 1.0f, 34.0f);
        button.tag = kVCMainSectionHeaderButtonTagBase + tab;
        button.autoresizingMask = tab == 0 ? UIViewAutoresizingFlexibleRightMargin
                                           : UIViewAutoresizingFlexibleLeftMargin;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:11.5f];
        button.titleLabel.adjustsFontSizeToFitWidth = YES;
        VCSetLabelMinimumScaleFactor(button.titleLabel, 0.85f);
        button.titleEdgeInsets = UIEdgeInsetsMake(0.0f, 2.0f, 0.0f, 26.0f);
        [button setTitle:tab == 0 ? @"Configurations" : @"Subscriptions"
                forState:UIControlStateNormal];
        button.layer.cornerRadius = 9.0f;
        button.layer.borderWidth = 1.0f;
        button.layer.masksToBounds = YES;
        button.accessibilityLabel = tab == 0 ? @"Configurations" : @"Subscriptions";
        [button addTarget:self action:@selector(mainTabPressed:)
         forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *longPress = [[[UILongPressGestureRecognizer alloc]
            initWithTarget:self action:@selector(mainTabLongPressed:)] autorelease];
        longPress.minimumPressDuration = 0.5;
        [button addGestureRecognizer:longPress];

        UIButton *countBadge = [UIButton buttonWithType:UIButtonTypeCustom];
        countBadge.frame = CGRectMake(button.bounds.size.width - 28.0f, 8.0f, 23.0f, 18.0f);
        countBadge.tag = kVCMainSectionHeaderCountTagBase + tab;
        countBadge.userInteractionEnabled = NO;
        countBadge.titleLabel.font = [UIFont boldSystemFontOfSize:11.0f];
        countBadge.titleLabel.adjustsFontSizeToFitWidth = YES;
        VCSetLabelMinimumScaleFactor(countBadge.titleLabel, 0.65f);
        countBadge.layer.cornerRadius = 9.0f;
        [button addSubview:countBadge];
        [self updateMainTabButton:button section:tab];
        [track addSubview:button];
    }

    return header;
}

- (void)updateMainTabButton:(UIButton *)button section:(NSInteger)section {
    if (!button || section < 0 || section > 1) return;

    BOOL selected = [self isMainTabSelected:section];
    button.accessibilityValue = selected ? @"Selected" : @"Not selected";
    button.accessibilityHint = selected
        ? (_reorderingSection == section ? @"Long press again to save the order"
                                          : @"Long press to reorder this list")
        : @"Shows this list";
    button.backgroundColor = selected ? [VCAccentColor() colorWithAlphaComponent:0.28f] : [UIColor clearColor];
    button.layer.borderColor = selected ? VCAccentColor().CGColor : [UIColor clearColor].CGColor;
    [button setTitleColor:selected ? VCPrimaryTextColor() : VCSecondaryTextColor()
                forState:UIControlStateNormal];

    UIButton *countLabel = (UIButton *)[button viewWithTag:(kVCMainSectionHeaderCountTagBase + section)];
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    [countLabel setTitle:[NSString stringWithFormat:@"%lu", (unsigned long)count]
                forState:UIControlStateNormal];
    countLabel.backgroundColor = selected ? VCAccentColor()
                                          : [VCSecondaryTextColor() colorWithAlphaComponent:0.18f];
    [countLabel setTitleColor:selected ? [UIColor whiteColor] : VCSecondaryTextColor()
                    forState:UIControlStateNormal];
}

- (void)updateMainSwitcherView:(UIView *)header {
    if (!header) return;

    UIButton *firstButton = (UIButton *)[header viewWithTag:kVCMainSectionHeaderButtonTagBase];
    UIView *track = firstButton.superview;
    CGFloat switchWidth = header.bounds.size.width;
    track.frame = CGRectMake(0.0f, 6.0f, switchWidth, 36.0f);
    track.backgroundColor = VCCellBackgroundColor();
    track.layer.borderColor = VCSeparatorColor().CGColor;
    for (NSInteger tab = 0; tab < 2; tab++) {
        UIButton *button = (UIButton *)[header viewWithTag:(kVCMainSectionHeaderButtonTagBase + tab)];
        CGFloat tabWidth = switchWidth * 0.5f;
        button.frame = CGRectMake(1.0f + tab * (tabWidth - 1.0f), 1.0f,
                                  tabWidth - 1.0f, 34.0f);
        UIButton *badge = (UIButton *)[button viewWithTag:(kVCMainSectionHeaderCountTagBase + tab)];
        badge.frame = CGRectMake(button.bounds.size.width - 28.0f, 8.0f, 23.0f, 18.0f);
        [self updateMainTabButton:button section:tab];
    }
}

- (void)reloadMainTableDataAfterExternalChange {
    _mainSectionTransitionToken++;
    _subscriptionExpansionOverridesActive = NO;
    _compactSubscriptionOffsetAnimationInProgress = NO;
    [self prepareMainTableStructuralTransition];
    [_tableView reloadData];
    [self updateMainEmptyState];
    [self completeMainTableStructuralTransition];
    _tableView.userInteractionEnabled = YES;
    [self refreshMainSwitcher];
}

- (void)configureSubscriptionHeaderCell:(UITableViewCell *)cell atIndex:(NSInteger)index {
    if (![cell isKindOfClass:[VCSubscriptionHeaderCell class]] ||
        index < 0 || index >= (NSInteger)[_subscriptions count]) {
        return;
    }

    NSDictionary *subscription = [_subscriptions objectAtIndex:index];
    BOOL providerButtonsEnabled = (_reorderingSection != 1);
    BOOL hasWebPage = providerButtonsEnabled &&
        [VCSubscriptionProviderURL(subscription, kSubscriptionWebPageURLKey) length] > 0;
    BOOL hasSupport = providerButtonsEnabled &&
        [VCSubscriptionProviderURL(subscription, kSubscriptionSupportURLKey) length] > 0;
    [(VCSubscriptionHeaderCell *)cell
        configureDescription:VCSubscriptionDescription(subscription)
                 configCount:[NSString stringWithFormat:@"%lu",
                              (unsigned long)[[self subscriptionItemsAtIndex:index] count]]
                     traffic:[self subscriptionTrafficTextFromDictionary:subscription]
                      expiry:[self subscriptionExpiryTextFromDictionary:subscription]
                 lastUpdated:VCSubscriptionLastUpdatedText(subscription)
             showDescription:([self subscriptionHeaderExpandedIndex] == index)
                 pingLoading:[self isSubscriptionPingInProgressAtIndex:index]
                     canPing:([[self subscriptionItemsAtIndex:index] count] > 0)
                showActions:providerButtonsEnabled
                  hasWebPage:hasWebPage
                   hasSupport:hasSupport
                       index:index
                      target:self];
}

- (void)refreshVisibleSubscriptionHeaderAccessories {
    if (!_tableView || !_subscriptionsSectionExpanded || _reorderingSection == 1) return;

    for (NSInteger subIdx = 0; subIdx < (NSInteger)[_subscriptions count]; subIdx++) {
        NSInteger row = [self rowForSubscriptionHeaderAtIndex:subIdx];
        if (row < 0) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;

        BOOL expanded = [self subscriptionHeaderExpandedIndex] == subIdx;
        BOOL loading = _updatingSubscriptionIndex == subIdx;
        cell.accessoryView = [self subscriptionHeaderAccessoryExpanded:expanded loading:loading];
        [self configureSubscriptionHeaderCell:cell atIndex:subIdx];
    }
}

- (void)refreshVisibleSubscriptionHeaderExpansionAppearanceAnimated:(BOOL)animated {
    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSInteger expandedIndex = [self subscriptionHeaderExpandedIndex];
    for (NSInteger subIdx = 0; subIdx < (NSInteger)[_subscriptions count]; subIdx++) {
        NSInteger row = [self rowForSubscriptionHeaderAtIndex:subIdx];
        if (row < 0) continue;
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (![cell isKindOfClass:[VCSubscriptionHeaderCell class]]) continue;

        BOOL expanded = (expandedIndex == subIdx);
        BOOL active = (_selectedSubIndex == subIdx && _selectedSubItemIndex >= 0);
        [(VCMainListCell *)cell configureVisualKind:VCMainListCellKindSubscriptionHeader
                                             expanded:expanded
                                            firstItem:NO
                                             lastItem:NO
                                                active:active
                                       showsHeaderTab:(_reorderingSection != 1)];
        [self configureSubscriptionHeaderCell:cell atIndex:subIdx];

        UIImageView *chevron = (UIImageView *)[cell.accessoryView
            viewWithTag:kVCSubscriptionHeaderChevronTag];
        if (![chevron isKindOfClass:[UIImageView class]]) continue;
        UIImage *image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight,
                                       16.0f, NO);
        if (animated) {
            [UIView transitionWithView:chevron
                              duration:0.15
                               options:(UIViewAnimationOptionTransitionCrossDissolve |
                                        UIViewAnimationOptionBeginFromCurrentState)
                            animations:^{
                                chevron.image = image;
                            }
                            completion:nil];
        } else {
            chevron.image = image;
        }
    }
}

- (BOOL)isMainTabSelected:(NSInteger)section {
    if (section == 0) return _configurationsSectionExpanded;
    if (section == 1) return _subscriptionsSectionExpanded;
    return NO;
}

- (void)refreshMainSwitcher {
    [self updateMainSwitcherView:_mainSwitchView];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self stabilizeMainTableOffsetDuringStructuralTransition];
        [self updatePhoneConnectionLayout];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView != _tableView) return;
    _mainTableDragStartOffsetY = scrollView.contentOffset.y;
    _mainTableDragStartOffsetValid = YES;
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView != _tableView || IsPadDevice() || _showingTerminal || !targetContentOffset) return;

    CGFloat referenceOffset = _mainTableDragStartOffsetValid
        ? _mainTableDragStartOffsetY
        : scrollView.contentOffset.y;
    CGFloat proposedOffset = targetContentOffset->y;
    CGFloat snappedOffset = [self phoneConnectionSnapOffsetForProposedOffset:proposedOffset
                                                               currentOffset:referenceOffset
                                                                    velocity:velocity.y];
    CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
    CGFloat expandedOffset = -collapseDistance;
    if (snappedOffset <= expandedOffset + 0.5f) {
        _phoneConnectionCompact = NO;
    } else if (snappedOffset >= -0.5f) {
        _phoneConnectionCompact = YES;
    }

    targetContentOffset->y = snappedOffset;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self snapPhoneConnectionLayoutIfNeededAnimated:YES];
        [self scheduleMainDetailRelayout];
        [self recordMainLayoutEvent:@"Main list scroll ended"];
    } else if (scrollView == _logView) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == _tableView) {
        if (!decelerate) {
            CGFloat collapseDistance = kVCMainContentStartY - kVCMainCompactContentStartY;
            CGFloat expandedOffset = -collapseDistance;
            CGFloat currentOffset = scrollView.contentOffset.y;
            if (currentOffset > expandedOffset + 0.5f && currentOffset < -0.5f) {
                [self animatePhoneConnectionToOffset:(_phoneConnectionCompact ? 0.0f : expandedOffset)];
            } else {
                [self snapPhoneConnectionLayoutIfNeededAnimated:YES];
            }
            [self scheduleMainDetailRelayout];
            [self recordMainLayoutEvent:@"Main list drag ended"];
        }
        _mainTableDragStartOffsetValid = NO;
    } else if (scrollView == _logView && !decelerate) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    if (scrollView != _tableView) return;
    [self updatePhoneConnectionLayout];
    [self scheduleMainDetailRelayout];
}

@end
