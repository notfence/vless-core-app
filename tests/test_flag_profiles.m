#import "../common/profile_logic.h"
#include "../common/flag_logic.h"
#include "check.h"
#include <sys/resource.h>
#include <time.h>

static double milliseconds(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC,&now);
    return now.tv_sec*1000.0+now.tv_nsec/1000000.0;
}

int main(int argc, char **argv) {
    NSAutoreleasePool *outer=[[NSAutoreleasePool alloc] init];
    NSUInteger count=argc>1 ? strtoul(argv[1],NULL,10) : 1000;
    BOOL scan=argc>2 && !strcmp(argv[2],"scan");
    NSMutableString *source=[NSMutableString string];
    for (NSUInteger i=0;i<count;i++) [source appendFormat:@"vless://11111111-2222-4333-8444-555555555555@profile%lu.test:443?security=tls#%%F0%%9F%%87%%B3%%F0%%9F%%87%%B1%%20NL%lu\n",(unsigned long)i,(unsigned long)i];
    VCProfileLogic *profiles=[[VCProfileLogic alloc] init];
    double begin=milliseconds();
    NSAutoreleasePool *work=[[NSAutoreleasePool alloc] init];
    NSDictionary *report=[[profiles subscriptionImportReportFromData:[source dataUsingEncoding:NSUTF8StringEncoding]] retain];
    NSArray *uris=[report objectForKey:@"uris"];
    NSDictionary *prepared=[profiles preparedMetadataForConfigurations:@[] subscriptions:@[@{@"items":uris}] additionalMetadata:[report objectForKey:@"metadata"]];
    [profiles installPreparedMetadata:prepared];
    [work drain];
    double loaded=milliseconds()-begin; begin=milliseconds();
    NSUInteger total=0, found=0, visible=MIN(count,(NSUInteger)24);
    for (NSUInteger pass=0;pass<3;pass++) for (NSUInteger i=0;i<visible;i++) {
        work=[[NSAutoreleasePool alloc] init];
        NSString *uri=[uris objectAtIndex:i];
        NSString *name=[[profiles metadataForURI:uri] objectForKey:@"title"];
        total+=[name length];
        if (scan) {
            NSMutableData *buffer=[NSMutableData dataWithLength:[name length]*sizeof(unichar)];
            [name getCharacters:[buffer mutableBytes] range:NSMakeRange(0,[name length])];
            size_t cursor=0; VCFlagMatch match;
            while (VCFlagNext([buffer bytes],[name length],&cursor,&match)) {
                CHECK("flag-profiles/correct-asset",!strcmp(match.asset,"1f1f3-1f1f1")); found++;
            }
        }
        CHECK("flag-profiles/uri-not-rewritten",[uri rangeOfString:@"#%F0%9F%87%B3%F0%9F%87%B1%20NL"].location!=NSNotFound);
        CHECK("flag-profiles/name-remains-unicode",[name characterAtIndex:0]==0xd83c && [name characterAtIndex:1]==0xddf3);
        [work drain];
    }
    double titles=milliseconds()-begin;
    CHECK("flag-profiles/count",[uris count]==count && found==(scan ? visible*3 : 0));
    struct rusage usage; getrusage(RUSAGE_SELF,&usage);
    unsigned long rss=0,peak=0; char line[256]; FILE *status=fopen("/proc/self/status","r");
    if (status) { while (fgets(line,sizeof(line),status)) { sscanf(line,"VmRSS: %lu",&rss); sscanf(line,"VmHWM: %lu",&peak); } fclose(status); }
    printf("{\"count\":%lu,\"accepted\":%lu,\"title_units\":%lu,\"flags\":%lu,\"load_ms\":%.6f,\"titles_ms\":%.6f,\"cpu_s\":%.6f,\"rss_kib\":%lu,\"peak_rss_kib\":%lu}\n",(unsigned long)count,(unsigned long)[uris count],(unsigned long)total,(unsigned long)found,loaded,titles,usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1000000.0+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1000000.0,rss,peak);
    [report release]; [profiles release]; [outer drain]; return 0;
}
