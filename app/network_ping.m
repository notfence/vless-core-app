#import "app_support.h"
#include <ifaddrs.h>
#include <net/if.h>
#import <SystemConfiguration/CaptiveNetwork.h>

static long long PingMonotonicMs(void) {
    return (long long)([[NSProcessInfo processInfo] systemUptime] * 1000.0);
}

static NSDictionary *NativePingReport(NSString *stage, long long dns, long long tcp, long long carry, long long total) {
    return @{@"v":@1, @"id":@0, @"success":@([stage isEqualToString:@"none"]), @"stage":stage,
             @"dns_ms":@(dns), @"tcp_ms":@(tcp), @"transport_ms":@(-1), @"protocol_ms":@(-1),
             @"carry_ms":@(carry), @"total_ms":@(total)};
}

NSString *VCPingNetworkSignature(void) {
    struct ifaddrs *interfaces = NULL;
    if (getifaddrs(&interfaces) != 0) return nil;
    NSMutableArray *addresses = [NSMutableArray array];
    for (struct ifaddrs *it = interfaces; it; it = it->ifa_next) {
        if (!it->ifa_addr || !it->ifa_name || !(it->ifa_flags & IFF_UP) || !(it->ifa_flags & IFF_RUNNING)) continue;
        if (strncmp(it->ifa_name,"en",2) && strncmp(it->ifa_name,"pdp_ip",6)) continue;
        char address[INET6_ADDRSTRLEN];
        int family = it->ifa_addr->sa_family;
        const void *bytes = family == AF_INET ? (const void *)&((struct sockaddr_in *)it->ifa_addr)->sin_addr
            : family == AF_INET6 ? (const void *)&((struct sockaddr_in6 *)it->ifa_addr)->sin6_addr : NULL;
        if (bytes && inet_ntop(family,bytes,address,sizeof(address)))
            [addresses addObject:[NSString stringWithFormat:@"%s=%s",it->ifa_name,address]];
    }
    freeifaddrs(interfaces);
    CFArrayRef wifiInterfaces = CNCopySupportedInterfaces();
    for (NSString *interface in (NSArray *)wifiInterfaces) {
        CFDictionaryRef info = CNCopyCurrentNetworkInfo((CFStringRef)interface);
        NSString *bssid = info ? [(NSDictionary *)info objectForKey:(NSString *)kCNNetworkInfoKeyBSSID] : nil;
        if ([bssid isKindOfClass:[NSString class]]) [addresses addObject:[NSString stringWithFormat:@"wifi=%@",bssid]];
        if (info) CFRelease(info);
    }
    if (wifiInterfaces) CFRelease(wifiInterfaces);
    [addresses sortUsingSelector:@selector(compare:)];
    struct sockaddr_in route;
    memset(&route,0,sizeof(route));
    route.sin_len = sizeof(route);
    route.sin_family = AF_INET;
    SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault,(struct sockaddr *)&route);
    SCNetworkReachabilityFlags flags = 0;
    if (reachability) {
        SCNetworkReachabilityGetFlags(reachability,&flags);
        CFRelease(reachability);
    }
    return [NSString stringWithFormat:@"%u|%@",(unsigned)(flags & kSCNetworkReachabilityFlagsIsWWAN),[addresses componentsJoinedByString:@"|"]];
}

static NSDictionary *ReadProbeReport(int fd, long long previousID, VCPingCancellation *cancellation) {
    if (fd < 0) return nil;
    for (int attempt = 0; attempt < 20 && ![cancellation isCancelled]; attempt++) {
        struct stat state;
        if (fstat(fd,&state) != 0) break;
        size_t length = state.st_size > 65536 ? 65536 : (size_t)state.st_size;
        char *buffer = calloc(1,length + 1);
        if (!buffer) break;
        ssize_t count = pread(fd,buffer,length,state.st_size - length);
        NSDictionary *report = count > 0 ? VCProbeReportFromLog([NSString stringWithUTF8String:buffer]) : nil;
        free(buffer);
        if ([[report objectForKey:@"id"] longLongValue] > previousID) return report;
        usleep(5000);
    }
    return nil;
}

