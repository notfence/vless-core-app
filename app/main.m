#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <signal.h>
#include <sys/wait.h>

static NSString *const kDefaultsConfigsKey = @"vlesscore.configs";
static NSString *const kDefaultsSubsKey = @"vlesscore.subscriptions";
static NSString *const kDefaultsAutoUpdateSubsKey = @"vlesscore.auto_update_subs";

typedef NS_ENUM(NSInteger, VCAlertTag) {
    VCAlertTagImportManual = 1001,
};

typedef NS_ENUM(NSInteger, VCActionSheetTag) {
    VCActionSheetTagImport = 2001,
    VCActionSheetTagSettings = 2002,
};

typedef NS_ENUM(NSInteger, VCIconType) {
    VCIconTypeAdd = 1,
    VCIconTypeTerminal = 2,
    VCIconTypeRefresh = 3,
    VCIconTypeSettings = 4,
    VCIconTypeChevronRight = 5,
    VCIconTypeChevronDown = 6,
    VCIconTypeWifi = 7,
    VCIconTypeCheck = 8,
    VCIconTypeList = 9,
};

static int TryBootstrapDaemon(void) {
    return system("/usr/bin/vpnctld-bootstrap >/dev/null 2>&1");
}

static NSString *SendCommand(NSString *cmdLine) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return [NSString stringWithFormat:@"socket() failed: %s", strerror(errno)];
    }

    struct timeval tv;
    tv.tv_sec = 5;
    tv.tv_usec = 0;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons(9093);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
        close(fd);
        TryBootstrapDaemon();

        fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) {
            return [NSString stringWithFormat:@"daemon offline (%s)", strerror(errno)];
        }
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

        if (connect(fd, (struct sockaddr *)&sa, sizeof(sa)) != 0) {
            NSString *err = [NSString stringWithFormat:@"daemon offline (%s)", strerror(errno)];
            close(fd);
            return err;
        }
    }

    NSData *outData = [cmdLine dataUsingEncoding:NSUTF8StringEncoding];
    ssize_t wr = write(fd, [outData bytes], [outData length]);
    if (wr < 0) {
        NSString *err = [NSString stringWithFormat:@"write failed: %s", strerror(errno)];
        close(fd);
        return err;
    }

    char buf[2048];
    ssize_t rd = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if (rd <= 0) {
        return @"no response from daemon";
    }
    buf[rd] = '\0';
    return [NSString stringWithUTF8String:buf];
}

static int ConnectLatencyMs(const char *host, uint16_t port, int timeout_ms, int *latency_ms) {
    if (!host || !*host) return -1;

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;

    struct addrinfo *res = NULL;
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        return -2;
    }

    int rc_out = -3;
    for (struct addrinfo *ai = res; ai; ai = ai->ai_next) {
        int fd = socket(ai->ai_family, ai->ai_socktype, ai->ai_protocol);
        if (fd < 0) continue;

        int flags = fcntl(fd, F_GETFL, 0);
        if (flags >= 0) {
            (void)fcntl(fd, F_SETFL, flags | O_NONBLOCK);
        }

        struct timeval t0, t1;
        gettimeofday(&t0, NULL);
        int cr = connect(fd, ai->ai_addr, ai->ai_addrlen);
        if (cr != 0 && errno != EINPROGRESS) {
            close(fd);
            continue;
        }

        fd_set wfds;
        FD_ZERO(&wfds);
        FD_SET(fd, &wfds);
        struct timeval tv;
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        int sr = select(fd + 1, NULL, &wfds, NULL, &tv);
        if (sr > 0 && FD_ISSET(fd, &wfds)) {
            int soerr = 0;
            socklen_t sl = (socklen_t)sizeof(soerr);
            if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl) == 0 && soerr == 0) {
                gettimeofday(&t1, NULL);
                long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
                if (ms < 0) ms = 0;
                if (latency_ms) *latency_ms = (int)ms;
                rc_out = 0;
                close(fd);
                break;
            }
        }

        close(fd);
    }

    freeaddrinfo(res);
    return rc_out;
}

static int ConnectLatencyBestOfNMs(const char *host, uint16_t port, int timeout_ms, int attempts, int *latency_ms) {
    if (attempts <= 0) attempts = 1;

    int best = -1;
    for (int i = 0; i < attempts; i++) {
        int ms = 0;
        if (ConnectLatencyMs(host, port, timeout_ms, &ms) == 0) {
            if (best < 0 || ms < best) best = ms;
        }
    }

    if (best < 0) return -1;
    if (latency_ms) *latency_ms = best;
    return 0;
}

static int write_all(int fd, const void *buf, size_t len) {
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

static int connect_loopback_port(uint16_t port, int timeout_ms) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

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
        close(fd);
        return -1;
    }
    return fd;
}

