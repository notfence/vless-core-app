#import "subscription_task.h"
#import "app_constants.h"
#include <errno.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#include <pthread.h>
static mach_timebase_info_data_t taskTimebase;
static pthread_once_t taskClockOnce=PTHREAD_ONCE_INIT;
static void taskClockInit(void) { mach_timebase_info(&taskTimebase); }
#else
#include <time.h>
#endif

double VCSubscriptionMonotonicTime(void) {
#ifdef __APPLE__
    pthread_once(&taskClockOnce,taskClockInit);
    return (double)mach_absolute_time()*taskTimebase.numer/taskTimebase.denom/1e9;
#else
    struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
    return now.tv_sec+now.tv_nsec/1e9;
#endif
}

VCSubscriptionTask *VCCurrentSubscriptionTask(void) {
    return [[[NSThread currentThread] threadDictionary] objectForKey:@"VCSubscriptionTask"];
}

VCSubscriptionTask *VCSetCurrentSubscriptionTask(VCSubscriptionTask *task) {
    NSMutableDictionary *dictionary=[[NSThread currentThread] threadDictionary];
    VCSubscriptionTask *previous=[[[dictionary objectForKey:@"VCSubscriptionTask"] retain] autorelease];
    if (task) [dictionary setObject:task forKey:@"VCSubscriptionTask"];
    else [dictionary removeObjectForKey:@"VCSubscriptionTask"];
    return previous;
}

@implementation VCSubscriptionTask

- (id)initWithPreserveNames:(BOOL)preserve observer:(id)observer selector:(SEL)selector {
    return [self initWithPreserveNames:preserve kind:VCSubscriptionTaskProfiles observer:observer selector:selector];
}
- (id)initWithPreserveNames:(BOOL)preserve kind:(VCSubscriptionTaskKind)kind observer:(id)observer selector:(SEL)selector {
    if ((self=[super init])) {
        _lock=[[NSLock alloc] init]; _kind=kind; _preserveNames=preserve; _observer=observer; _selector=selector;
        _phase=[@"Downloading" copy]; _metadata=[[NSMutableDictionary alloc] init];
    }
    return self;
}
- (VCSubscriptionTaskKind)kind { return _kind; }
- (void)dealloc { [_lock release]; [_reason release]; [_phase release]; [_metadata release]; [super dealloc]; }
- (BOOL)preserveCustomSubscriptionNames { return _preserveNames; }
- (NSTimeInterval)subscriptionUpdateTimestamp { return [NSDate timeIntervalSinceReferenceDate]+NSTimeIntervalSince1970; }
- (BOOL)cancelWithReason:(NSString *)reason {
    [_lock lock]; BOOL allowed=!_committing && !_finished;
    if (allowed && !_cancelled) { _cancelled=YES; _reason=[reason copy]; }
    [_lock unlock]; return allowed;
}
- (BOOL)isCancelled { [_lock lock]; BOOL value=_cancelled; [_lock unlock]; return value; }
- (NSString *)cancellationReason { [_lock lock]; NSString *value=[[_reason retain] autorelease]; [_lock unlock]; return value ?: (_kind == VCSubscriptionTaskUpdate ? @"Subscription update cancelled" : @"Import cancelled"); }
- (BOOL)beginCommit {
    [_lock lock]; BOOL allowed=!_cancelled && !_finished && !_committing;
    if (allowed) { _committing=YES; [_phase release]; _phase=[@"Saving" copy]; }
    [_lock unlock]; return allowed;
}
- (BOOL)isCommitting { [_lock lock]; BOOL value=_committing; [_lock unlock]; return value; }
- (void)finish { [_lock lock]; _finished=YES; _observer=nil; [_lock unlock]; }
- (void)notifyProgress {
    double now=VCSubscriptionMonotonicTime();
    [_lock lock];
    id observer=nil; SEL selector=_selector;
    if (!_finished && !_cancelled && !_notificationPending && _observer && now-_lastNotification >= .1) {
        observer=[_observer retain]; _notificationPending=YES; _lastNotification=now;
    }
    [_lock unlock];
    if (observer) { [observer performSelectorOnMainThread:selector withObject:self waitUntilDone:NO]; [observer release]; }
}
- (void)setPhase:(NSString *)phase {
    [_lock lock];
    if (![_phase isEqualToString:phase]) { _processed=0; _total=0; }
    [_phase release]; _phase=[phase copy]; [_lock unlock]; [self notifyProgress];
}
- (void)processed:(NSUInteger)processed total:(NSUInteger)total {
    [_lock lock]; _processed=processed; _total=total;
    [_lock unlock]; [self notifyProgress];
}
- (void)addAccepted:(NSUInteger)accepted skipped:(NSUInteger)skipped { [_lock lock]; _accepted+=accepted; _skipped+=skipped; [_lock unlock]; }
- (void)recordDuplicate { [_lock lock]; _duplicates++; [_lock unlock]; }
- (NSDictionary *)consumeProgress {
    [_lock lock]; _notificationPending=NO;
    BOOL determinate=[_phase isEqualToString:@"Processing"] && _total > 0 && !_cancelled;
    double fraction=determinate ? MIN(1.0,(double)_processed/(double)_total) : 0.0;
    NSDictionary *result=@{@"phase":_cancelled ? @"Stopping" : _phase,@"processed":@(_processed),@"total":@(_total),@"accepted":@(_accepted),@"skipped":@(_skipped),@"duplicates":@(_duplicates),@"determinate":@(determinate),@"fraction":@(fraction),@"stoppable":@(!_cancelled && !_committing && !_finished)};
    [_lock unlock]; return result;
}
- (void)profileMetadataPrepared:(NSDictionary *)metadata {
    if (![metadata count]) return;
    [_lock lock]; if (!_cancelled && !_finished) [_metadata addEntriesFromDictionary:metadata]; [_lock unlock];
}
- (NSDictionary *)takePreparedMetadata {
    [_lock lock]; NSDictionary *result=[_metadata autorelease]; _metadata=nil; [_lock unlock]; return result;
}
- (NSDictionary *)preparedMetadataForURI:(NSString *)uri {
    [_lock lock]; NSDictionary *result=[[[_metadata objectForKey:uri] retain] autorelease]; [_lock unlock]; return result;
}
@end

