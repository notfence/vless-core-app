#import "../common/connection_logic.h"
#include "check.h"
#include <sys/socket.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <unistd.h>
#include <pthread.h>

static unsigned killed;
static pid_t lastKilled, waitResult;
static int waitError;
static int wrongSignal, cancelOnWait, waitEntered;
static pthread_mutex_t waitLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t waitCondition = PTHREAD_COND_INITIALIZER;

int __wrap_kill(pid_t pid, int signal) {
    if (signal != SIGTERM) wrongSignal = 1;
    killed++;
    lastKilled = pid;
    return 0;
}

int __real_select(int, fd_set *, fd_set *, fd_set *, struct timeval *);
int __wrap_select(int count, fd_set *readable, fd_set *writable, fd_set *errors, struct timeval *timeout) {
    if (cancelOnWait) {
        pthread_mutex_lock(&waitLock);
        waitEntered = 1;
        pthread_cond_signal(&waitCondition);
        pthread_mutex_unlock(&waitLock);
    }
    return __real_select(count, readable, writable, errors, timeout);
}

pid_t __wrap_waitpid(pid_t pid, int *status, int options) {
    (void)pid;
    CHECK("ping/poll-is-nonblocking", status == NULL && options == WNOHANG);
    errno = waitError;
    return waitResult;
}

@interface VCPingTestOwner : NSObject {
    VCPingCancellation *ping;
    NSUInteger stopped;
}
@property(nonatomic, retain) VCPingCancellation *ping;
@property(nonatomic) NSUInteger stopped;
- (void)pingWorker:(id)payload;
- (void)stopAllPings;
@end
@implementation VCPingTestOwner
@synthesize ping, stopped;
- (void)dealloc { [ping release]; [super dealloc]; }
- (void)pingWorker:(id)payload { (void)payload; }
- (void)stopAllPings { stopped++; [ping cancel]; }
@end

static void *cancelWhileWaiting(void *opaque) {
    pthread_mutex_lock(&waitLock);
    while (!waitEntered) pthread_cond_wait(&waitCondition, &waitLock);
    pthread_mutex_unlock(&waitLock);
    [(VCPingCancellation *)opaque cancel];
    return NULL;
}

