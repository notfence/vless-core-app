#define _DARWIN_C_SOURCE 1
#include "socket_peer_pid.h"
#include <errno.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#if !defined(__LP64__)
#include <sys/syscall.h>
#include <sys/ucred.h>

typedef struct {
    unsigned char file_info[24];
    unsigned char stat_info[136];
    uint64_t socket_id, pcb_id;
    int32_t type, protocol, family;
    int16_t options, linger, state, qlen, incqlen, qlimit, timeout, error;
    uint32_t oobmark;
    unsigned char receive_buffer[24], send_buffer[24];
    int32_t kind;
    uint32_t reserved;
    uint64_t peer_socket_id, peer_pcb_id;
} vc_socket_prefix_t;

typedef union {
    vc_socket_prefix_t info;
    unsigned char bytes[792];
} vc_socket_info_t;

typedef struct { int32_t fd; uint32_t type; } vc_proc_fd_t;
typedef union {
    struct { uint32_t fields[12]; char name[16]; } info;
    unsigned char bytes[136];
} vc_bsd_info_t;

_Static_assert(offsetof(vc_socket_prefix_t, socket_id) == 160, "proc_info socket ABI");
_Static_assert(offsetof(vc_socket_prefix_t, peer_socket_id) == 264, "proc_info peer ABI");
_Static_assert(sizeof(vc_socket_info_t) == 792, "proc_info buffer ABI");

static int socket_info(pid_t pid, int fd, vc_socket_info_t *result) {
    memset(result, 0, sizeof(*result));
    int count = syscall(SYS_proc_info, 3, pid, 3, (uint64_t)fd, result, (int)sizeof(*result));
    if (count < 0) return -1;
    if (count != sizeof(*result) || result->info.family != AF_UNIX ||
        result->info.type != SOCK_STREAM || result->info.kind != 3) {
        errno = EINVAL;
        return -1;
    }
    if (!(result->info.state & 0x0002) || !result->info.socket_id || !result->info.pcb_id ||
        !result->info.peer_socket_id || !result->info.peer_pcb_id) {
        errno = ENOTCONN;
        return -1;
    }
    return 0;
}

static int sockets_match(const vc_socket_info_t *server, const vc_socket_info_t *peer) {
    return server->info.socket_id == peer->info.peer_socket_id &&
           server->info.pcb_id == peer->info.peer_pcb_id &&
           server->info.peer_socket_id == peer->info.socket_id &&
           server->info.peer_pcb_id == peer->info.pcb_id;
}

static int candidate_name_matches(const char name[16], const char *const *paths, size_t count) {
    for (size_t index = 0; index < count; index++) {
        const char *base = strrchr(paths[index], '/');
        base = base ? base + 1 : paths[index];
        if (name[15] == '\0' && strncmp(name, base, 15) == 0) return 1;
    }
    return 0;
}

static pid_t vc_legacy_socket_peer_pid(int fd, const char *const *paths, size_t path_count) {
    if (fd < 0 || !paths || !path_count) { errno = EINVAL; return -1; }
    struct xucred credential;
    socklen_t size = sizeof(credential);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &credential, &size) != 0) return -1;
    if (size != sizeof(credential) || credential.cr_version != XUCRED_VERSION) {
        errno = EINVAL;
        return -1;
    }
    vc_socket_info_t server;
    if (socket_info(getpid(), fd, &server) != 0) return -1;
    int32_t pids[1024];
    int count = syscall(SYS_proc_info, 1, 4, credential.cr_uid, (uint64_t)0, pids, (int)sizeof(pids));
    if (count < 0) return -1;
    if (count == sizeof(pids) || count % sizeof(pids[0]) != 0) { errno = EOVERFLOW; return -1; }
    pid_t found_pid = -1;
    int found_fd = -1;
    for (size_t index = 0; index < (size_t)count / sizeof(pids[0]); index++) {
        if (pids[index] <= 0) continue;
        vc_bsd_info_t bsd;
        int bytes = syscall(SYS_proc_info, 2, pids[index], 3, (uint64_t)0, &bsd, (int)sizeof(bsd));
        if (bytes != sizeof(bsd) || bsd.info.fields[3] != (uint32_t)pids[index] ||
            !candidate_name_matches(bsd.info.name, paths, path_count)) continue;
        vc_proc_fd_t descriptors[1024];
        bytes = syscall(SYS_proc_info, 2, pids[index], 1, (uint64_t)0,
                        descriptors, (int)sizeof(descriptors));
        if (bytes < 0 || bytes == sizeof(descriptors) || bytes % sizeof(descriptors[0]) != 0) continue;
        for (size_t slot = 0; slot < (size_t)bytes / sizeof(descriptors[0]); slot++) {
            if (descriptors[slot].type != 2) continue;
            vc_socket_info_t peer;
            if (socket_info(pids[index], descriptors[slot].fd, &peer) != 0 || !sockets_match(&server, &peer)) continue;
            if (found_pid > 0 && found_pid != pids[index]) { errno = EACCES; return -1; }
            found_pid = pids[index];
            found_fd = descriptors[slot].fd;
            break;
        }
    }
    if (found_pid <= 0) { errno = ESRCH; return -1; }
    vc_socket_info_t current, peer;
    if (socket_info(getpid(), fd, &current) != 0 ||
        socket_info(found_pid, found_fd, &peer) != 0) return -1;
    if (!sockets_match(&server, &peer) || !sockets_match(&current, &peer)) { errno = ENOTCONN; return -1; }
    return found_pid;
}
#endif

pid_t vc_socket_peer_pid(int fd, const char *const *paths, size_t path_count) {
    pid_t pid = 0;
    socklen_t size = sizeof(pid);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &size) == 0) {
        if (size != sizeof(pid) || pid <= 0) { errno = EINVAL; return -1; }
        return pid;
    }
#if !defined(__LP64__)
    if (errno == EOPNOTSUPP) {
        return vc_legacy_socket_peer_pid(fd, paths, path_count);
    }
#else
    (void)paths; (void)path_count;
#endif
    return -1;
}
