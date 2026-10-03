#ifndef VC_DNS_RELAY_H
#define VC_DNS_RELAY_H
#include <stddef.h>
#define DNS_PROXY_UPSTREAM_IP "1.1.1.1"
#define DNS_PROXY_UPSTREAM_PORT 53
#define DNS_PROXY_TIMEOUT_MS 6000
void set_fd_timeout_ms(int fd, int timeout_ms);
int dns_proxy_query_tcp(int socks_port, int *upstream_fd, const unsigned char *query, size_t query_len, unsigned char *reply,
                               size_t reply_cap, size_t *reply_len, int *error_out);
#endif
