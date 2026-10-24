#import "../common/profile_logic.h"
#import "../common/secure_store.h"
#import "../common/subscription_task.h"
#import "../common/list_logic.h"
#include "check.h"
#include <time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>

@interface VCBulkSubscriptions : NSArray { @public NSArray *items; NSUInteger counts; }
@end
@implementation VCBulkSubscriptions
- (NSUInteger)count { counts++; return [items count]; }
- (id)objectAtIndex:(NSUInteger)index { return [items objectAtIndex:index]; }
@end

@interface VCBulkProgress : NSObject { @public NSMutableArray *times; }
- (void)progress:(VCSubscriptionTask *)task;
@end
@implementation VCBulkProgress
- (id)init { if ((self=[super init])) times=[[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [times release]; [super dealloc]; }
- (void)progress:(VCSubscriptionTask *)task { CHECK("bulk/progress-on-main",[NSThread isMainThread]); [task consumeProgress]; [times addObject:@(VCSubscriptionMonotonicTime())]; }
@end

@interface VCCancellingProfiles : VCProfileLogic { @public NSUInteger reads; }
@end
@implementation VCCancellingProfiles
- (NSDictionary *)metadataForURI:(NSString *)uri {
    if (++reads == 37) [VCCurrentSubscriptionTask() cancelWithReason:@"Controlled cancellation"];
    return [super metadataForURI:uri];
}
@end

@interface VCSlowBulkProfiles : VCProfileLogic
@end
@implementation VCSlowBulkProfiles
- (NSDictionary *)metadataForURI:(NSString *)uri {
    usleep(2000);
    return [super metadataForURI:uri];
}
@end

@interface VCBulkParseWorker : NSObject {
@public VCSubscriptionTask *task; NSString *text; NSDictionary *report; BOOL done;
}
- (void)parse;
- (void)finished;
@end
@implementation VCBulkParseWorker
- (void)dealloc { [task release]; [text release]; [report release]; [super dealloc]; }
- (void)parse {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    VCSubscriptionTask *previous=[VCSetCurrentSubscriptionTask(task) retain];
    VCSlowBulkProfiles *profiles=[[VCSlowBulkProfiles alloc] init];
    report=[[profiles subscriptionImportReportFromData:[text dataUsingEncoding:NSUTF8StringEncoding]] retain];
    [profiles release]; VCSetCurrentSubscriptionTask(previous); [previous release];
    [self performSelectorOnMainThread:@selector(finished) withObject:nil waitUntilDone:NO];
    [pool drain];
}
- (void)finished { done=YES; }
@end

static NSUInteger stoppedRequests;
@interface VCBulkURLProtocol : NSURLProtocol
@end
@implementation VCBulkURLProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [[[request URL] scheme] isEqual:@"vc-bulk"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSString *host=[[[self request] URL] host];
    if ([host isEqual:@"slow"]) return;
    NSURLResponse *response=[[[NSURLResponse alloc] initWithURL:[[self request] URL] MIMEType:@"text/plain" expectedContentLength:[host isEqual:@"large"] ? 33554433 : 3 textEncodingName:nil] autorelease];
    [[self client] URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    if ([host isEqual:@"large"]) return;
    unsigned char bytes[]={0,0,42};
    [[self client] URLProtocol:self didLoadData:[NSData dataWithBytes:bytes length:sizeof(bytes)]];
    [[self client] URLProtocolDidFinishLoading:self];
}
- (void)stopLoading { stoppedRequests++; }
@end

@interface VCBulkCancelTimer : NSObject
- (void)cancel:(NSTimer *)timer;
@end
@implementation VCBulkCancelTimer
- (void)cancel:(NSTimer *)timer { [(VCSubscriptionTask *)[timer userInfo] cancelWithReason:@"Download cancelled"]; }
@end

@interface VCBulkProcessWait : NSObject {
@public pid_t pid; VCSubscriptionTask *task; BOOL done,success; NSString *error; int status;
}
- (void)waitForChild;
- (void)finished;
@end
@implementation VCBulkProcessWait
- (void)dealloc { [task release]; [error release]; [super dealloc]; }
- (void)waitForChild {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init]; NSString *reason=nil;
    success=VCWaitSubscriptionProcess(pid,&status,NULL,33554432,2,task,&reason); error=[reason copy];
    [self performSelectorOnMainThread:@selector(finished) withObject:nil waitUntilDone:NO]; [pool drain];
}
- (void)finished { done=YES; }
@end

static void taskTests(NSString *text) {
    VCBulkProgress *observer=[[VCBulkProgress alloc] init];
    VCSubscriptionTask *task=[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:observer selector:@selector(progress:)];
    CHECK("bulk/task-presentation-kind",[task respondsToSelector:@selector(kind)]);
    CHECK("bulk/default-task-is-profile-import",task.kind == VCSubscriptionTaskProfiles);
    CHECK("bulk/task-options-snapshot",task.preserveCustomSubscriptionNames && fabs(task.subscriptionUpdateTimestamp-[[NSDate date] timeIntervalSince1970]) < 2);
    VCSubscriptionTask *previous=[VCSetCurrentSubscriptionTask(task) retain];
    CHECK("bulk/task-thread-binding",VCCurrentSubscriptionTask() == task);
    VCCancellingProfiles *profiles=[[VCCancellingProfiles alloc] init];
    NSDictionary *report=[profiles subscriptionImportReportFromData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("bulk/cancel-between-records",profiles->reads == 37 && [[report objectForKey:@"uris"] count] == 0 && [[report objectForKey:@"error"] isEqual:@"Controlled cancellation"]);
    CHECK("bulk/cancel-prevents-commit",![task beginCommit]);
    VCSetCurrentSubscriptionTask(previous); [previous release];
    CHECK("bulk/task-binding-restored",VCCurrentSubscriptionTask() == nil);
    [task finish]; [task release]; [profiles release];
    VCBulkParseWorker *parser=[[VCBulkParseWorker alloc] init];
    parser->task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL]; parser->text=[text copy];
    NSOperationQueue *parseQueue=[[NSOperationQueue alloc] init];
    NSInvocationOperation *parseOperation=[[NSInvocationOperation alloc] initWithTarget:parser selector:@selector(parse) object:nil];
    [parseQueue addOperation:parseOperation]; [parseOperation release];
    NSUInteger parseHeartbeat=0;
    for (NSUInteger i=0;i<5;i++) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]]; parseHeartbeat++; }
    CHECK("bulk/main-progresses-during-slow-parse",parseHeartbeat == 5 && !parser->done);
    [parser->task cancelWithReason:@"Background parse cancelled"];
    double parseDeadline=VCSubscriptionMonotonicTime()+3;
    while (!parser->done && VCSubscriptionMonotonicTime() < parseDeadline) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    CHECK("bulk/slow-parse-cancels-without-partial-output",parser->done && [[parser->report objectForKey:@"uris"] count] == 0 && [[parser->report objectForKey:@"error"] isEqual:@"Background parse cancelled"]);
    [parseQueue waitUntilAllOperationsAreFinished]; [parseQueue release]; [parser release];
    task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:observer selector:@selector(progress:)];
    for (NSUInteger i=0;i<1000;i++) [task processed:i total:1000];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.12]];
    [task processed:1000 total:1000];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    CHECK("bulk/progress-coalesced",[observer->times count] <= 3);
    if ([observer->times count] > 1) CHECK("bulk/progress-throttled",[[observer->times lastObject] doubleValue]-[[observer->times objectAtIndex:[observer->times count]-2] doubleValue] >= .09);
    [task profileMetadataPrepared:@{@"fixture":@{@"host":@"example.test"}}];
    NSDictionary *metadata=[task takePreparedMetadata];
    CHECK("bulk/task-metadata-transferred",[metadata count] == 1 && [task takePreparedMetadata] == nil);
    CHECK("bulk/task-commit-gate",[task beginCommit] && ![task cancelWithReason:@"too late"]);
    [task finish]; CHECK("bulk/task-finished-not-cancellable",![task cancelWithReason:@"too late"]);
    [task release]; [observer release];
    for (NSInteger kind=VCSubscriptionTaskProfiles;kind<=VCSubscriptionTaskUpdate;kind++) {
        task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO kind:(VCSubscriptionTaskKind)kind observer:nil selector:NULL];
        NSString *reason=kind == VCSubscriptionTaskUpdate ? @"Subscription update cancelled" : @"Import cancelled";
        CHECK("bulk/cancel-reason-matches-operation",[task.cancellationReason isEqual:reason]);
        CHECK("bulk/default-cancel-reason-matches-operation",[task cancelWithReason:nil] && task.isCancelled && [task.cancellationReason isEqual:reason]);
        [task cancelWithReason:@"Later cancellation"];
        CHECK("bulk/first-cancel-reason-is-preserved",[task.cancellationReason isEqual:reason]);
        [task finish]; [task release];
        task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO kind:(VCSubscriptionTaskKind)kind observer:nil selector:NULL];
        [task cancelWithReason:@"Explicit cancellation"];
        CHECK("bulk/explicit-cancel-reason-is-preserved",[task.cancellationReason isEqual:@"Explicit cancellation"]);
        [task finish]; [task release];
    }
    for (NSInteger kind=VCSubscriptionTaskProfiles;kind<=VCSubscriptionTaskUpdate;kind++) {
        task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO kind:(VCSubscriptionTaskKind)kind observer:nil selector:NULL];
        NSDictionary *progress=[task consumeProgress];
        CHECK("bulk/progress-kind-preserved",task.kind == kind && [progress objectForKey:@"shows_notice"] == nil);
        CHECK("bulk/download-has-no-fake-percentage",![[progress objectForKey:@"determinate"] boolValue] && [[progress objectForKey:@"fraction"] doubleValue] == 0 && [[progress objectForKey:@"stoppable"] boolValue]);
        [task setPhase:@"Processing"]; [task processed:25 total:100]; progress=[task consumeProgress];
        CHECK("bulk/processing-fraction",[[progress objectForKey:@"determinate"] boolValue] && [[progress objectForKey:@"fraction"] doubleValue] == .25);
        [task processed:500 total:100];
        CHECK("bulk/processing-fraction-clamped",[[[task consumeProgress] objectForKey:@"fraction"] doubleValue] == 1);
        [task processed:0 total:0];
        CHECK("bulk/unknown-count-is-indeterminate",![[[task consumeProgress] objectForKey:@"determinate"] boolValue]);
        [task processed:25 total:100]; [task setPhase:@"Downloading"]; progress=[task consumeProgress];
        CHECK("bulk/new-stage-clears-old-counts",[[progress objectForKey:@"processed"] unsignedIntegerValue] == 0 && [[progress objectForKey:@"total"] unsignedIntegerValue] == 0);
        [task addAccepted:3 skipped:2]; [task recordDuplicate]; [task recordDuplicate];
        CHECK("bulk/progress-keeps-result-counts",[[[task consumeProgress] objectForKey:@"accepted"] unsignedIntegerValue] == 3 && [[[task consumeProgress] objectForKey:@"skipped"] unsignedIntegerValue] == 2 && [[[task consumeProgress] objectForKey:@"duplicates"] unsignedIntegerValue] == 2);
        [task cancelWithReason:@"Stopped"]; progress=[task consumeProgress];
        CHECK("bulk/cancel-stops-refresh-button",![[progress objectForKey:@"stoppable"] boolValue] && [[progress objectForKey:@"phase"] isEqual:@"Stopping"] && ![[progress objectForKey:@"determinate"] boolValue] && ![task beginCommit]);
        [task finish];
        CHECK("bulk/finished-task-cannot-stop",![[[task consumeProgress] objectForKey:@"stoppable"] boolValue]);
        [task release];
        task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO kind:(VCSubscriptionTaskKind)kind observer:nil selector:NULL];
        CHECK("bulk/progress-commit-begins",[task beginCommit]); progress=[task consumeProgress];
        CHECK("bulk/saving-cannot-be-stopped",[[progress objectForKey:@"phase"] isEqual:@"Saving"] && ![[progress objectForKey:@"stoppable"] boolValue] && ![[progress objectForKey:@"determinate"] boolValue] && ![task cancelWithReason:@"Late stop"]);
        [task finish]; [task release];
    }
    VCBulkProcessWait *wait=[[VCBulkProcessWait alloc] init];
    wait->task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL];
    wait->pid=fork(); CHECK("bulk/download-child-created",wait->pid >= 0);
    if (!wait->pid) { for (;;) pause(); }
    NSOperationQueue *queue=[[NSOperationQueue alloc] init];
    NSInvocationOperation *operation=[[NSInvocationOperation alloc] initWithTarget:wait selector:@selector(waitForChild) object:nil];
    [queue addOperation:operation]; [operation release];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];
    CHECK("bulk/main-progresses-during-download",!wait->done);
    [wait->task cancelWithReason:@"Download cancelled"];
    double deadline=VCSubscriptionMonotonicTime()+3;
    while (!wait->done && VCSubscriptionMonotonicTime() < deadline) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    CHECK("bulk/download-cancelled",wait->done && !wait->success && [wait->error isEqual:@"Download cancelled"]);
    int status=0; CHECK("bulk/download-child-reaped",waitpid(wait->pid,&status,WNOHANG) == -1 && errno == ECHILD);
    [queue release]; [wait release];
    CHECK("bulk/foundation-protocol-registered",[NSURLProtocol registerClass:[VCBulkURLProtocol class]]);
    NSError *error=nil; NSURLResponse *response=nil;
    NSURLRequest *request=[NSURLRequest requestWithURL:[NSURL URLWithString:@"vc-bulk://good"]];
    NSData *data=VCFetchSubscriptionRequest(request,1,&response,&error);
    unsigned char bytes[]={0,0,42};
    CHECK("bulk/foundation-download",data && !error && [data isEqual:[NSData dataWithBytes:bytes length:3]]);
    request=[NSURLRequest requestWithURL:[NSURL URLWithString:@"vc-bulk://large"]];
    CHECK("bulk/foundation-size-limit",VCFetchSubscriptionRequest(request,1,&response,&error) == nil && error.code == NSURLErrorDataLengthExceedsMaximum);
    task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL];
    previous=[VCSetCurrentSubscriptionTask(task) retain];
    VCBulkCancelTimer *timerTarget=[[VCBulkCancelTimer alloc] init];
    [NSTimer scheduledTimerWithTimeInterval:.02 target:timerTarget selector:@selector(cancel:) userInfo:task repeats:NO];
    request=[NSURLRequest requestWithURL:[NSURL URLWithString:@"vc-bulk://slow"]];
    CHECK("bulk/foundation-cancel",VCFetchSubscriptionRequest(request,1,&response,&error) == nil && error.code == NSURLErrorCancelled);
    CHECK("bulk/foundation-stopped",stoppedRequests > 0);
    VCSetCurrentSubscriptionTask(previous); [previous release]; [timerTarget release]; [task finish]; [task release];
    [NSURLProtocol unregisterClass:[VCBulkURLProtocol class]];
    task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL];
    previous=[VCSetCurrentSubscriptionTask(task) retain];
    report=[VCProfiles() subscriptionImportReportFromData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("bulk/retry-after-cancellation",[[report objectForKey:@"uris"] count] == 2000 && ![report objectForKey:@"error"]);
    VCSetCurrentSubscriptionTask(previous); [previous release]; [task finish]; [task release];
    char file[]="/tmp/vless-bulk-file-XXXXXX";
    int fd=mkstemp(file); CHECK("bulk/import-file-created",fd >= 0);
    CHECK("bulk/import-file-written",write(fd,"fixture",7) == 7);
    NSString *reason=nil,*filePath=[NSString stringWithUTF8String:file];
    CHECK("bulk/import-file-read",[VCReadSubscriptionFile(filePath,&reason) isEqual:[@"fixture" dataUsingEncoding:NSUTF8StringEncoding]] && !reason);
    CHECK("bulk/import-file-sparse-limit",ftruncate(fd,33554433) == 0 && VCReadSubscriptionFile(filePath,&reason) == nil && reason != nil);
    close(fd);
    task=[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL];
    [task cancelWithReason:@"File cancelled"]; previous=[VCSetCurrentSubscriptionTask(task) retain];
    CHECK("bulk/import-file-cancelled",VCReadSubscriptionFile(filePath,&reason) == nil && [reason isEqual:@"File cancelled"]);
    VCSetCurrentSubscriptionTask(previous); [previous release]; [task release];
    CHECK("bulk/import-file-removed",unlink(file) == 0);
    CHECK("bulk/import-fifo-nonblocking",mkfifo(file,0600) == 0 && VCReadSubscriptionFile(filePath,&reason) == nil);
    CHECK("bulk/import-fifo-removed",unlink(file) == 0);
    pid_t child=fork(); CHECK("bulk/timeout-child-created",child >= 0);
    if (!child) for (;;) pause();
    CHECK("bulk/download-timeout",!VCWaitSubscriptionProcess(child,&status,NULL,33554432,.03,nil,&reason) && [reason isEqual:@"vless-core-curl timed out"]);
    CHECK("bulk/timeout-child-reaped",waitpid(child,&status,WNOHANG) == -1 && errno == ECHILD);
    CHECK("bulk/invalid-child-rejected",!VCWaitSubscriptionProcess(0,&status,NULL,33554432,.03,nil,&reason));
    NSString *headers=[NSString stringWithFormat:@"# Profile-title: First\n# Profile-title: base64:!!!\n# subscription-userinfo: upload=10; download=20; total=30\n# announce: Notice\n# profile-update-interval: 12\n# subscription-refill-date: 42\n%@",text];
    NSData *headerData=[headers dataUsingEncoding:NSUTF8StringEncoding];
    for (NSData *body in @[headerData,[[headerData base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding]]) {
        NSDictionary *parsed=[VCProfiles() subscriptionImportReportFromData:body];
        NSString *compact=[parsed objectForKey:@"metadata_text"];
        CHECK("bulk/metadata-title-compatible",[[VCProfiles() subscriptionTitleFromMetadataText:compact] isEqual:[VCProfiles() subscriptionTitleFromData:body]]);
        CHECK("bulk/metadata-traffic-compatible",[[VCProfiles() subscriptionUserInfoFromMetadataText:compact] isEqual:[VCProfiles() subscriptionUserInfoFromData:body]]);
        CHECK("bulk/metadata-fields-compatible",[[VCProfiles() subscriptionMetadataFromMetadataText:compact] isEqual:[VCProfiles() subscriptionMetadataFromData:body]]);
        CHECK("bulk/metadata-does-not-retain-profile-list",[compact length] < 1024 && [compact rangeOfString:@"vless://"].location == NSNotFound);
    }
}

static NSUInteger liveTemporaries, peakTemporaries, queryReads;
static NSCondition *storeCondition;
static BOOL holdStore, storeEntered, failProtection, storeUsedMain;

static NSString *storeCommand(NSString *command) {
    (void)command;
    return @"OK 0000000000000000000000000000000000000000000000000000000000000000";
}

static BOOL protectStore(NSString *path) {
    (void)path;
    [storeCondition lock];
    storeEntered=YES; storeUsedMain=[NSThread isMainThread]; [storeCondition broadcast];
    while (holdStore) [storeCondition wait];
    BOOL result=!failProtection; [storeCondition unlock]; return result;
}

@interface VCBulkStoreObserver : NSObject { @public NSMutableArray *results; }
- (void)finished:(NSDictionary *)result;
@end
@implementation VCBulkStoreObserver
- (id)init { if ((self=[super init])) results=[[NSMutableArray alloc] init]; return self; }
- (void)dealloc { [results release]; [super dealloc]; }
- (void)finished:(NSDictionary *)result { CHECK("bulk/store-completion-on-main",[NSThread isMainThread]); [results addObject:result]; }
@end

static void waitForStore(VCConfigurationStoreWriter *writer, VCBulkStoreObserver *observer, NSUInteger count) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    while ((!writer.isIdle || [observer->results count] < count) && [end timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.005]];
    CHECK("bulk/store-completes",writer.isIdle && [observer->results count] == count);
}

