#ifndef VC_PROXY_PROBE_H
#define VC_PROXY_PROBE_H
#import "../common/connection_logic.h"
#include <stddef.h>
#include <stdint.h>

extern NSString *const kVCDefaultProxyPingURL;
NSDictionary *VCProxyPingTargetForURL(NSString *url);
NSString *VCProxyPingURLInDefaults(id defaults);
NSString *VCSelectedProxyPingURL(void);
int write_all(int fd, const void *buf, size_t len);
int connect_loopback_port(uint16_t port, int timeout_ms, VCPingCancellation *cancellation);
int socks5_connect_domain(int fd, const char *host, uint16_t port);
int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms);
int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms, VCPingCancellation *cancellation);
int ProxyGetConnectToURLOnceMs(uint16_t local_port, NSString *url, int timeout_ms, int *latency_ms, VCPingCancellation *cancellation);
#endif
