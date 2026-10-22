#define _POSIX_C_SOURCE 200809L
#include "../daemon/core_config.h"
#include "../common/daemon_policy.h"
#include "check.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

typedef struct { uint64_t now, inspect_time, resolve_time; unsigned inspections, resolutions; int inspect_result, resolve_result; const char *report,*primary,*download,*uri; } fixture_t;
static uint64_t now(void *context) { return ((fixture_t *)context)->now; }
static int inspect(void *context, const char *uri, uint64_t until, char *output, size_t capacity) {
    fixture_t *fixture=context; fixture->inspections++;
    CHECK("prepare/inspection-budget",until == fixture->now+2000 && !strcmp(uri,fixture->uri ? fixture->uri : "private-vless-core"));
    fixture->now+=fixture->inspect_time;
    snprintf(output,capacity,"%s",fixture->report);
    return fixture->inspect_result;
}
static int resolve(void *context, const char *host, uint64_t until, char *output, size_t capacity) {
    fixture_t *fixture=context;
    CHECK("prepare/shared-resolver-budget",until == 8100);
    CHECK("prepare/expected-host-order",!strcmp(host,fixture->resolutions ? "download.test" : "primary.test"));
    snprintf(output,capacity,"%s",fixture->resolutions++ ? fixture->download : fixture->primary);
    fixture->now+=fixture->resolve_time;
    return fixture->resolve_result;
}
static fixture_t initial(void) {
    return (fixture_t){.now=100,.report="CONFIG\t1\nPRIMARY\tprimary.test\t443\nDOWNLOAD\tdownload.test\t8443\nEND\n",.primary="192.0.2.1,192.0.2.2",.download="192.0.2.2,198.51.100.1"};
}
static void preparation(void) {
    fixture_t fixture=initial(); VCCorePrepareOperations ops={now,inspect,resolve,&fixture}; VCCoreAddresses addresses; char error[256];
    CHECK("prepare/two-independent-lists",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) == 0);
    CHECK("prepare/primary-is-not-union",!strcmp(addresses.primary,"192.0.2.1, 192.0.2.2"));
    CHECK("prepare/download-is-not-primary",!strcmp(addresses.download,"192.0.2.2, 198.51.100.1"));
    CHECK("prepare/deduplicated-bypass",!strcmp(addresses.bypass,"192.0.2.1, 192.0.2.2, 198.51.100.1"));
    CHECK("prepare/download-permanent-direct-exemption",ipv4_is_permanent_bypass_for_policy("198.51.100.1",addresses.bypass,0));
    CHECK("prepare/one-inspection-two-resolutions",fixture.inspections == 1 && fixture.resolutions == 2);
    fixture=initial(); fixture.report="CONFIG\t1\nPRIMARY\tprimary.test\t443\nDOWNLOAD\tPRIMARY.TEST\t8443\nEND\n";
    CHECK("prepare/same-host-resolved-once",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) == 0 && fixture.resolutions == 1 && !strcmp(addresses.primary,addresses.download));
    const char *bad[]={"", "CONFIG\t2\nPRIMARY\tprimary.test\t443\nEND\n", "CONFIG\t1\nPRIMARY\tprimary.test\t0\nEND\n", "CONFIG\t1\nPRIMARY\tprimary.test\t18446744073709551616\nEND\n", "CONFIG\t1\nPRIMARY\tprimary.test\t443\n", "CONFIG\t1\nPRIMARY\tprimary.test\t443\nEND\nsecret", "CONFIG\t1\nPRIMARY\tprimary.test\t443\nDOWNLOAD\tbad/name\t80\nEND\n"};
    for (unsigned i=0;i<sizeof(bad)/sizeof(*bad);i++) {
        fixture=initial(); fixture.report=bad[i];
        CHECK("prepare/malformed-reply-before-dns",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && !fixture.resolutions && !addresses.bypass[0]);
        CHECK("prepare/errors-without-uri",!strstr(error,"private-vless-core"));
    }
    fixture=initial(); fixture.report="CONFIG\t1\nPRIMARY\tprimary.test\t443\nDOWNLOAD\t2001:db8::1\t443\nEND\n";
    CHECK("prepare/ipv6-download-explicit-error",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && strstr(error,"IPv6") && !fixture.resolutions);
    fixture=initial(); fixture.inspect_time=2000;
    CHECK("prepare/inspection-timeout",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && strstr(error,"timed out") && !fixture.resolutions);
    fixture=initial(); fixture.resolve_time=4000;
    CHECK("prepare/deadline-is-not-restarted",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && fixture.resolutions == 2 && !addresses.primary[0] && !addresses.download[0] && !addresses.bypass[0]);
    fixture=initial(); fixture.download="";
    CHECK("prepare/download-dns-error",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && strstr(error,"download") && !addresses.bypass[0]);
    char primary[512]={0},download[512]={0};
    for (unsigned i=1;i<25;i++) { char ip[32]; snprintf(ip,sizeof(ip),"198.51.100.%u",i); CHECK("prepare/primary-fixture",ip_list_append(primary,sizeof(primary),ip) == 0); snprintf(ip,sizeof(ip),"203.0.113.%u",i); CHECK("prepare/download-fixture",ip_list_append(download,sizeof(download),ip) == 0); }
    fixture=initial(); fixture.primary=primary; fixture.download=download;
    CHECK("prepare/combined-capacity-not-truncated",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) < 0 && strstr(error,"511") && !addresses.bypass[0]);
    fixture=initial();
    CHECK("prepare/recovery-after-errors",vc_core_prepare("private-vless-core",&ops,&addresses,error,sizeof(error)) == 0);
    const char *uris[]={"vless://private@primary.test:443","socks5://primary.test:1080","trojan://private@primary.test:443","vmess://private-encoded-envelope","ss://private-encoded-envelope"};
    for (unsigned i=0;i<sizeof(uris)/sizeof(*uris);i++) {
        fixture=initial(); fixture.uri=uris[i];
        CHECK("prepare/new-protocols-inspected-once",vc_core_prepare(uris[i],&ops,&addresses,error,sizeof(error)) == 0 && fixture.inspections == 1 && fixture.resolutions == 2);
        CHECK("prepare/new-protocols-independent-addresses",!strcmp(addresses.primary,"192.0.2.1, 192.0.2.2") && !strcmp(addresses.download,"192.0.2.2, 198.51.100.1") && strstr(addresses.bypass,"198.51.100.1"));
        fixture=initial(); fixture.uri=uris[i]; fixture.inspect_result=-1;
        CHECK("prepare/invalid-protocol-never-resolves",vc_core_prepare(uris[i],&ops,&addresses,error,sizeof(error)) < 0 && !fixture.resolutions && !addresses.primary[0] && !addresses.download[0] && !addresses.bypass[0]);
    }
}