static void storeTests(void) {
    char path[]="/tmp/vless-bulk-store-XXXXXX";
    CHECK("bulk/store-temp-directory",mkdtemp(path) != NULL);
    NSString *directory=[NSString stringWithUTF8String:path],*file=[directory stringByAppendingPathComponent:@"configs.dat"];
    VCStoragePaths paths={directory,file,nil,storeCommand,protectStore};
    storeCondition=[[NSCondition alloc] init]; holdStore=YES; storeEntered=NO;
    VCConfigurationStoreWriter *writer=[[VCConfigurationStoreWriter alloc] initWithPaths:&paths];
    VCBulkStoreObserver *observer=[[VCBulkStoreObserver alloc] init];
    CHECK("bulk/store-first-enqueue",[writer enqueueConfigurations:@[@{@"uri":@"first"}] subscriptions:@[] revision:1 target:observer selector:@selector(finished:) context:@"first"]);
    [storeCondition lock]; NSDate *end=[NSDate dateWithTimeIntervalSinceNow:5];
    while (!storeEntered && [end timeIntervalSinceNow] > 0) [storeCondition waitUntilDate:end];
    BOOL entered=storeEntered; [storeCondition unlock];
    CHECK("bulk/store-worker-starts",entered);
    for (NSUInteger i=2;i<=101;i++) {
        CHECK("bulk/store-latest-enqueue",[writer enqueueConfigurations:@[@{@"uri":@(i)}] subscriptions:@[] revision:i target:observer selector:@selector(finished:) context:@"latest"]);
        CHECK("bulk/store-only-two-snapshots",writer.bufferedSnapshotCount <= 2);
    }
    CHECK("bulk/store-off-main",!storeUsedMain && [observer->results count] == 0);
    NSUInteger heartbeat=0;
    for (NSUInteger i=0;i<5;i++) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]]; heartbeat++; }
    CHECK("bulk/main-progresses-during-blocked-store",heartbeat == 5 && !writer.isIdle);
    [storeCondition lock]; holdStore=NO; [storeCondition broadcast]; [storeCondition unlock];
    waitForStore(writer,observer,2);
    CHECK("bulk/store-completion-order",[[[observer->results objectAtIndex:0] objectForKey:@"revision"] unsignedIntegerValue] == 1 && [[[observer->results objectAtIndex:1] objectForKey:@"revision"] unsignedIntegerValue] == 101);
    BOOL exists=NO; NSDictionary *loaded=VCLoadProtectedConfigurationDataAtPaths(&exists,&paths);
    CHECK("bulk/store-latest-data",exists && [[[[loaded objectForKey:@"configs"] objectAtIndex:0] objectForKey:@"uri"] unsignedIntegerValue] == 101);
    NSData *previous=[NSData dataWithContentsOfFile:file];
    failProtection=YES;
    CHECK("bulk/store-failure-enqueue",[writer enqueueConfigurations:@[] subscriptions:@[] revision:102 target:observer selector:@selector(finished:) context:@"failure"]);
    waitForStore(writer,observer,3);
    CHECK("bulk/store-failure-reported",![[[observer->results lastObject] objectForKey:@"saved"] boolValue]);
    CHECK("bulk/store-failure-preserves-file",[[NSData dataWithContentsOfFile:file] isEqual:previous]);
    CHECK("bulk/store-stale-revision-rejected",![writer enqueueConfigurations:@[] subscriptions:@[] revision:101 target:observer selector:@selector(finished:) context:nil]);
    failProtection=NO;
    CHECK("bulk/store-recovers",[writer enqueueConfigurations:@[] subscriptions:@[] revision:103 target:observer selector:@selector(finished:) context:nil]);
    waitForStore(writer,observer,4);
    CHECK("bulk/store-recovers-successfully",[[[observer->results lastObject] objectForKey:@"saved"] boolValue] && writer.bufferedSnapshotCount == 0);
    struct stat st; CHECK("bulk/store-keeps-private-permissions",stat([file fileSystemRepresentation],&st) == 0 && (st.st_mode & 0777) == 0600);
    [writer release]; [observer release]; [storeCondition release]; storeCondition=nil;
    CHECK("bulk/store-temp-cleanup",unlink([file fileSystemRepresentation]) == 0 && rmdir(path) == 0);
}