BOOL VCWaitSubscriptionProcess(pid_t pid, int *status, const char *bodyPath, NSUInteger maximumBytes, double timeout, VCSubscriptionTask *task, NSString **error) {
    if (pid <= 0) { if (error) *error=@"Invalid subscription download process"; return NO; }
    double deadline=VCSubscriptionMonotonicTime()+timeout;
    if (error) *error=nil;
    for (;;) {
        pid_t result=waitpid(pid,status,WNOHANG);
        int waitError=errno;
        if (result == pid) return YES;
        NSString *failure=nil;
        if (result < 0 && waitError != EINTR) failure=@"Unable to wait for subscription download";
        if (task.isCancelled) failure=task.cancellationReason;
        if (!failure && VCSubscriptionMonotonicTime() >= deadline) failure=@"vless-core-curl timed out";
        struct stat st;
        if (!failure && bodyPath && lstat(bodyPath,&st) == 0 && S_ISREG(st.st_mode) && st.st_size >= 0 && (uint64_t)st.st_size > maximumBytes) failure=@"Subscription response exceeds 32 MiB";
        if (failure) {
            if (result >= 0 || waitError != ECHILD) { kill(pid,SIGKILL); while (waitpid(pid,status,0) < 0 && errno == EINTR) {} }
            if (error) *error=failure;
            return NO;
        }
        usleep(50000);
    }
}

@interface VCSubscriptionRequestReceiver : NSObject <NSURLConnectionDataDelegate> {
@public
    NSMutableData *body;
    NSURLResponse *response;
    NSError *error;
    BOOL finished;
}
@end

