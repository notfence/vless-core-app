#ifndef VC_HOST_DARWIN_PEER_H
#define VC_HOST_DARWIN_PEER_H
#define SOL_LOCAL 0
#define LOCAL_PEERPID 2
#define LOCAL_PEERCRED 1
#define XUCRED_VERSION 0
#define SYS_proc_info 336
struct xucred { unsigned cr_version; uid_t cr_uid; short cr_ngroups; gid_t cr_groups[16]; };
#endif