int ConnectLatencyMs(const char *host, uint16_t port, int timeout_ms, int *latency_ms,
                            VCPingCancellation *cancellation) {
    if (!host || !*host) return -1;
    long long started = PingMonotonicMs();

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        long long elapsed = PingMonotonicMs() - started;
        cancellation.diagnosticReport = NativePingReport(@"dns",elapsed,-1,-1,elapsed);
        return -2;
    }
    long long dns = PingMonotonicMs() - started;

    int rc_out = -3;
    for (struct addrinfo *ai = res; ai && ![cancellation isCancelled]; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;
        if (cancellation && ![cancellation registerSocket:fd]) break;

        int flags = fcntl(fd, F_GETFL, 0);
        if (flags >= 0) {
            (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        }

        struct timeval t0, t1;
        gettimeofday(&t0, NULL);
        int cr = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (cr != 0 && errno != EINPROGRESS) {
            VCClosePingSocket(fd, cancellation);
            continue;
        }

        int sr = VCWaitForPingSocket(fd, YES, timeout_ms, cancellation);
        if (sr > 0) {
            int soerr = 0;
            socklen_t sl = (socklen_t)sizeof(soerr);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) == 0 && soerr == 0) {
                gettimeofday(&t1, NULL);
                long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
                if (ms < 0) ms = 0;
                if (latency_ms) *latency_ms = (int)ms;
                rc_out = 0;
                VCClosePingSocket(fd, cancellation);
                break;
            }
        }

        VCClosePingSocket(fd, cancellation);
    }

    freeaddrinfo(res);
    long long elapsed = PingMonotonicMs() - started;
    cancellation.diagnosticReport = NativePingReport(rc_out == 0 ? @"none" : @"tcp",dns,elapsed - dns,-1,elapsed);
    return rc_out;
}

int ConnectLatencyBestOfNMs(const char *host, uint16_t port, int timeout_ms, int attempts, int *latency_ms,
                                   VCPingCancellation *cancellation) {
    if (attempts <= 0) attempts = 1;

    int best = -1;
    NSDictionary *selectedReport = nil;
    for (int i = 0; i < attempts && ![cancellation isCancelled]; i++) {
        int ms = 0;
        if (ConnectLatencyMs(host, port, timeout_ms, &ms, cancellation) == 0) {
            if (best < 0 || ms < best) { best = ms; selectedReport = cancellation.diagnosticReport; }
        } else if (best < 0) {
            selectedReport = cancellation.diagnosticReport;
        }
    }
    cancellation.diagnosticReport = selectedReport;

    if (best < 0) return -1;
    if (latency_ms) *latency_ms = best;
    return 0;
}

int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *p = (const unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t wr = write(fd, p, left);
        if (wr < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (wr == 0) return -1;
        p += (size_t)wr;
        left -= (size_t)wr;
    }
    return 0;
}

static int read_full(int fd, void *buf, size_t len) {
    unsigned char *p = (unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        ssize_t rd = read(fd, p, left);
        if (rd < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (rd == 0) return -1;
        p += (size_t)rd;
        left -= (size_t)rd;
    }
    return 0;
}

static int pick_free_loopback_port(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons(0);

    if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        return -1;
    }

    socklen_t sl = (socklen_t)sizeof(sa);
    if (getsockname(fd, (struct sockaddr *)&sa, &sl) != 0) {
        close(fd);
        return -1;
    }
    close(fd);
    return (int)ntohs(sa.sin_port);
}

int connect_loopback_port(uint16_t port, int timeout_ms, VCPingCancellation *cancellation) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    if (cancellation && ![cancellation registerSocket:fd]) return -1;
    int no_sigpipe = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(port);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        VCClosePingSocket(fd, cancellation);
        return -1;
    }
    return fd;
}

static int wait_for_loopback_listener(uint16_t port, pid_t pid, int timeout_ms, VCPingCancellation *cancellation) {
    int waited = 0;
    while (waited < timeout_ms && ![cancellation isCancelled]) {
        int ms = 0;
        if (ConnectLatencyMs("127.0.0.1", port, 250, &ms, cancellation) == 0) {
            return 0;
        }
        if (pid > 0) {
            pid_t wr = [cancellation pollChild:pid];
            if (wr == pid) return -2;
        }
        usleep(100 * 1000);
        waited += 100;
    }
    return -1;
}

static void stop_child_process(pid_t pid) {
    if (pid <= 0) return;

    int st = 0;
    pid_t wr = waitpid(pid, &st, WNOHANG);
    if (wr == pid) return;
    if (wr < 0 && errno == ECHILD) return;

    kill(pid, SIGTERM);
    for (int i = 0; i < 20; i++) {
        wr = waitpid(pid, &st, WNOHANG);
        if (wr == pid) return;
        if (wr < 0 && errno == ECHILD) return;
        usleep(50 * 1000);
    }
    kill(pid, SIGKILL);
    wr = waitpid(pid, &st, 0);
    if (wr < 0 && errno == ECHILD) return;
}

