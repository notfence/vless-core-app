#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netdb.h>
#include <netinet/in.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
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
    MODE_TUN = 1,
    MODE_IPFW = 2,
    MODE_PF = 3,
} vpn_mode_t;

typedef struct {
    int connected;
    int socks_port;
    int redir_port;
    pid_t v2_pid;
    pid_t tun_pid;
    pid_t redsocks_pid;
    vpn_mode_t mode;
    int pf_enabled_before;
    char gateway[64];
    char server_ip[64];
    char server_ips[512];
} vpn_state_t;

static vpn_state_t g;
static const char *kVPNIconStatePath = "/var/mobile/Library/Preferences/com.vlesscore.vpnicon.state";
static const char *kVPNIconDarwinNotify = "com.vlesscore.vpnicon.changed";

static void stop_pid(pid_t *p);

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

static int run_cmd(const char *cmd) {
    log_msg("run: %s", cmd);
    int rc = system(cmd);
    if (rc == -1) {
        log_msg("run: rc=-1 errno=%d", errno);
        return -1;
    }
    if (WIFEXITED(rc)) {
        int st = WEXITSTATUS(rc);
        log_msg("run: rc=%d", st);
        return st;
    }
    log_msg("run: abnormal exit");
    return -1;
}

static int can_exec(const char *path) {
    return access(path, X_OK) == 0;
}

static int find_cmd_path(const char *cmd, char *out, size_t out_cap) {
    char shell_cmd[128];
    snprintf(shell_cmd, sizeof(shell_cmd), "command -v %s 2>/dev/null", cmd);

    FILE *fp = popen(shell_cmd, "r");
    if (!fp) return -1;

    char line[PATH_MAX];
    if (!fgets(line, sizeof(line), fp)) {
        pclose(fp);
        return -1;
    }
    pclose(fp);

    char *nl = strchr(line, '\n');
    if (nl) *nl = '\0';
    if (line[0] == '\0') return -1;
    if (strlen(line) >= out_cap) return -1;

    snprintf(out, out_cap, "%s", line);
    return 0;
}

static int path_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

static const char *mode_name(vpn_mode_t mode) {
    switch (mode) {
        case MODE_TUN: return "tun2socks";
        case MODE_IPFW: return "ipfw+redsocks";
        case MODE_PF: return "pf+redsocks";
        default: return "none";
    }
}

static const char *find_ipfw_bin(void) {
    if (can_exec("/sbin/ipfw")) return "/sbin/ipfw";
    if (can_exec("/usr/sbin/ipfw")) return "/usr/sbin/ipfw";
    if (can_exec("/bin/ipfw")) return "/bin/ipfw";
    if (can_exec("/usr/bin/ipfw")) return "/usr/bin/ipfw";
    if (can_exec("/usr/local/sbin/ipfw")) return "/usr/local/sbin/ipfw";
    if (can_exec("/usr/local/bin/ipfw")) return "/usr/local/bin/ipfw";

    static char resolved[PATH_MAX];
    if (find_cmd_path("ipfw", resolved, sizeof(resolved)) == 0 && can_exec(resolved)) {
        return resolved;
    }

    return NULL;
}

