#ifndef VC_LEGACY_LOOPBACK_H
#define VC_LEGACY_LOOPBACK_H

int vc_legacy_loopback_required(void);
int vc_legacy_loopback_start(const char *server_ips, int bypass_lan);
int vc_legacy_loopback_stop(void);
int vc_legacy_loopback_active(void);
int vc_legacy_loopback_direct(const char *ip, int add);
int vc_legacy_loopback_healthy(void);

#endif