@implementation VCSubscriptionRequestReceiver
- (id)init { if ((self=[super init])) body=[[NSMutableData alloc] init]; return self; }
- (void)dealloc { [body release]; [response release]; [error release]; [super dealloc]; }
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)value {
    [response release]; response=[value retain]; [body setLength:0];
    if (value.expectedContentLength > (long long)kVCMaximumSubscriptionBytes) {
        error=[[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:@{NSLocalizedDescriptionKey:@"Subscription response exceeds 32 MiB"}] retain];
        finished=YES; [connection cancel];
    }
}
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)value {
    if ([value length] > kVCMaximumSubscriptionBytes-[body length]) {
        [error release]; error=[[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorDataLengthExceedsMaximum userInfo:@{NSLocalizedDescriptionKey:@"Subscription response exceeds 32 MiB"}] retain];
        finished=YES; [connection cancel]; return;
    }
    [body appendData:value];
}
- (void)connectionDidFinishLoading:(NSURLConnection *)connection { (void)connection; finished=YES; }
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)value { (void)connection; [error release]; error=[value retain]; finished=YES; }
@end

NSData *VCFetchSubscriptionRequest(NSURLRequest *request, double timeout, NSURLResponse **response, NSError **error) {
    VCSubscriptionTask *task=VCCurrentSubscriptionTask();
    VCSubscriptionRequestReceiver *receiver=[[VCSubscriptionRequestReceiver alloc] init];
    NSURLConnection *connection=[[NSURLConnection alloc] initWithRequest:request delegate:receiver startImmediately:NO];
    if (!connection) {
        if (response) *response=nil;
        if (error) *error=[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnknown userInfo:@{NSLocalizedDescriptionKey:@"Unable to start subscription download"}];
        [receiver release]; return nil;
    }
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    if (!task.isCancelled) [connection start];
    double deadline=VCSubscriptionMonotonicTime()+timeout;
    while (!receiver->finished && !task.isCancelled && VCSubscriptionMonotonicTime() < deadline) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.05]];
        [pool drain];
    }
    if (!receiver->finished || task.isCancelled) {
        [connection cancel]; [receiver->error release];
        receiver->error=[[NSError errorWithDomain:NSURLErrorDomain code:task.isCancelled ? NSURLErrorCancelled : NSURLErrorTimedOut
                                       userInfo:@{NSLocalizedDescriptionKey:task.isCancelled ? task.cancellationReason : @"Subscription request timed out"}] retain];
    }
    if (response) *response=[[receiver->response retain] autorelease];
    if (error) *error=[[receiver->error retain] autorelease];
    NSData *result=receiver->error ? nil : [[receiver->body retain] autorelease];
    [connection cancel]; [connection release]; [receiver release]; return result;
}

NSData *VCReadSubscriptionFile(NSString *path, NSString **error) {
    if (error) *error=nil;
    VCSubscriptionTask *task=VCCurrentSubscriptionTask();
    if (task.isCancelled) { if (error) *error=task.cancellationReason; return nil; }
    int fd=open([path fileSystemRepresentation],O_RDONLY|O_NONBLOCK);
    if (fd < 0) { if (error) *error=@"Unable to read import file"; return nil; }
    struct stat st;
    if (fstat(fd,&st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 || (uint64_t)st.st_size > kVCMaximumSubscriptionBytes) {
        close(fd); if (error) *error=@"Import file is invalid or exceeds 32 MiB"; return nil;
    }
    NSMutableData *data=[NSMutableData data];
    unsigned char buffer[16384];
    for (;;) {
        if (task.isCancelled) { close(fd); if (error) *error=task.cancellationReason; return nil; }
        ssize_t count=read(fd,buffer,sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count < 0 || (count > 0 && (NSUInteger)count > kVCMaximumSubscriptionBytes-[data length])) {
            close(fd); if (error) *error=@"Unable to read import file within 32 MiB"; return nil;
        }
        if (!count) break;
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(fd); return data;
}
