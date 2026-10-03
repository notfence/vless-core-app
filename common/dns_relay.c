#include "dns_relay.h"
#include <arpa/inet.h>
#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

void set_fd_timeout_ms(int fd, int timeout_ms) {
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

int dns_proxy_query_tcp(int socks_port, int *upstream_fd, const unsigned char *query, size_t query_len, unsigned char *reply,
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
