#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE 1

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <netdb.h>
#include <net/if.h>
#include <netinet/in.h>
#include <pthread.h>
#include <poll.h>
#include <pwd.h>
#include <grp.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "vpnicon_statusbar.h"
#include "vpnctld_protocol.h"
#include "system_proxy.h"
#include "core_config.h"
#include "socket_peer_pid.h"
#include "legacy_loopback.h"
#include "legacy_dns.h"
#include "../common/daemon_policy.h"
#include "../common/control_auth.h"
#include "../common/helper_monitor.h"
#include "../common/dns_relay.h"

#if __has_include(<net/pfvar.h>)
#include <net/pfvar.h>
#else
struct pf_addr {
    union {
        struct in_addr v4;
        struct in6_addr v6;
        uint8_t addr8[16];
        uint16_t addr16[8];
        uint32_t addr32[4];
    } pfa;
};
#ifndef v4
#define v4 pfa.v4
#endif
union pf_state_xport {
    uint16_t port;
    uint16_t call_id;
    uint32_t spi;
};
struct pfioc_natlook {
    struct pf_addr saddr;
    struct pf_addr daddr;
    struct pf_addr rsaddr;
    struct pf_addr rdaddr;
    union pf_state_xport sxport;
    union pf_state_xport dxport;
    union pf_state_xport rsxport;
    union pf_state_xport rdxport;
    sa_family_t af;
    uint8_t proto;
    uint8_t proto_variant;
    uint8_t direction;
};
#define PF_NATLOOK_USES_XPORT 1
#ifndef PF_IN
#define PF_IN 1
#endif
#ifndef PF_OUT
#define PF_OUT 2
#endif
#ifndef DIOCNATLOOK
#define DIOCNATLOOK _IOWR('D', 23, struct pfioc_natlook)
#endif
#endif

#if defined(PF_NATLOOK_USES_XPORT)
#define VC_NL_SET_SPORT(nl, value) ((nl).sxport.port = (value))
#define VC_NL_SET_DPORT(nl, value) ((nl).dxport.port = (value))
#define VC_NL_GET_RDPORT(nl) ((nl).rdxport.port)
#define VC_NL_GET_DPORT(nl) ((nl).dxport.port)
#define VC_NL_GET_RSPORT(nl) ((nl).rsxport.port)
#else
#define VC_NL_SET_SPORT(nl, value) ((nl).sport = (value))
#define VC_NL_SET_DPORT(nl, value) ((nl).dport = (value))
#define VC_NL_GET_RDPORT(nl) ((nl).rdport)
#define VC_NL_GET_DPORT(nl) ((nl).dport)
#define VC_NL_GET_RSPORT(nl) ((nl).rsport)
#endif

static char *const kSafeRootEnvironment[] = {
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME=/var/root",
    "TMPDIR=/private/var/tmp",
    "LANG=C",
    NULL
};

static char *const kSafeHelperEnvironment[] = {
    "PATH=/usr/bin:/bin:/usr/sbin:/sbin",
    "HOME=/var/mobile",
    "TMPDIR=/private/var/tmp",
    "LANG=C",
    "REDSOCKS_PF_BROKER=/var/run/vpnctld.sock",
    NULL
};

typedef enum {
    MODE_NONE = 0,
    MODE_PF = 1,
} vpn_mode_t;

typedef enum {
    PF_ENABLED_ERROR = -1,
    PF_DISABLED = 0,
    PF_ENABLED = 1,
} pf_enabled_state_t;

typedef enum {
    PF_ROOT_ERROR = -1,
    PF_ROOT_CONFLICT = -2,
    PF_ROOT_EMPTY = 0,
    PF_ROOT_OWN_DISPATCH = 1,
    PF_ROOT_SHARED_DISPATCH = 2,
} pf_root_state_t;

typedef struct {
    char ip[INET_ADDRSTRLEN];
    unsigned int references;
} route_bypass_entry_t;

typedef struct {
    int connected;
    time_t connected_since;
    int socks_port;
    int redir_port;
    int dns_port;
    pid_t core_pid;
    pid_t redsocks_pid;
    pid_t redsocks_log_relay_pid;
    pid_t dns_pid;
    vpn_mode_t mode;
    int pf_enabled_before;
    int pf_dispatch_installed;
    char server_ip[64];
    char server_ips[512];
    char download_ips[512];
    char bypass_ips[512];
    char routing[8192];
    int routing_bypass_lan;
    int protect_logs;
    int system_proxy_enabled;
    long long system_proxy_refresh_ms;
    long long loopback_check_ms;
    pid_t springboard_pid;
    pid_t springboard_candidate_pid;
    unsigned int springboard_candidate_polls;
    long long springboard_poll_ms;
    route_bypass_entry_t route_bypass[256];
} vpn_state_t;

static vpn_state_t g;
static const char *kStateDirectory = "/var/db/vless-core";
static const char *kPFPreviousStatePath = "/var/db/vless-core/pf-state";
static const char *kPFPreviousStateTempPath = "/var/db/vless-core/pf-state.tmp";
static const char *kLegacyPFPreviousStatePath = "/var/run/vlesscore-pf-previous-state";
static const char *kLegacyPFPreviousStateTempPath = "/var/run/vlesscore-pf-previous-state.tmp";
static volatile sig_atomic_t g_terminate = 0;
static int g_listen_fd = -1;
static int g_instance_lock_fd = -1;
static int g_vpn_icon_publisher_logged = 0;
static uid_t g_helper_uid = (uid_t)-1;
static gid_t g_helper_gid = (gid_t)-1;

#define DIAGNOSTIC_EVENT_CAPACITY 48
#define DIAGNOSTIC_EVENT_MESSAGE_CAPACITY 128

typedef struct {
    long long timestamp_ms;
    char message[DIAGNOSTIC_EVENT_MESSAGE_CAPACITY];
} diagnostic_event_t;

static diagnostic_event_t g_diagnostic_events[DIAGNOSTIC_EVENT_CAPACITY];
static size_t g_diagnostic_event_next = 0;
static size_t g_diagnostic_event_count = 0;

static void diagnostic_event(const char *fmt, ...) {
    if (!fmt) return;

    struct timeval tv;
    gettimeofday(&tv, NULL);
    diagnostic_event_t *event = &g_diagnostic_events[g_diagnostic_event_next];
    event->timestamp_ms = (long long)tv.tv_sec * 1000LL + (long long)(tv.tv_usec / 1000);

    va_list ap;
    va_start(ap, fmt);
    vsnprintf(event->message, sizeof(event->message), fmt, ap);
    va_end(ap);
    event->message[sizeof(event->message) - 1] = '\0';
    for (char *cursor = event->message; *cursor; cursor++) {
        if (*cursor == '\r' || *cursor == '\n' || *cursor == '\t') *cursor = ' ';
    }

    g_diagnostic_event_next = (g_diagnostic_event_next + 1) % DIAGNOSTIC_EVENT_CAPACITY;
    if (g_diagnostic_event_count < DIAGNOSTIC_EVENT_CAPACITY) g_diagnostic_event_count++;
}


typedef enum {
    CONTROL_AUTH_FAILURE_NONE = 0,
    CONTROL_AUTH_FAILURE_INVALID_ARGUMENTS,
    CONTROL_AUTH_FAILURE_PEER_PID,
    CONTROL_AUTH_FAILURE_ARGMAX_QUERY,
    CONTROL_AUTH_FAILURE_ARGMAX_VALUE,
    CONTROL_AUTH_FAILURE_NO_MEMORY,
    CONTROL_AUTH_FAILURE_PROCARGS_QUERY,
    CONTROL_AUTH_FAILURE_PROCARGS_FORMAT,
    CONTROL_AUTH_FAILURE_PATH_LENGTH,
    CONTROL_AUTH_FAILURE_PATH_MISMATCH,
    CONTROL_AUTH_FAILURE_TRUSTED_EXECUTABLE,
} control_auth_failure_t;

typedef struct {
    control_auth_failure_t failure;
    int error_number;
    pid_t peer_pid;
    char executable[PATH_MAX];
} control_auth_diagnostic_t;

static void stop_pid(pid_t *p);
static void finish_log_relay(pid_t *p);
static void truncate_log_file(const char *path);
static void clear_logs(void);
static void restart_system_dns_resolver(void);

#if defined(__GNUC__) || defined(__clang__)
#define VC_PRINTF_FORMAT(format_index, arguments_index) \
    __attribute__((format(printf, format_index, arguments_index)))
#else
#define VC_PRINTF_FORMAT(format_index, arguments_index)
#endif

static void log_msg(const char *fmt, ...) VC_PRINTF_FORMAT(1, 2);
static void log_warning(const char *fmt, ...) VC_PRINTF_FORMAT(1, 2);
static void log_error(const char *fmt, ...) VC_PRINTF_FORMAT(1, 2);
static void core_log_event(const char *level, const char *fmt, ...)
    VC_PRINTF_FORMAT(2, 3);

#undef VC_PRINTF_FORMAT

static void handle_term_signal(int sig) {
    (void)sig;
    g_terminate = 1;
    if (g_listen_fd >= 0) {
        close(g_listen_fd);
        g_listen_fd = -1;
    }
}

static void close_inherited_descriptors(void) {
    long maximum = sysconf(_SC_OPEN_MAX);
    if (maximum < 0 || maximum > 4096) maximum = 4096;
    for (int fd = STDERR_FILENO + 1; fd < maximum; fd++) close(fd);
}

static int load_helper_identity(void) {
    struct passwd *account = getpwnam("mobile");
    if (account == NULL || account->pw_uid == 0 || account->pw_gid == 0) return -1;
    g_helper_uid = account->pw_uid;
    g_helper_gid = account->pw_gid;
    return 0;
}

static int acquire_instance_lock(int wait_for_owner) {
    int fd = open(VC_DAEMON_LOCK_PATH, O_RDWR | O_CREAT | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || st.st_nlink != 1) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    if ((st.st_mode & 0777) != 0600 && fchmod(fd, 0600) != 0) {
        close(fd);
        return -1;
    }

    struct flock lock;
    memset(&lock, 0, sizeof(lock));
    lock.l_type = F_WRLCK;
    lock.l_whence = SEEK_SET;
    int command = wait_for_owner ? F_SETLKW : F_SETLK;
    while (fcntl(fd, command, &lock) != 0) {
        if (wait_for_owner && errno == EINTR) continue;
        int saved_errno = errno;
        close(fd);
        errno = saved_errno;
        return -1;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) != 0) {
        close(fd);
        return -1;
    }

    char owner[32];
    int owner_length = snprintf(owner, sizeof(owner), "%ld\n", (long)getpid());
    if (owner_length <= 0 || (size_t)owner_length >= sizeof(owner) ||
        ftruncate(fd, 0) != 0 || lseek(fd, 0, SEEK_SET) < 0 ||
        write(fd, owner, (size_t)owner_length) != owner_length) {
        close(fd);
        return -1;
    }
    return fd;
}

static int ensure_state_directory(void) {
    struct stat st;
    if (lstat(kStateDirectory, &st) != 0) {
        if (errno != ENOENT || mkdir(kStateDirectory, 0700) != 0 ||
            lstat(kStateDirectory, &st) != 0) {
            return -1;
        }
    }
    if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode) || st.st_uid != 0) return -1;
    if ((st.st_mode & 0777) != 0700 && chmod(kStateDirectory, 0700) != 0) return -1;
    return 0;
}

static int sync_state_directory(void) {
    int fd = open(kStateDirectory, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    struct stat st;
    int result = fstat(fd, &st) == 0 && S_ISDIR(st.st_mode) && fsync(fd) == 0 ? 0 : -1;
    close(fd);
    return result;
}

static int write_pf_previous_state(int was_enabled, int dispatch_installed) {
    if (ensure_state_directory() != 0) return -1;
    (void)unlink(kPFPreviousStateTempPath);
    int fd = open(kPFPreviousStateTempPath,
                  O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
                  0600);
    if (fd < 0) return -1;

    char state[64];
    int state_length = snprintf(state,
                                sizeof(state),
                                "v2\nenabled=%d\ndispatch=%d\n",
                                was_enabled ? 1 : 0,
                                dispatch_installed ? 1 : 0);
    if (state_length <= 0 || (size_t)state_length >= sizeof(state)) {
        close(fd);
        (void)unlink(kPFPreviousStateTempPath);
        return -1;
    }
    size_t offset = 0;
    while (offset < (size_t)state_length) {
        ssize_t count = write(fd, state + offset, (size_t)state_length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset += (size_t)count;
    }
    int result = offset == (size_t)state_length && fsync(fd) == 0 ? 0 : -1;
    if (close(fd) != 0) result = -1;
    if (result == 0 && rename(kPFPreviousStateTempPath, kPFPreviousStatePath) != 0) {
        result = -1;
    }
    if (result == 0 && sync_state_directory() != 0) result = -1;
    if (result != 0) (void)unlink(kPFPreviousStateTempPath);
    if (result == 0) (void)unlink(kLegacyPFPreviousStatePath);
    return result;
}

static int read_pf_previous_state_file(const char *path,
                                       int *was_enabled,
                                       int *dispatch_installed) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? 1 : -1;

    struct stat st;
    char state[64] = {0};
    ssize_t count = -1;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == 0 &&
        st.st_nlink == 1 && st.st_size > 0 && st.st_size < (off_t)sizeof(state)) {
        do {
            count = read(fd, state, (size_t)st.st_size);
        } while (count < 0 && errno == EINTR);
    }
    close(fd);
    if (count == 2 && state[1] == '\n' && (state[0] == '0' || state[0] == '1')) {
        *was_enabled = state[0] == '1';
        *dispatch_installed = -1;
        return 0;
    }

    for (int enabled = 0; enabled <= 1; enabled++) {
        for (int dispatch = 0; dispatch <= 1; dispatch++) {
            char expected[64];
            int expected_length = snprintf(expected,
                                           sizeof(expected),
                                           "v2\nenabled=%d\ndispatch=%d\n",
                                           enabled,
                                           dispatch);
            if (expected_length == count && memcmp(state, expected, (size_t)count) == 0) {
                *was_enabled = enabled;
                *dispatch_installed = dispatch;
                return 0;
            }
        }
    }
    return -1;
}

static int read_pf_previous_state(int *was_enabled, int *dispatch_installed) {
    int result = read_pf_previous_state_file(kPFPreviousStatePath,
                                             was_enabled,
                                             dispatch_installed);
    if (result != 1) return result;
    return read_pf_previous_state_file(kLegacyPFPreviousStatePath,
                                       was_enabled,
                                       dispatch_installed);
}

static int remove_pf_previous_state(void) {
    int result = 0;
    if (unlink(kPFPreviousStatePath) == 0) {
        if (sync_state_directory() != 0) result = -1;
    } else if (errno != ENOENT) {
        result = -1;
    }
    if (unlink(kLegacyPFPreviousStatePath) != 0 && errno != ENOENT) result = -1;
    return result;
}

