#import <Foundation/Foundation.h>
#import "../common/connection_logic.h"
#include "check.h"
#include <sys/resource.h>
#include <sys/time.h>
#ifdef VC_PING_START_BENCHMARK
#import <dispatch/dispatch.h>
#import <CoreFoundation/CoreFoundation.h>
#endif

typedef NSInteger VCPingType;
#ifdef VC_PING_START_BENCHMARK
static VCPingType VCSelectedPingType(void) { return 0; }
static NSInteger VCPingTimeoutSecondsInDefaults(id defaults) { (void)defaults; return 5; }
static BOOL VCUseXmuxInDefaults(id defaults) { (void)defaults; return YES; }
static NSString *VCSelectedProxyPingURL(void) { return @"http://127.0.0.1/"; }
#endif
static NSString *kVCPingLoadingValue=@"loading";
static void VCRecordAppEvent(id a,id b,id c) { (void)a; (void)b; (void)c; }

@interface VCTestPingQueue : NSObject {
    NSMutableArray *_operations;
}
- (NSArray *)operations;
- (void)addOperation:(NSOperation *)operation;
- (void)cancelAllOperations;
@end
@implementation VCTestPingQueue
- (id)init { if ((self=[super init])) _operations=[[NSMutableArray alloc] init]; return self; }
- (NSArray *)operations {
    for (NSUInteger i=[_operations count];i>0;i--)
        if ([[_operations objectAtIndex:i-1] isFinished]) [_operations removeObjectAtIndex:i-1];
    return _operations;
}
- (void)addOperation:(NSOperation *)operation { [_operations addObject:operation]; }
- (void)cancelAllOperations { for (NSOperation *operation in _operations) [operation cancel]; }
- (void)dealloc { [_operations release]; [super dealloc]; }
@end

@interface MainVC : NSObject {
@public
    NSMutableDictionary *_pingDisplayByURI,*_standalonePingCancellationsByURI;
    NSMutableDictionary *_subscriptionPingPendingByIdentifier,*_subscriptionPingOperationsByIdentifier;
    NSMutableDictionary *_subscriptionPingPreviousDisplayByIdentifier,*_subscriptionPingTokenByIdentifier;
    NSMutableDictionary *_subscriptionPingPreparationByIdentifier;
    NSMutableArray *_subscriptionPingReadyIdentifiers;
    VCTestPingQueue *_pingQueue;
    BOOL _sortSubscriptionsByPing;
    NSUInteger _nextSubscriptionPingToken,_pingNetworkGeneration;
    NSArray *_items;
}
- (void)pingWorker:(id)payload;
- (NSOperation *)enqueuePingForURI:(NSString *)uri type:(VCPingType)type priority:(NSOperationQueuePriority)priority batchIdentifier:(NSString *)identifier batchToken:(NSNumber *)token;
- (void)pumpSubscriptionPings;
- (void)pingOperationFinished:(VCPingCancellation *)cancellation;
- (BOOL)isURIInActiveSubscriptionPing:(NSString *)uri;
- (void)stopAllPings;
- (void)stopSubscriptionPingAtIndex:(NSInteger)index;
- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)index;
- (void)refreshVisiblePingAccessoriesForURI:(id)uri;
- (void)refreshVisibleSubscriptionPingAccessories;
- (void)refreshVisibleSubscriptionHeaderAccessories;
- (void)scheduleSubscriptionPingSort;
- (void)showStatus:(id)message ok:(BOOL)ok;
#ifdef VC_PING_START_BENCHMARK
- (void)startSubscriptionPingAtIndex:(NSInteger)index;
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index;
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index;
- (void)refreshPingNetworkState;
#endif
@end
@implementation MainVC
- (id)init {
    if ((self=[super init])) {
        _pingDisplayByURI=[[NSMutableDictionary alloc] init];
        _standalonePingCancellationsByURI=[[NSMutableDictionary alloc] init];
        _subscriptionPingPendingByIdentifier=[[NSMutableDictionary alloc] init];
        _subscriptionPingOperationsByIdentifier=[[NSMutableDictionary alloc] init];
        _subscriptionPingPreviousDisplayByIdentifier=[[NSMutableDictionary alloc] init];
        _subscriptionPingTokenByIdentifier=[[NSMutableDictionary alloc] init];
        _subscriptionPingPreparationByIdentifier=[[NSMutableDictionary alloc] init];
        _subscriptionPingReadyIdentifiers=[[NSMutableArray alloc] init];
        _pingQueue=[[VCTestPingQueue alloc] init];
    }
    return self;
}
- (void)dealloc {
    [self stopAllPings];
    [_pingDisplayByURI release]; [_standalonePingCancellationsByURI release];
    [_subscriptionPingPendingByIdentifier release]; [_subscriptionPingOperationsByIdentifier release];
    [_subscriptionPingPreviousDisplayByIdentifier release]; [_subscriptionPingTokenByIdentifier release];
    [_subscriptionPingPreparationByIdentifier release]; [_subscriptionPingReadyIdentifiers release];
    [_pingQueue release]; [super dealloc];
}
- (void)pingWorker:(id)payload { (void)payload; }
- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)index { return [NSString stringWithFormat:@"%ld",(long)index]; }
- (void)refreshVisiblePingAccessoriesForURI:(id)uri { (void)uri; }
- (void)refreshVisibleSubscriptionPingAccessories {}
- (void)refreshVisibleSubscriptionHeaderAccessories {}
- (void)scheduleSubscriptionPingSort {}
- (void)showStatus:(id)message ok:(BOOL)ok { (void)message; (void)ok; }
- (NSOperation *)enqueuePingForURI:(NSString *)uri type:(VCPingType)type priority:(NSOperationQueuePriority)priority batchIdentifier:(NSString *)identifier batchToken:(NSNumber *)token {
    (void)type; (void)identifier; (void)token;
    VCPingCancellation *cancel=[[[VCPingCancellation alloc] init] autorelease];
    VCPingOperation *operation=[[[VCPingOperation alloc] initWithTarget:self payload:@{} cancellation:cancel] autorelease];
    operation.queuePriority=priority;
    [_pingDisplayByURI setObject:kVCPingLoadingValue forKey:uri];
    [_pingQueue addOperation:operation];
    return operation;
}
#include "main_ping_test.inc"
#ifdef VC_PING_START_BENCHMARK
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index { (void)index; return _items; }
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index { return [_subscriptionPingTokenByIdentifier objectForKey:[self subscriptionPingIdentifierAtIndex:index]]!=nil; }
- (void)refreshPingNetworkState {}
#include "ping_start_test.inc"
#endif
@end

