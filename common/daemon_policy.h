#ifndef VC_DAEMON_POLICY_H
#define VC_DAEMON_POLICY_H
#include <stddef.h>
#include <stdio.h>

typedef enum {
    PF_RULE_ROUTE_TO_LO0 = 0,
    PF_RULE_ROUTE_TO_LO0_NOGW = 1,
    PF_RULE_DIVERT_TO = 2,
    PF_RULE_DIVERT_TO_OLD = 3,
    PF_RULE_RDR_TO = 4,
    PF_RULE_RDR_TO_OLD = 5,
    PF_RULE_LEGACY_RDR = 6,
    PF_RULE_LOOPBACK_ROUTES = 7,
} pf_rule_mode_t;

int starts_with_ci(const char *s, const char *prefix);
int contains_ci(const char *haystack, const char *needle);
int is_supported_config_uri(const char *uri);
static inline int vc_xray_version_valid(const char *value) {
    if (!value) return 0;
    for (unsigned component=0;component<3;component++) {
        unsigned number=0;
        if (*value < '0' || *value > '9') return 0;
        do {
            unsigned digit=(unsigned)(*value-'0');
            if (number > (255U-digit)/10U) return 0;
            number=number*10U+digit; value++;
        } while (*value >= '0' && *value <= '9');
        if (*value != (component == 2 ? '\0' : '.')) return 0;
        if (component != 2) value++;
    }
    return 1;
}
int xray_version_valid(const char *value);
int parse_server_host(const char *uri, char *out, size_t out_cap);
int ip_list_contains(const char *list, const char *ip);
int ip_list_append(char *list, size_t list_cap, const char *ip);
int routing_payload_valid_with_capacity(const char *text, int *bypass_lan_out, size_t capacity);
int ipv4_is_permanent_bypass_for_policy(const char *ip, const char *server_ips, int bypass_lan);
int ifname_is_safe(const char *ifname);
int pf_interface_allowed(const char *ifname);
int text_has_nonspace(const char *text);
int pf_dispatch_rules_only(const char *rules, int nat_rules);
int vc_write_pf_conf(const char *path, int bypass_lan, const char *server_ips, char ifnames[][32], size_t if_count, int redir_port, int dns_port, pf_rule_mode_t mode);
#endif
