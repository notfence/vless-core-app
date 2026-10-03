#import "main_screen.h"
#import "main_cells.h"

@implementation MainVC (VCMainTable)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) {
        return _configurationsSectionExpanded ? [_configs count] : 0;
    }
    return _subscriptionsSectionExpanded ? [self subscriptionSectionRowCount] : 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) {
        if (_reorderingSection == 0) return 56.0f;
        BOOL firstItem = (indexPath.row == 0);
        BOOL lastItem = (indexPath.row == (NSInteger)[_configs count] - 1);
        return 44.0f + (firstItem ? 4.0f : 0.0f) + (lastItem ? 8.0f : 0.0f);
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row
                       toSubIndex:&subIdx
                        itemIndex:&itemIdx
                         isHeader:&isHeader]) {
        return 44.0f;
    }
    if (isHeader) {
        if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return 84.0f;
        NSDictionary *subscription = [_subscriptions objectAtIndex:subIdx];
        NSString *visibleDescription = ([self subscriptionHeaderExpandedIndex] == subIdx)
            ? VCSubscriptionDescription(subscription)
            : nil;
        return VCSubscriptionCardHeight(visibleDescription,
                                        CGRectGetWidth(tableView.bounds),
                                        _reorderingSection == 1);
    }

    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    BOOL firstItem = (itemIdx == 0);
    BOOL lastItem = (itemIdx == (NSInteger)[items count] - 1);
    return 44.0f + (firstItem ? 4.0f : 0.0f) + (lastItem ? 8.0f : 0.0f);
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection >= 0) {
        return indexPath.section == _reorderingSection;
    }
    if (indexPath.section == 0) {
        return YES;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        return NO;
    }
    if (!isHeader && subIdx >= 0 && subIdx < (NSInteger)[_subscriptions count] &&
        SubscriptionDictionaryIsHappEncrypted([_subscriptions objectAtIndex:subIdx])) {
        return NO;
    }
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    if (_reorderingSection >= 0) return UITableViewCellEditingStyleNone;
    return UITableViewCellEditingStyleDelete;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return _reorderingSection < 0;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection < 0 || indexPath.section != _reorderingSection) return NO;
    if (indexPath.section == 0) {
        return indexPath.row >= 0 && indexPath.row < (NSInteger)[_configs count];
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = NO;
    return [self mapSubscriptionRow:indexPath.row
                         toSubIndex:&subIdx
                          itemIndex:&itemIdx
                           isHeader:&isHeader] && isHeader;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    (void)tableView;
    NSInteger count = (_reorderingSection == 0) ? (NSInteger)[_configs count]
                                                : (NSInteger)[_subscriptions count];
    if (count <= 0) return sourceIndexPath;

    NSInteger row = proposedDestinationIndexPath.row;
    if (proposedDestinationIndexPath.section < _reorderingSection) row = 0;
    else if (proposedDestinationIndexPath.section > _reorderingSection) row = count - 1;
    if (row < 0) row = 0;
    if (row >= count) row = count - 1;
    return [NSIndexPath indexPathForRow:row inSection:_reorderingSection];
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
       toIndexPath:(NSIndexPath *)destinationIndexPath {
    (void)tableView;
    if (_reorderingSection < 0 ||
        sourceIndexPath.section != _reorderingSection ||
        destinationIndexPath.section != _reorderingSection ||
        sourceIndexPath.row == destinationIndexPath.row) {
        return;
    }

    NSMutableArray *items = (_reorderingSection == 0) ? _configs : _subscriptions;
    if (sourceIndexPath.row < 0 || sourceIndexPath.row >= (NSInteger)[items count] ||
        destinationIndexPath.row < 0 || destinationIndexPath.row >= (NSInteger)[items count]) {
        return;
    }

    NSInteger *selectedIndex = (_reorderingSection == 0) ? &_selectedConfigIndex : &_selectedSubIndex;
    VCMoveListItem(items, sourceIndexPath.row, destinationIndexPath.row, selectedIndex);

    [self normalizeSelection];
    [self saveData];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) return;

        [_configs removeObjectAtIndex:indexPath.row];
        VCRecordAppEvent(@"configuration", @"Configuration deleted",
                         [NSString stringWithFormat:@"remaining=%lu", (unsigned long)[_configs count]]);

        if (_selectedConfigIndex == indexPath.row) {
            if ([_configs count] > 0) {
                NSInteger fallback = indexPath.row;
                if (fallback >= (NSInteger)[_configs count]) fallback = (NSInteger)[_configs count] - 1;
                _selectedConfigIndex = fallback;
            } else {
                _selectedConfigIndex = -1;
            }
        } else if (_selectedConfigIndex > indexPath.row) {
            _selectedConfigIndex--;
        }

        [self normalizeSelection];
        [self saveData];
        [self reloadMainTableDataAfterExternalChange];
        [self showStatus:@"Configuration deleted" ok:YES];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        return;
    }

    if (isHeader) {
        if (![self deleteSubscriptionAtIndex:subIdx]) return;
        [self reloadMainTableDataAfterExternalChange];
        [self showStatus:@"Subscription deleted" ok:YES];
        return;
    }

    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return;
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    if (SubscriptionDictionaryIsHappEncrypted(sub)) return;
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return;
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) return;

    NSMutableArray *updatedItems = [NSMutableArray arrayWithArray:items];
    [updatedItems removeObjectAtIndex:itemIdx];
    VCRecordAppEvent(@"subscription", @"Subscription configuration deleted",
                     [NSString stringWithFormat:@"remaining_in_subscription=%lu",
                      (unsigned long)[updatedItems count]]);

    NSMutableDictionary *updatedSub = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updatedSub setObject:updatedItems forKey:@"items"];
    [_subscriptions replaceObjectAtIndex:subIdx withObject:updatedSub];

    if (_selectedSubIndex == subIdx) {
        if (_selectedSubItemIndex == itemIdx) {
            if ([updatedItems count] == 0) {
                _selectedSubItemIndex = -1;
            } else {
                NSInteger fallback = itemIdx;
                if (fallback >= (NSInteger)[updatedItems count]) fallback = (NSInteger)[updatedItems count] - 1;
                _selectedSubItemIndex = fallback;
            }
        } else if (_selectedSubItemIndex > itemIdx) {
            _selectedSubItemIndex--;
        }
    }

    [self normalizeSelection];
    [self saveData];
    [self reloadMainTableDataAfterExternalChange];
    [self showStatus:@"Subscription config deleted" ok:YES];
}

