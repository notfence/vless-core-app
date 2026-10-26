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
#include <sys/stat.h>

@implementation VCStatusCoordinator
- (id)initWithCommand:(NSString *(*)(NSString *))command {
    if ((self = [super init])) {
        _condition = [[NSCondition alloc] init];
        _command = command;
    }
    return self;
}
- (void)dealloc {
    [_condition release];
    [_response release];
    [super dealloc];
}
- (NSString *)readStatus {
    [_condition lock];
    if (_inFlight) {
        NSUInteger generation = _generation;
        while (_inFlight && generation == _generation) [_condition wait];
        NSString *response = [_response retain];
        [_condition unlock];
        return [response autorelease];
    }
    _inFlight = YES;
    [_condition unlock];
    NSString *response = nil;
    @try {
        response = _command ? [_command(@"STATUS\n") copy] : nil;
    } @finally {
        [_condition lock];
        [_response release];
        _response = [response retain];
        _generation++;
        _inFlight = NO;
        [_condition broadcast];
        [_condition unlock];
    }
    return [response autorelease];
}
@end

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
@synthesize cancellation = _cancellation;
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

@implementation VCPingBatch
@synthesize options = _options, pending = _pending, operations = _operations, previousDisplays = _previousDisplays;
- (id)initWithURIs:(NSArray *)uris options:(NSDictionary *)options cancellation:(VCPingCancellation *)cancellation {
    self = [super init];
    if (self) {
        _pending = [[NSMutableSet alloc] init];
        NSMutableArray *ordered = [[NSMutableArray alloc] init];
        for (id uri in uris) {
            if ([cancellation isCancelled]) {
                [ordered release];
                [self release];
                return nil;
            }
            if (![uri isKindOfClass:[NSString class]] || ![uri length] || [_pending containsObject:uri]) continue;
            [_pending addObject:uri];
            [ordered addObject:uri];
        }
        _uris = ordered;
        _options = [options copy];
        _operations = [[NSMutableArray alloc] initWithCapacity:4];
        _previousDisplays = [[NSMutableDictionary alloc] initWithCapacity:4];
    }
    return self;
}
- (NSString *)nextURI {
    return _cursor < [_uris count] ? [_uris objectAtIndex:_cursor++] : nil;
}
- (void)dealloc {
    [_uris release];
    [_options release];
    [_pending release];
    [_operations release];
    [_previousDisplays release];
    [super dealloc];
}
@end

@implementation VCProbeLogReader
- (id)initWithFileDescriptor:(int)descriptor {
    if ((self = [super init])) {
        _descriptor = descriptor;
        _pending = [[NSMutableData alloc] init];
    }
    return self;
}
- (NSDictionary *)readReportAfterID:(long long)identifier {
    struct stat state;
    if (_descriptor < 0 || fstat(_descriptor, &state) != 0 || state.st_size < 0) return nil;
    if (_offset > state.st_size || state.st_size - _offset > 65536) {
        _offset = state.st_size > 65536 ? state.st_size - 65536 : 0;
        [_pending setLength:0];
        [_latest release]; _latest = nil;
    }
    NSUInteger interruptions = 0;
    while (_offset < state.st_size) {
        unsigned char bytes[4096];
        size_t requested = (size_t)MIN((off_t)sizeof(bytes), state.st_size - _offset);
        ssize_t count = pread(_descriptor, bytes, requested, _offset);
        if (count < 0 && errno == EINTR && ++interruptions < 8) continue;
        if (count <= 0) break;
        _offset += count;
        if ([_pending length] > 65536 - (NSUInteger)count)
            [_pending replaceBytesInRange:NSMakeRange(0, [_pending length] - (65536 - count)) withBytes:NULL length:0];
        [_pending appendBytes:bytes length:count];
        const unsigned char *data = [_pending bytes];
        NSUInteger length = [_pending length], consumed = 0;
        while (consumed < length) {
            const unsigned char *newline = memchr(data + consumed, '\n', length - consumed);
            if (!newline) break;
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSUInteger end = (NSUInteger)(newline - data) + 1;
            NSString *line = [[NSString alloc] initWithBytes:data + consumed length:end - consumed encoding:NSUTF8StringEncoding];
            NSDictionary *report = VCProbeReportFromLog(line);
            if (report) { [_latest release]; _latest = [report retain]; }
            [line release];
            [pool drain];
            consumed = end;
        }
        if (consumed) [_pending replaceBytesInRange:NSMakeRange(0, consumed) withBytes:NULL length:0];
    }
    return [[_latest objectForKey:@"id"] longLongValue] > identifier ? _latest : nil;
}
- (void)dealloc { [_pending release]; [_latest release]; [super dealloc]; }
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
