#ifndef VC_LIST_LOGIC_H
#define VC_LIST_LOGIC_H
#import <Foundation/Foundation.h>
NSArray *VCSubscriptionItemsAtIndex(NSArray *subscriptions, NSInteger subIdx);
NSInteger VCSubscriptionRowCount(NSArray *subscriptions, NSInteger expandedIndex);
BOOL VCMapSubscriptionRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger row, NSInteger *subIndex, NSInteger *itemIndex, BOOL *isHeader);
NSInteger VCSubscriptionHeaderRow(NSArray *subscriptions, NSInteger expandedIndex, NSInteger subIdx);
void VCNormalizeSelection(NSUInteger configCount, NSArray *subscriptions, NSInteger *configIndex, NSInteger *subIndex, NSInteger *itemIndex);
void VCMoveListItem(NSMutableArray *items, NSInteger source, NSInteger destination, NSInteger *selectedIndex);
#endif
