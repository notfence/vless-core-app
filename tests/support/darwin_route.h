#ifndef VC_HOST_DARWIN_ROUTE_H
#define VC_HOST_DARWIN_ROUTE_H
#include <stdint.h>
struct vc_darwin_sockaddr { uint8_t sa_len, sa_family; char sa_data[14]; };
struct vc_darwin_sockaddr_in { uint8_t sin_len, sin_family; uint16_t sin_port; struct in_addr sin_addr; char sin_zero[8]; };
struct vc_darwin_sockaddr_storage { uint8_t ss_len, ss_family; char padding[126]; };
#define sockaddr vc_darwin_sockaddr
#define sockaddr_in vc_darwin_sockaddr_in
#define sockaddr_storage vc_darwin_sockaddr_storage
#define AF_LINK 18
static inline unsigned vc_test_if_nametoindex(const char *name) { return !strcmp(name, "lo0") ? 1 : 7; }
#define if_nametoindex vc_test_if_nametoindex
#endif