- (void)applyDetailForMainCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (!cell || !indexPath) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) {
            [self applyDetailPrefix:@"" tail:@"" toCell:cell];
            return;
        }
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *uri = [cfg objectForKey:@"uri"];
        NSString *prefix = [self configPrefixTextFromURI:uri];
        NSString *tail = [self configEndpointTextFromURI:uri];
        [self applyDetailPrefix:prefix
                    prefixColor:[self configPrefixColorForURI:uri]
                           tail:tail
                         toCell:cell];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        [self applyDetailPrefix:@"" tail:@"" toCell:cell];
        return;
    }

    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    if (isHeader) {
        [self clearDetailTextForCell:cell];
        return;
    }

    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) {
        [self applyDetailPrefix:@"" tail:@"" toCell:cell];
        return;
    }

    NSString *uri = [items objectAtIndex:itemIdx];
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *tail = SubscriptionDictionaryIsHappEncrypted(sub)
        ? kHiddenLinkText
        : [self configEndpointTextFromURI:uri];
    [self applyDetailPrefix:prefix
                prefixColor:[self configPrefixColorForURI:uri]
                       tail:tail
                     toCell:cell];
}

- (void)runQueuedMainDetailRelayout {
    _queuedMainDetailRelayout = NO;
    if (!_tableView || _showingTerminal) return;

    NSArray *visible = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *ip in visible) {
        UITableViewCell *visibleCell = [_tableView cellForRowAtIndexPath:ip];
        if (visibleCell) {
            [self applyDetailForMainCell:visibleCell atIndexPath:ip];
        }
    }
}

- (void)scheduleMainDetailRelayout {
    if (_queuedMainDetailRelayout) return;
    _queuedMainDetailRelayout = YES;
    [self performSelector:@selector(runQueuedMainDetailRelayout) withObject:nil afterDelay:0.0];
}

- (void)refreshMainListCellAppearance:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (!cell || !indexPath) return;
    if ([cell isKindOfClass:[VCMainListCell class]]) {
        [(VCMainListCell *)cell refreshVisualAppearance];
        return;
    }

    BOOL selectedConfig = (indexPath.section == 0 && _selectedConfigIndex == indexPath.row);
    cell.backgroundColor = selectedConfig ? VCSelectedCellColor() : VCCellBackgroundColor();
    cell.contentView.backgroundColor = [UIColor clearColor];
}

