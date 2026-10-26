#import <Foundation/Foundation.h>
#import "../common/connection_logic.h"
#ifdef __APPLE__
#include <Block.h>
#else
#include "support/objc/blocks_runtime.h"
#endif
#include "check.h"

#ifndef DISPATCH_QUEUE_PRIORITY_DEFAULT
#define DISPATCH_QUEUE_PRIORITY_DEFAULT 0
#endif
#define dispatch_get_global_queue VCStatusTestGlobalQueue
#define dispatch_get_main_queue VCStatusTestMainQueue
#define dispatch_async VCStatusTestEnqueue
static void (^queued[2][32])(void);
static NSUInteger queuedCount[2],requests,events;
static NSString *response=@"OK disconnected\n";
static int dispatch_get_global_queue(int priority,int flags) { (void)priority; (void)flags; return 0; }
static int dispatch_get_main_queue(void) { return 1; }
static void dispatch_async(int queue,void (^block)(void)) {
    CHECK("status/bounded-queue",queuedCount[queue]<32);
    queued[queue][queuedCount[queue]++]=Block_copy(block);
}
static void runOne(int queue) {
    CHECK("status/expected-callback",queuedCount[queue]>0);
    void (^block)(void)=queued[queue][0];
    memmove(queued[queue],queued[queue]+1,--queuedCount[queue]*sizeof(block));
    block(); Block_release(block);
}
static NSString *VCReadDaemonStatus(void) { requests++; return response; }
static void VCRecordAppEvent(id category,id action,id detail) { (void)category; (void)action; (void)detail; events++; }

@interface MainVC : NSObject {
@public
    BOOL _daemonStatusCheckInFlight,_didQueryInitialDaemonStatus,_connectionActionInProgress,_reconnectInProgress;
    BOOL _connected,_connectedWithProtectedLogs,active,lastOK;
    NSUInteger _connectionActionGeneration,buttons,starts,stops;
    NSTimeInterval _connectedSince;
    NSString *_pendingReconnectURI,*lastStatus;
}
- (void)queryInitialStatus;
@end
@implementation MainVC
- (id)init { if ((self=[super init])) active=YES; return self; }
- (void)dealloc { [_pendingReconnectURI release]; [lastStatus release]; [super dealloc]; }
- (BOOL)isMainUIActive { return active; }
- (id)sanitizeDaemonText:(id)text { return text; }
- (void)showStatus:(id)text ok:(BOOL)ok { [lastStatus release]; lastStatus=[text copy]; lastOK=ok; }
- (void)updateConnectButton { buttons++; }
- (void)startUptimeTimerWithDaemonResponse:(NSString *)text { starts++; _connectedSince=VCConnectedSince(text,[[NSDate date] timeIntervalSince1970]); }
- (void)stopUptimeTimer { stops++; _connectedSince=0; }
#include "main_status.inc"
@end

static void query(MainVC *vc) { [vc queryInitialStatus]; runOne(0); runOne(1); }

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MainVC *vc=[[[MainVC alloc] init] autorelease];
    [vc queryInitialStatus];
    CHECK("status/asynchronous",requests==0 && vc->_daemonStatusCheckInFlight);
    for (NSUInteger i=0;i<50;i++) [vc queryInitialStatus];
    CHECK("status/one-flight",queuedCount[0]==1);
    runOne(0); runOne(1);
    CHECK("status/initial-ready",vc->_didQueryInitialDaemonStatus && [vc->lastStatus isEqual:@"Ready"] && !vc->_connected);
    [vc showStatus:@"Subscriptions updated: synthetic counts" ok:YES];
    NSUInteger previousEvents=events,previousButtons=vc->buttons;
    query(vc);
    CHECK("status/unchanged-disconnected-feedback-preserved",[vc->lastStatus isEqual:@"Subscriptions updated: synthetic counts"]);
    CHECK("status/unchanged-disconnected-no-extra-events",events==previousEvents && vc->buttons==previousButtons);
    response=@"OK connected since=100 socks=1080 protected=1\n";
    query(vc);
    CHECK("status/new-connection-applied",vc->_connected && vc->_connectedWithProtectedLogs && vc->_connectedSince==100 && [vc->lastStatus isEqual:@"Connected"]);
    [vc showStatus:@"Selected synthetic profile" ok:YES];
    previousEvents=events; previousButtons=vc->buttons;
    query(vc);
    CHECK("status/unchanged-connected-feedback-preserved",[vc->lastStatus isEqual:@"Selected synthetic profile"] && events==previousEvents && vc->buttons==previousButtons);
    response=@"ERR daemon timeout\n";
    query(vc);
    CHECK("status/failure-does-not-clear-live-protected-session",vc->_connected && vc->_connectedWithProtectedLogs && vc->_connectedSince==100 && [vc->lastStatus isEqual:@"Selected synthetic profile"]);
    response=@"OK disconnected\n";
    query(vc);
    CHECK("status/confirmed-loss-applied",!vc->_connected && !vc->_connectedWithProtectedLogs && vc->_connectedSince==0 && [vc->lastStatus isEqual:@"Connection lost"]);
    [vc queryInitialStatus]; runOne(0); vc->_connectionActionGeneration++; runOne(1);
    CHECK("status/stale-generation-ignored",!vc->_connected && [vc->lastStatus isEqual:@"Connection lost"]);
    [vc queryInitialStatus]; runOne(0); vc->_connectionActionInProgress=YES; runOne(1);
    CHECK("status/active-action-ignored",!vc->_connected && [vc->lastStatus isEqual:@"Connection lost"]);
    vc->_connectionActionInProgress=NO;
    MainVC *hidden=[[[MainVC alloc] init] autorelease]; hidden->active=NO;
    query(hidden);
    CHECK("status/hidden-initial-is-not-applied",!hidden->_didQueryInitialDaemonStatus && !hidden->_daemonStatusCheckInFlight);
    hidden->active=YES; query(hidden);
    CHECK("status/return-applies-initial-ready",hidden->_didQueryInitialDaemonStatus && [hidden->lastStatus isEqual:@"Ready"]);
    MainVC *failed=[[[MainVC alloc] init] autorelease]; response=@"ERR unavailable\n";
    query(failed);
    CHECK("status/initial-failure-is-not-ready",!failed->_didQueryInitialDaemonStatus && !failed->lastOK && [failed->lastStatus isEqual:response]);
    response=@"OK disconnected\n"; query(failed);
    CHECK("status/initial-failure-recovers",failed->_didQueryInitialDaemonStatus && [failed->lastStatus isEqual:@"Ready"]);
    CHECK("status/queues-drained",!queuedCount[0] && !queuedCount[1]);
    FINISH("main status refresh"); [pool drain]; return 0;
}