static int drop_helper_privileges(void) {
    if (g_helper_uid == (uid_t)-1 || g_helper_gid == (gid_t)-1) return -1;
    gid_t groups[1] = {g_helper_gid};
    if (setgroups(1, groups) != 0 || setgid(g_helper_gid) != 0 || setuid(g_helper_uid) != 0) return -1;
    return geteuid() == g_helper_uid && getegid() == g_helper_gid ? 0 : -1;
}

static int log_token_equals(const char *token, size_t length, const char *expected) {
    return token && expected && strlen(expected) == length &&
           strncmp(token, expected, length) == 0;
}

static const char *child_log_record(const char *component, const char *line,
                                    const char **level_out) {
    const char *payload = line ? line : "";
    const char *level = "I";
    if (component && strcmp(component, "redsocks") == 0 && isdigit((unsigned char)*payload)) {
        const char *cursor = payload;
        while (isdigit((unsigned char)*cursor)) cursor++;
        if (*cursor == '.') {
            cursor++;
            while (isdigit((unsigned char)*cursor)) cursor++;
            if (*cursor == ' ') {
                while (*cursor == ' ') cursor++;
                const char *priority = cursor;
                while (*cursor && *cursor != ' ') cursor++;
                size_t priority_length = (size_t)(cursor - priority);
                const char *priority_level = "I";
                if (log_token_equals(priority, priority_length, "emerg") ||
                    log_token_equals(priority, priority_length, "alert") ||
                    log_token_equals(priority, priority_length, "crit") ||
                    log_token_equals(priority, priority_length, "err")) {
                    priority_level = "E";
                } else if (log_token_equals(priority, priority_length, "warning")) {
                    priority_level = "W";
                } else if (log_token_equals(priority, priority_length, "notice") ||
                           log_token_equals(priority, priority_length, "info")) {
                    priority_level = "I";
                } else if (log_token_equals(priority, priority_length, "debug")) {
                    priority_level = "D";
                }
                while (*cursor == ' ') cursor++;
                if (*cursor) payload = cursor;
                level = priority_level;
            }
        }
    }
    if (level_out) *level_out = level;
    return payload;
}

static void format_log_timestamp(char *destination, size_t capacity) {
    if (!destination || capacity == 0) return;
    struct timeval tv;
    gettimeofday(&tv, NULL);
    unsigned int milliseconds = (unsigned int)(tv.tv_usec / 1000);
    time_t seconds = tv.tv_sec;
    struct tm local_time;
    char calendar[24];
    if (localtime_r(&seconds, &local_time) == NULL ||
        strftime(calendar, sizeof(calendar), "%Y-%m-%d %H:%M:%S", &local_time) == 0) {
        snprintf(destination, capacity, "%ld.%03u",
                 (long)tv.tv_sec, milliseconds);
        return;
    }
    snprintf(destination, capacity, "%s.%03u", calendar, milliseconds);
}

static void sanitize_log_message(const char *source, char *destination, size_t capacity) {
    if (!destination || capacity == 0) return;
    size_t used = 0;
    if (source) {
        while (*source && used + 1 < capacity) {
            unsigned char byte = (unsigned char)*source++;
            destination[used++] = (byte < 0x20 || byte == 0x7f) ? ' ' : (char)byte;
        }
    }
    while (used > 0 && destination[used - 1] == ' ') used--;
    destination[used] = '\0';
}

static int write_log_record_fd(int fd, const char *component,
                               const char *level, const char *message) {
    char timestamp[40];
    char safe_message[3072];
    char record[3328];
    format_log_timestamp(timestamp, sizeof(timestamp));
    sanitize_log_message(message, safe_message, sizeof(safe_message));

    int length;
    if (component && *component) {
        length = snprintf(record, sizeof(record), "%s %s [%s] %s\n",
                          timestamp,
                          level && *level ? level : "I",
                          component,
                          safe_message);
    } else {
        length = snprintf(record, sizeof(record), "%s %s %s\n",
                          timestamp,
                          level && *level ? level : "I",
                          safe_message);
    }
    if (length <= 0) return -1;
    size_t remaining = (size_t)length < sizeof(record) ? (size_t)length : sizeof(record) - 1;
    size_t offset = 0;
    while (offset < remaining) {
        ssize_t written = write(fd, record + offset, remaining - offset);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return -1;
        offset += (size_t)written;
    }
    return 0;
}

static void format_log_message(char *destination, size_t capacity,
                               const char *format, va_list arguments) {
    if (!destination || capacity == 0) return;
    destination[0] = '\0';
    int length = vsnprintf(destination, capacity, format, arguments);
    if (length < 0) {
        snprintf(destination, capacity, "log message formatting failed");
    } else if ((size_t)length >= capacity && capacity >= 4) {
        memcpy(destination + capacity - 4, "...", 3);
        destination[capacity - 1] = '\0';
    }
}

static void log_vmessage(const char *level, const char *fmt, va_list ap) {
    if (g.protect_logs || !fmt) return;
    int saved_errno = errno;
    char message[2048];
    format_log_message(message, sizeof(message), fmt, ap);
    (void)write_log_record_fd(STDERR_FILENO, NULL, level, message);
    errno = saved_errno;
}

static void log_msg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_vmessage("I", fmt, ap);
    va_end(ap);
}

static void log_warning(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_vmessage("W", fmt, ap);
    va_end(ap);
}

static void log_error(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    log_vmessage("E", fmt, ap);
    va_end(ap);
}

static void core_log_event(const char *level, const char *fmt, ...) {
    if (g.protect_logs || !fmt) return;
    char message[1024];
    va_list ap;
    va_start(ap, fmt);
    format_log_message(message, sizeof(message), fmt, ap);
    va_end(ap);

    int fd = open("/var/log/vless-core.log",
                  O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW,
                  0600);
    if (fd < 0) return;
    (void)fchmod(fd, 0600);
    (void)write_log_record_fd(fd, "session", level, message);
    close(fd);
}

static void log_argv_command(const char *prefix, char *const argv[]) {
    char line[1024];
    line[0] = '\0';
    if (prefix && *prefix) {
        strncat(line, prefix, sizeof(line) - strlen(line) - 1);
        strncat(line, ": ", sizeof(line) - strlen(line) - 1);
    }

    for (int i = 0; argv && argv[i]; i++) {
        if (i > 0) strncat(line, " ", sizeof(line) - strlen(line) - 1);
        strncat(line, argv[i], sizeof(line) - strlen(line) - 1);
    }

    log_msg("%s", line);
}

static int wait_spawned(pid_t pid, const char *label) {
    int status = 0;
    pid_t rc = 0;
    do {
        rc = waitpid(pid, &status, 0);
    } while (rc < 0 && errno == EINTR);

    if (rc < 0) {
        log_error("%s: waitpid errno=%d", label ? label : "run", errno);
        return -1;
    }
    if (WIFEXITED(status)) {
        int st = WEXITSTATUS(status);
        if (st == 0) {
            log_msg("%s: rc=%d", label ? label : "run", st);
        } else {
            log_error("%s: rc=%d", label ? label : "run", st);
        }
        return st;
    }

    log_error("%s: abnormal exit", label ? label : "run");
    return -1;
}

static int run_argv(char *const argv[]) {
    if (!argv || !argv[0]) return -1;

    log_argv_command("run", argv);

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], &actions, NULL, argv, kSafeRootEnvironment);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) {
        log_error("run: spawn errno=%d", rc);
        return -1;
    }

    return wait_spawned(pid, "run");
}

static int wait_spawned_quiet(pid_t pid) {
    int status = 0;
    pid_t rc = 0;
    do {
        rc = waitpid(pid, &status, 0);
    } while (rc < 0 && errno == EINTR);
    return rc == pid && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static int run_argv_capture_impl(char *const argv[], char *out, size_t out_cap, int verbose) {
    if (!argv || !argv[0] || !out || out_cap == 0) return -1;
    out[0] = '\0';

    if (verbose) log_argv_command("run", argv);

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        if (verbose) log_error("run: pipe errno=%d", errno);
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], &actions, NULL, argv, kSafeRootEnvironment);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    if (rc != 0) {
        close(pipefd[0]);
        if (verbose) log_error("run: spawn errno=%d", rc);
        return -1;
    }

    size_t used = 0;
    for (;;) {
        char buf[512];
        ssize_t rd = read(pipefd[0], buf, sizeof(buf));
        if (rd < 0) {
            if (errno == EINTR) continue;
            close(pipefd[0]);
            if (verbose) {
                (void)wait_spawned(pid, "run");
                log_error("run: read errno=%d", errno);
            } else {
                (void)wait_spawned_quiet(pid);
            }
            return -1;
        }
        if (rd == 0) break;

        if (used + 1 < out_cap) {
            size_t copy = (size_t)rd;
            if (copy > out_cap - used - 1) {
                copy = out_cap - used - 1;
            }
            memcpy(out + used, buf, copy);
            used += copy;
            out[used] = '\0';
        }
    }
    close(pipefd[0]);

    return verbose ? wait_spawned(pid, "run") : wait_spawned_quiet(pid);
}

static int run_argv_capture(char *const argv[], char *out, size_t out_cap) {
    return run_argv_capture_impl(argv, out, out_cap, 1);
}

static int run_argv_capture_quiet(char *const argv[], char *out, size_t out_cap) {
    return run_argv_capture_impl(argv, out, out_cap, 0);
}

static int can_exec(const char *path) {
    return access(path, X_OK) == 0;
}

static int path_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static int process_executable_path(pid_t pid,
                                   char *path,
                                   size_t path_cap,
                                   control_auth_diagnostic_t *diagnostic) {
    if (pid <= 0 || !path || path_cap == 0) {
        if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_INVALID_ARGUMENTS;
        return -1;
    }

    int argmax_mib[2] = { CTL_KERN, KERN_ARGMAX };
    int argmax = 0;
    size_t argmax_size = sizeof(argmax);
    int argmax_rc = sysctl(argmax_mib, 2, &argmax, &argmax_size, NULL, 0);
    if (argmax_rc != 0) {
        if (diagnostic) {
            diagnostic->failure = CONTROL_AUTH_FAILURE_ARGMAX_QUERY;
            diagnostic->error_number = errno;
        }
        return -1;
    }
    if (argmax <= (int)sizeof(int) || argmax > 1024 * 1024) {
        if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_ARGMAX_VALUE;
        return -1;
    }

    char *arguments = (char *)calloc(1, (size_t)argmax);
    if (!arguments) {
        if (diagnostic) {
            diagnostic->failure = CONTROL_AUTH_FAILURE_NO_MEMORY;
            diagnostic->error_number = ENOMEM;
        }
        return -1;
    }

    int process_mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    size_t arguments_size = (size_t)argmax;
    int rc = sysctl(process_mib, 3, arguments, &arguments_size, NULL, 0);
    if (rc != 0) {
        if (diagnostic) {
            diagnostic->failure = CONTROL_AUTH_FAILURE_PROCARGS_QUERY;
            diagnostic->error_number = errno;
        }
        free(arguments);
        return -1;
    }
    if (arguments_size <= sizeof(int)) {
        if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_PROCARGS_FORMAT;
        free(arguments);
        return -1;
    }

    const char *executable = arguments + sizeof(int);
    size_t available = arguments_size - sizeof(int);
    const char *terminator = (const char *)memchr(executable, '\0', available);
    if (!terminator) {
        if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_PROCARGS_FORMAT;
        free(arguments);
        return -1;
    }

    size_t length = (size_t)(terminator - executable);
    if (length == 0 || length >= path_cap) {
        if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_PATH_LENGTH;
        free(arguments);
        return -1;
    }
    memcpy(path, executable, length);
    path[length] = '\0';
    free(arguments);
    return 0;
}

static int executable_path_matches(const char *actual,
                                   const char *expected,
                                   int *trust_error) {
    const VCControlAuthOperations operations = {realpath, stat};
    return VCExecutablePathMatches(actual, expected, trust_error, &operations);
}

static control_client_t control_client_type(int client_fd,
                                            control_auth_diagnostic_t *diagnostic) {
    if (diagnostic) memset(diagnostic, 0, sizeof(*diagnostic));
    const char *expected_paths[] = {
        VC_APP_EXECUTABLE_PATH,
        VC_BOOTSTRAP_EXECUTABLE_PATH,
        VC_CORE_EXECUTABLE_PATH,
        VC_REDSOCKS_EXECUTABLE_PATH,
    };
    pid_t peer_pid = vc_socket_peer_pid(client_fd, expected_paths,
                                      sizeof(expected_paths) / sizeof(expected_paths[0]));
    if (peer_pid <= 0) {
        if (diagnostic) {
            diagnostic->failure = CONTROL_AUTH_FAILURE_PEER_PID;
            diagnostic->error_number = errno;
            diagnostic->peer_pid = peer_pid;
        }
        return CONTROL_CLIENT_UNAUTHORIZED;
    }
    if (diagnostic) diagnostic->peer_pid = peer_pid;

    char executable[PATH_MAX];
    if (process_executable_path(peer_pid,
                                executable,
                                sizeof(executable),
                                diagnostic) != 0) {
        return CONTROL_CLIENT_UNAUTHORIZED;
    }
    if (diagnostic) snprintf(diagnostic->executable,
                             sizeof(diagnostic->executable),
                             "%s",
                             executable);
    const control_client_t expected_clients[] = {
        CONTROL_CLIENT_APP,
        CONTROL_CLIENT_BOOTSTRAP,
        CONTROL_CLIENT_CORE,
        CONTROL_CLIENT_REDSOCKS,
    };
    for (size_t index = 0; index < sizeof(expected_paths) / sizeof(expected_paths[0]); index++) {
        int trust_error = 0;
        int match = executable_path_matches(executable, expected_paths[index], &trust_error);
        if (match > 0) return expected_clients[index];
        if (match < 0) {
            if (diagnostic) {
                diagnostic->failure = CONTROL_AUTH_FAILURE_TRUSTED_EXECUTABLE;
                diagnostic->error_number = trust_error;
            }
            return CONTROL_CLIENT_UNAUTHORIZED;
        }
    }
    if (diagnostic) diagnostic->failure = CONTROL_AUTH_FAILURE_PATH_MISMATCH;
    return CONTROL_CLIENT_UNAUTHORIZED;
}

static const char *control_auth_failure_name(control_auth_failure_t failure) {
    switch (failure) {
        case CONTROL_AUTH_FAILURE_INVALID_ARGUMENTS: return "invalid_arguments";
        case CONTROL_AUTH_FAILURE_PEER_PID: return "peer_pid";
        case CONTROL_AUTH_FAILURE_ARGMAX_QUERY: return "argmax_query";
        case CONTROL_AUTH_FAILURE_ARGMAX_VALUE: return "argmax_value";
        case CONTROL_AUTH_FAILURE_NO_MEMORY: return "no_memory";
        case CONTROL_AUTH_FAILURE_PROCARGS_QUERY: return "procargs_query";
        case CONTROL_AUTH_FAILURE_PROCARGS_FORMAT: return "procargs_format";
        case CONTROL_AUTH_FAILURE_PATH_LENGTH: return "path_length";
        case CONTROL_AUTH_FAILURE_PATH_MISMATCH: return "path_mismatch";
        case CONTROL_AUTH_FAILURE_TRUSTED_EXECUTABLE: return "trusted_executable";
        default: return "unknown";
    }
}

