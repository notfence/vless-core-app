#define _GNU_SOURCE 1
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdint.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "../common/daemon_policy.h"
#include "../common/helper_monitor.h"
#include "../daemon/core_config.h"
#include "../daemon/vpnctld_protocol.h"
#include "check.h"
#include "daemon_pf_state.inc"

static const char *kPFPreviousStateTempPath = "pf-state.tmp";
static const char *kLegacyPFPreviousStateTempPath = "legacy-pf-state.tmp";
static int g_pf_recovery_pending;
static char *const kSafeRootEnvironment[] = {"LANG=C", NULL};
static const char own_nat[] = "nat-anchor \"vlesscore\"\nrdr-anchor \"vlesscore\"\n";
static const char own_filter[] = "anchor \"vlesscore\" all\n";
static const char foreign_nat[] =
    "nat on en0 inet proto tcp from any to ! <test_bypass> -> 127.0.0.1\n"
    "rdr pass on lo0 inet proto tcp from any to ! <test_bypass> -> 127.0.0.1 port 10809\n"
    "rdr pass on lo0 inet proto udp from any to any port = 53 -> 127.0.0.1 port 10853\n";
static const char foreign_filter[] =
    "pass out quick on en0 route-to (lo0 127.0.0.1) inet proto tcp from any to ! <test_bypass> flags S/SA keep state\n"
    "block return out quick on en0 inet6 all\n";

enum { ROOT_INSTALL = 1, ENGINE_ENABLE, ANCHOR_LOAD, ANCHOR_CLEAR, TABLES_CLEAR, STATES_FLUSH, ENGINE_DISABLE, ROOT_CLEAR };
static struct {
    const char *nat, *filter;
    int enabled, missing, query_error, change_at_spawn, change_at_journal, change_at_tables;
    int journal, saved_enabled, saved_dispatch, journal_error;
    int legacy, fail_command, prepare, spawned, stopped, log_clears, resolver_restarts;
    int anchor, command_count, command[32];
    char event[128];
} m;

static void log_warning(const char *fmt, ...) { (void)fmt; }
static void log_error(const char *fmt, ...) { (void)fmt; }
static void log_msg(const char *fmt, ...) { (void)fmt; }
static void log_argv_command(const char *name, char *const argv[]) { (void)name; (void)argv; }
static void core_log_event(const char *level, const char *fmt, ...) { (void)level; (void)fmt; }
static void diagnostic_event(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(m.event, sizeof(m.event), fmt, args);
    va_end(args);
}

static int wait_spawned_quiet(pid_t pid) {
    int status;
    pid_t result;
    do { result = waitpid(pid, &status, 0); } while (result < 0 && errno == EINTR);
    return result == pid && WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}
static int wait_spawned(pid_t pid, const char *name) { (void)name; return wait_spawned_quiet(pid); }
#include "daemon_pf_capture.inc"

static int mock_capture(char *const argv[], char *out, size_t capacity, int verbose, int complete) {
    (void)verbose;
    if (!complete || m.query_error) return -1;
    const char *value = !strcmp(argv[1], "-sn") ? m.nat : !strcmp(argv[1], "-sr") ? m.filter :
        m.enabled ? "Status: Enabled" : "Status: Disabled";
    return snprintf(out, capacity, "%s", value) < (int)capacity ? 0 : -1;
}

static void foreign_rules(void) { m.nat = foreign_nat; m.filter = foreign_filter; }
static int run_argv(char *const argv[]) {
    int command = 0;
    if (!strcmp(argv[2], "-a")) {
        if (strcmp(argv[3], "vlesscore")) abort();
        command = !strcmp(argv[4], "-F") ? TABLES_CLEAR : !strcmp(argv[5], "/dev/null") ? ANCHOR_CLEAR : ANCHOR_LOAD;
    } else if (!strcmp(argv[2], "-f")) {
        command = !strcmp(argv[3], "/dev/null") ? ROOT_CLEAR : ROOT_INSTALL;
    } else if (!strcmp(argv[2], "-F")) {
        if (strcmp(argv[3], "states")) abort();
        command = STATES_FLUSH;
    } else if (!strcmp(argv[2], "-d")) {
        command = ENGINE_DISABLE;
    } else if (!strcmp(argv[2], "-e") || !strcmp(argv[2], "-E")) {
        command = ENGINE_ENABLE;
    }
    if (!command || m.command_count == 32) abort();
    m.command[m.command_count++] = command;
    if (command == m.fail_command) return -1;
    switch (command) {
        case ROOT_INSTALL: m.nat = own_nat; m.filter = own_filter; break;
        case ROOT_CLEAR: m.nat = m.filter = ""; break;
        case ENGINE_ENABLE: m.enabled = 1; break;
        case ENGINE_DISABLE: m.enabled = 0; break;
        case ANCHOR_LOAD: m.anchor = 1; break;
        case ANCHOR_CLEAR: m.anchor = 0; break;
        case TABLES_CLEAR: if (m.change_at_tables) foreign_rules(); break;
    }
    return 0;
}