static int wait_for_loopback_listener(uint16_t port, pid_t pid, int timeout_ms) {
    int waited = 0;
    while (waited < timeout_ms) {
        int ms = 0;
        if (ConnectLatencyMs("127.0.0.1", port, 250, &ms) == 0) {
            return 0;
        }
        if (pid > 0) {
            int st = 0;
            pid_t wr = waitpid(pid, &st, WNOHANG);
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

static pid_t spawn_temp_core_for_ping(const char *uri, uint16_t port) {
    if (!uri || !*uri) return -1;
    const char *core = "/usr/bin/vless-core-darwin-amrv7";
    if (access(core, X_OK) != 0) {
        return -1;
    }

    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%u", (unsigned)port);

    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        int dn = open("/dev/null", O_RDWR);
        if (dn >= 0) {
            (void)dup2(dn, STDOUT_FILENO);
            (void)dup2(dn, STDERR_FILENO);
            if (dn > STDERR_FILENO) close(dn);
        }
        execl(core, "vless-core-darwin-amrv7", "--uri", uri, "--listen-port", port_str, (char *)NULL);
        _exit(127);
    }
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

    unsigned char resp[4];
    if (read_full(fd, resp, sizeof(resp)) != 0) return -1;
    if (resp[0] != 0x05 || resp[1] != 0x00) return -1;

    size_t tail = 0;
    if (resp[3] == 0x01) {
        tail = 4 + 2;
    } else if (resp[3] == 0x04) {
        tail = 16 + 2;
    } else if (resp[3] == 0x03) {
        unsigned char dsz = 0;
        if (read_full(fd, &dsz, 1) != 0) return -1;
        tail = (size_t)dsz + 2;
    } else {
        return -1;
    }
    if (tail > 0) {
        unsigned char tmp[300];
        if (tail > sizeof(tmp)) return -1;
        if (read_full(fd, tmp, tail) != 0) return -1;
    }
    return 0;
}

static int RealPingConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    int fd = connect_loopback_port(local_port, timeout_ms);
    if (fd < 0) {
        return -1;
    }

    struct timeval t0, t1;
    gettimeofday(&t0, NULL);

    uint32_t target = inet_addr("1.1.1.1");
    if (target == INADDR_NONE || socks5_connect_ipv4(fd, target, 80) != 0) {
        close(fd);
        return -2;
    }

    gettimeofday(&t1, NULL);
    long ms = (long)((t1.tv_sec - t0.tv_sec) * 1000L + (t1.tv_usec - t0.tv_usec) / 1000L);
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;

    close(fd);
    return 0;
}

static int RealPingViaTempCoreMs(const char *uri, int timeout_ms, int attempts, int *latency_ms) {
    if (!uri || !*uri) return -1;
    if (attempts <= 0) attempts = 1;

    int port = pick_free_loopback_port();
    if (port <= 0 || port > 65535) return -2;

    pid_t pid = spawn_temp_core_for_ping(uri, (uint16_t)port);
    if (pid <= 0) return -3;

    int rc = -4;
    if (wait_for_loopback_listener((uint16_t)port, pid, 6000) != 0) {
        stop_child_process(pid);
        return rc;
    }

    int best = -1;
    for (int i = 0; i < attempts; i++) {
        int ms = 0;
        if (RealPingConnectOnceMs((uint16_t)port, timeout_ms, &ms) == 0) {
            if (best < 0 || ms < best) best = ms;
        }
    }
    stop_child_process(pid);

    if (best < 0) {
        return -5;
    }
    if (latency_ms) *latency_ms = best;
    return 0;
}

static NSString *RunCommandFirstLine(const char *cmdLine) {
    if (!cmdLine || !*cmdLine) return nil;

    FILE *fp = popen(cmdLine, "r");
    if (!fp) return nil;

    char buf[256];
    char *got = fgets(buf, sizeof(buf), fp);
    pclose(fp);
    if (!got) return nil;

    size_t len = strlen(buf);
    while (len > 0 && (buf[len - 1] == '\n' || buf[len - 1] == '\r' || buf[len - 1] == ' ' || buf[len - 1] == '\t')) {
        buf[len - 1] = '\0';
        len--;
    }
    if (len == 0) return nil;

    return [NSString stringWithUTF8String:buf];
}

static NSString *DetectCoreBinaryVersion(void) {
    NSString *v = RunCommandFirstLine("/usr/bin/vless-core-darwin-amrv7 -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine("vless-core-darwin-amrv7 -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"unknown";
    }
    return v;
}

static NSString *TrimSimpleString(NSString *s) {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *ReadTextFileBestEffort(NSString *path) {
    if (!path || [path length] == 0) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || [data length] == 0) return nil;

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    return txt;
}

static NSData *FetchURLViaVlessCoreCurl(NSString *urlString, NSString **errOut) {
    const char *curl_path = "/usr/bin/vless-core-curl";
    const char *ca_bundle_path = "/usr/share/vless-core/cacert.pem";

    if (!urlString || [urlString length] == 0) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }

    if (access(curl_path, X_OK) != 0) {
        if (errOut) *errOut = @"vless-core-curl not found";
        return nil;
    }

    const char *url_c = [urlString UTF8String];
    if (!url_c || !*url_c) {
        if (errOut) *errOut = @"Invalid subscription URL";
        return nil;
    }

    char out_tmpl[] = "/tmp/vlesscore-sub-out-XXXXXX";
    int out_fd = mkstemp(out_tmpl);
    if (out_fd < 0) {
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(out) failed: %s", strerror(errno)];
        return nil;
    }

    char err_tmpl[] = "/tmp/vlesscore-sub-err-XXXXXX";
    int err_fd = mkstemp(err_tmpl);
    if (err_fd < 0) {
        close(out_fd);
        unlink(out_tmpl);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(err) failed: %s", strerror(errno)];
        return nil;
    }

    pid_t pid = fork();
    if (pid < 0) {
        close(out_fd);
        close(err_fd);
        unlink(out_tmpl);
        unlink(err_tmpl);
        if (errOut) *errOut = [NSString stringWithFormat:@"fork failed: %s", strerror(errno)];
        return nil;
    }

    if (pid == 0) {
        int dn = open("/dev/null", O_RDONLY);
        if (dn >= 0) {
            (void)dup2(dn, STDIN_FILENO);
            if (dn > STDERR_FILENO) close(dn);
        }

        (void)dup2(out_fd, STDOUT_FILENO);
        (void)dup2(err_fd, STDERR_FILENO);
        close(out_fd);
        close(err_fd);

        if (access(ca_bundle_path, R_OK) == 0) {
            execl(curl_path, "vless-core-curl",
                  "--fail",
                  "--location",
                  "--silent",
                  "--show-error",
                  "--connect-timeout", "10",
                  "--max-time", "25",
                  "--proto", "=https,http",
                  "--cacert", ca_bundle_path,
                  url_c,
                  (char *)NULL);
        } else {
            execl(curl_path, "vless-core-curl",
                  "--fail",
                  "--location",
                  "--silent",
                  "--show-error",
                  "--connect-timeout", "10",
                  "--max-time", "25",
                  "--proto", "=https,http",
                  url_c,
                  (char *)NULL);
        }
        _exit(127);
    }

    close(out_fd);
    close(err_fd);

    int status = 0;
    int waited_ms = 0;
    const int timeout_ms = 30000;
    while (1) {
        pid_t wr = waitpid(pid, &status, WNOHANG);
        if (wr == pid) break;
        if (wr < 0) {
            if (errno == EINTR) continue;
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            unlink(out_tmpl);
            unlink(err_tmpl);
            if (errOut) *errOut = [NSString stringWithFormat:@"waitpid failed: %s", strerror(errno)];
            return nil;
        }

        if (waited_ms >= timeout_ms) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            unlink(out_tmpl);
            unlink(err_tmpl);
            if (errOut) *errOut = @"vless-core-curl timed out";
            return nil;
        }

        usleep(100 * 1000);
        waited_ms += 100;
    }

    NSString *out_path = [NSString stringWithUTF8String:out_tmpl];
    NSString *err_path = [NSString stringWithUTF8String:err_tmpl];
    NSData *body = [NSData dataWithContentsOfFile:out_path];
    NSString *curl_err = TrimSimpleString(ReadTextFileBestEffort(err_path));
    if ([curl_err length] > 220) {
        curl_err = [curl_err substringToIndex:220];
    }

    unlink(out_tmpl);
    unlink(err_tmpl);

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (errOut) {
            if ([curl_err length] > 0) {
                *errOut = curl_err;
            } else if (WIFEXITED(status)) {
                *errOut = [NSString stringWithFormat:@"vless-core-curl exited with code %d", WEXITSTATUS(status)];
            } else {
                *errOut = @"vless-core-curl terminated unexpectedly";
            }
        }
        return nil;
    }

    if (!body || [body length] == 0) {
        if (errOut) *errOut = @"Empty subscription response";
        return nil;
    }

    return body;
}

static void ClearLogsViaDaemon(void) {
    NSString *resp = SendCommand(@"CLEAR_LOGS\n");
    (void)resp;
}

static NSString *ReadFileTail(NSString *path, NSUInteger maxBytes) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!fh) {
        return [NSString stringWithFormat:@"(cannot open %@)\n", path];
    }

    unsigned long long sz = [fh seekToEndOfFile];
    if (sz > maxBytes) {
        [fh seekToFileOffset:(sz - maxBytes)];
    } else {
        [fh seekToFileOffset:0];
    }

    NSData *data = [fh readDataToEndOfFile];
    [fh closeFile];

    if (!data || [data length] == 0) {
        return @"(empty)\n";
    }

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) {
        txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
    if (!txt) {
        return @"(unreadable)\n";
    }
    return txt;
}

static NSString *BuildCombinedLogs(void) {
    NSMutableString *s = [NSMutableString stringWithCapacity:8192];
    [s appendString:@"=== /var/log/vpnctld.log ===\n"];
    [s appendString:ReadFileTail(@"/var/log/vpnctld.log", 8192)];

    [s appendString:@"\n\n=== /var/log/vless-core.log ===\n"];
    [s appendString:ReadFileTail(@"/var/log/vless-core.log", 8192)];
    return s;
}

static int Base64Value(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return (int)(c - 'A');
    if (c >= 'a' && c <= 'z') return (int)(c - 'a') + 26;
    if (c >= '0' && c <= '9') return (int)(c - '0') + 52;
    if (c == '+' || c == '-') return 62;
    if (c == '/' || c == '_') return 63;
    return -1;
}

static NSData *DecodeBase64String(NSString *input) {
    if (!input) return nil;

    const char *s = [input UTF8String];
    if (!s) return nil;

    size_t in_len = strlen(s);
    if (in_len == 0) return nil;

    size_t cap = (in_len / 4) * 3 + 3;
    unsigned char *out = (unsigned char *)malloc(cap);
    if (!out) return nil;

    int vals[4];
    int vcount = 0;
    size_t out_len = 0;

    for (size_t i = 0; i < in_len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
            continue;
        }

        if (c == '=') {
            vals[vcount++] = -2;
        } else {
            int v = Base64Value(c);
            if (v < 0) {
                free(out);
                return nil;
            }
            vals[vcount++] = v;
        }

        if (vcount == 4) {
            if (vals[0] < 0 || vals[1] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));

            if (vals[2] == -2) {
                vcount = 0;
                break;
            }
            if (vals[2] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)(((vals[1] & 0x0F) << 4) | (vals[2] >> 2));

            if (vals[3] == -2) {
                vcount = 0;
                break;
            }
            if (vals[3] < 0) {
                free(out);
                return nil;
            }

            out[out_len++] = (unsigned char)(((vals[2] & 0x03) << 6) | vals[3]);
            vcount = 0;
        }
    }

    if (vcount == 2) {
        if (vals[0] < 0 || vals[1] < 0) {
            free(out);
            return nil;
        }
        out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));
    } else if (vcount == 3) {
        if (vals[0] < 0 || vals[1] < 0 || vals[2] < 0) {
            free(out);
            return nil;
        }
        out[out_len++] = (unsigned char)((vals[0] << 2) | (vals[1] >> 4));
        out[out_len++] = (unsigned char)(((vals[1] & 0x0F) << 4) | (vals[2] >> 2));
    } else if (vcount != 0) {
        free(out);
        return nil;
    }

    return [NSData dataWithBytesNoCopy:out length:out_len freeWhenDone:YES];
}