static void sanitize_control_text(const char *source, char *destination, size_t capacity) {
    if (!destination || capacity == 0) return;
    size_t used = 0;
    if (source) {
        while (*source && used + 1 < capacity) {
            unsigned char byte = (unsigned char)*source++;
            destination[used++] = (byte < 0x20 || byte == 0x7f) ? '?' : (char)byte;
        }
    }
    destination[used] = '\0';
}

static const char *control_executable_class(const char *path) {
    if (!path || !*path) return "unavailable";
    if (strstr(path, "/private/var/db/stash/") || strstr(path, "/var/stash/")) return "stash";
    if (strstr(path, "/var/jb/")) return "rootless";
    if (strstr(path, "/Containers/Bundle/Application/")) return "app_container";
    if (strstr(path, "/Applications/")) return "applications";
    return "other";
}

static int should_record_auth_failure(control_auth_failure_t failure) {
    static control_auth_failure_t previous_failure = CONTROL_AUTH_FAILURE_NONE;
    static long long previous_timestamp_ms = 0;
    struct timeval now;
    gettimeofday(&now, NULL);
    long long timestamp_ms = (long long)now.tv_sec * 1000LL + (long long)(now.tv_usec / 1000);
    if (failure == previous_failure && timestamp_ms - previous_timestamp_ms < 60000LL) return 0;
    previous_failure = failure;
    previous_timestamp_ms = timestamp_ms;
    return 1;
}

static const char *mode_name(vpn_mode_t mode) {
    switch (mode) {
        case MODE_PF: return vc_legacy_loopback_active() ? "pf+loopback+redsocks" : "pf+redsocks";
        default: return "none";
    }
}

static const char *find_pfctl_bin(void) {
    if (can_exec("/sbin/pfctl")) return "/sbin/pfctl";
    if (can_exec("/usr/sbin/pfctl")) return "/usr/sbin/pfctl";
    if (can_exec("/bin/pfctl")) return "/bin/pfctl";
    if (can_exec("/usr/bin/pfctl")) return "/usr/bin/pfctl";

    return NULL;
}

static const char *find_route_bin(void) {
    if (can_exec("/sbin/route")) return "/sbin/route";
    if (can_exec("/usr/sbin/route")) return "/usr/sbin/route";
    if (can_exec("/bin/route")) return "/bin/route";
    if (can_exec("/usr/bin/route")) return "/usr/bin/route";

    return NULL;
}

static const char *find_ifconfig_bin(void) {
    if (can_exec("/sbin/ifconfig")) return "/sbin/ifconfig";
    if (can_exec("/usr/sbin/ifconfig")) return "/usr/sbin/ifconfig";
    if (can_exec("/bin/ifconfig")) return "/bin/ifconfig";
    if (can_exec("/usr/bin/ifconfig")) return "/usr/bin/ifconfig";

    return NULL;
}

static const char *find_redsocks_bin(void) {
    if (can_exec("/usr/bin/redsocks-vless-core")) return "/usr/bin/redsocks-vless-core";
    return NULL;
}

static const char *find_vless_core_bin(void) {
    if (can_exec(VC_CORE_EXECUTABLE_PATH)) return VC_CORE_EXECUTABLE_PATH;
    return NULL;
}

static int pick_free_port_range(int start, int end) {
    for (int p = start; p <= end; p++) {
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return -1;

        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = inet_addr("127.0.0.1");
        sa.sin_port = htons((uint16_t)p);

        int ok = bind(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0;
        close(fd);
        if (ok) return p;
    }
    return -1;
}

static int bind_udp_loopback_range(int start, int end, int *port_out) {
    if (port_out) *port_out = 0;

    for (int p = start; p <= end; p++) {
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) return -1;

        int one = 1;
        (void)setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = inet_addr("127.0.0.1");
        sa.sin_port = htons((uint16_t)p);

        if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
            if (port_out) *port_out = p;
            return fd;
        }

        close(fd);
    }

    return -1;
}

static int pick_port(int requested) {
    if (requested > 0) {
        return pick_free_port_range(requested, requested);
    }
    return pick_free_port_range(1083, 1183);
}








static int routing_payload_valid(const char *text, int *bypass_lan_out) {
    return routing_payload_valid_with_capacity(text, bypass_lan_out, sizeof(g.routing));
}

static int ipv4_is_permanent_bypass(const char *ip) {
    return ipv4_is_permanent_bypass_for_policy(ip, g.bypass_ips, g.routing_bypass_lan);
}

static int pf_table_change(const char *operation, const char *ip) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return -1;
    char *argv[] = {
        (char *)pfctl,
        "-a",
        "vlesscore",
        "-t",
        "vlesscore_bypass",
        "-T",
        (char *)operation,
        (char *)ip,
        NULL,
    };
    return run_argv(argv);
}

static int route_direct_reference(const char *ip, int add) {
    struct in_addr address;
    if (!g.connected || inet_pton(AF_INET, ip, &address) != 1) {
        return -1;
    }
    if (ipv4_is_permanent_bypass(ip)) {
        return 0;
    }

    route_bypass_entry_t *free_entry = NULL;
    for (size_t i = 0; i < sizeof(g.route_bypass) / sizeof(g.route_bypass[0]); i++) {
        route_bypass_entry_t *entry = &g.route_bypass[i];
        if (entry->ip[0] == '\0') {
            if (!free_entry) free_entry = entry;
            continue;
        }
        if (strcmp(entry->ip, ip) != 0) continue;

        if (add) {
            entry->references++;
            log_msg("routing direct bypass retained ip=%s refs=%u", ip, entry->references);
            return 0;
        }
        if (entry->references > 1) {
            entry->references--;
            log_msg("routing direct bypass released ip=%s refs=%u", ip, entry->references);
            return 0;
        }
        if (vc_legacy_loopback_direct(ip, 0) != 0 || pf_table_change("delete", ip) != 0) {
            return -1;
        }
        memset(entry, 0, sizeof(*entry));
        log_msg("routing direct bypass removed ip=%s", ip);
        return 0;
    }

    if (!add) return 0;
    if (!free_entry || vc_legacy_loopback_direct(ip, 1) != 0) {
        return -1;
    }
    if (pf_table_change("add", ip) != 0) {
        (void)vc_legacy_loopback_direct(ip, 0);
        return -1;
    }
    snprintf(free_entry->ip, sizeof(free_entry->ip), "%s", ip);
    free_entry->references = 1;
    log_msg("routing direct bypass added ip=%s", ip);
    return 0;
}

static long long now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return ((long long)tv.tv_sec * 1000LL) + ((long long)tv.tv_usec / 1000LL);
}

static int resolve_host_ipv4_all(const char *host, char *first_ip, size_t first_ip_cap, char *ip_list, size_t ip_list_cap) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    if (first_ip_cap > 0) first_ip[0] = '\0';
    if (ip_list_cap > 0) ip_list[0] = '\0';

    struct addrinfo *res = NULL;
    int rc = getaddrinfo(host, NULL, &hints, &res);
    if (rc != 0 || !res) {
        return -1;
    }

    int got = 0;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        if (!ai->ai_addr) continue;

        struct sockaddr_in *sa = (struct sockaddr_in *)ai->ai_addr;
        char ip[64];
        const char *p = inet_ntop(AF_INET, &sa->sin_addr, ip, (socklen_t)sizeof(ip));
        if (!p) continue;

        if (!got) {
            if (strlen(ip) >= first_ip_cap) {
                freeaddrinfo(res);
                return -1;
            }
            snprintf(first_ip, first_ip_cap, "%s", ip);
            got = 1;
        }

        if (ip_list_append(ip_list, ip_list_cap, ip) != 0) {
            freeaddrinfo(res);
            return -1;
        }
    }

    freeaddrinfo(res);
    if (!got) return -1;

    if (ip_list[0] == '\0') {
        if (strlen(first_ip) >= ip_list_cap) return -1;
        snprintf(ip_list, ip_list_cap, "%s", first_ip);
    }
    return 0;
}

typedef struct {
    int rc;
    char first_ip[64];
    char ip_list[512];
} resolve_result_t;

static void reap_child_briefly(pid_t pid) {
    int status = 0;
    for (int i = 0; i < 20; i++) {
        pid_t wr = waitpid(pid, &status, WNOHANG);
        if (wr == pid) return;
        if (wr < 0 && errno != EINTR) return;
        usleep(50000);
    }
}

static int read_resolve_result_timeout(int fd, resolve_result_t *out, int timeout_ms) {
    unsigned char *p = (unsigned char *)out;
    size_t got = 0;
    uint64_t deadline = vc_core_now_ms() + (unsigned)timeout_ms;

    while (got < sizeof(*out)) {
        uint64_t now = vc_core_now_ms();
        if (now >= deadline) return -2;
        uint64_t remaining = deadline - now;
        struct pollfd socket = {.fd=fd, .events=POLLIN};
        int sr = poll(&socket, 1, remaining > INT_MAX ? INT_MAX : (int)remaining);
        if (sr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (sr == 0) return -2;

        ssize_t n = read(fd, p + got, sizeof(*out) - got);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (n == 0) return -1;
        got += (size_t)n;
    }

    return 0;
}

static int resolve_host_ipv4_all_bounded(const char *host, char *first_ip, size_t first_ip_cap, char *ip_list, size_t ip_list_cap,
                                         int timeout_ms) {
    struct in_addr literal_addr;
    if (inet_pton(AF_INET, host, &literal_addr) == 1) {
        if (strlen(host) >= first_ip_cap || strlen(host) >= ip_list_cap) return -1;
        snprintf(first_ip, first_ip_cap, "%s", host);
        snprintf(ip_list, ip_list_cap, "%s", host);
        return 0;
    }

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        log_error("resolver pipe failed errno=%d", errno);
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        log_error("resolver fork failed errno=%d", errno);
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        close(pipefd[0]);

        resolve_result_t result;
        memset(&result, 0, sizeof(result));
        result.rc = resolve_host_ipv4_all(host, result.first_ip, sizeof(result.first_ip), result.ip_list, sizeof(result.ip_list));
        (void)write(pipefd[1], &result, sizeof(result));
        close(pipefd[1]);
        _exit(0);
    }

    close(pipefd[1]);

    resolve_result_t result;
    memset(&result, 0, sizeof(result));
    int rc = read_resolve_result_timeout(pipefd[0], &result, timeout_ms);
    close(pipefd[0]);

    if (rc == -2) {
        kill(pid, SIGKILL);
        reap_child_briefly(pid);
        return -2;
    }

    reap_child_briefly(pid);
    if (rc != 0 || result.rc != 0) return -1;
    if (strlen(result.first_ip) >= first_ip_cap || strlen(result.ip_list) >= ip_list_cap) return -1;

    snprintf(first_ip, first_ip_cap, "%s", result.first_ip);
    snprintf(ip_list, ip_list_cap, "%s", result.ip_list);
    return 0;
}

static int read_default_interface(char *ifname, size_t ifname_cap) {
    const char *route = find_route_bin();
    if (!route) return -1;

    char output[2048];
    char *argv[] = {
        (char *)route,
        "-n",
        "get",
        "default",
        NULL,
    };
    if (run_argv_capture(argv, output, sizeof(output)) != 0) {
        return -1;
    }

    int found = -1;
    char *save = NULL;
    for (char *line = strtok_r(output, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
        char *p = strstr(line, "interface:");
        if (!p) continue;

        p += 10;
        while (*p == ' ' || *p == '\t') p++;

        char *e = p;
        while (*e && *e != '\n' && *e != ' ' && *e != '\t') e++;
        *e = '\0';

        if (strlen(p) > 0 && strlen(p) < ifname_cap) {
            snprintf(ifname, ifname_cap, "%s", p);
            found = 0;
            break;
        }
    }

    return found;
}


static int ifname_exists(const char *ifname) {
    if (!ifname || !*ifname) return 0;
    return if_nametoindex(ifname) != 0;
}


static int add_pf_interface(char ifnames[][32], size_t *count, size_t cap, const char *ifname) {
    if (!ifnames || !count || !ifname) return 0;
    if (!ifname_is_safe(ifname)) return 0;
    if (!pf_interface_allowed(ifname)) return 0;
    if (!ifname_exists(ifname)) return 0;

    for (size_t i = 0; i < *count; i++) {
        if (strcmp(ifnames[i], ifname) == 0) return 0;
    }

    if (*count >= cap) return -1;
    snprintf(ifnames[*count], 32, "%s", ifname);
    (*count)++;
    return 0;
}

static size_t collect_pf_interfaces(char ifnames[][32], size_t cap) {
    if (!ifnames || cap == 0) return 0;

    size_t count = 0;
    const char *ifconfig = find_ifconfig_bin();
    if (ifconfig) {
        char output[4096];
        char *argv[] = {
            (char *)ifconfig,
            "-l",
            NULL,
        };
        if (run_argv_capture(argv, output, sizeof(output)) == 0) {
            char *save = NULL;
            for (char *tok = strtok_r(output, " \t\r\n", &save); tok; tok = strtok_r(NULL, " \t\r\n", &save)) {
                if (add_pf_interface(ifnames, &count, cap, tok) != 0) break;
            }
        }
    }

    char def_if[32];
    memset(def_if, 0, sizeof(def_if));
    if (read_default_interface(def_if, sizeof(def_if)) == 0) {
        (void)add_pf_interface(ifnames, &count, cap, def_if);
    }

    (void)add_pf_interface(ifnames, &count, cap, "en0");
    (void)add_pf_interface(ifnames, &count, cap, "pdp_ip0");
    (void)add_pf_interface(ifnames, &count, cap, "pdp_ip1");

    return count;
}

static int interface_list_has_prefix(char ifnames[][32], size_t if_count, const char *prefix) {
    if (!ifnames || !prefix || !*prefix) return 0;
    size_t n = strlen(prefix);
    for (size_t i = 0; i < if_count; i++) {
        if (strncmp(ifnames[i], prefix, n) == 0) return 1;
    }
    return 0;
}

static int write_all_fd(int fd, const void *data, size_t length) {
    const uint8_t *cursor = (const uint8_t *)data;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return -1;
        cursor += (size_t)written;
        length -= (size_t)written;
    }
    return 0;
}