static const char *find_sysctl_bin(void) {
    if (can_exec("/usr/sbin/sysctl")) return "/usr/sbin/sysctl";
    if (can_exec("/sbin/sysctl")) return "/sbin/sysctl";
    if (can_exec("/usr/bin/sysctl")) return "/usr/bin/sysctl";
    if (can_exec("/bin/sysctl")) return "/bin/sysctl";

    static char resolved[PATH_MAX];
    if (find_cmd_path("sysctl", resolved, sizeof(resolved)) == 0 && can_exec(resolved)) {
        return resolved;
    }

    return NULL;
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

static const char *find_redsocks_bin(void) {
    if (can_exec("/usr/bin/redsocks-v2ray")) return "/usr/bin/redsocks-v2ray";
    if (can_exec("/usr/bin/redsocks")) return "/usr/bin/redsocks";
    return NULL;
}

static const char *find_vless_core_bin(void) {
    if (can_exec("/usr/bin/vless-core-darwin-amrv7")) return "/usr/bin/vless-core-darwin-amrv7";
    return NULL;
}

static const char *find_tun2socks_bin(void) {
    if (can_exec("/usr/bin/tun2socks-v2ray")) return "/usr/bin/tun2socks-v2ray";
    if (can_exec("/usr/bin/tun2socks")) return "/usr/bin/tun2socks";
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

static int pick_port(int requested) {
    if (requested > 0) {
        return pick_free_port_range(requested, requested);
    }
    return pick_free_port_range(1083, 1183);
}

static int parse_server_host(const char *uri, char *out, size_t out_cap) {
    const char *scheme = strstr(uri, "vless://");
    if (scheme != uri) return -1;

    const char *at = strchr(uri, '@');
    if (!at) return -1;

    const char *host = at + 1;
    const char *end = host;
    while (*end && *end != ':' && *end != '?' && *end != '/' && *end != '#') end++;

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

static int read_default_gateway(char *gw, size_t gw_cap) {
    FILE *fp = popen("/sbin/route -n get default 2>/dev/null", "r");
    if (!fp) return -1;

    char line[256];
    int found = -1;
    while (fgets(line, sizeof(line), fp)) {
        char *p = strstr(line, "gateway:");
        if (!p) continue;

        p += 8;
        while (*p == ' ' || *p == '\t') p++;

        char *e = p;
        while (*e && *e != '\n' && *e != ' ' && *e != '\t') e++;
        *e = '\0';

        if (strlen(p) > 0 && strlen(p) < gw_cap) {
            snprintf(gw, gw_cap, "%s", p);
            found = 0;
            break;
        }
    }

    pclose(fp);
    return found;
}

static int read_default_interface(char *ifname, size_t ifname_cap) {
    FILE *fp = popen("/sbin/route -n get default 2>/dev/null", "r");
    if (!fp) return -1;

    char line[256];
    int found = -1;
    while (fgets(line, sizeof(line), fp)) {
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

    pclose(fp);
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

static int spawn_v2ray(const char *uri, int port, pid_t *pid_out) {
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

static int spawn_tun2socks(int socks_port, pid_t *pid_out) {
    const char *bin = find_tun2socks_bin();
    if (!bin) return -2;

    char socks[64];
    snprintf(socks, sizeof(socks), "127.0.0.1:%d", socks_port);

    char *argv[] = {
        (char *)bin,
        "--tundev",
        "tun0",
        "--netif-ipaddr",
        "10.233.233.2",
        "--netif-netmask",
        "255.255.255.0",
        "--socks-server-addr",
        socks,
        NULL,
    };

    return spawn_logged(bin, argv, pid_out);
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

static void truncate_log_file(const char *path) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        close(fd);
    }
}

static void clear_logs(void) {
    truncate_log_file("/var/log/vpnctld.log");
    truncate_log_file("/var/log/vless-core.log");
    truncate_log_file("/var/log/v2rayios6.log");
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

static void stop_pid(pid_t *p) {
    if (*p <= 0) return;

    kill(*p, SIGTERM);
    usleep(300000);
    kill(*p, SIGKILL);
    waitpid(*p, NULL, 0);
    *p = 0;
}

static void clear_ipfw_rules(void) {
    const char *ipfw = find_ipfw_bin();
    if (!ipfw) return;

    char cmd[256];
    for (int n = 12030; n >= 12000; n--) {
        snprintf(cmd, sizeof(cmd), "%s -q delete %d >/dev/null 2>&1", ipfw, n);
        run_cmd(cmd);
    }
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

static int write_pf_conf(const char *server_ips, const char *ifname, int redir_port, pf_rule_mode_t mode) {
    FILE *fp = fopen("/var/run/vlesscore-pf.conf", "w");
    if (!fp) return -1;

    int rc = 0;
    if (mode == PF_RULE_ROUTE_TO_LO0) {
        rc = fprintf(
            fp,
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "rdr pass on lo0 inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
            "pass out quick on %s route-to (lo0 127.0.0.1) inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            redir_port,
            ifname,
            ifname,
            ifname
        );
    } else if (mode == PF_RULE_ROUTE_TO_LO0_NOGW) {
        rc = fprintf(
            fp,
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "rdr pass on lo0 inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
            "pass out quick on %s route-to (lo0) inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            redir_port,
            ifname,
            ifname,
            ifname
        );
    } else if (mode == PF_RULE_DIVERT_TO) {
        rc = fprintf(
            fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
            "pass out quick on %s divert-to 127.0.0.1 port %d inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            ifname,
            ifname,
            redir_port,
            ifname
        );
    } else if (mode == PF_RULE_DIVERT_TO_OLD) {
        rc = fprintf(
            fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
            "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> divert-to 127.0.0.1 port %d keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            ifname,
            ifname,
            redir_port,
            ifname
        );
    } else if (mode == PF_RULE_RDR_TO) {
        rc = fprintf(
            fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
            "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d flags S/SA keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            ifname,
            ifname,
            redir_port,
            ifname
        );
    } else if (mode == PF_RULE_RDR_TO_OLD) {
        rc = fprintf(
            fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
            "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d keep state\n"
            "pass out on %s all keep state\n"
            "pass in all keep state\n",
            server_ips,
            ifname,
            ifname,
            redir_port,
            ifname
        );
    } else {
        rc = fprintf(
            fp,
            "set skip on lo0\n"
            "table <vlesscore_bypass> persist { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 255.255.255.255/32, %s }\n"
            "rdr pass on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n"
            "pass out all keep state\n"
            "pass in all keep state\n",
            server_ips,
            ifname,
            redir_port
        );
    }

    fclose(fp);
    return (rc > 0) ? 0 : -1;
}

static int pf_is_enabled(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return 0;

    char cmd[320];
    snprintf(cmd, sizeof(cmd), "%s -s info 2>/dev/null | grep -qi 'Status: Enabled'", pfctl);
    return run_cmd(cmd) == 0;
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

static int apply_pf_rules(const char *server_ips, int redir_port) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) {
        log_msg("pfctl binary not found");
        return -1;
    }

    int was_enabled = pf_is_enabled();
    if (was_enabled) {
        log_msg("pf already enabled; will reload rules");
    }

    char ifname[32];
    memset(ifname, 0, sizeof(ifname));
    if (read_default_interface(ifname, sizeof(ifname)) != 0 || !ifname_is_safe(ifname)) {
        snprintf(ifname, sizeof(ifname), "%s", "en0");
    }

    log_msg("pf target interface: %s", ifname);

    g.pf_enabled_before = was_enabled ? 1 : 0;

    char cmd[512];
    int enabled_now = 0;

    if (was_enabled) {
        enabled_now = 1;
    } else {
        snprintf(cmd, sizeof(cmd), "%s -e", pfctl);
        if (run_cmd(cmd) == 0 || pf_is_enabled()) {
            enabled_now = 1;
        } else {
            snprintf(cmd, sizeof(cmd), "%s -E", pfctl);
            if (run_cmd(cmd) == 0 || pf_is_enabled()) {
                enabled_now = 1;
            }
        }
    }

    if (!enabled_now) {
        return -5;
    }

    ensure_pf_os_file();

    const pf_rule_mode_t modes[] = {
        PF_RULE_ROUTE_TO_LO0,
        PF_RULE_ROUTE_TO_LO0_NOGW,
        PF_RULE_LEGACY_RDR,
        PF_RULE_DIVERT_TO_OLD,
        PF_RULE_DIVERT_TO,
        PF_RULE_RDR_TO_OLD,
        PF_RULE_RDR_TO,
    };

    for (size_t i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
        pf_rule_mode_t mode = modes[i];

        if (write_pf_conf(server_ips, ifname, redir_port, mode) != 0) {
            continue;
        }

        log_msg("pf trying mode=%s", pf_rule_mode_name(mode));
        snprintf(cmd, sizeof(cmd), "%s -f /var/run/vlesscore-pf.conf", pfctl);
        if (run_cmd(cmd) == 0) {
            log_msg("pf rules loaded mode=%s", pf_rule_mode_name(mode));
            return 0;
        }
    }

    return -4;
}

static void clear_pf_rules(void) {
    const char *pfctl = find_pfctl_bin();
    if (!pfctl) return;

    char cmd[320];
    snprintf(cmd, sizeof(cmd), "%s -F all", pfctl);
    run_cmd(cmd);

    if (!g.pf_enabled_before) {
        snprintf(cmd, sizeof(cmd), "%s -d", pfctl);
        run_cmd(cmd);
    }

}

static int add_ipfw_rule_compat(const char *ipfw, int rule_num, const char *rule_with_out, const char *rule_plain) {
    char cmd[640];
    snprintf(cmd, sizeof(cmd), "%s -q add %d %s", ipfw, rule_num, rule_with_out);
    if (run_cmd(cmd) == 0) {
        return 0;
    }

    if (rule_plain && strcmp(rule_plain, rule_with_out) != 0) {
        snprintf(cmd, sizeof(cmd), "%s -q add %d %s", ipfw, rule_num, rule_plain);
        if (run_cmd(cmd) == 0) {
            return 0;
        }
    }

    return -1;
}

static void try_enable_ipfw_firewall(void) {
    const char *sysctl = find_sysctl_bin();
    if (!sysctl) return;

    char cmd[256];
    snprintf(cmd, sizeof(cmd), "%s -w net.inet.ip.fw.enable=1", sysctl);
    run_cmd(cmd);
}

static int apply_ipfw_rules(const char *server_ip, int redir_port, int socks_port) {
    const char *ipfw = find_ipfw_bin();
    if (!ipfw) {
        log_msg("ipfw binary not found");
        return -1;
    }

    try_enable_ipfw_firewall();
    clear_ipfw_rules();

    char rule_out[320];
    char rule_plain[320];

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 127.0.0.1 out");
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 127.0.0.1");
    if (add_ipfw_rule_compat(ipfw, 12000, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to %s out", server_ip);
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to %s", server_ip);
    if (add_ipfw_rule_compat(ipfw, 12001, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 10.0.0.0/8 out");
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 10.0.0.0/8");
    if (add_ipfw_rule_compat(ipfw, 12002, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 172.16.0.0/12 out");
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 172.16.0.0/12");
    if (add_ipfw_rule_compat(ipfw, 12003, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 192.168.0.0/16 out");
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 192.168.0.0/16");
    if (add_ipfw_rule_compat(ipfw, 12004, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 127.0.0.1 %d out", socks_port);
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 127.0.0.1 %d", socks_port);
    if (add_ipfw_rule_compat(ipfw, 12005, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "allow tcp from any to 127.0.0.1 %d out", redir_port);
    snprintf(rule_plain, sizeof(rule_plain), "allow tcp from any to 127.0.0.1 %d", redir_port);
    if (add_ipfw_rule_compat(ipfw, 12006, rule_out, rule_plain) != 0) return -1;

    snprintf(rule_out, sizeof(rule_out), "fwd 127.0.0.1,%d tcp from any to any out", redir_port);
    snprintf(rule_plain, sizeof(rule_plain), "fwd 127.0.0.1,%d tcp from any to any", redir_port);
    if (add_ipfw_rule_compat(ipfw, 12020, rule_out, rule_plain) != 0) return -1;

    return 0;
}

static void cleanup_tun_side(void) {
    char cmd[256];

    if (strlen(g.gateway) > 0) {
        snprintf(cmd, sizeof(cmd), "/sbin/route -n delete default >/dev/null 2>&1");
        run_cmd(cmd);

        snprintf(cmd, sizeof(cmd), "/sbin/route -n add default %s >/dev/null 2>&1", g.gateway);
        run_cmd(cmd);
    }

    if (strlen(g.server_ip) > 0) {
        snprintf(cmd, sizeof(cmd), "/sbin/route -n delete -host %s >/dev/null 2>&1", g.server_ip);
        run_cmd(cmd);
    }

    run_cmd("/sbin/ifconfig tun0 down >/dev/null 2>&1");
    stop_pid(&g.tun_pid);
}

static void disconnect_all(void) {
    if (g.mode == MODE_TUN) {
        cleanup_tun_side();
    }

    if (g.mode == MODE_IPFW) {
        clear_ipfw_rules();
    }

    if (g.mode == MODE_PF) {
        clear_pf_rules();
    }

    stop_pid(&g.redsocks_pid);
    stop_pid(&g.v2_pid);

    unlink("/var/run/vlesscore-redsocks.conf");

    memset(&g, 0, sizeof(g));
    update_vpn_icon_state(0);
}

static int try_connect_tun(int socks_port) {
    if (!path_exists("/dev/tun0")) return -2;
    if (!find_tun2socks_bin()) return -3;

    if (read_default_gateway(g.gateway, sizeof(g.gateway)) != 0) {
        return -4;
    }

    char cmd[256];

    snprintf(cmd, sizeof(cmd), "/sbin/route -n delete -host %s >/dev/null 2>&1", g.server_ip);
    run_cmd(cmd);

    snprintf(cmd, sizeof(cmd), "/sbin/route -n add -host %s %s >/dev/null 2>&1", g.server_ip, g.gateway);
    if (run_cmd(cmd) != 0) {
        cleanup_tun_side();
        return -5;
    }

    if (run_cmd("/sbin/ifconfig tun0 10.233.233.1 10.233.233.2 netmask 255.255.255.0 up >/dev/null 2>&1") != 0) {
        cleanup_tun_side();
        return -6;
    }

    int tun_rc = spawn_tun2socks(socks_port, &g.tun_pid);
    if (tun_rc != 0) {
        cleanup_tun_side();
        return -7;
    }

    usleep(400000);

    run_cmd("/sbin/route -n delete default >/dev/null 2>&1");
    if (run_cmd("/sbin/route -n add default 10.233.233.2 >/dev/null 2>&1") != 0) {
        cleanup_tun_side();
        return -8;
    }

    g.mode = MODE_TUN;
    g.connected = 1;
    g.socks_port = socks_port;
    return 0;
}

static int try_connect_ipfw(int socks_port) {
    if (!find_ipfw_bin()) {
        log_msg("ipfw backend skipped: binary not found");
        return -21;
    }

    int redir_port = 0;
    const char *ipfw_redirectors[] = {"generic"};
    int rc = spawn_redsocks(
        socks_port,
        ipfw_redirectors,
        sizeof(ipfw_redirectors) / sizeof(ipfw_redirectors[0]),
        &redir_port,
        &g.redsocks_pid
    );
    if (rc != 0) {
        return -10 + rc;
    }

    usleep(300000);

    if (apply_ipfw_rules(g.server_ip, redir_port, socks_port) != 0) {
        clear_ipfw_rules();
        stop_pid(&g.redsocks_pid);
        return -20;
    }

    g.mode = MODE_IPFW;
    g.connected = 1;
    g.socks_port = socks_port;
    g.redir_port = redir_port;
    return 0;
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

    const char *pf_server_ips = (g.server_ips[0] != '\0') ? g.server_ips : g.server_ip;
    int pf_rc = apply_pf_rules(pf_server_ips, redir_port);
    if (pf_rc != 0) {
        clear_pf_rules();
        stop_pid(&g.redsocks_pid);
        return -40 + pf_rc;
    }

    g.mode = MODE_PF;
    g.connected = 1;
    g.socks_port = socks_port;
    g.redir_port = redir_port;
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
        snprintf(msg, msg_cap, "ERR invalid vless URI (cannot parse host)");
        return -1;
    }

    if (resolve_host_ipv4_all(host, g.server_ip, sizeof(g.server_ip), g.server_ips, sizeof(g.server_ips)) != 0) {
        snprintf(msg, msg_cap, "ERR failed to resolve server host");
        return -1;
    }

    log_msg("resolved server host %s -> %s", host, g.server_ips);

    if (spawn_v2ray(uri, port, &g.v2_pid) != 0) {
        snprintf(msg, msg_cap, "ERR failed to start vless-core core binary");
        disconnect_all();
        return -1;
    }

    usleep(500000);

    int tun_rc = try_connect_tun(port);
    if (tun_rc == 0) {
        update_vpn_icon_state(1);
        snprintf(msg, msg_cap, "OK connected mode=%s socks=%d gw=%s", mode_name(g.mode), g.socks_port, g.gateway);
        return 0;
    }

    int ipfw_rc = try_connect_ipfw(port);
    if (ipfw_rc == 0) {
        update_vpn_icon_state(1);
        snprintf(msg, msg_cap, "OK connected mode=%s socks=%d redir=%d", mode_name(g.mode), g.socks_port, g.redir_port);
        return 0;
    }

    int pf_rc = try_connect_pf(port);
    if (pf_rc == 0) {
        update_vpn_icon_state(1);
        snprintf(msg, msg_cap, "OK connected mode=%s socks=%d redir=%d", mode_name(g.mode), g.socks_port, g.redir_port);
        return 0;
    }

    disconnect_all();
    snprintf(msg, msg_cap, "ERR no usable full-device backend: tun_rc=%d ipfw_rc=%d pf_rc=%d (see /var/log/vpnctld.log)", tun_rc, ipfw_rc, pf_rc);
    return -1;
}

static void handle_client(int cfd) {
    char buf[4096];
    ssize_t n = read(cfd, buf, sizeof(buf) - 1);
    if (n <= 0) {
        return;
    }
    buf[n] = '\0';

    char reply[512];
    memset(reply, 0, sizeof(reply));

    if (strncmp(buf, "STATUS", 6) == 0) {
        if (g.connected) {
            snprintf(reply, sizeof(reply), "OK connected mode=%s socks=%d redir=%d\\n", mode_name(g.mode), g.socks_port, g.redir_port);
        } else {
            snprintf(reply, sizeof(reply), "OK disconnected\\n");
        }
    } else if (strncmp(buf, "DISCONNECT", 10) == 0) {
        disconnect_all();
        snprintf(reply, sizeof(reply), "OK disconnected\\n");
    } else if (strncmp(buf, "CLEAR_LOGS", 10) == 0) {
        clear_logs();
        snprintf(reply, sizeof(reply), "OK logs cleared\\n");
    } else if (strncmp(buf, "CONNECT\t", 8) == 0) {
        char *p = buf + 8;
        char *tab = strchr(p, '\t');
        if (!tab) {
            snprintf(reply, sizeof(reply), "ERR malformed CONNECT\\n");
        } else {
            *tab = '\0';
            int port = atoi(p);

            char *uri = tab + 1;
            char *nl = strchr(uri, '\n');
            if (nl) *nl = '\0';

            if (strncmp(uri, "vless://", 8) != 0) {
                snprintf(reply, sizeof(reply), "ERR uri must start with vless://\\n");
            } else {
                connect_all(uri, port, reply, sizeof(reply));
                strncat(reply, "\\n", sizeof(reply) - strlen(reply) - 1);
            }
        }
    } else {
        snprintf(reply, sizeof(reply), "ERR unknown command\\n");
    }

    write(cfd, reply, strlen(reply));
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    memset(&g, 0, sizeof(g));
    update_vpn_icon_state(0);

    int lfd = socket(AF_INET, SOCK_STREAM, 0);
    if (lfd < 0) {
        return 1;
    }

    int one = 1;
    setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = inet_addr("127.0.0.1");
    sa.sin_port = htons(9093);

    if (bind(lfd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(lfd);
        return 1;
    }

    if (listen(lfd, 16) != 0) {
        close(lfd);
        return 1;
    }

    for (;;) {
        int cfd = accept(lfd, NULL, NULL);
        if (cfd < 0) {
            if (errno == EINTR) continue;
            break;
        }

        handle_client(cfd);
        close(cfd);
    }

    disconnect_all();
    close(lfd);
    return 0;
}
