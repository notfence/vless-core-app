#import "../common/profile_logic.h"
#import "../common/secure_store.h"
#include "check.h"
#include <time.h>
#include <sys/resource.h>
#include <unistd.h>
#include <sys/stat.h>

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
    [profiles release]; FINISH("large subscriptions"); [outer drain]; return 0;
}
