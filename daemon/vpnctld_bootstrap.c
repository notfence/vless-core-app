#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

extern char **environ;

static const char *kDaemonPortPath = "/var/run/vpnctld.port";
static const int kDaemonDefaultPort = 9093;
static const int kDaemonPortMax = 9113;

static int read_daemon_port(void) {
    FILE *fp = fopen(kDaemonPortPath, "r");
    if (!fp) return kDaemonDefaultPort;

    int port = 0;
    if (fscanf(fp, "%d", &port) != 1 || port <= 0 || port > 65535) {
        port = kDaemonDefaultPort;
    }
    fclose(fp);
    return port;
}

static int build_daemon_port_list(int *ports, int cap) {
    if (!ports || cap <= 0) return 0;

    int count = 0;
    int preferred = read_daemon_port();
    if (preferred > 0 && preferred <= 65535) {
        ports[count++] = preferred;
    }

    for (int p = kDaemonDefaultPort; p <= kDaemonPortMax && count < cap; p++) {
        if (p == preferred) continue;
        ports[count++] = p;
    }
    return count;
}

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
    int ports[64];
    int port_count = build_daemon_port_list(ports, (int)(sizeof(ports) / sizeof(ports[0])));

    for (int i = 0; i < port_count; i++) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) continue;

        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = inet_addr("127.0.0.1");
        sa.sin_port = htons((uint16_t)ports[i]);

        if (connect_with_timeout(fd, (struct sockaddr *)&sa, (socklen_t)sizeof(sa), 300) != 0) {
            close(fd);
            continue;
        }

        struct timeval tv;
        tv.tv_sec = 1;
        tv.tv_usec = 0;
        (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        const char probe[] = "STATUS\n";
        ssize_t wr = write(fd, probe, (size_t)(sizeof(probe) - 1));
        if (wr < 0) {
            close(fd);
            continue;
        }

        char reply[64];
        ssize_t rd = read(fd, reply, sizeof(reply) - 1);
        close(fd);
        if (rd <= 0) {
            continue;
        }

        reply[rd] = '\0';
        if (strncmp(reply, "OK ", 3) == 0) {
            return 1;
        }
    }
    return 0;
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