static void send_log_tail(int client_fd, const char *path) {
    static const size_t maximum_tail = 32768;
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0) {
        if (fd >= 0) close(fd);
        (void)write_all_fd(client_fd, "ERR cannot read log\n", 20);
        return;
    }

    off_t start = st.st_size > (off_t)maximum_tail ? st.st_size - (off_t)maximum_tail : 0;
    if (start > 0) {
        char previous = '\0';
        ssize_t previous_count;
        if (lseek(fd, start - 1, SEEK_SET) < 0) {
            close(fd);
            return;
        }
        do {
            previous_count = read(fd, &previous, 1);
        } while (previous_count < 0 && errno == EINTR);
        if (previous_count != 1) {
            close(fd);
            return;
        }
        if (previous != '\n') {
            char byte = '\0';
            int found_newline = 0;
            for (;;) {
                ssize_t count = read(fd, &byte, 1);
                if (count < 0 && errno == EINTR) continue;
                if (count != 1) break;
                if (byte == '\n') {
                    found_newline = 1;
                    break;
                }
            }
            if (!found_newline && lseek(fd, start, SEEK_SET) < 0) {
                close(fd);
                return;
            }
        }
    } else if (lseek(fd, 0, SEEK_SET) < 0) {
        close(fd);
        return;
    }
    if (write_all_fd(client_fd, "OK\n", 3) != 0) {
        close(fd);
        return;
    }

    char buffer[2048];
    for (;;) {
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0 || write_all_fd(client_fd, buffer, (size_t)count) != 0) break;
    }
    close(fd);
}

static int read_exact_fd(int fd, void *data, size_t length) {
    uint8_t *cursor = (uint8_t *)data;
    while (length > 0) {
        ssize_t count = read(fd, cursor, length);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        cursor += (size_t)count;
        length -= (size_t)count;
    }
    return 0;
}

static void secure_zero(void *data, size_t length) {
    volatile unsigned char *cursor = (volatile unsigned char *)data;
    while (length-- > 0) *cursor++ = 0;
}

static int read_secure_store_key(unsigned char key[32]) {
    const char *path = "/private/var/root/Library/Preferences/vless-core/store.key";
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? 1 : -1;
    struct stat st;
    int result = -1;
    if (fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == 0 && st.st_nlink == 1 && st.st_size == 32 &&
        ((st.st_mode & 0077) == 0 || fchmod(fd, 0600) == 0) && read_exact_fd(fd, key, 32) == 0) {
        result = 0;
    }
    close(fd);
    return result;
}

static int load_or_create_secure_store_key(unsigned char key[32]) {
    int result = read_secure_store_key(key);
    if (result <= 0) return result;

    const char *directory = "/private/var/root/Library/Preferences/vless-core";
    struct stat directory_stat;
    if ((mkdir(directory, 0700) != 0 && errno != EEXIST) || lstat(directory, &directory_stat) != 0 ||
        !S_ISDIR(directory_stat.st_mode) || S_ISLNK(directory_stat.st_mode) || directory_stat.st_uid != 0 ||
        chmod(directory, 0700) != 0) {
        return -1;
    }

    int random_fd = open("/dev/urandom", O_RDONLY);
    if (random_fd < 0 || read_exact_fd(random_fd, key, 32) != 0) {
        if (random_fd >= 0) close(random_fd);
        return -1;
    }
    close(random_fd);

    char temporary[PATH_MAX];
    int length = snprintf(temporary, sizeof(temporary), "%s/store.key.tmp.XXXXXX", directory);
    if (length <= 0 || (size_t)length >= sizeof(temporary)) return -1;
    int temporary_fd = mkstemp(temporary);
    if (temporary_fd < 0) return -1;
    int write_result = fchmod(temporary_fd, 0600) == 0 && write_all_fd(temporary_fd, key, 32) == 0 && fsync(temporary_fd) == 0 ? 0 : -1;
    if (close(temporary_fd) != 0) write_result = -1;
    if (write_result == 0 && link(temporary, "/private/var/root/Library/Preferences/vless-core/store.key") != 0) {
        write_result = errno == EEXIST ? 1 : -1;
    }
    unlink(temporary);
    if (write_result == 1) return read_secure_store_key(key) == 0 ? 0 : -1;
    if (write_result == 0) {
        int directory_fd = open(directory, O_RDONLY | O_NOFOLLOW);
        if (directory_fd >= 0) {
            (void)fsync(directory_fd);
            close(directory_fd);
        }
    }
    return write_result;
}

static void send_secure_store_key(int client_fd, int create_if_missing) {
    unsigned char key[32];
    int result = create_if_missing ? load_or_create_secure_store_key(key) : read_secure_store_key(key);
    if (result != 0) {
        secure_zero(key, sizeof(key));
        (void)write_all_fd(client_fd, "ERR secure store unavailable\n", 29);
        return;
    }
    char response[69];
    memcpy(response, "OK ", 3);
    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < sizeof(key); i++) {
        response[3 + i * 2] = hex[key[i] >> 4];
        response[4 + i * 2] = hex[key[i] & 0x0f];
    }
    response[67] = '\n';
    response[68] = '\0';
    (void)write_all_fd(client_fd, response, 68);
    secure_zero(key, sizeof(key));
    secure_zero(response, sizeof(response));
}

static void relay_child_log_stream(int input_fd, int output_fd, const char *component) {
    char line[2048];
    size_t used = 0;
    char buffer[512];
    for (;;) {
        ssize_t count = read(input_fd, buffer, sizeof(buffer));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;

        for (ssize_t index = 0; index < count; index++) {
            unsigned char byte = (unsigned char)buffer[index];
            if (byte == '\n') {
                while (used > 0 && line[used - 1] == '\r') used--;
                line[used] = '\0';
                if (used > 0) {
                    const char *level = NULL;
                    const char *message = child_log_record(component, line, &level);
                    (void)write_log_record_fd(output_fd, component, level, message);
                }
                used = 0;
                continue;
            }
            if (used + 1 == sizeof(line)) {
                line[used] = '\0';
                const char *level = NULL;
                const char *message = child_log_record(component, line, &level);
                (void)write_log_record_fd(output_fd, component, level, message);
                used = 0;
            }
            line[used++] = (char)byte;
        }
    }
    while (used > 0 && line[used - 1] == '\r') used--;
    line[used] = '\0';
    if (used > 0) {
        const char *level = NULL;
        const char *message = child_log_record(component, line, &level);
        (void)write_log_record_fd(output_fd, component, level, message);
    }
}

static void finish_log_relay(pid_t *p) {
    if (!p || *p <= 0) return;
    pid_t pid = *p;
    for (int attempt = 0; attempt < 50; attempt++) {
        pid_t result = waitpid(pid, NULL, WNOHANG);
        if (result == pid || (result < 0 && errno == ECHILD)) {
            *p = 0;
            return;
        }
        if (result < 0 && errno != EINTR) break;
        usleep(10000);
    }
    (void)kill(pid, SIGTERM);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
    }
    *p = 0;
}

static int spawn_logged(const char *bin, char *const argv[], const char *stdin_data,
                        const char *relay_component, pid_t *pid_out,
                        pid_t *relay_pid_out) {
    if (!bin || !argv || !pid_out || (relay_component && !relay_pid_out)) return -1;
    *pid_out = 0;
    if (relay_pid_out) *relay_pid_out = 0;

    int input_pipe[2] = {-1, -1};
    int relay_pipe[2] = {-1, -1};
    int relay_output = !g.protect_logs && relay_component != NULL;
    if (stdin_data != NULL && pipe(input_pipe) != 0) return -1;
    if (relay_output && pipe(relay_pipe) != 0) {
        if (input_pipe[0] >= 0) close(input_pipe[0]);
        if (input_pipe[1] >= 0) close(input_pipe[1]);
        return -1;
    }

    const char *output_path = g.protect_logs ? "/dev/null" : "/var/log/vless-core.log";
    int output_flags = g.protect_logs ? O_WRONLY : (O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW);
    int output_fd = open(output_path, output_flags, 0600);
    int input_fd = stdin_data != NULL ? input_pipe[0] : open("/dev/null", O_RDONLY);
    if (output_fd < 0 || input_fd < 0) {
        if (output_fd >= 0) close(output_fd);
        if (input_fd >= 0 && input_fd != input_pipe[0]) close(input_fd);
        if (input_pipe[0] >= 0) close(input_pipe[0]);
        if (input_pipe[1] >= 0) close(input_pipe[1]);
        if (relay_pipe[0] >= 0) close(relay_pipe[0]);
        if (relay_pipe[1] >= 0) close(relay_pipe[1]);
        return -1;
    }
    if (!g.protect_logs) (void)fchmod(output_fd, 0600);

    pid_t relay_pid = 0;
    int helper_output_fd = output_fd;
    if (relay_output) {
        relay_pid = fork();
        if (relay_pid == 0) {
            if (dup2(relay_pipe[0], STDIN_FILENO) < 0 ||
                dup2(output_fd, STDOUT_FILENO) < 0) {
                _exit(126);
            }
            close_inherited_descriptors();
            relay_child_log_stream(STDIN_FILENO, STDOUT_FILENO, relay_component);
            _exit(0);
        }
        if (relay_pid < 0) {
            close(output_fd);
            close(input_fd);
            if (input_pipe[1] >= 0) close(input_pipe[1]);
            close(relay_pipe[0]);
            close(relay_pipe[1]);
            return -1;
        }
        close(relay_pipe[0]);
        close(output_fd);
        helper_output_fd = relay_pipe[1];
    }

    pid_t pid = fork();
    if (pid == 0) {
        if (dup2(input_fd, STDIN_FILENO) < 0 ||
            dup2(helper_output_fd, STDOUT_FILENO) < 0 ||
            dup2(helper_output_fd, STDERR_FILENO) < 0) {
            _exit(126);
        }
        close_inherited_descriptors();
        if (drop_helper_privileges() != 0) _exit(126);
        execve(bin, argv, kSafeHelperEnvironment);
        _exit(127);
    }

    close(helper_output_fd);
    if (input_fd >= 0) close(input_fd);
    if (input_pipe[0] >= 0 && input_pipe[0] != input_fd) close(input_pipe[0]);
    if (pid < 0) {
        if (input_pipe[1] >= 0) close(input_pipe[1]);
        finish_log_relay(&relay_pid);
        return -1;
    }
    if (stdin_data != NULL) {
        size_t length = strlen(stdin_data);
        int write_result = write_all_fd(input_pipe[1], stdin_data, length);
        close(input_pipe[1]);
        if (write_result != 0) {
            kill(pid, SIGTERM);
            (void)waitpid(pid, NULL, 0);
            finish_log_relay(&relay_pid);
            return -1;
        }
    }

    *pid_out = pid;
    if (relay_pid_out) *relay_pid_out = relay_pid;
    return 0;
}

static int spawn_core(const char *uri, const char *server_ips, const char *xray_version,
                      int port, pid_t *pid_out) {
    const char *core_bin = find_vless_core_bin();
    if (!core_bin) return -2;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    char connection_data[sizeof(g.routing) + sizeof(g.server_ips)];
    int connection_length = snprintf(connection_data, sizeof(connection_data), "%s\n%s", uri, server_ips);
    if (connection_length <= 0 || (size_t)connection_length >= sizeof(connection_data)) {
        secure_zero(connection_data, sizeof(connection_data));
        return -1;
    }

    char *argv[14];
    size_t argc = 0;
    argv[argc++] = (char *)core_bin;
    argv[argc++] = "--connection-fd";
    argv[argc++] = "0";
    argv[argc++] = "--listen-port";
    argv[argc++] = port_str;
    argv[argc++] = "--routing";
    argv[argc++] = g.routing;
    argv[argc++] = "--route-control-socket";
    argv[argc++] = VC_DAEMON_SOCKET_PATH;
    if (g.download_ips[0]) {
        argv[argc++] = "--download-server-ips";
        argv[argc++] = g.download_ips;
    }
    if (xray_version && *xray_version) {
        argv[argc++] = "--xray-version";
        argv[argc++] = (char *)xray_version;
    }
    argv[argc] = NULL;

    int result = spawn_logged(core_bin, argv, connection_data,
                              NULL, pid_out, NULL);
    secure_zero(connection_data, sizeof(connection_data));
    return result;
}

static uint64_t core_prepare_now(void *context) {
    (void)context;
    return vc_core_now_ms();
}

static int core_inspection_child(void *context) {
    (void)context;
    close_inherited_descriptors();
    return drop_helper_privileges();
}

static int inspect_connection(void *context, const char *uri, uint64_t until, char *output, size_t capacity) {
    (void)context;
    const char *binary=find_vless_core_bin();
    if (!binary) return -1;
    int flags=g.protect_logs ? O_WRONLY : O_WRONLY|O_CREAT|O_APPEND|O_NOFOLLOW;
    int log_fd=open(g.protect_logs ? "/dev/null" : "/var/log/vless-core.log",flags,0600);
    if (log_fd < 0) return -1;
    if (!g.protect_logs) (void)fchmod(log_fd,0600);
    int result=vc_core_inspect_run(binary,uri,kSafeHelperEnvironment,log_fd,until,core_inspection_child,NULL,output,capacity);
    close(log_fd);
    return result;
}

static int resolve_connection(void *context, const char *host, uint64_t until, char *ips, size_t capacity) {
    (void)context;
    uint64_t now=vc_core_now_ms();
    if (now >= until) return -2;
    uint64_t remaining=until-now;
    char first[64];
    return resolve_host_ipv4_all_bounded(host,first,sizeof(first),ips,capacity,remaining > INT_MAX ? INT_MAX : (int)remaining);
}

