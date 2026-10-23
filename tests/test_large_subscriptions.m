#import "../common/profile_logic.h"
#import "../common/secure_store.h"
#include "check.h"
#include <time.h>
#include <sys/resource.h>
#include <unistd.h>

static NSUInteger liveTemporaries, peakTemporaries, queryReads;

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

int main(int argc, char **argv) {
    NSAutoreleasePool *outer=[[NSAutoreleasePool alloc] init];
    if (argc == 3 && !strcmp(argv[1],"--measure")) { int result=measure([NSString stringWithUTF8String:argv[2]]); [outer drain]; return result; }
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
    [profiles release]; FINISH("large subscriptions"); [outer drain]; return 0;
}