static UIImage *LoadBundledIconScaled(NSString *baseName, CGFloat size) {
    NSString *path = [[NSBundle mainBundle] pathForResource:baseName ofType:@"png"];
    if (!path) return nil;

    UIImage *raw = [UIImage imageWithContentsOfFile:path];
    if (!raw) return nil;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
    [raw drawInRect:CGRectMake(0, 0, size, size)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

static UIImage *SolidImageWithColor(UIColor *color) {
    CGRect rect = CGRectMake(0, 0, 4, 4);
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0f);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillRect(ctx, rect);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

static UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active) {
    CGSize iconSize = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(iconSize, NO, 0.0f);

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *clr = active ? [UIColor colorWithRed:0.10f green:0.44f blue:0.86f alpha:1.0f]
                          : [UIColor colorWithWhite:0.25f alpha:1.0f];
    CGContextSetStrokeColorWithColor(ctx, clr.CGColor);
    CGContextSetFillColorWithColor(ctx, clr.CGColor);
    CGContextSetLineWidth(ctx, 2.0f);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);

    CGFloat c = size * 0.5f;
    CGFloat r = size * 0.34f;

    if (type == VCIconTypeAdd) {
        CGContextMoveToPoint(ctx, c, c - r);
        CGContextAddLineToPoint(ctx, c, c + r);
        CGContextMoveToPoint(ctx, c - r, c);
        CGContextAddLineToPoint(ctx, c + r, c);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeTerminal) {
        CGRect box = CGRectMake(size * 0.14f, size * 0.18f, size * 0.72f, size * 0.64f);
        UIBezierPath *bp = [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:size * 0.10f];
        bp.lineWidth = 2.0f;
        [bp stroke];

        CGContextMoveToPoint(ctx, size * 0.30f, c);
        CGContextAddLineToPoint(ctx, size * 0.42f, c + size * 0.10f);
        CGContextMoveToPoint(ctx, size * 0.30f, c);
        CGContextAddLineToPoint(ctx, size * 0.42f, c - size * 0.10f);
        CGContextMoveToPoint(ctx, size * 0.48f, c + size * 0.12f);
        CGContextAddLineToPoint(ctx, size * 0.68f, c + size * 0.12f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeRefresh) {
        CGRect arcRect = CGRectMake(c - r, c - r, r * 2.0f, r * 2.0f);
        UIBezierPath *ap = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                           radius:r
                                                       startAngle:(CGFloat)(M_PI * 0.22f)
                                                         endAngle:(CGFloat)(M_PI * 1.85f)
                                                        clockwise:YES];
        ap.lineWidth = 2.0f;
        [ap stroke];

        CGPoint tip = CGPointMake(CGRectGetMaxX(arcRect) - size * 0.02f, c - size * 0.08f);
        CGContextMoveToPoint(ctx, tip.x, tip.y);
        CGContextAddLineToPoint(ctx, tip.x - size * 0.12f, tip.y + size * 0.01f);
        CGContextAddLineToPoint(ctx, tip.x - size * 0.02f, tip.y + size * 0.10f);
        CGContextClosePath(ctx);
        CGContextFillPath(ctx);
    } else if (type == VCIconTypeSettings) {
        for (int i = 0; i < 8; i++) {
            CGFloat a = (CGFloat)i * (CGFloat)(M_PI / 4.0);
            CGFloat r1 = size * 0.22f;
            CGFloat r2 = size * 0.37f;
            CGFloat x1 = c + cosf(a) * r1;
            CGFloat y1 = c + sinf(a) * r1;
            CGFloat x2 = c + cosf(a) * r2;
            CGFloat y2 = c + sinf(a) * r2;
            CGContextMoveToPoint(ctx, x1, y1);
            CGContextAddLineToPoint(ctx, x2, y2);
        }
        CGContextStrokePath(ctx);

        UIBezierPath *outer = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                              radius:size * 0.21f
                                                          startAngle:0
                                                            endAngle:(CGFloat)(M_PI * 2.0f)
                                                           clockwise:YES];
        outer.lineWidth = 2.0f;
        [outer stroke];

        UIBezierPath *inner = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c)
                                                              radius:size * 0.08f
                                                          startAngle:0
                                                            endAngle:(CGFloat)(M_PI * 2.0f)
                                                           clockwise:YES];
        inner.lineWidth = 2.0f;
        [inner stroke];
    } else if (type == VCIconTypeChevronRight) {
        CGContextMoveToPoint(ctx, size * 0.38f, size * 0.24f);
        CGContextAddLineToPoint(ctx, size * 0.62f, size * 0.50f);
        CGContextAddLineToPoint(ctx, size * 0.38f, size * 0.76f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeChevronDown) {
        CGContextMoveToPoint(ctx, size * 0.24f, size * 0.38f);
        CGContextAddLineToPoint(ctx, size * 0.50f, size * 0.62f);
        CGContextAddLineToPoint(ctx, size * 0.76f, size * 0.38f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeWifi) {
        UIBezierPath *a1 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.10f)
                                                          radius:size * 0.30f
                                                      startAngle:(CGFloat)(M_PI * 1.20f)
                                                        endAngle:(CGFloat)(M_PI * 1.80f)
                                                       clockwise:YES];
        a1.lineWidth = 2.0f;
        [a1 stroke];

        UIBezierPath *a2 = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.10f)
                                                          radius:size * 0.20f
                                                      startAngle:(CGFloat)(M_PI * 1.20f)
                                                        endAngle:(CGFloat)(M_PI * 1.80f)
                                                       clockwise:YES];
        a2.lineWidth = 2.0f;
        [a2 stroke];

        UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:CGPointMake(c, c + size * 0.22f)
                                                           radius:size * 0.05f
                                                       startAngle:0
                                                         endAngle:(CGFloat)(M_PI * 2.0f)
                                                        clockwise:YES];
        [dot fill];
    } else if (type == VCIconTypeCheck) {
        UIColor *ok = [UIColor colorWithRed:0.10f green:0.50f blue:0.15f alpha:1.0f];
        CGContextSetStrokeColorWithColor(ctx, ok.CGColor);
        CGContextMoveToPoint(ctx, size * 0.20f, size * 0.54f);
        CGContextAddLineToPoint(ctx, size * 0.42f, size * 0.74f);
        CGContextAddLineToPoint(ctx, size * 0.80f, size * 0.30f);
        CGContextStrokePath(ctx);
    } else if (type == VCIconTypeList) {
        CGFloat ys[3] = { size * 0.30f, size * 0.50f, size * 0.70f };
        for (int i = 0; i < 3; i++) {
            CGFloat y = ys[i];
            UIBezierPath *dot = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size * 0.22f, y)
                                                               radius:size * 0.05f
                                                           startAngle:0
                                                             endAngle:(CGFloat)(M_PI * 2.0f)
                                                            clockwise:YES];
            [dot fill];
            CGContextMoveToPoint(ctx, size * 0.34f, y);
            CGContextAddLineToPoint(ctx, size * 0.80f, y);
        }
        CGContextStrokePath(ctx);
    }

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@interface MainVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UITextViewDelegate> {
    UIButton *_connectBtn;
    UIButton *_plusBtn;
    UIButton *_terminalBtn;
    UIButton *_refreshBtn;
    UIButton *_settingsBtn;
    UILabel *_statusLabel;
    UILabel *_titleLabel;

    UITableView *_tableView;
    UITextView *_logView;
    NSTimer *_logTimer;
    NSTimer *_uptimeTimer;
    NSTimeInterval _connectedSince;
    NSString *_statusBaseText;

    NSMutableArray *_configs;
    NSMutableArray *_subscriptions;

    NSInteger _selectedConfigIndex;
    NSInteger _selectedSubIndex;
    NSInteger _selectedSubItemIndex;
    NSInteger _expandedSubscription;

    BOOL _connected;
    BOOL _showingTerminal;
    BOOL _autoUpdateSubscriptions;
}
@end

@implementation MainVC