- (void)refreshVisiblePingAccessoriesForURI:(NSString *)uri {
    if (!_tableView || (uri && (![uri isKindOfClass:[NSString class]] || [uri length] == 0))) return;

    NSArray *visibleRows = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visibleRows) {
        NSInteger tag = -1;
        NSString *rowURI = nil;

        if (indexPath.section == 0) {
            if (indexPath.row >= 0 && indexPath.row < (NSInteger)[_configs count]) {
                NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
                rowURI = [cfg objectForKey:@"uri"];
                tag = 10000 + indexPath.row;
            }
        } else {
            NSInteger subIdx = -1;
            NSInteger itemIdx = -1;
            BOOL isHeader = YES;
            if ([self mapSubscriptionRow:indexPath.row
                              toSubIndex:&subIdx
                               itemIndex:&itemIdx
                                isHeader:&isHeader] && !isHeader) {
                NSArray *items = [self subscriptionItemsAtIndex:subIdx];
                if (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) {
                    rowURI = [items objectAtIndex:itemIdx];
                    tag = 20000 + (subIdx * 1000) + itemIdx;
                }
            }
        }

        if (tag < 0 || (uri && ![rowURI isEqualToString:uri])) continue;
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        cell.accessoryView = [self accessoryPingWithTag:tag uri:rowURI];
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
        [self applyDetailForMainCell:cell atIndexPath:indexPath];
    }
}

