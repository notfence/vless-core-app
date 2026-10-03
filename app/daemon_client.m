#import "app_support.h"

static BOOL VCApplyStoreFileProtection(NSString *temporaryPath) {
    BOOL ok = YES;
    NSDictionary *protectionAttributes = [NSDictionary dictionaryWithObject:NSFileProtectionComplete
                                                                    forKey:NSFileProtectionKey];
    NSError *attributeError = nil;
    if (![[NSFileManager defaultManager] setAttributes:protectionAttributes
                                          ofItemAtPath:temporaryPath
                                                 error:&attributeError]) {
        BOOL knownPermissionFailure = [[attributeError domain] isEqualToString:NSCocoaErrorDomain] &&
                                      [attributeError code] == NSFileReadNoPermissionError;
        if (!knownPermissionFailure) ok = NO;
    }
    return ok;
}

VCStoragePaths VCMainStoragePaths(void) {
    VCStoragePaths paths = {kSecureStoreDirectoryPath, kSecureStoreFilePath, kDiagnosticEventDatabasePath, SendCommand, VCApplyStoreFileProtection};
    return paths;
}

BOOL VCSaveProtectedConfigurationData(NSArray *configs, NSArray *subscriptions) {
    VCStoragePaths paths = VCMainStoragePaths();
    return VCSaveProtectedConfigurationDataAtPaths(configs, subscriptions, &paths);
}

NSDictionary *VCLoadProtectedConfigurationData(BOOL *fileExistsOut) {
    VCStoragePaths paths = VCMainStoragePaths();
    return VCLoadProtectedConfigurationDataAtPaths(fileExistsOut, &paths);
}

static int TryBootstrapDaemon(void) {
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);

    char *argv[] = {
        "/usr/bin/vpnctld-bootstrap",
        NULL
    };

    pid_t pid = 0;
    int rc = posix_spawn(&pid, "/usr/bin/vpnctld-bootstrap", &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc == 0) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            while (waitpid(pid, NULL, 0) < 0 && errno == EINTR) {
            }
        });
    }
    return (rc == 0) ? 0 : -1;
}

static int ConnectWithTimeout(int fd, const struct sockaddr *sa, socklen_t sa_len, int timeout_ms) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags < 0) {
        return -1;
    }
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) != 0) {
        return -1;
    }

    int rc = connect(fd, sa, sa_len);
    if (rc == 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return 0;
    }
    if (errno != EINPROGRESS) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    fd_set wfds;
    FD_ZERO(&wfds);
    FD_SET(fd, &wfds);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    rc = select(fd + 1, NULL, &wfds, NULL, &tv);
    if (rc <= 0) {
        errno = (rc == 0) ? ETIMEDOUT : errno;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    int soerr = 0;
    socklen_t sl = (socklen_t)sizeof(soerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) != 0) {
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }
    if (soerr != 0) {
        errno = soerr;
        (void)fcntl(fd, F_SETFL, flags);
        return -1;
    }

    (void)fcntl(fd, F_SETFL, flags);
    return 0;
}

static int OpenDaemonSocket(const struct timeval *rw_tv, int connect_timeout_ms, int *fd_out, int *last_errno_out) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        if (last_errno_out) *last_errno_out = errno;
        return -1;
    }

    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, rw_tv, sizeof(*rw_tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, rw_tv, sizeof(*rw_tv));

    struct sockaddr_un sa;
    memset(&sa, 0, sizeof(sa));
    sa.sun_family = AF_UNIX;
    snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", VC_DAEMON_SOCKET_PATH);
    sa.sun_len = (uint8_t)SUN_LEN(&sa);

    if (ConnectWithTimeout(fd, (struct sockaddr *)&sa, (socklen_t)sa.sun_len, connect_timeout_ms) == 0) {
        *fd_out = fd;
        if (last_errno_out) *last_errno_out = 0;
        return 0;
    }

    if (last_errno_out) *last_errno_out = errno;
    close(fd);
    return -1;
}