- (NSString *)safeTrim:(NSString *)s {
    if (!s) return @"";
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)decodedFragmentFromURI:(NSString *)uri {
    NSRange hash = [uri rangeOfString:@"#" options:NSBackwardsSearch];
    if (hash.location == NSNotFound) return nil;
    NSString *frag = [uri substringFromIndex:(hash.location + 1)];
    frag = [frag stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    frag = [self safeTrim:frag];
    return [frag length] > 0 ? frag : nil;
}

- (NSString *)hostFromVLESSURI:(NSString *)uri {
    NSRange at = [uri rangeOfString:@"@"];
    if (at.location == NSNotFound) return @"vless";

    NSUInteger start = at.location + 1;
    NSUInteger i = start;
    while (i < [uri length]) {
        unichar c = [uri characterAtIndex:i];
        if (c == ':' || c == '?' || c == '/' || c == '#') break;
        i++;
    }
    if (i <= start) return @"vless";
    return [uri substringWithRange:NSMakeRange(start, i - start)];
}

- (NSString *)displayNameForURI:(NSString *)uri index:(NSInteger)index {
    NSString *name = [self decodedFragmentFromURI:uri];
    if (name) return name;

    NSString *host = [self hostFromVLESSURI:uri];
    return [NSString stringWithFormat:@"Config %ld (%@)", (long)(index + 1), host];
}

- (NSString *)hostFromURLString:(NSString *)urlString {
    NSURL *u = [NSURL URLWithString:urlString];
    NSString *h = [u host];
    if (!h || [h length] == 0) return @"subscription";
    return h;
}

- (BOOL)isSubscriptionURL:(NSString *)s {
    return [s hasPrefix:@"http://"] || [s hasPrefix:@"https://"];
}

- (BOOL)isVLESSURI:(NSString *)s {
    return [s hasPrefix:@"vless://"];
}

- (void)saveData {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:_configs forKey:kDefaultsConfigsKey];
    [ud setObject:_subscriptions forKey:kDefaultsSubsKey];
    [ud setBool:_autoUpdateSubscriptions forKey:kDefaultsAutoUpdateSubsKey];
    [ud synchronize];
}

- (void)loadData {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];

    NSArray *cfg = [ud objectForKey:kDefaultsConfigsKey];
    if ([cfg isKindOfClass:[NSArray class]]) {
        _configs = [[NSMutableArray alloc] initWithArray:cfg];
    } else {
        _configs = [[NSMutableArray alloc] init];
    }

    NSArray *subs = [ud objectForKey:kDefaultsSubsKey];
    if ([subs isKindOfClass:[NSArray class]]) {
        _subscriptions = [[NSMutableArray alloc] initWithArray:subs];
    } else {
        _subscriptions = [[NSMutableArray alloc] init];
    }

    if ([ud objectForKey:kDefaultsAutoUpdateSubsKey] == nil) {
        _autoUpdateSubscriptions = YES;
    } else {
        _autoUpdateSubscriptions = [ud boolForKey:kDefaultsAutoUpdateSubsKey];
    }

    _selectedConfigIndex = -1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    _expandedSubscription = -1;

    if ([_configs count] > 0) {
        _selectedConfigIndex = 0;
    }
}

- (NSArray *)subscriptionItemsAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return [NSArray array];
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return [NSArray array];
    return items;
}

- (NSInteger)subscriptionSectionRowCount {
    NSInteger rows = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        rows += 1;
        if (i == _expandedSubscription) {
            rows += (NSInteger)[[self subscriptionItemsAtIndex:i] count];
        }
    }
    return rows;
}

- (BOOL)mapSubscriptionRow:(NSInteger)row toSubIndex:(NSInteger *)subIndex itemIndex:(NSInteger *)itemIndex isHeader:(BOOL *)isHeader {
    NSInteger cursor = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        if (row == cursor) {
            if (subIndex) *subIndex = i;
            if (itemIndex) *itemIndex = -1;
            if (isHeader) *isHeader = YES;
            return YES;
        }
        cursor += 1;

        if (i == _expandedSubscription) {
            NSArray *items = [self subscriptionItemsAtIndex:i];
            NSInteger cnt = (NSInteger)[items count];
            if (row < cursor + cnt) {
                if (subIndex) *subIndex = i;
                if (itemIndex) *itemIndex = row - cursor;
                if (isHeader) *isHeader = NO;
                return YES;
            }
            cursor += cnt;
        }
    }
    return NO;
}

- (void)normalizeSelection {
    if (_selectedConfigIndex >= (NSInteger)[_configs count]) {
        _selectedConfigIndex = -1;
    }

    if (_selectedSubIndex >= (NSInteger)[_subscriptions count]) {
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
    }

    if (_selectedSubIndex >= 0) {
        NSArray *items = [self subscriptionItemsAtIndex:_selectedSubIndex];
        if ([items count] == 0) {
            _selectedSubItemIndex = -1;
        } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[items count]) {
            _selectedSubItemIndex = 0;
        }
    }
}

- (NSString *)sanitizeDaemonText:(NSString *)text {
    if (!text) return @"";
    NSString *s = [text stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    while ([s rangeOfString:@"  "].location != NSNotFound) {
        s = [s stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)formatDuration:(NSTimeInterval)seconds {
    NSInteger total = (NSInteger)(seconds >= 0 ? seconds : 0);
    NSInteger h = total / 3600;
    NSInteger m = (total % 3600) / 60;
    NSInteger s = total % 60;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld", (long)h, (long)m, (long)s];
}

- (void)refreshStatusText {
    NSString *base = _statusBaseText ? _statusBaseText : @"";
    if (_connected && _connectedSince > 0) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - _connectedSince;
        NSString *uptime = [self formatDuration:delta];
        _statusLabel.text = [NSString stringWithFormat:@"%@\nConnected: %@", base, uptime];
    } else {
        _statusLabel.text = base;
    }
}

- (void)startUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;

    _connectedSince = [[NSDate date] timeIntervalSince1970];
    _uptimeTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                     target:self
                                                   selector:@selector(uptimeTick:)
                                                   userInfo:nil
                                                    repeats:YES] retain];
}

- (void)stopUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;
    _connectedSince = 0;
}

- (void)uptimeTick:(NSTimer *)timer {
    (void)timer;
    [self refreshStatusText];
}

- (void)showStatus:(NSString *)text ok:(BOOL)ok {
    [_statusBaseText release];
    _statusBaseText = [[self sanitizeDaemonText:text] copy];
    _statusLabel.textColor = ok ? [UIColor colorWithRed:0.1f green:0.5f blue:0.1f alpha:1.0f]
                                : [UIColor colorWithRed:0.7f green:0.0f blue:0.0f alpha:1.0f];
    [self refreshStatusText];
}

- (BOOL)parseVLESSHost:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    NSRange at = [uri rangeOfString:@"@"];
    if (at.location == NSNotFound) return NO;

    NSUInteger hostStart = at.location + 1;
    NSUInteger i = hostStart;
    while (i < [uri length]) {
        unichar c = [uri characterAtIndex:i];
        if (c == ':' || c == '?' || c == '/' || c == '#') break;
        i++;
    }
    if (i <= hostStart) return NO;

    NSString *host = [uri substringWithRange:NSMakeRange(hostStart, i - hostStart)];
    uint16_t port = 443;
    if (i < [uri length] && [uri characterAtIndex:i] == ':') {
        NSUInteger pStart = i + 1;
        NSUInteger j = pStart;
        while (j < [uri length]) {
            unichar c = [uri characterAtIndex:j];
            if (c < '0' || c > '9') break;
            j++;
        }
        if (j > pStart) {
            NSInteger p = [[uri substringWithRange:NSMakeRange(pStart, j - pStart)] integerValue];
            if (p > 0 && p <= 65535) port = (uint16_t)p;
        }
    }

    if (hostOut) *hostOut = host;
    if (portOut) *portOut = port;
    return YES;
}