static const char *find_pfctl_bin(void) { return m.missing ? NULL : "/sbin/pfctl"; }
static void ensure_pf_os_file(void) {}
static int ensure_state_directory(void) { return 0; }
static int write_pf_previous_state(int enabled, int dispatch) {
    if (m.change_at_journal) foreign_rules();
    m.journal = 1;
    m.saved_enabled = enabled;
    m.saved_dispatch = dispatch;
    return m.journal_error ? -1 : 0;
}
static int read_pf_previous_state(int *enabled, int *dispatch) {
    *enabled = m.saved_enabled;
    *dispatch = m.saved_dispatch;
    return m.journal ? 0 : 1;
}
static int remove_pf_previous_state(void) { m.journal = 0; return 0; }
static size_t collect_pf_interfaces(char ifnames[][32], size_t cap) { if (!cap) return 0; strcpy(ifnames[0], "en0"); return 1; }
static int interface_list_has_prefix(char ifnames[][32], size_t n, const char *prefix) {
    return n && !strncmp(ifnames[0], prefix, strlen(prefix));
}
static int write_pf_conf(const char *ips, char ifnames[][32], size_t count, int redir, int dns, pf_rule_mode_t mode) {
    (void)ips; (void)ifnames; (void)count; (void)redir; (void)dns; (void)mode; return 0;
}
static const char *pf_rule_mode_name(pf_rule_mode_t mode) { (void)mode; return "test"; }
static const char *mode_name(vpn_mode_t mode) { return mode == MODE_PF ? "pf" : "none"; }
static int vc_legacy_loopback_required(void) { return m.legacy; }
static int vc_legacy_loopback_start(const char *ips, int lan) { (void)ips; (void)lan; return 0; }
static int vc_legacy_dns_start(void) { return 0; }
static int vc_legacy_dns_stop(void) { return 0; }
static int vc_legacy_loopback_stop(void) { return 0; }
static int vc_system_proxy_enable(int port) { (void)port; return 0; }
static int vc_system_proxy_disable(void) { return 0; }
static void restart_system_dns_resolver(void) { m.resolver_restarts++; }
static void update_vpn_icon_state(int enabled) { (void)enabled; }
static pid_t springboard_pid(pid_t pid) { return pid; }
static long long now_ms(void) { return 0; }
static void clear_logs(void) { m.log_clears++; }
static void stop_pid(pid_t *pid) { if (*pid) m.stopped++; *pid = 0; }
static void finish_log_relay(pid_t *pid) { stop_pid(pid); }
static int child_process_running(pid_t *pid, const char *name) { (void)name; return *pid > 0; }
static int spawn_core(const char *uri, const char *ips, const char *version, int port, pid_t *pid) {
    (void)uri; (void)ips; (void)version; (void)port;
    *pid = ++m.spawned;
    if (m.change_at_spawn) foreign_rules();
    return 0;
}
static int spawn_redsocks(int port, int *redir, pid_t *pid, pid_t *log_relay) {
    (void)port; *redir = 12081; *pid = ++m.spawned; *log_relay = ++m.spawned; return 0;
}
static int spawn_dns_proxy(int port, int *dns, pid_t *pid) {
    (void)port; *dns = 12531; *pid = ++m.spawned; return 0;
}
static int pick_port(int requested) { return requested ? requested : 1080; }
static uint64_t core_prepare_now(void *context) { (void)context; return 0; }
static int inspect_connection(void *context, const char *uri, uint64_t until, char *out, size_t size) {
    (void)context; (void)uri; (void)until; (void)out; (void)size; return 0;
}
static int resolve_connection(void *context, const char *host, uint64_t until, char *out, size_t size) {
    return inspect_connection(context, host, until, out, size);
}
int vc_core_prepare(const char *uri, const VCCorePrepareOperations *ops, VCCoreAddresses *addresses, char *out, size_t size) {
    (void)uri; (void)ops; (void)out; (void)size;
    m.prepare++;
    memset(addresses, 0, sizeof(*addresses));
    strcpy(addresses->primary, "192.0.2.1");
    return 0;
}
static int mock_unlink(const char *path) { (void)path; return 0; }
static FILE *mock_fopen(const char *path, const char *mode) { (void)path; (void)mode; return tmpfile(); }
static int mock_usleep(useconds_t us) { (void)us; return 0; }
#define run_argv_capture_impl mock_capture
#define unlink mock_unlink
#define fopen mock_fopen
#define usleep mock_usleep
#include "daemon_pf_calls.inc"
#undef usleep
#undef fopen
#undef unlink
#undef run_argv_capture_impl

