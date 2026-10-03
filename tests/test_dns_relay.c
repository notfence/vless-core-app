#define _DEFAULT_SOURCE 1
#include "../common/dns_relay.h"
#include "check.h"
#include <arpa/inet.h>
#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <unistd.h>
typedef struct { int listener, mode, requests, accepted, valid_handshakes; } Fixture;
static int read_full(int fd, void *data, size_t size) { unsigned char *p = data; while (size) { ssize_t n = recv(fd, p, size, 0); if (n <= 0) return -1; p += n; size -= n; } return 0; }
static void *server(void *opaque) {
    Fixture *fixture = opaque;
    unsigned connections = fixture->mode ? 2 : 1;
    for (unsigned connection = 0; connection < connections; connection++) {
        struct pollfd ready = {fixture->listener, POLLIN, 0}; if (poll(&ready, 1, 2000) != 1) return NULL;
        int fd = accept(fixture->listener, NULL, NULL); if (fd < 0) return NULL; fixture->accepted++;
        set_fd_timeout_ms(fd, 2000);
        unsigned char hello[3], request[10];
        if (read_full(fd, hello, 3) || memcmp(hello, "\x05\x01\x00", 3)) { close(fd); return NULL; }
        unsigned char method[] = {5, fixture->mode == 4 ? 0xff : 0}; send(fd, method, 2, 0);
        if (fixture->mode == 4) { close(fd); continue; }
        if (read_full(fd, request, 10) || memcmp(request, "\x05\x01\x00\x01\x01\x01\x01\x01\x00\x35", 10)) { close(fd); return NULL; }
        fixture->valid_handshakes++;
        unsigned char response[10] = {5, 0, 0, 1, 127, 0, 0, 1, 0, 0}; send(fd, response, 10, 0);
        unsigned queries = fixture->mode ? 1 : 2;
        for (unsigned query = 0; query < queries; query++) {
            unsigned char frame[2], payload[256]; if (read_full(fd, frame, 2)) break;
            size_t length = (size_t)frame[0] * 256 + frame[1]; if (length > sizeof(payload) || read_full(fd, payload, length)) break;
            fixture->requests++;
            if (fixture->mode == 1 && connection == 0) break;
            if (fixture->mode == 2) payload[0] ^= 1;
            if (fixture->mode == 3) { frame[0] = 0; frame[1] = 1; }
            send(fd, frame, 2, 0);
            for (size_t i = 0; i < length; i++) if (send(fd, payload + i, 1, 0) != 1) break;
        }
        close(fd);
    }
    return NULL;
}
int main(void) {
    signal(SIGPIPE, SIG_IGN);
    unsigned char query[12] = {0x12, 0x34, 1, 0}, reply[32] = {0}; size_t size = 0; int upstream = -1, error = 0;
    CHECK("dns/invalid-query", dns_proxy_query_tcp(0, &upstream, query, 1, reply, sizeof(reply), &size, &error) == -1 && error == EINVAL);
    CHECK("dns/oversized-query", dns_proxy_query_tcp(0, &upstream, query, 65536, reply, sizeof(reply), &size, &error) == -1 && error == EINVAL);
    for (int mode = 0; mode <= 4; mode++) {
        int listener = socket(AF_INET, SOCK_STREAM, 0); CHECK("dns/local-listener", listener >= 0);
        struct sockaddr_in address = {0}; address.sin_family = AF_INET; address.sin_addr.s_addr = inet_addr("127.0.0.1");
        CHECK("dns/loopback-bind-only", !bind(listener, (struct sockaddr *)&address, sizeof(address)) && !listen(listener, 2));
        socklen_t length = sizeof(address); CHECK("dns/ephemeral-port", !getsockname(listener, (struct sockaddr *)&address, &length));
        Fixture fixture = {listener, mode, 0, 0, 0}; pthread_t worker;
        CHECK("dns/local-server-thread", !pthread_create(&worker, NULL, server, &fixture)); upstream = -1;
        int result = dns_proxy_query_tcp(ntohs(address.sin_port), &upstream, query, sizeof(query), reply, sizeof(reply), &size, &error);
        if (mode <= 1) CHECK("dns/roundtrip-and-fragmented-reply", result == 0 && size == sizeof(query) && !memcmp(reply, query, size));
        else CHECK("dns/invalid-response-fails-closed", result == -1 && size == 0 && upstream == -1);
        if (mode == 0) CHECK("dns/persistent-upstream-reuse", !dns_proxy_query_tcp(ntohs(address.sin_port), &upstream, query, sizeof(query), reply, sizeof(reply), &size, &error));
        if (upstream >= 0) close(upstream);
        CHECK("dns/server-completed", !pthread_join(worker, NULL)); close(listener);
        CHECK("dns/reconnect-only-when-required", fixture.accepted == (mode ? 2 : 1));
        if (mode != 4) CHECK("dns/upstream-destination-contract", fixture.valid_handshakes == fixture.accepted);
        if (mode == 0 || mode == 1) CHECK("dns/two-requests-accounted", fixture.requests == 2);
    }
    FINISH("DNS over SOCKS loopback"); return 0;
}