static int write_redsocks_conf(int socks_port, int redir_port, const char *redirector) {
    int fd = open("/var/run/vlesscore-redsocks.conf", O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
    if (fd < 0 || fchmod(fd, 0600) != 0 || fchown(fd, g_helper_uid, g_helper_gid) != 0) {
        if (fd >= 0) close(fd);
        return -1;
    }
    FILE *fp = fdopen(fd, "w");
    if (!fp) {
        close(fd);
        return -1;
    }

    int rc = fprintf(
        fp,
        "base {\n"
        "  log_debug = off;\n"
        "  log_info = on;\n"
        "  daemon = off;\n"
        "  redirector = %s;\n"
        "  rlimit_nofile = 1024;\n"
        "  redsocks_conn_max = 256;\n"
        "  connpres_idle_timeout = 600;\n"
        "}\n"
        "redsocks {\n"
        "  local_ip = 127.0.0.1;\n"
        "  local_port = %d;\n"
        "  ip = 127.0.0.1;\n"
        "  port = %d;\n"
        "  type = socks5;\n"
        "}\n",
        redirector,
        redir_port,
        socks_port
    );

    int close_rc = fclose(fp);
    return (rc > 0 && close_rc == 0) ? 0 : -1;
}

static int child_process_running(pid_t *pid, const char *name) {
    if (!pid || *pid <= 0) return 0;

    int status = 0;
    pid_t rc = 0;
    do {
        rc = waitpid(*pid, &status, WNOHANG);
    } while (rc < 0 && errno == EINTR);

    if (rc == 0) {
        return 1;
    }
    if (rc == *pid) {
        if (WIFEXITED(status)) {
            int exit_status = WEXITSTATUS(status);
            if (exit_status == 0) {
                log_msg("%s pid=%d exited, status=%d", name, (int)*pid, exit_status);
            } else {
                log_error("%s pid=%d exited, status=%d", name, (int)*pid, exit_status);
            }
        } else if (WIFSIGNALED(status)) {
            log_error("%s pid=%d terminated by signal=%d", name, (int)*pid, WTERMSIG(status));
        } else {
            log_warning("%s pid=%d exited with an unrecognized wait status", name, (int)*pid);
        }
        *pid = 0;
        return 0;
    }

    log_error("%s pid=%d waitpid failed errno=%d", name, (int)*pid, errno);
    *pid = 0;
    return 0;
}

static int child_process_alive_snapshot(pid_t pid) {
    if (pid <= 0) return 0;
    if (kill(pid, 0) == 0) return 1;
    return errno == EPERM;
}

static int spawn_redsocks(int socks_port, int *redir_port_out,
                          pid_t *pid_out, pid_t *relay_pid_out) {
    const char *bin = find_redsocks_bin();
    if (!bin) return -2;

    int redir_port = pick_free_port_range(12080, 12180);
    if (redir_port <= 0) return -3;

    if (write_redsocks_conf(socks_port, redir_port, "pf") != 0) {
        return -4;
    }

    char *argv[] = {
        (char *)bin,
        "-c",
        "/var/run/vlesscore-redsocks.conf",
        NULL,
    };

    pid_t pid = 0;
    pid_t relay_pid = 0;
    if (spawn_logged(bin, argv, NULL, "redsocks", &pid, &relay_pid) != 0) {
        return -5;
    }

    usleep(300000);
    if (!child_process_running(&pid, "redsocks")) {
        stop_pid(&pid);
        finish_log_relay(&relay_pid);
        log_error("redsocks failed with redirector=pf");
        return -6;
    }

    log_msg("redsocks started pid=%d redirector=pf port=%d", (int)pid, redir_port);
    *pid_out = pid;
    *relay_pid_out = relay_pid;
    *redir_port_out = redir_port;
    return 0;
}

#define DNS_PROXY_MAX_PACKET 4096
#define DNS_PROXY_WORKER_COUNT 8
#define DNS_PROXY_IDLE_POLL_MS 250
#define DNS_PROXY_REUSE_IDLE_MS 3000







typedef struct {
    int udp_fd;
    int socks_port;
    int index;
} dns_proxy_worker_t;

static void *dns_proxy_worker_loop(void *opaque) {
    dns_proxy_worker_t *worker = (dns_proxy_worker_t *)opaque;
    unsigned char query[DNS_PROXY_MAX_PACKET];
    unsigned char reply[DNS_PROXY_MAX_PACKET];
    int upstream_fd = -1;
    long long upstream_last_used_ms = 0;

    while (!g_terminate) {
        if (upstream_fd >= 0 && now_ms() - upstream_last_used_ms >= DNS_PROXY_REUSE_IDLE_MS) {
            close(upstream_fd);
            upstream_fd = -1;
        }

        struct sockaddr_storage peer;
        socklen_t peer_len = sizeof(peer);
        ssize_t n = recvfrom(worker->udp_fd, query, sizeof(query), 0, (struct sockaddr *)&peer, &peer_len);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno == EAGAIN || errno == EWOULDBLOCK) continue;
            log_error("dns proxy worker=%d recv failed errno=%d", worker->index, errno);
            continue;
        }
        if (n < 12) {
            continue;
        }

        size_t reply_len = 0;
        int error_no = 0;
        if (dns_proxy_query_tcp(worker->socks_port, &upstream_fd, query, (size_t)n, reply, sizeof(reply), &reply_len, &error_no) != 0) {
            log_error("dns proxy query failed worker=%d bytes=%ld errno=%d", worker->index, (long)n, error_no);
            continue;
        }
        upstream_last_used_ms = now_ms();

        if (sendto(worker->udp_fd, reply, reply_len, 0, (struct sockaddr *)&peer, peer_len) < 0) {
            log_error("dns proxy worker=%d reply failed errno=%d", worker->index, errno);
        }
    }

    if (upstream_fd >= 0) close(upstream_fd);
    return NULL;
}

static void dns_proxy_loop(int udp_fd, int socks_port) {
    pthread_t workers[DNS_PROXY_WORKER_COUNT];
    dns_proxy_worker_t worker_args[DNS_PROXY_WORKER_COUNT];
    struct timeval idle_poll;
    int worker_count = 0;

    idle_poll.tv_sec = DNS_PROXY_IDLE_POLL_MS / 1000;
    idle_poll.tv_usec = (DNS_PROXY_IDLE_POLL_MS % 1000) * 1000;
    (void)setsockopt(udp_fd, SOL_SOCKET, SO_RCVTIMEO, &idle_poll, sizeof(idle_poll));

    for (int i = 0; i < DNS_PROXY_WORKER_COUNT; i++) {
        worker_args[i].udp_fd = udp_fd;
        worker_args[i].socks_port = socks_port;
        worker_args[i].index = i;
        int thread_rc = pthread_create(&workers[i], NULL, dns_proxy_worker_loop, &worker_args[i]);
        if (thread_rc != 0) {
            log_error("dns proxy worker=%d start failed error=%d", i, thread_rc);
            break;
        }
        worker_count++;
    }

    log_msg("dns proxy loop started socks=%d upstream=%s:%d workers=%d", socks_port, DNS_PROXY_UPSTREAM_IP, DNS_PROXY_UPSTREAM_PORT,
            worker_count);

    if (worker_count == 0) {
        worker_args[0].udp_fd = udp_fd;
        worker_args[0].socks_port = socks_port;
        worker_args[0].index = 0;
        (void)dns_proxy_worker_loop(&worker_args[0]);
    } else {
        for (int i = 0; i < worker_count; i++) {
            (void)pthread_join(workers[i], NULL);
        }
    }

    close(udp_fd);
    log_msg("dns proxy loop stopped");
}

static int spawn_dns_proxy(int socks_port, int *dns_port_out, pid_t *pid_out) {
    if (dns_port_out) *dns_port_out = 0;
    if (pid_out) *pid_out = 0;

    int dns_port = 0;
    int udp_fd = bind_udp_loopback_range(12530, 12630, &dns_port);
    if (udp_fd < 0 || dns_port <= 0) {
        if (udp_fd >= 0) close(udp_fd);
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(udp_fd);
        return -2;
    }

    if (pid == 0) {
        long maximum = sysconf(_SC_OPEN_MAX);
        if (maximum < 0 || maximum > 4096) maximum = 4096;
        for (int fd = STDERR_FILENO + 1; fd < maximum; fd++) {
            if (fd != udp_fd) close(fd);
        }
        g_listen_fd = -1;
        if (drop_helper_privileges() != 0) _exit(126);
        dns_proxy_loop(udp_fd, socks_port);
        _exit(0);
    }

    close(udp_fd);
    usleep(100000);
    if (!child_process_running(&pid, "dns proxy")) {
        stop_pid(&pid);
        return -3;
    }

    log_msg("dns proxy started pid=%d port=%d", (int)pid, dns_port);
    if (dns_port_out) *dns_port_out = dns_port;
    if (pid_out) *pid_out = pid;
    return 0;
}

static void truncate_log_file(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd >= 0) {
        (void)fchmod(fd, 0600);
        close(fd);
    }
}

static void clear_logs(void) {
    truncate_log_file("/var/log/vpnctld.log");
    truncate_log_file("/var/log/vless-core.log");
}

static void update_vpn_icon_state(int enabled) {
    int publisher_rc = vpnicon_statusbar_set_enabled(enabled);
    if (publisher_rc == VPNICON_STATUSBAR_OK) {
        int item_type = vpnicon_statusbar_item_type();
        if (item_type >= 0 && !g_vpn_icon_publisher_logged) {
            log_msg("VPN status bar publisher ready item=%d", item_type);
            g_vpn_icon_publisher_logged = 1;
        }
    } else if (publisher_rc == VPNICON_STATUSBAR_ERROR) {
        log_warning("VPN status bar publisher unavailable: %s", vpnicon_statusbar_last_error());
    }
}

static int process_has_name(pid_t pid, const char *name) {
    if (pid <= 0 || !name || !*name) return 0;
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
    struct kinfo_proc process;
    memset(&process, 0, sizeof(process));
    size_t size = sizeof(process);
    return sysctl(mib, 4, &process, &size, NULL, 0) == 0 &&
           size >= sizeof(process) &&
           process.kp_proc.p_pid == pid &&
           strcmp(process.kp_proc.p_comm, name) == 0;
}

static pid_t springboard_pid(pid_t cached_pid) {
    if (process_has_name(cached_pid, "SpringBoard")) return cached_pid;

    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    for (int attempt = 0; attempt < 3; attempt++) {
        size_t size = 0;
        if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return 0;

        size_t capacity = size + sizeof(struct kinfo_proc) * 16;
        struct kinfo_proc *processes = malloc(capacity);
        if (!processes) return 0;
        if (sysctl(mib, 4, processes, &capacity, NULL, 0) == 0) {
            size_t count = capacity / sizeof(struct kinfo_proc);
            pid_t found = 0;
            for (size_t index = 0; index < count; index++) {
                if (strcmp(processes[index].kp_proc.p_comm, "SpringBoard") == 0) {
                    found = processes[index].kp_proc.p_pid;
                    break;
                }
            }
            free(processes);
            return found;
        }
        int saved_errno = errno;
        free(processes);
        if (saved_errno != ENOMEM) return 0;
    }
    return 0;
}

static void restart_system_dns_resolver(void) {
    int mib[] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    for (int attempt = 0; attempt < 3; attempt++) {
        size_t size = 0;
        if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size == 0) return;

        size_t capacity = size + sizeof(struct kinfo_proc) * 16;
        struct kinfo_proc *processes = malloc(capacity);
        if (!processes) return;
        if (sysctl(mib, 4, processes, &capacity, NULL, 0) == 0) {
            size_t count = capacity / sizeof(struct kinfo_proc);
            unsigned int signaled = 0;
            for (size_t index = 0; index < count; index++) {
                if (strncmp(processes[index].kp_proc.p_comm,
                            "mDNSResponder",
                            strlen("mDNSResponder")) == 0 &&
                    processes[index].kp_proc.p_pid > 1 &&
                    kill(processes[index].kp_proc.p_pid, SIGKILL) == 0) {
                    signaled++;
                }
            }
            free(processes);
            log_msg("restarted system DNS resolver processes=%u after stale PF recovery",
                    signaled);
            return;
        }
        int saved_errno = errno;
        free(processes);
        if (saved_errno != ENOMEM) return;
    }
}

static void monitor_springboard_icon(long long current_ms) {
    if (current_ms - g.springboard_poll_ms < 1000) return;
    g.springboard_poll_ms = current_ms;

    pid_t cached_pid = g.springboard_candidate_pid > 0
        ? g.springboard_candidate_pid
        : g.springboard_pid;
    pid_t observed_pid = springboard_pid(cached_pid);
    if (observed_pid <= 0) {
        g.springboard_candidate_pid = 0;
        g.springboard_candidate_polls = 0;
        return;
    }
    if (g.springboard_pid <= 0) {
        g.springboard_pid = observed_pid;
        return;
    }
    if (observed_pid == g.springboard_pid) {
        g.springboard_candidate_pid = 0;
        g.springboard_candidate_polls = 0;
        return;
    }
    if (observed_pid != g.springboard_candidate_pid) {
        g.springboard_candidate_pid = observed_pid;
        g.springboard_candidate_polls = 1;
        return;
    }
    if (++g.springboard_candidate_polls < 2) return;

    g.springboard_pid = observed_pid;
    g.springboard_candidate_pid = 0;
    g.springboard_candidate_polls = 0;
    int rc = vpnicon_statusbar_republish();
    if (rc == VPNICON_STATUSBAR_OK) {
        log_msg("VPN status bar icon republished after SpringBoard restart pid=%d",
                (int)observed_pid);
        diagnostic_event("VPN icon restored after SpringBoard restart");
    } else if (rc == VPNICON_STATUSBAR_ERROR) {
        log_warning("VPN status bar icon republish failed: %s", vpnicon_statusbar_last_error());
    }
}

static int bind_control_socket(void) {
    int lfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (lfd < 0) {
        log_error("control socket() failed errno=%d", errno);
        return -1;
    }

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", VC_DAEMON_SOCKET_PATH);
    sa.sun_len = (uint8_t)SUN_LEN(&sa);
    unlink(VC_DAEMON_SOCKET_PATH);

    if (bind(lfd, (struct sockaddr *)&sa, (socklen_t)sa.sun_len) != 0) {
        log_error("bind(%s) failed errno=%d", VC_DAEMON_SOCKET_PATH, errno);
        close(lfd);
        return -1;
    }
    if (chmod(VC_DAEMON_SOCKET_PATH, 0666) != 0) {
        log_error("chmod(%s) failed errno=%d", VC_DAEMON_SOCKET_PATH, errno);
        close(lfd);
        unlink(VC_DAEMON_SOCKET_PATH);
        return -1;
    }

    if (listen(lfd, 16) != 0) {
        log_error("listen(%s) failed errno=%d", VC_DAEMON_SOCKET_PATH, errno);
        close(lfd);
        unlink(VC_DAEMON_SOCKET_PATH);
        return -1;
    }

    return lfd;
}

static void stop_pid(pid_t *p) {
    if (*p <= 0) return;

    pid_t pid = *p;
    (void)kill(pid, SIGTERM);
    for (int attempt = 0; attempt < 30; attempt++) {
        pid_t result = waitpid(pid, NULL, WNOHANG);
        if (result == pid || (result < 0 && errno == ECHILD)) {
            *p = 0;
            return;
        }
        if (result < 0 && errno != EINTR) break;
        usleep(10000);
    }

    (void)kill(pid, SIGKILL);
    while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
    }
    *p = 0;
}


static const char *pf_rule_mode_name(pf_rule_mode_t mode) {
    switch (mode) {
        case PF_RULE_ROUTE_TO_LO0: return "route-to-lo0+rdr";
        case PF_RULE_ROUTE_TO_LO0_NOGW: return "route-to-lo0-nogw+rdr";
        case PF_RULE_DIVERT_TO: return "divert-to";
        case PF_RULE_DIVERT_TO_OLD: return "divert-to-old";
        case PF_RULE_RDR_TO: return "rdr-to";
        case PF_RULE_RDR_TO_OLD: return "rdr-to-old";
        case PF_RULE_LEGACY_RDR: return "legacy-rdr";
        case PF_RULE_LOOPBACK_ROUTES: return "loopback-routes+rdr";
        default: return "unknown";
    }
}


static int write_pf_conf(const char *server_ips, char ifnames[][32], size_t if_count, int redir_port, int dns_port, pf_rule_mode_t mode) {
    return vc_write_pf_conf("/var/run/vlesscore-pf.conf", g.routing_bypass_lan, server_ips, ifnames, if_count, redir_port, dns_port, mode);
}

static pf_enabled_state_t pf_enabled_state_query(const char *pfctl, int verbose) {
    if (!pfctl) return PF_ENABLED_ERROR;
    char output[4096];
    char *argv[] = {
        (char *)pfctl,
        "-s",
        "info",
        NULL,
    };
    int rc = verbose
        ? run_argv_capture(argv, output, sizeof(output))
        : run_argv_capture_quiet(argv, output, sizeof(output));
    if (rc != 0) {
        if (verbose) log_warning("pf status query failed");
        return PF_ENABLED_ERROR;
    }
    if (contains_ci(output, "Status: Enabled")) return PF_ENABLED;
    if (contains_ci(output, "Status: Disabled")) return PF_DISABLED;
    if (verbose) log_warning("pf status query returned an unknown state");
    return PF_ENABLED_ERROR;
}

