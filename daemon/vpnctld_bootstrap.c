#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

#include "vpnctld_protocol.h"

extern char **environ;

static int connect_with_timeout(int fd, const struct sockaddr *sa, socklen_t sa_len, int timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) return -1;
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) return -1;

    int rc = connect(fd, sa, sa_len);
    if (rc == 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return 0;
    }
    if (errno != EINPROGRESS) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (rc <= 0) {
        errno = (rc == 0) ? ETIMEDOUT : errno;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    int soerr = 0;
    socklen_t sl = (socklen_t)sizeof(soerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) != 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }
    if (soerr != 0) {
        errno = soerr;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    (void)fcntl(fd, F_SETFL, flags);
    return 0;
}

static int daemon_online(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return 0;

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", VC_DAEMON_SOCKET_PATH);
    sa.sun_len = (uint8_t)SUN_LEN(&sa);

    if (connect_with_timeout(fd, (struct sockaddr *)&sa, (socklen_t)sa.sun_len, 300) != 0) {
        close(fd);
        return 0;
    }

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    const char probe[] = "STATUS\n";
    if (write(fd, probe, (size_t)(sizeof(probe) - 1)) < 0) {
        close(fd);
        return 0;
    }

    char reply[64];
    ssize_t rd = read(fd, reply, sizeof(reply) - 1);
    close(fd);
    if (rd <= 0) return 0;

    reply[rd] = '\0';
    return strncmp(reply, "OK ", 3) == 0;
}

static int spawn_direct_daemon(void) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/var/log/vpnctld.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/var/log/vpnctld.log", O_WRONLY | O_CREAT | O_APPEND, 0644);

    char *argv[] = {
        "/usr/bin/vpnctld",
        NULL
    };

    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/usr/bin/vpnctld", &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    return rc == 0 ? 0 : -1;
}

int main(void) {
    (void)setgid(0);
    (void)setuid(0);

    if (daemon_online()) {
        return 0;
    }

    if (spawn_direct_daemon() == 0) {
        for (int i = 0; i < 20; i++) {
            usleep(100000);
            if (daemon_online()) {
                return 0;
            }
        }
    }

    return 1;
}