- (void)refreshVisibleSubscriptionPingAccessories {
    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSArray *visibleRows = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visibleRows) {
        if (indexPath.section != 1) continue;

        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if (![self mapSubscriptionRow:indexPath.row
                           toSubIndex:&subIdx
                            itemIndex:&itemIdx
                             isHeader:&isHeader] || isHeader) {
            continue;
        }

        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) continue;

        NSString *uri = [items objectAtIndex:itemIdx];
        NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:indexPath];
        if (!cell) continue;
        cell.accessoryView = [self accessoryPingWithTag:tag uri:uri];
        [cell setNeedsLayout];
        [cell layoutIfNeeded];
        [self applyDetailForMainCell:cell atIndexPath:indexPath];
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger mappedSubIdx = -1;
    NSInteger mappedItemIdx = -1;
    BOOL mappedIsHeader = YES;
    VCMainListCellKind visualKind = VCMainListCellKindConfigurationItem;
    BOOL firstItem = NO;
    BOOL lastItem = NO;
    BOOL expanded = NO;
    BOOL active = NO;
    NSString *cellID = @"VCItemCell";

    if (indexPath.section == 0) {
        firstItem = (_reorderingSection == 0 || indexPath.row == 0);
        lastItem = (_reorderingSection == 0 || indexPath.row == (NSInteger)[_configs count] - 1);
        active = (_selectedConfigIndex == indexPath.row);
        cellID = @"VCConfigurationItemCell";
    } else if (indexPath.section == 1 &&
        [self mapSubscriptionRow:indexPath.row
                      toSubIndex:&mappedSubIdx
                       itemIndex:&mappedItemIdx
                        isHeader:&mappedIsHeader]) {
        if (mappedIsHeader) {
            visualKind = VCMainListCellKindSubscriptionHeader;
            expanded = ([self subscriptionHeaderExpandedIndex] == mappedSubIdx);
            active = (_selectedSubIndex == mappedSubIdx && _selectedSubItemIndex >= 0);
            cellID = @"VCSubscriptionHeaderCell";
        } else {
            visualKind = VCMainListCellKindSubscriptionItem;
            NSArray *mappedItems = [self subscriptionItemsAtIndex:mappedSubIdx];
            firstItem = (mappedItemIdx == 0);
            lastItem = (mappedItemIdx == (NSInteger)[mappedItems count] - 1);
            active = (_selectedSubIndex == mappedSubIdx && _selectedSubItemIndex == mappedItemIdx);
            cellID = @"VCSubscriptionItemCell";
        }
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        if (visualKind == VCMainListCellKindSubscriptionHeader) {
            cell = [[[VCSubscriptionHeaderCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                    reuseIdentifier:cellID] autorelease];
        } else {
            cell = [[[VCMainListCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:cellID] autorelease];
        }
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0f];
    }
    cell.clipsToBounds = YES;
    cell.contentView.clipsToBounds = YES;
    cell.indentationLevel = 0;
    cell.indentationWidth = 14.0f;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.showsReorderControl = (_reorderingSection == indexPath.section);
    cell.selectionStyle = (_reorderingSection >= 0 ||
                           visualKind == VCMainListCellKindSubscriptionHeader)
        ? UITableViewCellSelectionStyleNone : UITableViewCellSelectionStyleBlue;
    VCAppearanceApplyCell(cell);
    if ([cell isKindOfClass:[VCMainListCell class]]) {
        [(VCMainListCell *)cell configureVisualKind:visualKind
                                          expanded:expanded
                                         firstItem:firstItem
                                          lastItem:lastItem
                                             active:active
                                    showsHeaderTab:(visualKind == VCMainListCellKindSubscriptionHeader &&
                                                    _reorderingSection != 1)];
    } else {
        [self refreshMainListCellAppearance:cell atIndexPath:indexPath];
    }

    if (indexPath.section == 0) {
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        NSString *shownConfigName = ([name length] > 0) ? name : [NSString stringWithFormat:@"Config %ld", (long)(indexPath.row + 1)];
        cell.textLabel.text = [self maskedLinkText:shownConfigName];
        if (_reorderingSection != 0) {
            NSString *uri = [cfg objectForKey:@"uri"];
            cell.accessoryView = [self accessoryPingWithTag:(10000 + indexPath.row) uri:uri];
        }
    } else {
        NSInteger subIdx = mappedSubIdx;
        NSInteger itemIdx = mappedItemIdx;
        BOOL isHeader = mappedIsHeader;
        if (subIdx >= 0) {
            NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
            NSString *name = [sub objectForKey:@"name"];
            NSString *url = [sub objectForKey:@"url"];
            NSArray *items = [self subscriptionItemsAtIndex:subIdx];

            if (isHeader) {
                NSString *shownName = ([name length] > 0) ? name : @"";
                NSString *host = [self hostFromURLString:url];
                if ([shownName length] == 0 || [shownName isEqualToString:host]) {
                    shownName = [self subscriptionNameFromURLString:url];
                }
                shownName = [self maskedLinkText:shownName];
                cell.textLabel.text = shownName;
                if (_reorderingSection != 1) {
                    BOOL loading = (_updatingSubscriptionIndex == subIdx);
                    BOOL expanded = [self subscriptionHeaderExpandedIndex] == subIdx;
                    cell.accessoryView = [self subscriptionHeaderAccessoryExpanded:expanded loading:loading];
                }
                [self configureSubscriptionHeaderCell:cell atIndex:subIdx];
            } else {
                NSString *uri = [items objectAtIndex:itemIdx];
                cell.indentationLevel = 0;
                NSString *itemName = [self displayNameForSubscriptionURI:uri
                                                                    index:itemIdx
                                                             subscription:sub];
                cell.textLabel.text = [self maskedLinkText:itemName];
                NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
                cell.accessoryView = [self accessoryPingWithTag:tag uri:uri];
            }
        } else {
            cell.textLabel.text = @"(invalid row)";
        }
    }

    [self applyDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainDetailRelayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCAppearanceApplyCell(cell);
    [self refreshMainListCellAppearance:cell atIndexPath:indexPath];
    [self applyDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainDetailRelayout];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (_reorderingSection >= 0) {
        [_tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    if (_mainSectionTransitionInProgress) {
        [_tableView deselectRowAtIndexPath:indexPath animated:NO];
        return;
    }
    if (VCConfigurationSelectionBlocked(_connectionActionInProgress, _connected, _subscriptionRefreshInProgress)) {
        BOOL selectsConfiguration = indexPath.section == 0;
        if (indexPath.section == 1) {
            BOOL isHeader = YES;
            selectsConfiguration = [self mapSubscriptionRow:indexPath.row
                                                toSubIndex:NULL itemIndex:NULL isHeader:&isHeader] && !isHeader;
        }
        if (selectsConfiguration) {
            [_tableView deselectRowAtIndexPath:indexPath animated:NO];
            VCRecordAppEvent(@"connection", @"Configuration switch blocked",
                             _connectionActionInProgress ? @"connection action in progress" : @"subscription update in progress");
            [self showStatus:@"Busy" ok:NO];
            return;
        }
    }
    BOOL animateSubscriptionsSection = NO;
    BOOL selectionChanged = NO;
    NSInteger oldExpandedSubscription = -1;
    NSInteger oldExpandedHeaderRow = -1;
    NSInteger oldExpandedItemCount = 0;
    NSInteger subscriptionHeaderAnchorIndex = -1;
    CGFloat subscriptionHeaderAnchorViewportY = 0.0f;
    BOOL compactSubscriptionTransition = NO;
    NSString *oldURI = nil;
    if (_connected) {
        NSString *u = [self uriForCurrentSelection];
        if ([u isKindOfClass:[NSString class]] && [u length] > 0) {
            oldURI = [u copy];
        }
    }

    if (indexPath.section == 0) {
        VCRecordAppEvent(@"ui", @"Configuration selected",
                         [NSString stringWithFormat:@"index=%ld total=%lu",
                          (long)indexPath.row, (unsigned long)[_configs count]]);
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        _selectedConfigIndex = indexPath.row;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        selectionChanged = YES;
        [self showStatus:[NSString stringWithFormat:@"Selected config: %@", name ? name : @"(unnamed)"] ok:YES];
    } else {
        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if ([self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
            if (isHeader) {
                compactSubscriptionTransition = !IsPadDevice() &&
                    (_phoneConnectionCompact || _tableView.contentOffset.y >= -0.5f);
                CGRect selectedHeaderFrame = [_tableView rectForRowAtIndexPath:indexPath];
                subscriptionHeaderAnchorIndex = subIdx;
                subscriptionHeaderAnchorViewportY = selectedHeaderFrame.origin.y -
                    _tableView.contentOffset.y;
                VCRecordAppEvent(@"ui", @"Subscription expanded state changed",
                                 [NSString stringWithFormat:@"index=%ld expanded=%d configs=%lu",
                                  (long)subIdx,
                                  _expandedSubscription == subIdx ? 0 : 1,
                                  (unsigned long)[[self subscriptionItemsAtIndex:subIdx] count]]);
                animateSubscriptionsSection = YES;
                oldExpandedSubscription = _expandedSubscription;
                if (oldExpandedSubscription >= 0) {
                    oldExpandedHeaderRow = [self rowForSubscriptionHeaderAtIndex:oldExpandedSubscription];
                    oldExpandedItemCount = (NSInteger)[[self subscriptionItemsAtIndex:oldExpandedSubscription] count];
                }
                if (compactSubscriptionTransition) {
                    _subscriptionExpansionOverridesActive = YES;
                    _subscriptionRowsExpandedOverride = oldExpandedSubscription;
                    _subscriptionHeaderExpandedOverride = oldExpandedSubscription;
                }
                if (_expandedSubscription == subIdx) {
                    _expandedSubscription = -1;
                } else {
                    _expandedSubscription = subIdx;
                    if ([[self subscriptionItemsAtIndex:subIdx] count] == 0) {
                        [self refreshSubscriptionAtIndex:subIdx showStatus:NO];
                    }
                }
                NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
                NSString *name = [sub objectForKey:@"name"];
                [self showStatus:[NSString stringWithFormat:@"Subscription: %@", name ? name : @"(unnamed)"] ok:YES];
            } else {
                VCRecordAppEvent(@"ui", @"Subscription configuration selected",
                                 [NSString stringWithFormat:@"subscription_index=%ld item_index=%ld",
                                  (long)subIdx, (long)itemIdx]);
                NSArray *items = [self subscriptionItemsAtIndex:subIdx];
                NSString *uri = (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) ? [items objectAtIndex:itemIdx] : @"";
                _selectedConfigIndex = -1;
                _selectedSubIndex = subIdx;
                _selectedSubItemIndex = itemIdx;
                selectionChanged = YES;
                NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
                NSString *itemName = [self displayNameForSubscriptionURI:uri
                                                                    index:itemIdx
                                                             subscription:sub];
                [self showStatus:[NSString stringWithFormat:@"Selected: %@", itemName] ok:YES];
            }
        }
    }

    [_tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self normalizeSelection];
    if (selectionChanged || animateSubscriptionsSection) [self saveMainState];
    if (_connected && oldURI) {
        NSString *newURI = [self uriForCurrentSelection];
        [self reconnectToURIIfNeededFrom:oldURI to:newURI];
    }

    if (animateSubscriptionsSection) {
        NSInteger newExpandedSubscription = _expandedSubscription;
        NSInteger newExpandedHeaderRow = (newExpandedSubscription >= 0)
            ? [self rowForSubscriptionHeaderAtIndex:newExpandedSubscription]
            : -1;
        NSInteger newExpandedItemCount = (newExpandedSubscription >= 0)
            ? (NSInteger)[[self subscriptionItemsAtIndex:newExpandedSubscription] count]
            : 0;

        if (compactSubscriptionTransition) {
            BOOL animationsWereEnabled = [UIView areAnimationsEnabled];
            if (animationsWereEnabled) {
                [self startCompactSubscriptionTransitionFromHeaderRow:oldExpandedHeaderRow
                                                          oldItemCount:oldExpandedItemCount
                                                          newItemCount:newExpandedItemCount
                                                            anchorIndex:subscriptionHeaderAnchorIndex
                                                        anchorViewportY:subscriptionHeaderAnchorViewportY];
                [oldURI release];
                return;
            }

            ++_mainSectionTransitionToken;
            [self prepareMainTableStructuralTransition];
            [UIView setAnimationsEnabled:NO];
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _subscriptionExpansionOverridesActive = NO;
            [_tableView reloadData];
            [_tableView layoutIfNeeded];
            if (subscriptionHeaderAnchorIndex >= 0) {
                NSInteger anchorRow = [self rowForSubscriptionHeaderAtIndex:subscriptionHeaderAnchorIndex];
                if (anchorRow >= 0) {
                    NSIndexPath *anchorPath = [NSIndexPath indexPathForRow:anchorRow inSection:1];
                    CGRect anchorFrame = [_tableView rectForRowAtIndexPath:anchorPath];
                    CGFloat anchoredOffset = anchorFrame.origin.y - subscriptionHeaderAnchorViewportY;
                    _mainTableOffsetBeforeTransition = MAX(0.0f, anchoredOffset);
                }
            }
            [self completeMainTableStructuralTransition];
            [self refreshVisibleSubscriptionHeaderAccessories];
            [self refreshMainSwitcher];
            [CATransaction commit];
            [UIView setAnimationsEnabled:animationsWereEnabled];
            [oldURI release];
            return;
        }

        NSMutableArray *deletedRows = [NSMutableArray array];
        for (NSInteger item = 0; item < oldExpandedItemCount; item++) {
            [deletedRows addObject:[NSIndexPath indexPathForRow:(oldExpandedHeaderRow + 1 + item)
                                                       inSection:1]];
        }

        NSMutableArray *insertedRows = [NSMutableArray array];
        for (NSInteger item = 0; item < newExpandedItemCount; item++) {
            [insertedRows addObject:[NSIndexPath indexPathForRow:(newExpandedHeaderRow + 1 + item)
                                                        inSection:1]];
        }

        NSUInteger transitionToken = ++_mainSectionTransitionToken;
        [self prepareMainTableStructuralTransition];
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            if (transitionToken != _mainSectionTransitionToken) return;
            [self completeMainTableStructuralTransition];
            [self refreshVisibleSubscriptionHeaderAccessories];
            [self refreshMainSwitcher];
        }];

        UITableViewCell *selectedHeaderCell = [_tableView cellForRowAtIndexPath:indexPath];
        [self configureSubscriptionHeaderCell:selectedHeaderCell
                                      atIndex:subscriptionHeaderAnchorIndex];
        if (oldExpandedSubscription >= 0 && oldExpandedSubscription != newExpandedSubscription) {
            NSIndexPath *oldHeaderPath = [NSIndexPath indexPathForRow:oldExpandedHeaderRow
                                                            inSection:1];
            UITableViewCell *oldHeaderCell = [_tableView cellForRowAtIndexPath:oldHeaderPath];
            [self configureSubscriptionHeaderCell:oldHeaderCell atIndex:oldExpandedSubscription];
        }

        [_tableView beginUpdates];
        if ([deletedRows count] > 0) {
            [_tableView deleteRowsAtIndexPaths:deletedRows withRowAnimation:UITableViewRowAnimationFade];
        }
        if ([insertedRows count] > 0) {
            [_tableView insertRowsAtIndexPaths:insertedRows withRowAnimation:UITableViewRowAnimationFade];
        }
        [_tableView endUpdates];
        [CATransaction commit];

        if ([deletedRows count] == 0 && [insertedRows count] == 0) {
            [self refreshVisibleSubscriptionHeaderAccessories];
        }
    } else {
        [_tableView reloadData];
    }
    [oldURI release];
}

@end