static pf_enabled_state_t pf_enabled_state(const char *pfctl) {
    return pf_enabled_state_query(pfctl, 1);
}

static pf_enabled_state_t pf_enabled_state_quiet(const char *pfctl) {
    return pf_enabled_state_query(pfctl, 0);
}

static void ensure_pf_os_file(void) {
    if (path_exists("/etc/pf.os")) return;

    int fd = open("/etc/pf.os", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        log_error("cannot create /etc/pf.os errno=%d", errno);
        return;
    }

    const char *placeholder = "# vlesscore placeholder\n";
    (void)write(fd, placeholder, strlen(placeholder));
    close(fd);
    log_msg("created placeholder /etc/pf.os");
}

static int flush_pf_states(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return -1;

    char *argv[] = {
        (char *)pfctl,
        "-q",
        "-F",
        "states",
        NULL,
    };
    if (run_argv(argv) == 0) {
        log_msg("pf states flushed");
        return 0;
    }
    return -1;
}





static pf_root_state_t pf_root_state_query(const char *pfctl, int verbose) {
    char nat_rules[16384];
    char filter_rules[16384];
    char *nat_argv[] = { (char *)pfctl, "-sn", NULL };
    char *filter_argv[] = { (char *)pfctl, "-sr", NULL };
    int nat_rc = verbose
        ? run_argv_capture(nat_argv, nat_rules, sizeof(nat_rules))
        : run_argv_capture_quiet(nat_argv, nat_rules, sizeof(nat_rules));
    int filter_rc = verbose
        ? run_argv_capture(filter_argv, filter_rules, sizeof(filter_rules))
        : run_argv_capture_quiet(filter_argv, filter_rules, sizeof(filter_rules));
    if (nat_rc != 0 || filter_rc != 0) {
        return PF_ROOT_ERROR;
    }

    int has_nat = contains_ci(nat_rules, "nat-anchor \"vlesscore\"");
    int has_rdr = contains_ci(nat_rules, "rdr-anchor \"vlesscore\"");
    int has_filter = contains_ci(filter_rules, "anchor \"vlesscore\"");
    if (has_nat && has_rdr && has_filter) {
        if (pf_dispatch_rules_only(nat_rules, 1) &&
            pf_dispatch_rules_only(filter_rules, 0)) {
            return PF_ROOT_OWN_DISPATCH;
        }
        return PF_ROOT_SHARED_DISPATCH;
    }

    if (text_has_nonspace(nat_rules) || text_has_nonspace(filter_rules)) {
        if (verbose) log_warning("pf root rules exist without vlesscore anchor; refusing to replace them");
        return PF_ROOT_CONFLICT;
    }
    return PF_ROOT_EMPTY;
}

static pf_root_state_t pf_root_state(const char *pfctl) {
    return pf_root_state_query(pfctl, 1);
}

static pf_root_state_t pf_root_state_quiet(const char *pfctl) {
    return pf_root_state_query(pfctl, 0);
}

static int install_pf_dispatch(const char *pfctl) {
    const char *path = "/var/run/vlesscore-pf-dispatch.conf";
    FILE *fp = fopen(path, "w");
    if (!fp) return -1;
    int write_failed =
        fprintf(fp,
                "nat-anchor \"vlesscore\"\n"
                "rdr-anchor \"vlesscore\"\n"
                "anchor \"vlesscore\"\n") < 0;
    if (fclose(fp) != 0 || write_failed) return -1;

    char *load_argv[] = {
        (char *)pfctl,
        "-q",
        "-f",
        (char *)path,
        NULL,
    };
    if (run_argv(load_argv) != 0) {
        log_error("pf failed to install vlesscore anchor dispatch");
        return -1;
    }
    log_msg("pf vlesscore anchor dispatch installed");
    return 0;
}

static int remove_owned_pf_dispatch(const char *pfctl) {
    pf_root_state_t state = pf_root_state(pfctl);
    if (state == PF_ROOT_ERROR) return -1;
    if (state == PF_ROOT_EMPTY) return 0;
    if (state != PF_ROOT_OWN_DISPATCH) {
        log_warning("pf root rules changed while VPN was active; leaving root dispatch untouched");
        return 0;
    }

    char *clear_argv[] = {
        (char *)pfctl,
        "-q",
        "-f",
        "/dev/null",
        NULL,
    };
    if (run_argv(clear_argv) != 0) return -1;
    if (pf_root_state(pfctl) != PF_ROOT_EMPTY) return -1;
    log_msg("pf vlesscore root dispatch removed");
    return 0;
}

static int apply_pf_rules(const char *server_ips, int redir_port, int dns_port) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) {
        log_error("pfctl binary not found");
        return -1;
    }

    pf_enabled_state_t enabled_state = pf_enabled_state(pfctl);
    if (enabled_state == PF_ENABLED_ERROR) return -8;

    pf_root_state_t root_state = pf_root_state(pfctl);
    if (root_state == PF_ROOT_ERROR || root_state == PF_ROOT_CONFLICT) return -7;

    ensure_pf_os_file();
    int was_enabled = enabled_state == PF_ENABLED;
    g.pf_enabled_before = was_enabled;
    g.pf_dispatch_installed =
        root_state == PF_ROOT_EMPTY || root_state == PF_ROOT_OWN_DISPATCH;
    if (write_pf_previous_state(g.pf_enabled_before, g.pf_dispatch_installed) != 0) {
        log_error("failed to persist previous PF state");
        return -1;
    }
    if (root_state == PF_ROOT_EMPTY && install_pf_dispatch(pfctl) != 0) return -7;

    if (was_enabled) {
        log_msg("pf already enabled; will reload rules");
    }

    char ifnames[8][32];
    memset(ifnames, 0, sizeof(ifnames));
    size_t if_count = collect_pf_interfaces(ifnames, sizeof(ifnames) / sizeof(ifnames[0]));
    if (if_count == 0) {
        log_error("pf: no suitable interfaces found (expected en*/pdp_ip*)");
        return -6;
    }

    char if_list[256];
    if_list[0] = '\0';
    for (size_t i = 0; i < if_count; i++) {
        if (i > 0) {
            strncat(if_list, ",", sizeof(if_list) - strlen(if_list) - 1);
        }
        strncat(if_list, ifnames[i], sizeof(if_list) - strlen(if_list) - 1);
    }
    log_msg("pf target interfaces: %s", if_list);

    int enabled_now = 0;

    if (was_enabled) {
        enabled_now = 1;
    } else {
        char *enable_argv[] = {
            (char *)pfctl,
            "-q",
            "-e",
            NULL,
        };
        (void)run_argv(enable_argv);
        pf_enabled_state_t state_after_enable = pf_enabled_state(pfctl);
        if (state_after_enable == PF_ENABLED) {
            enabled_now = 1;
        } else if (state_after_enable == PF_DISABLED) {
            char *enable_old_argv[] = {
                (char *)pfctl,
                "-q",
                "-E",
                NULL,
            };
            (void)run_argv(enable_old_argv);
            if (pf_enabled_state(pfctl) == PF_ENABLED) {
                enabled_now = 1;
            }
        }
    }

    if (!enabled_now) {
        return -5;
    }

    const pf_rule_mode_t modes_default[] = {
        PF_RULE_ROUTE_TO_LO0,
        PF_RULE_ROUTE_TO_LO0_NOGW,
        PF_RULE_LEGACY_RDR,
        PF_RULE_DIVERT_TO_OLD,
        PF_RULE_DIVERT_TO,
        PF_RULE_RDR_TO_OLD,
        PF_RULE_RDR_TO,
    };
    const pf_rule_mode_t modes_cellular[] = {
        PF_RULE_ROUTE_TO_LO0,
        PF_RULE_LEGACY_RDR,
        PF_RULE_ROUTE_TO_LO0_NOGW,
        PF_RULE_DIVERT_TO,
        PF_RULE_RDR_TO,
        PF_RULE_DIVERT_TO_OLD,
        PF_RULE_RDR_TO_OLD,
    };

    const pf_rule_mode_t *modes = modes_default;
    size_t mode_count = sizeof(modes_default) / sizeof(modes_default[0]);
    if (interface_list_has_prefix(ifnames, if_count, "pdp_ip")) {
        modes = modes_cellular;
        mode_count = sizeof(modes_cellular) / sizeof(modes_cellular[0]);
        log_msg("pf detected cellular interfaces");
    }
    const pf_rule_mode_t modes_ios5[] = {PF_RULE_LOOPBACK_ROUTES};
    if (vc_legacy_loopback_required()) {
        modes = modes_ios5;
        mode_count = 1;
        log_msg("iOS 5: using ordinary loopback routes");
    }

    for (size_t i = 0; i < mode_count; i++) {
        pf_rule_mode_t mode = modes[i];

        if (write_pf_conf(server_ips, ifnames, if_count, redir_port, dns_port, mode) != 0) {
            continue;
        }

        log_msg("pf trying mode=%s", pf_rule_mode_name(mode));
        char *load_argv[] = {
            (char *)pfctl,
            "-q",
            "-a",
            "vlesscore",
            "-f",
            "/var/run/vlesscore-pf.conf",
            NULL,
        };
        if (run_argv(load_argv) == 0) {
            log_msg("pf rules loaded mode=%s", pf_rule_mode_name(mode));
            (void)flush_pf_states();
            return 0;
        }
    }

    return -4;
}

static int clear_pf_rules(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return -1;
    int result = 0;
    int legacy = vc_legacy_loopback_required();

    char *empty_argv[] = {
        (char *)pfctl,
        "-q",
        "-a",
        "vlesscore",
        "-f",
        "/dev/null",
        NULL,
    };
    if (run_argv(empty_argv) != 0) result = -1;
    if (legacy && flush_pf_states() != 0) result = -1;

    char *flush_tables_argv[] = {
        (char *)pfctl,
        "-q",
        "-a",
        "vlesscore",
        "-F",
        "Tables",
        NULL,
    };
    if (run_argv(flush_tables_argv) != 0) result = -1;

    if (g.pf_dispatch_installed && remove_owned_pf_dispatch(pfctl) != 0) result = -1;

    if (!legacy && flush_pf_states() != 0) result = -1;

    if (!g.pf_enabled_before) {
        char *disable_argv[] = {
            (char *)pfctl,
            "-q",
            "-d",
            NULL,
        };
        if (run_argv(disable_argv) != 0 && pf_enabled_state(pfctl) != PF_DISABLED) {
            result = -1;
        }
    }

    if (result == 0) {
        g.pf_dispatch_installed = 0;
        if (remove_pf_previous_state() != 0) result = -1;
    }
    return result;
}

static int recover_stale_pf_state(void) {
    if (ensure_state_directory() != 0) return -1;
    (void)unlink(kPFPreviousStateTempPath);
    (void)unlink(kLegacyPFPreviousStateTempPath);

    int was_enabled = 0;
    int dispatch_installed = 0;
    int state_result = read_pf_previous_state(&was_enabled, &dispatch_installed);
    const char *pfctl = find_pfctl_bin();
    pf_root_state_t root_state = pfctl ? pf_root_state(pfctl) : PF_ROOT_ERROR;
    int stale_dispatch_present =
        root_state == PF_ROOT_OWN_DISPATCH || root_state == PF_ROOT_SHARED_DISPATCH;
    if (vc_legacy_loopback_required() && state_result == 0 && !was_enabled &&
        root_state == PF_ROOT_OWN_DISPATCH) {
        char *disable_argv[] = {(char *)pfctl, "-q", "-d", NULL};
        (void)run_argv(disable_argv);
        if (pf_enabled_state(pfctl) != PF_DISABLED) return -1;
        log_msg("iOS 5: disabled owned stale PF before recovery");
    }

    if (state_result == 1) {
        if (!stale_dispatch_present) return 0;
        g.pf_enabled_before = 1;
        g.pf_dispatch_installed = root_state == PF_ROOT_OWN_DISPATCH;
        log_warning("recovering orphaned PF dispatch without state file");
        if (clear_pf_rules() != 0) return -1;
        restart_system_dns_resolver();
        return 0;
    }
    if (state_result != 0) {
        log_warning("invalid PF state file; recovering conservatively");
        g.pf_enabled_before = 1;
        g.pf_dispatch_installed = root_state == PF_ROOT_OWN_DISPATCH;
        if (stale_dispatch_present && clear_pf_rules() != 0) return -1;
        if (!stale_dispatch_present && remove_pf_previous_state() != 0) return -1;
        if (stale_dispatch_present) restart_system_dns_resolver();
        return 0;
    }

    g.pf_enabled_before = was_enabled;
    if (dispatch_installed < 0) {
        dispatch_installed = root_state == PF_ROOT_OWN_DISPATCH;
    }
    g.pf_dispatch_installed = dispatch_installed;
    log_warning("recovering stale PF state previous_enabled=%d dispatch_installed=%d",
                was_enabled,
                dispatch_installed);
    if (clear_pf_rules() != 0) return -1;
    (void)unlink("/var/run/vlesscore-redsocks.conf");
    (void)unlink("/var/run/vlesscore-pf.conf");
    (void)unlink("/var/run/vlesscore-pf-dispatch.conf");
    if (stale_dispatch_present) restart_system_dns_resolver();
    return 0;
}

static int disconnect_all(void) {
    int had_active_state = g.connected || g.core_pid > 0 || g.redsocks_pid > 0 ||
                           g.redsocks_log_relay_pid > 0 || g.dns_pid > 0;
    int protected_logs = g.protect_logs;
    char routing[sizeof(g.routing)];
    snprintf(routing, sizeof(routing), "%s", g.routing);
    int routing_bypass_lan = g.routing_bypass_lan;

#if defined(__LP64__)
    int proxy_enabled = g.system_proxy_enabled;
    int (*restore_proxy)(void) = vc_system_proxy_disable;
#else
    int proxy_enabled = 0;
    int (*restore_proxy)(void) = NULL;
#endif
    const VCNetworkRestoreOperations operations = {vc_legacy_dns_stop, vc_legacy_loopback_stop, restore_proxy, clear_pf_rules, diagnostic_event, log_error};
    if (VCRestoreNetworkBeforeStoppingHelpers(proxy_enabled, g.mode == MODE_PF, &operations) != 0) return -1;

    if (had_active_state && !protected_logs) {
        core_log_event("I", "VPN session stopping");
    }
    stop_pid(&g.redsocks_pid);
    stop_pid(&g.dns_pid);
    stop_pid(&g.core_pid);
    finish_log_relay(&g.redsocks_log_relay_pid);
    if (had_active_state && !protected_logs) {
        core_log_event("I", "VPN session stopped");
    }

    unlink("/var/run/vlesscore-redsocks.conf");
    unlink("/var/run/vlesscore-pf.conf");
    unlink("/var/run/vlesscore-pf-dispatch.conf");

    memset(&g, 0, sizeof(g));
    snprintf(g.routing, sizeof(g.routing), "%s", routing);
    g.routing_bypass_lan = routing_bypass_lan;
    update_vpn_icon_state(0);
    if (had_active_state) diagnostic_event("VPN disconnected and routing restored");
    if (protected_logs) {
        clear_logs();
    }
    return 0;
}

