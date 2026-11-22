#ifndef VPNCTLD_PROTOCOL_H
#define VPNCTLD_PROTOCOL_H

#define VC_DAEMON_SOCKET_PATH "/var/run/vpnctld.sock"
#define VC_DAEMON_LOCK_PATH "/var/run/vpnctld.lock"
#define VC_APP_EXECUTABLE_PATH "/Applications/vless-core.app/vless-core"
#define VC_BOOTSTRAP_EXECUTABLE_PATH "/usr/bin/vpnctld-bootstrap"
#ifndef VC_CORE_EXECUTABLE_PATH
#define VC_CORE_EXECUTABLE_PATH "/usr/bin/vless-core-darwin-armv7"
#endif
#ifndef VC_CORE_EXECUTABLE_NAME
#define VC_CORE_EXECUTABLE_NAME "vless-core-darwin-armv7"
#endif
#define VC_REDSOCKS_EXECUTABLE_PATH "/usr/bin/redsocks-vless-core"
#define VC_PF_CONFLICT_REPLY "ERR Existing firewall rules conflict with vless-core."
#define VC_PF_QUERY_REPLY "ERR Could not read firewall status or rules."
#define VC_PF_APPLY_REPLY "ERR Could not apply vless-core firewall rules."

#endif
