#ifndef VLESS_CORE_SYSTEM_PROXY_H
#define VLESS_CORE_SYSTEM_PROXY_H

int vc_system_proxy_enable(int socks_port);
int vc_system_proxy_disable(void);
int vc_system_proxy_refresh(int socks_port);
int vc_system_proxy_restore_stale(void);
int vc_system_proxy_status(void);

#endif
