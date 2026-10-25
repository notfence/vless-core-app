#import "../common/connection_logic.h"
#include "check.h"

@interface NSObject (VCBatchTestAPI)
- (id)initWithURIs:(NSArray *)uris options:(NSDictionary *)options cancellation:(VCPingCancellation *)cancellation;
- (NSString *)nextURI;
- (NSMutableSet *)pending;
- (NSMutableArray *)operations;
- (NSMutableDictionary *)previousDisplays;
- (NSDictionary *)options;
@end

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    Class implementation=NSClassFromString(@"VCPingBatch");
    CHECK("ping-batch/bounded-cursor-exists",implementation!=Nil);
    for (NSUInteger count=1000;count<=20000;count=count==1000 ? 6000 : 20000) {
        NSAutoreleasePool *work=[[NSAutoreleasePool alloc] init];
        NSMutableArray *items=[NSMutableArray array];
        for (NSUInteger i=0;i<count;i++) {
            NSString *uri=[NSString stringWithFormat:@"profile:%lu",(unsigned long)i];
            [items addObject:uri]; [items addObject:uri];
        }
        [items addObject:@0]; [items addObject:@""];
        VCPingCancellation *cancel=[[[VCPingCancellation alloc] init] autorelease];
        NSDictionary *options=@{@"type":@0,@"timeout_ms":@5000,@"use_xmux":@1};
        id batch=[[[implementation alloc] initWithURIs:items options:options cancellation:cancel] autorelease];
        CHECK("ping-batch/unique-pending",[[batch pending] count]==count);
        CHECK("ping-batch/no-eager-operations",[[batch operations] count]==0 && [[batch previousDisplays] count]==0);
        CHECK("ping-batch/options-snapshot",[[batch options] isEqual:options]);
        for (NSUInteger i=0;i<count;i++) {
            NSString *uri=[batch nextURI];
            CHECK("ping-batch/source-order",[uri isEqual:[NSString stringWithFormat:@"profile:%lu",(unsigned long)i]]);
            CHECK("ping-batch/queued-is-pending",[[batch pending] containsObject:uri]);
            [[batch pending] removeObject:uri];
        }
        CHECK("ping-batch/exhausted",[batch nextURI]==nil && [[batch pending] count]==0);
        [cancel cancel];
        CHECK("ping-batch/cancelled-preparation",[[[implementation alloc] initWithURIs:items options:options cancellation:cancel] autorelease]==nil);
        [work drain];
        if (count==20000) break;
    }
    FINISH("ping batch cursor"); [pool drain]; return 0;
}