static void monitor_connected_children(void) {
    const VCHelperMonitorOperations operations = {child_process_running, diagnostic_event, log_error, log_warning, disconnect_all};
    if (!VCMonitorHelpers(g.connected, &g.core_pid, &g.redsocks_pid, &g.dns_pid, &operations)) return;

#if defined(__LP64__)
    long long current_ms = now_ms();
    if (g.system_proxy_enabled && current_ms - g.system_proxy_refresh_ms >= 1000) {
        g.system_proxy_refresh_ms = current_ms;
        if (vc_system_proxy_refresh(g.socks_port) != 0) {
            log_error("system PAC proxy refresh failed; disconnecting to prevent WebKit traffic leaks");
            diagnostic_event("PAC refresh failed; disconnecting to prevent a leak");
            if (disconnect_all() != 0) {
                log_warning("VPN cleanup will be retried while system proxy restoration is pending");
            }
        }
    }
#else
    long long current_ms = now_ms();
    if (vc_legacy_loopback_active() && current_ms - g.loopback_check_ms >= 1000) {
        g.loopback_check_ms = current_ms;
        if (!vc_legacy_loopback_healthy() || !vc_legacy_dns_healthy()) {
            log_warning("iOS 5 network/DNS configuration changed; restoring legacy routing");
            (void)disconnect_all();
            return;
        }
    }
#endif
    monitor_springboard_icon(current_ms);
}

static int try_connect_pf(int socks_port) {
    int redir_port = 0;
    int rc = spawn_redsocks(socks_port, &redir_port,
                            &g.redsocks_pid, &g.redsocks_log_relay_pid);
    if (rc != 0) {
        return -30 + rc;
    }
    diagnostic_event("Traffic redirector started");

    usleep(300000);

    int dns_port = 0;
    if (spawn_dns_proxy(socks_port, &dns_port, &g.dns_pid) != 0) {
        stop_pid(&g.redsocks_pid);
        finish_log_relay(&g.redsocks_log_relay_pid);
        return -45;
    }
    diagnostic_event("DNS helper started");

    const char *pf_server_ips = g.bypass_ips;
    int pf_rc = apply_pf_rules(pf_server_ips, redir_port, dns_port);
    if (pf_rc != 0) {
        if (clear_pf_rules() != 0) {
            log_error("failed to roll back PF after connection error");
        }
        stop_pid(&g.dns_pid);
        stop_pid(&g.redsocks_pid);
        finish_log_relay(&g.redsocks_log_relay_pid);
        return -40 + pf_rc;
    }
    diagnostic_event("PF routing activated");

    if (vc_legacy_loopback_required()) {
        int legacy_rc = vc_legacy_loopback_start(pf_server_ips, g.routing_bypass_lan);
        if (legacy_rc != 0) log_error("iOS 5 loopback route setup failed errno=%d", errno);
        else {
            legacy_rc = vc_legacy_dns_start();
            if (legacy_rc != 0) log_error("iOS 5 DNS override failed result=%d", legacy_rc);
        }
        if (legacy_rc != 0) {
            g.mode = MODE_PF;
            (void)disconnect_all();
            return -49;
        }
        log_msg("iOS 5 ordinary loopback routes and unscoped DNS activated");
    }

    g.mode = MODE_PF;
    g.connected = 1;
    g.socks_port = socks_port;
    g.redir_port = redir_port;
    g.dns_port = dns_port;
    return 0;
}

static void finish_failed_protected_connect(void) {
    if (!g.protect_logs) return;
    clear_logs();
    g.protect_logs = 0;
}

static int connect_all(const char *uri, const char *xray_version, int requested_port,
                       int protect_logs, char *msg, size_t msg_cap) {
    if (g.connected) {
        if (g.protect_logs != (protect_logs ? 1 : 0)) {
            snprintf(msg, msg_cap, "ERR already connected with different log protection");
            return -1;
        }
        snprintf(msg, msg_cap, "OK already connected mode=%s socks=%d protected=%d since=%lld",
                 mode_name(g.mode), g.socks_port, g.protect_logs, (long long)g.connected_since);
        return 0;
    }

    diagnostic_event("Connection requested");

    g.protect_logs = protect_logs ? 1 : 0;
    if (g.protect_logs) {
        clear_logs();
    }
    if (xray_version && *xray_version) {
        log_msg("Xray version spoof enabled: %s", xray_version);
    }

    int port = pick_port(requested_port);
    if (port <= 0) {
        snprintf(msg, msg_cap, "ERR no free local SOCKS port");
        diagnostic_event("Connection failed: no local SOCKS port available");
        finish_failed_protected_connect();
        return -1;
    }

    g.server_ip[0]=g.server_ips[0]=g.download_ips[0]=g.bypass_ips[0]=0;
    VCCoreAddresses addresses;
    char preparation_error[256];
    const VCCorePrepareOperations operations={core_prepare_now,inspect_connection,resolve_connection,NULL};
    if (vc_core_prepare(uri,&operations,&addresses,preparation_error,sizeof(preparation_error))) {
        snprintf(msg,msg_cap,"ERR %s",preparation_error);
        log_error("connection preparation failed: %s",preparation_error);
        diagnostic_event("Connection failed: configuration or server address preparation failed");
        finish_failed_protected_connect();
        return -1;
    }
    memcpy(g.server_ips,addresses.primary,sizeof(g.server_ips));
    memcpy(g.download_ips,addresses.download,sizeof(g.download_ips));
    memcpy(g.bypass_ips,addresses.bypass,sizeof(g.bypass_ips));
    size_t first_length=strcspn(g.server_ips,", ");
    memcpy(g.server_ip,g.server_ips,first_length); g.server_ip[first_length]=0;
    diagnostic_event("Configuration validated and server addresses resolved");
    log_msg("VPN session starting primary=%s download=%s local_socks=%d",g.server_ips,g.download_ips[0] ? g.download_ips : "none",port);

    if (spawn_core(uri, g.server_ips, xray_version, port, &g.core_pid) != 0) {
        snprintf(msg, msg_cap, "ERR failed to start vless-core binary");
        core_log_event("E", "VPN session failed | vless-core did not start");
        diagnostic_event("Connection failed: core helper did not start");
        (void)disconnect_all();
        return -1;
    }

    usleep(500000);
    if (!child_process_running(&g.core_pid, "vless-core")) {
        snprintf(msg, msg_cap, "ERR vless-core exited during startup");
        diagnostic_event("Connection failed: core helper exited during startup");
        (void)disconnect_all();
        return -1;
    }
    diagnostic_event("Core helper started");

    int pf_rc = try_connect_pf(port);
    if (pf_rc == 0) {
        if (!child_process_running(&g.core_pid, "vless-core") ||
            !child_process_running(&g.redsocks_pid, "redsocks") ||
            !child_process_running(&g.dns_pid, "dns proxy")) {
            snprintf(msg, msg_cap, "ERR VPN helper exited during startup");
            diagnostic_event("Connection failed: a helper exited during startup");
            (void)disconnect_all();
            return -1;
        }
#if defined(__LP64__)
        if (vc_system_proxy_enable(port) != 0) {
            log_error("failed to enable system PAC proxy for WebKit");
            (void)vc_system_proxy_disable();
            snprintf(msg, msg_cap, "ERR failed to configure system proxy");
            diagnostic_event("Connection failed: PAC configuration failed");
            (void)disconnect_all();
            return -1;
        }
        g.system_proxy_enabled = 1;
        log_msg("system PAC proxy enabled on network services port=%d", port);
        diagnostic_event("PAC configured for WebKit traffic");
#endif
        g.connected_since = time(NULL);
        update_vpn_icon_state(1);
        g.springboard_pid = springboard_pid(0);
        g.springboard_poll_ms = now_ms();
        log_msg("VPN session established mode=%s socks=%d redir=%d dns=%d",
                mode_name(g.mode), g.socks_port, g.redir_port, g.dns_port);
        core_log_event("I", "VPN session established | mode=%s | socks=%d | redir=%d | dns=%d",
                       mode_name(g.mode), g.socks_port, g.redir_port, g.dns_port);
        diagnostic_event("VPN connection established");
        snprintf(msg, msg_cap, "OK connected mode=%s socks=%d redir=%d protected=%d since=%lld",
                 mode_name(g.mode), g.socks_port, g.redir_port, g.protect_logs, (long long)g.connected_since);
        return 0;
    }

    (void)disconnect_all();
    diagnostic_event("Connection failed: PF routing unavailable");
    snprintf(msg, msg_cap, "ERR pf backend unavailable: pf_rc=%d (see /var/log/vpnctld.log)", pf_rc);
    return -1;
}

static int natlook_endpoint_is_usable(const struct sockaddr_in *endpoint,
                                      const struct sockaddr_in *redirected) {
    uint32_t address = ntohl(endpoint->sin_addr.s_addr);
    return endpoint->sin_port != 0 &&
           (address >> 24) != 127 && address != 0 &&
           !(endpoint->sin_port == redirected->sin_port &&
             endpoint->sin_addr.s_addr == redirected->sin_addr.s_addr);
}

static int pf_original_destination(const struct sockaddr_in *client,
                                   const struct sockaddr_in *redirected,
                                   struct sockaddr_in *destination) {
    int pf_fd = open("/dev/pf", O_RDWR | O_NOFOLLOW);
    if (pf_fd < 0) return -1;

    struct stat device_stat;
    if (fstat(pf_fd, &device_stat) != 0 || !S_ISCHR(device_stat.st_mode)) {
        close(pf_fd);
        return -1;
    }

    struct pfioc_natlook lookup;
    memset(&lookup, 0, sizeof(lookup));
    lookup.saddr.v4 = client->sin_addr;
    VC_NL_SET_SPORT(lookup, client->sin_port);
    lookup.daddr.v4 = redirected->sin_addr;
    VC_NL_SET_DPORT(lookup, redirected->sin_port);
    lookup.af = AF_INET;
    lookup.proto = IPPROTO_TCP;
#if defined(PF_NATLOOK_USES_XPORT)
    lookup.proto_variant = 0;
#endif
    lookup.direction = PF_OUT;

    if (ioctl(pf_fd, DIOCNATLOOK, &lookup) != 0) {
        if (errno != ENOENT) {
            close(pf_fd);
            return -1;
        }
        lookup.direction = PF_IN;
        if (ioctl(pf_fd, DIOCNATLOOK, &lookup) != 0) {
            close(pf_fd);
            return -1;
        }
    }
    close(pf_fd);

    struct sockaddr_in candidates[3];
    memset(candidates, 0, sizeof(candidates));
    candidates[0].sin_family = AF_INET;
    candidates[0].sin_port = VC_NL_GET_RDPORT(lookup);
    candidates[0].sin_addr = lookup.rdaddr.v4;
    candidates[1].sin_family = AF_INET;
    candidates[1].sin_port = VC_NL_GET_DPORT(lookup);
    candidates[1].sin_addr = lookup.daddr.v4;
    candidates[2].sin_family = AF_INET;
    candidates[2].sin_port = VC_NL_GET_RSPORT(lookup);
    candidates[2].sin_addr = lookup.rsaddr.v4;

    for (size_t i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
        if (natlook_endpoint_is_usable(&candidates[i], redirected)) {
            *destination = candidates[i];
            return 0;
        }
    }
    return -1;
}

static void handle_redsocks_natlook(int client_fd, char *command) {
    char *newline = strchr(command, '\n');
    if (!newline || newline[1] != '\0') {
        (void)write_all_fd(client_fd, "ERR malformed NATLOOK\n", 22);
        return;
    }
    *newline = '\0';

    char client_ip[INET_ADDRSTRLEN];
    char redirected_ip[INET_ADDRSTRLEN];
    unsigned client_port = 0;
    unsigned redirected_port = 0;
    char trailing = '\0';
    int parsed = sscanf(command, "NATLOOK\t%15[0-9.]\t%u\t%15[0-9.]\t%u%c",
                        client_ip, &client_port, redirected_ip, &redirected_port, &trailing);
    if (parsed != 4 || client_port == 0 || client_port > 65535 ||
        redirected_port == 0 || redirected_port > 65535) {
        (void)write_all_fd(client_fd, "ERR malformed NATLOOK\n", 22);
        return;
    }

    struct sockaddr_in client;
    struct sockaddr_in redirected;
    struct sockaddr_in destination;
    memset(&client, 0, sizeof(client));
    memset(&redirected, 0, sizeof(redirected));
    memset(&destination, 0, sizeof(destination));
    client.sin_family = AF_INET;
    client.sin_port = htons((uint16_t)client_port);
    redirected.sin_family = AF_INET;
    redirected.sin_port = htons((uint16_t)redirected_port);
    if (inet_pton(AF_INET, client_ip, &client.sin_addr) != 1 ||
        inet_pton(AF_INET, redirected_ip, &redirected.sin_addr) != 1 ||
        (ntohl(client.sin_addr.s_addr) >> 24) != 127 ||
        (ntohl(redirected.sin_addr.s_addr) >> 24) != 127 ||
        redirected_port < 12080 || redirected_port > 12180 ||
        pf_original_destination(&client, &redirected, &destination) != 0) {
        (void)write_all_fd(client_fd, "ERR NATLOOK failed\n", 19);
        return;
    }

    char destination_ip[INET_ADDRSTRLEN];
    if (!inet_ntop(AF_INET, &destination.sin_addr, destination_ip, sizeof(destination_ip))) {
        (void)write_all_fd(client_fd, "ERR NATLOOK failed\n", 19);
        return;
    }
    char response[80];
    int response_length = snprintf(response, sizeof(response), "OK\t%s\t%u\n",
                                   destination_ip, (unsigned)ntohs(destination.sin_port));
    if (response_length > 0 && (size_t)response_length < sizeof(response)) {
        (void)write_all_fd(client_fd, response, (size_t)response_length);
    }
}

static const char *pf_enabled_state_name(pf_enabled_state_t state) {
    if (state == PF_ENABLED) return "enabled";
    if (state == PF_DISABLED) return "disabled";
    return "error";
}

static const char *pf_routing_state_name(pf_enabled_state_t enabled,
                                         pf_root_state_t root) {
    if (!g.connected || g.mode != MODE_PF) return "inactive";
    if (enabled == PF_ENABLED_ERROR || root == PF_ROOT_ERROR) return "error";
    if (enabled != PF_ENABLED) return "missing";
    if (root == PF_ROOT_OWN_DISPATCH || root == PF_ROOT_SHARED_DISPATCH) return "active";
    if (root == PF_ROOT_CONFLICT) return "conflict";
    return "missing";
}

static const char *pac_state_name(void) {
#if defined(__LP64__)
    int state = vc_system_proxy_status();
    if (state > 0) return "active";
    if (state == 0) return "inactive";
    return "error";
#else
    return "not_required";
#endif
}

