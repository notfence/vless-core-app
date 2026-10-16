#define _POSIX_C_SOURCE 200809L
#include "core_config.h"
#include "../common/daemon_policy.h"
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

uint64_t vc_core_now_ms(void) {
#ifdef __APPLE__
    mach_timebase_info_data_t scale;
    if (mach_timebase_info(&scale) != KERN_SUCCESS || !scale.denom) return 0;
    return (uint64_t)((double)mach_absolute_time()*scale.numer/scale.denom/1000000.0);
#else
    struct timespec time;
    if (clock_gettime(CLOCK_MONOTONIC,&time)) return 0;
    return (uint64_t)time.tv_sec*1000+(uint64_t)time.tv_nsec/1000000;
#endif
}

static int fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error,capacity,"%s",message);
    return -1;
}

static int parse_endpoint(char **cursor, const char *kind, char host[256]) {
    char *line=*cursor,*end=strchr(line,'\n');
    size_t prefix=strlen(kind);
    if (!end || strncmp(line,kind,prefix) || line[prefix] != '\t') return -1;
    char *name=line+prefix+1,*separator=memchr(name,'\t',(size_t)(end-name));
    if (!separator || separator == name || (size_t)(separator-name) >= 256) return -1;
    for (const unsigned char *p=(const unsigned char *)name;p<(const unsigned char *)separator;p++)
        if (*p <= 0x20 || *p == 0x7f || strchr("/@?#[]",*p)) return -1;
    unsigned port=0;
    for (char *p=separator+1;p<end;p++) {
        unsigned digit=(unsigned)(*p-'0');
        if (digit > 9 || port > 65535/10 || (port == 65535/10 && digit > 65535%10)) return -1;
        port=port*10+digit;
    }
    if (!port) return -1;
    memcpy(host,name,(size_t)(separator-name)); host[separator-name]=0;
    *cursor=end+1;
    return 0;
}

static int append_ips(char *destination, size_t capacity, const char *source) {
    char copy[512];
    if (!source || !*source || strlen(source) >= sizeof(copy)) return -1;
    memcpy(copy,source,strlen(source)+1);
    for (char *cursor=copy;cursor && *cursor;) {
        char *next=strchr(cursor,','); if (next) *next++=0;
        while (*cursor == ' ' || *cursor == '\t') cursor++;
        char *end=cursor+strlen(cursor); while (end > cursor && (end[-1] == ' ' || end[-1] == '\t')) *--end=0;
        struct in_addr address; char text[INET_ADDRSTRLEN];
        if (inet_pton(AF_INET,cursor,&address) != 1 || !inet_ntop(AF_INET,&address,text,sizeof(text)) || ip_list_append(destination,capacity,text)) return -1;
        if (next && !*next) return -1;
        cursor=next;
    }
    return 0;
}

int vc_core_prepare(const char *uri, const VCCorePrepareOperations *ops, VCCoreAddresses *output, char *error, size_t capacity) {
    if (!output) return -1;
    memset(output,0,sizeof(*output));
    if (!uri || !*uri || strlen(uri) > 4095 || !ops || !ops->now || !ops->inspect || !ops->resolve) return fail(error,capacity,"invalid connection preparation");
    uint64_t start=ops->now(ops->context);
    if (start > UINT64_MAX-8000) return fail(error,capacity,"connection preparation deadline overflow");
    uint64_t until=start+8000;
    char report[1024]={0},primary[256],download[256]={0},addresses[512]={0};
    int result=ops->inspect(ops->context,uri,start+2000,report,sizeof(report));
    if (result || ops->now(ops->context) >= start+2000) return fail(error,capacity,result == -2 || ops->now(ops->context) >= start+2000 ? "configuration inspection timed out" : "configuration inspection failed; update the bundled core if inspection is unsupported");
    if (!memchr(report,0,sizeof(report)) || strncmp(report,"CONFIG\t1\n",9)) return fail(error,capacity,"invalid configuration inspection response");
    char *cursor=report+9;
    if (parse_endpoint(&cursor,"PRIMARY",primary)) return fail(error,capacity,"invalid primary endpoint response");
    if (!strncmp(cursor,"DOWNLOAD\t",9) && parse_endpoint(&cursor,"DOWNLOAD",download)) return fail(error,capacity,"invalid download endpoint response");
    if (strcmp(cursor,"END\n")) return fail(error,capacity,"incomplete configuration inspection response");
    struct in6_addr ipv6;
    if (inet_pton(AF_INET6,primary,&ipv6) == 1) return fail(error,capacity,"primary server requires unsupported IPv6 routing");
    if (*download && inet_pton(AF_INET6,download,&ipv6) == 1) return fail(error,capacity,"download server requires unsupported IPv6 routing");
    result=ops->resolve(ops->context,primary,until,addresses,sizeof(addresses));
    const char *reason="primary server has no usable IPv4 addresses";
    if (result || ops->now(ops->context) >= until || append_ips(output->primary,sizeof(output->primary),addresses)) goto invalid;
    if (*download) {
        reason="download server has no usable IPv4 addresses";
        if (!strcasecmp(primary,download)) memcpy(output->download,output->primary,strlen(output->primary)+1);
        else {
            memset(addresses,0,sizeof(addresses));
            result=ops->resolve(ops->context,download,until,addresses,sizeof(addresses));
            if (result || ops->now(ops->context) >= until || append_ips(output->download,sizeof(output->download),addresses)) goto invalid;
        }
    }
    reason="combined server bypass list exceeds 511 bytes";
    if (append_ips(output->bypass,sizeof(output->bypass),output->primary) || (*output->download && append_ips(output->bypass,sizeof(output->bypass),output->download))) goto invalid;
    return 0;
invalid:
    if (result == -2 || ops->now(ops->context) >= until) reason="server address preparation timed out";
    memset(output,0,sizeof(*output));
    return fail(error,capacity,reason);
}