- (BOOL)isXHTTPTransportURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;

    NSRange q = [uri rangeOfString:@"?"];
    if (q.location == NSNotFound) return NO;

    NSUInteger start = q.location + 1;
    NSUInteger end = [uri length];
    NSRange hash = [uri rangeOfString:@"#" options:0 range:NSMakeRange(start, end - start)];
    if (hash.location != NSNotFound) {
        end = hash.location;
    }
    if (end <= start) return NO;

    NSString *query = [uri substringWithRange:NSMakeRange(start, end - start)];
    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        if (![pair isKindOfClass:[NSString class]] || [pair length] == 0) continue;

        NSRange eq = [pair rangeOfString:@"="];
        NSString *k = (eq.location == NSNotFound) ? pair : [pair substringToIndex:eq.location];
        NSString *v = (eq.location == NSNotFound) ? @"" : [pair substringFromIndex:(eq.location + 1)];

        k = [k lowercaseString];
        NSString *decoded = [v stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        if (decoded) v = decoded;
        v = [v lowercaseString];

        if ([k isEqualToString:@"type"] && [v isEqualToString:@"xhttp"]) {
            return YES;
        }
    }
    return NO;
}

- (void)pingWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];
    NSString *title = [payload objectForKey:@"title"];

    NSString *host = nil;
    uint16_t port = 0;
    NSString *result = nil;
    if (![self parseVLESSHost:&host port:&port fromURI:uri]) {
        result = [NSString stringWithFormat:@"Ping failed (%@): invalid URI", title ? title : @"config"];
    } else {
        int ms = 0;
        int rc = -1;

        if ([self isXHTTPTransportURI:uri]) {
            // For xhttp we keep a real tunnel ping (same flow as runtime), but take best-of-2.
            rc = RealPingViaTempCoreMs([uri UTF8String], 5000, 2, &ms);
            if (rc != 0) {
                rc = ConnectLatencyBestOfNMs([host UTF8String], port, 3500, 2, &ms);
            }
        } else {
            // For vision/reality and other transports prefer real tunnel delay first.
            rc = RealPingViaTempCoreMs([uri UTF8String], 5000, 2, &ms);
            if (rc != 0) {
                rc = ConnectLatencyBestOfNMs([host UTF8String], port, 3500, 2, &ms);
            }
        }

        if (rc == 0) {
            result = [NSString stringWithFormat:@"Ping %@ = %d ms", title ? title : host, ms];
        } else {
            result = [NSString stringWithFormat:@"Ping %@ failed", title ? title : host];
        }
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:2];
    [out setObject:(result ? result : @"Ping failed") forKey:@"text"];
    [self performSelectorOnMainThread:@selector(pingResultOnMain:) withObject:out waitUntilDone:NO];

    [pool drain];
}

- (void)pingResultOnMain:(NSDictionary *)payload {
    NSString *text = [payload objectForKey:@"text"];
    [self showStatus:text ok:([text rangeOfString:@"failed"].location == NSNotFound)];
}

- (void)pingButtonPressed:(UIButton *)sender {
    NSInteger tag = sender.tag;
    NSString *uri = nil;
    NSString *title = @"config";

    if (tag >= 10000 && tag < 20000) {
        NSInteger idx = tag - 10000;
        if (idx >= 0 && idx < (NSInteger)[_configs count]) {
            NSDictionary *cfg = [_configs objectAtIndex:idx];
            uri = [cfg objectForKey:@"uri"];
            NSString *name = [cfg objectForKey:@"name"];
            if ([name isKindOfClass:[NSString class]] && [name length] > 0) title = name;
        }
    } else if (tag >= 20000) {
        NSInteger code = tag - 20000;
        NSInteger subIdx = code / 1000;
        NSInteger itemIdx = code % 1000;
        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        if (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) {
            uri = [items objectAtIndex:itemIdx];
            title = [self displayNameForURI:uri index:itemIdx];
        }
    }

    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) {
        [self showStatus:@"Ping failed: no URI" ok:NO];
        return;
    }

    [self showStatus:[NSString stringWithFormat:@"Pinging %@...", title] ok:YES];
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             uri, @"uri",
                             title, @"title",
                             nil];
    [NSThread detachNewThreadSelector:@selector(pingWorker:) toTarget:self withObject:payload];
}

- (void)updateConnectButton {
    NSString *title = _connected ? @"Disconnect" : @"Connect";
    [_connectBtn setTitle:title forState:UIControlStateNormal];

    UIColor *fill = _connected
        ? [UIColor colorWithRed:0.12f green:0.58f blue:0.20f alpha:1.0f]
        : [UIColor colorWithRed:0.10f green:0.40f blue:0.82f alpha:1.0f];
    _connectBtn.backgroundColor = fill;
}

- (void)applyTouchFeedbackToButton:(UIButton *)btn {
    if (!btn) return;
    btn.showsTouchWhenHighlighted = YES;
    btn.adjustsImageWhenHighlighted = YES;
    btn.layer.masksToBounds = NO;
    [btn addTarget:self action:@selector(buttonTouchDown:) forControlEvents:UIControlEventTouchDown];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpInside];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchUpOutside];
    [btn addTarget:self action:@selector(buttonTouchUp:) forControlEvents:UIControlEventTouchCancel];
}

- (void)applyTopButtonFeedbackToButton:(UIButton *)btn {
    if (!btn) return;
    btn.showsTouchWhenHighlighted = NO;
    btn.adjustsImageWhenHighlighted = NO;
    btn.layer.cornerRadius = 6.0f;
    btn.layer.masksToBounds = YES;
    [btn setBackgroundImage:SolidImageWithColor([UIColor colorWithWhite:0.0f alpha:0.0f]) forState:UIControlStateNormal];
    [btn setBackgroundImage:SolidImageWithColor([UIColor colorWithWhite:0.72f alpha:1.0f]) forState:UIControlStateHighlighted];
    [btn setBackgroundImage:SolidImageWithColor([UIColor colorWithWhite:0.72f alpha:1.0f]) forState:UIControlStateSelected];
}

- (void)buttonTouchDown:(UIButton *)sender {
    sender.layer.shadowColor = [UIColor blackColor].CGColor;
    sender.layer.shadowOffset = CGSizeMake(0.0f, 2.0f);
    sender.layer.shadowRadius = 4.0f;
    sender.layer.shadowOpacity = 0.35f;
}

- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.12
                     animations:^{
                         sender.layer.shadowOpacity = 0.0f;
                     }];
}

- (void)updateTopButtonsIcons {
    [_plusBtn setImage:MakeIconImage(VCIconTypeAdd, 20.0f, NO) forState:UIControlStateNormal];
    UIImage *refresh = LoadBundledIconScaled(@"icon-refresh", 20.0f);
    UIImage *terminal = _showingTerminal
        ? LoadBundledIconScaled(@"icon-list", 20.0f)
        : LoadBundledIconScaled(@"icon-terminal", 20.0f);
    UIImage *settings = LoadBundledIconScaled(@"icon-settings", 20.0f);

    [_refreshBtn setImage:(refresh ? refresh : MakeIconImage(VCIconTypeRefresh, 20.0f, NO)) forState:UIControlStateNormal];
    [_terminalBtn setImage:(terminal ? terminal : MakeIconImage(_showingTerminal ? VCIconTypeList : VCIconTypeTerminal, 20.0f, _showingTerminal))
                  forState:UIControlStateNormal];
    [_settingsBtn setImage:(settings ? settings : MakeIconImage(VCIconTypeSettings, 20.0f, NO)) forState:UIControlStateNormal];
}

- (NSArray *)extractVLESSURIsFromText:(NSString *)text {
    if (!text || [text length] == 0) return [NSArray array];

    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"vless://[^\\s\"'<>]+"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&reErr];
    if (!re || reErr) {
        return [NSArray array];
    }

    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, [text length])];
    NSMutableArray *out = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location == NSNotFound || m.range.length == 0) continue;
        NSString *uri = [text substringWithRange:m.range];

        while ([uri hasSuffix:@","] || [uri hasSuffix:@";"] || [uri hasSuffix:@")"] || [uri hasSuffix:@"]"]) {
            if ([uri length] <= 1) break;
            uri = [uri substringToIndex:([uri length] - 1)];
        }

        if ([uri length] == 0) continue;
        if (![out containsObject:uri]) {
            [out addObject:uri];
        }
    }
    return out;
}

- (NSArray *)parseSubscriptionData:(NSData *)data {
    if (!data || [data length] == 0) return [NSArray array];

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];

    NSArray *uris = [NSArray array];
    if (raw) {
        uris = [self extractVLESSURIsFromText:raw];
        if ([uris count] > 0) return uris;

        NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        NSData *decoded = DecodeBase64String(b64);
        if (decoded && [decoded length] > 0) {
            NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
            if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
            if (decodedText) {
                uris = [self extractVLESSURIsFromText:decodedText];
                if ([uris count] > 0) return uris;
            }
        }
    }

    return [NSArray array];
}

- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus {
    if (idx < 0 || idx >= (NSInteger)[_subscriptions count]) return NO;

    NSDictionary *sub = [_subscriptions objectAtIndex:idx];
    NSString *urlString = [sub objectForKey:@"url"];
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return NO;

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return NO;

    NSString *fetchErr = nil;
    NSData *data = FetchURLViaVlessCoreCurl(urlString, &fetchErr);
    if (!data && (!fetchErr || [fetchErr hasPrefix:@"vless-core-curl not found"])) {
        NSURLRequest *req = [NSURLRequest requestWithURL:url
                                             cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                         timeoutInterval:20.0];
        NSURLResponse *resp = nil;
        NSError *err = nil;
        data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        if (!data || err) {
            fetchErr = [err localizedDescription];
        }
    }

    if (!data) {
        if (showStatus) {
            if (![fetchErr isKindOfClass:[NSString class]] || [fetchErr length] == 0) {
                fetchErr = @"unknown error";
            }
            [self showStatus:[NSString stringWithFormat:@"Subscription fetch failed: %@", fetchErr] ok:NO];
        }
        return NO;
    }

    NSArray *uris = [self parseSubscriptionData:data];
    if ([uris count] == 0) {
        if (showStatus) {
            [self showStatus:@"Subscription has no valid vless:// entries" ok:NO];
        }
        return NO;
    }

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updated setObject:uris forKey:@"items"];

    NSString *name = [updated objectForKey:@"name"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        [updated setObject:[self hostFromURLString:urlString] forKey:@"name"];
    }

    [_subscriptions replaceObjectAtIndex:idx withObject:updated];
    if (_selectedSubIndex == idx) {
        if ((NSInteger)[uris count] <= 0) {
            _selectedSubItemIndex = -1;
        } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
            _selectedSubItemIndex = 0;
        }
    }
    [self saveData];
    if (showStatus) {
        [self showStatus:[NSString stringWithFormat:@"Subscription updated (%lu configs)", (unsigned long)[uris count]] ok:YES];
    }
    return YES;
}

- (void)refreshAllSubscriptions:(BOOL)showStatus {
    if ([_subscriptions count] == 0) {
        if (showStatus) [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }

    NSUInteger okCount = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        if ([self refreshSubscriptionAtIndex:i showStatus:NO]) {
            okCount++;
        }
    }

    [self normalizeSelection];
    [_tableView reloadData];

    if (showStatus) {
        BOOL ok = okCount > 0;
        [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
                          (unsigned long)okCount,
                          (unsigned long)[_subscriptions count]]
                     ok:ok];
    }
}

- (void)showAbout {
    NSString *ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (![ver isKindOfClass:[NSString class]] || [ver length] == 0) {
        ver = @"0.0.0";
    }
    NSString *coreBinary = @"vless-core-darwin-amrv7";
    NSString *coreVersion = DetectCoreBinaryVersion();

    NSString *msg =
        [NSString stringWithFormat:
         @"vless-core app %@\n"
         @"\n"
         @"Core binary: %@\n"
         @"Binary version: %@\n"
         @"\n"
         @"made by notfence",
         ver, coreBinary, coreVersion];

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"About vless-core"
                                                   message:msg
                                                  delegate:nil
                                         cancelButtonTitle:@"OK"
                                         otherButtonTitles:nil] autorelease];
    [av show];
}

- (UIView *)accessoryChevronExpanded:(BOOL)expanded {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)] autorelease];
    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(2, 2, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];
    return v;
}

- (UIView *)accessoryPingWithTag:(NSInteger)tag selected:(BOOL)selected {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 24)] autorelease];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 24, 24);
    UIImage *pingIcon = LoadBundledIconScaled(@"icon-ping", 18.0f);
    [btn setImage:(pingIcon ? pingIcon : MakeIconImage(VCIconTypeWifi, 18.0f, NO)) forState:UIControlStateNormal];
    btn.tag = tag;
    [btn addTarget:self action:@selector(pingButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:btn];
    [v addSubview:btn];

    if (selected) {
        UIImageView *chk = [[[UIImageView alloc] initWithFrame:CGRectMake(28, 4, 16, 16)] autorelease];
        chk.image = MakeIconImage(VCIconTypeCheck, 16.0f, YES);
        [v addSubview:chk];
    }

    return v;
}

- (void)importDirectURI:(NSString *)uri {
    NSString *name = [self displayNameForURI:uri index:[_configs count]];
    NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                         name, @"name",
                         uri, @"uri",
                         nil];
    [_configs addObject:cfg];
    [self saveData];

    _selectedConfigIndex = [_configs count] - 1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    [_tableView reloadData];
    [self showStatus:@"Configuration imported" ok:YES];
}

- (void)importSubscriptionURL:(NSString *)urlString {
    NSString *name = [self hostFromURLString:urlString];

    NSDictionary *sub = [NSDictionary dictionaryWithObjectsAndKeys:
                         name, @"name",
                         urlString, @"url",
                         [NSArray array], @"items",
                         nil];

    NSInteger existing = -1;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *it = [_subscriptions objectAtIndex:i];
        if ([[it objectForKey:@"url"] isEqualToString:urlString]) {
            existing = i;
            break;
        }
    }

    NSInteger subIndex = 0;
    if (existing >= 0) {
        [_subscriptions replaceObjectAtIndex:existing withObject:sub];
        subIndex = existing;
    } else {
        [_subscriptions addObject:sub];
        subIndex = [_subscriptions count] - 1;
    }

    _expandedSubscription = subIndex;
    [self saveData];
    [self refreshSubscriptionAtIndex:subIndex showStatus:YES];
    _selectedConfigIndex = -1;
    _selectedSubIndex = subIndex;
    _selectedSubItemIndex = 0;
    [self normalizeSelection];
    [_tableView reloadData];
}

- (void)importTextEntry:(NSString *)rawText {
    NSString *text = [self safeTrim:rawText];
    if ([text length] == 0) {
        [self showStatus:@"Import text is empty" ok:NO];
        return;
    }

    if ([self isVLESSURI:text]) {
        [self importDirectURI:text];
        return;
    }

    if ([self isSubscriptionURL:text]) {
        [self importSubscriptionURL:text];
        return;
    }

    NSArray *uris = [self extractVLESSURIsFromText:text];
    if ([uris count] > 0) {
        for (NSString *uri in uris) {
            [self importDirectURI:uri];
        }
        [self showStatus:[NSString stringWithFormat:@"Imported %lu configurations", (unsigned long)[uris count]] ok:YES];
        return;
    }

    [self showStatus:@"Unsupported import format (use vless:// or http(s) subscription)" ok:NO];
}

- (NSString *)uriForCurrentSelection {
    if (_selectedConfigIndex >= 0 && _selectedConfigIndex < (NSInteger)[_configs count]) {
        NSDictionary *cfg = [_configs objectAtIndex:_selectedConfigIndex];
        NSString *uri = [cfg objectForKey:@"uri"];
        if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
            return uri;
        }
    }

    if (_selectedSubIndex >= 0 && _selectedSubIndex < (NSInteger)[_subscriptions count]) {
        NSDictionary *sub = [_subscriptions objectAtIndex:_selectedSubIndex];
        NSArray *items = [sub objectForKey:@"items"];
        if (![items isKindOfClass:[NSArray class]] || [items count] == 0) {
            if (![self refreshSubscriptionAtIndex:_selectedSubIndex showStatus:NO]) {
                return nil;
            }
            sub = [_subscriptions objectAtIndex:_selectedSubIndex];
            items = [sub objectForKey:@"items"];
        }

        if ([items isKindOfClass:[NSArray class]] && [items count] > 0) {
            NSInteger idx = _selectedSubItemIndex;
            if (idx < 0 || idx >= (NSInteger)[items count]) idx = 0;
            NSString *uri = [items objectAtIndex:idx];
            if ([uri isKindOfClass:[NSString class]] && [uri length] > 0) {
                return uri;
            }
        }
    }

    return nil;
}