static pid_t spawn_temp_core_for_ping(const char *uri, uint16_t port, const char *xray_version, int diagnostics_fd) {
    if (!uri || !*uri) return -1;
    size_t uri_length = strlen(uri);
    if (uri_length > kVCMaximumConfigURIBytes) return -1;
    const char *core = VC_CORE_EXECUTABLE_PATH;
    if (access(core, X_OK) != 0) {
        return -1;
    }

    int uri_pipe[2];
    if (pipe(uri_pipe) != 0) return -1;
    if (write_all(uri_pipe[1], uri, uri_length) != 0) {
        close(uri_pipe[0]);
        close(uri_pipe[1]);
        return -1;
    }
    close(uri_pipe[1]);

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    pid_t pid = fork();
    if (pid < 0) {
        close(uri_pipe[0]);
        return -1;
    }
    if (pid == 0) {
        if (uri_pipe[0] != STDIN_FILENO) {
            if (dup2(uri_pipe[0], STDIN_FILENO) < 0) _exit(126);
            close(uri_pipe[0]);
        }
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) {
            (void)dup2(dn, STDOUT_FILENO);
            (void)dup2(dn, STDERR_FILENO);
            if (dn > STDERR_FILENO) close(dn);
        }
        if (diagnostics_fd >= 0) {
            if (dup2(diagnostics_fd,STDERR_FILENO) < 0) _exit(126);
            if (diagnostics_fd > STDERR_FILENO) close(diagnostics_fd);
        }
        if (xray_version && *xray_version) {
            execl(core, VC_CORE_EXECUTABLE_NAME, "--uri-fd", "0", "--listen-port", port_str,
                  "--xray-version", xray_version, (char *)NULL);
        } else {
            execl(core, VC_CORE_EXECUTABLE_NAME, "--uri-fd", "0", "--listen-port", port_str,
                  (char *)NULL);
        }
        _exit(127);
    }
    close(uri_pipe[0]);
    return pid;
}

static int socks5_negotiate_noauth(int fd) {
    unsigned char hello[3] = {0x05, 0x01, 0x00};
    if (write_all(fd, hello, sizeof(hello)) != 0) return -1;

    unsigned char hello_resp[2];
    if (read_full(fd, hello_resp, sizeof(hello_resp)) != 0) return -1;
    if (hello_resp[0] != 0x05 || hello_resp[1] != 0x00) return -1;
    return 0;
}

static int socks5_read_connect_response(int fd) {
    unsigned char resp[4];
    if (read_full(fd, resp, sizeof(resp)) != 0) return -1;
    if (resp[0] != 0x05 || resp[1] != 0x00) return -1;

    size_t tail = 0;
    if (resp[3] == 0x01) {
        tail = 4 + 2;
    } else if (resp[3] == 0x04) {
        tail = 16 + 2;
    } else if (resp[3] == 0x03) {
        unsigned char domain_len = 0;
        if (read_full(fd, &domain_len, 1) != 0) return -1;
        tail = (size_t)domain_len + 2;
    } else {
        return -1;
    }

    unsigned char bound_address[257];
    if (tail > sizeof(bound_address)) return -1;
    return read_full(fd, bound_address, tail);
}

static int socks5_connect_ipv4(int fd, uint32_t ipv4_be, uint16_t port) {
    if (socks5_negotiate_noauth(fd) != 0) return -1;

    unsigned char req[10];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    req[n++] = 0x01;
    memcpy(&req[n], &ipv4_be, 4);
    n += 4;
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (write_all(fd, req, n) != 0) return -1;

    return socks5_read_connect_response(fd);
}

int socks5_connect_domain(int fd, const char *host, uint16_t port) {
    if (!host || !*host) return -1;
    size_t host_len = strlen(host);
    if (host_len > 255) return -1;
    if (socks5_negotiate_noauth(fd) != 0) return -1;

    unsigned char req[4 + 1 + 255 + 2];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    req[n++] = 0x03;
    req[n++] = (unsigned char)host_len;
    memcpy(&req[n], host, host_len);
    n += host_len;
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (write_all(fd, req, n) != 0) return -1;

    return socks5_read_connect_response(fd);
}

