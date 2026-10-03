#import "list_logic.h"

NSArray *VCSubscriptionItemsAtIndex(NSArray *subscriptions, NSInteger subIdx) {
    if (subIdx < 0 || subIdx >= (NSInteger)[subscriptions count]) return [NSArray array];
    NSDictionary *sub = [subscriptions objectAtIndex:subIdx];
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return [NSArray array];
    return items;
}

NSInteger VCSubscriptionRowCount(NSArray *subscriptions, NSInteger expandedIndex) {
    NSInteger rows = 0;
    for (NSInteger i = 0; i < (NSInteger)[subscriptions count]; i++) {
        rows += 1;
        if (i == expandedIndex) {
            rows += (NSInteger)[VCSubscriptionItemsAtIndex(subscriptions, i) count];
        }
    }
    return rows;
}

BOOL VCMapSubscriptionRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger row, NSInteger *subIndex, NSInteger *itemIndex, BOOL *isHeader) {
    NSInteger cursor = 0;
    for (NSInteger i = 0; i < (NSInteger)[subscriptions count]; i++) {
        if (row == cursor) {
            if (subIndex) *subIndex = i;
            if (itemIndex) *itemIndex = -1;
            if (isHeader) *isHeader = YES;
            return YES;
        }
        cursor += 1;

        if (i == expandedIndex) {
            NSArray *items = VCSubscriptionItemsAtIndex(subscriptions, i);
            NSInteger cnt = (NSInteger)[items count];
            if (row < cursor + cnt) {
                if (subIndex) *subIndex = i;
                if (itemIndex) *itemIndex = row - cursor;
                if (isHeader) *isHeader = NO;
                return YES;
            }
            cursor += cnt;
        }
    }
    return NO;
}

NSInteger VCSubscriptionHeaderRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger subIdx) {
    if (subIdx < 0 || subIdx >= (NSInteger)[subscriptions count]) return -1;

    NSInteger row = 0;
    for (NSInteger i = 0; i < (NSInteger)[subscriptions count]; i++) {
        if (i == subIdx) {
            return row;
        }
        row += 1;
        if (i == expandedIndex) {
            row += (NSInteger)[VCSubscriptionItemsAtIndex(subscriptions, i) count];
        }
    }

    return -1;
}

void VCNormalizeSelection(NSUInteger configCount, NSArray *subscriptions, NSInteger *configIndex, NSInteger *subIndex, NSInteger *itemIndex) {
    if ((*configIndex) >= (NSInteger)configCount) {
        (*configIndex) = -1;
    }

    if ((*subIndex) >= (NSInteger)[subscriptions count]) {
        (*subIndex) = -1;
        (*itemIndex) = -1;
    }

    if ((*subIndex) >= 0) {
        NSArray *items = VCSubscriptionItemsAtIndex(subscriptions, (*subIndex));
        if ([items count] == 0) {
            (*itemIndex) = -1;
        } else if ((*itemIndex) < 0 || (*itemIndex) >= (NSInteger)[items count]) {
            (*itemIndex) = 0;
        }
    }
}

void VCMoveListItem(NSMutableArray *items, NSInteger source, NSInteger destination, NSInteger *selectedIndex) {
    id selected = nil;
    if (*selectedIndex >= 0 && *selectedIndex < (NSInteger)[items count]) selected = [[items objectAtIndex:*selectedIndex] retain];
    id moved = [[items objectAtIndex:source] retain];
    [items removeObjectAtIndex:source];
    [items insertObject:moved atIndex:destination];
    [moved release];
    if (selected) {
        NSUInteger newIndex = [items indexOfObjectIdenticalTo:selected];
        *selectedIndex = (newIndex == NSNotFound) ? -1 : (NSInteger)newIndex;
        [selected release];
    }
}