- (void)reconnectToURIIfNeededFrom:(NSString *)oldURI to:(NSString *)newURI {
    if (!_connected) return;
    if (![oldURI isKindOfClass:[NSString class]] || ![newURI isKindOfClass:[NSString class]]) return;
    if ([oldURI length] == 0 || [newURI length] == 0) return;
    if ([oldURI isEqualToString:newURI]) return;

    [self showStatus:@"Reconnecting to selected config..." ok:YES];

    NSString *discResp = [self sanitizeDaemonText:SendCommand(@"DISCONNECT\n")];
    if (![discResp hasPrefix:@"OK"]) {
        [self showStatus:[NSString stringWithFormat:@"Reconnect failed (disconnect): %@", discResp] ok:NO];
        return;
    }

    NSString *cmd = [NSString stringWithFormat:@"CONNECT\t0\t%@\n", newURI];
    NSString *connResp = [self sanitizeDaemonText:SendCommand(cmd)];
    if ([connResp hasPrefix:@"OK"]) {
        _connected = YES;
        [self startUptimeTimer];
        [self updateConnectButton];
        [self showStatus:@"Connected (switched config)" ok:YES];
    } else {
        _connected = NO;
        [self stopUptimeTimer];
        [self updateConnectButton];
        [self showStatus:[NSString stringWithFormat:@"Reconnect failed (connect): %@", connResp] ok:NO];
    }
}

- (void)togglePressed {
    if (!_connected) {
        NSString *uri = [self uriForCurrentSelection];
        if (!uri) {
            [self showStatus:@"Select/import a configuration first" ok:NO];
            return;
        }

        NSString *cmd = [NSString stringWithFormat:@"CONNECT\t0\t%@\n", uri];
        NSString *resp = [self sanitizeDaemonText:SendCommand(cmd)];
        if ([resp hasPrefix:@"OK"]) {
            _connected = YES;
            [self startUptimeTimer];
            [self updateConnectButton];
            [self showStatus:@"Connected" ok:YES];
        } else {
            [self showStatus:resp ok:NO];
        }
        return;
    }

    NSString *resp = [self sanitizeDaemonText:SendCommand(@"DISCONNECT\n")];
    if ([resp hasPrefix:@"OK"]) {
        _connected = NO;
        [self stopUptimeTimer];
        [self updateConnectButton];
        [self showStatus:@"Ready" ok:YES];
    } else {
        [self showStatus:resp ok:NO];
    }
}

- (void)plusPressed {
    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Import"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:@"Import from Clipboard", @"Manual Input", nil] autorelease];
    sheet.tag = VCActionSheetTagImport;
    [sheet showInView:self.view];
}

- (void)refreshPressed {
    [self refreshAllSubscriptions:YES];
}

- (void)settingsPressed {
    NSString *autoUpdateTitle = _autoUpdateSubscriptions ? @"Auto-update subscriptions: ON"
                                                         : @"Auto-update subscriptions: OFF";

    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:@"Settings"
                                                         delegate:self
                                                cancelButtonTitle:@"Close"
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:autoUpdateTitle, @"About", nil] autorelease];
    sheet.tag = VCActionSheetTagSettings;
    [sheet showInView:self.view];
}

- (void)terminalPressed {
    _showingTerminal = !_showingTerminal;

    _tableView.hidden = _showingTerminal;
    _logView.hidden = !_showingTerminal;

    if (_showingTerminal) {
        [self refreshLogs];
        if (!_logTimer) {
            _logTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
                                                          target:self
                                                        selector:@selector(refreshLogsTick:)
                                                        userInfo:nil
                                                         repeats:YES] retain];
        }
    } else {
        [_logTimer invalidate];
        [_logTimer release];
        _logTimer = nil;
    }

    [self updateTopButtonsIcons];
}

- (void)refreshLogs {
    if (_logView.selectedRange.length > 0) {
        return;
    }

    NSString *newText = BuildCombinedLogs();
    NSString *oldText = _logView.text ? _logView.text : @"";
    if ([newText isEqualToString:oldText]) {
        return;
    }

    CGFloat maxOffsetY = _logView.contentSize.height - _logView.bounds.size.height;
    if (maxOffsetY < 0.0f) maxOffsetY = 0.0f;
    BOOL wasNearBottom = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));

    _logView.text = newText;
    if (wasNearBottom && [_logView.text length] > 0) {
        NSRange r = NSMakeRange([_logView.text length] - 1, 1);
        [_logView scrollRangeToVisible:r];
    }
}

- (void)refreshLogsTick:(NSTimer *)timer {
    (void)timer;
    [self refreshLogs];
}

