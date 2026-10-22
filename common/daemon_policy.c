#define _DEFAULT_SOURCE 1
#include "daemon_policy.h"
#include <arpa/inet.h>
#include <ctype.h>
#include <stdint.h>
#include <string.h>

int starts_with_ci(const char *s, const char *prefix) {
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

int contains_ci(const char *haystack, const char *needle) {
    if (!haystack || !needle) return 0;
    if (!*needle) return 1;

    for (const char *p = haystack; *p; p++) {
        if (starts_with_ci(p, needle)) return 1;
    }
    return 0;
}

int is_supported_config_uri(const char *uri) {
    return starts_with_ci(uri, "vless://") || starts_with_ci(uri, "socks5://") ||
           starts_with_ci(uri, "trojan://") || starts_with_ci(uri, "vmess://") || starts_with_ci(uri, "ss://");
}

int xray_version_valid(const char *value) {
    unsigned int x = 0, y = 0, z = 0;
    char trailing = '\0';
    return value &&
           sscanf(value, "%u.%u.%u%c", &x, &y, &z, &trailing) == 3 &&
           x <= 255 && y <= 255 && z <= 255;
}

int parse_server_host(const char *uri, char *out, size_t out_cap) {
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

int ip_list_contains(const char *list, const char *ip) {
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

int ip_list_append(char *list, size_t list_cap, const char *ip) {
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

int routing_payload_valid_with_capacity(const char *text, int *bypass_lan_out, size_t capacity) {
    if (!text || !*text || strlen(text) >= capacity) return 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (!(isalnum(*p) || *p == ';' || *p == ',' || *p == '.' ||
              *p == ':' || *p == '/' || *p == '-' || *p == '_')) {
            return 0;
        }
    }

    const char *first = strchr(text, ';');
    const char *second = first ? strchr(first + 1, ';') : NULL;
    const char *third = second ? strchr(second + 1, ';') : NULL;
    if (!first || !second || first != text + 1 ||
        (text[0] != '0' && text[0] != '1') ||
        second == first + 1 || second[1] == '\0') {
        return 0;
    }
    size_t action_len = (size_t)(second - first - 1);
    if (!((action_len == 5 && strncmp(first + 1, "proxy", 5) == 0) ||
          (action_len == 6 && strncmp(first + 1, "direct", 6) == 0) ||
          (action_len == 5 && strncmp(first + 1, "block", 5) == 0))) {
        return 0;
    }
    size_t lan_len = third ? (size_t)(third - second - 1) : strlen(second + 1);
    if (lan_len != 1 || (second[1] != '0' && second[1] != '1')) {
        return 0;
    }
    if (bypass_lan_out) *bypass_lan_out = second[1] == '1';
    return 1;
}

int ipv4_is_permanent_bypass_for_policy(const char *ip, const char *server_ips, int bypass_lan) {
    struct in_addr address;
    if (inet_pton(AF_INET, ip, &address) != 1) return 0;
    uint32_t value = ntohl(address.s_addr);

    if ((value >> 24) == 127 ||
        (value & 0xf0000000U) == 0xe0000000U ||
        value == 0xffffffffU ||
        ip_list_contains(server_ips, ip)) {
        return 1;
    }
    if (!bypass_lan) return 0;
    return (value & 0xff000000U) == 0x0a000000U ||
           (value & 0xffc00000U) == 0x64400000U ||
           (value & 0xffff0000U) == 0xa9fe0000U ||
           (value & 0xfff00000U) == 0xac100000U ||
           (value & 0xffff0000U) == 0xc0a80000U;
}

int ifname_is_safe(const char *ifname) {
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

int pf_interface_allowed(const char *ifname) {
    if (!ifname) return 0;
    if (strncmp(ifname, "en", 2) == 0) return 1;
    if (strncmp(ifname, "pdp_ip", 6) == 0) return 1;
    return 0;
}

int text_has_nonspace(const char *text) {
    while (text && *text) {
        if (!isspace((unsigned char)*text)) return 1;
        text++;
    }
    return 0;
}

static int rule_line_equals(const char *start, size_t length, const char *expected) {
    while (length > 0 && isspace((unsigned char)*start)) {
        start++;
        length--;
    }
    while (length > 0 && isspace((unsigned char)start[length - 1])) length--;
    return strlen(expected) == length && memcmp(start, expected, length) == 0;
}

static int rule_line_has_nonspace(const char *start, size_t length) {
    for (size_t index = 0; index < length; index++) {
        if (!isspace((unsigned char)start[index])) return 1;
    }
    return 0;
}

int pf_dispatch_rules_only(const char *rules, int nat_rules) {
    int nat_count = 0;
    int rdr_count = 0;
    int filter_count = 0;
    const char *line = rules;
    while (line && *line) {
        const char *newline = strchr(line, '\n');
        size_t length = newline ? (size_t)(newline - line) : strlen(line);
        if (length > 0) {
            if (nat_rules &&
                (rule_line_equals(line, length, "nat-anchor \"vlesscore\"") ||
                 rule_line_equals(line, length, "nat-anchor \"vlesscore\" all"))) {
                nat_count++;
            } else if (nat_rules &&
                       (rule_line_equals(line, length, "rdr-anchor \"vlesscore\"") ||
                        rule_line_equals(line, length, "rdr-anchor \"vlesscore\" all"))) {
                rdr_count++;
            } else if (!nat_rules &&
                       (rule_line_equals(line, length, "anchor \"vlesscore\"") ||
                        rule_line_equals(line, length, "anchor \"vlesscore\" all"))) {
                filter_count++;
            } else if (rule_line_has_nonspace(line, length)) {
                return 0;
            }
        }
        line = newline ? newline + 1 : NULL;
    }
    return nat_rules ? nat_count == 1 && rdr_count == 1 : filter_count == 1;
}

static int write_pf_bypass_table(FILE *fp, const char *server_ips, int bypass_lan) {
    if (fprintf(fp, "table <vlesscore_bypass> persist { 127.0.0.0/8, ") < 0) {
        return -1;
    }
    if (bypass_lan &&
        fprintf(fp, "10.0.0.0/8, 100.64.0.0/10, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, ") < 0) {
        return -1;
    }
    return fprintf(fp, "224.0.0.0/4, 255.255.255.255/32, %s }\n", server_ips) < 0 ? -1 : 0;
}

int vc_write_pf_conf(const char *path, int bypass_lan, const char *server_ips, char ifnames[][32], size_t if_count, int redir_port, int dns_port, pf_rule_mode_t mode) {
    FILE *fp = fopen(path, "w");
    if (!fp) return -1;

    if (!server_ips || !*server_ips || !ifnames || if_count == 0) {
        fclose(fp);
        return -1;
    }

    if (mode == PF_RULE_LOOPBACK_ROUTES) {
        if (write_pf_bypass_table(fp, server_ips, bypass_lan) != 0 || fprintf(fp,
            "rdr pass on lo0 inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1 port %d\n"
            "rdr pass on lo0 inet proto udp from any to any port 53 -> 127.0.0.1 port %d\n"
            "pass out quick on lo0 inet proto tcp from any to ! <vlesscore_bypass> no state\n"
            "pass out quick on lo0 inet proto udp from any to any port 53 no state\n"
            "block return out quick on lo0 inet proto udp from any to ! <vlesscore_bypass>\n",
            redir_port, dns_port) < 0) { fclose(fp); return -1; }
        for (size_t i = 0; i < if_count; i++) {
            if (fprintf(fp,
                "block return out quick on %s inet proto tcp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet proto udp from any to any port 53\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifnames[i], ifnames[i], ifnames[i], ifnames[i], ifnames[i]) < 0) { fclose(fp); return -1; }
        }
    } else if (mode == PF_RULE_ROUTE_TO_LO0) {
        if (write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "nat on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1\n"
                "nat on %s inet proto udp from any to any port 53 -> 127.0.0.1\n",
                ifname, ifname) < 0) {
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
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else if (mode == PF_RULE_ROUTE_TO_LO0_NOGW) {
        if (write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "nat on %s inet proto tcp from any to ! <vlesscore_bypass> -> 127.0.0.1\n"
                "nat on %s inet proto udp from any to any port 53 -> 127.0.0.1\n",
                ifname, ifname) < 0) {
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
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else if (mode == PF_RULE_DIVERT_TO) {
        if (fprintf(fp, "set skip on lo0\n") < 0 ||
            write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s divert-to 127.0.0.1 port %d inet proto tcp from any to ! <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s divert-to 127.0.0.1 port %d inet proto udp from any to any port 53 keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else if (mode == PF_RULE_DIVERT_TO_OLD) {
        if (fprintf(fp, "set skip on lo0\n") < 0 ||
            write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> divert-to 127.0.0.1 port %d keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 divert-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else if (mode == PF_RULE_RDR_TO) {
        if (fprintf(fp, "set skip on lo0\n") < 0 ||
            write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> flags S/SA keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d flags S/SA keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 rdr-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else if (mode == PF_RULE_RDR_TO_OLD) {
        if (fprintf(fp, "set skip on lo0\n") < 0 ||
            write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
            fclose(fp);
            return -1;
        }

        for (size_t i = 0; i < if_count; i++) {
            const char *ifname = ifnames[i];
            if (fprintf(fp,
                "pass out quick on %s inet proto tcp from any to <vlesscore_bypass> keep state\n"
                "pass out quick on %s inet proto tcp from any to ! <vlesscore_bypass> rdr-to 127.0.0.1 port %d keep state\n"
                "pass out quick on %s inet proto udp from any to any port 53 rdr-to 127.0.0.1 port %d keep state\n"
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, redir_port, ifname, dns_port, ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    } else {
        if (fprintf(fp, "set skip on lo0\n") < 0 ||
            write_pf_bypass_table(fp, server_ips, bypass_lan) != 0) {
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
                "block return out quick on %s inet proto udp from any to ! <vlesscore_bypass>\n"
                "block return out quick on %s inet6 all\n"
                "pass out on %s all keep state\n",
                ifname, ifname, ifname) < 0) {
                fclose(fp);
                return -1;
            }
        }

    }

    fclose(fp);
    return 0;
}