@interface VCBulkTemporary : NSObject
@end
@implementation VCBulkTemporary
- (id)init { if ((self=[super init])) { liveTemporaries++; if (liveTemporaries > peakTemporaries) peakTemporaries=liveTemporaries; } return self; }
- (void)dealloc { liveTemporaries--; [super dealloc]; }
@end

@interface VCBulkProfiles : VCProfileLogic
@end
@implementation VCBulkProfiles
- (NSDictionary *)metadataForURI:(NSString *)uri {
    [[[VCBulkTemporary alloc] init] autorelease];
    return [super metadataForURI:uri];
}
- (NSString *)queryValueForURLString:(NSString *)uri key:(NSString *)key {
    queryReads++;
    return [super queryValueForURLString:uri key:key];
}
@end

static double clockMS(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
    return now.tv_sec*1000.0+now.tv_nsec/1000000.0;
}

static void memory(unsigned long *current, unsigned long *peak) {
    FILE *file=fopen("/proc/self/status","r"); char line[256];
    *current=*peak=0;
    if (file) { while (fgets(line,sizeof(line),file)) { sscanf(line,"VmRSS: %lu",current); sscanf(line,"VmHWM: %lu",peak); } fclose(file); }
}

static int measure(NSString *path) {
    NSData *data=[[NSData alloc] initWithContentsOfFile:path];
    if (!data) return 2;
    VCProfileLogic *profiles=[[VCProfileLogic alloc] init];
    NSAutoreleasePool *work=[[NSAutoreleasePool alloc] init];
    double begin=clockMS();
    NSDictionary *report=[[profiles subscriptionImportReportFromData:data] retain];
    double parsed=clockMS()-begin;
    [work drain];
    work=[[NSAutoreleasePool alloc] init]; begin=clockMS();
    if ([profiles respondsToSelector:@selector(preparedMetadataForConfigurations:subscriptions:additionalMetadata:)])
        [profiles installPreparedMetadata:[profiles preparedMetadataForConfigurations:@[] subscriptions:@[@{@"items":[report objectForKey:@"uris"]}]
                                                                    additionalMetadata:[report objectForKey:@"metadata"]]];
    else [profiles prepareMetadataForConfigurations:@[] subscriptions:@[@{@"items":[report objectForKey:@"uris"]}]];
    double metadata=clockMS()-begin;
    [work drain];
    unsigned long rss,peak; memory(&rss,&peak);
    struct rusage usage; getrusage(RUSAGE_SELF,&usage);
    printf("{\"bytes\":%lu,\"accepted\":%lu,\"skipped\":%lu,\"parse_ms\":%.6f,\"metadata_ms\":%.6f,\"rss_kib\":%lu,\"peak_rss_kib\":%lu,\"cpu_s\":%.6f}\n",
           (unsigned long)[data length],(unsigned long)[[report objectForKey:@"uris"] count],
           (unsigned long)[[report objectForKey:@"skipped"] unsignedIntegerValue],parsed,metadata,rss,peak,
           usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1000000.0+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1000000.0);
    [report release]; [profiles release]; [data release]; return 0;
}

