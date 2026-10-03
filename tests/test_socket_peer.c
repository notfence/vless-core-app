#define _DEFAULT_SOURCE 1
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>
#include "check.h"
static int modern = 1, bad_pid, bad_name, bad_size, disconnected, ambiguous, mismatch, changed;
static unsigned server_reads;
static int fake_getsockopt(int, int, int, void *, socklen_t *);
static long fake_syscall(long, ...);
#define getsockopt fake_getsockopt
#define syscall fake_syscall
#define VC_HOST_PEER_TEST 1
#include "../daemon/socket_peer_pid.c"
#undef getsockopt
#undef syscall
static int fake_getsockopt(int fd, int level, int option, void *out, socklen_t *length) {
    (void)fd; (void)level;
    if (option == LOCAL_PEERPID) {
        if (modern) { *(pid_t *)out = bad_pid ? 0 : 42; *length = sizeof(pid_t); return 0; }
        errno = EOPNOTSUPP; return -1;
    }
    struct xucred *credential = out; memset(credential, 0, sizeof(*credential));
    credential->cr_version = XUCRED_VERSION; credential->cr_uid = 501; *length = sizeof(*credential); return 0;
}
static long fake_syscall(long number, ...) {
    CHECK("peer/proc-info-syscall-contract", number == SYS_proc_info);
    va_list ap; va_start(ap, number); int kind = va_arg(ap, int); int pid = va_arg(ap, int); int flavor = va_arg(ap, int);
    uint64_t argument = va_arg(ap, uint64_t); void *out = va_arg(ap, void *); int length = va_arg(ap, int); va_end(ap);
    memset(out, 0, length);
    if (kind == 1) { int32_t *pids = out; pids[0] = 42; if (ambiguous) pids[1] = 43; return ambiguous ? 8 : 4; }
    if (kind == 2 && flavor == 3) {
        vc_bsd_info_t *bsd = out; bsd->info.fields[3] = pid; strcpy(bsd->info.name, bad_name ? "other" : "vless-core"); return sizeof(*bsd);
    }
    if (kind == 2 && flavor == 1) { vc_proc_fd_t *fds = out; fds[0].fd = 12; fds[0].type = 2; return sizeof(*fds); }
    CHECK("peer/socket-query-flavor", kind == 3 && flavor == 3);
    vc_socket_info_t *socket = out;
    socket->info.family = AF_UNIX; socket->info.type = SOCK_STREAM; socket->info.kind = 3;
    socket->info.state = disconnected ? 0 : 2;
    if (pid == getpid() && argument == 10) {
        server_reads++; socket->info.socket_id = 100; socket->info.pcb_id = 200; socket->info.peer_socket_id = 300; socket->info.peer_pcb_id = changed && server_reads > 1 ? 999 : 400;
    } else {
        socket->info.socket_id = 300; socket->info.pcb_id = 400; socket->info.peer_socket_id = mismatch ? 999 : 100; socket->info.peer_pcb_id = 200;
    }
    return bad_size ? length - 1 : length;
}
int main(void) {
    const char *paths[] = {"/Applications/vless-core.app/vless-core"};
    CHECK("peer/modern-pid", vc_socket_peer_pid(10, paths, 1) == 42);
    bad_pid = 1; CHECK("peer/modern-invalid-pid", vc_socket_peer_pid(10, paths, 1) == -1 && errno == EINVAL); bad_pid = 0;
    modern = 0; CHECK("peer/legacy-identified", vc_socket_peer_pid(10, paths, 1) == 42);
    bad_name = 1; CHECK("peer/foreign-process-name", vc_socket_peer_pid(10, paths, 1) == -1 && errno == ESRCH); bad_name = 0;
    bad_size = 1; CHECK("peer/truncated-kernel-record", vc_socket_peer_pid(10, paths, 1) == -1 && errno == EINVAL); bad_size = 0;
    disconnected = 1; CHECK("peer/disconnected-socket", vc_socket_peer_pid(10, paths, 1) == -1 && errno == ENOTCONN); disconnected = 0;
    ambiguous = 1; CHECK("peer/ambiguous-owner-denied", vc_socket_peer_pid(10, paths, 1) == -1 && errno == EACCES); ambiguous = 0;
    mismatch = 1; CHECK("peer/mismatched-socket-owner", vc_socket_peer_pid(10, paths, 1) == -1 && errno == ESRCH); mismatch = 0;
    changed = 1; server_reads = 0; CHECK("peer/race-recheck", vc_socket_peer_pid(10, paths, 1) == -1 && errno == ENOTCONN);
    FINISH("socket peer identity"); return 0;
}
