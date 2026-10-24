#import "list_logic.h"

NSArray *VCSubscriptionItemsAtIndex(NSArray *subscriptions, NSInteger subIdx) {
    if (subIdx < 0 || subIdx >= (NSInteger)[subscriptions count]) return [NSArray array];
    NSDictionary *sub = [subscriptions objectAtIndex:subIdx];
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return [NSArray array];
    return items;
}

NSInteger VCSubscriptionRowCount(NSArray *subscriptions, NSInteger expandedIndex) {
    return (NSInteger)[subscriptions count]+(NSInteger)[VCSubscriptionItemsAtIndex(subscriptions,expandedIndex) count];
}

BOOL VCMapSubscriptionRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger row, NSInteger *subIndex, NSInteger *itemIndex, BOOL *isHeader) {
    if (row < 0) return NO;
    NSInteger count=(NSInteger)[subscriptions count];
    NSInteger extra=(NSInteger)[VCSubscriptionItemsAtIndex(subscriptions,expandedIndex) count];
    if (row >= count+extra) return NO;
    BOOL item=expandedIndex >= 0 && expandedIndex < count && row > expandedIndex && row <= expandedIndex+extra;
    NSInteger index=item ? expandedIndex : row-((expandedIndex >= 0 && row > expandedIndex+extra) ? extra : 0);
    if (subIndex) *subIndex=index;
    if (itemIndex) *itemIndex=item ? row-expandedIndex-1 : -1;
    if (isHeader) *isHeader=!item;
    return YES;
}

NSInteger VCSubscriptionHeaderRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger subIdx) {
    if (subIdx < 0 || subIdx >= (NSInteger)[subscriptions count]) return -1;
    return subIdx+((expandedIndex >= 0 && expandedIndex < subIdx) ? (NSInteger)[VCSubscriptionItemsAtIndex(subscriptions,expandedIndex) count] : 0);
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