static int measureStore(NSString *source, BOOL background) {
    NSAutoreleasePool *parsePool=[[NSAutoreleasePool alloc] init];
    NSData *data=[NSData dataWithContentsOfFile:source];
    NSArray *uris=[[VCProfiles() parseSubscriptionData:data] retain];
    [parsePool drain];
    char path[]="/tmp/vless-measure-store-XXXXXX";
    if (!mkdtemp(path)) return 2;
    NSString *directory=[NSString stringWithUTF8String:path],*file=[directory stringByAppendingPathComponent:@"configs.dat"];
    VCStoragePaths paths={directory,file,nil,storeCommand,protectStore};
    storeCondition=[[NSCondition alloc] init];
    NSArray *subscriptions=@[@{@"url":@"https://subscription.test/fixture",@"items":uris}];
    VCBulkStoreObserver *observer=[[VCBulkStoreObserver alloc] init];
    VCConfigurationStoreWriter *writer=background ? [[VCConfigurationStoreWriter alloc] initWithPaths:&paths] : nil;
    struct rusage before,after; getrusage(RUSAGE_SELF,&before);
    double started=clockMS(),mainMS=0;
    BOOL ok;
    if (background) {
        ok=[writer enqueueConfigurations:@[] subscriptions:subscriptions revision:1 target:observer selector:@selector(finished:) context:nil];
        mainMS=clockMS()-started;
        waitForStore(writer,observer,1);
        ok=ok && [[[observer->results lastObject] objectForKey:@"saved"] boolValue];
    } else { ok=VCSaveProtectedConfigurationDataAtPaths(@[],subscriptions,&paths); mainMS=clockMS()-started; }
    double total=clockMS()-started;
    getrusage(RUSAGE_SELF,&after);
    BOOL exists=NO;
    NSDictionary *loaded=VCLoadProtectedConfigurationDataAtPaths(&exists,&paths);
    ok=ok && exists && [[loaded objectForKey:@"subscriptions"] isEqual:subscriptions];
    unsigned long rss,peak; memory(&rss,&peak);
    printf("{\"background\":%s,\"main_ms\":%.6f,\"store_ms\":%.6f,\"cpu_s\":%.6f,\"rss_kib\":%lu,\"peak_rss_kib\":%lu,\"accepted\":%lu}\n",background ? "true" : "false",mainMS,total,
           (after.ru_utime.tv_sec-before.ru_utime.tv_sec)+(after.ru_utime.tv_usec-before.ru_utime.tv_usec)/1000000.0+(after.ru_stime.tv_sec-before.ru_stime.tv_sec)+(after.ru_stime.tv_usec-before.ru_stime.tv_usec)/1000000.0,rss,peak,(unsigned long)[uris count]);
    [writer release]; [observer release]; [storeCondition release]; storeCondition=nil;
    unlink([file fileSystemRepresentation]); rmdir(path); [uris release]; return ok ? 0 : 1;
}