static void send_safe_diagnostics(int client_fd) {
    const char *pfctl = find_pfctl_bin();
    pf_enabled_state_t enabled = pfctl ? pf_enabled_state_quiet(pfctl) : PF_ENABLED_ERROR;
    pf_root_state_t root = pfctl ? pf_root_state_quiet(pfctl) : PF_ROOT_ERROR;
    char response[2048];
    int length = snprintf(response,
                          sizeof(response),
                          "OK diagnostics=1\n"
                          "connected=%d\n"
                          "mode=%s\n"
                          "architecture=%s\n"
                          "socks_port=%d\n"
                          "pf=%s\n"
                          "pf_routing=%s\n"
                          "pac=%s\n"
                          "core=%s\n"
                          "redsocks=%s\n"
                          "dns=%s\n"
                          "protected_logs=%d\n",
                          g.connected ? 1 : 0,
                          mode_name(g.mode),
#if defined(__LP64__)
                          "arm64",
#else
                          "armv7",
#endif
                          g.socks_port,
                          pf_enabled_state_name(enabled),
                          pf_routing_state_name(enabled, root),
                          pac_state_name(),
                          child_process_alive_snapshot(g.core_pid) ? "running" : "stopped",
                          child_process_alive_snapshot(g.redsocks_pid) ? "running" : "stopped",
                          child_process_alive_snapshot(g.dns_pid) ? "running" : "stopped",
                          g.protect_logs ? 1 : 0);
    if (length <= 0 || (size_t)length >= sizeof(response)) {
        static const char error[] = "ERR diagnostics unavailable\n";
        (void)write_all_fd(client_fd, error, sizeof(error) - 1);
        return;
    }
    (void)write_all_fd(client_fd, response, (size_t)length);
}

static void send_diagnostic_events(int client_fd) {
    char header[64];
    int header_length = snprintf(header,
                                 sizeof(header),
                                 "OK events=%u\n",
                                 (unsigned)g_diagnostic_event_count);
    if (header_length > 0 && (size_t)header_length < sizeof(header)) {
        (void)write_all_fd(client_fd, header, (size_t)header_length);
    }

    size_t first = (g_diagnostic_event_next + DIAGNOSTIC_EVENT_CAPACITY -
                    g_diagnostic_event_count) % DIAGNOSTIC_EVENT_CAPACITY;
    for (size_t index = 0; index < g_diagnostic_event_count; index++) {
        diagnostic_event_t *event =
            &g_diagnostic_events[(first + index) % DIAGNOSTIC_EVENT_CAPACITY];
        char line[DIAGNOSTIC_EVENT_MESSAGE_CAPACITY + 64];
        int length = snprintf(line,
                              sizeof(line),
                              "EVENT\t%lld\t%s\n",
                              event->timestamp_ms,
                              event->message);
        if (length > 0 && (size_t)length < sizeof(line)) {
            (void)write_all_fd(client_fd, line, (size_t)length);
        }
    }
}

static void clear_diagnostic_events(int client_fd) {
    memset(g_diagnostic_events, 0, sizeof(g_diagnostic_events));
    g_diagnostic_event_next = 0;
    g_diagnostic_event_count = 0;
    static const char response[] = "OK cleared\n";
    (void)write_all_fd(client_fd, response, sizeof(response) - 1);
}

static void handle_client(int cfd, control_client_t client_type) {
    char buf[sizeof(g.routing) + 32];
    ssize_t n = read(cfd, buf, sizeof(buf) - 1);
    if (n <= 0) {
        return;
    }
    buf[n] = '\0';

    char reply[512];
    memset(reply, 0, sizeof(reply));

    if (client_type == CONTROL_CLIENT_BOOTSTRAP && !VCControlCommandAllowed(client_type, buf)) {
        snprintf(reply, sizeof(reply), "ERR unauthorized command\n");
        write(cfd, reply, strlen(reply));
        return;
    }
    if (client_type == CONTROL_CLIENT_CORE && !VCControlCommandAllowed(client_type, buf)) {
        snprintf(reply, sizeof(reply), "ERR unauthorized command\n");
        write(cfd, reply, strlen(reply));
        return;
    }
    if (client_type == CONTROL_CLIENT_REDSOCKS) {
        if (VCControlCommandAllowed(client_type, buf)) {
            handle_redsocks_natlook(cfd, buf);
        } else {
            (void)write_all_fd(cfd, "ERR unauthorized command\n", 25);
        }
        return;
    }

    if (client_type == CONTROL_CLIENT_APP && strncmp(buf, "LOG\t", 4) == 0) {
        char *name = buf + 4;
        char *newline = strchr(name, '\n');
        if (newline) *newline = '\0';
        if (strcmp(name, "core") == 0) {
            send_log_tail(cfd, "/var/log/vless-core.log");
        } else if (strcmp(name, "daemon") == 0) {
            send_log_tail(cfd, "/var/log/vpnctld.log");
        } else {
            (void)write_all_fd(cfd, "ERR invalid log\n", 16);
        }
        return;
    }
    if (client_type == CONTROL_CLIENT_APP && strcmp(buf, "DIAGNOSTICS\n") == 0) {
        send_safe_diagnostics(cfd);
        return;
    }
    if (client_type == CONTROL_CLIENT_APP && strcmp(buf, "EVENTS\n") == 0) {
        send_diagnostic_events(cfd);
        return;
    }
    if (client_type == CONTROL_CLIENT_APP && strcmp(buf, "CLEAR_EVENTS\n") == 0) {
        clear_diagnostic_events(cfd);
        return;
    }
    if (client_type == CONTROL_CLIENT_APP &&
        (strcmp(buf, "STORE_KEY\tGET\n") == 0 || strcmp(buf, "STORE_KEY\tCREATE\n") == 0)) {
        send_secure_store_key(cfd, strstr(buf, "\tCREATE") != NULL);
        return;
    }

    if (strncmp(buf, "STATUS", 6) == 0) {
        if (g.connected) {
            snprintf(reply, sizeof(reply), "OK connected mode=%s socks=%d redir=%d dns=%d protected=%d since=%lld\n", mode_name(g.mode), g.socks_port,
                     g.redir_port, g.dns_port, g.protect_logs ? 1 : 0, (long long)g.connected_since);
        } else {
            snprintf(reply, sizeof(reply), "OK disconnected\n");
        }
    } else if (strncmp(buf, "DISCONNECT", 10) == 0) {
        if (disconnect_all() == 0) {
            snprintf(reply, sizeof(reply), "OK disconnected\n");
        } else {
            snprintf(reply, sizeof(reply), "ERR failed to restore system PAC settings\n");
        }
    } else if (strncmp(buf, "CLEAR_LOGS", 10) == 0) {
        clear_logs();
        snprintf(reply, sizeof(reply), "OK logs cleared\n");
    } else if (strncmp(buf, "ROUTING\t", 8) == 0) {
        char *routing = buf + 8;
        char *nl = strchr(routing, '\n');
        if (nl) *nl = '\0';
        int bypass_lan = 1;
        if (!routing_payload_valid(routing, &bypass_lan)) {
            snprintf(reply, sizeof(reply), "ERR invalid routing policy\n");
        } else {
            snprintf(g.routing, sizeof(g.routing), "%s", routing);
            g.routing_bypass_lan = bypass_lan;
            log_msg("routing policy saved enabled=%c bypass_lan=%s",
                    routing[0], bypass_lan ? "yes" : "no");
            snprintf(reply, sizeof(reply), "OK routing saved\n");
        }
    } else if (strncmp(buf, "ROUTE_DIRECT_ADD\t", 17) == 0 ||
               strncmp(buf, "ROUTE_DIRECT_REMOVE\t", 20) == 0) {
        int add = strncmp(buf, "ROUTE_DIRECT_ADD\t", 17) == 0;
        char *ip = buf + (add ? 17 : 20);
        char *nl = strchr(ip, '\n');
        if (nl) *nl = '\0';
        if (route_direct_reference(ip, add) == 0) {
            snprintf(reply, sizeof(reply), "%s", add && vc_legacy_loopback_active() &&
                     !ipv4_is_permanent_bypass(ip) ? "OK hold\n" : "OK\n");
        } else {
            snprintf(reply, sizeof(reply), "ERR route bypass update failed\n");
        }
    } else if (strncmp(buf, "CONNECT\t", 8) == 0 || strncmp(buf, "CONNECT_PRIVATE\t", 16) == 0) {
        int protect_logs = strncmp(buf, "CONNECT_PRIVATE\t", 16) == 0;
        char *p = buf + (protect_logs ? 16 : 8);
        char *tab = strchr(p, '\t');
        if (!tab) {
            snprintf(reply, sizeof(reply), "ERR malformed CONNECT\n");
        } else {
            *tab = '\0';
            int port = atoi(p);

            char *payload = tab + 1;
            char *nl = strchr(payload, '\n');
            if (nl) *nl = '\0';

            char *xray_version = NULL;
            char *uri = payload;
            if (!is_supported_config_uri(payload)) {
                char *version_tab = strchr(payload, '\t');
                if (version_tab) {
                    *version_tab = '\0';
                    xray_version = payload;
                    uri = version_tab + 1;
                }
            }

            if (xray_version && !xray_version_valid(xray_version)) {
                snprintf(reply, sizeof(reply), "ERR invalid Xray version\n");
            } else if (!is_supported_config_uri(uri)) {
                snprintf(reply, sizeof(reply), "ERR unsupported configuration URI scheme\n");
            } else {
                connect_all(uri, xray_version, port, protect_logs, reply, sizeof(reply));
                strncat(reply, "\n", sizeof(reply) - strlen(reply) - 1);
            }
        }
    } else {
        snprintf(reply, sizeof(reply), "ERR unknown command\n");
    }

    write(cfd, reply, strlen(reply));
}

static void reject_control_client(int client_fd,
                                  const control_auth_diagnostic_t *diagnostic) {
    if (!diagnostic ||
        (diagnostic->failure == CONTROL_AUTH_FAILURE_PEER_PID &&
         diagnostic->error_number == ENOTCONN)) {
        return;
    }

    const char *reason = control_auth_failure_name(diagnostic->failure);
    if (should_record_auth_failure(diagnostic->failure)) {
        char safe_executable[PATH_MAX];
        sanitize_control_text(diagnostic->executable,
                              safe_executable,
                              sizeof(safe_executable));
        if (safe_executable[0]) {
            log_warning("control authorization rejected reason=%s errno=%d pid=%d executable=%s",
                        reason,
                        diagnostic->error_number,
                        (int)diagnostic->peer_pid,
                        safe_executable);
        } else {
            log_warning("control authorization rejected reason=%s errno=%d pid=%d",
                        reason,
                        diagnostic->error_number,
                        (int)diagnostic->peer_pid);
        }
        diagnostic_event("Control authorization rejected reason=%s errno=%d",
                         reason,
                         diagnostic->error_number);
    }

    char response[192];
    int response_length;
    if (diagnostic->executable[0]) {
        response_length = snprintf(response,
                                   sizeof(response),
                                   "ERR unauthorized client reason=%s errno=%d executable_class=%s\n",
                                   reason,
                                   diagnostic->error_number,
                                   control_executable_class(diagnostic->executable));
    } else {
        response_length = snprintf(response,
                                   sizeof(response),
                                   "ERR unauthorized client reason=%s errno=%d\n",
                                   reason,
                                   diagnostic->error_number);
    }
    if (response_length > 0 && (size_t)response_length < sizeof(response)) {
        (void)write_all_fd(client_fd, response, (size_t)response_length);
    }
}

int main(int argc, char **argv) {
    int launched_by_launchd = argc == 2 && strcmp(argv[1], "--launchd") == 0;
    if (argc != 1 && !launched_by_launchd) return 1;

    umask(0077);
    if (geteuid() != 0 || chdir("/") != 0) return 1;
    close_inherited_descriptors();
    g_instance_lock_fd = acquire_instance_lock(launched_by_launchd);
    if (g_instance_lock_fd < 0) {
        if (!launched_by_launchd && (errno == EACCES || errno == EAGAIN)) return 0;
        log_error("daemon instance lock unavailable errno=%d", errno);
        return 1;
    }
    if (load_helper_identity() != 0) return 1;
    (void)chmod("/var/log/vpnctld.log", 0600);
    (void)chmod("/var/log/vless-core.log", 0600);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_term_signal;
    sigemptyset(&sa.sa_mask);
    (void)sigaction(SIGTERM, &sa, NULL);
    (void)sigaction(SIGINT, &sa, NULL);
    (void)sigaction(SIGHUP, &sa, NULL);

    signal(SIGPIPE, SIG_IGN);
    memset(&g, 0, sizeof(g));
    snprintf(g.routing, sizeof(g.routing), "0;proxy;1");
    g.routing_bypass_lan = 1;
#if defined(__LP64__)
    if (vc_system_proxy_restore_stale() != 0) {
        log_error("fatal: cannot restore stale system PAC settings");
        return 1;
    }
#endif
    if (recover_stale_pf_state() != 0) {
        log_error("fatal: cannot restore stale PF state");
        return 1;
    }
    if (vc_legacy_dns_stop() != 0 || vc_legacy_loopback_stop() != 0) {
        log_error("fatal: cannot restore stale iOS 5 DNS/routes");
        return 1;
    }
    update_vpn_icon_state(0);

    int lfd = bind_control_socket();
    if (lfd < 0) {
        log_error("fatal: cannot bind daemon control socket");
        return 1;
    }
    g_listen_fd = lfd;
    log_msg("daemon control socket ready");
    diagnostic_event("Daemon ready");

    for (;;) {
        if (g_terminate) break;

        monitor_connected_children();

        fd_set read_fds;
        FD_ZERO(&read_fds);
        FD_SET(lfd, &read_fds);
        struct timeval monitor_timeout;
        struct timeval *timeout_ptr = NULL;
        if (g.connected) {
            monitor_timeout.tv_sec = 1;
            monitor_timeout.tv_usec = 0;
            timeout_ptr = &monitor_timeout;
        }

        int ready = select(lfd + 1, &read_fds, NULL, NULL, timeout_ptr);
        if (ready < 0) {
            if (errno == EINTR) continue;
            log_error("control socket select failed errno=%d", errno);
            break;
        }
        if (ready == 0) continue;

        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR && !g_terminate) continue;
            break;
        }

        monitor_connected_children();

        control_auth_diagnostic_t auth_diagnostic;
        control_client_t client_type = control_client_type(cfd, &auth_diagnostic);
        if (client_type == CONTROL_CLIENT_UNAUTHORIZED) {
            reject_control_client(cfd, &auth_diagnostic);
            close(cfd);
            continue;
        }

        struct timeval timeout;
        timeout.tv_sec = 2;
        timeout.tv_usec = 0;
        (void)setsockopt(cfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        (void)setsockopt(cfd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        handle_client(cfd, client_type);
        close(cfd);
    }

    (void)disconnect_all();
    unlink(VC_DAEMON_SOCKET_PATH);
    if (lfd >= 0) {
        close(lfd);
    }
    g_listen_fd = -1;
    close(g_instance_lock_fd);
    g_instance_lock_fd = -1;
    return 0;
}
