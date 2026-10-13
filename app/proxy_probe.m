#import "proxy_probe.h"
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

const char *kVCProxyPingHost = "www.gstatic.com";
const uint16_t kVCProxyPingPort = 80;
const char *kVCProxyPingRequest =
    "GET /generate_204 HTTP/1.1\r\n"
    "Host: www.gstatic.com\r\n"
    "User-Agent: vless-core-app-ping\r\n"
    "Connection: close\r\n\r\n";

int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *p = (const unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t wr = write(fd, p, left);
        if (wr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (wr == 0) return -1;
        p += (size_t)wr;
        left -= (size_t)wr;
    }
    return 0;
}

static int read_full(int fd, void *buf, size_t len) {
    unsigned char *p = (unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t rd = read(fd, p, left);
        if (rd < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (rd == 0) return -1;
        p += (size_t)rd;
        left -= (size_t)rd;
    }
    return 0;
}

int connect_loopback_port(uint16_t port, int timeout_ms, VCPingCancellation *cancellation) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    if (cancellation && ![cancellation registerSocket:fd]) return -1;
#ifdef SO_NOSIGPIPE
    int no_sigpipe = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        VCClosePingSocket(fd, cancellation);
        return -1;
    }
    return fd;
}

static int socks5_negotiate_noauth(int fd) {
    unsigned char hello[3] = {0x05, 0x01, 0x00};
    if (write_all(fd, hello, sizeof(hello)) != 0) return -1;

    unsigned char hello_resp[2];
    if (read_full(fd, hello_resp, sizeof(hello_resp)) != 0) return -1;
    if (hello_resp[0] != 0x05 || hello_resp[1] != 0x00) return -1;
    return 0;
}

static int socks5_read_connect_response(int fd) {
    unsigned char resp[4];
    if (read_full(fd, resp, sizeof(resp)) != 0) return -1;
    if (resp[0] != 0x05 || resp[1] != 0x00) return -1;

    size_t tail = 0;
    if (resp[3] == 0x01) {
        tail = 4 + 2;
    } else if (resp[3] == 0x04) {
        tail = 16 + 2;
    } else if (resp[3] == 0x03) {
        unsigned char domain_len = 0;
        if (read_full(fd, &domain_len, 1) != 0) return -1;
        tail = (size_t)domain_len + 2;
    } else {
        return -1;
    }

    unsigned char bound_address[257];
    if (tail > sizeof(bound_address)) return -1;
    return read_full(fd, bound_address, tail);
}

int socks5_connect_domain(int fd, const char *host, uint16_t port) {
    if (!host || !*host) return -1;
    size_t host_len = strlen(host);
    if (host_len > 255) return -1;
    if (socks5_negotiate_noauth(fd) != 0) return -1;

    unsigned char req[4 + 1 + 255 + 2];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    req[n++] = 0x03;
    req[n++] = (unsigned char)host_len;
    memcpy(&req[n], host, host_len);
    n += host_len;
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (write_all(fd, req, n) != 0) return -1;

    return socks5_read_connect_response(fd);
}

int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    return ProxyGetConnectOnceMs(local_port, timeout_ms, latency_ms, nil);
}

int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms,
                                 VCPingCancellation *cancellation) {
    int fd = connect_loopback_port(local_port, timeout_ms, cancellation);
    if (fd < 0) {
        return -1;
    }

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);

    if (socks5_connect_domain(fd, kVCProxyPingHost, kVCProxyPingPort) != 0 ||
        write_all(fd, kVCProxyPingRequest, strlen(kVCProxyPingRequest)) != 0) {
        VCClosePingSocket(fd, cancellation);
        return -2;
    }

    char response[512];
    size_t response_len = 0;
    BOOL got_first_byte = NO;
    while (response_len + 1 < sizeof(response) && ![cancellation isCancelled]) {
        ssize_t rd = read(fd, response + response_len, sizeof(response) - response_len - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd <= 0) break;
        if (!got_first_byte) {
            gettimeofday(&t1, NULL);
            got_first_byte = YES;
        }
        response_len += (size_t)rd;
        response[response_len] = '\0';
        if (strstr(response, "\r\n") != NULL) break;
    }
    VCClosePingSocket(fd, cancellation);

    char *line_end = got_first_byte ? strstr(response, "\r\n") : NULL;
    if ([cancellation isCancelled] || !line_end || line_end - response < 13 ||
        (memcmp(response, "HTTP/1.1 ", 9) != 0 && memcmp(response, "HTTP/1.0 ", 9) != 0) ||
        response[9] < '1' || response[9] > '5' || response[10] < '0' || response[10] > '9' ||
        response[11] < '0' || response[11] > '9' || response[12] != ' ') {
        return -3;
    }

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}
