#import <Foundation/Foundation.h>
#ifdef __APPLE__
#include <Block.h>
#else
#include "support/objc/blocks_runtime.h"
#endif
#import "../common/connection_logic.h"
#include "check.h"

typedef NSInteger VCPingType;
enum { UIApplicationStateActive=0, UIApplicationStateBackground=2 };
#ifndef DISPATCH_QUEUE_PRIORITY_DEFAULT
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#endif
static NSInteger applicationState;
static NSUInteger scans;
static NSString *network=@"wifi-a";
static NSString *activeXrayVersion;
static VCPingType selectedPingType;
static VCPingType VCSelectedPingType(void) { return selectedPingType; }
static NSString *VCActiveXrayVersion(void) { return activeXrayVersion; }
static NSString *VCSelectedProxyPingURL(void) { return @"https://example.invalid/probe"; }
static NSInteger VCPingTimeoutSecondsInDefaults(id defaults) { (void)defaults; return 9; }
static BOOL VCUseXmuxInDefaults(id defaults) { (void)defaults; return YES; }
#define dispatch_get_global_queue VCNetworkTestGlobalQueue
#define dispatch_get_main_queue VCNetworkTestMainQueue
#define dispatch_async VCNetworkTestEnqueue
static void (^queued[2][128])(void);
static NSUInteger queuedCount[2];
static int dispatch_get_global_queue(int priority,int flags) { (void)priority; (void)flags; return 0; }
static int dispatch_get_main_queue(void) { return 1; }
static void dispatch_async(int queue,void (^block)(void)) {
    CHECK("network/bounded-test-queue",queuedCount[queue]<128);
    queued[queue][queuedCount[queue]++]=Block_copy(block);
}
static void runOne(int queue) {
    CHECK("network/expected-callback",queuedCount[queue]>0);
    void (^block)(void)=queued[queue][0];
    memmove(queued[queue],queued[queue]+1,--queuedCount[queue]*sizeof(block));
    block(); Block_release(block);
}
static NSString *VCPingNetworkSignature(void) { scans++; return network; }
static void VCRecordAppEvent(id a,id b,id c) { (void)a; (void)b; (void)c; }
@interface UIApplication : NSObject
+ (id)sharedApplication;
- (NSInteger)applicationState;
@end
@implementation UIApplication
+ (id)sharedApplication { static id value; if (!value) value=[[self alloc] init]; return value; }
- (NSInteger)applicationState { return applicationState; }
@end

