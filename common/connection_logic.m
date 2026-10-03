#import "connection_logic.h"
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>

@implementation VCPingCancellation
@synthesize previousDisplay = _previousDisplay;
- (id)init {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        _socket = -1;
    }
    return self;
}
- (void)dealloc {
    [_previousDisplay release];
    [_lock release];
    [super dealloc];
}
- (BOOL)isCancelled {
    [_lock lock];
    BOOL cancelled = _cancelled;
    [_lock unlock];
    return cancelled;
}
- (void)cancel {
    [_lock lock];
    _cancelled = YES;
    if (_socket >= 0) shutdown(_socket, SHUT_RDWR);
    if (_child > 0) kill(_child, SIGTERM);
    [_lock unlock];
}
- (BOOL)registerSocket:(int)fd {
    [_lock lock];
    BOOL accepted = !_cancelled;
    if (accepted) _socket = fd;
    [_lock unlock];
    if (!accepted) close(fd);
    return accepted;
}
- (void)closeSocket:(int)fd {
    [_lock lock];
    if (_socket == fd) _socket = -1;
    close(fd);
    [_lock unlock];
}
- (void)registerChild:(pid_t)pid {
    [_lock lock];
    _child = pid;
    if (_cancelled) kill(pid, SIGTERM);
    [_lock unlock];
}
- (pid_t)pollChild:(pid_t)pid {
    [_lock lock];
    pid_t result = waitpid(pid, NULL, WNOHANG);
    if (result == pid || (result < 0 && errno == ECHILD)) _child = 0;
    [_lock unlock];
    return result;
}
- (void)forgetChild:(pid_t)pid {
    [_lock lock];
    if (_child == pid) _child = 0;
    [_lock unlock];
}
@end

@implementation VCPingOperation
- (id)initWithTarget:(id)target payload:(NSDictionary *)payload cancellation:(VCPingCancellation *)cancellation {
    self = [super initWithTarget:target selector:@selector(pingWorker:) object:payload];
    if (self) _cancellation = [cancellation retain];
    return self;
}
- (void)cancel {
    [_cancellation cancel];
    [super cancel];
}
- (void)dealloc {
    [_cancellation release];
    [super dealloc];
}
@end

void VCClosePingSocket(int fd, VCPingCancellation *cancellation) {
    if (cancellation) [cancellation closeSocket:fd];
    else close(fd);
}

int VCWaitForPingSocket(int fd, BOOL writable, int timeout_ms, VCPingCancellation *cancellation) {
    struct timeval start, now;
    gettimeofday(&start, NULL);
    int remaining = timeout_ms;
    while (remaining > 0 && ![cancellation isCancelled]) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        int slice = cancellation ? MIN(remaining, 100) : remaining;
        struct timeval timeout = {slice / 1000, (slice % 1000) * 1000};
        int result = select(fd + 1, writable ? NULL : &fds, writable ? &fds : NULL, NULL, &timeout);
        if ([cancellation isCancelled]) return -1;
        if (result > 0) return result;
        if (result < 0 && errno != EINTR) return -1;
        gettimeofday(&now, NULL);
        remaining = timeout_ms - (int)((now.tv_sec - start.tv_sec) * 1000L +
                                     (now.tv_usec - start.tv_usec) / 1000L);
    }
    return 0;
}

BOOL VCConnectionActionInProgress(BOOL action, BOOL reconnect, BOOL pending) { return action || reconnect || pending; }
VCConnectionGate VCConnectionToggleGate(BOOL refresh, BOOL action, BOOL reconnect) {
    if (refresh || action) return VCConnectionGateBusy;
    if (reconnect) return VCConnectionGateSwitching;
    return VCConnectionGateAllowed;
}
BOOL VCConfigurationSelectionBlocked(BOOL action, BOOL connected, BOOL refresh) { return action || (connected && refresh); }
BOOL VCConfigSwitchNeeded(BOOL connected, id oldURI, id newURI, BOOL oldProtected, BOOL newProtected) {
    if (!connected) return NO;
    if (![oldURI isKindOfClass:[NSString class]] || ![newURI isKindOfClass:[NSString class]]) return NO;
    if ([oldURI length] == 0 || [newURI length] == 0) return NO;
    if ([oldURI isEqualToString:newURI] && oldProtected == newProtected) return NO;
    return YES;
}
void VCConnectionTouchDown(id target, BOOL connectionButton) {
    if (connectionButton) [target performSelector:NSSelectorFromString(@"stopAllPings")];
}
NSTimeInterval VCConnectedSince(NSString *response, NSTimeInterval now) {
    NSTimeInterval since;
    since = now;
    for (NSString *field in [response componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
        if (![field hasPrefix:@"since="]) continue;
        NSScanner *scanner = [NSScanner scannerWithString:[field substringFromIndex:6]];
        long long timestamp = 0;
        if ([scanner scanLongLong:&timestamp] && [scanner isAtEnd] &&
            timestamp > 0 && timestamp <= since) {
            since = (NSTimeInterval)timestamp;
        }
        break;
    }
    return since;
}

NSString *VCFormatDuration(NSTimeInterval seconds) {
    NSInteger total = (NSInteger)(seconds >= 0 ? seconds : 0);
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)h, (long)m, (long)s];
}

BOOL VCConnectionLossApplies(BOOL disconnected, BOOL connected, NSUInteger expectedGeneration, NSUInteger generation, BOOL action, NSTimeInterval expectedSince, NSTimeInterval since) {
    return disconnected && connected && expectedGeneration == generation && !action && expectedSince == since;
}
