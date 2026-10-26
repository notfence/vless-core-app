#import <Foundation/Foundation.h>
#include "check.h"
enum { UIApplicationStateActive=0,UIApplicationStateBackground=2 };
static NSInteger applicationState;
@interface UIApplication : NSObject
+ (id)sharedApplication;
- (NSInteger)applicationState;
@end
@implementation UIApplication
+ (id)sharedApplication { static id value; if (!value) value=[[self alloc] init]; return value; }
- (NSInteger)applicationState { return applicationState; }
@end
@interface MainVC : NSObject {
@public BOOL _mainScreenVisible,_periodicUIActive,_connected,_showingTerminal,_pingNetworkDirty;
    NSTimer *_uptimeTimer,*_logTimer,*_pingNetworkTimer;
    NSUInteger _logReadGeneration,uptime,logs,status;
    BOOL _logReadPending;
    NSTimeInterval _connectedSince;
}
- (BOOL)isMainUIActive;
- (void)updatePeriodicUIActivity;
- (void)refreshUptimeText;
- (void)refreshLogs;
- (void)reconcileConnectionStateWithDaemon;
- (void)refreshLogsTick:(id)timer;
@end
@implementation MainVC
- (void)refreshUptimeText { uptime++; }
- (void)refreshLogs { logs++; }
- (void)reconcileConnectionStateWithDaemon { status++; }
- (void)refreshLogsTick:(id)timer { (void)timer; }
- (void)dealloc { [_uptimeTimer invalidate]; [_uptimeTimer release]; [_logTimer invalidate]; [_logTimer release]; [_pingNetworkTimer invalidate]; [_pingNetworkTimer release]; [super dealloc]; }
#include "main_lifecycle.inc"
@end
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MainVC *vc=[[[MainVC alloc] init] autorelease];
    CHECK("lifecycle/coordinator-implemented",[vc respondsToSelector:@selector(updatePeriodicUIActivity)]);
    vc->_connected=YES; vc->_connectedSince=1234; vc->_mainScreenVisible=YES;
    [vc updatePeriodicUIActivity]; CHECK("lifecycle/visible-connected-timer",vc->_uptimeTimer!=nil && vc->uptime==1);
    NSTimer *first=vc->_uptimeTimer;
    for (NSUInteger i=0;i<100;i++) [vc updatePeriodicUIActivity];
    CHECK("lifecycle/one-timer",vc->_uptimeTimer==first && vc->uptime==1);
    [vc uptimeTick:nil]; CHECK("lifecycle/visible-uptime-and-status",vc->uptime==2 && vc->status==1);
    vc->_showingTerminal=YES; [vc updatePeriodicUIActivity]; CHECK("lifecycle/log-consumer-timer",vc->_logTimer!=nil && vc->logs==1);
    vc->_mainScreenVisible=NO; [vc updatePeriodicUIActivity];
    CHECK("lifecycle/hidden-stops-ui-not-vpn",!vc->_uptimeTimer && !vc->_logTimer && vc->_connected && vc->_connectedSince==1234);
    for (NSUInteger i=0;i<1000;i++) [vc uptimeTick:nil];
    CHECK("lifecycle/late-timer-callbacks-ignored",vc->uptime==2 && vc->status==1);
    vc->_mainScreenVisible=YES; [vc updatePeriodicUIActivity];
    CHECK("lifecycle/return-resumes-consumers",vc->_uptimeTimer && vc->_logTimer && vc->uptime==3 && vc->logs==2);
    applicationState=UIApplicationStateBackground;
    [vc applicationDidEnterBackgroundNotification:nil];
    CHECK("lifecycle/background-stops-periodic-ui",!vc->_uptimeTimer && !vc->_logTimer && !vc->_periodicUIActive && vc->_pingNetworkDirty);
    applicationState=UIApplicationStateActive; [vc updatePeriodicUIActivity];
    CHECK("lifecycle/foreground-resumes-without-losing-session",vc->_uptimeTimer && vc->_logTimer && vc->_connectedSince==1234);
    vc->_connected=NO; vc->_showingTerminal=NO; [vc updatePeriodicUIActivity];
    CHECK("lifecycle/no-consumers-no-timers",!vc->_uptimeTimer && !vc->_logTimer);
    FINISH("main lifecycle"); [pool drain]; return 0;
}