static VCPingBatch *attach(MainVC *owner,NSInteger index,NSArray *items) {
    NSString *identifier=[owner subscriptionPingIdentifierAtIndex:index];
    VCPingBatch *batch=[[[VCPingBatch alloc] initWithURIs:items options:@{@"type":@0} cancellation:nil] autorelease];
    [owner->_subscriptionPingPendingByIdentifier setObject:batch forKey:identifier];
    [owner->_subscriptionPingOperationsByIdentifier setObject:batch.operations forKey:identifier];
    [owner->_subscriptionPingPreviousDisplayByIdentifier setObject:batch.previousDisplays forKey:identifier];
    [owner->_subscriptionPingTokenByIdentifier setObject:@1 forKey:identifier];
    [owner->_subscriptionPingReadyIdentifiers addObject:identifier];
    return batch;
}

int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
#ifdef VC_PING_START_BENCHMARK
    if (argc==3 && !strcmp(argv[1],"--measure")) {
        NSUInteger count=strtoul(argv[2],NULL,10);
        MainVC *measured=[[[MainVC alloc] init] autorelease];
        NSMutableArray *items=[NSMutableArray arrayWithCapacity:count];
        for (NSUInteger i=0;i<count;i++) [items addObject:[NSString stringWithFormat:@"profile:%lu",(unsigned long)i]];
        measured->_items=items;
        double started=CFAbsoluteTimeGetCurrent();
        [measured startSubscriptionPingAtIndex:0];
        double mainMs=(CFAbsoluteTimeGetCurrent()-started)*1000;
        while ([measured->_subscriptionPingPreparationByIdentifier count] && CFAbsoluteTimeGetCurrent()-started<10)
            CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.001,YES);
        CHECK("ping-bench/preparation-completed",![measured->_subscriptionPingPreparationByIdentifier count]);
        double readyMs=(CFAbsoluteTimeGetCurrent()-started)*1000;
        NSUInteger live=[[measured->_pingQueue operations] count];
        double cancel=CFAbsoluteTimeGetCurrent();
        [measured stopAllPings];
        double cancelMs=(CFAbsoluteTimeGetCurrent()-cancel)*1000;
        struct rusage usage; getrusage(RUSAGE_SELF,&usage);
        printf("{\"count\":%lu,\"main_start_ms\":%.6f,\"ready_ms\":%.6f,\"cancel_ms\":%.6f,\"live_operations\":%lu,\"cpu_s\":%.6f,\"maxrss\":%ld}\n",
            (unsigned long)count,mainMs,readyMs,cancelMs,(unsigned long)live,
            usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6,usage.ru_maxrss);
        [pool drain]; return 0;
    }
