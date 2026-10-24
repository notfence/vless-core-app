#import "list_logic.h"
#include <limits.h>
#include <stdlib.h>

struct VCSubscriptionPingEntry {
    NSUInteger source;
    unsigned int latency;
};

static unsigned int VCSubscriptionPingLatency(id display) {
    if (![display isKindOfClass:[NSString class]] || ![display hasSuffix:@" ms"] || [display length] <= 3) return UINT_MAX;
    unsigned int value = 0;
    for (NSUInteger i = 0; i < [display length]-3; i++) {
        unichar c = [display characterAtIndex:i];
        if (c < '0' || c > '9' || value > (INT_MAX-(unsigned int)(c-'0'))/10) return UINT_MAX;
        value = value*10+(unsigned int)(c-'0');
    }
    return value;
}

static int VCCompareSubscriptionPingEntries(const void *left, const void *right) {
    const struct VCSubscriptionPingEntry *a = left, *b = right;
    if (a->latency != b->latency) return a->latency < b->latency ? -1 : 1;
    return (a->source > b->source)-(a->source < b->source);
}

@implementation VCSubscriptionPingOrder
- (id)initWithItems:(NSArray *)items displays:(NSDictionary *)displays {
    self = [super init];
    if (self) {
        _items = [items retain];
        [self updateWithDisplays:displays];
    }
    return self;
}
- (void)dealloc {
    free(_entries);
    [_items release];
    [super dealloc];
}
- (BOOL)matchesItems:(NSArray *)items { return _items == items; }
- (NSInteger)sourceIndexForDisplayIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)[_items count]) return -1;
    return _entries ? (NSInteger)_entries[index].source : index;
}
- (BOOL)updateWithDisplays:(NSDictionary *)displays {
    if (![displays count] && !_entries) return NO;
    NSUInteger count = [_items count];
    struct VCSubscriptionPingEntry *entries = NULL;
    BOOL reordered = NO;
    if ([displays count] && count > 1) {
        if (count > NSUIntegerMax/sizeof(*entries)) return NO;
        entries = malloc(count*sizeof(*entries));
        if (!entries) return NO;
        for (NSUInteger i = 0; i < count; i++) {
            entries[i].source = i;
            entries[i].latency = VCSubscriptionPingLatency([displays objectForKey:[_items objectAtIndex:i]]);
        }
        qsort(entries, count, sizeof(*entries), VCCompareSubscriptionPingEntries);
        for (NSUInteger i = 0; i < count; i++) {
            if (entries[i].source != i) { reordered = YES; break; }
        }
        if (!reordered) { free(entries); entries = NULL; }
    }
    BOOL changed = NO;
    for (NSUInteger i = 0; i < count; i++) {
        if ((_entries ? _entries[i].source : i) != (entries ? entries[i].source : i)) { changed = YES; break; }
    }
    free(_entries);
    _entries = entries;
    return changed;
}
@end

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
