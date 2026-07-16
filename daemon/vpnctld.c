#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <net/if.h>
#include <netinet/in.h>
#include <pthread.h>
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
#include <dirent.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
extern int notify_post(const char *name);

typedef enum {
    MODE_NONE = 0,
    MODE_PF = 1,
} vpn_mode_t;

typedef struct {
    int connected;
    int socks_port;
    int redir_port;
    int dns_port;
    pid_t core_pid;
    pid_t redsocks_pid;
    pid_t dns_pid;
    vpn_mode_t mode;
    int pf_enabled_before;
    char server_ip[64];
    char server_ips[512];
} vpn_state_t;

static vpn_state_t g;
static const char *kVPNIconStatePath = "/var/mobile/Library/Preferences/com.vlesscore.vpnicon.state";
static const char *kVPNIconDarwinNotify = "com.vlesscore.vpnicon.changed";
static const char *kDaemonPortPath = "/var/run/vpnctld.port";
static const char *kDNSCachePath = "/var/run/vlesscore-dns-cache.txt";
static const int kDaemonPortDefault = 9093;
static const int kDaemonPortMax = 9113;
static const int kConnectResolveTimeoutMs = 8000;
static volatile sig_atomic_t g_terminate = 0;
static int g_listen_fd = -1;

static void stop_pid(pid_t *p);
static void truncate_log_file(const char *path);

static void handle_term_signal(int sig) {
    (void)sig;
    g_terminate = 1;
    if (g_listen_fd >= 0) {
        close(g_listen_fd);
        g_listen_fd = -1;
    }
}

static void log_msg(const char *fmt, ...) {
    struct timeval tv;
    gettimeofday(&tv, NULL);

    fprintf(stderr, "[%ld.%03ld] ", (long)tv.tv_sec, (long)(tv.tv_usec / 1000));
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    fflush(stderr);
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
        log_msg("%s: waitpid errno=%d", label ? label : "run", errno);
        return -1;
    }
    if (WIFEXITED(status)) {
        int st = WEXITSTATUS(status);
        log_msg("%s: rc=%d", label ? label : "run", st);
        return st;
    }

    log_msg("%s: abnormal exit", label ? label : "run");
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
    int rc = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) {
        log_msg("run: spawn errno=%d", rc);
        return -1;
    }

    return wait_spawned(pid, "run");
}