static void reset(void) {
    memset(&g, 0, sizeof(g));
    memset(&m, 0, sizeof(m));
    g_pf_recovery_pending = 0;
    m.nat = m.filter = "";
}
static int connect_fixture(int protect, char msg[256]) {
    return connect_all("socks5://192.0.2.1:1080", NULL, 0, protect, msg, 256);
}
static int commands(const int *expected, size_t n) {
    return m.command_count == (int)n && !memcmp(m.command, expected, n * sizeof(*expected));
}
#define COMMANDS(...) commands((int[]){__VA_ARGS__}, sizeof((int[]){__VA_ARGS__}) / sizeof(int))

int main(void) {
    char out[8];
    char *fits[] = {"/usr/bin/printf", "%s", "1234567", NULL};
    char *over[] = {"/usr/bin/printf", "%s", "12345678", NULL};
    char *nul[] = {"/usr/bin/printf", "abc\\0def", NULL};
    CHECK("pf/read-complete-output", run_argv_capture_impl(fits, out, sizeof(out), 0, 1) == 0 && !strcmp(out, "1234567"));
    CHECK("pf/read-truncated-output-rejected", run_argv_capture_impl(over, out, sizeof(out), 0, 1) != 0);
    CHECK("pf/read-nul-output-rejected", run_argv_capture_impl(nul, out, sizeof(out), 0, 1) != 0);

    char msg[256];
    for (int enabled = 0; enabled <= 1; enabled++) {
        reset(); foreign_rules(); m.enabled = enabled;
        CHECK("pf/early-conflict", connect_fixture(enabled, msg) == -1 && !strcmp(msg, VC_PF_CONFLICT_REPLY));
        CHECK("pf/early-conflict-read-only", !m.prepare && !m.spawned && !m.command_count && !m.journal && m.enabled == enabled);
        CHECK("pf/early-conflict-safe-event", !strcmp(m.event, "PF rules conflict") && !g.protect_logs);
        CHECK("pf/conflict-reported-while-disconnected", !strcmp(pf_routing_state_name(enabled, PF_ROOT_CONFLICT), "conflict"));
    }

    reset(); m.nat = "nat-anchor \"vlesscore\"\n";
    CHECK("pf/partial-anchors-rejected-before-prepare", connect_fixture(0, msg) == -1 &&
          !strcmp(msg, VC_PF_CONFLICT_REPLY) && !m.prepare && !m.command_count);

    for (int missing = 0; missing <= 1; missing++) {
        reset(); m.missing = missing; m.query_error = !missing;
        CHECK("pf/query-error-not-conflict", connect_fixture(0, msg) == -1 && !strcmp(msg, VC_PF_QUERY_REPLY) &&
              !m.command_count && !m.prepare);
    }

    reset(); m.change_at_spawn = 1;
    CHECK("pf/conflict-during-preparation", connect_fixture(1, msg) == -1 && !strcmp(msg, VC_PF_CONFLICT_REPLY) &&
          m.prepare == 1 && m.spawned == 4 && m.stopped == 4 && !m.command_count && !m.journal && !g.protect_logs);
    reset(); m.change_at_journal = 1;
    CHECK("pf/recheck-before-root-reload", connect_fixture(0, msg) == -1 && !strcmp(msg, VC_PF_CONFLICT_REPLY) &&
          !m.command_count && !m.journal && m.nat == foreign_nat);

    reset(); m.journal_error = 1;
    CHECK("pf/journal-error-has-no-firewall-rollback", connect_fixture(0, msg) == -1 && !strcmp(msg, VC_PF_APPLY_REPLY) &&
          !m.command_count && !m.journal && m.spawned == m.stopped);
    reset(); m.fail_command = ROOT_INSTALL;
    CHECK("pf/failed-dispatch-not-a-conflict", connect_fixture(0, msg) == -1 && !strcmp(msg, VC_PF_APPLY_REPLY) &&
          COMMANDS(ROOT_INSTALL) && !m.journal && m.spawned == m.stopped);
    reset(); m.fail_command = ANCHOR_LOAD; m.legacy = 1;
    CHECK("pf/failed-anchor-load-rolls-back-own-setup", connect_fixture(0, msg) == -1 && !strcmp(msg, VC_PF_APPLY_REPLY) &&
          COMMANDS(ROOT_INSTALL, ENGINE_ENABLE, ANCHOR_LOAD, ANCHOR_CLEAR, TABLES_CLEAR, ENGINE_DISABLE, ROOT_CLEAR) &&
          !m.enabled && !m.journal && m.spawned == m.stopped);

    reset();
    CHECK("pf/empty-root-connect", connect_fixture(0, msg) == 0 && g.connected && m.enabled && m.anchor &&
          COMMANDS(ROOT_INSTALL, ENGINE_ENABLE, ANCHOR_LOAD, STATES_FLUSH));
    CHECK("pf/normal-exclusive-disconnect", disconnect_all() == 0 && !g.connected && !m.enabled && !m.anchor &&
          COMMANDS(ROOT_INSTALL, ENGINE_ENABLE, ANCHOR_LOAD, STATES_FLUSH, ANCHOR_CLEAR, TABLES_CLEAR,
                   STATES_FLUSH, ENGINE_DISABLE, ROOT_CLEAR));

    reset(); m.enabled = 1;
    m.nat = own_nat; m.filter = "anchor \"vlesscore\"\npass in all\n";
    CHECK("pf/shared-dispatch-still-connects", connect_fixture(0, msg) == 0 && m.anchor && m.enabled && g.connected &&
          COMMANDS(ANCHOR_LOAD, STATES_FLUSH));
    CHECK("pf/shared-disconnect-only-own-anchor", disconnect_all() == 0 && !m.anchor && m.enabled &&
          COMMANDS(ANCHOR_LOAD, STATES_FLUSH, ANCHOR_CLEAR, TABLES_CLEAR));

    reset();
    CHECK("pf/setup-before-foreign-takeover", connect_fixture(0, msg) == 0);
    m.change_at_tables = 1;
    CHECK("pf/takeover-during-disconnect-preserves-foreign-root", disconnect_all() == 0 && m.enabled && m.nat == foreign_nat &&
          COMMANDS(ROOT_INSTALL, ENGINE_ENABLE, ANCHOR_LOAD, STATES_FLUSH, ANCHOR_CLEAR, TABLES_CLEAR));

    reset(); foreign_rules(); m.enabled = 1; m.journal = 1; m.saved_dispatch = 1;
    CHECK("pf/stale-journal-does-not-authorize-global-cleanup", recover_stale_pf_state() == 0 &&
          !m.journal && !m.command_count && m.enabled && m.nat == foreign_nat && !m.resolver_restarts);
    reset(); m.nat = own_nat; m.filter = own_filter;
    m.enabled = 1; m.journal = 1; m.saved_dispatch = -1; m.legacy = 1;
    m.query_error = 1;
    CHECK("pf/unreadable-stale-state-is-preserved", recover_stale_pf_state() == 1 && m.journal && !m.command_count);
    g_pf_recovery_pending = 1; m.query_error = 0;
    CHECK("pf/retry-legacy-recovery-before-connect", connect_fixture(0, msg) == 0 && m.resolver_restarts == 1 &&
          COMMANDS(ENGINE_DISABLE, ANCHOR_CLEAR, STATES_FLUSH, TABLES_CLEAR, ROOT_CLEAR,
                   ROOT_INSTALL, ENGINE_ENABLE, ANCHOR_LOAD, STATES_FLUSH));

    reset();
    CHECK("pf/connect-before-cleanup-failure", connect_fixture(0, msg) == 0);
    m.fail_command = ANCHOR_CLEAR;
    CHECK("pf/failed-rollback-retains-helpers-and-journal", disconnect_all() != 0 &&
          m.journal && !m.stopped && g.pf_cleanup_pending);
    m.fail_command = 0;
    CHECK("pf/cleanup-retry-completes", disconnect_all() == 0 && !m.journal && m.spawned == m.stopped);
    FINISH("daemon PF conflict and rollback");
    return 0;
}