int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    int fd = connect_loopback_port(local_port, timeout_ms, nil);
    if (fd < 0) return -1;

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    uint32_t target = inet_addr("1.1.1.1");
    if (target == INADDR_NONE || socks5_connect_ipv4(fd, target, 80) != 0) {
        close(fd);
        return -2;
    }
    gettimeofday(&t1, NULL);
    close(fd);

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms,
                                 VCPingCancellation *cancellation) {
    int fd = connect_loopback_port(local_port, timeout_ms, cancellation);
    if (fd < 0) {
        return -1;
    }

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);

    if (socks5_connect_domain(fd, kVCProxyPingHost, kVCProxyPingPort) != 0 ||
        write_all(fd, kVCProxyPingRequest, strlen(kVCProxyPingRequest)) != 0) {
        VCClosePingSocket(fd, cancellation);
        return -2;
    }

    char response[512];
    size_t response_len = 0;
    BOOL got_first_byte = NO;
    while (response_len + 1 < sizeof(response) && ![cancellation isCancelled]) {
        ssize_t rd = read(fd, response + response_len, sizeof(response) - response_len - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd <= 0) break;
        if (!got_first_byte) {
            gettimeofday(&t1, NULL);
            got_first_byte = YES;
        }
        response_len += (size_t)rd;
        response[response_len] = '\0';
        if (strstr(response, "\r\n") != NULL) break;
    }
    VCClosePingSocket(fd, cancellation);

    if (!got_first_byte || response_len < 5 || strncmp(response, "HTTP/", 5) != 0) {
        return -3;
    }

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

int ProxyGetViaTempCoreMs(const char *uri, const char *xray_version,
                                 int timeout_ms, int attempts, int *latency_ms,
                                 VCPingCancellation *cancellation) {
    cancellation.diagnosticReport = nil;
    if (!uri || !*uri || [cancellation isCancelled]) return -1;
    if (attempts <= 0) attempts = 1;

    int port = pick_free_loopback_port();
    if (port <= 0 || port > 65535) return -2;

    char capturePath[] = "/tmp/vlesscore-probe-XXXXXX";
    int capture = mkstemp(capturePath);
    if (capture >= 0) {
        if (unlink(capturePath) != 0 || fcntl(capture,F_SETFD,FD_CLOEXEC) != 0) { close(capture); capture = -1; }
    }
    pid_t pid = spawn_temp_core_for_ping(uri, (uint16_t)port, xray_version,capture);
    if (pid <= 0) { if (capture >= 0) close(capture); return -3; }
    [cancellation registerChild:pid];

    int rc = -4;
    if (wait_for_loopback_listener((uint16_t)port, pid, 6000, cancellation) != 0) {
        [cancellation forgetChild:pid];
        stop_child_process(pid);
        if (capture >= 0) close(capture);
        return rc;
    }

    int best = -1;
    long long previousID = 0;
    NSDictionary *selectedReport = nil;
    for (int i = 0; i < attempts && ![cancellation isCancelled]; i++) {
        int ms = 0;
        int result = ProxyGetConnectOnceMs((uint16_t)port, timeout_ms, &ms, cancellation);
        NSDictionary *report = ReadProbeReport(capture,previousID,cancellation);
        if (report) previousID = [[report objectForKey:@"id"] longLongValue];
        if (result == 0) {
            if (best < 0 || ms < best) { best = ms; selectedReport = report; }
        } else if (best < 0) {
            if ([[report objectForKey:@"success"] boolValue]) {
                NSMutableDictionary *failure = [NSMutableDictionary dictionaryWithDictionary:report];
                [failure setObject:@0 forKey:@"success"];
                [failure setObject:@"carry" forKey:@"stage"];
                report = failure;
            }
            selectedReport = report;
        }
    }
    [cancellation forgetChild:pid];
    stop_child_process(pid);
    if (capture >= 0) close(capture);
    cancellation.diagnosticReport = selectedReport;

    if (best < 0) {
        return -5;
    }
    if (latency_ms) *latency_ms = best;
    return 0;
}

static uint16_t ICMPChecksum(const void *bytes, size_t length) {
    const unsigned char *cursor = (const unsigned char *)bytes;
    uint32_t sum = 0;
    while (length >= 2) {
        uint16_t word = 0;
        memcpy(&word, cursor, sizeof(word));
        sum += word;
        cursor += 2;
        length -= 2;
    }
    if (length == 1) {
        uint16_t word = 0;
        memcpy(&word, cursor, 1);
        sum += word;
    }
    while ((sum >> 16) != 0) {
        sum = (sum & 0xFFFFU) + (sum >> 16);
    }
    return (uint16_t)~sum;
}