static int run_argv_capture(char *const argv[], char *out, size_t out_cap) {
    if (!argv || !argv[0] || !out || out_cap == 0) return -1;
    out[0] = '\0';

    log_argv_command("run", argv);

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        log_msg("run: pipe errno=%d", errno);
        return -1;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[1]);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(pipefd[1]);

    if (rc != 0) {
        close(pipefd[0]);
        log_msg("run: spawn errno=%d", rc);
        return -1;
    }

    size_t used = 0;
    for (;;) {
        char buf[512];
        ssize_t rd = read(pipefd[0], buf, sizeof(buf));
        if (rd < 0) {
            if (errno == EINTR) continue;
            close(pipefd[0]);
            (void)wait_spawned(pid, "run");
            log_msg("run: read errno=%d", errno);
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

    return wait_spawned(pid, "run");
}

static int can_exec(const char *path) {
    return access(path, X_OK) == 0;
}

static int find_cmd_path(const char *cmd, char *out, size_t out_cap) {
    if (!cmd || !*cmd || strchr(cmd, '/') || !out || out_cap == 0) return -1;

    const char *path = getenv("PATH");
    if (!path || !*path) {
        path = "/sbin:/usr/sbin:/bin:/usr/bin:/usr/local/sbin:/usr/local/bin";
    }

    const char *p = path;
    while (p && *p) {
        const char *colon = strchr(p, ':');
        size_t dir_len = colon ? (size_t)(colon - p) : strlen(p);

        char candidate[PATH_MAX];
        if (dir_len == 0) {
            if (snprintf(candidate, sizeof(candidate), "./%s", cmd) < 0) return -1;
        } else {
            if (dir_len >= sizeof(candidate)) return -1;
            char dir[PATH_MAX];
            memcpy(dir, p, dir_len);
            dir[dir_len] = '\0';
            if (snprintf(candidate, sizeof(candidate), "%s/%s", dir, cmd) < 0) return -1;
        }

        if (can_exec(candidate)) {
            if (strlen(candidate) >= out_cap) return -1;
            snprintf(out, out_cap, "%s", candidate);
            return 0;
        }

        if (!colon) break;
        p = colon + 1;
    }

    return -1;
}

static int path_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static int write_all_fd(int fd, const char *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t wr = write(fd, buf + off, len - off);
        if (wr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (wr == 0) return -1;
        off += (size_t)wr;
    }
    return 0;
}

static char *base64_encode_bytes(const unsigned char *data, size_t len, size_t *out_len) {
    static const char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t enc_len = ((len + 2) / 3) * 4;
    char *out = (char *)malloc(enc_len + 1);
    if (!out) return NULL;

    size_t i = 0;
    size_t j = 0;
    while (i < len) {
        unsigned int a = data[i++];
        unsigned int b = (i < len) ? data[i++] : 0;
        unsigned int c = (i < len) ? data[i++] : 0;

        unsigned int triple = (a << 16) | (b << 8) | c;
        out[j++] = table[(triple >> 18) & 0x3F];
        out[j++] = table[(triple >> 12) & 0x3F];
        out[j++] = table[(triple >> 6) & 0x3F];
        out[j++] = table[triple & 0x3F];
    }

    size_t mod = len % 3;
    if (mod == 1) {
        out[enc_len - 1] = '=';
        out[enc_len - 2] = '=';
    } else if (mod == 2) {
        out[enc_len - 1] = '=';
    }

    out[enc_len] = '\0';
    if (out_len) *out_len = enc_len;
    return out;
}

static int is_forbidden_path(const char *path) {
    if (!path || !*path) return 1;
    for (const char *p = path; *p; p++) {
        if (*p == '\n' || *p == '\r' || *p == '\t') return 1;
    }
    return 0;
}

static int path_is_under_root(const char *path, const char *root) {
    size_t n = strlen(root);
    return strncmp(path, root, n) == 0 && (path[n] == '\0' || path[n] == '/');
}

static int path_is_under_allowed_import_root(const char *path) {
    static const char *roots[] = {
        "/var/mobile",
        "/private/var/mobile",
        "/var/root",
        "/private/var/root",
    };

    for (size_t i = 0; i < sizeof(roots) / sizeof(roots[0]); i++) {
        if (path_is_under_root(path, roots[i])) {
            return 1;
        }
    }
    return 0;
}

static int resolve_allowed_import_path(const char *path, char *resolved, size_t resolved_cap) {
    if (is_forbidden_path(path) || !resolved || resolved_cap == 0) {
        return -1;
    }

    char real[PATH_MAX];
    if (!realpath(path, real)) {
        return -1;
    }

    if (!path_is_under_allowed_import_root(real)) {
        return -1;
    }

    if (strlen(real) >= resolved_cap) {
        return -1;
    }
    snprintf(resolved, resolved_cap, "%s", real);
    return 0;
}

static void reply_error(int cfd, const char *reason) {
    char msg[512];
    snprintf(msg, sizeof(msg), "ERR %s\n", reason ? reason : "unknown error");
    write_all_fd(cfd, msg, strlen(msg));
}

static void handle_listdir_command(int cfd, const char *path) {
    char resolved_path[PATH_MAX];
    if (resolve_allowed_import_path(path, resolved_path, sizeof(resolved_path)) != 0) {
        reply_error(cfd, "path is outside allowed import directory");
        return;
    }

    DIR *dir = opendir(resolved_path);
    if (!dir) {
        char reason[256];
        snprintf(reason, sizeof(reason), "cannot open directory (%s)", strerror(errno));
        reply_error(cfd, reason);
        return;
    }

    size_t cap = 64 * 1024;
    char *reply = (char *)malloc(cap);
    if (!reply) {
        closedir(dir);
        reply_error(cfd, "out of memory");
        return;
    }

    size_t used = 0;
    int hdr = snprintf(reply, cap, "OK\n");
    if (hdr < 0 || (size_t)hdr >= cap) {
        free(reply);
        closedir(dir);
        reply_error(cfd, "internal error");
        return;
    }
    used = (size_t)hdr;

    struct dirent *de = NULL;
    int entry_count = 0;
    while ((de = readdir(dir)) != NULL) {
        const char *name = de->d_name;
        if (!name || !*name) continue;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;
        if (name[0] == '.') continue;
        if (strchr(name, '\n') || strchr(name, '\r') || strchr(name, '\t')) continue;

        char full[PATH_MAX];
        int path_len = snprintf(full, sizeof(full), "%s/%s", resolved_path, name);
        if (path_len <= 0 || (size_t)path_len >= sizeof(full)) continue;

        struct stat st;
        int is_dir = (lstat(full, &st) == 0 && S_ISDIR(st.st_mode)) ? 1 : 0;

        char line[PATH_MAX + 8];
        int ln = snprintf(line, sizeof(line), "%c\t%s\n", is_dir ? 'D' : 'F', name);
        if (ln <= 0) continue;
        if (used + (size_t)ln >= cap) break;

        memcpy(reply + used, line, (size_t)ln);
        used += (size_t)ln;
        reply[used] = '\0';

        entry_count++;
        if (entry_count >= 400) break;
    }

    closedir(dir);
    write_all_fd(cfd, reply, used);
    free(reply);
}

static void handle_readfile_command(int cfd, const char *path) {
    char resolved_path[PATH_MAX];
    if (resolve_allowed_import_path(path, resolved_path, sizeof(resolved_path)) != 0) {
        reply_error(cfd, "path is outside allowed import directory");
        return;
    }

    int fd = open(resolved_path, O_RDONLY);
    if (fd < 0) {
        char reason[256];
        snprintf(reason, sizeof(reason), "cannot open file (%s)", strerror(errno));
        reply_error(cfd, reason);
        return;
    }

    size_t max_bytes = 48 * 1024;
    unsigned char *data = (unsigned char *)malloc(max_bytes);
    if (!data) {
        close(fd);
        reply_error(cfd, "out of memory");
        return;
    }

    size_t total = 0;
    while (total < max_bytes) {
        ssize_t rd = read(fd, data + total, max_bytes - total);
        if (rd < 0) {
            if (errno == EINTR) continue;
            char reason[256];
            snprintf(reason, sizeof(reason), "cannot read file (%s)", strerror(errno));
            free(data);
            close(fd);
            reply_error(cfd, reason);
            return;
        }
        if (rd == 0) break;
        total += (size_t)rd;
    }
    close(fd);

    size_t b64_len = 0;
    char *b64 = base64_encode_bytes(data, total, &b64_len);
    free(data);
    if (!b64) {
        reply_error(cfd, "encoding error");
        return;
    }

    size_t cap = b64_len + 8;
    char *reply = (char *)malloc(cap);
    if (!reply) {
        free(b64);
        reply_error(cfd, "out of memory");
        return;
    }

    int n = snprintf(reply, cap, "OK\t%s\n", b64);
    free(b64);
    if (n <= 0 || (size_t)n >= cap) {
        free(reply);
        reply_error(cfd, "internal error");
        return;
    }

    write_all_fd(cfd, reply, (size_t)n);
    free(reply);
}

static const char *mode_name(vpn_mode_t mode) {
    switch (mode) {
        case MODE_PF: return "pf+redsocks";
        default: return "none";
    }
}

static const char *find_pfctl_bin(void) {
    if (can_exec("/sbin/pfctl")) return "/sbin/pfctl";
    if (can_exec("/usr/sbin/pfctl")) return "/usr/sbin/pfctl";
    if (can_exec("/bin/pfctl")) return "/bin/pfctl";
    if (can_exec("/usr/bin/pfctl")) return "/usr/bin/pfctl";

    static char resolved[PATH_MAX];
    if (find_cmd_path("pfctl", resolved, sizeof(resolved)) == 0 && can_exec(resolved)) {
        return resolved;
    }

    return NULL;
}

static const char *find_route_bin(void) {
    if (can_exec("/sbin/route")) return "/sbin/route";
    if (can_exec("/usr/sbin/route")) return "/usr/sbin/route";
    if (can_exec("/bin/route")) return "/bin/route";
    if (can_exec("/usr/bin/route")) return "/usr/bin/route";

    static char resolved[PATH_MAX];
    if (find_cmd_path("route", resolved, sizeof(resolved)) == 0 && can_exec(resolved)) {
        return resolved;
    }

    return NULL;
}

static const char *find_ifconfig_bin(void) {
    if (can_exec("/sbin/ifconfig")) return "/sbin/ifconfig";
    if (can_exec("/usr/sbin/ifconfig")) return "/usr/sbin/ifconfig";
    if (can_exec("/bin/ifconfig")) return "/bin/ifconfig";
    if (can_exec("/usr/bin/ifconfig")) return "/usr/bin/ifconfig";

    static char resolved[PATH_MAX];
    if (find_cmd_path("ifconfig", resolved, sizeof(resolved)) == 0 && can_exec(resolved)) {
        return resolved;
    }

    return NULL;
}

static const char *find_redsocks_bin(void) {
    if (can_exec("/usr/bin/redsocks-vless-core")) return "/usr/bin/redsocks-vless-core";
    return NULL;
}

static const char *find_vless_core_bin(void) {
    if (can_exec("/usr/bin/vless-core-darwin-armv7")) return "/usr/bin/vless-core-darwin-armv7";
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

static int starts_with_ci(const char *s, const char *prefix) {
    if (!s || !prefix) return 0;
    while (*prefix) {
        char a = *s;
        char b = *prefix;
        if (!a) return 0;
        if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
        if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
        if (a != b) return 0;
        s++;
        prefix++;
    }
    return 1;
}

static int contains_ci(const char *haystack, const char *needle) {
    if (!haystack || !needle) return 0;
    if (!*needle) return 1;

    for (const char *p = haystack; *p; p++) {
        if (starts_with_ci(p, needle)) return 1;
    }
    return 0;
}

static int is_supported_config_uri(const char *uri) {
    return starts_with_ci(uri, "vless://") || starts_with_ci(uri, "socks5://");
}

static int parse_server_host(const char *uri, char *out, size_t out_cap) {
    size_t scheme_len = 0;
    if (starts_with_ci(uri, "vless://")) {
        scheme_len = 8;
    } else if (starts_with_ci(uri, "socks5://")) {
        scheme_len = 9;
    } else {
        return -1;
    }

    const char *authority = uri + scheme_len;
    const char *authority_end = authority;
    while (*authority_end && *authority_end != '/' && *authority_end != '?' && *authority_end != '#') authority_end++;

    const char *host = authority;
    for (const char *p = authority; p < authority_end; p++) {
        if (*p == '@') host = p + 1;
    }
    if (host >= authority_end) return -1;

    const char *end = host;
    if (*host == '[') {
        host++;
        end = host;
        while (end < authority_end && *end != ']') end++;
        if (end >= authority_end) return -1;
    } else {
        while (end < authority_end && *end != ':') end++;
    }

    size_t n = (size_t)(end - host);
    if (n == 0 || n >= out_cap) return -1;

    memcpy(out, host, n);
    out[n] = '\0';
    return 0;
}

static int ip_list_contains(const char *list, const char *ip) {
    if (!list || !ip || !*ip) return 0;

    size_t ip_len = strlen(ip);
    const char *p = list;

    while (*p) {
        while (*p == ' ' || *p == ',') p++;
        if (!*p) break;

        const char *start = p;
        while (*p && *p != ',') p++;
        const char *end = p;
        while (end > start && *(end - 1) == ' ') end--;

        size_t len = (size_t)(end - start);
        if (len == ip_len && strncmp(start, ip, ip_len) == 0) {
            return 1;
        }
    }

    return 0;
}

static int ip_list_append(char *list, size_t list_cap, const char *ip) {
    if (!list || !ip || !*ip) return -1;
    if (ip_list_contains(list, ip)) return 0;

    if (list[0] == '\0') {
        if (strlen(ip) >= list_cap) return -1;
        snprintf(list, list_cap, "%s", ip);
        return 0;
    }

    size_t cur = strlen(list);
    size_t need = cur + 2 + strlen(ip) + 1;
    if (need > list_cap) return -1;

    snprintf(list + cur, list_cap - cur, ", %s", ip);
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
    long long deadline = now_ms() + timeout_ms;

    while (got < sizeof(*out)) {
        long long remaining = deadline - now_ms();
        if (remaining <= 0) return -2;

        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(fd, &rfds);

        struct timeval tv;
        memset(&tv, 0, sizeof(tv));
        tv.tv_sec = (time_t)(remaining / 1000);
        tv.tv_usec = (suseconds_t)((remaining % 1000) * 1000);

        int sr = select(fd + 1, &rfds, NULL, NULL, &tv);
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
        log_msg("resolver pipe failed errno=%d", errno);
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        log_msg("resolver fork failed errno=%d", errno);
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

static int ifname_is_safe(const char *ifname) {
    if (!ifname || !*ifname) return 0;

    for (const char *p = ifname; *p; p++) {
        char c = *p;
        if ((c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') ||
            c == '_' || c == '-' || c == '.') {
            continue;
        }
        return 0;
    }
    return 1;
}

static int ifname_exists(const char *ifname) {
    if (!ifname || !*ifname) return 0;
    return if_nametoindex(ifname) != 0;
}

static int pf_interface_allowed(const char *ifname) {
    if (!ifname) return 0;
    if (strncmp(ifname, "en", 2) == 0) return 1;
    if (strncmp(ifname, "pdp_ip", 6) == 0) return 1;
    return 0;
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

static int spawn_logged(const char *bin, char *const argv[], pid_t *pid_out) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);

    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/var/log/vless-core.log", O_WRONLY | O_CREAT | O_APPEND, 0644);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/var/log/vless-core.log", O_WRONLY | O_CREAT | O_APPEND, 0644);

    pid_t pid = 0;
    int rc = posix_spawn(&pid, bin, &actions, NULL, argv, environ);

    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) return -1;

    *pid_out = pid;
    return 0;
}

static int spawn_core(const char *uri, int port, pid_t *pid_out) {
    const char *core_bin = find_vless_core_bin();
    if (!core_bin) return -2;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", port);

    char *argv[] = {
        (char *)core_bin,
        "--uri",
        (char *)uri,
        "--listen-port",
        port_str,
        NULL,
    };

    return spawn_logged(core_bin, argv, pid_out);
}

static int write_redsocks_conf(int socks_port, int redir_port, const char *redirector) {
    FILE *fp = fopen("/var/run/vlesscore-redsocks.conf", "w");
    if (!fp) return -1;

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

    fclose(fp);
    return (rc > 0) ? 0 : -1;
}

static int pid_alive(pid_t pid) {
    if (pid <= 0) return 0;

    int status = 0;
    pid_t rc = waitpid(pid, &status, WNOHANG);
    if (rc == 0) {
        return 1;
    }
    if (rc == pid) {
        if (WIFEXITED(status)) {
            log_msg("pid=%d exited, status=%d", (int)pid, WEXITSTATUS(status));
        } else if (WIFSIGNALED(status)) {
            log_msg("pid=%d terminated by signal=%d", (int)pid, WTERMSIG(status));
        } else {
            log_msg("pid=%d exited", (int)pid);
        }
        return 0;
    }
    return 0;
}

static int spawn_redsocks(int socks_port, const char *const *redirectors, size_t redirector_count, int *redir_port_out, pid_t *pid_out) {
    const char *bin = find_redsocks_bin();
    if (!bin) return -2;

    int redir_port = pick_free_port_range(12080, 12180);
    if (redir_port <= 0) return -3;

    const char *fallback_redirectors[] = {"generic"};
    if (!redirectors || redirector_count == 0) {
        redirectors = fallback_redirectors;
        redirector_count = sizeof(fallback_redirectors) / sizeof(fallback_redirectors[0]);
    }

    for (size_t i = 0; i < redirector_count; i++) {
        const char *redir = redirectors[i];
        if (write_redsocks_conf(socks_port, redir_port, redir) != 0) {
            return -4;
        }

        char *argv[] = {
            (char *)bin,
            "-c",
            "/var/run/vlesscore-redsocks.conf",
            NULL,
        };

        pid_t pid = 0;
        if (spawn_logged(bin, argv, &pid) != 0) {
            continue;
        }

        usleep(300000);
        if (!pid_alive(pid)) {
            stop_pid(&pid);
            log_msg("redsocks failed with redirector=%s, trying next", redir);
            continue;
        }

        log_msg("redsocks started pid=%d redirector=%s port=%d", (int)pid, redir, redir_port);
        *pid_out = pid;
        *redir_port_out = redir_port;
        return 0;
    }

    return -6;
}

#define DNS_PROXY_UPSTREAM_IP "1.1.1.1"
#define DNS_PROXY_UPSTREAM_PORT 53
#define DNS_PROXY_TIMEOUT_MS 6000
#define DNS_PROXY_MAX_PACKET 4096
#define DNS_PROXY_WORKER_COUNT 8
#define DNS_PROXY_IDLE_POLL_MS 250
#define DNS_PROXY_REUSE_IDLE_MS 3000

static void set_fd_timeout_ms(int fd, int timeout_ms) {
    struct timeval tv;
    memset(&tv, 0, sizeof(tv));
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    (void)setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    (void)setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
}

static int tcp_write_all_fd(int fd, const void *buf, size_t len) {
    const unsigned char *p = (const unsigned char *)buf;
    size_t off = 0;
    while (off < len) {
        ssize_t n = send(fd, p + off, len - off, 0);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

static int tcp_read_exact_fd(int fd, void *buf, size_t len) {
    unsigned char *p = (unsigned char *)buf;
    size_t off = 0;
    while (off < len) {
        ssize_t n = recv(fd, p + off, len - off, 0);
        if (n <= 0) return -1;
        off += (size_t)n;
    }
    return 0;
}

static int read_socks5_addr_tail(int fd, unsigned char atyp) {
    unsigned char tmp[260];
    size_t len = 0;
    if (atyp == 0x01) {
        len = 4 + 2;
    } else if (atyp == 0x04) {
        len = 16 + 2;
    } else if (atyp == 0x03) {
        unsigned char dlen = 0;
        if (tcp_read_exact_fd(fd, &dlen, 1) != 0) return -1;
        len = (size_t)dlen + 2;
    } else {
        return -1;
    }
    if (len > sizeof(tmp)) return -1;
    return tcp_read_exact_fd(fd, tmp, len);
}

static int dns_proxy_open_socks_tcp(int socks_port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    set_fd_timeout_ms(fd, DNS_PROXY_TIMEOUT_MS);

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = inet_addr("127.0.0.1");
    sa.sin_port = htons((uint16_t)socks_port);

    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        return -1;
    }

    unsigned char hello[] = {0x05, 0x01, 0x00};
    unsigned char method[2];
    if (tcp_write_all_fd(fd, hello, sizeof(hello)) != 0 ||
        tcp_read_exact_fd(fd, method, sizeof(method)) != 0 ||
        method[0] != 0x05 || method[1] != 0x00) {
        close(fd);
        return -1;
    }

    struct in_addr dns_ip;
    if (inet_pton(AF_INET, DNS_PROXY_UPSTREAM_IP, &dns_ip) != 1) {
        close(fd);
        return -1;
    }

    unsigned char req[10];
    req[0] = 0x05;
    req[1] = 0x01;
    req[2] = 0x00;
    req[3] = 0x01;
    memcpy(req + 4, &dns_ip, 4);
    req[8] = (unsigned char)((DNS_PROXY_UPSTREAM_PORT >> 8) & 0xff);
    req[9] = (unsigned char)(DNS_PROXY_UPSTREAM_PORT & 0xff);

    unsigned char resp[4];
    if (tcp_write_all_fd(fd, req, sizeof(req)) != 0 ||
        tcp_read_exact_fd(fd, resp, sizeof(resp)) != 0 ||
        resp[0] != 0x05 ||
        resp[1] != 0x00 ||
        read_socks5_addr_tail(fd, resp[3]) != 0) {
        close(fd);
        return -1;
    }

    return fd;
}

static int dns_proxy_query_tcp(int socks_port, int *upstream_fd, const unsigned char *query, size_t query_len, unsigned char *reply,
                               size_t reply_cap, size_t *reply_len, int *error_out) {
    if (reply_len) *reply_len = 0;
    if (error_out) *error_out = 0;
    if (!upstream_fd || !query || query_len < 2 || query_len > 0xffff || !reply || reply_cap < 2) {
        if (error_out) *error_out = EINVAL;
        return -1;
    }

    for (int attempt = 0; attempt < 2; attempt++) {
        if (*upstream_fd < 0) {
            *upstream_fd = dns_proxy_open_socks_tcp(socks_port);
            if (*upstream_fd < 0) {
                if (error_out) *error_out = errno;
                continue;
            }
        }

        int fd = *upstream_fd;
        unsigned char lenbuf[2];
        lenbuf[0] = (unsigned char)((query_len >> 8) & 0xff);
        lenbuf[1] = (unsigned char)(query_len & 0xff);

        if (tcp_write_all_fd(fd, lenbuf, sizeof(lenbuf)) == 0 &&
            tcp_write_all_fd(fd, query, query_len) == 0 &&
            tcp_read_exact_fd(fd, lenbuf, sizeof(lenbuf)) == 0) {
            size_t n = ((size_t)lenbuf[0] << 8) | (size_t)lenbuf[1];
            if (n >= 2 && n <= reply_cap && tcp_read_exact_fd(fd, reply, n) == 0 && reply[0] == query[0] && reply[1] == query[1]) {
                if (reply_len) *reply_len = n;
                return 0;
            }
            if (n < 2 || n > reply_cap || (n >= 2 && (reply[0] != query[0] || reply[1] != query[1]))) {
                errno = EPROTO;
            }
        }

        if (error_out) *error_out = errno;
        close(fd);
        *upstream_fd = -1;
    }

    return -1;
}

static int dns_read_u16(const unsigned char *buf, size_t len, size_t pos, uint16_t *out) {
    if (!buf || !out || pos + 2 > len) return -1;
    *out = (uint16_t)(((uint16_t)buf[pos] << 8) | (uint16_t)buf[pos + 1]);
    return 0;
}

static int dns_read_u32(const unsigned char *buf, size_t len, size_t pos, uint32_t *out) {
    if (!buf || !out || pos + 4 > len) return -1;
    *out = ((uint32_t)buf[pos] << 24) | ((uint32_t)buf[pos + 1] << 16) | ((uint32_t)buf[pos + 2] << 8) | (uint32_t)buf[pos + 3];
    return 0;
}

static int dns_skip_name(const unsigned char *msg, size_t len, size_t *pos) {
    if (!msg || !pos || *pos >= len) return -1;

    while (*pos < len) {
        unsigned char c = msg[*pos];
        if (c == 0) {
            (*pos)++;
            return 0;
        }
        if ((c & 0xc0) == 0xc0) {
            if (*pos + 2 > len) return -1;
            *pos += 2;
            return 0;
        }
        if ((c & 0xc0) != 0) return -1;
        *pos += (size_t)c + 1;
    }

    return -1;
}

static int dns_query_name(const unsigned char *query, size_t len, char *out, size_t out_cap) {
    if (!query || len < 13 || !out || out_cap == 0) return -1;

    size_t pos = 12;
    size_t off = 0;
    out[0] = '\0';

    while (pos < len) {
        unsigned char lab_len = query[pos++];
        if (lab_len == 0) {
            if (off == 0) return -1;
            out[off] = '\0';
            return 0;
        }
        if ((lab_len & 0xc0) != 0 || lab_len > 63 || pos + lab_len > len) return -1;
        if (off != 0) {
            if (off + 1 >= out_cap) return -1;
            out[off++] = '.';
        }
        if (off + lab_len >= out_cap) return -1;
        for (unsigned int i = 0; i < lab_len; i++) {
            unsigned char ch = query[pos + i];
            if (ch <= 0x20 || ch >= 0x7f || ch == '\t') return -1;
            out[off++] = (char)ch;
        }
        pos += lab_len;
    }

    return -1;
}

static void dns_cache_append_mapping(const char *ip, const char *name) {
    if (!ip || !*ip || !name || !*name) return;

    int fd = open(kDNSCachePath, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;

    char line[512];
    int n = snprintf(line, sizeof(line), "%s\t%s\n", ip, name);
    if (n > 0 && (size_t)n < sizeof(line)) {
        (void)write(fd, line, (size_t)n);
    }
    close(fd);
}

static void dns_cache_store_a_answers(const unsigned char *query, size_t query_len, const unsigned char *reply, size_t reply_len) {
    char name[256];
    if (dns_query_name(query, query_len, name, sizeof(name)) != 0) return;
    if (!reply || reply_len < 12) return;

    uint16_t qdcount = 0;
    uint16_t ancount = 0;
    if (dns_read_u16(reply, reply_len, 4, &qdcount) != 0 || dns_read_u16(reply, reply_len, 6, &ancount) != 0) return;

    size_t pos = 12;
    for (uint16_t i = 0; i < qdcount; i++) {
        if (dns_skip_name(reply, reply_len, &pos) != 0 || pos + 4 > reply_len) return;
        pos += 4;
    }

    for (uint16_t i = 0; i < ancount; i++) {
        if (dns_skip_name(reply, reply_len, &pos) != 0 || pos + 10 > reply_len) return;

        uint16_t type = 0;
        uint16_t klass = 0;
        uint16_t rdlen = 0;
        uint32_t ttl = 0;
        if (dns_read_u16(reply, reply_len, pos, &type) != 0 ||
            dns_read_u16(reply, reply_len, pos + 2, &klass) != 0 ||
            dns_read_u32(reply, reply_len, pos + 4, &ttl) != 0 ||
            dns_read_u16(reply, reply_len, pos + 8, &rdlen) != 0) {
            return;
        }
        (void)ttl;
        pos += 10;
        if (pos + rdlen > reply_len) return;

        if (type == 1 && klass == 1 && rdlen == 4) {
            char ip[64];
            if (inet_ntop(AF_INET, reply + pos, ip, (socklen_t)sizeof(ip)) != NULL) {
                dns_cache_append_mapping(ip, name);
            }
        }
        pos += rdlen;
    }
}

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
            log_msg("dns proxy worker=%d recv failed errno=%d", worker->index, errno);
            continue;
        }
        if (n < 12) {
            continue;
        }

        size_t reply_len = 0;
        int error_no = 0;
        if (dns_proxy_query_tcp(worker->socks_port, &upstream_fd, query, (size_t)n, reply, sizeof(reply), &reply_len, &error_no) != 0) {
            log_msg("dns proxy query failed worker=%d bytes=%ld errno=%d", worker->index, (long)n, error_no);
            continue;
        }
        upstream_last_used_ms = now_ms();

        dns_cache_store_a_answers(query, (size_t)n, reply, reply_len);
        if (sendto(worker->udp_fd, reply, reply_len, 0, (struct sockaddr *)&peer, peer_len) < 0) {
            log_msg("dns proxy worker=%d reply failed errno=%d", worker->index, errno);
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
            log_msg("dns proxy worker=%d start failed error=%d", i, thread_rc);
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

    truncate_log_file(kDNSCachePath);

    pid_t pid = fork();
    if (pid < 0) {
        close(udp_fd);
        return -2;
    }

    if (pid == 0) {
        if (g_listen_fd >= 0) {
            close(g_listen_fd);
            g_listen_fd = -1;
        }
        dns_proxy_loop(udp_fd, socks_port);
        _exit(0);
    }

    close(udp_fd);
    usleep(100000);
    if (!pid_alive(pid)) {
        stop_pid(&pid);
        return -3;
    }

    log_msg("dns proxy started pid=%d port=%d", (int)pid, dns_port);
    if (dns_port_out) *dns_port_out = dns_port;
    if (pid_out) *pid_out = pid;
    return 0;
}

static void truncate_log_file(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        close(fd);
    }
}

static void clear_logs(void) {
    truncate_log_file("/var/log/vpnctld.log");
    truncate_log_file("/var/log/vless-core.log");
}

static void update_vpn_icon_state(int enabled) {
    int fd = open(kVPNIconStatePath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        const char *v = enabled ? "1\n" : "0\n";
        (void)write(fd, v, strlen(v));
        close(fd);
    }

    int rc = notify_post(kVPNIconDarwinNotify);
    if (rc != 0) {
        log_msg("notify_post(%s) rc=%d", kVPNIconDarwinNotify, rc);
    }
}

static void write_daemon_port_file(int port) {
    int fd = open(kDaemonPortPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        log_msg("cannot write %s errno=%d", kDaemonPortPath, errno);
        return;
    }

    char buf[32];
    int n = snprintf(buf, sizeof(buf), "%d\n", port);
    if (n > 0) {
        (void)write(fd, buf, (size_t)n);
    }
    close(fd);
}

static int try_bind_listen(int port, int *lfd_out) {
    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0) {
        log_msg("socket() failed errno=%d", errno);
        return -1;
    }

    int one = 1;
    (void)setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = inet_addr("127.0.0.1");
    sa.sin_port = htons((uint16_t)port);

    if (bind(lfd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        log_msg("bind(127.0.0.1:%d) failed errno=%d", port, errno);
        close(lfd);
        return -1;
    }

    if (listen(lfd, 16) != 0) {
        log_msg("listen(%d) failed errno=%d", port, errno);
        close(lfd);
        return -1;
    }

    *lfd_out = lfd;
    return 0;
}

static void stop_pid(pid_t *p) {
    if (*p <= 0) return;

    kill(*p, SIGTERM);
    usleep(300000);
    kill(*p, SIGKILL);
    waitpid(*p, NULL, 0);
    *p = 0;
}

typedef enum {
    PF_RULE_ROUTE_TO_LO0 = 0,
    PF_RULE_ROUTE_TO_LO0_NOGW = 1,
    PF_RULE_DIVERT_TO = 2,
    PF_RULE_DIVERT_TO_OLD = 3,
    PF_RULE_RDR_TO = 4,
    PF_RULE_RDR_TO_OLD = 5,
    PF_RULE_LEGACY_RDR = 6,
} pf_rule_mode_t;

static const char *pf_rule_mode_name(pf_rule_mode_t mode) {
    switch (mode) {
        case PF_RULE_ROUTE_TO_LO0: return "route-to-lo0+rdr";
        case PF_RULE_ROUTE_TO_LO0_NOGW: return "route-to-lo0-nogw+rdr";
        case PF_RULE_DIVERT_TO: return "divert-to";
        case PF_RULE_DIVERT_TO_OLD: return "divert-to-old";
        case PF_RULE_RDR_TO: return "rdr-to";
        case PF_RULE_RDR_TO_OLD: return "rdr-to-old";
        case PF_RULE_LEGACY_RDR: return "legacy-rdr";
        default: return "unknown";
    }
}

static int write_pf_conf(const char *server_ips, char ifnames[][32], size_t if_count, int redir_port, int dns_port, pf_rule_mode_t mode) {
    FILE *fp = fopen("/var/run/vlesscore-pf.conf", "w");
    if (!fp) return -1;

    if (!server_ips || !*server_ips || !ifnames || if_count == 0) {
        fclose(fp);
        return -1;
    }

    if (mode == PF_RULE_ROUTE_TO_LO0) {
        if (fprintf(fp,
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "nat on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1\n",
                ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp,
            "rdr pass on lo0 inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n",
            redir_port) < 0) {
            fclose(fp);
            return -1;
        }
        if (fprintf(fp,
            "rdr pass on lo0 inet proto udp from any to any port 53 -> 127.0.0.1 port %d\n",
            dns_port) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s route-to (lo0 127.0.0.1) inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s route-to (lo0 127.0.0.1) inet proto udp from any to any port 53 keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else if (mode == PF_RULE_ROUTE_TO_LO0_NOGW) {
        if (fprintf(fp,
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "nat on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1\n",
                ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp,
            "rdr pass on lo0 inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n",
            redir_port) < 0) {
            fclose(fp);
            return -1;
        }
        if (fprintf(fp,
            "rdr pass on lo0 inet proto udp from any to any port 53 -> 127.0.0.1 port %d\n",
            dns_port) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s route-to (lo0) inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s route-to (lo0) inet proto udp from any to any port 53 keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else if (mode == PF_RULE_DIVERT_TO) {
        if (fprintf(fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s divert-to 127.0.0.1 port %d inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s divert-to 127.0.0.1 port %d inet proto udp from any to any port 53 keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else if (mode == PF_RULE_DIVERT_TO_OLD) {
        if (fprintf(fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> divert-to 127.0.0.1 port %d keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 divert-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else if (mode == PF_RULE_RDR_TO) {
        if (fprintf(fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d flags S/SA keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 rdr-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else if (mode == PF_RULE_RDR_TO_OLD) {
        if (fprintf(fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 rdr-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    } else {
        if (fprintf(fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n",
            server_ips) < 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "rdr pass on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n",
                ifname, redir_port) < 0) {
                fclose(fp);
                return -1;
            }
            if (fprintf(fp,
                "rdr pass on %s inet proto udp from any to any port 53 -> 127.0.0.1 port %d\n",
                ifname, dns_port) < 0) {
                fclose(fp);
                return -1;
            }
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass> port 443\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

        if (fprintf(fp, "pass in all keep state\n") < 0) {
            fclose(fp);
            return -1;
        }
    }

    fclose(fp);
    return 0;
}

static int pf_is_enabled(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return 0;

    char output[4096];
    char *argv[] = {
        (char *)pfctl,
        "-s",
        "info",
        NULL,
    };
    if (run_argv_capture(argv, output, sizeof(output)) != 0) {
        return 0;
    }

    return contains_ci(output, "Status: Enabled");
}

static void ensure_pf_os_file(void) {
    if (path_exists("/etc/pf.os")) return;

    int fd = open("/etc/pf.os", O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        log_msg("cannot create /etc/pf.os errno=%d", errno);
        return;
    }

    const char *placeholder = "# vlesscore placeholder\n";
    (void)write(fd, placeholder, strlen(placeholder));
    close(fd);
    log_msg("created placeholder /etc/pf.os");
}

static void flush_pf_states(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return;

    char *argv[] = {
        (char *)pfctl,
        "-q",
        "-F",
        "states",
        NULL,
    };
    if (run_argv(argv) == 0) {
        log_msg("pf states flushed after rule load");
    }
}

static int apply_pf_rules(const char *server_ips, int redir_port, int dns_port) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) {
        log_msg("pfctl binary not found");
        return -1;
    }

    int was_enabled = pf_is_enabled();
    if (was_enabled) {
        log_msg("pf already enabled; will reload rules");
    }

    char ifnames[8][32];
    memset(ifnames, 0, sizeof(ifnames));
    size_t if_count = collect_pf_interfaces(ifnames, sizeof(ifnames) / sizeof(ifnames[0]));
    if (if_count == 0) {
        log_msg("pf: no suitable interfaces found (expected en*/pdp_ip*)");
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

    g.pf_enabled_before = was_enabled ? 1 : 0;

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
        if (run_argv(enable_argv) == 0 || pf_is_enabled()) {
            enabled_now = 1;
        } else {
            char *enable_old_argv[] = {
                (char *)pfctl,
                "-q",
                "-E",
                NULL,
            };
            if (run_argv(enable_old_argv) == 0 || pf_is_enabled()) {
                enabled_now = 1;
            }
        }
    }

    if (!enabled_now) {
        return -5;
    }

    ensure_pf_os_file();

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

    for (size_t i = 0; i < mode_count; i++) {
        pf_rule_mode_t mode = modes[i];

        if (write_pf_conf(server_ips, ifnames, if_count, redir_port, dns_port, mode) != 0) {
            continue;
        }

        log_msg("pf trying mode=%s", pf_rule_mode_name(mode));
        char *load_argv[] = {
            (char *)pfctl,
            "-q",
            "-f",
            "/var/run/vlesscore-pf.conf",
            NULL,
        };
        if (run_argv(load_argv) == 0) {
            log_msg("pf rules loaded mode=%s", pf_rule_mode_name(mode));
            flush_pf_states();
            return 0;
        }
    }

    return -4;
}

static void clear_pf_rules(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return;

    char *flush_argv[] = {
        (char *)pfctl,
        "-q",
        "-F",
        "all",
        NULL,
    };
    run_argv(flush_argv);

    if (!g.pf_enabled_before) {
        char *disable_argv[] = {
            (char *)pfctl,
            "-q",
            "-d",
            NULL,
        };
        run_argv(disable_argv);
    }

}

static void disconnect_all(void) {
    if (g.mode == MODE_PF) {
        clear_pf_rules();
    }

    stop_pid(&g.redsocks_pid);
    stop_pid(&g.dns_pid);
    stop_pid(&g.core_pid);

    unlink("/var/run/vlesscore-redsocks.conf");
    unlink(kDNSCachePath);

    memset(&g, 0, sizeof(g));
    update_vpn_icon_state(0);
}

static int try_connect_pf(int socks_port) {
    int redir_port = 0;
    const char *pf_redirectors[] = {"pf", "generic"};
    int rc = spawn_redsocks(
        socks_port,
        pf_redirectors,
        sizeof(pf_redirectors) / sizeof(pf_redirectors[0]),
        &redir_port,
        &g.redsocks_pid
    );
    if (rc != 0) {
        return -30 + rc;
    }

    usleep(300000);

    int dns_port = 0;
    if (spawn_dns_proxy(socks_port, &dns_port, &g.dns_pid) != 0) {
        clear_pf_rules();
        stop_pid(&g.redsocks_pid);
        return -45;
    }

    const char *pf_server_ips = (g.server_ips[0] != '\0') ? g.server_ips : g.server_ip;
    int pf_rc = apply_pf_rules(pf_server_ips, redir_port, dns_port);
    if (pf_rc != 0) {
        clear_pf_rules();
        stop_pid(&g.dns_pid);
        stop_pid(&g.redsocks_pid);
        return -40 + pf_rc;
    }

    g.mode = MODE_PF;
    g.connected = 1;
    g.socks_port = socks_port;
    g.redir_port = redir_port;
    g.dns_port = dns_port;
    return 0;
}

static int connect_all(const char *uri, int requested_port, char *msg, size_t msg_cap) {
    if (g.connected) {
        snprintf(msg, msg_cap, "OK already connected mode=%s socks=%d", mode_name(g.mode), g.socks_port);
        return 0;
    }

    int port = pick_port(requested_port);
    if (port <= 0) {
        snprintf(msg, msg_cap, "ERR no free local SOCKS port");
        return -1;
    }

    char host[256];
    if (parse_server_host(uri, host, sizeof(host)) != 0) {
        snprintf(msg, msg_cap, "ERR invalid config URI (cannot parse host)");
        return -1;
    }

    long long resolve_start_ms = now_ms();
    int resolve_rc = resolve_host_ipv4_all_bounded(host, g.server_ip, sizeof(g.server_ip), g.server_ips, sizeof(g.server_ips),
                                                   kConnectResolveTimeoutMs);
    if (resolve_rc == -2) {
        snprintf(msg, msg_cap, "ERR server DNS timeout after %dms", kConnectResolveTimeoutMs);
        log_msg("resolve server host %s timed out after %dms", host, kConnectResolveTimeoutMs);
        return -1;
    }
    if (resolve_rc != 0) {
        snprintf(msg, msg_cap, "ERR failed to resolve server host");
        return -1;
    }

    log_msg("resolved server host %s -> %s in %lldms", host, g.server_ips, now_ms() - resolve_start_ms);

    if (spawn_core(uri, port, &g.core_pid) != 0) {
        snprintf(msg, msg_cap, "ERR failed to start vless-core binary");
        disconnect_all();
        return -1;
    }

    usleep(500000);

    int pf_rc = try_connect_pf(port);
    if (pf_rc == 0) {
        update_vpn_icon_state(1);
        snprintf(msg, msg_cap, "OK connected mode=%s socks=%d redir=%d", mode_name(g.mode), g.socks_port, g.redir_port);
        return 0;
    }

    disconnect_all();
    snprintf(msg, msg_cap, "ERR pf backend unavailable: pf_rc=%d (see /var/log/vpnctld.log)", pf_rc);
    return -1;
}

static void handle_client(int cfd) {
    char buf[4096];
    ssize_t n = read(cfd, buf, sizeof(buf) - 1);
    if (n <= 0) {
        return;
    }
    buf[n] = '\0';

    if (strncmp(buf, "LISTDIR\t", 8) == 0) {
        char *path = buf + 8;
        char *nl = strchr(path, '\n');
        if (nl) *nl = '\0';
        handle_listdir_command(cfd, path);
        return;
    } else if (strncmp(buf, "READFILE\t", 9) == 0) {
        char *path = buf + 9;
        char *nl = strchr(path, '\n');
        if (nl) *nl = '\0';
        handle_readfile_command(cfd, path);
        return;
    }

    char reply[512];
    memset(reply, 0, sizeof(reply));

    if (strncmp(buf, "STATUS", 6) == 0) {
        if (g.connected) {
            snprintf(reply, sizeof(reply), "OK connected mode=%s socks=%d redir=%d dns=%d\n", mode_name(g.mode), g.socks_port, g.redir_port,
                     g.dns_port);
        } else {
            snprintf(reply, sizeof(reply), "OK disconnected\n");
        }
    } else if (strncmp(buf, "DISCONNECT", 10) == 0) {
        disconnect_all();
        snprintf(reply, sizeof(reply), "OK disconnected\n");
    } else if (strncmp(buf, "CLEAR_LOGS", 10) == 0) {
        clear_logs();
        snprintf(reply, sizeof(reply), "OK logs cleared\n");
    } else if (strncmp(buf, "CONNECT\t", 8) == 0) {
        char *p = buf + 8;
        char *tab = strchr(p, '\t');
        if (!tab) {
            snprintf(reply, sizeof(reply), "ERR malformed CONNECT\n");
        } else {
            *tab = '\0';
            int port = atoi(p);

            char *uri = tab + 1;
            char *nl = strchr(uri, '\n');
            if (nl) *nl = '\0';

            if (!is_supported_config_uri(uri)) {
                snprintf(reply, sizeof(reply), "ERR uri must start with vless:// or socks5://\n");
            } else {
                connect_all(uri, port, reply, sizeof(reply));
                strncat(reply, "\n", sizeof(reply) - strlen(reply) - 1);
            }
        }
    } else {
        snprintf(reply, sizeof(reply), "ERR unknown command\n");
    }

    write(cfd, reply, strlen(reply));
}

int main(void) {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = handle_term_signal;
    sigemptyset(&sa.sa_mask);
    (void)sigaction(SIGTERM, &sa, NULL);
    (void)sigaction(SIGINT, &sa, NULL);
    (void)sigaction(SIGHUP, &sa, NULL);

    signal(SIGPIPE, SIG_IGN);
    memset(&g, 0, sizeof(g));
    update_vpn_icon_state(0);

    int lfd = -1;
    int bound_port = 0;
    for (int port = kDaemonPortDefault; port <= kDaemonPortMax; port++) {
        if (try_bind_listen(port, &lfd) == 0) {
            bound_port = port;
            break;
        }
    }
    if (lfd < 0) {
        log_msg("fatal: cannot bind daemon API port range %d-%d", kDaemonPortDefault, kDaemonPortMax);
        return 1;
    }
    g_listen_fd = lfd;

    if (bound_port != kDaemonPortDefault) {
        log_msg("daemon API moved to fallback port=%d", bound_port);
    } else {
        log_msg("daemon API listening on default port=%d", bound_port);
    }
    write_daemon_port_file(bound_port);

    for (;;) {
        if (g_terminate) break;

        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR && !g_terminate) continue;
            break;
        }

        handle_client(cfd);
        close(cfd);
    }

    disconnect_all();
    unlink(kDaemonPortPath);
    if (lfd >= 0) {
        close(lfd);
    }
    g_listen_fd = -1;
    return 0;
}