int main(void) {
    alarm(5);
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VCPingCancellation *cancellation = [[[VCPingCancellation alloc] init] autorelease];
    CHECK("ping/new-operation-not-cancelled", ![cancellation isCancelled]);
    int sockets[2];
    CHECK("ping/local-socketpair", socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    CHECK("ping/socket-registered", [cancellation registerSocket:sockets[0]]);
    char byte = 'x';
    CHECK("ping/readable-socket", write(sockets[1], &byte, 1) == 1 && VCWaitForPingSocket(sockets[0], NO, 50, cancellation) > 0);
    CHECK("ping/consume-ready-data", read(sockets[0], &byte, 1) == 1);
    CHECK("ping/wait-times-out", VCWaitForPingSocket(sockets[0], NO, 1, cancellation) == 0);
    [cancellation registerChild:12345];
    pthread_t thread;
    cancelOnWait = 1;
    CHECK("ping/concurrent-cancel-thread", pthread_create(&thread, NULL, cancelWhileWaiting, cancellation) == 0);
    CHECK("ping/cancellation-unblocks-socket-wait", VCWaitForPingSocket(sockets[0], NO, 1000, cancellation) == -1);
    CHECK("ping/cancel-thread-finished", pthread_join(thread, NULL) == 0);
    cancelOnWait = 0;
    CHECK("ping/child-cancelled", [cancellation isCancelled] && killed == 1 && lastKilled == 12345);
    CHECK("ping/child-stopped-with-sigterm", !wrongSignal);
    CHECK("ping/socket-shutdown", read(sockets[1], &byte, 1) == 0);
    VCClosePingSocket(sockets[0], cancellation);
    close(sockets[1]);
    CHECK("ping/registered-socket-closed", fcntl(sockets[0], F_GETFD) == -1 && errno == EBADF);
    CHECK("ping/late-local-socketpair", socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == 0);
    CHECK("ping/register-after-cancel-closes-socket", ![cancellation registerSocket:sockets[0]] && fcntl(sockets[0], F_GETFD) == -1 && errno == EBADF);
    close(sockets[1]);
    [cancellation registerChild:54321];
    CHECK("ping/register-after-cancel-stops-child", killed == 2 && lastKilled == 54321);
    waitResult = 54321;
    CHECK("ping/terminated-child-reaped", [cancellation pollChild:54321] == 54321);
    [cancellation cancel];
    CHECK("ping/reaped-child-not-signalled-again", killed == 2);
    [cancellation registerChild:54321];
    waitResult = -1; waitError = ECHILD;
    CHECK("ping/already-reaped-child", [cancellation pollChild:54321] == -1);
    unsigned before = killed;
    [cancellation cancel];
    CHECK("ping/missing-child-not-signalled-again", killed == before);
    [cancellation registerChild:54321];
    [cancellation forgetChild:54321]; before = killed;
    [cancellation cancel];
    CHECK("ping/forgotten-child-not-signalled-again", killed == before);
    cancellation = [[[VCPingCancellation alloc] init] autorelease];
    VCPingTestOwner *owner = [[[VCPingTestOwner alloc] init] autorelease];
    VCPingOperation *operation = [[[VCPingOperation alloc] initWithTarget:owner payload:@{} cancellation:cancellation] autorelease];
    [operation cancel];
    CHECK("ping/queue-cancel-propagates-to-worker", [operation isCancelled] && [cancellation isCancelled]);
    NSString *record = @"2026-10-05 I [probe] v=1 id=2 success=1 stage=none dns_ms=3 tcp_ms=4 transport_ms=5 protocol_ms=6 carry_ms=7 total_ms=25\n";
    NSDictionary *report = VCProbeReportFromLog(record);
    CHECK("ping/parse-real-core-report", [[report objectForKey:@"id"] intValue] == 2 && [[report objectForKey:@"carry_ms"] intValue] == 7);
    CHECK("ping/ignore-partially-written-record", VCProbeReportFromLog([record stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]) == nil);
    CHECK("ping/ignore-unstructured-helper-log", VCProbeReportFromLog(@"connection failed\n") == nil && VCProbeReportFromLog(nil) == nil);
    NSArray *malformed = @[
        [record stringByReplacingOccurrencesOfString:@"v=1" withString:@"v=4294967297"],
        [record stringByReplacingOccurrencesOfString:@"success=1" withString:@"success=4294967297"],
        [record stringByReplacingOccurrencesOfString:@"success=1" withString:@"success=0"],
        [record stringByReplacingOccurrencesOfString:@"stage=none" withString:@"stage=unknown"],
        [record stringByReplacingOccurrencesOfString:@"dns_ms=3" withString:@"dns_ms=-2"],
        [record stringByReplacingOccurrencesOfString:@"tcp_ms=4" withString:@"tcp_ms=nan"],
        [record stringByReplacingOccurrencesOfString:@"total_ms=25" withString:@"total_ms=-1"],
        [record stringByReplacingOccurrencesOfString:@"id=2" withString:@"id=0"],
        [record stringByReplacingOccurrencesOfString:@"id=2" withString:@"id=999999999999999999999999"],
        [record stringByReplacingOccurrencesOfString:@"\n" withString:@" uri=secret\n"],
        [record stringByReplacingOccurrencesOfString:@"\n" withString:@" id=3\n"]
    ];
    for (NSString *invalid in malformed) CHECK("ping/reject-malformed-or-ambiguous-report", VCProbeReportFromLog(invalid) == nil);
    NSString *failed = [record stringByReplacingOccurrencesOfString:@"success=1 stage=none" withString:@"success=0 stage=transport"];
    report = VCProbeReportFromLog([record stringByAppendingString:failed]);
    CHECK("ping/latest-complete-attempt-wins", ![[report objectForKey:@"success"] boolValue] && [[report objectForKey:@"stage"] isEqual:@"transport"]);
    CHECK("ping/failure-stage-visible-and-red", [VCProbeFailureDisplay(report) isEqual:@"Transport"] && VCPingDisplayIsFailure(VCProbeFailureDisplay(report)));
    for (NSString *stage in @[@"dns", @"tcp", @"transport", @"protocol", @"carry"])
        CHECK("ping/every-failed-stage-has-a-label", VCPingDisplayIsFailure(VCProbeFailureDisplay(@{@"stage":stage})));
    CHECK("ping/legacy-helper-falls-back-without-guessing", [VCProbeFailureDisplay(nil) isEqual:@"Failed"] && [VCProbeSummary(nil) isEqual:@"details=unavailable"]);
    CHECK("ping/latency-and-loading-not-errors", !VCPingDisplayIsFailure(@"15 ms") && !VCPingDisplayIsFailure(@"...") && !VCPingDisplayIsFailure(nil));
    NSMutableDictionary *mutableReport = [NSMutableDictionary dictionaryWithDictionary:report];
    cancellation.diagnosticReport = mutableReport;
    [mutableReport setObject:@"dns" forKey:@"stage"];
    CHECK("ping/report-is-an-immutable-snapshot", [[cancellation.diagnosticReport objectForKey:@"stage"] isEqual:@"transport"]);
    CHECK("ping/summary-contains-measured-stages", [VCProbeSummary(report) rangeOfString:@"transport_ms=5"].location != NSNotFound);
    CHECK("ping/summary-never-contains-private-extra-fields", [VCProbeSummary(@{@"stage":@"tcp", @"uri":@"secret", @"password":@"secret"}) rangeOfString:@"secret"].location == NSNotFound);
    CHECK("ping/accept-result-from-current-network", VCPingResultIsCurrent(3,3));
    CHECK("ping/reject-result-from-old-network", !VCPingResultIsCurrent(2,3));
    NSString *network = nil;
    NSUInteger generation = 0;
    NSMutableDictionary *displays = [NSMutableDictionary dictionary];
    owner.ping = [[[VCPingCancellation alloc] init] autorelease];
    CHECK("ping/initial-network-does-not-cancel-work", !VCPingUpdateNetwork(owner,@"wifi-a",&network,&generation,displays) && generation == 1 && owner.stopped == 0);
    [displays setObject:@"17 ms" forKey:@"vless-core"];
    CHECK("ping/same-network-preserves-results", !VCPingUpdateNetwork(owner,@"wifi-a",&network,&generation,displays) && [displays count] == 1 && ![owner.ping isCancelled]);
    NSUInteger measuredGeneration = generation;
    CHECK("ping/network-change-cancels-real-operation", VCPingUpdateNetwork(owner,@"wifi-b",&network,&generation,displays) && owner.stopped == 1 && [owner.ping isCancelled]);
    CHECK("ping/network-change-clears-old-displays", [displays count] == 0 && !VCPingResultIsCurrent(measuredGeneration,generation));
    CHECK("ping/unknown-network-does-not-invent-change", !VCPingUpdateNetwork(owner,nil,&network,&generation,displays) && owner.stopped == 1);
    [network release];
    FINISH("ping cancellation");
    alarm(0);
    [pool drain];
    return 0;
}