static int WriteAll(int fd, const void *bytes, size_t length) {
    const unsigned char *data = (const unsigned char *)bytes;
    size_t written = 0;
    while (written < length) {
        ssize_t count = write(fd, data + written, length - written);
        if (count < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (count == 0) {
            errno = EPIPE;
            return -1;
        }
        written += (size_t)count;
    }
    return 0;
}

static ssize_t SendRawCommand(NSData *outData, const struct timeval *rw_tv, int connect_timeout_ms, char *buf, size_t buf_cap, int *last_errno_out, BOOL *connected_out) {
    if (connected_out) *connected_out = NO;
    int fd = -1;
    int last_errno = 0;
    if (OpenDaemonSocket(rw_tv, connect_timeout_ms, &fd, &last_errno) != 0 || fd < 0) {
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }
    if (connected_out) *connected_out = YES;

    if (WriteAll(fd, [outData bytes], [outData length]) != 0) {
        last_errno = errno;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    size_t used = 0;
    for (;;) {
        if (used + 1 >= buf_cap) {
            close(fd);
            if (last_errno_out) *last_errno_out = EMSGSIZE;
            return -1;
        }
        ssize_t rd = read(fd, buf + used, buf_cap - used - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd < 0) {
            last_errno = errno;
            close(fd);
            if (last_errno_out) *last_errno_out = last_errno;
            return -1;
        }
        if (rd == 0) break;
        used += (size_t)rd;
    }
    close(fd);
    if (used == 0) {
        if (last_errno_out) *last_errno_out = ECONNRESET;
        return -1;
    }
    buf[used] = '\0';
    if (last_errno_out) *last_errno_out = 0;
    return (ssize_t)used;
}

NSString *SendCommand(NSString *cmdLine) {
    BOOL isConnectCommand = [cmdLine hasPrefix:@"CONNECT\t"] ||
                            [cmdLine hasPrefix:@"CONNECT_PRIVATE\t"];

    struct timeval cmd_tv;
    cmd_tv.tv_sec = isConnectCommand ? 8 : 2;
    cmd_tv.tv_usec = 0;

    NSData *outData = [cmdLine dataUsingEncoding:NSUTF8StringEncoding];
    int last_errno = 0;
    NSString *last_io_error = nil;

    for (int phase = 0; phase < 2; phase++) {
        if (phase == 1) {
            (void)TryBootstrapDaemon();
        }

        int ready_attempts = (phase == 1) ? 10 : 1;
        for (int attempt = 0; attempt < ready_attempts; attempt++) {
            BOOL connected = NO;
            char buf[65536];
            ssize_t rd = SendRawCommand(outData, &cmd_tv, 500, buf, sizeof(buf), &last_errno, &connected);
            if (rd > 0) {
                NSString *response = [NSString stringWithUTF8String:buf];
                VCRecordDaemonAuthorizationFailure(response);
                return response;
            }

            if (connected) {
                last_io_error = (last_errno == EPIPE || last_errno == ECONNRESET) ?
                    @"no response from daemon" :
                    [NSString stringWithFormat:@"write/read failed: %s", strerror(last_errno)];
                return last_io_error;
            }
            if (attempt + 1 < ready_attempts) usleep(120 * 1000);
        }
    }

    if (last_io_error) {
        return last_io_error;
    }
    if (last_errno == 0) {
        last_errno = ECONNREFUSED;
    }
    return [NSString stringWithFormat:@"daemon offline (%s)", strerror(last_errno)];
}

NSString *ConnectCommandForURI(NSString *uri, BOOL protectLogs) {
    NSString *command = protectLogs ? @"CONNECT_PRIVATE" : @"CONNECT";
    NSString *xrayVersion = VCActiveXrayVersion();
    if (xrayVersion) {
        return [NSString stringWithFormat:@"%@\t0\t%@\t%@\n",
                command, xrayVersion, (uri ? uri : @"")];
    }
    return [NSString stringWithFormat:@"%@\t0\t%@\n", command, (uri ? uri : @"")];
}

NSString *RoutingPolicyText(void) {
    return RoutingPolicyTextInDefaults([NSUserDefaults standardUserDefaults]);
}