int vc_core_inspect_run(const char *binary, const char *uri, char *const *environment, int log_fd, uint64_t until,
                       int (*prepare_child)(void *), void *context, char *output, size_t capacity) {
    if (!binary || !uri || !output || capacity < 2 || strlen(uri) > 4095) return -1;
    output[0]=0;
    int input[2]={-1,-1},reply[2]={-1,-1},result=-1,status=0,reaped=0,eof=0;
    pid_t pid=-1;
    if (pipe(input) || pipe(reply)) goto cleanup;
    for (unsigned i=0;i<2;i++) {
        int *pipes[]={input+i,reply+i};
        for (unsigned j=0;j<2;j++) if (*pipes[j] < 3) {
            int copy=fcntl(*pipes[j],F_DUPFD,3);
            if (copy < 0) goto cleanup;
            close(*pipes[j]); *pipes[j]=copy;
        }
    }
    for (unsigned i=0;i<2;i++) if (fcntl(input[i],F_SETFD,FD_CLOEXEC) || fcntl(reply[i],F_SETFD,FD_CLOEXEC)) goto cleanup;
    pid=fork();
    if (pid < 0) goto cleanup;
    if (!pid) {
        if (dup2(input[0],STDIN_FILENO) < 0 || dup2(reply[1],STDOUT_FILENO) < 0 || (log_fd >= 0 && dup2(log_fd,STDERR_FILENO) < 0)) _exit(126);
        close(input[0]); close(input[1]); close(reply[0]); close(reply[1]);
        if (prepare_child && prepare_child(context)) _exit(126);
        char *arguments[]={(char *)binary,"--inspect-config","--uri-fd","0",NULL};
        execve(binary,arguments,environment); _exit(127);
    }
    close(input[0]); input[0]=-1; close(reply[1]); reply[1]=-1;
    if (fcntl(input[1],F_SETFL,O_NONBLOCK) || fcntl(reply[0],F_SETFL,O_NONBLOCK)) goto cleanup;
    size_t sent=0,used=0,length=strlen(uri);
    while (!eof || !reaped) {
        uint64_t now=vc_core_now_ms();
        if (now >= until) { result=-2; goto cleanup; }
        if (!reaped) {
            pid_t waited=waitpid(pid,&status,WNOHANG);
            if (waited == pid) reaped=1;
            else if (waited < 0 && errno != EINTR) goto cleanup;
        }
        struct pollfd fds[2]={{.fd=input[1],.events=POLLOUT},{.fd=eof ? -1 : reply[0],.events=POLLIN}};
        uint64_t remaining=until-now;
        int wait=remaining > 25 ? 25 : (int)remaining;
        int ready=poll(fds,2,wait);
        if (ready < 0) { if (errno == EINTR) continue; goto cleanup; }
        if (fds[0].revents) {
            if (fds[0].revents&(POLLERR|POLLHUP|POLLNVAL)) goto cleanup;
            ssize_t count=write(input[1],uri+sent,length-sent);
            if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) goto cleanup;
            if (count > 0) sent+=(size_t)count;
            if (sent == length) { close(input[1]); input[1]=-1; }
        }
        if (fds[1].revents) {
            char bytes[256]; ssize_t count=read(reply[0],bytes,sizeof(bytes));
            if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) goto cleanup;
            if (!count) eof=1;
            if (count > 0) {
                if ((size_t)count >= capacity-used || memchr(bytes,0,(size_t)count)) goto cleanup;
                memcpy(output+used,bytes,(size_t)count); used+=(size_t)count; output[used]=0;
            }
        }
    }
    result=sent == length && WIFEXITED(status) && WEXITSTATUS(status) == 0 && *output ? 0 : -1;
cleanup:
    for (unsigned i=0;i<2;i++) { if (input[i] >= 0) close(input[i]); if (reply[i] >= 0) close(reply[i]); }
    if (pid > 0 && !reaped) { kill(pid,SIGKILL); while (waitpid(pid,NULL,0) < 0 && errno == EINTR) {} }
    if (result) output[0]=0;
    return result;
}