- (void)queryInitialStatus {
    NSString *resp = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
    if ([resp hasPrefix:@"OK connected"]) {
        _connected = YES;
        [self startUptimeTimer];
        [self showStatus:@"Connected" ok:YES];
    } else {
        _connected = NO;
        [self stopUptimeTimer];
        [self showStatus:@"Ready" ok:YES];
    }
    [self updateConnectButton];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.97f alpha:1.0f];

    [self loadData];

    CGRect b = self.view.bounds;
    UIColor *bg = [UIColor colorWithWhite:0.97f alpha:1.0f];
    self.view.backgroundColor = bg;

    CGFloat topY = 10.0f;
    CGFloat iconW = 28.0f;
    CGFloat gap = 6.0f;
    CGFloat right = b.size.width - 12.0f;

    CGFloat settingsX = right - iconW;
    CGFloat refreshX = settingsX - gap - iconW;
    CGFloat terminalX = refreshX - gap - iconW;
    CGFloat plusX = terminalX - gap - iconW;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, plusX - 20, 28)];
    _titleLabel.text = @"vless-core";
    _titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    _titleLabel.textColor = [UIColor blackColor];
    _titleLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_titleLabel];

    _plusBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plusBtn.frame = CGRectMake(plusX, topY, iconW, iconW);
    [_plusBtn addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self.view addSubview:_plusBtn];

    _terminalBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _terminalBtn.frame = CGRectMake(terminalX, topY, iconW, iconW);
    [_terminalBtn addTarget:self action:@selector(terminalPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self.view addSubview:_terminalBtn];

    _refreshBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _refreshBtn.frame = CGRectMake(refreshX, topY, iconW, iconW);
    [_refreshBtn addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self.view addSubview:_refreshBtn];

    _settingsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _settingsBtn.frame = CGRectMake(settingsX, topY, iconW, iconW);
    [_settingsBtn addTarget:self action:@selector(settingsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self.view addSubview:_settingsBtn];

    CGFloat btnSize = 122.0f;
    _connectBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _connectBtn.frame = CGRectMake((b.size.width - btnSize) * 0.5f, 74.0f, btnSize, btnSize);
    _connectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20.0f];
    _connectBtn.layer.cornerRadius = btnSize * 0.5f;
    _connectBtn.layer.borderWidth = 2.0f;
    _connectBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.95f].CGColor;
    [_connectBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_connectBtn addTarget:self action:@selector(togglePressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:_connectBtn];
    [self.view addSubview:_connectBtn];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 206, b.size.width - 32, 36)];
    _statusLabel.font = [UIFont systemFontOfSize:12.5f];
    _statusLabel.numberOfLines = 2;
    _statusLabel.text = @"Ready";
    _statusLabel.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_statusLabel];

    CGFloat listY = 242.0f;
    CGFloat listH = b.size.height - listY;
    if (listH < 120.0f) listH = 120.0f;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, listY, b.size.width, listH) style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.opaque = NO;
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    _tableView.tableFooterView = footer;
    [self.view addSubview:_tableView];

    _logView = [[UITextView alloc] initWithFrame:_tableView.frame];
    _logView.editable = NO;
    _logView.font = [UIFont systemFontOfSize:10.0f];
    _logView.backgroundColor = bg;
    _logView.hidden = YES;
    _logView.text = @"Terminal logs";
    _logView.delegate = self;
    [self.view addSubview:_logView];

    [self updateConnectButton];
    [self updateTopButtonsIcons];
    [_tableView reloadData];
    [self queryInitialStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_autoUpdateSubscriptions && [_subscriptions count] > 0) {
        [self refreshAllSubscriptions:YES];
    }
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [_logTimer invalidate];
    [_logTimer release];
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    [_statusBaseText release];

    [_connectBtn release];
    [_plusBtn release];
    [_terminalBtn release];
    [_refreshBtn release];
    [_settingsBtn release];
    [_statusLabel release];
    [_titleLabel release];

    [_tableView release];
    [_logView release];

    [_configs release];
    [_subscriptions release];

    [super dealloc];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (section == 0) ? [_configs count] : [self subscriptionSectionRowCount];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return (section == 0) ? @"Configurations" : @"Subscriptions";
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == 0) {
        return YES;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    return [self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) return;

        [_configs removeObjectAtIndex:indexPath.row];

        if (_selectedConfigIndex == indexPath.row) {
            if ([_configs count] > 0) {
                NSInteger fallback = indexPath.row;
                if (fallback >= (NSInteger)[_configs count]) fallback = (NSInteger)[_configs count] - 1;
                _selectedConfigIndex = fallback;
            } else {
                _selectedConfigIndex = -1;
            }
        } else if (_selectedConfigIndex > indexPath.row) {
            _selectedConfigIndex--;
        }

        [self normalizeSelection];
        [self saveData];
        [_tableView reloadData];
        [self showStatus:@"Configuration deleted" ok:YES];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        return;
    }

    if (isHeader) {
        if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return;

        [_subscriptions removeObjectAtIndex:subIdx];

        if (_expandedSubscription == subIdx) {
            _expandedSubscription = -1;
        } else if (_expandedSubscription > subIdx) {
            _expandedSubscription--;
        }

        if (_selectedSubIndex == subIdx) {
            _selectedSubIndex = -1;
            _selectedSubItemIndex = -1;
        } else if (_selectedSubIndex > subIdx) {
            _selectedSubIndex--;
        }

        [self normalizeSelection];
        [self saveData];
        [_tableView reloadData];
        [self showStatus:@"Subscription deleted" ok:YES];
        return;
    }

    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return;
    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    NSArray *items = [sub objectForKey:@"items"];
    if (![items isKindOfClass:[NSArray class]]) return;
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) return;

    NSMutableArray *updatedItems = [NSMutableArray arrayWithArray:items];
    [updatedItems removeObjectAtIndex:itemIdx];

    NSMutableDictionary *updatedSub = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updatedSub setObject:updatedItems forKey:@"items"];
    [_subscriptions replaceObjectAtIndex:subIdx withObject:updatedSub];

    if (_selectedSubIndex == subIdx) {
        if (_selectedSubItemIndex == itemIdx) {
            if ([updatedItems count] == 0) {
                _selectedSubItemIndex = -1;
            } else {
                NSInteger fallback = itemIdx;
                if (fallback >= (NSInteger)[updatedItems count]) fallback = (NSInteger)[updatedItems count] - 1;
                _selectedSubItemIndex = fallback;
            }
        } else if (_selectedSubItemIndex > itemIdx) {
            _selectedSubItemIndex--;
        }
    }

    [self normalizeSelection];
    [self saveData];
    [_tableView reloadData];
    [self showStatus:@"Subscription config deleted" ok:YES];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCellId = @"VCItemCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellId] autorelease];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0f];
        cell.detailTextLabel.textColor = [UIColor grayColor];
    }
    cell.indentationLevel = 0;
    cell.indentationWidth = 14.0f;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;

    if (indexPath.section == 0) {
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        NSString *uri = [cfg objectForKey:@"uri"];
        cell.textLabel.text = ([name length] > 0) ? name : [NSString stringWithFormat:@"Config %ld", (long)(indexPath.row + 1)];
        cell.detailTextLabel.text = [self hostFromVLESSURI:uri];
        cell.accessoryView = [self accessoryPingWithTag:(10000 + indexPath.row) selected:(_selectedConfigIndex == indexPath.row)];
    } else {
        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if ([self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
            NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
            NSString *name = [sub objectForKey:@"name"];
            NSString *url = [sub objectForKey:@"url"];
            NSArray *items = [self subscriptionItemsAtIndex:subIdx];
            NSUInteger cnt = [items count];

            if (isHeader) {
                cell.textLabel.text = ([name length] > 0) ? name : [self hostFromURLString:url];
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu configs • %@", (unsigned long)cnt, url ? url : @""];
                cell.accessoryView = [self accessoryChevronExpanded:(_expandedSubscription == subIdx)];
            } else {
                NSString *uri = [items objectAtIndex:itemIdx];
                cell.indentationLevel = 0;
                cell.textLabel.text = [self displayNameForURI:uri index:itemIdx];
                cell.detailTextLabel.text = [self hostFromVLESSURI:uri];
                NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
                BOOL selected = (_selectedSubIndex == subIdx && _selectedSubItemIndex == itemIdx);
                cell.accessoryView = [self accessoryPingWithTag:tag selected:selected];
            }
        } else {
            cell.textLabel.text = @"(invalid row)";
            cell.detailTextLabel.text = @"";
        }
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    BOOL animateSubscriptionsSection = NO;
    NSString *oldURI = nil;
    if (_connected) {
        NSString *u = [self uriForCurrentSelection];
        if ([u isKindOfClass:[NSString class]] && [u length] > 0) {
            oldURI = [u copy];
        }
    }

    if (indexPath.section == 0) {
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        _selectedConfigIndex = indexPath.row;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        [self showStatus:[NSString stringWithFormat:@"Selected config: %@", name ? name : @"(unnamed)"] ok:YES];
    } else {
        NSInteger subIdx = -1;
        NSInteger itemIdx = -1;
        BOOL isHeader = YES;
        if ([self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
            if (isHeader) {
                animateSubscriptionsSection = YES;
                if (_expandedSubscription == subIdx) {
                    _expandedSubscription = -1;
                } else {
                    _expandedSubscription = subIdx;
                    if ([[self subscriptionItemsAtIndex:subIdx] count] == 0) {
                        [self refreshSubscriptionAtIndex:subIdx showStatus:NO];
                    }
                }
                NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
                NSString *name = [sub objectForKey:@"name"];
                [self showStatus:[NSString stringWithFormat:@"Subscription: %@", name ? name : @"(unnamed)"] ok:YES];
            } else {
                NSArray *items = [self subscriptionItemsAtIndex:subIdx];
                NSString *uri = (itemIdx >= 0 && itemIdx < (NSInteger)[items count]) ? [items objectAtIndex:itemIdx] : @"";
                _selectedConfigIndex = -1;
                _selectedSubIndex = subIdx;
                _selectedSubItemIndex = itemIdx;
                [self showStatus:[NSString stringWithFormat:@"Selected: %@", [self displayNameForURI:uri index:itemIdx]] ok:YES];
            }
        }
    }

    [self normalizeSelection];
    if (_connected && oldURI) {
        NSString *newURI = [self uriForCurrentSelection];
        [self reconnectToURIIfNeededFrom:oldURI to:newURI];
    }

    if (animateSubscriptionsSection) {
        [UIView transitionWithView:_tableView
                          duration:0.18
                           options:UIViewAnimationOptionTransitionCrossDissolve
                        animations:^{
                            [_tableView reloadData];
                        }
                        completion:nil];
    } else {
        [_tableView reloadData];
    }
    [oldURI release];
    [_tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Import UI

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (actionSheet.tag == VCActionSheetTagImport) {
        if (buttonIndex == 0) {
            NSString *clip = [[UIPasteboard generalPasteboard] string];
            [self importTextEntry:clip];
        } else if (buttonIndex == 1) {
            UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Manual Import"
                                                          message:@"Paste vless:// or subscription URL"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                                otherButtonTitles:@"Import", nil] autorelease];
            av.alertViewStyle = UIAlertViewStylePlainTextInput;
            av.tag = VCAlertTagImportManual;

            UITextField *tf = [av textFieldAtIndex:0];
            tf.placeholder = @"vless://... or https://...";
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.keyboardType = UIKeyboardTypeURL;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;

            [av show];
        }
        return;
    }

    if (actionSheet.tag == VCActionSheetTagSettings) {
        if (buttonIndex == 0) {
            _autoUpdateSubscriptions = !_autoUpdateSubscriptions;
            [self saveData];
            [self showStatus:_autoUpdateSubscriptions ? @"Auto-update subscriptions: ON"
                                                   : @"Auto-update subscriptions: OFF"
                         ok:YES];
        } else if (buttonIndex == 1) {
            [self showAbout];
        }
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex != 1) return;
    if (alertView.tag == VCAlertTagImportManual) {
        NSString *txt = [[alertView textFieldAtIndex:0] text];
        [self importTextEntry:txt];
    }
}

@end

@interface AppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
}
@property (nonatomic, retain) UIWindow *window;
@end

@implementation AppDelegate
@synthesize window = _window;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;

    ClearLogsViaDaemon();
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    MainVC *vc = [[[MainVC alloc] init] autorelease];
    _window.rootViewController = vc;
    [_window makeKeyAndVisible];
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    ClearLogsViaDaemon();
}

- (void)dealloc {
    [_window release];
    [super dealloc];
}

@end

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int rc = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return rc;
}