@interface MainVC : NSObject {
@public
    BOOL _pingNetworkCheckInFlight,_pingNetworkCheckPending,_pingNetworkDirty,_publishingPingNetwork,_sortSubscriptionsByPing;
    NSUInteger _pingNetworkGeneration,stopped,begun,accepted,refills,failures;
    NSString *_pingNetworkSignature;
    NSMutableDictionary *_pingDisplayByURI;
    NSMutableArray *_pingNetworkStarts,*_pingNetworkResults;
    NSArray *_items;
    NSDictionary *_lastOptions;
}
- (NSDictionary *)pingOptionsForType:(VCPingType)type;
- (void)startPingForURI:(NSString *)uri type:(VCPingType)type;
- (void)startSubscriptionPingAtIndex:(NSInteger)index;
- (void)refreshPingNetworkState;
- (void)stopAllPings;
- (void)scheduleSubscriptionPingSort;
- (void)refreshVisiblePingAccessoriesForURI:(id)uri;
- (void)refreshVisibleSubscriptionHeaderAccessories;
- (void)pingResultOnMain:(NSDictionary *)result;
- (void)beginPingForURI:(id)uri type:(VCPingType)type options:(id)options;
- (void)beginSubscriptionPingAtIndex:(NSInteger)index options:(id)options;
- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)index;
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index;
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index;
- (void)pumpSubscriptionPings;
- (void)showStatus:(id)message ok:(BOOL)ok;
@end
@implementation MainVC
- (id)init {
    if ((self=[super init])) {
        _pingNetworkStarts=[[NSMutableArray alloc] init];
        _pingNetworkResults=[[NSMutableArray alloc] init];
        _pingDisplayByURI=[[NSMutableDictionary alloc] init];
        _items=[@[@"synthetic:1",@"synthetic:2"] retain];
    }
    return self;
}
- (void)dealloc { [_pingNetworkStarts release]; [_pingNetworkResults release]; [_pingDisplayByURI release]; [_pingNetworkSignature release]; [_items release]; [_lastOptions release]; [super dealloc]; }
- (void)stopAllPings { stopped++; if (!_publishingPingNetwork) [_pingNetworkStarts removeAllObjects]; [_pingNetworkResults removeAllObjects]; }
- (void)scheduleSubscriptionPingSort {}
- (void)refreshVisiblePingAccessoriesForURI:(id)uri { (void)uri; }
- (void)refreshVisibleSubscriptionHeaderAccessories {}
- (void)pingResultOnMain:(NSDictionary *)result {
    if (VCPingResultIsCurrent([[result objectForKey:@"network_generation"] unsignedIntegerValue],_pingNetworkGeneration)) accepted++;
}
- (void)beginPingForURI:(id)uri type:(VCPingType)type options:(id)options { (void)uri; (void)type; [_lastOptions release]; _lastOptions=[options copy]; begun++; }
- (void)beginSubscriptionPingAtIndex:(NSInteger)index options:(id)options { (void)index; [_lastOptions release]; _lastOptions=[options copy]; begun++; }
- (NSString *)subscriptionPingIdentifierAtIndex:(NSInteger)index { (void)index; return @"subscription"; }
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index { (void)index; return _items; }
- (BOOL)isSubscriptionPingInProgressAtIndex:(NSInteger)index {
    NSString *identifier=[self subscriptionPingIdentifierAtIndex:index];
    for (NSDictionary *start in _pingNetworkStarts)
        if ([[start objectForKey:@"identifier"] isEqual:identifier]) return YES;
    return NO;
}
- (void)pumpSubscriptionPings { refills++; }
- (void)showStatus:(id)message ok:(BOOL)ok { (void)message; if (!ok) failures++; }
#include "main_network_test.inc"
@end

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MainVC *owner=[[[MainVC alloc] init] autorelease];
    NSDictionary *request=@{@"uri":@"synthetic",@"options":@{@"type":@0}};
    [owner->_pingNetworkStarts addObject:request];
    [owner refreshPingNetworkState];
    CHECK("network/check-is-asynchronous",scans==0 && owner->_pingNetworkCheckInFlight && !owner->begun);
    for (int i=0;i<100;i++) [owner refreshPingNetworkState];
    CHECK("network/notifications-coalesce",queuedCount[0]==1);
    runOne(0); runOne(1);
    CHECK("network/dirty-during-check-rechecks-once",scans==1 && queuedCount[0]==1 && !owner->begun);
    runOne(0); runOne(1);
    CHECK("network/starts-after-current-signature",scans==2 && owner->begun==1 && !owner->_pingNetworkDirty && owner->_pingNetworkGeneration==1);
    [owner->_pingDisplayByURI setObject:@"10 ms" forKey:@"old"];
    [owner->_pingNetworkResults addObject:@{@"network_generation":@1}];
    [owner->_pingNetworkStarts addObject:request];
    network=@"wifi-b";
    [owner refreshPingNetworkState]; runOne(0); runOne(1);
    CHECK("network/change-cancels-old-not-new-start",owner->stopped==1 && owner->begun==2 && !owner->accepted && ![owner->_pingDisplayByURI count] && owner->_pingNetworkGeneration==2);
    [owner->_pingNetworkStarts addObject:request];
    [owner refreshPingNetworkState];
    [owner stopAllPings]; runOne(0); runOne(1);
    CHECK("network/cancel-prevents-deferred-start",owner->begun==2);
    [owner refreshPingNetworkState]; runOne(0);
    applicationState=UIApplicationStateBackground; runOne(1);
    CHECK("network/background-does-not-publish-results",owner->_pingNetworkDirty);
    NSUInteger before=scans;
    [owner refreshPingNetworkState];
    CHECK("network/background-does-not-scan",queuedCount[0]==0 && scans==before);
    applicationState=UIApplicationStateActive;
    [owner refreshPingNetworkState]; runOne(0); runOne(1);
    CHECK("network/resume-revalidates",scans==before+1 && !owner->_pingNetworkDirty);
    network=nil; [owner->_pingNetworkStarts addObject:request];
    [owner refreshPingNetworkState]; runOne(0); runOne(1);
    CHECK("network/failed-check-is-not-trusted",owner->_pingNetworkDirty && owner->failures==1 && owner->begun==2);
    network=@"wifi-options";
    for (NSUInteger spoof=0;spoof<2;spoof++) {
        for (VCPingType type=0;type<3;type++) {
            for (NSUInteger subscription=0;subscription<2;subscription++) {
                MainVC *probe=[[[MainVC alloc] init] autorelease];
                activeXrayVersion=spoof ? @"26.6.27" : nil;
                selectedPingType=type;
                BOOL threw=NO;
                @try {
                    if (subscription) [probe startSubscriptionPingAtIndex:0];
                    else [probe startPingForURI:@"synthetic:single" type:type];
                } @catch (NSException *exception) { (void)exception; threw=YES; }
                CHECK("ping-options/start-with-optional-spoof-does-not-throw",!threw);
                CHECK("ping-options/one-deferred-start",[probe->_pingNetworkStarts count]==1 && queuedCount[0]==1 && !probe->begun);
                activeXrayVersion=spoof ? nil : @"26.7.1";
                selectedPingType=(type+1)%3;
                runOne(0); runOne(1);
                NSDictionary *captured=probe->_lastOptions;
                CHECK("ping-options/deferred-start-delivered",probe->begun==1 && ![probe->_pingNetworkStarts count]);
                CHECK("ping-options/type-snapshot",[[captured objectForKey:@"type"] integerValue]==type);
                CHECK("ping-options/timeout-preserved",[[captured objectForKey:@"timeout_ms"] integerValue]==9000);
                CHECK("ping-options/url-preserved",[[captured objectForKey:@"probe_url"] isEqual:VCSelectedProxyPingURL()]);
                CHECK("ping-options/xmux-preserved",[[captured objectForKey:@"use_xmux"] boolValue]);
                CHECK("ping-options/disabled-spoof-omitted",spoof || ![captured objectForKey:@"xray_version"]);
                CHECK("ping-options/enabled-spoof-snapshot",!spoof || [[captured objectForKey:@"xray_version"] isEqual:@"26.6.27"]);
            }
        }
    }
    CHECK("network/all-callbacks-drained",!queuedCount[0] && !queuedCount[1]);
    FINISH("ping network coordinator"); [pool drain]; return 0;
}
