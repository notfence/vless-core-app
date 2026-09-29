#ifndef VC_SOCKET_PEER_PID_H
#define VC_SOCKET_PEER_PID_H

#include <stddef.h>
#include <sys/types.h>

pid_t vc_socket_peer_pid(int fd, const char *const *expected_paths, size_t path_count);

#endif
