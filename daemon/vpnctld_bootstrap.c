#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

extern char **environ;

static int daemon_online(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(9093);
    sa.sin_addr.s_addr = inet_addr("127.0.0.1");

    int ok = (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0);
    close(fd);
    return ok;
}

static int run_cmd(const char *cmd) {
    int rc = system(cmd);
    if (rc == -1) return -1;
    return rc;
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

    run_cmd("launchctl unload /Library/LaunchDaemons/com.vlesscore.vpnctld.plist >/dev/null 2>&1");
    run_cmd("launchctl load /Library/LaunchDaemons/com.vlesscore.vpnctld.plist >/dev/null 2>&1");
    usleep(500000);

    if (daemon_online()) {
        return 0;
    }

    if (spawn_direct_daemon() == 0) {
        usleep(500000);
        if (daemon_online()) {
            return 0;
        }
    }

    return 1;
}