#else
    (void)argc; (void)argv;
#endif
    MainVC *owner=[[[MainVC alloc] init] autorelease];
    [owner->_pingDisplayByURI setObject:@"42 ms" forKey:@"a"];
    VCPingBatch *first=attach(owner,0,@[@"a",@"b",@"c",@"d",@"e"]);
    VCPingBatch *second=attach(owner,1,@[@"v",@"w",@"x",@"y",@"z"]);
    [owner pumpSubscriptionPings];
    CHECK("ping-pump/only-four-operations",[[owner->_pingQueue operations] count]==4);
    CHECK("ping-pump/round-robin",[first.operations count]==2 && [second.operations count]==2);
    CHECK("ping-pump/no-loading-object-for-waiting",[owner->_pingDisplayByURI objectForKey:@"e"]==nil && [owner isURIInActiveSubscriptionPing:@"e"]);
    CHECK("ping-pump/only-active-prior-displays",[first.previousDisplays count]==2 && [second.previousDisplays count]==2);
    VCPingOperation *done=[[first.operations objectAtIndex:0] retain];
    [done start];
    [owner pingOperationFinished:done.cancellation];
    CHECK("ping-pump/completion-releases-reference",![first.operations containsObject:done] && [first.operations count]+[second.operations count]==4);
    [done release];
    [owner stopSubscriptionPingAtIndex:0];
    CHECK("ping-pump/independent-cancel",[owner->_subscriptionPingTokenByIdentifier count]==1 && [owner isURIInActiveSubscriptionPing:@"z"]);
    CHECK("ping-pump/old-result-restored",[[owner->_pingDisplayByURI objectForKey:@"a"] isEqual:@"42 ms"]);
    VCPingCancellation *preparation=[[[VCPingCancellation alloc] init] autorelease];
    [owner->_subscriptionPingPreparationByIdentifier setObject:preparation forKey:@"2"];
    [owner->_subscriptionPingTokenByIdentifier setObject:@2 forKey:@"2"];
    [owner stopAllPings];
    CHECK("ping-pump/preparation-cancelled",[preparation isCancelled] && ![owner->_subscriptionPingTokenByIdentifier count]);
    CHECK("ping-pump/waiting-results-unchanged",[owner->_pingDisplayByURI count]==1 && [[owner->_pingDisplayByURI objectForKey:@"a"] isEqual:@"42 ms"]);
    CHECK("ping-pump/cursor-lists-released",![owner->_subscriptionPingPendingByIdentifier count] && ![owner->_subscriptionPingReadyIdentifiers count]);
    [owner pingOperationFinished:nil];
    CHECK("ping-pump/late-completion-cannot-restart",![owner->_subscriptionPingTokenByIdentifier count]);
    [owner->_pingQueue release]; owner->_pingQueue=[[VCTestPingQueue alloc] init];
    NSMutableArray *many=[NSMutableArray array];
    for (NSUInteger i=0;i<1000;i++) [many addObject:[NSString stringWithFormat:@"p%lu",(unsigned long)i]];
    VCPingBatch *large=attach(owner,3,many);
    [owner pumpSubscriptionPings];
    NSUInteger finished=0;
    while ([large.operations count]) {
        NSAutoreleasePool *step=[[NSAutoreleasePool alloc] init];
        VCPingOperation *operation=[[large.operations objectAtIndex:0] retain];
        [operation start];
        [owner pingOperationFinished:operation.cancellation];
        [operation release];
        CHECK("ping-pump/large-list-bounded",[large.operations count]<=4 && [large.previousDisplays count]<=1000);
        finished++;
        [step drain];
    }
    CHECK("ping-pump/every-cursor-item-issued",finished==1000);
    FINISH("main ping scheduler");
    [pool drain]; return 0;
}
