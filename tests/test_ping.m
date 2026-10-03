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

@interface VCPingTestOwner : NSObject
- (void)pingWorker:(id)payload;
@end
@implementation VCPingTestOwner
- (void)pingWorker:(id)payload { (void)payload; }
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
    FINISH("ping cancellation");
    alarm(0);
    [pool drain];
    return 0;
}
