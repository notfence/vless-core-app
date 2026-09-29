#define _DARWIN_C_SOURCE 1
#include "legacy_loopback.h"

#if !defined(__LP64__)
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <unistd.h>

#ifndef VC_LOOPBACK_STATE_PATH
#define VC_LOOPBACK_STATE_PATH "/var/db/vless-core/loopback-routes"
#endif
#define ROUTE_LIMIT 320
#define OWN_FLAGS (0x800U | 0x4000U | 0x8000U)

typedef struct {
    uint16_t length;
    uint8_t version, type;
    uint16_t index;
    int32_t flags, addrs, pid, seq, error, use;
    uint32_t inits, metrics[14];
} route_header_t;
_Static_assert(sizeof(route_header_t) == 92, "routing header ABI");
typedef struct {
    uint32_t destination, mask;
    uint16_t index, reserved;
    uint32_t flags;
    struct sockaddr_storage gateway;
    struct sockaddr_in source;
} route_t;
typedef struct {
    uint32_t magic, count;
    route_t entries[ROUTE_LIMIT];
} route_state_t;
static route_state_t state;
static route_t original_default;
static int active, sequence;

int vc_legacy_loopback_required(void) {
    struct utsname name;
    return uname(&name) == 0 && strncmp(name.release, "11.", 3) == 0;
}
int vc_legacy_loopback_active(void) { return active; }

static struct sockaddr_in ipv4(uint32_t address) {
    struct sockaddr_in value;
    memset(&value, 0, sizeof(value));
    value.sin_len = sizeof(value);
    value.sin_family = AF_INET;
    value.sin_addr.s_addr = address;
    return value;
}

static int append_address(unsigned char *message, size_t *length, const void *address) {
    const struct sockaddr *sa = address;
    size_t size = sa->sa_len ? (sa->sa_len + 3U) & ~3U : 4U;
    if (*length + size > 2048 || size > sizeof(struct sockaddr_storage)) { errno = EINVAL; return -1; }
    memcpy(message + *length, address, sa->sa_len);
    *length += size;
    return 0;
}

static int route_message(int type, const route_t *route, int exact, route_t *reply) {
    unsigned char buffer[2048];
    memset(buffer, 0, sizeof(buffer));
    route_header_t *header = (void *)buffer;
    header->version = 5;
    header->type = (uint8_t)type;
    header->pid = getpid();
    header->seq = ++sequence;
    header->index = type == 4 ? 0 : route->index;
    header->flags = type == 4 ? 0 : (int32_t)route->flags;
    header->addrs = 1;
    size_t length = sizeof(*header);
    struct sockaddr_in destination = ipv4(route->destination), mask = ipv4(route->mask);
    if (append_address(buffer, &length, &destination) != 0) return -1;
    if (type != 4) {
        header->addrs |= 2;
        if (append_address(buffer, &length, &route->gateway) != 0) return -1;
    }
    if ((type != 4 || exact) && route->mask != UINT32_MAX) {
        header->addrs |= 4;
        if (append_address(buffer, &length, &mask) != 0) return -1;
    }
    if (type == 4 || route->source.sin_family == AF_INET) {
        struct sockaddr_storage ifp;
        memset(&ifp, 0, sizeof(ifp));
        ifp.ss_len = 8;
        ifp.ss_family = AF_LINK;
        if (type != 4) memcpy((unsigned char *)&ifp + 2, &route->index, sizeof(route->index));
        header->addrs |= 16 | 32;
        if (append_address(buffer, &length, &ifp) != 0 ||
            append_address(buffer, &length, &route->source) != 0) return -1;
    }
    header->length = (uint16_t)length;
    int seq = header->seq;
    int fd = socket(PF_ROUTE, SOCK_RAW, 0);
    if (fd < 0) return -1;
    (void)fcntl(fd, F_SETFD, FD_CLOEXEC);
    if (write(fd, buffer, length) != (ssize_t)length) { int error = errno; close(fd); errno = error; return -1; }
    int result = -1, error = ETIMEDOUT;
    for (unsigned attempt = 0; attempt < 32; attempt++) {
        struct pollfd ready = {fd, POLLIN, 0};
        if (poll(&ready, 1, 500) <= 0) break;
        ssize_t count = read(fd, buffer, sizeof(buffer));
        if (count < (ssize_t)sizeof(*header)) continue;
        if (header->version != 5 || header->pid != getpid() || header->seq != seq) continue;
        error = header->error;
        if (error) break;
        if (header->length > count || header->length < sizeof(*header)) { error = EINVAL; break; }
        if (reply) {
            memset(reply, 0, sizeof(*reply));
            reply->index = header->index;
            reply->flags = (uint32_t)header->flags;
            size_t offset = sizeof(*header);
            for (unsigned bit = 1; bit <= 128; bit <<= 1) {
                if (!(header->addrs & bit)) continue;
                if (offset + 2 > header->length) { error = EINVAL; break; }
                struct sockaddr *sa = (void *)(buffer + offset);
                size_t size = sa->sa_len ? (sa->sa_len + 3U) & ~3U : 4U;
                if (offset + size > header->length || size > sizeof(struct sockaddr_storage)) { error = EINVAL; break; }
                if (bit == 2) memcpy(&reply->gateway, sa, sa->sa_len);
                else if (bit == 4 || ((bit == 1 || bit == 32) && sa->sa_len >= 8)) {
                    struct sockaddr_in address = ipv4(0);
                    memcpy(&address, sa, sa->sa_len < sizeof(address) ? sa->sa_len : sizeof(address));
                    if (bit == 1) reply->destination = address.sin_addr.s_addr;
                    else if (bit == 4) reply->mask = address.sin_addr.s_addr;
                    else reply->source = address;
                }
                offset += size;
            }
            if (header->flags & 4) reply->mask = UINT32_MAX;
        }
        result = error ? -1 : 0;
        break;
    }
    close(fd);
    errno = error;
    return result;
}

