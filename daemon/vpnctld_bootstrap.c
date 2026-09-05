#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1

#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include "vpnctld_protocol.h"

#define LAUNCHCTL_EXECUTABLE_PATH "/bin/launchctl"
#define VPNCTLD_LAUNCHD_LABEL "com.vlesscore.vpnctld"
#define VPNCTLD_LAUNCHD_PLIST "/Library/LaunchDaemons/com.vlesscore.vpnctld.plist"
#ifndef VPNCTLD_EXECUTABLE_PATH
#define VPNCTLD_EXECUTABLE_PATH "/usr/bin/vpnctld"
#endif

static char *const kSafeProcessEnvironment[] = {
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME=/var/root",
    "TMPDIR=/private/var/tmp",
    "LANG=C",
    NULL
};

static void close_inherited_descriptors(void) {
    long maximum = sysconf(_SC_OPEN_MAX);
    if (maximum < 0 || maximum > 4096) maximum = 4096;
    for (int fd = STDERR_FILENO + 1; fd < maximum; fd++) close(fd);
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

static int send_daemon_command(const char *command, char *reply, size_t reply_cap) {
    if (!command || !reply || reply_cap < 2) return -1;

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", VC_DAEMON_SOCKET_PATH);
    sa.sun_len = (uint8_t)SUN_LEN(&sa);

    if (connect_with_timeout(fd, (struct sockaddr *)&sa, (socklen_t)sa.sun_len, 300) != 0) {
        close(fd);
        return -2;
    }

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    size_t command_len = strlen(command);
    size_t written = 0;
    while (written < command_len) {
        ssize_t count = write(fd, command + written, command_len - written);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) {
            close(fd);
            return -1;
        }
        written += (size_t)count;
    }

    ssize_t rd;
    do {
        rd = read(fd, reply, reply_cap - 1);
    } while (rd < 0 && errno == EINTR);
    close(fd);
    if (rd <= 0) return -1;

    reply[rd] = '\0';
    return 0;
}

static int daemon_online(void) {
    char reply[64];
    int result = send_daemon_command("STATUS\n", reply, sizeof(reply));
    if (result == -2) return 0;
    if (result != 0) return -1;
    return strncmp(reply, "OK ", 3) == 0 ? 1 : -1;
}

static int run_launchctl(const char *command, const char *argument) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    sigset_t empty_signals;
    sigset_t default_signals;
    sigemptyset(&empty_signals);
    sigfillset(&default_signals);
    sigdelset(&default_signals, SIGKILL);
    sigdelset(&default_signals, SIGSTOP);
    posix_spawnattr_setsigmask(&attributes, &empty_signals);
    posix_spawnattr_setsigdefault(&attributes, &default_signals);
    posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

    char *argv[] = {
        LAUNCHCTL_EXECUTABLE_PATH,
        (char *)command,
        (char *)argument,
        NULL
    };

    pid_t pid = 0;
    int rc = posix_spawn(&pid,
                         LAUNCHCTL_EXECUTABLE_PATH,
                         &actions,
                         &attributes,
                         argv,
                         kSafeProcessEnvironment);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) return -1;

    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno == EINTR) continue;
        return -1;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : -1;
}

static int wait_for_daemon(void) {
    for (int i = 0; i < 20; i++) {
        usleep(100000);
        int status = daemon_online();
        if (status > 0) return 0;
        if (status < 0) return -1;
    }
    return -1;
}

static int spawn_fallback_daemon(void) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions,
                                     STDOUT_FILENO,
                                     "/var/log/vpnctld.log",
                                     O_WRONLY | O_CREAT | O_APPEND,
                                     0600);
    posix_spawn_file_actions_addopen(&actions,
                                     STDERR_FILENO,
                                     "/var/log/vpnctld.log",
                                     O_WRONLY | O_CREAT | O_APPEND,
                                     0600);

    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    sigset_t empty_signals;
    sigset_t default_signals;
    sigemptyset(&empty_signals);
    sigfillset(&default_signals);
    sigdelset(&default_signals, SIGKILL);
    sigdelset(&default_signals, SIGSTOP);
    posix_spawnattr_setsigmask(&attributes, &empty_signals);
    posix_spawnattr_setsigdefault(&attributes, &default_signals);
    posix_spawnattr_setflags(&attributes,
                             POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);

    char *argv[] = {
        VPNCTLD_EXECUTABLE_PATH,
        NULL
    };
    pid_t pid = 0;
    int rc = posix_spawn(&pid,
                         VPNCTLD_EXECUTABLE_PATH,
                         &actions,
                         &attributes,
                         argv,
                         kSafeProcessEnvironment);
    posix_spawnattr_destroy(&attributes);
    posix_spawn_file_actions_destroy(&actions);
    return rc == 0 ? 0 : -1;
}

static int start_launchd_daemon(void) {
    int launchd_manages_daemon =
        run_launchctl("list", VPNCTLD_LAUNCHD_LABEL) == 0;
    if (!launchd_manages_daemon) {
        (void)run_launchctl("load", VPNCTLD_LAUNCHD_PLIST);
        launchd_manages_daemon =
            run_launchctl("list", VPNCTLD_LAUNCHD_LABEL) == 0;
    }
    if (launchd_manages_daemon) {
        (void)run_launchctl("start", VPNCTLD_LAUNCHD_LABEL);
        return wait_for_daemon();
    }

    if (spawn_fallback_daemon() != 0) return -1;
    return wait_for_daemon();
}

int main(int argc, char **argv) {
    uid_t invoking_uid = getuid();
    int disconnect_requested = argc == 2 && strcmp(argv[1], "--disconnect") == 0;
    if ((argc != 1 && !disconnect_requested) || (disconnect_requested && invoking_uid != 0)) return 1;

    umask(0077);
    if (setgid(0) != 0 || setuid(0) != 0 || getegid() != 0 || geteuid() != 0) return 1;
    if (chdir("/") != 0) return 1;
    close_inherited_descriptors();

    if (disconnect_requested) {
        char reply[64];
        return send_daemon_command("DISCONNECT\n", reply, sizeof(reply)) == 0 &&
                       strncmp(reply, "OK disconnected", 15) == 0
                   ? 0
                   : 1;
    }

    int status = daemon_online();
    if (status > 0) {
        return 0;
    }
    if (status < 0) return 1;

    return start_launchd_daemon() == 0 ? 0 : 1;
}
