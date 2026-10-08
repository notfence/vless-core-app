#import "connection_logic.h"
#include <sys/socket.h>
#include <sys/select.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>

NSDictionary *VCProbeReportFromLog(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return nil;
    NSArray *numericKeys = @[@"v", @"id", @"success", @"dns_ms", @"tcp_ms", @"transport_ms", @"protocol_ms", @"carry_ms", @"total_ms"];
    NSSet *stages = [NSSet setWithObjects:@"none", @"dns", @"tcp", @"transport", @"protocol", @"carry", nil];
    NSDictionary *latest = nil;
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    for (NSUInteger index = 0; index + 1 < [lines count]; index++) {
        NSString *line = [lines objectAtIndex:index];
        NSRange marker = [line rangeOfString:@"[probe] "];
        if (marker.location == NSNotFound) continue;
        NSString *body = [line substringFromIndex:NSMaxRange(marker)];
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        BOOL valid = YES;
        for (NSString *field in [body componentsSeparatedByString:@" "]) {
            NSArray *parts = [field componentsSeparatedByString:@"="];
            if ([parts count] != 2) { valid = NO; break; }
            NSString *key = [parts objectAtIndex:0], *value = [parts objectAtIndex:1];
            if ([report objectForKey:key]) { valid = NO; break; }
            if ([key isEqualToString:@"stage"]) {
                if (![stages containsObject:value]) { valid = NO; break; }
                [report setObject:value forKey:key];
            } else {
                if (![numericKeys containsObject:key] || [value length] == 0) { valid = NO; break; }
                const char *number = [value UTF8String];
                if (!number || strlen(number) != [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]) { valid = NO; break; }
                char *end = NULL;
                int savedErrno = errno;
                errno = 0;
                long long parsed = strtoll(number, &end, 10);
                BOOL parsedOK = errno == 0 && end != number && *end == '\0';
                errno = savedErrno;
                if (!parsedOK || parsed < ([key hasSuffix:@"_ms"] && ![key isEqualToString:@"total_ms"] ? -1 : 0)) { valid = NO; break; }
                [report setObject:[NSNumber numberWithLongLong:parsed] forKey:key];
            }
        }
        if (!valid || [report count] != 10 || [[report objectForKey:@"v"] longLongValue] != 1 ||
            [[report objectForKey:@"id"] longLongValue] == 0 || [[report objectForKey:@"success"] longLongValue] > 1) continue;
        BOOL success = [[report objectForKey:@"success"] boolValue];
        if (success != [[report objectForKey:@"stage"] isEqualToString:@"none"]) continue;
        latest = report;
    }
    return latest;
}

NSString *VCProbeFailureDisplay(NSDictionary *report) {
    if (![report isKindOfClass:[NSDictionary class]]) return @"Failed";
    NSDictionary *labels = @{@"dns":@"DNS", @"tcp":@"TCP", @"transport":@"Transport", @"protocol":@"Protocol", @"carry":@"Response"};
    NSString *stage = [report objectForKey:@"stage"];
    NSString *label = [stage isKindOfClass:[NSString class]] ? [labels objectForKey:stage] : nil;
    return label ? label : @"Failed";
}

BOOL VCPingDisplayIsFailure(NSString *display) {
    return [[NSSet setWithObjects:@"Failed", @"DNS", @"TCP", @"Transport", @"Protocol", @"Response", nil] containsObject:display ? display : @""];
}

NSString *VCProbeSummary(NSDictionary *report) {
    if (![report isKindOfClass:[NSDictionary class]]) return @"details=unavailable";
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *key in @[@"id", @"success", @"stage", @"dns_ms", @"tcp_ms", @"transport_ms", @"protocol_ms", @"carry_ms", @"total_ms"]) {
        id value = [report objectForKey:key];
        BOOL knownStage = [key isEqualToString:@"stage"] && [[NSSet setWithObjects:@"none", @"dns", @"tcp", @"transport", @"protocol", @"carry", nil] containsObject:value ? value : @""];
        if ([value isKindOfClass:[NSNumber class]] || knownStage)
            [fields addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
    }
    return [fields componentsJoinedByString:@" "];
}

BOOL VCPingResultIsCurrent(NSUInteger expectedGeneration, NSUInteger generation) {
    return expectedGeneration == generation;
}

BOOL VCPingUpdateNetwork(id owner, NSString *signature, NSString **storedSignature, NSUInteger *generation, NSMutableDictionary *displays) {
    if (!signature || !storedSignature || !generation) return NO;
    BOOL changed = *storedSignature && ![*storedSignature isEqualToString:signature];
    if (!*storedSignature || changed) {
        NSString *copy = [signature copy];
        [*storedSignature release];
        *storedSignature = copy;
        ++*generation;
    }
    if (changed) {
        [owner performSelector:NSSelectorFromString(@"stopAllPings")];
        [displays removeAllObjects];
    }
    return changed;
}

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
    [_diagnosticReport release];
    [_lock release];
    [super dealloc];
}
- (NSDictionary *)diagnosticReport {
    [_lock lock];
    NSDictionary *report = [_diagnosticReport retain];
    [_lock unlock];
    return [report autorelease];
}
- (void)setDiagnosticReport:(NSDictionary *)report {
    NSDictionary *copy = [report copy];
    [_lock lock];
    [_diagnosticReport release];
    _diagnosticReport = copy;
    [_lock unlock];
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