int main(int argc, char **argv) {
    NSAutoreleasePool *outer=[[NSAutoreleasePool alloc] init];
    if (argc == 3 && !strcmp(argv[1],"--measure")) { int result=measure([NSString stringWithUTF8String:argv[2]]); [outer drain]; return result; }
    if (argc == 4 && !strcmp(argv[1],"--measure-store")) { int result=measureStore([NSString stringWithUTF8String:argv[2]],!strcmp(argv[3],"background")); [outer drain]; return result; }
    VCBulkProfiles *profiles=[[VCBulkProfiles alloc] init];
    NSMutableString *text=[NSMutableString string];
    for (NSUInteger i=0;i<2000;i++) [text appendFormat:@"vless://u@profile%lu.test:443?type=ws&security=tls&fp=firefox\n",(unsigned long)i];
    NSAutoreleasePool *work=[[NSAutoreleasePool alloc] init];
    NSDictionary *report=[profiles subscriptionImportReportFromData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("bulk/all-records-preserved",[[report objectForKey:@"uris"] count] == 2000);
    CHECK("bulk/temporary-lifetime-bounded",peakTemporaries <= 2);
    [work drain];
    CHECK("bulk/temporaries-freed",liveTemporaries == 0);
    queryReads=0;
    NSDictionary *json=@{@"v":@"2",@"add":@"example.test",@"port":@443,@"id":@"11111111-2222-4333-8444-555555555555",@"net":@"ws",@"tls":@"tls",@"host":@"example.test"};
    NSString *vmess=[@"vmess://" stringByAppendingString:[[NSJSONSerialization dataWithJSONObject:json options:0 error:NULL] base64EncodedStringWithOptions:0]];
    CHECK("bulk/vmess-still-valid",[profiles isSupportedConfigTupleForURI:vmess]);
    CHECK("bulk/metadata-does-not-reparse-query",queryReads == 0);
    NSString *one=@"trojan://A%2B%3A%40@example.test:443?type=ws",*two=@"socks5://example.test";
    NSArray *expected=@[one,two];
    NSString *embedded=[NSString stringWithFormat:@"<a href=\"%@\">entry</a>\n%@\n%@\n",two,one,one];
    CHECK("bulk/extraction-order-and-dedup",[[profiles extractConfigURIsFromText:embedded] isEqual:expected]);
    NSData *plain=[[NSString stringWithFormat:@"%@\r\n%@\r%@\n",one,two,one] dataUsingEncoding:NSUTF8StringEncoding];
    CHECK("bulk/newline-forms",[[profiles parseSubscriptionData:plain] isEqual:expected]);
    CHECK("bulk/base64-wrapper",[[profiles parseSubscriptionData:[[plain base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding]] isEqual:expected]);
    CHECK("bulk/aliases-rejected",[profiles unsupportedConfigReasonForURI:@"vless://u@example.test:443?type=ws&network=tcp"] != nil);
    CHECK("bulk/empty-query-compatible",[profiles isSupportedConfigTupleForURI:@"vless://u@example.test:443?fp=&type=tcp&security=none"]);
    CHECK("bulk/socks-query-compatible",[profiles isSupportedConfigTupleForURI:@"socks5://example.test?ignored&security=none"]);
    CHECK("bulk/prepared-metadata-interface",[profiles respondsToSelector:@selector(preparedMetadataForConfigurations:subscriptions:additionalMetadata:)]);
    NSDictionary *preparedReport=[profiles subscriptionImportReportFromData:plain];
    NSDictionary *entries=[preparedReport objectForKey:@"metadata"];
    CHECK("bulk/report-keeps-validated-metadata",[entries count] == 2 && ![[[entries objectForKey:one] description] containsString:@"A+:"]);
    NSDictionary *prepared=[profiles preparedMetadataForConfigurations:@[] subscriptions:@[@{@"items":@[one]}] additionalMetadata:entries];
    CHECK("bulk/preparation-reuses-parsed-metadata",[prepared objectForKey:one] == [entries objectForKey:one] && [prepared count] == 1);
    CHECK("bulk/preparation-does-not-install",[profiles metadataForURI:one] != [entries objectForKey:one]);
    [profiles installPreparedMetadata:prepared];
    CHECK("bulk/prepared-install",[profiles metadataForURI:one] == [entries objectForKey:one]);
    NSDictionary *reused=[profiles preparedMetadataForConfigurations:@[@{@"uri":one}] subscriptions:@[] additionalMetadata:nil];
    CHECK("bulk/unchanged-metadata-reused",[reused objectForKey:one] == [entries objectForKey:one]);
    [profiles installPreparedMetadata:[profiles preparedMetadataForConfigurations:@[] subscriptions:@[] additionalMetadata:nil]];
    CHECK("bulk/removed-metadata-pruned",[profiles metadataForURI:one] != [entries objectForKey:one]);
    CHECK("bulk/background-writer-interface",NSClassFromString(@"VCConfigurationStoreWriter") != Nil);
    storeTests();
    CHECK("bulk/cancellable-task-interface",NSClassFromString(@"VCSubscriptionTask") != Nil);
    taskTests(text);
    NSMutableArray *manySubscriptions=[NSMutableArray array];
    for (NSUInteger i=0;i<1000;i++) [manySubscriptions addObject:@{@"items":@[one,two]}];
    VCBulkSubscriptions *indexed=[[VCBulkSubscriptions alloc] init]; indexed->items=manySubscriptions;
    NSInteger sub=-1,item=-1; BOOL header=NO;
    CHECK("bulk/row-index-last",VCMapSubscriptionRow(indexed,999,1001,&sub,&item,&header) && sub == 999 && item == 1 && !header);
    CHECK("bulk/row-index-constant-work",indexed->counts <= 6);
    CHECK("bulk/row-index-negative-rejected",!VCMapSubscriptionRow(indexed,999,-1,NULL,NULL,NULL));
    for (NSInteger expanded=-1;expanded<1000;expanded+=101) {
        for (NSInteger index=0;index<1000;index+=97) {
            NSInteger row=VCSubscriptionHeaderRow(indexed,expanded,index);
            CHECK("bulk/header-index-compatible",row == index+((expanded >= 0 && expanded < index) ? 2 : 0));
            CHECK("bulk/header-row-roundtrip",VCMapSubscriptionRow(indexed,expanded,row,&sub,&item,&header) && sub == index && item == -1 && header);
        }
    }
    [indexed release];
    [profiles release]; FINISH("large subscriptions"); [outer drain]; return 0;
}