static int descriptor_count(void) { int count=0; for (int fd=0;fd<256;fd++) if (fcntl(fd,F_GETFD) >= 0) count++; return count; }
static int child_fixture(void) {
    char input[4096]; size_t used=0; ssize_t count;
    while ((count=read(0,input+used,sizeof(input)-used)) > 0) { used+=(size_t)count; if (used == sizeof(input)) return 1; }
    const char *mode=getenv("VC_CORE_TEST_MODE");
    if (mode && !strcmp(mode,"crash")) { raise(SIGKILL); return 1; }
    if (mode && !strcmp(mode,"large")) { memset(input,'A',sizeof(input)); return write(1,input,sizeof(input)) == sizeof(input) ? 0 : 1; }
    const char *report="CONFIG\t1\nPRIMARY\tprimary.test\t443\nEND\n";
    for (const char *p=report;*p;p++) {
        if (write(1,p,1) != 1) return 1;
        if (mode && !strcmp(mode,"slow")) { struct timespec wait={.tv_nsec=10000000}; nanosleep(&wait,NULL); }
    }
    return used ? 0 : 1;
}
static void processes(const char *binary) {
    int baseline=descriptor_count(); char output[1024];
    for (unsigned i=0;i<8;i++) {
        char *env[]={i%4 == 0 ? "VC_CORE_TEST_MODE=normal" : i%4 == 1 ? "VC_CORE_TEST_MODE=slow" : i%4 == 2 ? "VC_CORE_TEST_MODE=crash" : "VC_CORE_TEST_MODE=large",NULL};
        uint64_t start=vc_core_now_ms();
        int result=vc_core_inspect_run(binary,"private-vless-core",env,-1,start+(i%4 == 1 ? 150 : 2000),NULL,NULL,output,sizeof(output));
        CHECK("inspect/process-results",i%4 == 0 ? !result && !strcmp(output,"CONFIG\t1\nPRIMARY\tprimary.test\t443\nEND\n") : i%4 == 1 ? result == -2 : result == -1);
        CHECK("inspect/absolute-process-deadline",vc_core_now_ms()-start < (i%4 == 1 ? 1000 : 4000));
        CHECK("inspect/no-descriptor-leak",descriptor_count() == baseline);
        CHECK("inspect/no-zombie",waitpid(-1,NULL,WNOHANG) < 0 && errno == ECHILD);
    }
}
int main(int argc, char **argv) {
    signal(SIGPIPE,SIG_IGN);
    if (argc == 3 && !strcmp(argv[1],"--real")) {
        char uri[4096],output[1024]; size_t used=0; ssize_t count;
        while ((count=read(0,uri+used,sizeof(uri)-used)) > 0) { used+=(size_t)count; if (used == sizeof(uri)) return 1; }
        if (count < 0) return 1;
        uri[used]=0;
        char *env[]={"PATH=/usr/bin:/bin",NULL};
        int result=vc_core_inspect_run(argv[2],uri,env,STDERR_FILENO,vc_core_now_ms()+2000,NULL,NULL,output,sizeof(output));
        memset(uri,0,sizeof(uri));
        if (!result) fputs(output,stdout);
        return result ? 1 : 0;
    }
    if (argc > 1) return argc == 4 && !strcmp(argv[1],"--inspect-config") && !strcmp(argv[2],"--uri-fd") && !strcmp(argv[3],"0") ? child_fixture() : 1;
    preparation(); processes(argv[0]); FINISH("core connection preparation"); return 0;
}