static int ICMPLatencyOnceMs(const struct sockaddr_in *target,
                             int timeout_ms,
                             uint16_t sequence,
                             int *latency_ms,
                             VCPingCancellation *cancellation) {
    if (!target) return -1;

    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (fd < 0) {
        fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    }
    if (fd < 0) return -2;
    if (cancellation && ![cancellation registerSocket:fd]) return -2;

    unsigned char packet[24];
    memset(packet, 0, sizeof(packet));
    packet[0] = 8;  // ICMP echo request
    uint16_t identifier = htons((uint16_t)(getpid() & 0xFFFF));
    uint16_t network_sequence = htons(sequence);
    memcpy(packet + 4, &identifier, sizeof(identifier));
    memcpy(packet + 6, &network_sequence, sizeof(network_sequence));
    for (size_t i = 8; i < sizeof(packet); i++) {
        packet[i] = (unsigned char)i;
    }
    uint16_t checksum = ICMPChecksum(packet, sizeof(packet));
    memcpy(packet + 2, &checksum, sizeof(checksum));

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);
    ssize_t sent = sendto(fd,
                          packet,
                          sizeof(packet),
                          0,
                          (const struct sockaddr *)target,
                          (socklen_t)sizeof(*target));
    if (sent != (ssize_t)sizeof(packet)) {
        VCClosePingSocket(fd, cancellation);
        return -3;
    }

    int selected = VCWaitForPingSocket(fd, NO, timeout_ms, cancellation);
    if (selected <= 0) {
        VCClosePingSocket(fd, cancellation);
        return -4;
    }

    unsigned char reply[512];
    struct sockaddr_in source;
    socklen_t source_len = (socklen_t)sizeof(source);
    ssize_t received = recvfrom(fd,
                                reply,
                                sizeof(reply),
                                0,
                                (struct sockaddr *)&source,
                                &source_len);
    gettimeofday(&t1, NULL);
    VCClosePingSocket(fd, cancellation);
    if (received < 8 || source.sin_addr.s_addr != target->sin_addr.s_addr) return -5;

    size_t offset = 0;
    if ((reply[0] >> 4) == 4) {
        offset = (size_t)(reply[0] & 0x0F) * 4;
    }
    if (offset + 8 > (size_t)received || reply[offset] != 0 || reply[offset + 1] != 0) {
        return -6;
    }
    uint16_t reply_sequence = 0;
    memcpy(&reply_sequence, reply + offset + 6, sizeof(reply_sequence));
    if (ntohs(reply_sequence) != sequence) return -7;

    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}

int ICMPLatencyBestOfNMs(const char *host,
                                int timeout_ms,
                                int attempts,
                                int *latency_ms,
                                VCPingCancellation *cancellation) {
    if (!host || !*host) return -1;
    if (attempts <= 0) attempts = 1;
    long long started = PingMonotonicMs();

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_DGRAM;

    struct addrinfo *result = NULL;
    if (getaddrinfo(host, NULL, &hints, &result) != 0 || !result) {
        long long elapsed = PingMonotonicMs() - started;
        cancellation.diagnosticReport = NativePingReport(@"dns",elapsed,-1,-1,elapsed);
        return -2;
    }
    long long dns = PingMonotonicMs() - started;

    struct sockaddr_in target;
    memset(&target, 0, sizeof(target));
    memcpy(&target, result->ai_addr, sizeof(target));
    freeaddrinfo(result);

    struct timeval sequence_time;
    gettimeofday(&sequence_time, NULL);
    uint16_t first_sequence = (uint16_t)(sequence_time.tv_usec & 0xFFFF);
    int best = -1;
    NSDictionary *selectedReport = nil;
    for (int i = 0; i < attempts && ![cancellation isCancelled]; i++) {
        int ms = 0;
        uint16_t sequence = (uint16_t)(first_sequence + i);
        long long attemptStarted = PingMonotonicMs();
        int result = ICMPLatencyOnceMs(&target, timeout_ms, sequence, &ms, cancellation);
        long long carry = PingMonotonicMs() - attemptStarted;
        NSDictionary *report = NativePingReport(result == 0 ? @"none" : result == -2 ? @"transport" : @"carry",dns,-1,carry,dns + carry);
        if (result == -2) {
            NSMutableDictionary *failure = [NSMutableDictionary dictionaryWithDictionary:report];
            [failure setObject:@(carry) forKey:@"transport_ms"];
            [failure setObject:@(-1) forKey:@"carry_ms"];
            report = failure;
        }
        if (result == 0) {
            if (best < 0 || ms < best) { best = ms; selectedReport = report; }
        } else if (best < 0) {
            selectedReport = report;
        }
    }
    cancellation.diagnosticReport = selectedReport;
    if (best < 0) return -3;
    if (latency_ms) *latency_ms = best;
    return 0;
}
