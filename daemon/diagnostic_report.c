#include "diagnostic_report.h"
#include <stdio.h>
#include <string.h>

typedef struct {
    char *text;
    size_t used, capacity;
    int clipped;
} ReportText;

static int append(ReportText *out, const char *text, size_t length) {
    if (out->clipped || length >= out->capacity - out->used) {
        out->clipped = 1;
        return 0;
    }
    memcpy(out->text + out->used, text, length);
    out->used += length;
    out->text[out->used] = 0;
    return 1;
}

static const char *finish(ReportText *out) {
    return out->clipped ? "(output limit exceeded)" : out->used ? out->text : "(empty)";
}

static const char *known(const char *value, size_t length, const char *const *options) {
    for (; *options; ++options) if (strlen(*options) == length && !memcmp(value, *options, length)) return *options;
    return NULL;
}

static int decimal(const char *value, size_t length, unsigned maximum) {
    unsigned result = 0;
    if (!length || length > 10) return 0;
    for (size_t i = 0; i < length; ++i) {
        unsigned digit = (unsigned char)value[i] - '0';
        if (digit > 9 || digit > maximum || result > (maximum - digit) / 10) return 0;
        result = result * 10 + digit;
    }
    return 1;
}

int VCDiagnosticEncodeLog(const char *source, size_t length, char *output, size_t capacity) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    size_t groups = length / 3 + (length % 3 != 0);
    if (!capacity || groups > (capacity - 1) / 4) return -1;
    for (size_t i = 0, used = 0; i < length; i += 3) {
        size_t remaining = length - i;
        unsigned a = (unsigned char)source[i];
        unsigned b = remaining > 1 ? (unsigned char)source[i + 1] : 0;
        unsigned c = remaining > 2 ? (unsigned char)source[i + 2] : 0;
        output[used++] = alphabet[a >> 2];
        output[used++] = alphabet[((a & 3) << 4) | (b >> 4)];
        output[used++] = remaining > 1 ? alphabet[((b & 15) << 2) | (c >> 6)] : '=';
        output[used++] = remaining > 2 ? alphabet[c & 63] : '=';
    }
    output[groups * 4] = 0;
    return 0;
}

static unsigned pf_name(VCDiagnosticPFNames *names, const char *p, size_t length) {
    uint64_t hash = UINT64_C(14695981039346656037);
    for (size_t i = 0; i < length; ++i) hash = (hash ^ (unsigned char)p[i]) * UINT64_C(1099511628211);
    for (size_t i = 0; i < names->count; ++i) if (names->tokens[i] == hash) return (unsigned)i + 1;
    if (names->count >= sizeof(names->tokens) / sizeof(names->tokens[0])) return 0;
    names->tokens[names->count++] = hash;
    return (unsigned)names->count;
}

static int pf_interface(const char *p, size_t n) {
    static const char *const prefixes[] = {"en", "lo", "pdp_ip", "utun", "ipsec", "bridge", "awdl", "llw", NULL};
    for (size_t i = 0; prefixes[i]; ++i) {
        size_t prefix = strlen(prefixes[i]);
        if (n > prefix && !memcmp(p, prefixes[i], prefix) && decimal(p + prefix, n - prefix, 255)) return 1;
    }
    return 0;
}

const char *VCDiagnosticPFText(VCDiagnosticPFNames *names, const char *source, char *output, size_t capacity) {
    static const char *const words[] = {
        "nat", "rdr", "binat", "anchor", "nat-anchor", "rdr-anchor", "binat-anchor", "pass", "block", "match", "scrub",
        "no", "drop", "return", "return-rst", "return-icmp", "in", "out", "quick", "log", "on", "route-to", "reply-to", "dup-to", "inet", "inet6",
        "proto", "tcp", "udp", "icmp", "icmp6", "esp", "gre", "from", "to", "any", "all", "self", "port", "flags", "S/SA", "SA/SA",
        "keep", "modulate", "synproxy", "state", "if-bound", "floating", "static-port", "round-robin", "random", "bitmask", "source-hash", "sticky-address",
        "label", "tag", "tagged", "user", "group", "received-on", "!", "=", "!=", "<", ">", "<>", "><", "<=", ">=", "->", NULL
    };
    static const char *const services[] = {"domain", "http", "https", "socks", "ssh", NULL};
    static const char *const labels[] = {"vlesscore", "vlesscore/*", NULL};
    if (!capacity) return "(output limit exceeded)";
    ReportText out = {output, 0, capacity, 0};
    *output = 0;
    int port = 0, label = 0;
    for (const char *p = source; *p && !out.clipped;) {
        if (*p == '\n') { append(&out, "\n", 1); ++p; port = label = 0; continue; }
        if (*p == ' ' || *p == '\t') { append(&out, " ", 1); ++p; continue; }
        if (strchr("(){},", *p)) { append(&out, p++, 1); continue; }
        const char *start = p++;
        int quote = *start == '"';
        size_t table_size = *start == '<' ? strcspn(p, " \t\n>=") : 0;
        int table = table_size > 0 && p[table_size] == '>';
        if (quote) {
            while (*p && *p != '\n' && *p != '"') {
                if (*p == '\\' && p[1] && p[1] != '\n') ++p;
                ++p;
            }
            if (*p == '"') ++p;
        } else if (table) {
            p += table_size + 1;
        } else {
            while (*p && !strchr(" \t\n(){},", *p)) ++p;
        }
        size_t n = (size_t)(p - start);
        const char *word = label ? NULL : known(start, n, words);
        if (word) {
            append(&out, word, n);
            if (!strcmp(word, "port")) port = 1;
            else if (!strchr("=<>!", *word)) port = 0;
            label = !strcmp(word, "label") || !strcmp(word, "tag") || !strcmp(word, "tagged") ||
                    strstr(word, "anchor") != NULL;
        } else if (!label && (pf_interface(start, n) || (port && (decimal(start, n, 65535) || known(start, n, services))))) {
            append(&out, start, n);
        } else if (label && n > 2 && start[0] == '"' && p[-1] == '"' && known(start + 1, n - 2, labels)) {
            append(&out, start, n);
            label = 0;
        } else {
            unsigned id = pf_name(names, start, n);
            char name[32];
            if (table) snprintf(name, sizeof(name), "<table#%u>", id);
            else snprintf(name, sizeof(name), "%s#%u", quote || label ? "name" : "endpoint", id);
            append(&out, name, strlen(name));
            label = 0;
        }
    }
    return finish(&out);
}
