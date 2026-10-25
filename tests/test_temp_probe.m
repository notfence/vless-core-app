#import <Foundation/Foundation.h>
#import "../common/connection_logic.h"
#include "check.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

static NSUInteger calls,spawns,stops;
static int results[2],times[2];
static BOOL cancelFirst;
static NSDictionary *VCProxyPingTargetForURL(id url) { return [url isEqual:@"http://synthetic/"] ? @{} : nil; }
static int pick_free_loopback_port(void) { return 10101; }
static pid_t spawn_temp_core_for_ping(const char *uri,uint16_t port,const char *version,int capture) {
    (void)version;
    CHECK("temp-probe/input-preserved",!strcmp(uri,"synthetic-secret") && port==10101 && capture>=0);
    spawns++; return 100000000;
}
static int wait_for_loopback_listener(uint16_t port,pid_t pid,int timeout,VCPingCancellation *cancellation) {
    (void)port; (void)pid; (void)timeout; (void)cancellation; return 0;
}
static void stop_child_process(pid_t pid) { CHECK("temp-probe/only-owned-child",pid==100000000); stops++; }
static NSDictionary *ReadProbeReport(VCProbeLogReader *reader,long long previous,VCPingCancellation *cancellation) {
    (void)reader; (void)previous; (void)cancellation;
    return @{@"id":@(calls),@"success":@(results[calls-1]==0),@"stage":results[calls-1]==0 ? @"none" : @"tcp"};
}
static int ProxyGetConnectToURLOnceMs(uint16_t port,id url,int timeout,int *ms,VCPingCancellation *cancellation) {
    (void)port; (void)url;
    CHECK("temp-probe/attempt-keeps-selected-timeout",timeout==5000 && calls<2);
    *ms=times[calls];
    int rc=results[calls++];
    if (cancelFirst) [cancellation cancel];
    return rc;
}
@interface VCProbeCancellation : VCPingCancellation
@end
@implementation VCProbeCancellation
- (void)registerChild:(pid_t)pid { (void)pid; }
- (void)forgetChild:(pid_t)pid { (void)pid; }
@end
#include "temp_probe_test.inc"

static int probe(int first,int second,int firstTime,int secondTime,int *latency) {
    calls=spawns=stops=0; results[0]=first; results[1]=second; times[0]=firstTime; times[1]=secondTime;
    VCProbeCancellation *cancellation=[[[VCProbeCancellation alloc] init] autorelease];
    int rc=ProxyGetViaTempCoreMs("synthetic-secret",NULL,5000,2,latency,cancellation,@"http://synthetic/");
    CHECK("temp-probe/one-core-for-both-attempts",spawns==1 && stops==1);
    return rc;
}
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    int latency=-1;
    CHECK("temp-probe/first-failure-stops",probe(-1,0,0,1,&latency)!=0 && calls==1 && latency==-1);
    CHECK("temp-probe/two-successes-use-smaller",probe(0,0,20,7,&latency)==0 && calls==2 && latency==7);
    CHECK("temp-probe/second-failure-keeps-first",probe(0,-1,20,0,&latency)==0 && calls==2 && latency==20);
    cancelFirst=YES;
    probe(0,0,20,7,&latency);
    CHECK("temp-probe/cancel-stops-series",calls==1);
    FINISH("temporary proxy probe"); [pool drain]; return 0;
}
