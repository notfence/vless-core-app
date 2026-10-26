#import <Foundation/Foundation.h>
#import "../common/connection_logic.h"
#include "support/objc/blocks_runtime.h"
#include "check.h"
typedef NSUInteger dispatch_once_t;
typedef int dispatch_queue_t;
enum { DISPATCH_QUEUE_SERIAL=0,UIApplicationStateActive=0 };
typedef struct { double x,y; } CGPoint;
static const CGPoint CGPointZero={0,0};
static void (^queued[2][128])(void);
static NSUInteger queuedCount[2],sent,displayed;
static BOOL busy,protectedLogs;
static NSMutableArray *commands;
static dispatch_queue_t dispatch_queue_create(const char *label,int mode) { (void)label; (void)mode; return 0; }
static int dispatch_get_main_queue(void) { return 1; }
static void dispatch_once(dispatch_once_t *once,void (^block)(void)) { if (!*once) { *once=1; block(); } }
static void dispatch_async(int queue,void (^block)(void)) { CHECK("logs/bounded-test-queue",queuedCount[queue]<128); queued[queue][queuedCount[queue]++]=Block_copy(block); }
static void runOne(int queue) { CHECK("logs/expected-callback",queuedCount[queue]>0); void (^block)(void)=queued[queue][0]; memmove(queued[queue],queued[queue]+1,--queuedCount[queue]*sizeof(block)); block(); Block_release(block); }
static void dispatch_sync(int queue,void (^block)(void)) { while (queuedCount[queue]) runOne(queue); block(); }
static NSString *SendCommand(NSString *command) { sent++; [commands addObject:command]; return @"OK\nlatest log\n"; }
static void VCSendCommandAsync(NSString *,void (^)(NSString *));
static void VCWaitForDaemonUICommands(void);
#include "daemon_async.inc"
#include "log_text.inc"
#include "log_async.inc"
static void VCRecordAppEvent(id a,id b,id c) { (void)a; (void)b; (void)c; }
@interface UIApplication : NSObject
+ (id)sharedApplication;
- (NSInteger)applicationState;
@end
@implementation UIApplication
+ (id)sharedApplication { static id value; if (!value) value=[[self alloc] init]; return value; }
- (NSInteger)applicationState { return UIApplicationStateActive; }
@end
@interface LogView : NSObject {
@public BOOL tracking,dragging,decelerating; NSRange selectedRange; CGPoint contentOffset;
}
@property BOOL tracking,dragging,decelerating;
@property NSRange selectedRange;
@property CGPoint contentOffset;
@end
@implementation LogView
@synthesize tracking,dragging,decelerating,selectedRange,contentOffset;
@end
@interface UIButton : NSObject
@property NSInteger tag;
@end
@interface MainVC : NSObject {
@public BOOL _showingTerminal,_connectedWithProtectedLogs,_logReadInFlight,_logReadPending,_logClearInFlight;
    BOOL _connected,_connectionActionInProgress;
    NSUInteger _logReadGeneration,_connectionActionGeneration;
    NSInteger _activeLogIndex;
    NSTimeInterval _connectedSince;
    LogView *_logView;
    NSString *_logTexts[2],*lastText;
    CGPoint _logContentOffsets[2]; BOOL _logContentOffsetsValid[2],_logFollowsTail[2];
}
- (BOOL)isConnectionActionInProgress;
- (BOOL)selectedSubscriptionIsHappEncrypted;
- (void)refreshLogs;
- (void)requestLogRefresh;
- (void)forceRefreshLogs;
- (double)maximumLogOffsetY;
- (void)displayLogText:(NSString *)text atIndex:(NSInteger)index offset:(CGPoint)offset followTail:(BOOL)tail;
@end
@implementation MainVC
- (id)init { if ((self=[super init])) { _showingTerminal=YES; _logView=[[LogView alloc] init]; } return self; }
- (void)dealloc { [_logView release]; [lastText release]; [_logTexts[0] release]; [_logTexts[1] release]; [super dealloc]; }
- (BOOL)isConnectionActionInProgress { return busy || _connectionActionInProgress; }
- (BOOL)isMainUIActive { return YES; }
- (BOOL)selectedSubscriptionIsHappEncrypted { return protectedLogs; }
- (double)maximumLogOffsetY { return 100; }
- (void)displayLogText:(NSString *)text atIndex:(NSInteger)index offset:(CGPoint)offset followTail:(BOOL)tail { (void)offset; (void)tail; displayed++; [lastText release]; lastText=[text copy]; [_logTexts[index] release]; _logTexts[index]=[text copy]; }
- (void)rememberActiveLogPosition {}
- (void)updateLogSelectorAnimated:(BOOL)animated { (void)animated; }
- (void)showStatus:(id)text ok:(BOOL)ok { (void)text; (void)ok; }
- (id)sanitizeDaemonText:(id)text { return text; }
- (id)uriForCurrentSelection { return @"synthetic"; }
- (void)updateConnectButton {}
- (void)stopUptimeTimer { _connectedSince=0; }
#include "main_logs.inc"
#include "main_health_async.inc"
@end
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; commands=[[NSMutableArray alloc] init];
    MainVC *vc=[[[MainVC alloc] init] autorelease];
    CHECK("logs/async-implemented",[vc respondsToSelector:@selector(requestLogRefresh)]);
    [vc refreshLogs]; CHECK("logs/no-ipc-on-caller",sent==0 && vc->_logReadInFlight);
    for (NSUInteger i=0;i<100;i++) [vc refreshLogs];
    CHECK("logs/one-active-coalesced",queuedCount[0]==1);
    runOne(0); CHECK("logs/result-on-main",displayed==0); runOne(1);
    CHECK("logs/published",[vc->lastText isEqual:@"latest log\n"]);
    CHECK("logs/one-followup",queuedCount[0]==1);
    runOne(0); runOne(1); CHECK("logs/unchanged-not-redrawn",displayed==1);
    [vc refreshLogs]; runOne(0); vc->_showingTerminal=NO; vc->_logReadGeneration++; runOne(1);
    CHECK("logs/closed-screen-drops-result",displayed==1 && !vc->_logReadInFlight);
    vc->_showingTerminal=YES; [vc refreshLogs]; runOne(0); vc->_activeLogIndex=1; vc->_logReadGeneration++; [vc refreshLogs]; runOne(1);
    CHECK("logs/stale-source-followup",displayed==1 && queuedCount[0]==1); runOne(0); runOne(1);
    CHECK("logs/current-source",[commands.lastObject isEqual:@"LOG\tcore\n"] && displayed==2);
    [vc refreshLogs]; runOne(0); protectedLogs=YES; runOne(1);
    CHECK("logs/protected-result-not-shown",displayed==2); protectedLogs=NO;
    vc->_logView->selectedRange=NSMakeRange(0,1); [vc refreshLogs]; CHECK("logs/selection-skips",queuedCount[0]==0); vc->_logView->selectedRange=NSMakeRange(0,0);
    busy=YES; [vc refreshLogs]; CHECK("logs/busy-skips",queuedCount[0]==0); busy=NO;
    [vc clearLogsPressed]; [vc clearLogsPressed]; CHECK("logs/clear-not-synchronous-or-duplicated",queuedCount[0]==1 && vc->_logClearInFlight);
    runOne(0); runOne(1); CHECK("logs/clear-orders-before-read",[commands.lastObject isEqual:@"CLEAR_LOGS\n"] && queuedCount[0]==1);
    runOne(0); runOne(1); CHECK("logs/clear-finished",!vc->_logClearInFlight);
    VCSendCommandAsync(@"CLEAR_LOGS\n",nil); VCWaitForDaemonUICommands();
    CHECK("logs/background-fence",[commands.lastObject isEqual:@"CLEAR_LOGS\n"] && queuedCount[0]==0);
    vc->_connected=YES; vc->_connectedSince=1000; vc->_connectionActionGeneration=1;
    NSDictionary *failure=@{@"ok":@"0",@"uri":@"synthetic",@"generation":@1,@"since":@1000,@"reason":@"TOFU pin mismatch"};
    NSUInteger before=sent;
    [vc xhttpConnectHealthCheckResultOnMain:failure];
    CHECK("health/disconnect-not-on-main",sent==before && vc->_connectionActionInProgress && queuedCount[0]==1);
    [vc xhttpConnectHealthCheckResultOnMain:failure]; CHECK("health/stale-result-not-repeated",queuedCount[0]==1);
    runOne(0); CHECK("health/disconnect-awaits-completion",vc->_connected && [commands.lastObject isEqual:@"DISCONNECT\n"]); runOne(1);
    CHECK("health/disconnected-after-confirmation",!vc->_connected && !vc->_connectionActionInProgress && vc->_connectedSince==0);
    vc->_connected=YES; vc->_connectedSince=1000; vc->_connectionActionGeneration=1;
    [vc xhttpConnectHealthCheckResultOnMain:failure]; runOne(0); vc->_connectionActionGeneration++; runOne(1);
    CHECK("health/late-completion-cannot-change-new-action",vc->_connected && vc->_connectionActionInProgress);
    FINISH("async main logs"); [commands release]; [pool drain]; return 0;
}
