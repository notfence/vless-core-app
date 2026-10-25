#import <Foundation/Foundation.h>
#include "check.h"
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <errno.h>
#include <sys/resource.h>
#include <sys/time.h>
static const char *executable;
#define VC_CORE_EXECUTABLE_PATH executable
#define VC_CORE_EXECUTABLE_NAME "test-temp-core"
static NSUInteger const kVCMaximumConfigURIBytes=4095;
static int write_all(int fd,const void *bytes,size_t length) {
    while (length) {
        ssize_t result=write(fd,bytes,length);
        if (result<0 && errno==EINTR) continue;
        if (result<=0) return -1;
        bytes=(const char *)bytes+result; length-=(size_t)result;
    }
    return 0;
}
#include "temp_spawn_test.inc"

static int child(int argc,char **argv) {
    if (argc!=5 && argc!=7) return 20;
    if (strcmp(argv[1],"--uri-fd") || strcmp(argv[2],"0") || strcmp(argv[3],"--listen-port") || strcmp(argv[4],"12345")) return 21;
    if (argc==7 && (strcmp(argv[5],"--xray-version") || strcmp(argv[6],"26.6.27"))) return 22;
    for (int i=0;i<argc;i++) if (strstr(argv[i],"synthetic-secret")) return 23;
    char bytes[4096]; size_t used=0;
    for (;;) {
        ssize_t count=read(0,bytes+used,sizeof(bytes)-used);
        if (count<0 && errno==EINTR) continue;
        if (count<0) return 24;
        if (!count) break;
        used+=(size_t)count;
        if (used==sizeof(bytes)) return 25;
    }
    const char expected[]="synthetic-secret:%+@/";
    if (used!=sizeof(expected)-1 || memcmp(bytes,expected,used)) return 26;
    if (write_all(STDERR_FILENO,"child-ok\n",9)!=0) return 27;
    return 0;
}
static NSUInteger descriptors(void) {
    NSUInteger count=0;
    for (int fd=0;fd<256;fd++) if (fcntl(fd,F_GETFD)>=0) count++;
    return count;
}
int main(int argc,char **argv) {
    if (argc>1 && !strcmp(argv[1],"--uri-fd")) return child(argc,argv);
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    executable=argv[0];
    char path[]="/tmp/vless-temp-spawn-XXXXXX";
    int capture=mkstemp(path);
    CHECK("temp-spawn/capture",capture>=0 && unlink(path)==0 && fcntl(capture,F_SETFD,FD_CLOEXEC)==0);
    NSUInteger before=descriptors();
    BOOL measure=argc==3 && !strcmp(argv[1],"--measure");
    NSUInteger repetitions=measure ? strtoul(argv[2],NULL,10) : 20;
    CHECK("temp-spawn/bounded-test-count",repetitions>0 && repetitions<=1000);
    struct timeval start,end; gettimeofday(&start,NULL);
    struct rusage appBefore,coreBefore,appAfter,coreAfter;
    getrusage(RUSAGE_SELF,&appBefore); getrusage(RUSAGE_CHILDREN,&coreBefore);
    for (NSUInteger i=0;i<repetitions;i++) {
        pid_t pid=spawn_temp_core_for_ping("synthetic-secret:%+@/",12345,i%2 ? "26.6.27" : NULL,capture);
        int status=0;
        CHECK("temp-spawn/child-validates-pipe-and-argv",pid>0 && waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
        CHECK("temp-spawn/no-owned-fd-leak",descriptors()==before);
    }
    gettimeofday(&end,NULL); getrusage(RUSAGE_SELF,&appAfter); getrusage(RUSAGE_CHILDREN,&coreAfter);
    if (measure) {
        double elapsed=(end.tv_sec-start.tv_sec)*1000+(end.tv_usec-start.tv_usec)/1000.0;
        double appCPU=appAfter.ru_utime.tv_sec-appBefore.ru_utime.tv_sec+(appAfter.ru_utime.tv_usec-appBefore.ru_utime.tv_usec)/1e6+
            appAfter.ru_stime.tv_sec-appBefore.ru_stime.tv_sec+(appAfter.ru_stime.tv_usec-appBefore.ru_stime.tv_usec)/1e6;
        double childCPU=coreAfter.ru_utime.tv_sec-coreBefore.ru_utime.tv_sec+(coreAfter.ru_utime.tv_usec-coreBefore.ru_utime.tv_usec)/1e6+
            coreAfter.ru_stime.tv_sec-coreBefore.ru_stime.tv_sec+(coreAfter.ru_stime.tv_usec-coreBefore.ru_stime.tv_usec)/1e6;
        printf("{\"count\":%lu,\"spawn_child_ms\":%.6f,\"app_cpu_s\":%.6f,\"child_cpu_s\":%.6f,\"maxrss\":%ld,\"fds\":%lu}\n",(unsigned long)repetitions,elapsed/repetitions,appCPU,childCPU,appAfter.ru_maxrss,(unsigned long)descriptors());
        close(capture); [pool drain]; return 0;
    }
    char result[9];
    CHECK("temp-spawn/diagnostic-redirection",pread(capture,result,sizeof(result),0)==sizeof(result) && !memcmp(result,"child-ok\n",sizeof(result)));
    int saved=dup(STDIN_FILENO);
    CHECK("temp-spawn/save-stdin",saved>=0 && close(STDIN_FILENO)==0);
    pid_t pid=spawn_temp_core_for_ping("synthetic-secret:%+@/",12345,NULL,capture);
    int status=0;
    CHECK("temp-spawn/closed-stdin",pid>0 && waitpid(pid,&status,0)==pid && WIFEXITED(status) && WEXITSTATUS(status)==0);
    CHECK("temp-spawn/restore-stdin",dup2(saved,STDIN_FILENO)==STDIN_FILENO && close(saved)==0);
    executable="/does-not-exist/vless-test";
    CHECK("temp-spawn/missing-executable",spawn_temp_core_for_ping("synthetic-secret:%+@/",12345,NULL,capture)<0 && descriptors()==before);
    close(capture);
    FINISH("temporary core spawn"); [pool drain]; return 0;
}