static int save_state(void) {
    state.magic = 0x56434c31;
    int fd = open(VC_LOOPBACK_STATE_PATH ".tmp", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return -1;
    size_t size = 8 + state.count * sizeof(route_t);
    int result = write(fd, &state, size) == (ssize_t)size && fsync(fd) == 0 ? 0 : -1;
    if (close(fd) != 0) result = -1;
    if (result == 0) result = rename(VC_LOOPBACK_STATE_PATH ".tmp", VC_LOOPBACK_STATE_PATH);
    if (result == 0) {
        char directory[sizeof(VC_LOOPBACK_STATE_PATH)];
        strcpy(directory, VC_LOOPBACK_STATE_PATH);
        char *slash = strrchr(directory, '/');
        if (!slash || slash == directory) result = -1;
        else {
            *slash = '\0';
            int directory_fd = open(directory, O_RDONLY | O_NOFOLLOW);
            if (directory_fd < 0) result = -1;
            else { result = fsync(directory_fd); close(directory_fd); }
        }
    }
    if (result != 0) (void)unlink(VC_LOOPBACK_STATE_PATH ".tmp");
    return result;
}

static int load_state(void) {
    memset(&state, 0, sizeof(state));
    int fd = open(VC_LOOPBACK_STATE_PATH, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? 0 : -1;
    struct stat info;
    ssize_t size = -1;
    if (fstat(fd, &info) == 0 && S_ISREG(info.st_mode) && info.st_uid == 0 &&
        info.st_nlink == 1 && (info.st_mode & 0777) == 0600 && info.st_size <= sizeof(state)) {
        size = read(fd, &state, sizeof(state));
    }
    close(fd);
    if (size < 8 || state.magic != 0x56434c31 || state.count > ROUTE_LIMIT ||
        size != (ssize_t)(8 + state.count * sizeof(route_t))) { errno = EINVAL; return -1; }
    for (unsigned index = 0; index < state.count; index++) {
        route_t *entry = &state.entries[index];
        if (!entry->index || (entry->flags & OWN_FLAGS) != OWN_FLAGS ||
            entry->gateway.ss_len < 2 || entry->gateway.ss_len > sizeof(entry->gateway) ||
            (entry->gateway.ss_family != AF_INET && entry->gateway.ss_family != AF_LINK)) {
            errno = EINVAL; return -1;
        }
    }
    return 0;
}

static int same_route(const route_t *a, const route_t *b) {
    return a->destination == b->destination && a->mask == b->mask && a->index == b->index &&
        a->gateway.ss_len == b->gateway.ss_len &&
        memcmp(&a->gateway, &b->gateway, a->gateway.ss_len) == 0;
}

static int remove_route(const route_t *route) {
    route_t current;
    if (route_message(4, route, 1, &current) != 0) return errno == ESRCH ? 0 : -1;
    if (!same_route(route, &current) || (current.flags & OWN_FLAGS) != OWN_FLAGS) return 0;
    if (route_message(2, route, 1, NULL) != 0) return errno == ESRCH ? 0 : -1;
    return 0;
}

int vc_legacy_loopback_stop(void) {
    (void)unlink(VC_LOOPBACK_STATE_PATH ".tmp");
    if (load_state() != 0) return -1;
    while (state.count) {
        if (remove_route(&state.entries[state.count - 1]) != 0) return -1;
        state.count--;
        if (save_state() != 0) return -1;
    }
    active = 0;
    return unlink(VC_LOOPBACK_STATE_PATH) == 0 || errno == ENOENT ? 0 : -1;
}

static int add_route(route_t route, int allow_existing) {
    route_t current;
    int lookup = route_message(4, &route, 1, &current);
    if (lookup == 0 && current.destination == route.destination && current.mask == route.mask) {
        if (allow_existing && route.mask == UINT32_MAX && (current.flags & 0x20000U) &&
            !(current.flags & (0x800U | 0x100000U))) {
            if (route_message(2, &current, 1, NULL) != 0) return -1;
        } else {
            if (allow_existing && current.index != if_nametoindex("lo0")) return 0;
            errno = EEXIST;
            return -1;
        }
    }
    if (lookup != 0 && errno != ESRCH) return -1;
    if (state.count == ROUTE_LIMIT) { errno = ENOSPC; return -1; }
    route.flags = 1 | OWN_FLAGS | (route.mask == UINT32_MAX ? 4 : 0) |
        (route.gateway.ss_family == AF_INET ? 2 : 0);
    state.entries[state.count++] = route;
    if (save_state() != 0) { state.count--; return -1; }
    if (route_message(1, &route, 1, NULL) != 0) return -1;
    if (route_message(4, &route, 1, &current) != 0 || !same_route(&route, &current) ||
        (current.flags & OWN_FLAGS) != OWN_FLAGS) { errno = EIO; return -1; }
    return 0;
}

static int vc_legacy_loopback_probe(void) {
    route_t query;
    memset(&query, 0, sizeof(query));
    query.source = ipv4(0);
    route_t answer;
    if (route_message(4, &query, 1, &answer) != 0) return -1;
    if (!answer.index || answer.index == if_nametoindex("lo0") ||
        answer.source.sin_family != AF_INET || !answer.source.sin_addr.s_addr ||
        (answer.gateway.ss_family != AF_INET && answer.gateway.ss_family != AF_LINK)) { errno = ENETUNREACH; return -1; }
    original_default = answer;
    return 0;
}

static int direct_prefix(const char *ip, unsigned prefix) {
    route_t route = original_default;
    if (inet_pton(AF_INET, ip, &route.destination) != 1 || prefix > 32) { errno = EINVAL; return -1; }
    route.mask = htonl(prefix ? UINT32_MAX << (32 - prefix) : 0);
    route.destination &= route.mask;
    return add_route(route, 1);
}

int vc_legacy_loopback_start(const char *server_ips, int bypass_lan) {
    if (active || !server_ips || !*server_ips || strlen(server_ips) >= 512) { errno = EINVAL; return -1; }
    if (vc_legacy_loopback_stop() != 0 || vc_legacy_loopback_probe() != 0) return -1;
    char addresses[512];
    strcpy(addresses, server_ips);
    char *save = NULL;
    for (char *ip = strtok_r(addresses, ", ", &save); ip; ip = strtok_r(NULL, ", ", &save)) {
        if (direct_prefix(ip, 32) != 0) goto fail;
    }
    if (bypass_lan && (direct_prefix("10.0.0.0", 8) != 0 || direct_prefix("100.64.0.0", 10) != 0 ||
        direct_prefix("169.254.0.0", 16) != 0 || direct_prefix("172.16.0.0", 12) != 0 ||
        direct_prefix("192.168.0.0", 16) != 0)) goto fail;
    for (unsigned half = 0; half < 2; half++) {
        route_t route;
        memset(&route, 0, sizeof(route));
        route.destination = htonl(half ? 0x80000000U : 0);
        route.mask = htonl(0x80000000U);
        route.index = (uint16_t)if_nametoindex("lo0");
        struct sockaddr_in gateway = ipv4(htonl(0x7f000001U));
        memcpy(&route.gateway, &gateway, sizeof(gateway));
        route.source = gateway;
        if (add_route(route, 0) != 0) goto fail;
    }
    active = 1;
    return 0;
fail: {
    int error = errno;
    (void)vc_legacy_loopback_stop();
    errno = error;
    return -1;
}
}

int vc_legacy_loopback_direct(const char *ip, int add) {
    if (!active) return 0;
    struct in_addr address;
    if (inet_pton(AF_INET, ip, &address) != 1) { errno = EINVAL; return -1; }
    if (add) return direct_prefix(ip, 32);
    for (unsigned index = 0; index < state.count; index++) {
        route_t *route = &state.entries[index];
        if (route->destination != address.s_addr || route->mask != UINT32_MAX) continue;
        if (remove_route(route) != 0) return -1;
        memmove(route, route + 1, (state.count - index - 1) * sizeof(*route));
        state.count--;
        return save_state();
    }
    return 0;
}

int vc_legacy_loopback_healthy(void) {
    if (!active) return 1;
    route_t query, current;
    memset(&query, 0, sizeof(query));
    query.source = ipv4(0);
    return route_message(4, &query, 1, &current) == 0 && same_route(&original_default, &current) &&
        original_default.source.sin_addr.s_addr == current.source.sin_addr.s_addr;
}
#else
int vc_legacy_loopback_required(void) { return 0; }
int vc_legacy_loopback_active(void) { return 0; }
int vc_legacy_loopback_start(const char *ips, int lan) { (void)ips; (void)lan; return -1; }
int vc_legacy_loopback_stop(void) { return 0; }
int vc_legacy_loopback_direct(const char *ip, int add) { (void)ip; (void)add; return 0; }
int vc_legacy_loopback_healthy(void) { return 1; }
#endif
