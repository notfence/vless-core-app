#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include "quirc.h"

#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/select.h>
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
#include <spawn.h>

extern char **environ;

static NSString *const kDefaultsConfigsKey = @"vlesscore.configs";
static NSString *const kDefaultsSubsKey = @"vlesscore.subscriptions";
static NSString *const kDefaultsAutoUpdateSubsKey = @"vlesscore.auto_update_subs";
static NSString *const kDefaultsStealthModeKey = @"vlesscore.stealth_mode";
static NSString *const kDefaultsDarkThemeKey = @"vlesscore.dark_theme";
static NSString *const kDefaultsSubHWIDKey = @"vlesscore.subscription_hwid";
static NSString *const kSubscriptionAllowInsecureFetchKey = @"allow_insecure_fetch";
static const char *kDaemonPortPath = "/var/run/vpnctld.port";
static const int kDaemonDefaultPort = 9093;
static const int kDaemonPortMax = 9113;

static BOOL VCAppearanceIsDark(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsDarkThemeKey];
}

static void VCAppearanceSetDark(BOOL dark) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:dark forKey:kDefaultsDarkThemeKey];
    [ud synchronize];
}

static UIColor *VCBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.065f alpha:1.0f]
                                : [UIColor colorWithWhite:0.97f alpha:1.0f];
}

static UIColor *VCCellBackgroundColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.13f alpha:1.0f]
                                : [UIColor whiteColor];
}

static UIColor *VCPrimaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.92f alpha:1.0f]
                                : [UIColor colorWithWhite:0.08f alpha:1.0f];
}

static UIColor *VCSecondaryTextColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.67f alpha:1.0f]
                                : [UIColor colorWithWhite:0.42f alpha:1.0f];
}

static UIColor *VCSeparatorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                : [UIColor colorWithWhite:0.78f alpha:1.0f];
}

static UIColor *VCSelectedCellColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.12f green:0.24f blue:0.38f alpha:1.0f]
                                : [UIColor colorWithRed:0.82f green:0.89f blue:0.98f alpha:1.0f];
}

static UIColor *VCAccentColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.28f green:0.62f blue:1.0f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.44f blue:0.86f alpha:1.0f];
}

static UIColor *VCSuccessColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:0.32f green:0.82f blue:0.42f alpha:1.0f]
                                : [UIColor colorWithRed:0.10f green:0.50f blue:0.15f alpha:1.0f];
}

static UIColor *VCErrorColor(void) {
    return VCAppearanceIsDark() ? [UIColor colorWithRed:1.0f green:0.38f blue:0.38f alpha:1.0f]
                                : [UIColor colorWithRed:0.78f green:0.12f blue:0.12f alpha:1.0f];
}

static BOOL IsPadDevice(void) {
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        return YES;
    }

    NSString *model = [[UIDevice currentDevice] model];
    if (model && [model rangeOfString:@"iPad" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        return YES;
    }

    return NO;
}

static UIInterfaceOrientation CurrentInterfaceOrientation(void) {
    UIInterfaceOrientation o = [[UIApplication sharedApplication] statusBarOrientation];
    if (o == UIInterfaceOrientationLandscapeLeft ||
        o == UIInterfaceOrientationLandscapeRight ||
        o == UIInterfaceOrientationPortraitUpsideDown ||
        o == UIInterfaceOrientationPortrait) {
        return o;
    }
    return UIInterfaceOrientationPortrait;
}

typedef NS_ENUM(NSInteger, VCAlertTag) {
    VCAlertTagImportManual = 1001,
    VCAlertTagImportInsecureSubscription = 1002,
};

typedef NS_ENUM(NSInteger, VCActionSheetTag) {
    VCActionSheetTagImport = 2001,
    VCActionSheetTagImportFileBrowser = 2002,
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

static NSInteger const kVCSettingsTitleMarqueeTag = 7400;
static NSInteger const kVCSettingsDetailMarqueeTag = 7401;
static NSInteger const kVCMainDetailContainerTag = 7410;
static NSInteger const kVCMainDetailPrefixTag = 7411;
static NSInteger const kVCMainDetailTailTag = 7412;
static NSInteger const kVCMainSectionHeaderButtonTagBase = 7420;
static NSInteger const kVCMainSectionHeaderCountTagBase = 7430;
static NSInteger const kVCMainSectionHeaderChevronTagBase = 7440;
static CGFloat const kVCMainSectionHeaderHeight = 46.0f;
static CGFloat const kVCDetailMarqueeGap = 4.0f;
static NSTimeInterval const kVCMarqueePauseSeconds = 1.0;
static CGFloat const kVCMarqueePixelsPerSecond = 28.0f;
static NSString *const kVCQRMetadataType = @"org.iso.QRCode";

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
    return (rc == 0) ? 0 : -1;
}

static int ReadDaemonPort(void) {
    FILE *fp = fopen(kDaemonPortPath, "r");
    if (!fp) return kDaemonDefaultPort;

    int port = 0;
    if (fscanf(fp, "%d", &port) != 1 || port <= 0 || port > 65535) {
        port = kDaemonDefaultPort;
    }
    fclose(fp);
    return port;
}

static int BuildDaemonPortList(int *ports, int cap) {
    if (!ports || cap <= 0) return 0;

    int count = 0;
    int preferred = ReadDaemonPort();
    if (preferred > 0 && preferred <= 65535) {
        ports[count++] = preferred;
    }

    for (int p = kDaemonDefaultPort; p <= kDaemonPortMax && count < cap; p++) {
        if (p == preferred) continue;
        ports[count++] = p;
    }
    return count;
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

static int OpenDaemonSocketForPort(int port, const struct timeval *rw_tv, int connect_timeout_ms, int *fd_out, int *last_errno_out) {
    if (port <= 0 || port > 65535) {
        if (last_errno_out) *last_errno_out = EINVAL;
        return -1;
    }

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (last_errno_out) *last_errno_out = errno;
        return -1;
    }

    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, rw_tv, sizeof(*rw_tv));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, rw_tv, sizeof(*rw_tv));

    struct sockaddr_in sa;
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    sa.sin_port = htons((uint16_t)port);

    if (ConnectWithTimeout(fd, (struct sockaddr *)&sa, (socklen_t)sizeof(sa), connect_timeout_ms) == 0) {
        *fd_out = fd;
        if (last_errno_out) *last_errno_out = 0;
        return 0;
    }

    if (last_errno_out) *last_errno_out = errno;
    close(fd);
    return -1;
}

static int ProbeDaemonPort(int port, int connect_timeout_ms, int io_timeout_ms, int *last_errno_out) {
    struct timeval tv;
    tv.tv_sec = io_timeout_ms / 1000;
    tv.tv_usec = (io_timeout_ms % 1000) * 1000;

    int fd = -1;
    int last_errno = 0;
    if (OpenDaemonSocketForPort(port, &tv, connect_timeout_ms, &fd, &last_errno) != 0 || fd < 0) {
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    const char probe[] = "STATUS\n";
    ssize_t wr = write(fd, probe, (size_t)(sizeof(probe) - 1));
    if (wr < 0) {
        last_errno = errno;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    char buf[64];
    ssize_t rd = read(fd, buf, sizeof(buf) - 1);
    if (rd <= 0) {
        last_errno = (rd < 0) ? errno : ECONNRESET;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    buf[rd] = '\0';
    close(fd);
    if (strncmp(buf, "OK ", 3) == 0) {
        if (last_errno_out) *last_errno_out = 0;
        return 0;
    }

    if (last_errno_out) *last_errno_out = EPROTO;
    return -1;
}

static int FindResponsiveDaemonPort(int connect_timeout_ms, int io_timeout_ms, int *port_out, int *last_errno_out) {
    int ports[64];
    int port_count = BuildDaemonPortList(ports, (int)(sizeof(ports) / sizeof(ports[0])));
    if (port_count <= 0) {
        if (last_errno_out) *last_errno_out = EINVAL;
        return -1;
    }

    int last_errno = ETIMEDOUT;
    for (int i = 0; i < port_count; i++) {
        if (ProbeDaemonPort(ports[i], connect_timeout_ms, io_timeout_ms, &last_errno) == 0) {
            *port_out = ports[i];
            if (last_errno_out) *last_errno_out = 0;
            return 0;
        }
    }

    if (last_errno_out) *last_errno_out = last_errno;
    return -1;
}

static ssize_t SendRawCommandToPort(int port, NSData *outData, const struct timeval *rw_tv, int connect_timeout_ms, char *buf, size_t buf_cap, int *last_errno_out) {
    int fd = -1;
    int last_errno = 0;
    if (OpenDaemonSocketForPort(port, rw_tv, connect_timeout_ms, &fd, &last_errno) != 0 || fd < 0) {
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    ssize_t wr = write(fd, [outData bytes], [outData length]);
    if (wr < 0) {
        last_errno = errno;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    ssize_t rd = read(fd, buf, buf_cap - 1);
    if (rd <= 0) {
        last_errno = (rd < 0) ? errno : ECONNRESET;
        close(fd);
        if (last_errno_out) *last_errno_out = last_errno;
        return -1;
    }

    buf[rd] = '\0';
    close(fd);
    if (last_errno_out) *last_errno_out = 0;
    return rd;
}

static NSString *SendCommand(NSString *cmdLine) {
    BOOL isConnectCommand = [cmdLine hasPrefix:@"CONNECT\t"];

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

        int port = -1;
        int ready_attempts = (phase == 1) ? 10 : 1;
        for (int attempt = 0; attempt < ready_attempts; attempt++) {
            if (FindResponsiveDaemonPort(250, 300, &port, &last_errno) == 0 && port > 0) {
                break;
            }
            if (attempt + 1 < ready_attempts) {
                usleep(120 * 1000);
            }
        }

        if (port <= 0) {
            continue;
        }

        char buf[65536];
        ssize_t rd = SendRawCommandToPort(port, outData, &cmd_tv, 500, buf, sizeof(buf), &last_errno);
        if (rd > 0) {
            return [NSString stringWithUTF8String:buf];
        }

        last_io_error = (last_errno == EPIPE || last_errno == ECONNRESET) ?
            @"no response from daemon" :
            [NSString stringWithFormat:@"write/read failed: %s", strerror(last_errno)];
    }

    if (last_io_error) {
        return last_io_error;
    }
    if (last_errno == 0) {
        last_errno = ECONNREFUSED;
    }
    return [NSString stringWithFormat:@"daemon offline (%s)", strerror(last_errno)];
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
    const char *core = "/usr/bin/vless-core-darwin-armv7";
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
        execl(core, "vless-core-darwin-armv7", "--uri", uri, "--listen-port", port_str, (char *)NULL);
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
    NSString *v = RunCommandFirstLine("/usr/bin/vless-core-darwin-armv7 -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine("vless-core-darwin-armv7 -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"unknown";
    }
    return v;
}

static NSString *VersionTokenAfterPrefix(NSString *line, NSString *prefix) {
    if (!line || !prefix) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part hasPrefix:prefix] && [part length] > [prefix length]) {
            return [part substringFromIndex:[prefix length]];
        }
    }
    return @"unknown";
}

static NSString *CurlVersionFromVersionLine(NSString *line) {
    if (!line) return @"unknown";

    NSArray *parts = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *tokens = [NSMutableArray array];
    for (NSUInteger i = 0; i < [parts count]; i++) {
        NSString *part = [parts objectAtIndex:i];
        if ([part length] > 0) {
            [tokens addObject:part];
        }
    }

    if ([tokens count] >= 2 && [[tokens objectAtIndex:0] isEqualToString:@"curl"]) {
        return [tokens objectAtIndex:1];
    }
    return VersionTokenAfterPrefix(line, @"libcurl/");
}

static NSDictionary *DetectCurlDependencyVersions(void) {
    NSString *line = RunCommandFirstLine("/usr/bin/vless-core-curl --version 2>/dev/null");
    if (!line || [line length] == 0) {
        line = RunCommandFirstLine("vless-core-curl --version 2>/dev/null");
    }

    NSString *curlVersion = CurlVersionFromVersionLine(line);
    NSString *opensslVersion = VersionTokenAfterPrefix(line, @"OpenSSL/");
    NSString *zlibVersion = VersionTokenAfterPrefix(line, @"zlib/");

    return [NSDictionary dictionaryWithObjectsAndKeys:
            curlVersion, @"curl",
            opensslVersion, @"openssl",
            zlibVersion, @"zlib",
            nil];
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

static NSString *NormalizeOpenSSLPatchStatus(NSString *status) {
    NSString *trimmed = TrimSimpleString(status);
    if ([trimmed isEqualToString:@"patched"]) return @"patched";
    if ([trimmed isEqualToString:@"unpatched"]) return @"unpatched";
    return @"unpatched";
}

static NSString *DetectOpenSSLPatchStatus(void) {
    NSString *status = ReadTextFileBestEffort(@"/usr/share/vless-core/openssl-patch-status");
    if (!status || [status length] == 0) {
        status = RunCommandFirstLine("/usr/bin/vless-core-darwin-armv7 --openssl-patch-status 2>/dev/null");
    }
    return NormalizeOpenSSLPatchStatus(status);
}

static NSString *DetectRedsocksVersion(void) {
    NSString *v = RunCommandFirstLine("/usr/bin/redsocks-vless-core -v 2>/dev/null");
    if (!v || [v length] == 0) {
        v = RunCommandFirstLine("redsocks-vless-core -v 2>/dev/null");
    }
    if (!v || [v length] == 0) {
        v = @"bundled helper";
    }
    return v;
}

static NSString *AppDisplayName(void) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    NSString *name = [info objectForKey:@"CFBundleDisplayName"];
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = [info objectForKey:@"CFBundleName"];
    }
    if (![name isKindOfClass:[NSString class]] || [name length] == 0) {
        name = @"vless-core";
    }
    return name;
}

static NSString *AppShortVersion(void) {
    NSString *ver = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    if (![ver isKindOfClass:[NSString class]] || [ver length] == 0) {
        ver = @"0.0.0";
    }
    return ver;
}

static NSString *AppBuildVersion(void) {
    NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
    if (![build isKindOfClass:[NSString class]] || [build length] == 0) {
        build = @"0";
    }
    return build;
}

static NSString *AppVersionSummary(void) {
    return [NSString stringWithFormat:@"Version %@ (%@)", AppShortVersion(), AppBuildVersion()];
}

static NSString *AppInfoString(NSString *key, NSString *fallback) {
    NSString *value = [[[NSBundle mainBundle] infoDictionary] objectForKey:key];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) {
        return fallback;
    }
    return value;
}

static NSString *AppDebBuildDate(void) {
    return AppInfoString(@"VCBuildDate", @"unknown");
}

static NSString *AppGitShortCommit(void) {
    return AppInfoString(@"VCGitCommit", @"unknown");
}

static NSString *AppBuildMetadataSummary(void) {
    return [NSString stringWithFormat:@"Built at: %@\nGitSHA: %@", AppDebBuildDate(), AppGitShortCommit()];
}

static NSString *SubscriptionHWID(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *hwid = [ud objectForKey:kDefaultsSubHWIDKey];
    if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
        return hwid;
    }

    NSString *generated = nil;
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    if (uuid) {
        CFStringRef cf = CFUUIDCreateString(kCFAllocatorDefault, uuid);
        if (cf) {
            generated = [NSString stringWithString:(NSString *)cf];
            CFRelease(cf);
        }
        CFRelease(uuid);
    }

    if (![generated isKindOfClass:[NSString class]] || [generated length] == 0) {
        generated = [NSString stringWithFormat:@"%u-%u-%u",
                     (unsigned)arc4random(),
                     (unsigned)arc4random(),
                     (unsigned)getpid()];
    }

    [ud setObject:generated forKey:kDefaultsSubHWIDKey];
    [ud synchronize];
    return generated;
}

static void CleanupSubscriptionFetchTempFiles(const char *out_path, const char *err_path, const char *hdr_path) {
    if (out_path && *out_path) unlink(out_path);
    if (err_path && *err_path) unlink(err_path);
    if (hdr_path && *hdr_path) unlink(hdr_path);
}

static BOOL SubscriptionDictionaryAllowsInsecureFetch(NSDictionary *sub) {
    if (![sub isKindOfClass:[NSDictionary class]]) return NO;

    id value = [sub objectForKey:kSubscriptionAllowInsecureFetchKey];
    if ([value respondsToSelector:@selector(boolValue)]) {
        return [value boolValue] ? YES : NO;
    }
    return NO;
}

static BOOL CurlExitCodeCanRetryInsecurely(int exitCode) {
    return exitCode == 60; /* CURLE_PEER_FAILED_VERIFICATION */
}

static BOOL NSURLErrorCanRetryInsecurely(NSError *err) {
    if (![err isKindOfClass:[NSError class]]) return NO;
    if (![[err domain] isEqualToString:NSURLErrorDomain]) return NO;

    NSInteger code = [err code];
    return code == NSURLErrorSecureConnectionFailed ||
           code == NSURLErrorServerCertificateHasBadDate ||
           code == NSURLErrorServerCertificateUntrusted ||
           code == NSURLErrorServerCertificateHasUnknownRoot ||
           code == NSURLErrorServerCertificateNotYetValid;
}

static BOOL SubscriptionDataLooksLikeHTML(NSData *data) {
    if (!data || [data length] == 0) return NO;

    NSUInteger len = [data length];
    if (len > 4096) len = 4096;
    NSData *prefix = [NSData dataWithBytes:[data bytes] length:len];
    NSString *text = [[[NSString alloc] initWithData:prefix encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:prefix encoding:NSISOLatin1StringEncoding] autorelease];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return NO;

    NSString *trim = TrimSimpleString(text);
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"<!doctype html"] ||
           [lower hasPrefix:@"<html"] ||
           [lower rangeOfString:@"<body"].location != NSNotFound;
}

static NSData *FetchURLViaVlessCoreCurl(NSString *urlString, BOOL allowInsecureFetch, NSString **errOut, NSString **headersOut, int *exitCodeOut) {
    const char *curl_path = "/usr/bin/vless-core-curl";
    const char *ca_bundle_path = "/usr/share/vless-core/cacert.pem";

    if (errOut) *errOut = nil;
    if (headersOut) *headersOut = nil;
    if (exitCodeOut) *exitCodeOut = -1;

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

    NSString *hwid = TrimSimpleString(SubscriptionHWID());
    char hwid_header[256];
    memset(hwid_header, 0, sizeof(hwid_header));
    const char *hwid_c = [hwid UTF8String];
    if (hwid_c && *hwid_c) {
        snprintf(hwid_header, sizeof(hwid_header), "X-HWID: %s", hwid_c);
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
        CleanupSubscriptionFetchTempFiles(out_tmpl, NULL, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(err) failed: %s", strerror(errno)];
        return nil;
    }

    char hdr_tmpl[] = "/tmp/vlesscore-sub-hdr-XXXXXX";
    int hdr_fd = mkstemp(hdr_tmpl);
    if (hdr_fd < 0) {
        close(out_fd);
        close(err_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, NULL);
        if (errOut) *errOut = [NSString stringWithFormat:@"mkstemp(hdr) failed: %s", strerror(errno)];
        return nil;
    }
    close(hdr_fd);

    pid_t pid = fork();
    if (pid < 0) {
        close(out_fd);
        close(err_fd);
        CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
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

        char *argv[32];
        int argc = 0;
        argv[argc++] = (char *)"vless-core-curl";
        argv[argc++] = (char *)"--fail";
        argv[argc++] = (char *)"--location";
        argv[argc++] = (char *)"--silent";
        argv[argc++] = (char *)"--show-error";
        argv[argc++] = (char *)"--connect-timeout";
        argv[argc++] = (char *)"10";
        argv[argc++] = (char *)"--max-time";
        argv[argc++] = (char *)"25";
        argv[argc++] = (char *)"--proto";
        argv[argc++] = (char *)"=https,http";
        argv[argc++] = (char *)"--curves";
        argv[argc++] = (char *)"X25519:P-256:P-384";
        argv[argc++] = (char *)"-D";
        argv[argc++] = hdr_tmpl;

        if (allowInsecureFetch) {
            argv[argc++] = (char *)"--insecure";
        }

        if (hwid_header[0] != '\0') {
            argv[argc++] = (char *)"-H";
            argv[argc++] = hwid_header;
        }

        if (!allowInsecureFetch && access(ca_bundle_path, R_OK) == 0) {
            argv[argc++] = (char *)"--cacert";
            argv[argc++] = (char *)ca_bundle_path;
        }

        argv[argc++] = (char *)url_c;
        argv[argc] = NULL;

        execv(curl_path, argv);
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
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = [NSString stringWithFormat:@"waitpid failed: %s", strerror(errno)];
            return nil;
        }

        if (waited_ms >= timeout_ms) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);
            if (errOut) *errOut = @"vless-core-curl timed out";
            return nil;
        }

        usleep(100 * 1000);
        waited_ms += 100;
    }

    NSString *out_path = [NSString stringWithUTF8String:out_tmpl];
    NSString *err_path = [NSString stringWithUTF8String:err_tmpl];
    NSString *hdr_path = [NSString stringWithUTF8String:hdr_tmpl];
    NSData *body = [NSData dataWithContentsOfFile:out_path];
    NSString *curl_err = TrimSimpleString(ReadTextFileBestEffort(err_path));
    NSString *curl_hdr = ReadTextFileBestEffort(hdr_path);
    if ([curl_err length] > 220) {
        curl_err = [curl_err substringToIndex:220];
    }

    CleanupSubscriptionFetchTempFiles(out_tmpl, err_tmpl, hdr_tmpl);

    if (headersOut) {
        *headersOut = curl_hdr;
    }

    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        if (exitCodeOut && WIFEXITED(status)) {
            *exitCodeOut = WEXITSTATUS(status);
        }
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

static NSString *ClearLogsViaDaemon(void) {
    return SendCommand(@"CLEAR_LOGS\n");
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

static NSString *ReadLogAtIndex(NSInteger index) {
    NSString *path = (index == 1) ? @"/var/log/vless-core.log" : @"/var/log/vpnctld.log";
    return ReadFileTail(path, 8192);
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

static UIImage *TintImageWithColor(UIImage *image, UIColor *color) {
    if (!image || !color) return image;

    CGSize size = image.size;
    UIGraphicsBeginImageContextWithOptions(size, NO, image.scale);
    CGRect rect = CGRectMake(0.0f, 0.0f, size.width, size.height);
    [color setFill];
    UIRectFill(rect);
    [image drawInRect:rect blendMode:kCGBlendModeDestinationIn alpha:1.0f];
    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return tinted;
}

static UIImage *LoadBundledIconTinted(NSString *baseName, CGFloat size, UIColor *color) {
    UIImage *image = LoadBundledIconScaled(baseName, size);
    return image ? TintImageWithColor(image, color) : nil;
}

static void VCAppearanceApplyHeaderView(UIView *view);

static void VCAppearanceApplyTable(UITableView *tableView) {
    if (!tableView) return;

    tableView.backgroundColor = VCBackgroundColor();
    tableView.separatorColor = VCSeparatorColor();
    tableView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                     : UIScrollViewIndicatorStyleDefault;
    UIView *background = [[[UIView alloc] initWithFrame:tableView.bounds] autorelease];
    background.backgroundColor = VCBackgroundColor();
    tableView.backgroundView = background;
}

static void VCAppearanceApplyCell(UITableViewCell *cell) {
    if (!cell) return;

    cell.backgroundColor = VCCellBackgroundColor();
    cell.contentView.backgroundColor = [UIColor clearColor];
    cell.textLabel.backgroundColor = [UIColor clearColor];
    cell.detailTextLabel.backgroundColor = [UIColor clearColor];
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    cell.textLabel.highlightedTextColor = VCPrimaryTextColor();
    cell.detailTextLabel.highlightedTextColor = VCSecondaryTextColor();

    UIView *selected = [[[UIView alloc] initWithFrame:cell.bounds] autorelease];
    selected.backgroundColor = VCSelectedCellColor();
    cell.selectedBackgroundView = selected;
}

static void VCAppearanceApplyHeaderView(UIView *view) {
    if (!view) return;
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        label.textColor = VCSecondaryTextColor();
        if (VCAppearanceIsDark()) {
            label.shadowColor = [UIColor clearColor];
            label.shadowOffset = CGSizeZero;
        } else {
            label.shadowColor = [UIColor colorWithWhite:1.0f alpha:0.85f];
            label.shadowOffset = CGSizeMake(0.0f, 1.0f);
        }
    }
    for (UIView *subview in view.subviews) {
        VCAppearanceApplyHeaderView(subview);
    }
}

static void VCAppearanceRefreshVisibleTableHeaders(UITableView *tableView) {
    if (!tableView) return;

    [tableView setNeedsLayout];
    [tableView layoutIfNeeded];
    NSInteger sections = [tableView numberOfSections];
    for (NSInteger section = 0; section < sections; section++) {
        UIView *header = [tableView headerViewForSection:section];
        if (header) {
            VCAppearanceApplyHeaderView(header);
            [header setNeedsDisplay];
        }
    }
}

static void VCAppearanceScheduleVisibleTableHeadersRefresh(UITableView *tableView) {
    if (!tableView) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        VCAppearanceRefreshVisibleTableHeaders(tableView);
    });
}

static void VCAppearanceApplyNavigationBar(UINavigationBar *navigationBar) {
    if (!navigationBar) return;

    BOOL dark = VCAppearanceIsDark();
    BOOL modernTintBehavior = ([[[UIDevice currentDevice] systemVersion] integerValue] >= 7);
    navigationBar.barStyle = dark ? UIBarStyleBlack : UIBarStyleDefault;
    navigationBar.tintColor = dark
        ? (modernTintBehavior ? VCAccentColor() : [UIColor colorWithWhite:0.18f alpha:1.0f])
        : nil;
    if (dark) {
        NSDictionary *titleAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
            VCPrimaryTextColor(), UITextAttributeTextColor,
            [UIColor clearColor], UITextAttributeTextShadowColor,
            [NSValue valueWithUIOffset:UIOffsetZero], UITextAttributeTextShadowOffset,
            nil];
        [navigationBar setTitleTextAttributes:titleAttributes];
    } else {
        [navigationBar setTitleTextAttributes:nil];
    }

    UINavigationItem *topItem = navigationBar.topItem;
    NSString *title = [topItem.title copy];
    if (title) {
        topItem.title = nil;
        topItem.title = title;
        [title release];
    }
    [navigationBar setNeedsLayout];
    [navigationBar layoutIfNeeded];
}

static void VCAppearanceApplyStatusBar(void) {
    BOOL modernStatusBar = ([[[UIDevice currentDevice] systemVersion] integerValue] >= 7);
    UIStatusBarStyle style = UIStatusBarStyleDefault;
    if (VCAppearanceIsDark()) {
        style = modernStatusBar ? UIStatusBarStyleBlackTranslucent : UIStatusBarStyleBlackOpaque;
    }
    [[UIApplication sharedApplication] setStatusBarStyle:style animated:YES];
}

static UIImage *MakeIconImage(VCIconType type, CGFloat size, BOOL active) {
    CGSize iconSize = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(iconSize, NO, 0.0f);

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    UIColor *clr = active ? VCAccentColor() : VCPrimaryTextColor();
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
        UIColor *ok = VCSuccessColor();
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

@interface VCMarqueeLabel : UIView {
    UILabel *_label;
    NSString *_text;
    NSTimer *_startTimer;
    NSTimer *_endPauseTimer;
    CGFloat _overflowWidth;
    CGSize _lastBoundsSize;
    BOOL _needsRefresh;
}
@property (nonatomic, copy) NSString *text;
@property (nonatomic, retain) UIFont *font;
@property (nonatomic, retain) UIColor *textColor;
- (void)stopMarquee;
- (void)restartMarquee;
@end

@implementation VCMarqueeLabel
@synthesize text = _text;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;

    self.clipsToBounds = YES;
    self.backgroundColor = [UIColor clearColor];

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.backgroundColor = [UIColor clearColor];
    _label.textColor = [UIColor grayColor];
    _label.font = [UIFont systemFontOfSize:11.0f];
    _label.numberOfLines = 1;
    _label.lineBreakMode = NSLineBreakByClipping;
    [self addSubview:_label];

    _overflowWidth = 0.0f;
    _lastBoundsSize = CGSizeZero;
    _needsRefresh = YES;
    return self;
}

- (void)dealloc {
    [self stopMarquee];
    [_text release];
    [_label release];
    [super dealloc];
}

- (void)invalidateTimer:(NSTimer **)timerPtr {
    if (!timerPtr) return;
    NSTimer *timer = *timerPtr;
    if (timer) {
        [timer invalidate];
        [timer release];
        *timerPtr = nil;
    }
}

- (void)scheduleTimer:(NSTimer **)timerPtr selector:(SEL)selector after:(NSTimeInterval)seconds {
    [self invalidateTimer:timerPtr];
    NSTimer *timer = [NSTimer timerWithTimeInterval:seconds
                                             target:self
                                           selector:selector
                                           userInfo:nil
                                            repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    *timerPtr = [timer retain];
}

- (CGFloat)textWidthForCurrentText {
    if (![_text isKindOfClass:[NSString class]] || [_text length] == 0) return 0.0f;
    UIFont *font = (_label.font ? _label.font : [UIFont systemFontOfSize:11.0f]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize sz = [_text sizeWithFont:font];
#pragma clang diagnostic pop
    return ceilf(sz.width);
}

- (void)resetToStartAndPause {
    [self invalidateTimer:&_endPauseTimer];
    if (_overflowWidth <= 0.5f || !self.window) return;
    CGRect f = _label.frame;
    f.origin.x = 0.0f;
    _label.frame = f;
    [self scheduleTimer:&_startTimer selector:@selector(startScrollStep) after:kVCMarqueePauseSeconds];
}

- (void)startScrollStep {
    [self invalidateTimer:&_startTimer];
    if (_overflowWidth <= 0.5f || !self.window) return;

    CGFloat duration = _overflowWidth / kVCMarqueePixelsPerSecond;
    if (duration < 0.35f) duration = 0.35f;

    [UIView animateWithDuration:duration
                          delay:0.0
                        options:UIViewAnimationOptionCurveLinear | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         CGRect f = _label.frame;
                         f.origin.x = -_overflowWidth;
                         _label.frame = f;
                     }
                     completion:^(BOOL finished) {
                         if (!finished) return;
                         [self scheduleTimer:&_endPauseTimer
                                     selector:@selector(resetToStartAndPause)
                                        after:kVCMarqueePauseSeconds];
                     }];
}

- (void)refreshMarqueeIfNeeded:(BOOL)force {
    CGSize b = self.bounds.size;
    if (!force && !_needsRefresh && fabsf((float)(b.width - _lastBoundsSize.width)) < 0.5f &&
        fabsf((float)(b.height - _lastBoundsSize.height)) < 0.5f) {
        return;
    }

    _lastBoundsSize = b;
    _needsRefresh = NO;
    [self stopMarquee];
    _label.text = (_text ? _text : @"");

    CGFloat viewW = b.width;
    CGFloat viewH = b.height;
    if (viewW < 1.0f || viewH < 1.0f) {
        _label.frame = CGRectMake(0, 0, 0, 0);
        return;
    }

    CGFloat textW = [self textWidthForCurrentText];
    if (textW < 1.0f) textW = viewW;

    _overflowWidth = textW - viewW;
    if (_overflowWidth <= 0.5f) {
        _overflowWidth = 0.0f;
        _label.frame = CGRectMake(0, 0, viewW, viewH);
        return;
    }

    _label.frame = CGRectMake(0, 0, textW, viewH);
    [self scheduleTimer:&_startTimer selector:@selector(startScrollStep) after:kVCMarqueePauseSeconds];
}

- (void)setText:(NSString *)text {
    if (_text == text || [_text isEqualToString:text]) {
        _needsRefresh = YES;
        [self refreshMarqueeIfNeeded:YES];
        return;
    }
    [_text release];
    _text = [text copy];
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

- (UIFont *)font {
    return _label.font;
}

- (void)setFont:(UIFont *)font {
    if ((_label.font == font) || [_label.font isEqual:font]) return;
    _label.font = font;
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

- (UIColor *)textColor {
    return _label.textColor;
}

- (void)setTextColor:(UIColor *)textColor {
    if ((_label.textColor == textColor) || [_label.textColor isEqual:textColor]) return;
    _label.textColor = textColor;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self refreshMarqueeIfNeeded:NO];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        _needsRefresh = YES;
        [self refreshMarqueeIfNeeded:YES];
    } else {
        [self stopMarquee];
    }
}

- (void)stopMarquee {
    [self invalidateTimer:&_startTimer];
    [self invalidateTimer:&_endPauseTimer];
    [_label.layer removeAllAnimations];
}

- (void)restartMarquee {
    _needsRefresh = YES;
    [self refreshMarqueeIfNeeded:YES];
}

@end

@class SettingsVC;
@protocol SettingsVCDelegate <NSObject>
- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled;
- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled;
@end

@interface SettingsVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    UISwitch *_autoUpdateSwitch;
    UISwitch *_stealthSwitch;
    BOOL _autoUpdate;
    BOOL _stealthMode;
    BOOL _darkTheme;
    id<SettingsVCDelegate> _delegate;
}
@property (nonatomic, assign) BOOL autoUpdate;
@property (nonatomic, assign) BOOL stealthMode;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, assign) id<SettingsVCDelegate> delegate;
@end

@interface SettingsNavController : UINavigationController
@end

@interface FAQVC : UIViewController {
    UITextView *_textView;
}
@end

@implementation FAQVC

- (void)dealloc {
    [_textView release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FAQ";
    self.view.backgroundColor = VCBackgroundColor();

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.editable = NO;
    _textView.backgroundColor = [UIColor clearColor];
    _textView.textColor = VCPrimaryTextColor();
    _textView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                     : UIScrollViewIndicatorStyleDefault;
    _textView.font = [UIFont systemFontOfSize:15.0f];
    _textView.alwaysBounceVertical = YES;
    _textView.text =
        @"Q: Why can't I connect?\n"
        @"A: Most failures come from an unsupported configuration tuple, wrong server parameters, or a server that is offline. "
        @"This app currently allows [vless/tcp/reality] or [vless/tcp/tls] with omitted flow or flow=xtls-rprx-vision and fp=chrome/firefox/edge/random/randomized/qq, [vless/xhttp/tls], [vless/xhttp/reality], [vless/ws/tls], [vless/ws/none], or [socks5]. "
        @"Recheck the link, server details, and network reachability.\n\n"
        @"Q: How can I delete my config/subscription?\n"
        @"A: Just swipe on it from right to the left.\n\n"
        @"Q: Why isn't the subscription added?\n"
        @"A: The app accepts direct vless:// or socks5:// links, or http(s) subscription URLs that return valid config entries. "
        @"If your provider blocks requests, redirects heavily, or returns an empty list, import will fail.\n\n"
        @"Q: Which protocols are supported?\n"
        @"A: VLESS and SOCKS5 links are supported. For now, supported sets are vless tcp+reality with omitted flow or xtls-rprx-vision, vless tcp+tls with omitted flow or xtls-rprx-vision, vless xhttp+tls, vless xhttp+reality, vless ws+tls, vless ws+none, and [socks5]. "
        @"Other tuples are blocked on purpose to prevent broken connections.\n\n"
        @"Q: Why are some protocol tuples marked in red?\n"
        @"A: Red means the tuple or an option such as flow/fp is not supported by the app right now. "
        @"This warning is shown to help you avoid failed connection attempts.\n\n"
        @"Q: Up to which iOS version is the app supported?\n"
        @"A: This package targets legacy 32-bit iOS devices (minimum iOS 6.0). "
        @"It should work up to iOS 10. 64-bit unsupported";
    [self.view addSubview:_textView];
}

@end

@interface AboutVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
    CGFloat _headerWidth;
}
@end

@implementation AboutVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSString *coreVersion = DetectCoreBinaryVersion();
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();
    NSString *redsocksVersion = DetectRedsocksVersion();

    NSArray *components = [NSArray arrayWithObjects:
                           [self rowWithTitle:@"vless-core-cli" detail:coreVersion],
                           [self rowWithTitle:@"vless-core-curl"
                                       detail:[NSString stringWithFormat:@"curl %@, OpenSSL %@ (%@), zlib %@",
                                               [deps objectForKey:@"curl"],
                                               [deps objectForKey:@"openssl"],
                                               opensslPatchStatus,
                                               [deps objectForKey:@"zlib"]]],
                           [self rowWithTitle:@"redsocks-vless-core" detail:redsocksVersion],
                           nil];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"Bundled components" rows:components],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (UIView *)tableHeaderForWidth:(CGFloat)width {
    CGFloat headerHeight = 212.0f;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImage *icon = LoadBundledIconScaled(@"Icon", 82.0f);
    UIImageView *iconView = [[[UIImageView alloc] initWithImage:icon] autorelease];
    iconView.frame = CGRectMake((width - 82.0f) / 2.0f, 22.0f, 82.0f, 82.0f);
    iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    iconView.layer.cornerRadius = 14.0f;
    iconView.layer.masksToBounds = YES;
    [header addSubview:iconView];

    UILabel *nameLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 112.0f, width - 32.0f, 28.0f)] autorelease];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    nameLabel.backgroundColor = [UIColor clearColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.textColor = VCPrimaryTextColor();
    nameLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    nameLabel.text = AppDisplayName();
    [header addSubview:nameLabel];

    UILabel *versionLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 140.0f, width - 32.0f, 22.0f)] autorelease];
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    versionLabel.backgroundColor = [UIColor clearColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.textColor = VCSecondaryTextColor();
    versionLabel.font = [UIFont systemFontOfSize:14.0f];
    versionLabel.text = AppVersionSummary();
    [header addSubview:versionLabel];

    UILabel *buildLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 162.0f, width - 32.0f, 44.0f)] autorelease];
    buildLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    buildLabel.backgroundColor = [UIColor clearColor];
    buildLabel.textAlignment = NSTextAlignmentCenter;
    buildLabel.textColor = VCSecondaryTextColor();
    buildLabel.font = [UIFont systemFontOfSize:14.0f];
    buildLabel.numberOfLines = 2;
    buildLabel.text = AppBuildMetadataSummary();
    [header addSubview:buildLabel];

    return header;
}

- (UIView *)tableFooterForWidth:(CGFloat)width {
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 48.0f)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 8.0f, width - 32.0f, 24.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = VCSecondaryTextColor();
    label.font = [UIFont boldSystemFontOfSize:14.0f];
    label.text = @"made by notfence";
    [footer addSubview:label];

    return footer;
}

- (void)updateTableHeaderAndFooterForWidth:(CGFloat)width {
    if (width <= 0.0f) {
        return;
    }

    _headerWidth = width;
    _tableView.tableHeaderView = [self tableHeaderForWidth:width];
    _tableView.tableFooterView = [self tableFooterForWidth:width];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
    [self updateTableHeaderAndFooterForWidth:_tableView.bounds.size.width];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = _tableView.bounds.size.width;
    if (fabs(_headerWidth - width) > 0.5f) {
        [self updateTableHeaderAndFooterForWidth:width];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kAboutCellId = @"AboutCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (NSUInteger)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@interface CreditsVC : UIViewController <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_tableView;
    NSArray *_sections;
}
@end

@implementation CreditsVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();

    NSArray *libraries = [NSArray arrayWithObjects:
                          [self rowWithTitle:@"curl" detail:[NSString stringWithFormat:@"HTTP client library, version %@", [deps objectForKey:@"curl"]]],
                          [self rowWithTitle:@"OpenSSL" detail:[NSString stringWithFormat:@"TLS library, version %@, %@", [deps objectForKey:@"openssl"], opensslPatchStatus]],
                          [self rowWithTitle:@"zlib" detail:[NSString stringWithFormat:@"Compression library, version %@", [deps objectForKey:@"zlib"]]],
                          [self rowWithTitle:@"libevent" detail:@"Event loop library used by redsocks."],
                          [self rowWithTitle:@"quirc" detail:@"QR code recognition library by Daniel Beer, ISC License."],
                          [self rowWithTitle:@"CA certificates" detail:@"Mozilla CA bundle packaged as cacert.pem."],
                          nil];

    NSArray *thanks = [NSArray arrayWithObject:
                       [self rowWithTitle:@"Special thanks to:" detail:@"@kirillshpitalev for testing and debugging\n"
                                                                       @"@rafal_official for testing and debugging"]];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"Dependencies" rows:libraries],
                            [self sectionWithTitle:@"Special thanks" rows:thanks],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Credits";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCreditsCellId = @"CreditsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (NSUInteger)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@implementation SettingsVC
@synthesize autoUpdate = _autoUpdate;
@synthesize stealthMode = _stealthMode;
@synthesize darkTheme = _darkTheme;
@synthesize delegate = _delegate;

- (void)closePressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)autoUpdateSwitchChanged:(UISwitch *)sw {
    _autoUpdate = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeAutoUpdate:)]) {
        [_delegate settingsVC:self didChangeAutoUpdate:_autoUpdate];
    }
}

- (void)stealthSwitchChanged:(UISwitch *)sw {
    _stealthMode = [sw isOn];
    if ([_delegate respondsToSelector:@selector(settingsVC:didChangeStealthMode:)]) {
        [_delegate settingsVC:self didChangeStealthMode:_stealthMode];
    }
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _autoUpdateSwitch.onTintColor = VCAccentColor();
    _stealthSwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VCBackgroundColor();
    self.title = @"Settings";

    UIBarButtonItem *close = [[[UIBarButtonItem alloc] initWithTitle:@"Back"
                                                                style:UIBarButtonItemStyleBordered
                                                               target:self
                                                               action:@selector(closePressed)] autorelease];
    self.navigationItem.leftBarButtonItem = close;

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];

    _autoUpdateSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
    [_autoUpdateSwitch addTarget:self action:@selector(autoUpdateSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    _stealthSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_stealthSwitch setOn:_stealthMode animated:NO];
    [_stealthSwitch addTarget:self action:@selector(stealthSwitchChanged:) forControlEvents:UIControlEventValueChanged];

    [self applyTheme];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0 || section == 1) return 2;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return @"Subscriptions";
    if (section == 1) return @"Appearance";
    return @"About";
}

- (VCMarqueeLabel *)settingsMarqueeForCell:(UITableViewCell *)cell
                                        tag:(NSInteger)tag
                              createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[cell.contentView viewWithTag:tag];
    if (!marquee && createIfNeeded) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = tag;
        marquee.userInteractionEnabled = NO;
        marquee.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:marquee];
    }
    return marquee;
}

- (void)applySettingsMarqueesToCell:(UITableViewCell *)cell
                               title:(NSString *)title
                              detail:(NSString *)detail {
    if (!cell) return;
    NSString *titleText = ([title isKindOfClass:[NSString class]] ? title : @"");
    NSString *detailText = ([detail isKindOfClass:[NSString class]] ? detail : @"");
    UIColor *titleColor = VCPrimaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();

    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = titleColor;
    cell.detailTextLabel.textColor = detailColor;
    cell.textLabel.text = titleText;
    cell.detailTextLabel.text = detailText;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    VCMarqueeLabel *titleMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsTitleMarqueeTag createIfNeeded:YES];
    if ([titleText length] > 0) {
        titleMarquee.hidden = NO;
        titleMarquee.frame = cell.textLabel.frame;
        titleMarquee.font = cell.textLabel.font;
        titleMarquee.textColor = titleColor;
        titleMarquee.text = titleText;
        cell.textLabel.textColor = [UIColor clearColor];
    } else {
        [titleMarquee stopMarquee];
        titleMarquee.text = @"";
        titleMarquee.hidden = YES;
    }

    VCMarqueeLabel *detailMarquee = [self settingsMarqueeForCell:cell tag:kVCSettingsDetailMarqueeTag createIfNeeded:YES];
    if ([detailText length] > 0) {
        detailMarquee.hidden = NO;
        detailMarquee.frame = cell.detailTextLabel.frame;
        detailMarquee.font = cell.detailTextLabel.font;
        detailMarquee.textColor = detailColor;
        detailMarquee.text = detailText;
        cell.detailTextLabel.textColor = [UIColor clearColor];
    } else {
        [detailMarquee stopMarquee];
        detailMarquee.text = @"";
        detailMarquee.hidden = YES;
    }
}

- (NSString *)settingsTitleTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Auto-update subscriptions";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Stealth mode";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Light";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Dark";
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"About vless-core";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Credits";
    }
    if (indexPath.section == 2 && indexPath.row == 2) {
        return @"FAQ";
    }
    if (indexPath.section == 2 && indexPath.row == 3) {
        return @"Project on GitHub";
    }
    return @"";
}

- (NSString *)settingsDetailTextForIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        return @"Refresh subscriptions on app open";
    }
    if (indexPath.section == 0 && indexPath.row == 1) {
        return @"Hide links in configs and subscriptions";
    }
    if (indexPath.section == 1 && indexPath.row == 0) {
        return @"Use the light color scheme";
    }
    if (indexPath.section == 1 && indexPath.row == 1) {
        return @"Use the dark color scheme";
    }
    if (indexPath.section == 2 && indexPath.row == 0) {
        return @"Version and core binary info";
    }
    if (indexPath.section == 2 && indexPath.row == 1) {
        return @"Dependencies and special thanks";
    }
    if (indexPath.section == 2 && indexPath.row == 2) {
        return @"Common questions and quick answers";
    }
    if (indexPath.section == 2 && indexPath.row == 3) {
        return @"github.com/notfence/vless-core-app";
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0 && indexPath.row == 0) {
        static NSString *kSwitchCellId = @"SettingsSwitchCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kSwitchCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kSwitchCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_autoUpdateSwitch setOn:_autoUpdate animated:NO];
        cell.accessoryView = _autoUpdateSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Auto-update subscriptions"
                                   detail:@"Refresh subscriptions on app open"];
        return cell;
    }

    if (indexPath.section == 0 && indexPath.row == 1) {
        static NSString *kStealthCellId = @"SettingsStealthCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kStealthCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kStealthCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        [_stealthSwitch setOn:_stealthMode animated:NO];
        cell.accessoryView = _stealthSwitch;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Stealth mode"
                                   detail:@"Hide links in configs and subscriptions"];
        return cell;
    }

    if (indexPath.section == 1) {
        static NSString *kThemeCellId = @"SettingsThemeCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kThemeCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kThemeCellId] autorelease];
        }
        BOOL darkRow = (indexPath.row == 1);
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryView = nil;
        cell.accessoryType = (_darkTheme == darkRow) ? UITableViewCellAccessoryCheckmark
                                                     : UITableViewCellAccessoryNone;
        [self applySettingsMarqueesToCell:cell
                                    title:(darkRow ? @"Dark" : @"Light")
                                   detail:(darkRow ? @"Use the dark color scheme" : @"Use the light color scheme")];
        return cell;
    }

    if (indexPath.section == 2 && indexPath.row == 0) {
        static NSString *kAboutCellId = @"SettingsAboutCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [self applySettingsMarqueesToCell:cell
                                    title:@"About vless-core"
                                   detail:@"Version and core binary info"];
        return cell;
    }

    if (indexPath.section == 2 && indexPath.row == 1) {
        static NSString *kCreditsCellId = @"SettingsCreditsCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [self applySettingsMarqueesToCell:cell
                                    title:@"Credits"
                                   detail:@"Dependencies and special thanks"];
        return cell;
    }

    if (indexPath.section == 2 && indexPath.row == 2) {
        static NSString *kFAQCellId = @"SettingsFAQCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        [self applySettingsMarqueesToCell:cell
                                    title:@"FAQ"
                                   detail:@"Common questions and quick answers"];
        return cell;
    }

    static NSString *kGitHubCellId = @"SettingsGitHubCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kGitHubCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kGitHubCellId] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    [self applySettingsMarqueesToCell:cell
                                title:@"Project on GitHub"
                               detail:@"github.com/notfence/vless-core-app"];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    [self applySettingsMarqueesToCell:cell
                                title:[self settingsTitleTextForIndexPath:indexPath]
                               detail:[self settingsDetailTextForIndexPath:indexPath]];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        BOOL dark = (indexPath.row == 1);
        if (_darkTheme != dark) {
            _darkTheme = dark;
            VCAppearanceSetDark(dark);
            if ([_delegate respondsToSelector:@selector(settingsVC:didChangeDarkTheme:)]) {
                [_delegate settingsVC:self didChangeDarkTheme:dark];
            }
            [self applyTheme];
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            AboutVC *about = [[[AboutVC alloc] init] autorelease];
            [self.navigationController pushViewController:about animated:YES];
        } else if (indexPath.row == 1) {
            CreditsVC *credits = [[[CreditsVC alloc] init] autorelease];
            [self.navigationController pushViewController:credits animated:YES];
        } else if (indexPath.row == 2) {
            FAQVC *faq = [[[FAQVC alloc] init] autorelease];
            [self.navigationController pushViewController:faq animated:YES];
        } else {
            NSURL *url = [NSURL URLWithString:@"https://github.com/notfence/vless-core-app"];
            if (url) {
                [[UIApplication sharedApplication] openURL:url];
            }
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (NSUInteger)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    [_tableView release];
    [_autoUpdateSwitch release];
    [_stealthSwitch release];
    [super dealloc];
}

@end

@implementation SettingsNavController

- (void)viewDidLoad {
    [super viewDidLoad];
    VCAppearanceApplyNavigationBar(self.navigationBar);
}

- (BOOL)shouldAutorotate {
    return [[self topViewController] shouldAutorotate];
}

- (NSUInteger)supportedInterfaceOrientations {
    return [[self topViewController] supportedInterfaceOrientations];
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return [[self topViewController] preferredInterfaceOrientationForPresentation];
}

@end

@protocol QRScanVCDelegate <NSObject>
- (void)qrScanVCDidCancel:(UIViewController *)vc;
- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text;
@end

@interface QRScanVC : UIViewController <AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate> {
    id<QRScanVCDelegate> _delegate;
    AVCaptureSession *_captureSession;
    AVCaptureMetadataOutput *_metadataOutput;
    AVCaptureVideoDataOutput *_videoOutput;
    dispatch_queue_t _videoQueue;
    AVCaptureVideoPreviewLayer *_previewLayer;
    UILabel *_hintLabel;
    UIButton *_cancelButton;
    UILabel *_cancelButtonLabel;
    struct quirc *_qrDecoder;
    int _frameSkipCounter;
    BOOL _didFinish;
    BOOL _metadataCanScanQR;
}
@property (nonatomic, assign) id<QRScanVCDelegate> delegate;
@end

@implementation QRScanVC

@synthesize delegate = _delegate;

- (AVCaptureVideoOrientation)captureVideoOrientationForCurrentInterfaceOrientation {
    UIInterfaceOrientation ui = CurrentInterfaceOrientation();
    switch (ui) {
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationPortrait:
        default:
            return AVCaptureVideoOrientationPortrait;
    }
}

- (void)updateCaptureConnectionOrientations {
    AVCaptureVideoOrientation v = [self captureVideoOrientationForCurrentInterfaceOrientation];

    AVCaptureConnection *previewConn = [_previewLayer connection];
    if (previewConn && [previewConn isVideoOrientationSupported]) {
        [previewConn setVideoOrientation:v];
    }

    AVCaptureConnection *metadataConn = [_metadataOutput connectionWithMediaType:AVMediaTypeVideo];
    if (metadataConn && [metadataConn isVideoOrientationSupported]) {
        [metadataConn setVideoOrientation:v];
    }

    AVCaptureConnection *videoConn = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (videoConn && [videoConn isVideoOrientationSupported]) {
        [videoConn setVideoOrientation:v];
    }
}

- (void)deliverScanResult:(NSString *)rawValue {
    if (_didFinish) return;
    NSString *value = [rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![value isKindOfClass:[NSString class]] || [value length] == 0) return;

    _didFinish = YES;
    if (_captureSession && [_captureSession isRunning]) {
        [_captureSession stopRunning];
    }
    if ([_delegate respondsToSelector:@selector(qrScanVC:didScanText:)]) {
        [_delegate qrScanVC:self didScanText:value];
    }
}

- (BOOL)tryDecodeFrameWithQuirc:(CMSampleBufferRef)sampleBuffer decodedText:(NSString **)decodedText {
    if (!sampleBuffer || !decodedText) return NO;

    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return NO;

    CVPixelBufferLockBaseAddress(imageBuffer, 0);

    size_t width = 0;
    size_t height = 0;
    size_t bytesPerRow = 0;
    const uint8_t *source = NULL;
    BOOL isPlanar = CVPixelBufferIsPlanar(imageBuffer);

    if (isPlanar && CVPixelBufferGetPlaneCount(imageBuffer) > 0) {
        width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        source = (const uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    } else {
        width = CVPixelBufferGetWidth(imageBuffer);
        height = CVPixelBufferGetHeight(imageBuffer);
        bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        source = (const uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    }

    if (!source || width < 40 || height < 40) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    if (!_qrDecoder) {
        _qrDecoder = quirc_new();
    }
    if (!_qrDecoder) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    if (quirc_resize(_qrDecoder, (int)width, (int)height) < 0) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    uint8_t *dst = quirc_begin(_qrDecoder, NULL, NULL);
    if (!dst) {
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
        return NO;
    }

    if (isPlanar) {
        for (size_t y = 0; y < height; y++) {
            memcpy(dst + (y * width), source + (y * bytesPerRow), width);
        }
    } else {
        OSType pixelType = CVPixelBufferGetPixelFormatType(imageBuffer);
        if (pixelType == kCVPixelFormatType_32BGRA || pixelType == kCVPixelFormatType_32ARGB) {
            for (size_t y = 0; y < height; y++) {
                const uint8_t *row = source + (y * bytesPerRow);
                uint8_t *dstRow = dst + (y * width);
                for (size_t x = 0; x < width; x++) {
                    const uint8_t *px = row + (x * 4);
                    dstRow[x] = px[1];
                }
            }
        } else {
            for (size_t y = 0; y < height; y++) {
                memcpy(dst + (y * width), source + (y * bytesPerRow), width);
            }
        }
    }

    quirc_end(_qrDecoder);
    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);

    int count = quirc_count(_qrDecoder);
    for (int i = 0; i < count; i++) {
        struct quirc_code code;
        struct quirc_data data;
        quirc_extract(_qrDecoder, i, &code);
        quirc_decode_error_t err = quirc_decode(&code, &data);
        if (err != QUIRC_SUCCESS) {
            quirc_flip(&code);
            err = quirc_decode(&code, &data);
        }
        if (err != QUIRC_SUCCESS) continue;
        if (data.payload_len <= 0) continue;

        NSData *payloadData = [NSData dataWithBytes:data.payload length:(NSUInteger)data.payload_len];
        NSString *text = [[[NSString alloc] initWithData:payloadData encoding:NSUTF8StringEncoding] autorelease];
        if (!text) {
            text = [[[NSString alloc] initWithData:payloadData encoding:NSISOLatin1StringEncoding] autorelease];
        }
        if (!text || [text length] == 0) continue;

        *decodedText = text;
        return YES;
    }

    return NO;
}

- (void)configureCaptureSession {
    AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!camera) {
        _hintLabel.text = @"Camera is unavailable on this device";
        return;
    }

    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error];
    if (!input) {
        _hintLabel.text = @"Failed to access camera";
        return;
    }

    _captureSession = [[AVCaptureSession alloc] init];
    if ([_captureSession canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        _captureSession.sessionPreset = AVCaptureSessionPreset640x480;
    }
    if ([_captureSession canAddInput:input]) {
        [_captureSession addInput:input];
    } else {
        [_captureSession release];
        _captureSession = nil;
        _hintLabel.text = @"Camera input is not supported";
        return;
    }

    AVCaptureMetadataOutput *metadataOutput = [[[AVCaptureMetadataOutput alloc] init] autorelease];
    if ([_captureSession canAddOutput:metadataOutput]) {
        [_captureSession addOutput:metadataOutput];
        [metadataOutput setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
        _metadataOutput = [metadataOutput retain];
    }

    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    NSDictionary *settings = [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                                                         forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [_videoOutput setVideoSettings:settings];
    _videoQueue = dispatch_queue_create("com.vlesscore.qrscan.video", DISPATCH_QUEUE_SERIAL);
    [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
    if ([_captureSession canAddOutput:_videoOutput]) {
        [_captureSession addOutput:_videoOutput];
    } else {
        [_videoOutput release];
        _videoOutput = nil;
    }

    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_captureSession];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.view.layer insertSublayer:_previewLayer atIndex:0];
}

- (void)applyPreferredMetadataTypes {
    _metadataCanScanQR = NO;
    if (!_metadataOutput) {
        _hintLabel.text = @"Legacy QR mode: hold camera steady";
        return;
    }

    NSArray *availableTypes = [_metadataOutput availableMetadataObjectTypes];
    if (![availableTypes isKindOfClass:[NSArray class]] || [availableTypes count] == 0) {
        _hintLabel.text = @"Legacy QR mode: hold camera steady";
        return;
    }

    @try {
        if ([availableTypes containsObject:kVCQRMetadataType]) {
            [_metadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:kVCQRMetadataType]];
            _metadataCanScanQR = YES;
            _hintLabel.text = @"Point camera at QR code with vless://, socks5://, or subscription URL";
            return;
        }
        [_metadataOutput setMetadataObjectTypes:availableTypes];
    }
    @catch (NSException *exception) {
        (void)exception;
    }

    _hintLabel.text = @"Legacy QR mode: hold camera steady";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _hintLabel.textColor = [UIColor whiteColor];
    _hintLabel.font = [UIFont boldSystemFontOfSize:16.0];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.numberOfLines = 2;
    _hintLabel.text = @"Point camera at QR code with vless://, socks5://, or subscription URL";
    [self.view addSubview:_hintLabel];

    _cancelButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [_cancelButton setTitle:@"" forState:UIControlStateNormal];
    _cancelButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    _cancelButton.layer.cornerRadius = 8.0f;
    _cancelButton.layer.borderWidth = 1.0f;
    _cancelButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.45].CGColor;
    _cancelButton.titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [_cancelButton addTarget:self action:@selector(cancelPressed) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_cancelButton];

    _cancelButtonLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _cancelButtonLabel.backgroundColor = [UIColor clearColor];
    _cancelButtonLabel.text = @"Cancel";
    _cancelButtonLabel.font = [UIFont boldSystemFontOfSize:17.0];
    _cancelButtonLabel.textAlignment = NSTextAlignmentCenter;
    _cancelButtonLabel.textColor = [UIColor whiteColor];
    _cancelButtonLabel.shadowColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    _cancelButtonLabel.shadowOffset = CGSizeMake(0.0f, -1.0f);
    _cancelButtonLabel.userInteractionEnabled = NO;
    [_cancelButton addSubview:_cancelButtonLabel];

    [self configureCaptureSession];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    _previewLayer.frame = b;
    [self updateCaptureConnectionOrientations];

    CGFloat pad = 14.0f;
    CGFloat top = 28.0f;
    CGRect sb = [UIApplication sharedApplication].statusBarFrame;
    CGFloat statusInset = MIN(sb.size.width, sb.size.height);
    if (statusInset > 0.0f && statusInset < 64.0f) {
        top = statusInset + 8.0f;
    }
    _hintLabel.frame = CGRectMake(pad, top, b.size.width - (pad * 2.0f), 58.0f);
    _cancelButton.frame = CGRectMake(pad, b.size.height - 62.0f - pad, b.size.width - (pad * 2.0f), 62.0f);
    _cancelButtonLabel.frame = _cancelButton.bounds;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _didFinish = NO;
    _frameSkipCounter = 0;
    if (_captureSession) {
        [_captureSession startRunning];
        [self updateCaptureConnectionOrientations];
        [self applyPreferredMetadataTypes];
        [self performSelector:@selector(applyPreferredMetadataTypes) withObject:nil afterDelay:0.25];
        [self performSelector:@selector(applyPreferredMetadataTypes) withObject:nil afterDelay:0.9];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(applyPreferredMetadataTypes) object:nil];
    if (_captureSession && [_captureSession isRunning]) {
        [_captureSession stopRunning];
    }
}

- (void)cancelPressed {
    _didFinish = YES;
    if (_captureSession && [_captureSession isRunning]) {
        [_captureSession stopRunning];
    }
    if ([_delegate respondsToSelector:@selector(qrScanVCDidCancel:)]) {
        [_delegate qrScanVCDidCancel:self];
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputMetadataObjects:(NSArray *)metadataObjects
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    if (_didFinish || !_metadataCanScanQR || ![metadataObjects isKindOfClass:[NSArray class]]) return;

    for (id obj in metadataObjects) {
        if (![obj respondsToSelector:@selector(type)] ||
            ![obj respondsToSelector:@selector(stringValue)]) {
            continue;
        }

        NSString *type = [obj performSelector:@selector(type)];
        if (![type isKindOfClass:[NSString class]] || ![type isEqualToString:kVCQRMetadataType]) continue;
        NSString *value = [obj performSelector:@selector(stringValue)];
        if (![value isKindOfClass:[NSString class]] || [value length] == 0) continue;
        [self deliverScanResult:value];
        return;
    }
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    (void)captureOutput;
    (void)connection;
    if (_didFinish) return;

    _frameSkipCounter++;
    if ((_frameSkipCounter % 3) != 0) return;

    NSString *decoded = nil;
    if (![self tryDecodeFrameWithQuirc:sampleBuffer decodedText:&decoded]) {
        return;
    }
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) return;

    NSString *captured = [decoded copy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self deliverScanResult:captured];
        [captured release];
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (NSUInteger)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
    return UIInterfaceOrientationPortrait;
}

- (void)dealloc {
    if (_captureSession && [_captureSession isRunning]) {
        [_captureSession stopRunning];
    }
    if (_videoQueue) {
        dispatch_release(_videoQueue);
        _videoQueue = NULL;
    }
    if (_qrDecoder) {
        quirc_destroy(_qrDecoder);
        _qrDecoder = NULL;
    }
    [_captureSession release];
    [_metadataOutput release];
    [_videoOutput release];
    [_previewLayer release];
    [_hintLabel release];
    [_cancelButtonLabel release];
    [super dealloc];
}

@end

@interface MainVC : UIViewController <UITableViewDataSource, UITableViewDelegate, UIActionSheetDelegate, UIAlertViewDelegate, UITextViewDelegate, SettingsVCDelegate, QRScanVCDelegate> {
    UIButton *_connectBtn;
    UIButton *_plusBtn;
    UIButton *_terminalBtn;
    UIButton *_clearLogsBtn;
    UIButton *_refreshBtn;
    UIButton *_settingsBtn;
    UILabel *_statusLabel;
    UILabel *_uptimeLabel;
    UILabel *_titleLabel;

    UITableView *_tableView;
    UIView *_logSelector;
    UIButton *_logSelectorButtons[2];
    UIView *_logSelectionIndicator;
    UITextView *_logView;
    UIView *_stickySectionHeaderView;
    NSTimer *_logTimer;
    NSTimer *_uptimeTimer;
    NSTimeInterval _connectedSince;
    NSString *_statusBaseText;
    NSArray *_importBrowserItems;
    NSString *_pendingImportDoneStatus;
    NSArray *_pendingImportRefreshIndices;
    NSArray *_pendingInsecureImportURLs;

    NSMutableArray *_configs;
    NSMutableArray *_subscriptions;

    NSInteger _selectedConfigIndex;
    NSInteger _selectedSubIndex;
    NSInteger _selectedSubItemIndex;
    NSInteger _expandedSubscription;
    NSInteger _updatingSubscriptionIndex;
    NSInteger _stickySectionHeaderSection;
    NSInteger _activeLogIndex;
    NSUInteger _mainSectionTransitionToken;
    NSString *_logTexts[2];
    CGPoint _logContentOffsets[2];
    BOOL _logContentOffsetsValid[2];
    BOOL _logFollowsTail[2];

    BOOL _connected;
    BOOL _showingTerminal;
    BOOL _autoUpdateSubscriptions;
    BOOL _stealthModeEnabled;
    BOOL _darkThemeEnabled;
    BOOL _statusOK;
    BOOL _configurationsSectionExpanded;
    BOOL _subscriptionsSectionExpanded;
    BOOL _mainSectionTransitionInProgress;
    BOOL _didRunLaunchAutoUpdate;
    BOOL _launchAutoUpdateInProgress;
    BOOL _queuedMainMarqueeRelayout;
}
- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText;
- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts;
- (void)applyTheme;
- (UIView *)accessorySubscriptionHeaderExpanded:(BOOL)expanded loading:(BOOL)loading;
- (BOOL)isMainSectionExpanded:(NSInteger)section;
- (void)finishMainSectionTransition:(NSNumber *)transitionNumber;
- (void)rememberActiveLogPosition;
- (void)reloadMainTableDataAfterExternalChange;
- (void)refreshLogs;
- (void)updateLogSelectorAnimated:(BOOL)animated;
- (void)updateMainSectionHeaderButton:(UIButton *)button section:(NSInteger)section animated:(BOOL)animated;
- (void)updateMainSectionHeaderView:(UIView *)header section:(NSInteger)section animated:(BOOL)animated;
- (void)updateStickyMainSectionHeader;
- (void)refreshStickyMainSectionHeader;
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

- (NSString *)schemeFromURIString:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return @"vless";

    NSRange sep = [uri rangeOfString:@"://"];
    if (sep.location == NSNotFound || sep.location == 0) return @"vless";

    NSString *scheme = [self safeTrim:[uri substringToIndex:sep.location]];
    if ([scheme length] == 0) return @"vless";
    return [scheme lowercaseString];
}

- (BOOL)parseSOCKS5Host:(NSString **)hostOut port:(uint16_t *)portOut fromURI:(NSString *)uri {
    NSString *trim = [self safeTrim:uri];
    NSString *lower = [trim lowercaseString];
    if (![lower hasPrefix:@"socks5://"]) return NO;

    NSString *authority = [trim substringFromIndex:9];
    NSCharacterSet *endSet = [NSCharacterSet characterSetWithCharactersInString:@"/?#"];
    NSRange end = [authority rangeOfCharacterFromSet:endSet];
    if (end.location != NSNotFound) {
        authority = [authority substringToIndex:end.location];
    }
    authority = [self safeTrim:authority];
    if ([authority length] == 0) return NO;

    NSRange at = [authority rangeOfString:@"@" options:NSBackwardsSearch];
    if (at.location != NSNotFound && at.location + 1 < [authority length]) {
        authority = [authority substringFromIndex:(at.location + 1)];
    }
    authority = [self safeTrim:authority];
    if ([authority length] == 0) return NO;

    NSString *host = nil;
    uint16_t port = 1080;
    if ([authority hasPrefix:@"["]) {
        NSRange rb = [authority rangeOfString:@"]"];
        if (rb.location == NSNotFound || rb.location <= 1) return NO;
        host = [authority substringWithRange:NSMakeRange(1, rb.location - 1)];
        if (rb.location + 1 < [authority length] && [authority characterAtIndex:(rb.location + 1)] == ':') {
            NSString *rawPort = [authority substringFromIndex:(rb.location + 2)];
            NSInteger p = [rawPort integerValue];
            if (p <= 0 || p > 65535) return NO;
            port = (uint16_t)p;
        }
    } else {
        NSRange colon = [authority rangeOfString:@":" options:NSBackwardsSearch];
        if (colon.location != NSNotFound) {
            host = [authority substringToIndex:colon.location];
            NSString *rawPort = [authority substringFromIndex:(colon.location + 1)];
            NSInteger p = [rawPort integerValue];
            if (p <= 0 || p > 65535) return NO;
            port = (uint16_t)p;
        } else {
            host = authority;
        }
    }

    host = [self safeTrim:host];
    if ([host length] == 0) return NO;
    if (hostOut) *hostOut = host;
    if (portOut) *portOut = port;
    return YES;
}

- (NSString *)hostFromConfigURI:(NSString *)uri {
    NSURL *u = [NSURL URLWithString:uri];
    NSString *host = [self safeTrim:[u host]];
    if ([host length] > 0) return host;

    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) {
        NSString *parsedHost = nil;
        if ([self parseSOCKS5Host:&parsedHost port:NULL fromURI:uri] && [parsedHost length] > 0) {
            return parsedHost;
        }
        return @"socks5";
    }

    return [self hostFromVLESSURI:uri];
}

- (NSString *)displayNameForURI:(NSString *)uri index:(NSInteger)index {
    NSString *name = [self decodedFragmentFromURI:uri];
    if (name) return name;

    NSString *host = [self hostFromConfigURI:uri];
    return [NSString stringWithFormat:@"Config %ld (%@)", (long)(index + 1), host];
}

- (NSString *)hostFromURLString:(NSString *)urlString {
    NSURL *u = [NSURL URLWithString:urlString];
    NSString *h = [u host];
    if (!h || [h length] == 0) return @"subscription";
    return h;
}

- (NSString *)decodedURLComponent:(NSString *)component {
    if (![component isKindOfClass:[NSString class]] || [component length] == 0) return @"";

    NSString *fixed = [component stringByReplacingOccurrencesOfString:@"+" withString:@"%20"];
    NSString *decoded = [fixed stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    if (![decoded isKindOfClass:[NSString class]] || [decoded length] == 0) {
        decoded = fixed;
    }
    return [self safeTrim:decoded];
}

- (NSString *)queryValueForURLString:(NSString *)urlString key:(NSString *)key {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return nil;
    if (![key isKindOfClass:[NSString class]] || [key length] == 0) return nil;

    NSRange q = [urlString rangeOfString:@"?"];
    if (q.location == NSNotFound || q.location + 1 >= [urlString length]) return nil;

    NSString *query = [urlString substringFromIndex:(q.location + 1)];
    NSRange hash = [query rangeOfString:@"#"];
    if (hash.location != NSNotFound) {
        query = [query substringToIndex:hash.location];
    }

    NSArray *pairs = [query componentsSeparatedByString:@"&"];
    NSString *wanted = [[self decodedURLComponent:key] lowercaseString];
    for (NSString *pair in pairs) {
        if (![pair isKindOfClass:[NSString class]] || [pair length] == 0) continue;

        NSRange eq = [pair rangeOfString:@"="];
        NSString *rawKey = nil;
        NSString *rawValue = nil;
        if (eq.location == NSNotFound) {
            rawKey = pair;
            rawValue = @"";
        } else {
            rawKey = [pair substringToIndex:eq.location];
            rawValue = [pair substringFromIndex:(eq.location + 1)];
        }

        NSString *decodedKey = [[self decodedURLComponent:rawKey] lowercaseString];
        if (![decodedKey isEqualToString:wanted]) continue;

        NSString *decodedValue = [self decodedURLComponent:rawValue];
        if ([decodedValue length] > 0) return decodedValue;
    }

    return nil;
}

- (NSString *)decodedSubscriptionTitleValue:(NSString *)rawValue {
    if (![rawValue isKindOfClass:[NSString class]]) return nil;

    NSString *value = [self safeTrim:rawValue];
    if ([value length] == 0) return nil;

    if ([value hasPrefix:@"\""] && [value hasSuffix:@"\""] && [value length] >= 2) {
        value = [value substringWithRange:NSMakeRange(1, [value length] - 2)];
        value = [self safeTrim:value];
    }
    if ([value length] == 0) return nil;

    NSString *lower = [value lowercaseString];
    if ([lower hasPrefix:@"base64:"]) {
        NSString *b64 = [self safeTrim:[value substringFromIndex:7]];
        NSData *decoded = DecodeBase64String(b64);
        if (!decoded || [decoded length] == 0) return nil;

        NSString *txt = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
        if (!txt) txt = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
        txt = [self safeTrim:txt];
        return ([txt length] > 0) ? txt : nil;
    }

    NSString *decoded = [self decodedURLComponent:value];
    return ([decoded length] > 0) ? decoded : nil;
}

- (NSString *)subscriptionTitleFromMetadataText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) return nil;

    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *found = nil;
    for (NSString *line in lines) {
        if (![line isKindOfClass:[NSString class]]) continue;
        NSString *trim = [self safeTrim:line];
        if ([trim length] == 0) continue;

        if ([trim hasPrefix:@"#"]) {
            trim = [self safeTrim:[trim substringFromIndex:1]];
            if ([trim length] == 0) continue;
        }

        NSString *lower = [trim lowercaseString];
        if (![lower hasPrefix:@"profile-title"]) continue;

        NSRange sep = [trim rangeOfString:@":"];
        if (sep.location == NSNotFound) {
            sep = [trim rangeOfString:@"="];
        }
        if (sep.location == NSNotFound || sep.location + 1 >= [trim length]) continue;

        NSString *rawValue = [trim substringFromIndex:(sep.location + 1)];
        NSString *decoded = [self decodedSubscriptionTitleValue:rawValue];
        if ([decoded length] > 0) {
            found = decoded;
        }
    }

    return found;
}

- (NSString *)subscriptionTitleFromData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    NSString *raw = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!raw) raw = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!raw || [raw length] == 0) return nil;

    NSString *title = [self subscriptionTitleFromMetadataText:raw];
    if ([title length] > 0) return title;

    NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
    NSData *decoded = DecodeBase64String(b64);
    if (!decoded || [decoded length] == 0) return nil;

    NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
    if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
    if (!decodedText || [decodedText length] == 0) return nil;

    return [self subscriptionTitleFromMetadataText:decodedText];
}

- (NSString *)subscriptionTitleFromHTTPHeaders:(NSDictionary *)headers {
    if (![headers isKindOfClass:[NSDictionary class]]) return nil;

    for (id key in headers) {
        if (![key isKindOfClass:[NSString class]]) continue;
        NSString *keyString = [(NSString *)key lowercaseString];
        if (![keyString isEqualToString:@"profile-title"]) continue;

        id rawHeader = [headers objectForKey:key];
        if (![rawHeader isKindOfClass:[NSString class]]) continue;

        NSString *decoded = [self decodedSubscriptionTitleValue:(NSString *)rawHeader];
        if ([decoded length] > 0) return decoded;
    }

    return nil;
}

- (NSString *)transportTypeFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"tcp";

    NSString *transport = [self queryValueForURLString:uri key:@"type"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"transport"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"network"];
    if ([transport length] == 0) transport = [self queryValueForURLString:uri key:@"net"];

    transport = [self safeTrim:transport];
    if ([transport length] == 0) return @"tcp";
    return [transport lowercaseString];
}

- (NSString *)securityTypeFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"plain";

    NSString *security = [self queryValueForURLString:uri key:@"security"];
    security = [self safeTrim:security];
    if ([security length] == 0) return @"none";
    return [security lowercaseString];
}

- (NSString *)realityFlowFromURI:(NSString *)uri {
    NSString *flow = [self queryValueForURLString:uri key:@"flow"];
    return [self safeTrim:flow];
}

- (NSString *)realityFingerprintFromURI:(NSString *)uri {
    NSString *fp = [self queryValueForURLString:uri key:@"fp"];
    fp = [self safeTrim:fp];
    if ([fp length] == 0) return @"chrome";
    return [fp lowercaseString];
}

- (BOOL)isSupportedRealityFingerprint:(NSString *)fp {
    if (![fp isKindOfClass:[NSString class]] || [fp length] == 0) return NO;
    return [fp isEqualToString:@"chrome"] ||
           [fp isEqualToString:@"firefox"] ||
           [fp isEqualToString:@"edge"] ||
           [fp isEqualToString:@"random"] ||
           [fp isEqualToString:@"randomized"] ||
           [fp isEqualToString:@"qq"];
}

- (NSString *)subscriptionNameFromURLString:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        return @"subscription";
    }

    NSArray *queryKeys = [NSArray arrayWithObjects:@"profile-title", @"title", @"name", @"subname", @"tag", @"remark", nil];
    for (NSString *key in queryKeys) {
        NSString *value = [self queryValueForURLString:urlString key:key];
        if ([value length] > 0) return value;
    }

    return [self hostFromURLString:urlString];
}

- (BOOL)isLikelyLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return NO;
    NSString *trim = [self safeTrim:text];
    if ([trim length] == 0) return NO;

    NSString *lower = [trim lowercaseString];
    if ([lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"] || [lower hasPrefix:@"vless://"] || [lower hasPrefix:@"socks5://"]) return YES;
    if ([trim rangeOfString:@"/"].location != NSNotFound) return YES;
    if ([trim rangeOfString:@"."].location != NSNotFound) return YES;
    if ([trim rangeOfString:@":"].location != NSNotFound) return YES;
    return NO;
}

- (NSString *)maskedLinkText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *trim = [self safeTrim:text];
    NSUInteger len = [trim length];
    if (len == 0) return @"";

    if (!_stealthModeEnabled || ![self isLikelyLinkText:trim]) {
        return trim;
    }
    return @"**links are hidden**";
}

- (BOOL)isSubscriptionURL:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"http://"] || [lower hasPrefix:@"https://"];
}

- (BOOL)isVLESSURI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"vless://"];
}

- (BOOL)isSOCKS5URI:(NSString *)s {
    NSString *trim = [self safeTrim:s];
    NSString *lower = [trim lowercaseString];
    return [lower hasPrefix:@"socks5://"];
}

- (BOOL)isDirectConfigURI:(NSString *)s {
    return [self isVLESSURI:s] || [self isSOCKS5URI:s];
}

- (void)saveData {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:_configs forKey:kDefaultsConfigsKey];
    [ud setObject:_subscriptions forKey:kDefaultsSubsKey];
    [ud setBool:_autoUpdateSubscriptions forKey:kDefaultsAutoUpdateSubsKey];
    [ud setBool:_stealthModeEnabled forKey:kDefaultsStealthModeKey];
    [ud setBool:_darkThemeEnabled forKey:kDefaultsDarkThemeKey];
    [ud synchronize];
    [self updateStickyMainSectionHeader];
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

    if ([ud objectForKey:kDefaultsStealthModeKey] == nil) {
        _stealthModeEnabled = NO;
    } else {
        _stealthModeEnabled = [ud boolForKey:kDefaultsStealthModeKey];
    }

    _darkThemeEnabled = [ud boolForKey:kDefaultsDarkThemeKey];

    _selectedConfigIndex = -1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    _expandedSubscription = -1;
    _updatingSubscriptionIndex = -1;
    _stickySectionHeaderSection = -1;
    _configurationsSectionExpanded = NO;
    _subscriptionsSectionExpanded = NO;

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

- (NSInteger)rowForSubscriptionHeaderAtIndex:(NSInteger)subIdx {
    if (subIdx < 0 || subIdx >= (NSInteger)[_subscriptions count]) return -1;

    NSInteger row = 0;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        if (i == subIdx) {
            return row;
        }
        row += 1;
        if (i == _expandedSubscription) {
            row += (NSInteger)[[self subscriptionItemsAtIndex:i] count];
        }
    }

    return -1;
}

- (void)setUpdatingSubscriptionIndex:(NSInteger)subIdx {
    if (_updatingSubscriptionIndex == subIdx) return;

    NSInteger oldIdx = _updatingSubscriptionIndex;
    _updatingSubscriptionIndex = subIdx;

    if (!_tableView || !_subscriptionsSectionExpanded) return;

    NSInteger oldRow = [self rowForSubscriptionHeaderAtIndex:oldIdx];
    if (oldRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:oldRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            cell.accessoryView = [self accessorySubscriptionHeaderExpanded:(_expandedSubscription == oldIdx)
                                                                       loading:NO];
        }
    }

    NSInteger newRow = [self rowForSubscriptionHeaderAtIndex:subIdx];
    if (newRow >= 0) {
        NSIndexPath *ip = [NSIndexPath indexPathForRow:newRow inSection:1];
        UITableViewCell *cell = [_tableView cellForRowAtIndexPath:ip];
        if (cell) {
            cell.accessoryView = [self accessorySubscriptionHeaderExpanded:(_expandedSubscription == subIdx)
                                                                       loading:YES];
        }
    }
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
    _statusLabel.text = base;
}

- (void)refreshUptimeText {
    if (_connected && _connectedSince > 0) {
        NSTimeInterval delta = [[NSDate date] timeIntervalSince1970] - _connectedSince;
        _uptimeLabel.text = [self formatDuration:delta];
    } else {
        _uptimeLabel.text = @"00:00:00";
    }
}

- (void)startUptimeTimer {
    [_uptimeTimer invalidate];
    [_uptimeTimer release];
    _uptimeTimer = nil;

    _connectedSince = [[NSDate date] timeIntervalSince1970];
    [self refreshUptimeText];
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
    [self refreshUptimeText];
}

- (void)uptimeTick:(NSTimer *)timer {
    (void)timer;
    [self refreshUptimeText];
}

- (void)showStatus:(NSString *)text ok:(BOOL)ok {
    [_statusBaseText release];
    _statusBaseText = [[self sanitizeDaemonText:text] copy];
    _statusOK = ok;
    _statusLabel.textColor = ok ? VCSuccessColor() : VCErrorColor();
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

- (NSString *)endpointFromConfigURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return @"server";

    NSURL *u = [NSURL URLWithString:uri];
    NSString *host = [self safeTrim:[u host]];
    NSNumber *portNum = [u port];
    NSInteger port = [portNum respondsToSelector:@selector(integerValue)] ? [portNum integerValue] : 0;

    if ([host length] > 0) {
        if (port <= 0 || port > 65535) {
            NSString *scheme = [self schemeFromURIString:uri];
            if ([scheme isEqualToString:@"vless"]) {
                port = 443;
            } else if ([scheme isEqualToString:@"socks5"]) {
                port = 1080;
            }
        }

        if (port > 0 && port <= 65535) {
            return [NSString stringWithFormat:@"%@:%ld", host, (long)port];
        }
        return host;
    }

    NSString *parsedHost = nil;
    uint16_t parsedPort = 443;
    if ([self parseVLESSHost:&parsedHost port:&parsedPort fromURI:uri] && [parsedHost length] > 0) {
        return [NSString stringWithFormat:@"%@:%u", parsedHost, (unsigned int)parsedPort];
    }

    if ([self parseSOCKS5Host:&parsedHost port:&parsedPort fromURI:uri] && [parsedHost length] > 0) {
        return [NSString stringWithFormat:@"%@:%u", parsedHost, (unsigned int)parsedPort];
    }

    NSString *fallbackHost = [self hostFromVLESSURI:uri];
    if ([fallbackHost length] > 0) return fallbackHost;
    return @"server";
}

- (NSString *)configSecondaryTextFromURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *endpoint = [self configEndpointTextFromURI:uri];
    if ([prefix length] == 0) return endpoint;
    if ([endpoint length] == 0) return prefix;
    return [NSString stringWithFormat:@"%@ %@", prefix, endpoint];
}

- (NSString *)configPrefixTextFromURI:(NSString *)uri {
    NSString *scheme = [self schemeFromURIString:uri];
    if ([scheme isEqualToString:@"socks5"]) return @"[socks5]";

    NSString *transport = [self transportTypeFromURI:uri];
    NSString *security = [self securityTypeFromURI:uri];
    return [NSString stringWithFormat:@"[%@/%@/%@]", scheme, transport, security];
}

- (NSString *)configEndpointTextFromURI:(NSString *)uri {
    NSString *endpoint = [self endpointFromConfigURI:uri];
    return [self maskedLinkText:endpoint];
}

- (NSString *)unsupportedConfigReasonForURI:(NSString *)uri {
    NSString *scheme = [[self schemeFromURIString:uri] lowercaseString];
    NSString *transport = [[self transportTypeFromURI:uri] lowercaseString];
    NSString *security = [[self securityTypeFromURI:uri] lowercaseString];

    if ([scheme isEqualToString:@"socks5"]) {
        NSString *host = nil;
        uint16_t port = 0;
        if (![self parseSOCKS5Host:&host port:&port fromURI:uri] || [host length] == 0 || port == 0) {
            return @"invalid socks5 endpoint";
        }
        return nil;
    }

    if (![scheme isEqualToString:@"vless"]) {
        return @"protocol must be vless or socks5";
    }

    // Supported tuple #1: [vless/tcp/reality] and [vless/tcp/tls]
    BOOL vision = [transport isEqualToString:@"tcp"] &&
                  ([security isEqualToString:@"reality"] || [security isEqualToString:@"tls"]);
    if (vision) {
        NSString *flow = [self realityFlowFromURI:uri];
        if ([flow length] > 0 && ![flow isEqualToString:@"xtls-rprx-vision"]) {
            return [NSString stringWithFormat:@"unsupported flow=%@", flow];
        }

        NSString *fp = [self realityFingerprintFromURI:uri];
        if (![self isSupportedRealityFingerprint:fp]) {
            return [NSString stringWithFormat:@"unsupported fp=%@", fp];
        }

        return nil;
    }

    BOOL xhttpTransport = [transport isEqualToString:@"xhttp"] ||
                          [transport isEqualToString:@"splithttp"];

    // Supported tuple #2: [vless/xhttp/tls]
    if (xhttpTransport && [security isEqualToString:@"tls"]) return nil;

    // Supported tuple #3: [vless/xhttp/reality]
    if (xhttpTransport && [security isEqualToString:@"reality"]) {
        NSString *fp = [self realityFingerprintFromURI:uri];
        if (![self isSupportedRealityFingerprint:fp]) {
            return [NSString stringWithFormat:@"unsupported fp=%@", fp];
        }
        return nil;
    }

    // Supported tuple #4: [vless/ws/tls] and [vless/ws/none]
    if (([transport isEqualToString:@"ws"] || [transport isEqualToString:@"websocket"]) &&
        ([security isEqualToString:@"tls"] || [security isEqualToString:@"none"])) {
        return nil;
    }

    return @"supported sets are vless/tcp/reality, vless/tcp/tls, vless/xhttp/tls, vless/xhttp/reality, vless/ws/tls, vless/ws/none, and [socks5]";
}

- (BOOL)isSupportedConfigTupleForURI:(NSString *)uri {
    return ([self unsupportedConfigReasonForURI:uri] == nil);
}

- (UIColor *)configPrefixColorForURI:(NSString *)uri {
    if ([self isSupportedConfigTupleForURI:uri]) {
        return VCSecondaryTextColor();
    }
    return VCErrorColor();
}

- (NSString *)unsupportedConfigStatusTextForURI:(NSString *)uri {
    NSString *prefix = [self configPrefixTextFromURI:uri];
    if (![prefix isKindOfClass:[NSString class]] || [prefix length] == 0) {
        prefix = @"[unknown]";
    }
    NSString *reason = [self unsupportedConfigReasonForURI:uri];
    if ([reason length] > 0) {
        return [NSString stringWithFormat:@"Error: unsupported config %@ (%@)",
                prefix,
                reason];
    }
    return [NSString stringWithFormat:@"Error: unsupported config %@",
            prefix];
}

- (UIView *)mainDetailContainerForCell:(UITableViewCell *)cell createIfNeeded:(BOOL)createIfNeeded {
    if (!cell) return nil;
    UIView *container = [cell.contentView viewWithTag:kVCMainDetailContainerTag];
    if (!container && createIfNeeded) {
        container = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
        container.tag = kVCMainDetailContainerTag;
        container.backgroundColor = [UIColor clearColor];
        container.userInteractionEnabled = NO;
        container.clipsToBounds = YES;
        [cell.contentView addSubview:container];
    }
    return container;
}

- (UILabel *)mainDetailPrefixLabelForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    UILabel *label = (UILabel *)[container viewWithTag:kVCMainDetailPrefixTag];
    if (!label && createIfNeeded) {
        label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
        label.tag = kVCMainDetailPrefixTag;
        label.backgroundColor = [UIColor clearColor];
        label.numberOfLines = 1;
        label.lineBreakMode = NSLineBreakByClipping;
        [container addSubview:label];
    }
    return label;
}

- (VCMarqueeLabel *)mainDetailTailMarqueeForContainer:(UIView *)container createIfNeeded:(BOOL)createIfNeeded {
    if (!container) return nil;
    VCMarqueeLabel *marquee = (VCMarqueeLabel *)[container viewWithTag:kVCMainDetailTailTag];
    if (!marquee && createIfNeeded) {
        marquee = [[[VCMarqueeLabel alloc] initWithFrame:CGRectZero] autorelease];
        marquee.tag = kVCMainDetailTailTag;
        marquee.backgroundColor = [UIColor clearColor];
        marquee.userInteractionEnabled = NO;
        [container addSubview:marquee];
    }
    return marquee;
}

- (CGRect)mainDetailContentFrameForCell:(UITableViewCell *)cell {
    if (!cell) return CGRectZero;
    [cell setNeedsLayout];
    [cell layoutIfNeeded];

    CGRect contentBounds = cell.contentView.bounds;
    CGFloat contentW = CGRectGetWidth(contentBounds);
    CGFloat contentH = CGRectGetHeight(contentBounds);
    if (contentW < 1.0f || contentH < 1.0f) return CGRectZero;

    CGRect titleFrame = cell.textLabel.frame;
    CGRect legacyDetailFrame = cell.detailTextLabel.frame;

    CGFloat left = titleFrame.origin.x;
    if (left < 6.0f) {
        left = legacyDetailFrame.origin.x;
    }
    if (left < 6.0f) {
        left = 10.0f;
    }

    CGFloat top = CGRectGetMaxY(titleFrame) + 1.0f;
    if (top < 1.0f || top > contentH - 6.0f) {
        top = legacyDetailFrame.origin.y;
    }
    if (top < 1.0f) {
        top = 24.0f;
    }

    CGFloat right = contentW - 10.0f;
    if (cell.accessoryView && !cell.accessoryView.hidden) {
        CGRect accessoryFrame = cell.accessoryView.frame;
        if (CGRectGetWidth(accessoryFrame) > 1.0f && CGRectGetMinX(accessoryFrame) > 1.0f) {
            right = MIN(right, CGRectGetMinX(accessoryFrame) - 8.0f);
        }
    }
    if (right < left + 12.0f) {
        right = left + 12.0f;
    }

    CGFloat height = contentH - top - 2.0f;
    if (legacyDetailFrame.size.height > 0.0f) {
        height = MAX(height, legacyDetailFrame.size.height);
    }
    if (top + height > contentH) {
        height = contentH - top;
    }
    if (height < 10.0f) {
        height = 14.0f;
        if (top + height > contentH) {
            top = MAX(0.0f, contentH - height);
        }
    }

    return CGRectMake(left, top, right - left, height);
}

- (void)clearDetailMarqueeForCell:(UITableViewCell *)cell {
    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:NO];
    if (!container) return;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:NO];
    VCMarqueeLabel *tailMarquee = [self mainDetailTailMarqueeForContainer:container createIfNeeded:NO];
    if (tailMarquee) {
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;
    }
    if (prefixLabel) {
        prefixLabel.text = @"";
        prefixLabel.hidden = YES;
    }
    container.hidden = YES;
}

- (void)applyDetailPrefix:(NSString *)prefix
              prefixColor:(UIColor *)prefixColor
              marqueeTail:(NSString *)tail
                   toCell:(UITableViewCell *)cell {
    if (!cell) return;

    NSString *prefixText = ([prefix isKindOfClass:[NSString class]] ? prefix : @"");
    NSString *tailText = ([tail isKindOfClass:[NSString class]] ? tail : @"");
    UIColor *effectivePrefixColor = [prefixColor isKindOfClass:[UIColor class]] ? prefixColor : VCSecondaryTextColor();
    UIColor *detailColor = VCSecondaryTextColor();
    UIFont *detailFont = cell.detailTextLabel.font;
    if (!detailFont) detailFont = [UIFont systemFontOfSize:11.0f];

    // Keep subtitle geometry stable: non-empty detail preserves UIKit two-line layout metrics.
    BOOL hasDetail = ([prefixText length] > 0 || [tailText length] > 0);
    cell.detailTextLabel.text = hasDetail ? @" " : @"";
    cell.detailTextLabel.textColor = [UIColor clearColor];

    if ([prefixText length] == 0 && [tailText length] == 0) {
        [self clearDetailMarqueeForCell:cell];
        return;
    }

    UIView *container = [self mainDetailContainerForCell:cell createIfNeeded:YES];
    CGRect containerFrame = [self mainDetailContentFrameForCell:cell];
    if (CGRectGetWidth(containerFrame) < 8.0f || CGRectGetHeight(containerFrame) < 8.0f) {
        [self clearDetailMarqueeForCell:cell];
        return;
    }

    container.hidden = NO;
    container.frame = containerFrame;

    UILabel *prefixLabel = [self mainDetailPrefixLabelForContainer:container createIfNeeded:YES];
    VCMarqueeLabel *tailMarquee = [self mainDetailTailMarqueeForContainer:container createIfNeeded:YES];
    CGFloat lineH = CGRectGetHeight(container.bounds);
    CGFloat lineW = CGRectGetWidth(container.bounds);

    prefixLabel.font = detailFont;
    prefixLabel.textColor = effectivePrefixColor;
    prefixLabel.backgroundColor = [UIColor clearColor];

    tailMarquee.font = detailFont;
    tailMarquee.textColor = detailColor;
    tailMarquee.backgroundColor = [UIColor clearColor];

    if ([tailText length] == 0) {
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;

        prefixLabel.hidden = NO;
        prefixLabel.text = prefixText;
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        return;
    }

    if ([prefixText length] == 0) {
        prefixLabel.hidden = YES;
        prefixLabel.text = @"";
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, 0.0f, lineH);

        tailMarquee.hidden = NO;
        tailMarquee.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        tailMarquee.text = tailText;
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGSize prefixSize = [prefixText sizeWithFont:detailFont];
#pragma clang diagnostic pop

    CGFloat prefixWidth = ceilf(prefixSize.width);
    CGFloat maxPrefixWidth = lineW - 16.0f;
    if (maxPrefixWidth < 8.0f) maxPrefixWidth = lineW;
    if (prefixWidth > maxPrefixWidth) prefixWidth = maxPrefixWidth;
    if (prefixWidth < 0.0f) prefixWidth = 0.0f;

    CGFloat tailX = prefixWidth + kVCDetailMarqueeGap;
    CGFloat tailWidth = lineW - tailX;
    if (tailWidth < 8.0f) {
        prefixLabel.hidden = NO;
        prefixLabel.text = [NSString stringWithFormat:@"%@ %@", prefixText, tailText];
        prefixLabel.frame = CGRectMake(0.0f, 0.0f, lineW, lineH);
        [tailMarquee stopMarquee];
        tailMarquee.text = @"";
        tailMarquee.hidden = YES;
        return;
    }

    prefixLabel.hidden = NO;
    prefixLabel.text = prefixText;
    prefixLabel.frame = CGRectMake(0.0f, 0.0f, prefixWidth, lineH);

    tailMarquee.hidden = NO;
    tailMarquee.frame = CGRectMake(tailX, 0.0f, tailWidth, lineH);
    tailMarquee.text = tailText;
}

- (void)applyDetailPrefix:(NSString *)prefix marqueeTail:(NSString *)tail toCell:(UITableViewCell *)cell {
    [self applyDetailPrefix:prefix
                prefixColor:VCSecondaryTextColor()
                marqueeTail:tail
                     toCell:cell];
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

        if ([k isEqualToString:@"type"] && ([v isEqualToString:@"xhttp"] || [v isEqualToString:@"splithttp"])) {
            return YES;
        }
    }
    return NO;
}

- (NSString *)xhttpPinKeyFromURI:(NSString *)uri {
    NSString *host = nil;
    uint16_t port = 443;
    if (![self parseVLESSHost:&host port:&port fromURI:uri]) return nil;
    NSString *trimmedHost = [[self safeTrim:host] lowercaseString];
    if (![trimmedHost isKindOfClass:[NSString class]] || [trimmedHost length] == 0) return nil;
    return [NSString stringWithFormat:@"%@:%u", trimmedHost, (unsigned int)port];
}

- (NSString *)xhttpTOFUPinMismatchStatusForURI:(NSString *)uri {
    NSString *tail = ReadFileTail(@"/var/log/vless-core.log", 12288);
    if (![tail isKindOfClass:[NSString class]] || [tail length] == 0) return nil;

    NSString *lowerTail = [tail lowercaseString];
    if ([lowerTail rangeOfString:@"tofu pin mismatch"].location == NSNotFound) return nil;

    NSString *pinKey = [self xhttpPinKeyFromURI:uri];
    if ([pinKey length] > 0) {
        NSString *needle = [NSString stringWithFormat:@"tofu pin mismatch for %@", pinKey];
        if ([lowerTail rangeOfString:needle].location == NSNotFound &&
            [lowerTail rangeOfString:pinKey].location == NSNotFound) {
            return nil;
        }
        return [NSString stringWithFormat:@"Error: TOFU pin mismatch for %@ (clear old entry in xhttp-pins.txt)", pinKey];
    }

    return @"Error: TOFU pin mismatch (clear old entry in xhttp-pins.txt)";
}

- (BOOL)removeXHTTPPinKey:(NSString *)pinKey fromFile:(NSString *)path removed:(BOOL *)removedOut {
    if (removedOut) *removedOut = NO;
    if (![pinKey isKindOfClass:[NSString class]] || [pinKey length] == 0) return NO;
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) return NO;

    NSString *content = ReadTextFileBestEffort(path);
    if (![content isKindOfClass:[NSString class]]) {
        return YES;
    }

    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSMutableArray *kept = [NSMutableArray arrayWithCapacity:[lines count]];
    NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
    NSCharacterSet *trimSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *lowerPinKey = [pinKey lowercaseString];
    BOOL removed = NO;

    for (NSString *line in lines) {
        if (![line isKindOfClass:[NSString class]]) continue;

        NSString *trimmed = [line stringByTrimmingCharactersInSet:trimSet];
        if ([trimmed length] == 0 || [trimmed hasPrefix:@"#"]) {
            [kept addObject:line];
            continue;
        }

        NSRange wsRange = [trimmed rangeOfCharacterFromSet:ws];
        NSString *lineKey = (wsRange.location == NSNotFound) ? trimmed : [trimmed substringToIndex:wsRange.location];
        if ([[lineKey lowercaseString] isEqualToString:lowerPinKey]) {
            removed = YES;
            continue;
        }

        [kept addObject:line];
    }

    if (!removed) {
        return YES;
    }

    NSString *newContent = [kept componentsJoinedByString:@"\n"];
    if ([content hasSuffix:@"\n"] && ![newContent hasSuffix:@"\n"]) {
        newContent = [newContent stringByAppendingString:@"\n"];
    }

    BOOL ok = [newContent writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    if (!ok) {
        ok = [newContent writeToFile:path atomically:YES encoding:NSISOLatin1StringEncoding error:nil];
    }
    if (ok && removedOut) *removedOut = YES;
    return ok;
}

- (BOOL)clearXHTTPPinForURI:(NSString *)uri removedAny:(BOOL *)removedAnyOut {
    if (removedAnyOut) *removedAnyOut = NO;

    NSString *pinKey = [self xhttpPinKeyFromURI:uri];
    if (![pinKey isKindOfClass:[NSString class]] || [pinKey length] == 0) return NO;

    NSArray *paths = [NSArray arrayWithObjects:
                      @"/var/mobile/Library/Preferences/vless-core/xhttp-pins.txt",
                      @"/tmp/vless-core-xhttp-pins.txt",
                      nil];

    BOOL anyRemoved = NO;
    for (NSString *path in paths) {
        BOOL removed = NO;
        if (![self removeXHTTPPinKey:pinKey fromFile:path removed:&removed]) {
            return NO;
        }
        if (removed) anyRemoved = YES;
    }

    if (removedAnyOut) *removedAnyOut = anyRemoved;
    return YES;
}

- (NSInteger)socksPortFromDaemonStatusText:(NSString *)statusText {
    if (![statusText isKindOfClass:[NSString class]] || [statusText length] == 0) return -1;
    NSRange marker = [statusText rangeOfString:@"socks="];
    if (marker.location == NSNotFound) return -1;

    NSUInteger start = marker.location + marker.length;
    NSUInteger end = start;
    while (end < [statusText length]) {
        unichar c = [statusText characterAtIndex:end];
        if (c < '0' || c > '9') break;
        end++;
    }
    if (end <= start) return -1;

    NSInteger p = [[statusText substringWithRange:NSMakeRange(start, end - start)] integerValue];
    if (p <= 0 || p > 65535) return -1;
    return p;
}

- (NSInteger)currentDaemonSocksPort {
    NSString *status = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
    if (![status hasPrefix:@"OK connected"]) return -1;
    return [self socksPortFromDaemonStatusText:status];
}

- (void)xhttpConnectHealthCheckWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];

    BOOL ok = NO;
    for (int attempt = 0; attempt < 3 && !ok; attempt++) {
        NSInteger socksPort = [self currentDaemonSocksPort];
        if (socksPort > 0 && socksPort <= 65535) {
            int ms = 0;
            if (RealPingConnectOnceMs((uint16_t)socksPort, 3500, &ms) == 0) {
                ok = YES;
                break;
            }
        }
        usleep(250 * 1000);
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:3];
    [out setObject:(ok ? @"1" : @"0") forKey:@"ok"];
    if (![uri isKindOfClass:[NSString class]]) uri = @"";
    [out setObject:uri forKey:@"uri"];

    if (!ok) {
        NSString *reason = [self xhttpTOFUPinMismatchStatusForURI:uri];
        if (![reason isKindOfClass:[NSString class]] || [reason length] == 0) {
            reason = @"Error: xhttp tunnel failed health-check";
        }
        [out setObject:reason forKey:@"reason"];
    }

    [self performSelectorOnMainThread:@selector(xhttpConnectHealthCheckResultOnMain:) withObject:out waitUntilDone:NO];
    [pool drain];
}

- (void)xhttpConnectHealthCheckResultOnMain:(NSDictionary *)payload {
    BOOL ok = [[payload objectForKey:@"ok"] isEqualToString:@"1"];
    if (ok) return;
    if (!_connected) return;

    NSString *reason = [payload objectForKey:@"reason"];
    if ([reason rangeOfString:@"TOFU pin mismatch"].location == NSNotFound) {
        return;
    }

    NSString *uri = [payload objectForKey:@"uri"];
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) {
        [self showStatus:reason ok:NO];
        return;
    }

    BOOL removedAny = NO;
    BOOL clearOK = [self clearXHTTPPinForURI:uri removedAny:&removedAny];
    if (!clearOK) {
        [self showStatus:[NSString stringWithFormat:@"%@ (auto-fix failed: pin file write error)", reason] ok:NO];
        return;
    }

    NSString *discResp = [self sanitizeDaemonText:SendCommand(@"DISCONNECT\n")];
    if (![discResp hasPrefix:@"OK"]) {
        [self showStatus:[NSString stringWithFormat:@"%@ (disconnect failed: %@)", reason, discResp] ok:NO];
        return;
    }
    _connected = NO;
    [self stopUptimeTimer];
    [self updateConnectButton];

    NSString *cmd = [NSString stringWithFormat:@"CONNECT\t0\t%@\n", uri];
    NSString *resp = [self sanitizeDaemonText:SendCommand(cmd)];
    if ([resp hasPrefix:@"OK"]) {
        _connected = YES;
        [self startUptimeTimer];
        [self updateConnectButton];
        if (removedAny) {
            [self showStatus:@"Connected (xhttp pin refreshed)" ok:YES];
        } else {
            [self showStatus:@"Connected (xhttp reconnected)" ok:YES];
        }
    } else {
        [self showStatus:[NSString stringWithFormat:@"%@ (reconnect failed: %@)", reason, resp] ok:NO];
    }
}

- (void)scheduleXHTTPConnectHealthCheckForURI:(NSString *)uri {
    if (![self isXHTTPTransportURI:uri]) return;
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             (uri ? uri : @""), @"uri",
                             nil];
    [NSThread detachNewThreadSelector:@selector(xhttpConnectHealthCheckWorker:) toTarget:self withObject:payload];
}

- (void)pingWorker:(NSDictionary *)payload {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *uri = [payload objectForKey:@"uri"];
    NSString *title = [payload objectForKey:@"title"];

    NSString *host = nil;
    uint16_t port = 0;
    NSString *result = nil;
    NSString *scheme = [self schemeFromURIString:uri];
    BOOL isSOCKS5Config = [scheme isEqualToString:@"socks5"];
    BOOL parsed = isSOCKS5Config
        ? [self parseSOCKS5Host:&host port:&port fromURI:uri]
        : [self parseVLESSHost:&host port:&port fromURI:uri];
    if (!parsed) {
        result = [NSString stringWithFormat:@"Ping failed (%@): invalid URI", title ? title : @"config"];
    } else {
        int ms = 0;
        int rc = -1;

        if (isSOCKS5Config) {
            rc = RealPingViaTempCoreMs([uri UTF8String], 5000, 2, &ms);
        } else if ([self isXHTTPTransportURI:uri]) {
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
    UIColor *highlight = VCAppearanceIsDark() ? [UIColor colorWithWhite:0.24f alpha:1.0f]
                                               : [UIColor colorWithWhite:0.72f alpha:1.0f];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateHighlighted];
    [btn setBackgroundImage:SolidImageWithColor(highlight) forState:UIControlStateSelected];
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
    UIColor *iconColor = VCPrimaryTextColor();
    UIImage *refresh = LoadBundledIconTinted(@"icon-refresh", 20.0f, iconColor);
    UIImage *terminal = _showingTerminal
        ? LoadBundledIconTinted(@"icon-list", 20.0f, iconColor)
        : LoadBundledIconTinted(@"icon-terminal", 20.0f, iconColor);
    UIImage *settings = LoadBundledIconTinted(@"icon-settings", 20.0f, iconColor);
    UIImage *trash = LoadBundledIconTinted(@"icon-trash", 20.0f, iconColor);

    [_refreshBtn setImage:(refresh ? refresh : MakeIconImage(VCIconTypeRefresh, 20.0f, NO)) forState:UIControlStateNormal];
    [_terminalBtn setImage:(terminal ? terminal : MakeIconImage(_showingTerminal ? VCIconTypeList : VCIconTypeTerminal, 20.0f, _showingTerminal))
                  forState:UIControlStateNormal];
    [_clearLogsBtn setImage:trash forState:UIControlStateNormal];
    _clearLogsBtn.hidden = !_showingTerminal;
    [_settingsBtn setImage:(settings ? settings : MakeIconImage(VCIconTypeSettings, 20.0f, NO)) forState:UIControlStateNormal];
}

- (NSArray *)extractConfigURIsFromText:(NSString *)text {
    if (!text || [text length] == 0) return [NSArray array];

    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:vless://|socks5://)[^\\s\"'<>]+"
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
        NSString *lower = [uri lowercaseString];
        if (![lower hasPrefix:@"vless://"] && ![lower hasPrefix:@"socks5://"]) continue;
        if (![out containsObject:uri]) {
            [out addObject:uri];
        }
    }
    return out;
}

- (NSArray *)extractImportLinksFromText:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
        return [NSArray array];
    }

    NSError *reErr = nil;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:vless://|socks5://|https?://)[^\\s\"'<>]+"
                                                                         options:NSRegularExpressionCaseInsensitive
                                                                           error:&reErr];
    if (!re || reErr) {
        return [NSArray array];
    }

    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, [text length])];
    NSMutableArray *out = [NSMutableArray array];
    NSCharacterSet *trailSet = [NSCharacterSet characterSetWithCharactersInString:@",;)]}>\"'"];
    for (NSTextCheckingResult *m in matches) {
        if (m.range.location == NSNotFound || m.range.length == 0) continue;
        NSString *link = [text substringWithRange:m.range];
        link = [self safeTrim:link];
        while ([link length] > 0) {
            unichar c = [link characterAtIndex:([link length] - 1)];
            if (![trailSet characterIsMember:c]) break;
            link = [link substringToIndex:([link length] - 1)];
        }
        if ([link length] == 0) continue;

        NSString *lower = [link lowercaseString];
        if (![lower hasPrefix:@"vless://"] &&
            ![lower hasPrefix:@"socks5://"] &&
            ![lower hasPrefix:@"http://"] &&
            ![lower hasPrefix:@"https://"]) {
            continue;
        }

        if (![out containsObject:link]) {
            [out addObject:link];
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
        uris = [self extractConfigURIsFromText:raw];
        if ([uris count] > 0) return [self sanitizeSubscriptionURIs:uris];

        NSString *b64 = [[raw componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
        NSData *decoded = DecodeBase64String(b64);
        if (decoded && [decoded length] > 0) {
            NSString *decodedText = [[[NSString alloc] initWithData:decoded encoding:NSUTF8StringEncoding] autorelease];
            if (!decodedText) decodedText = [[[NSString alloc] initWithData:decoded encoding:NSISOLatin1StringEncoding] autorelease];
            if (decodedText) {
                uris = [self extractConfigURIsFromText:decodedText];
                if ([uris count] > 0) return [self sanitizeSubscriptionURIs:uris];
            }
        }
    }

    return [NSArray array];
}

- (BOOL)isLikelySubscriptionPlaceholderURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return NO;
    return [uri rangeOfString:@"@0.0.0.0:1?"].location != NSNotFound;
}

- (NSArray *)sanitizeSubscriptionURIs:(NSArray *)uris {
    if (![uris isKindOfClass:[NSArray class]] || [uris count] == 0) {
        return [NSArray array];
    }

    NSMutableArray *clean = [NSMutableArray array];
    BOOL hasReal = NO;
    for (id it in uris) {
        if (![it isKindOfClass:[NSString class]]) continue;
        NSString *uri = (NSString *)it;
        if ([uri length] == 0) continue;
        [clean addObject:uri];
        if (![self isLikelySubscriptionPlaceholderURI:uri]) {
            hasReal = YES;
        }
    }

    if (!hasReal) return clean;

    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *uri in clean) {
        if (![self isLikelySubscriptionPlaceholderURI:uri]) {
            [filtered addObject:uri];
        }
    }

    return ([filtered count] > 0) ? filtered : clean;
}

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut insecureRetryAvailable:(BOOL *)insecureRetryAvailableOut {
    if (errorTextOut) *errorTextOut = nil;
    if (insecureRetryAvailableOut) *insecureRetryAvailableOut = NO;
    if (![sub isKindOfClass:[NSDictionary class]]) {
        if (errorTextOut) *errorTextOut = @"Subscription entry is invalid";
        return nil;
    }

    NSString *urlString = [sub objectForKey:@"url"];
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is missing";
        return nil;
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (errorTextOut) *errorTextOut = @"Subscription URL is invalid";
        return nil;
    }

    NSString *nameFromURL = [self subscriptionNameFromURLString:urlString];
    NSString *hostName = [self hostFromURLString:urlString];
    NSString *nameFromMeta = nil;
    BOOL allowInsecureFetch = SubscriptionDictionaryAllowsInsecureFetch(sub);

    NSString *fetchErr = nil;
    NSString *curlHeaders = nil;
    int curlExitCode = -1;
    NSData *data = FetchURLViaVlessCoreCurl(urlString, allowInsecureFetch, &fetchErr, &curlHeaders, &curlExitCode);
    if (!data && !allowInsecureFetch && CurlExitCodeCanRetryInsecurely(curlExitCode)) {
        if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
    }
    if ([nameFromMeta length] == 0 && [curlHeaders length] > 0) {
        nameFromMeta = [self subscriptionTitleFromMetadataText:curlHeaders];
    }
    if (!data && !allowInsecureFetch && (!fetchErr || [fetchErr hasPrefix:@"vless-core-curl not found"])) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:20.0];
        NSString *hwid = SubscriptionHWID();
        if ([hwid isKindOfClass:[NSString class]] && [hwid length] > 0) {
            [req setValue:hwid forHTTPHeaderField:@"X-HWID"];
        }
        NSURLResponse *resp = nil;
        NSError *err = nil;
        data = [NSURLConnection sendSynchronousRequest:req returningResponse:&resp error:&err];
        if (!data || err) {
            fetchErr = [err localizedDescription];
            if (!allowInsecureFetch && NSURLErrorCanRetryInsecurely(err)) {
                if (insecureRetryAvailableOut) *insecureRetryAvailableOut = YES;
            }
        } else if ([resp isKindOfClass:[NSHTTPURLResponse class]]) {
            NSDictionary *headers = [(NSHTTPURLResponse *)resp allHeaderFields];
            nameFromMeta = [self subscriptionTitleFromHTTPHeaders:headers];
        }
    }

    if (!data) {
        if (![fetchErr isKindOfClass:[NSString class]] || [fetchErr length] == 0) {
            fetchErr = @"unknown error";
        }
        if (errorTextOut) *errorTextOut = [NSString stringWithFormat:@"Subscription fetch failed: %@", fetchErr];
        return nil;
    }

    if ([nameFromMeta length] == 0) {
        nameFromMeta = [self subscriptionTitleFromData:data];
    }

    NSArray *uris = [self parseSubscriptionData:data];
    if ([uris count] == 0) {
        if (errorTextOut) {
            if (SubscriptionDataLooksLikeHTML(data)) {
                *errorTextOut = @"Server returned a web page, not subscription data";
            } else {
                *errorTextOut = @"Subscription has no valid config entries";
            }
        }
        return nil;
    }

    NSMutableDictionary *updated = [NSMutableDictionary dictionaryWithDictionary:sub];
    [updated setObject:uris forKey:@"items"];

    NSString *name = [updated objectForKey:@"name"];
    if ([nameFromMeta length] > 0) {
        [updated setObject:nameFromMeta forKey:@"name"];
    } else {
        BOOL missing = (![name isKindOfClass:[NSString class]] || [name length] == 0);
        BOOL legacyHost = ([name isKindOfClass:[NSString class]] && [name isEqualToString:hostName]);
        if (missing || legacyHost) {
            [updated setObject:nameFromURL forKey:@"name"];
        }
    }

    return updated;
}

- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)sub errorText:(NSString **)errorTextOut {
    return [self updatedSubscriptionDictionaryFromSource:sub errorText:errorTextOut insecureRetryAvailable:NULL];
}

- (BOOL)refreshSubscriptionAtIndex:(NSInteger)idx showStatus:(BOOL)showStatus {
    if (idx < 0 || idx >= (NSInteger)[_subscriptions count]) return NO;

    NSDictionary *sub = [_subscriptions objectAtIndex:idx];
    NSString *errorText = nil;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
    if (![updated isKindOfClass:[NSDictionary class]]) {
        if (showStatus) {
            [self showStatus:([errorText length] > 0 ? errorText : @"Subscription update failed") ok:NO];
            [self showSubscriptionUpdateFailures:[NSArray arrayWithObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]]];
        }
        return NO;
    }

    NSArray *uris = [updated objectForKey:@"items"];
    [_subscriptions replaceObjectAtIndex:idx withObject:updated];
    if (_selectedSubIndex == idx) {
        if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
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

- (BOOL)subscriptionsMatchSnapshotForLaunchAutoUpdate:(NSArray *)snapshot {
    if (![snapshot isKindOfClass:[NSArray class]]) return NO;
    if ((NSInteger)[snapshot count] != (NSInteger)[_subscriptions count]) return NO;

    for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
        NSDictionary *oldSub = [snapshot objectAtIndex:i];
        NSDictionary *curSub = [_subscriptions objectAtIndex:i];
        NSString *oldURL = [oldSub objectForKey:@"url"];
        NSString *curURL = [curSub objectForKey:@"url"];
        if (![oldURL isKindOfClass:[NSString class]]) oldURL = @"";
        if (![curURL isKindOfClass:[NSString class]]) curURL = @"";
        if (![oldURL isEqualToString:curURL]) return NO;
    }
    return YES;
}

- (void)startBackgroundSubscriptionRefreshWithStatus:(NSString *)startStatus {
    if ([_subscriptions count] == 0) {
        if (_pendingImportDoneStatus) {
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        }
        if (_pendingImportRefreshIndices) {
            [_pendingImportRefreshIndices release];
            _pendingImportRefreshIndices = nil;
        }
        [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }
    if (_launchAutoUpdateInProgress) {
        if (_pendingImportDoneStatus) {
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        }
        if (_pendingImportRefreshIndices) {
            [_pendingImportRefreshIndices release];
            _pendingImportRefreshIndices = nil;
        }
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    NSArray *requestedIndices = nil;
    if (_pendingImportRefreshIndices && [_pendingImportRefreshIndices count] > 0) {
        requestedIndices = [_pendingImportRefreshIndices copy];
    }
    [_pendingImportRefreshIndices release];
    _pendingImportRefreshIndices = nil;

    NSArray *snapshot = [[NSArray alloc] initWithArray:_subscriptions copyItems:YES];
    NSMutableArray *refreshIndicesMutable = [NSMutableArray array];
    if ([requestedIndices count] > 0) {
        for (id idxObj in requestedIndices) {
            NSInteger idx = [idxObj integerValue];
            if (idx >= 0 && idx < (NSInteger)[snapshot count]) {
                [refreshIndicesMutable addObject:[NSNumber numberWithInteger:idx]];
            }
        }
    } else {
        for (NSInteger i = 0; i < (NSInteger)[snapshot count]; i++) {
            [refreshIndicesMutable addObject:[NSNumber numberWithInteger:i]];
        }
    }
    [requestedIndices release];

    if ([refreshIndicesMutable count] == 0) {
        if (_pendingImportDoneStatus) {
            [self showStatus:_pendingImportDoneStatus ok:YES];
            [_pendingImportDoneStatus release];
            _pendingImportDoneStatus = nil;
        } else {
            [self showStatus:@"No subscriptions to update" ok:NO];
        }
        [snapshot release];
        return;
    }

    _launchAutoUpdateInProgress = YES;

    NSArray *refreshIndices = [[NSArray alloc] initWithArray:refreshIndicesMutable];
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Updating subscriptions...";
    [self showStatus:startText ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *updatedSubs = [[NSMutableArray alloc] initWithArray:snapshot];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSUInteger okCount = 0;
        for (NSNumber *idxObj in refreshIndices) {
            NSInteger i = [idxObj integerValue];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [self setUpdatingSubscriptionIndex:i];
            });

            NSDictionary *sub = [snapshot objectAtIndex:i];
            NSString *errorText = nil;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
            if (updated) {
                [updatedSubs replaceObjectAtIndex:i withObject:updated];
                okCount++;
            } else {
                [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setUpdatingSubscriptionIndex:-1];
            _launchAutoUpdateInProgress = NO;

            if (![self subscriptionsMatchSnapshotForLaunchAutoUpdate:snapshot]) {
                [self showStatus:@"Auto-update skipped: subscriptions changed" ok:YES];
                if (_pendingImportDoneStatus) {
                    [_pendingImportDoneStatus release];
                    _pendingImportDoneStatus = nil;
                }
                [failureTexts release];
                [updatedSubs release];
                [refreshIndices release];
                [snapshot release];
                return;
            }

            [_subscriptions removeAllObjects];
            [_subscriptions addObjectsFromArray:updatedSubs];

            [self normalizeSelection];
            [self reloadMainTableDataAfterExternalChange];
            [self saveData];

            BOOL ok = okCount > 0;
            if (_pendingImportDoneStatus) {
                [self showStatus:_pendingImportDoneStatus ok:YES];
                [_pendingImportDoneStatus release];
                _pendingImportDoneStatus = nil;
            } else {
	                [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
	                                  (unsigned long)okCount,
	                                  (unsigned long)[refreshIndices count]]
	                         ok:ok];
            }

            if ([failureTexts count] > 0) {
                [self showSubscriptionUpdateFailures:failureTexts];
            }

            [failureTexts release];
            [updatedSubs release];
            [refreshIndices release];
            [snapshot release];
        });

        [pool drain];
    });
}

- (void)startLaunchAutoUpdateIfNeeded {
    if (_didRunLaunchAutoUpdate) return;
    _didRunLaunchAutoUpdate = YES;

    if (!_autoUpdateSubscriptions || [_subscriptions count] == 0) return;

    [self startBackgroundSubscriptionRefreshWithStatus:@"Auto-updating subscriptions in background..."];
}

- (void)refreshAllSubscriptions:(BOOL)showStatus {
    if ([_subscriptions count] == 0) {
        if (showStatus) [self showStatus:@"No subscriptions to update" ok:NO];
        return;
    }

    NSUInteger okCount = 0;
    NSMutableArray *failureTexts = [NSMutableArray array];
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *sub = [_subscriptions objectAtIndex:i];
        NSString *errorText = nil;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub errorText:&errorText];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            NSArray *uris = [updated objectForKey:@"items"];
            [_subscriptions replaceObjectAtIndex:i withObject:updated];
            if (_selectedSubIndex == i) {
                if (![uris isKindOfClass:[NSArray class]] || (NSInteger)[uris count] <= 0) {
                    _selectedSubItemIndex = -1;
                } else if (_selectedSubItemIndex < 0 || _selectedSubItemIndex >= (NSInteger)[uris count]) {
                    _selectedSubItemIndex = 0;
                }
            }
            [self saveData];
            okCount++;
        } else {
            [failureTexts addObject:[self shortUpdateFailureTextForSubscription:sub errorText:errorText]];
        }
    }

    [self normalizeSelection];
    [self reloadMainTableDataAfterExternalChange];

    if (showStatus) {
        BOOL ok = okCount > 0;
        [self showStatus:[NSString stringWithFormat:@"Subscriptions updated: %lu/%lu",
                          (unsigned long)okCount,
                          (unsigned long)[_subscriptions count]]
                     ok:ok];
        if ([failureTexts count] > 0) {
            [self showSubscriptionUpdateFailures:failureTexts];
        }
    }
}

- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)enabled {
    (void)vc;
    _autoUpdateSubscriptions = enabled;
    [self saveData];
    [self showStatus:_autoUpdateSubscriptions ? @"Auto-update subscriptions: ON"
                                           : @"Auto-update subscriptions: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)enabled {
    (void)vc;
    _stealthModeEnabled = enabled;
    [self saveData];
    [_tableView reloadData];
    [self showStatus:_stealthModeEnabled ? @"Stealth mode: ON"
                                   : @"Stealth mode: OFF"
                 ok:YES];
}

- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)enabled {
    (void)vc;
    _darkThemeEnabled = enabled;
    [self saveData];
    [self applyTheme];
}

- (UIView *)accessoryChevronExpanded:(BOOL)expanded {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 20, 20)] autorelease];
    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(2, 2, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];
    return v;
}

- (UIView *)accessorySubscriptionHeaderExpanded:(BOOL)expanded loading:(BOOL)loading {
    if (!loading) {
        return [self accessoryChevronExpanded:expanded];
    }

    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 20)] autorelease];

    UIActivityIndicatorView *spinner =
        [[[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:(VCAppearanceIsDark()
            ? UIActivityIndicatorViewStyleWhite
            : UIActivityIndicatorViewStyleGray)] autorelease];
    spinner.frame = CGRectMake(0, 0, 20, 20);
    spinner.hidesWhenStopped = YES;
    [spinner startAnimating];
    [v addSubview:spinner];

    UIImageView *iv = [[[UIImageView alloc] initWithFrame:CGRectMake(24, 2, 16, 16)] autorelease];
    iv.image = MakeIconImage(expanded ? VCIconTypeChevronDown : VCIconTypeChevronRight, 16.0f, NO);
    [v addSubview:iv];

    return v;
}

- (UIView *)accessoryPingWithTag:(NSInteger)tag selected:(BOOL)selected {
    UIView *v = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 24)] autorelease];

    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(0, 0, 24, 24);
    UIImage *pingIcon = LoadBundledIconTinted(@"icon-ping", 20.0f, VCPrimaryTextColor());
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

- (NSInteger)existingConfigIndexForURI:(NSString *)uri {
    if (![uri isKindOfClass:[NSString class]] || [uri length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_configs count]; i++) {
        NSDictionary *it = [_configs objectAtIndex:i];
        NSString *existingURI = [it objectForKey:@"uri"];
        if ([existingURI isKindOfClass:[NSString class]] && [existingURI isEqualToString:uri]) {
            return i;
        }
    }
    return -1;
}

- (NSInteger)existingSubscriptionIndexForURL:(NSString *)urlString {
    if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) return -1;
    for (NSInteger i = 0; i < (NSInteger)[_subscriptions count]; i++) {
        NSDictionary *it = [_subscriptions objectAtIndex:i];
        NSString *existingURL = [it objectForKey:@"url"];
        if ([existingURL isKindOfClass:[NSString class]] && [existingURL isEqualToString:urlString]) {
            return i;
        }
    }
    return -1;
}

- (NSDictionary *)subscriptionDictionaryForURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    NSString *name = [self subscriptionNameFromURLString:urlString];
    NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                name, @"name",
                                urlString, @"url",
                                [NSArray array], @"items",
                                nil];
    if (allowInsecureFetch) {
        [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
    }
    return sub;
}

- (void)selectSubscriptionAtIndex:(NSInteger)subIndex {
    _subscriptionsSectionExpanded = YES;
    _expandedSubscription = subIndex;
    _selectedConfigIndex = -1;
    _selectedSubIndex = subIndex;
    _selectedSubItemIndex = 0;
    [self normalizeSelection];
    [_tableView reloadData];
}

- (void)showInsecureSubscriptionImportPromptForURLs:(NSArray *)urlStrings fromBatchImport:(BOOL)fromBatchImport {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    [_pendingInsecureImportURLs release];
    _pendingInsecureImportURLs = [cleanURLs copy];

    NSUInteger count = [cleanURLs count];
    NSString *detail = nil;
    if (!fromBatchImport && count == 1) {
        detail = @"This subscription cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for this subscription. Continue?";
    } else {
        detail = @"One of your subscriptions cannot be fetched securely because certificate verification failed. In insecure mode, certificate verification will be disabled only for subscriptions that need it. Continue?";
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Warning"
                                                  message:detail
                                                 delegate:self
                                        cancelButtonTitle:@"No"
                                        otherButtonTitles:@"Yes", nil] autorelease];
    av.tag = VCAlertTagImportInsecureSubscription;
    [av show];
    [self showStatus:((!fromBatchImport && count == 1) ? @"Subscription requires insecure fetch confirmation"
                                                       : @"Some subscriptions require insecure fetch confirmation")
                  ok:NO];
}

- (void)showInsecureSubscriptionImportPromptForURL:(NSString *)urlString {
    [self showInsecureSubscriptionImportPromptForURLs:[NSArray arrayWithObject:urlString] fromBatchImport:NO];
}

- (void)commitUpdatedSubscription:(NSDictionary *)updated existingIndex:(NSInteger)existingIndex {
    if (![updated isKindOfClass:[NSDictionary class]]) return;

    NSArray *uris = [updated objectForKey:@"items"];
    NSInteger subIndex = existingIndex;
    if (existingIndex >= 0 && existingIndex < (NSInteger)[_subscriptions count]) {
        [_subscriptions replaceObjectAtIndex:existingIndex withObject:updated];
    } else {
        [_subscriptions addObject:updated];
        subIndex = [_subscriptions count] - 1;
    }

    [self saveData];
    [self selectSubscriptionAtIndex:subIndex];

    NSString *verb = (existingIndex >= 0) ? @"updated" : @"imported";
    [self showStatus:[NSString stringWithFormat:@"Subscription %@ (%lu configs)",
                      verb,
                      (unsigned long)[uris count]]
                 ok:YES];
}

- (NSString *)subscriptionImportCountText:(NSUInteger)count {
    return [NSString stringWithFormat:@"%lu subscription%@",
            (unsigned long)count,
            (count == 1 ? @"" : @"s")];
}

- (NSString *)shortSubscriptionFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText defaultReason:(NSString *)defaultReason {
    NSString *host = [self hostFromURLString:urlString];
    if (![host isKindOfClass:[NSString class]] || [host length] == 0) {
        host = @"subscription";
    }

    NSString *reason = [self safeTrim:errorText];
    NSString *prefix = @"Subscription fetch failed: ";
    if ([reason hasPrefix:prefix] && [reason length] > [prefix length]) {
        reason = [reason substringFromIndex:[prefix length]];
    }
    if ([reason length] == 0) {
        reason = ([defaultReason isKindOfClass:[NSString class]] && [defaultReason length] > 0)
                     ? defaultReason
                     : @"failed";
    }
    if ([reason length] > 120) {
        reason = [[reason substringToIndex:120] stringByAppendingString:@"..."];
    }

    return [NSString stringWithFormat:@"%@: %@", host, reason];
}

- (NSString *)shortImportFailureTextForURL:(NSString *)urlString errorText:(NSString *)errorText {
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"import failed"];
}

- (NSString *)shortUpdateFailureTextForSubscription:(NSDictionary *)sub errorText:(NSString *)errorText {
    NSString *urlString = [sub objectForKey:@"url"];
    return [self shortSubscriptionFailureTextForURL:urlString errorText:errorText defaultReason:@"update failed"];
}

- (void)showSubscriptionFailureAlertWithTitle:(NSString *)title failureTexts:(NSArray *)failureTexts {
    if (![failureTexts isKindOfClass:[NSArray class]] || [failureTexts count] == 0) return;

    NSMutableString *message = [NSMutableString string];
    NSUInteger limit = MIN((NSUInteger)[failureTexts count], (NSUInteger)5);
    for (NSUInteger i = 0; i < limit; i++) {
        id obj = [failureTexts objectAtIndex:i];
        if (![obj isKindOfClass:[NSString class]] || [(NSString *)obj length] == 0) continue;
        if ([message length] > 0) [message appendString:@"\n"];
        [message appendFormat:@"- %@", (NSString *)obj];
    }
    if ([failureTexts count] > limit) {
        [message appendFormat:@"\n- ... and %lu more", (unsigned long)([failureTexts count] - limit)];
    }

    UIAlertView *av = [[[UIAlertView alloc] initWithTitle:title
                                                  message:message
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil] autorelease];
    [av show];
}

- (void)showSubscriptionImportFailures:(NSArray *)failureTexts {
    [self showSubscriptionFailureAlertWithTitle:@"Some subscriptions were not imported" failureTexts:failureTexts];
}

- (void)showSubscriptionUpdateFailures:(NSArray *)failureTexts {
    NSString *title = ([failureTexts count] == 1) ? @"Subscription was not updated" : @"Some subscriptions were not updated";
    [self showSubscriptionFailureAlertWithTitle:title failureTexts:failureTexts];
}

- (void)startBackgroundSubscriptionImportForURLs:(NSArray *)urlStrings
                              allowInsecureFetch:(BOOL)allowInsecureFetch
                                     startStatus:(NSString *)startStatus
                              importedPrefixPart:(NSString *)importedPrefixPart {
    NSMutableArray *cleanURLs = [NSMutableArray array];
    for (id obj in urlStrings) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *urlString = [self safeTrim:(NSString *)obj];
        if ([urlString length] == 0) continue;
        if (![cleanURLs containsObject:urlString]) {
            [cleanURLs addObject:urlString];
        }
    }

    if ([cleanURLs count] == 0) {
        [self showStatus:@"No subscriptions to import" ok:NO];
        return;
    }

    if (_launchAutoUpdateInProgress) {
        [self showStatus:@"Subscriptions update is already running" ok:YES];
        return;
    }

    _launchAutoUpdateInProgress = YES;
    NSString *startText = ([startStatus isKindOfClass:[NSString class]] && [startStatus length] > 0)
                              ? startStatus
                              : @"Importing subscriptions...";
    [self showStatus:startText ok:YES];

    NSArray *urlsToImport = [[NSArray alloc] initWithArray:cleanURLs];
    NSString *prefixPart = [importedPrefixPart copy];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        NSMutableArray *importedSubs = [[NSMutableArray alloc] init];
        NSMutableArray *insecureURLs = [[NSMutableArray alloc] init];
        NSMutableArray *failureTexts = [[NSMutableArray alloc] init];
        NSUInteger failedCount = 0;

        for (NSString *urlString in urlsToImport) {
            NSDictionary *sub = [self subscriptionDictionaryForURL:urlString allowInsecureFetch:allowInsecureFetch];
            NSString *errorText = nil;
            BOOL insecureRetryAvailable = NO;
            NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                        errorText:&errorText
                                                           insecureRetryAvailable:&insecureRetryAvailable];
            if ([updated isKindOfClass:[NSDictionary class]]) {
                [importedSubs addObject:updated];
            } else if (!allowInsecureFetch && insecureRetryAvailable) {
                [insecureURLs addObject:urlString];
            } else {
                failedCount++;
                [failureTexts addObject:[self shortImportFailureTextForURL:urlString errorText:errorText]];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            _launchAutoUpdateInProgress = NO;

            NSUInteger addedCount = 0;
            NSInteger lastAddedIndex = -1;
            for (NSDictionary *sub in importedSubs) {
                NSString *urlString = [sub objectForKey:@"url"];
                if (![urlString isKindOfClass:[NSString class]] || [urlString length] == 0) continue;
                if ([self existingSubscriptionIndexForURL:urlString] >= 0) continue;

                [_subscriptions addObject:sub];
                addedCount++;
                lastAddedIndex = [_subscriptions count] - 1;
            }

            if (addedCount > 0) {
                [self saveData];
                [self selectSubscriptionAtIndex:lastAddedIndex];
            } else {
                [self normalizeSelection];
                [_tableView reloadData];
            }

            NSMutableArray *parts = [NSMutableArray array];
            if ([prefixPart isKindOfClass:[NSString class]] && [prefixPart length] > 0) {
                [parts addObject:prefixPart];
            }
            if (addedCount > 0) {
                [parts addObject:[self subscriptionImportCountText:addedCount]];
            }

            NSString *status = nil;
            if ([parts count] > 0) {
                status = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            } else {
                status = @"No subscriptions imported";
            }
            if (failedCount > 0) {
                status = [NSString stringWithFormat:@"%@ (failed: %@)",
                          status,
                          [self subscriptionImportCountText:failedCount]];
            }
            if ([insecureURLs count] > 0) {
                status = [NSString stringWithFormat:@"%@; %@ require insecure mode",
                          status,
                          [self subscriptionImportCountText:[insecureURLs count]]];
            }
            [self showStatus:status ok:([parts count] > 0 || [insecureURLs count] > 0)];

            if ([insecureURLs count] > 0) {
                [self showInsecureSubscriptionImportPromptForURLs:insecureURLs
                                                   fromBatchImport:([urlsToImport count] > 1)];
            }
            if ([failureTexts count] > 0) {
                [self showSubscriptionImportFailures:failureTexts];
            }

            [importedSubs release];
            [insecureURLs release];
            [failureTexts release];
            [urlsToImport release];
            [prefixPart release];
        });

        [pool drain];
    });
}

- (void)importDirectURI:(NSString *)uri {
    NSString *normalizedURI = [self safeTrim:uri];
    if (![normalizedURI isKindOfClass:[NSString class]] || [normalizedURI length] == 0) {
        [self showStatus:@"Invalid configuration link" ok:NO];
        return;
    }

    NSInteger existing = [self existingConfigIndexForURI:normalizedURI];
    if (existing >= 0) {
        _configurationsSectionExpanded = YES;
        _selectedConfigIndex = existing;
        _selectedSubIndex = -1;
        _selectedSubItemIndex = -1;
        [self normalizeSelection];
        [_tableView reloadData];
        [self showStatus:@"Configuration already exists (skipped)" ok:YES];
        return;
    }

    NSString *name = [self displayNameForURI:normalizedURI index:[_configs count]];
    NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                         name, @"name",
                         normalizedURI, @"uri",
                         nil];
    [_configs addObject:cfg];
    [self saveData];

    _configurationsSectionExpanded = YES;
    _selectedConfigIndex = [_configs count] - 1;
    _selectedSubIndex = -1;
    _selectedSubItemIndex = -1;
    [_tableView reloadData];
    [self showStatus:@"Configuration imported" ok:YES];
}

- (void)importSubscriptionURL:(NSString *)urlString allowInsecureFetch:(BOOL)allowInsecureFetch {
    NSString *normalizedURL = [self safeTrim:urlString];
    if (![normalizedURL isKindOfClass:[NSString class]] || [normalizedURL length] == 0) {
        [self showStatus:@"Invalid subscription URL" ok:NO];
        return;
    }

    NSInteger existing = [self existingSubscriptionIndexForURL:normalizedURL];
    if (existing >= 0) {
        NSArray *items = [self subscriptionItemsAtIndex:existing];
        if (!allowInsecureFetch && [items count] > 0) {
            [self selectSubscriptionAtIndex:existing];
            [self showStatus:@"Subscription already exists (skipped)" ok:YES];
            return;
        }

        NSMutableDictionary *sub = [NSMutableDictionary dictionaryWithDictionary:[_subscriptions objectAtIndex:existing]];
        [sub setObject:normalizedURL forKey:@"url"];
        if (allowInsecureFetch) {
            [sub setObject:[NSNumber numberWithBool:YES] forKey:kSubscriptionAllowInsecureFetchKey];
        }

        NSString *errorText = nil;
        BOOL insecureRetryAvailable = NO;
        NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                    errorText:&errorText
                                                       insecureRetryAvailable:&insecureRetryAvailable];
        if ([updated isKindOfClass:[NSDictionary class]]) {
            [self commitUpdatedSubscription:updated existingIndex:existing];
            return;
        }

        if (!allowInsecureFetch &&
            !SubscriptionDictionaryAllowsInsecureFetch(sub) &&
            insecureRetryAvailable) {
            [self showInsecureSubscriptionImportPromptForURL:normalizedURL];
            return;
        }

        [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
        return;
    }

    NSDictionary *sub = [self subscriptionDictionaryForURL:normalizedURL allowInsecureFetch:allowInsecureFetch];
    NSString *errorText = nil;
    BOOL insecureRetryAvailable = NO;
    NSDictionary *updated = [self updatedSubscriptionDictionaryFromSource:sub
                                                                errorText:&errorText
                                                   insecureRetryAvailable:&insecureRetryAvailable];
    if ([updated isKindOfClass:[NSDictionary class]]) {
        [self commitUpdatedSubscription:updated existingIndex:-1];
        return;
    }

    if (!allowInsecureFetch && insecureRetryAvailable) {
        [self showInsecureSubscriptionImportPromptForURL:normalizedURL];
        return;
    }

    [self showStatus:([errorText length] > 0 ? errorText : @"Subscription import failed") ok:NO];
}

- (void)importSubscriptionURL:(NSString *)urlString {
    [self importSubscriptionURL:urlString allowInsecureFetch:NO];
}

- (void)importTextEntry:(NSString *)rawText {
    NSString *text = [self safeTrim:rawText];
    if ([text length] == 0) {
        [self showStatus:@"Import text is empty" ok:NO];
        return;
    }

    BOOL hasWhitespace = ([text rangeOfCharacterFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].location != NSNotFound);
    if (!hasWhitespace && [self isDirectConfigURI:text]) {
        [self importDirectURI:text];
        return;
    }

    if (!hasWhitespace && [self isSubscriptionURL:text]) {
        [self importSubscriptionURL:text];
        return;
    }

    NSArray *links = [self extractImportLinksFromText:text];
    if ([links count] > 0) {
        if ([links count] == 1) {
            NSString *single = [links objectAtIndex:0];
            if ([self isDirectConfigURI:single]) {
                [self importDirectURI:single];
            } else if ([self isSubscriptionURL:single]) {
                [self importSubscriptionURL:single];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
            return;
        }

        NSInteger importedConfigs = 0;
        NSInteger pendingSubs = 0;
        NSInteger skippedConfigs = 0;
        NSInteger skippedSubs = 0;
        NSMutableArray *subscriptionURLsToImport = [NSMutableArray array];

        for (NSString *link in links) {
            if ([self isDirectConfigURI:link]) {
                if ([self existingConfigIndexForURI:link] >= 0) {
                    skippedConfigs++;
                    continue;
                }

                NSString *name = [self displayNameForURI:link index:[_configs count]];
                NSDictionary *cfg = [NSDictionary dictionaryWithObjectsAndKeys:
                                     name, @"name",
                                     link, @"uri",
                                     nil];
                [_configs addObject:cfg];
                importedConfigs++;
            } else if ([self isSubscriptionURL:link]) {
                if ([self existingSubscriptionIndexForURL:link] >= 0) {
                    skippedSubs++;
                    continue;
                }

                if (![subscriptionURLsToImport containsObject:link]) {
                    [subscriptionURLsToImport addObject:link];
                    pendingSubs++;
                }
            }
        }

        if (importedConfigs > 0 || pendingSubs > 0) {
            if (importedConfigs > 0) {
                [self saveData];
                _configurationsSectionExpanded = YES;
                _selectedConfigIndex = [_configs count] - 1;
                _selectedSubIndex = -1;
                _selectedSubItemIndex = -1;
                [self normalizeSelection];
                [_tableView reloadData];
            }
        }

        NSMutableArray *parts = [NSMutableArray array];
        if (importedConfigs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld config%@", (long)importedConfigs, (importedConfigs == 1 ? @"" : @"s")]];
        }
        if (pendingSubs > 0) {
            [parts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)pendingSubs, (pendingSubs == 1 ? @"" : @"s")]];
        }

        if ([parts count] > 0) {
            NSString *importText = [NSString stringWithFormat:@"Imported %@", [parts componentsJoinedByString:@", "]];
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                importText = [NSString stringWithFormat:@"%@ (skipped duplicates: %@)",
                              importText,
                              [skippedParts componentsJoinedByString:@", "]];
            }

            if ([subscriptionURLsToImport count] > 0) {
                NSString *configPart = nil;
                if (importedConfigs > 0) {
                    configPart = [NSString stringWithFormat:@"%ld config%@",
                                  (long)importedConfigs,
                                  (importedConfigs == 1 ? @"" : @"s")];
                }
                [self startBackgroundSubscriptionImportForURLs:subscriptionURLsToImport
                                            allowInsecureFetch:NO
                                                   startStatus:@"Importing subscriptions from file..."
                                            importedPrefixPart:configPart];
            } else {
                [self showStatus:importText ok:YES];
            }
        } else {
            if (skippedConfigs > 0 || skippedSubs > 0) {
                NSMutableArray *skippedParts = [NSMutableArray array];
                if (skippedConfigs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld config%@", (long)skippedConfigs, (skippedConfigs == 1 ? @"" : @"s")]];
                }
                if (skippedSubs > 0) {
                    [skippedParts addObject:[NSString stringWithFormat:@"%ld subscription%@", (long)skippedSubs, (skippedSubs == 1 ? @"" : @"s")]];
                }
                [self showStatus:[NSString stringWithFormat:@"Nothing imported: all links already exist (%@)",
                                  [skippedParts componentsJoinedByString:@", "]]
                             ok:YES];
            } else {
                [self showStatus:@"No importable links found" ok:NO];
            }
        }
        return;
    }

    [self showStatus:@"Unsupported import format (use vless://, socks5://, or http(s) subscription)" ok:NO];
}

- (NSString *)decodeImportTextData:(NSData *)data {
    if (!data || [data length] == 0) return nil;

    const unsigned char *bytes = (const unsigned char *)[data bytes];
    NSUInteger len = [data length];

    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding] autorelease];
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    if (!text && len >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        text = [[[NSString alloc] initWithData:data encoding:NSUTF16LittleEndianStringEncoding] autorelease];
    }
    if (!text && len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        text = [[[NSString alloc] initWithData:data encoding:NSUTF16BigEndianStringEncoding] autorelease];
    }
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
    return text;
}

- (void)importTextFileAtPath:(NSString *)rawPath {
    NSString *path = [self safeTrim:rawPath];
    if ([path hasPrefix:@"\""] && [path hasSuffix:@"\""] && [path length] >= 2) {
        path = [path substringWithRange:NSMakeRange(1, [path length] - 2)];
        path = [self safeTrim:path];
    }
    path = [path stringByExpandingTildeInPath];
    if ([path length] == 0) {
        [self showStatus:@"File path is empty" ok:NO];
        return;
    }

    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir];
    if (exists && isDir) {
        [self showStatus:@"Text file not found" ok:NO];
        return;
    }

    [self showStatus:@"Importing data from file..." ok:YES];

    NSData *data = [NSData dataWithContentsOfFile:path];
    if ((!data || [data length] == 0) &&
        [path rangeOfString:@"\n"].location == NSNotFound &&
        [path rangeOfString:@"\r"].location == NSNotFound &&
        [path rangeOfString:@"\t"].location == NSNotFound) {
        NSString *resp = SendCommand([NSString stringWithFormat:@"READFILE\t%@\n", path]);
        if ([resp isKindOfClass:[NSString class]] && [resp hasPrefix:@"OK\t"]) {
            NSString *b64 = [resp substringFromIndex:3];
            b64 = [b64 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSData *decoded = ([b64 length] > 0) ? DecodeBase64String(b64) : [NSData data];
            if (decoded) data = decoded;
        }
    }
    if (!data || [data length] == 0) {
        if (!exists) {
            [self showStatus:@"Text file not found" ok:NO];
            return;
        }
        [self showStatus:@"Failed to read text file" ok:NO];
        return;
    }

    NSString *text = [self decodeImportTextData:data];
    if (![text isKindOfClass:[NSString class]] || [text length] == 0) {
        [self showStatus:@"Unsupported text encoding" ok:NO];
        return;
    }

    [self importTextEntry:text];
}

- (BOOL)isDirectoryPath:(NSString *)path {
    if (![path isKindOfClass:[NSString class]] || [path length] == 0) return NO;
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) return NO;
    return isDir;
}

- (NSArray *)fileBrowserEntriesAtPath:(NSString *)dirPath {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *names = nil;
    if ([self isDirectoryPath:dirPath]) {
        names = [fm contentsOfDirectoryAtPath:dirPath error:nil];
    }
    if (![names isKindOfClass:[NSArray class]]) {
        if ([dirPath rangeOfString:@"\n"].location == NSNotFound &&
            [dirPath rangeOfString:@"\r"].location == NSNotFound &&
            [dirPath rangeOfString:@"\t"].location == NSNotFound) {
            NSString *resp = SendCommand([NSString stringWithFormat:@"LISTDIR\t%@\n", dirPath]);
            if ([resp isKindOfClass:[NSString class]] && [resp hasPrefix:@"OK"]) {
                NSArray *lines = [resp componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                NSMutableArray *dirs = [NSMutableArray array];
                NSMutableArray *files = [NSMutableArray array];

                for (NSInteger i = 1; i < (NSInteger)[lines count]; i++) {
                    id lineObj = [lines objectAtIndex:i];
                    if (![lineObj isKindOfClass:[NSString class]]) continue;
                    NSString *line = (NSString *)lineObj;
                    if ([line length] < 3) continue;
                    unichar kind = [line characterAtIndex:0];
                    if ((kind != 'D' && kind != 'F') || [line characterAtIndex:1] != '\t') continue;

                    NSString *name = [self safeTrim:[line substringFromIndex:2]];
                    if ([name length] == 0 || [name hasPrefix:@"."]) continue;

                    NSString *childPath = [dirPath stringByAppendingPathComponent:name];
                    BOOL childIsDir = (kind == 'D');
                    NSString *title = childIsDir ? [NSString stringWithFormat:@"[DIR] %@", name] : name;
                    NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:
                                          title, @"title",
                                          childPath, @"path",
                                          [NSNumber numberWithBool:childIsDir], @"is_dir",
                                          nil];
                    if (childIsDir) [dirs addObject:item];
                    else [files addObject:item];
                }

                NSArray *sortedDirs = [dirs sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                    NSString *la = [a objectForKey:@"title"];
                    NSString *lb = [b objectForKey:@"title"];
                    if (![la isKindOfClass:[NSString class]]) la = @"";
                    if (![lb isKindOfClass:[NSString class]]) lb = @"";
                    return [la localizedCaseInsensitiveCompare:lb];
                }];
                NSArray *sortedFiles = [files sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                    NSString *la = [a objectForKey:@"title"];
                    NSString *lb = [b objectForKey:@"title"];
                    if (![la isKindOfClass:[NSString class]]) la = @"";
                    if (![lb isKindOfClass:[NSString class]]) lb = @"";
                    return [la localizedCaseInsensitiveCompare:lb];
                }];

                NSMutableArray *out = [NSMutableArray array];
                if (![dirPath isEqualToString:@"/"]) {
                    NSString *parent = [dirPath stringByDeletingLastPathComponent];
                    if ([parent length] == 0) parent = @"/";
                    NSDictionary *up = [NSDictionary dictionaryWithObjectsAndKeys:
                                        @"[..]", @"title",
                                        parent, @"path",
                                        [NSNumber numberWithBool:YES], @"is_dir",
                                        nil];
                    [out addObject:up];
                }
                [out addObjectsFromArray:sortedDirs];
                [out addObjectsFromArray:sortedFiles];

                NSInteger cap = 90;
                if ((NSInteger)[out count] > cap) {
                    return [out subarrayWithRange:NSMakeRange(0, cap)];
                }
                return out;
            }
        }
        return [NSArray array];
    }
    NSArray *sortedNames = [names sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSMutableArray *dirs = [NSMutableArray array];
    NSMutableArray *files = [NSMutableArray array];

    for (id obj in sortedNames) {
        if (![obj isKindOfClass:[NSString class]]) continue;
        NSString *name = (NSString *)obj;
        if ([name hasPrefix:@"."] || [name length] == 0) continue;

        NSString *path = [dirPath stringByAppendingPathComponent:name];
        BOOL childIsDir = NO;
        if (![fm fileExistsAtPath:path isDirectory:&childIsDir]) continue;

        NSString *title = childIsDir ? [NSString stringWithFormat:@"[DIR] %@", name] : name;
        NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:
                              title, @"title",
                              path, @"path",
                              [NSNumber numberWithBool:childIsDir], @"is_dir",
                              nil];
        if (childIsDir) [dirs addObject:item];
        else [files addObject:item];
    }

    NSMutableArray *out = [NSMutableArray array];

    if (![dirPath isEqualToString:@"/"]) {
        NSString *parent = [dirPath stringByDeletingLastPathComponent];
        if ([parent length] == 0) parent = @"/";
        NSDictionary *up = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"[..]", @"title",
                            parent, @"path",
                            [NSNumber numberWithBool:YES], @"is_dir",
                            nil];
        [out addObject:up];
    }

    [out addObjectsFromArray:dirs];
    [out addObjectsFromArray:files];

    NSInteger cap = 90;
    if ((NSInteger)[out count] > cap) {
        return [out subarrayWithRange:NSMakeRange(0, cap)];
    }
    return out;
}

- (void)presentImportFileBrowserAtPath:(NSString *)rawPath {
    NSString *path = [self safeTrim:rawPath];
    if ([path length] == 0) path = @"/var/mobile";

    NSArray *items = [self fileBrowserEntriesAtPath:path];
    if ([items count] == 0) {
        [self showStatus:@"Directory not found or not allowed" ok:NO];
        return;
    }

    [_importBrowserItems release];
    _importBrowserItems = [items copy];

    NSString *title = [NSString stringWithFormat:@"Directory:\n%@", path];
    [self showStatus:[NSString stringWithFormat:@"Current directory: %@", path] ok:YES];

    UIActionSheet *sheet = [[[UIActionSheet alloc] initWithTitle:title
                                                         delegate:self
                                                cancelButtonTitle:nil
                                           destructiveButtonTitle:nil
                                                otherButtonTitles:nil] autorelease];
    for (NSDictionary *item in _importBrowserItems) {
        NSString *t = [item objectForKey:@"title"];
        if (![t isKindOfClass:[NSString class]] || [t length] == 0) t = @"(unnamed)";
        [sheet addButtonWithTitle:t];
    }
    NSInteger cancelIndex = [sheet addButtonWithTitle:@"Cancel"];
    sheet.cancelButtonIndex = cancelIndex;
    sheet.tag = VCActionSheetTagImportFileBrowser;
    [sheet showInView:self.view];
}

- (void)startFileBrowserImportFlow {
    [self presentImportFileBrowserAtPath:@"/var/mobile"];
}

- (void)startQRImportFlow {
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self showStatus:@"Camera is unavailable" ok:NO];
        return;
    }

    QRScanVC *scanner = [[[QRScanVC alloc] init] autorelease];
    scanner.delegate = self;
    scanner.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:scanner animated:YES completion:nil];
    [self showStatus:@"Scan QR code to import links..." ok:YES];
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
    if (![self isSupportedConfigTupleForURI:newURI]) {
        [self showStatus:[self unsupportedConfigStatusTextForURI:newURI] ok:NO];
        return;
    }

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
        [self scheduleXHTTPConnectHealthCheckForURI:newURI];
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
        if (![self isSupportedConfigTupleForURI:uri]) {
            [self showStatus:[self unsupportedConfigStatusTextForURI:uri] ok:NO];
            return;
        }

        NSString *cmd = [NSString stringWithFormat:@"CONNECT\t0\t%@\n", uri];
        NSString *resp = [self sanitizeDaemonText:SendCommand(cmd)];
        if ([resp hasPrefix:@"OK"]) {
            _connected = YES;
            [self startUptimeTimer];
            [self updateConnectButton];
            [self showStatus:@"Connected" ok:YES];
            [self scheduleXHTTPConnectHealthCheckForURI:uri];
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
                                                otherButtonTitles:@"Import from Clipboard", @"Import from File", @"Scan QR Code", @"Manual Input", nil] autorelease];
    sheet.tag = VCActionSheetTagImport;
    [sheet showInView:self.view];
}

- (void)refreshPressed {
    [self startBackgroundSubscriptionRefreshWithStatus:@"Updating subscriptions..."];
}

- (void)settingsPressed {
    SettingsVC *settings = [[[SettingsVC alloc] init] autorelease];
    settings.autoUpdate = _autoUpdateSubscriptions;
    settings.stealthMode = _stealthModeEnabled;
    settings.darkTheme = _darkThemeEnabled;
    settings.delegate = self;

    SettingsNavController *nav = [[[SettingsNavController alloc] initWithRootViewController:settings] autorelease];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)terminalPressed {
    _showingTerminal = !_showingTerminal;

    _tableView.hidden = _showingTerminal;
    _logSelector.hidden = !_showingTerminal;
    _logView.hidden = !_showingTerminal;
    [self updateStickyMainSectionHeader];

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
        [self rememberActiveLogPosition];
        [_logTimer invalidate];
        [_logTimer release];
        _logTimer = nil;
    }

    [self updateTopButtonsIcons];
}

- (CGFloat)maximumLogOffsetY {
    CGFloat maxOffsetY = _logView.contentSize.height - _logView.bounds.size.height;
    return (maxOffsetY > 0.0f) ? maxOffsetY : 0.0f;
}

- (void)rememberActiveLogPosition {
    if (_activeLogIndex < 0 || _activeLogIndex > 1 || !_logView) return;

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    _logContentOffsets[_activeLogIndex] = _logView.contentOffset;
    _logContentOffsetsValid[_activeLogIndex] = YES;
    _logFollowsTail[_activeLogIndex] = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
}

- (void)displayLogText:(NSString *)text
               atIndex:(NSInteger)index
                offset:(CGPoint)savedOffset
            followTail:(BOOL)followTail {
    if (index < 0 || index > 1) return;

    NSString *copiedText = [(text ? text : @"") copy];
    [_logTexts[index] release];
    _logTexts[index] = copiedText;
    _logView.text = _logTexts[index];
    [_logView setNeedsLayout];
    [_logView layoutIfNeeded];

    CGFloat maxOffsetY = [self maximumLogOffsetY];
    CGPoint targetOffset = savedOffset;
    targetOffset.x = 0.0f;
    if (followTail) {
        targetOffset.y = maxOffsetY;
    } else {
        if (targetOffset.y < 0.0f) targetOffset.y = 0.0f;
        if (targetOffset.y > maxOffsetY) targetOffset.y = maxOffsetY;
    }
    [_logView setContentOffset:targetOffset animated:NO];

    _logContentOffsets[index] = _logView.contentOffset;
    _logContentOffsetsValid[index] = YES;
    _logFollowsTail[index] = followTail || maxOffsetY <= 0.0f;
}

- (void)updateLogSelectorAnimated:(BOOL)animated {
    if (!_logSelector || !_logSelectionIndicator) return;

    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = _logSelectorButtons[i];
        [button setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
        [button setTitleColor:VCAccentColor() forState:UIControlStateSelected];
        [button setTitleColor:VCPrimaryTextColor() forState:UIControlStateHighlighted];
        button.selected = (i == _activeLogIndex);
    }

    _logSelectionIndicator.backgroundColor = VCAccentColor();
    CGFloat segmentWidth = _logSelector.bounds.size.width * 0.5f;
    CGRect indicatorFrame = _logSelectionIndicator.frame;
    indicatorFrame.origin.x = segmentWidth * _activeLogIndex + (segmentWidth - indicatorFrame.size.width) * 0.5f;
    void (^updates)(void) = ^{
        _logSelectionIndicator.frame = indicatorFrame;
    };
    if (animated) {
        [UIView animateWithDuration:0.16 animations:updates];
    } else {
        updates();
    }
}

- (void)logSourceChanged:(UIButton *)sender {
    NSInteger newIndex = sender.tag;
    if (newIndex < 0 || newIndex > 1 || newIndex == _activeLogIndex) return;

    [self rememberActiveLogPosition];
    _activeLogIndex = newIndex;
    [self updateLogSelectorAnimated:YES];

    CGPoint savedOffset = _logContentOffsetsValid[newIndex]
        ? _logContentOffsets[newIndex]
        : CGPointZero;
    BOOL followTail = _logContentOffsetsValid[newIndex]
        ? _logFollowsTail[newIndex]
        : YES;
    [self displayLogText:ReadLogAtIndex(newIndex)
                 atIndex:newIndex
                  offset:savedOffset
              followTail:followTail];
}

- (void)refreshLogs {
    if (!_showingTerminal || _activeLogIndex < 0 || _activeLogIndex > 1) {
        return;
    }
    if (_logView.tracking || _logView.dragging || _logView.decelerating ||
        _logView.selectedRange.length > 0) {
        return;
    }

    NSString *newText = ReadLogAtIndex(_activeLogIndex);
    NSString *oldText = _logTexts[_activeLogIndex] ? _logTexts[_activeLogIndex] : @"";
    if ([newText isEqualToString:oldText]) {
        return;
    }

    CGPoint savedOffset = _logView.contentOffset;
    CGFloat maxOffsetY = [self maximumLogOffsetY];
    BOOL wasNearBottom = (_logView.contentOffset.y >= (maxOffsetY - 20.0f));
    [self displayLogText:newText
                 atIndex:_activeLogIndex
                  offset:savedOffset
              followTail:wasNearBottom];
}

- (void)forceRefreshLogs {
    for (NSInteger i = 0; i < 2; i++) {
        [_logTexts[i] release];
        _logTexts[i] = nil;
        _logContentOffsets[i] = CGPointZero;
        _logContentOffsetsValid[i] = NO;
        _logFollowsTail[i] = YES;
    }
    [self displayLogText:ReadLogAtIndex(_activeLogIndex)
                 atIndex:_activeLogIndex
                  offset:CGPointZero
              followTail:NO];
}

- (void)clearLogsPressed {
    NSString *resp = [self sanitizeDaemonText:ClearLogsViaDaemon()];
    [self forceRefreshLogs];

    if ([resp hasPrefix:@"OK"]) {
        [self showStatus:@"Logs cleared" ok:YES];
    } else {
        NSString *msg = ([resp length] > 0) ? resp : @"Failed to clear logs";
        [self showStatus:msg ok:NO];
    }
}

- (void)refreshLogsTick:(NSTimer *)timer {
    (void)timer;
    [self refreshLogs];
}

- (void)queryInitialStatus {
    [self showStatus:@"Checking daemon..." ok:YES];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *resp = [self sanitizeDaemonText:SendCommand(@"STATUS\n")];
        BOOL connectedNow = [resp hasPrefix:@"OK connected"];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (connectedNow) {
                _connected = YES;
                [self startUptimeTimer];
                [self showStatus:@"Connected" ok:YES];
            } else {
                _connected = NO;
                [self stopUptimeTimer];
                [self showStatus:@"Ready" ok:YES];
            }
            [self updateConnectButton];
        });
        [pool drain];
    });
}

- (void)applyTheme {
    _darkThemeEnabled = VCAppearanceIsDark();
    UIColor *background = VCBackgroundColor();
    self.view.backgroundColor = background;
    _titleLabel.textColor = VCPrimaryTextColor();
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _statusLabel.textColor = _statusOK ? VCSuccessColor() : VCErrorColor();
    [self updateLogSelectorAnimated:NO];
    _logView.backgroundColor = background;
    _logView.textColor = VCPrimaryTextColor();
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    VCAppearanceApplyTable(_tableView);
    VCAppearanceApplyStatusBar();

    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self updateTopButtonsIcons];
    [_tableView reloadData];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    [self loadData];

    CGRect b = self.view.bounds;
    UIColor *bg = VCBackgroundColor();
    self.view.backgroundColor = bg;

    CGFloat topY = 10.0f;
    CGFloat iconW = 28.0f;
    CGFloat gap = 6.0f;
    CGFloat right = b.size.width - 12.0f;

    CGFloat settingsX = right - iconW;
    CGFloat refreshX = settingsX - gap - iconW;
    CGFloat terminalX = refreshX - gap - iconW;
    CGFloat plusX = terminalX - gap - iconW;
    CGFloat clearLogsY = topY + iconW + gap;

    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 6, plusX - 20, 28)];
    _titleLabel.text = @"vless-core";
    _titleLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    _titleLabel.textColor = VCPrimaryTextColor();
    _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_titleLabel];

    _plusBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _plusBtn.frame = CGRectMake(plusX, topY, iconW, iconW);
    _plusBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_plusBtn addTarget:self action:@selector(plusPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_plusBtn];
    [self.view addSubview:_plusBtn];

    _terminalBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _terminalBtn.frame = CGRectMake(terminalX, topY, iconW, iconW);
    _terminalBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_terminalBtn addTarget:self action:@selector(terminalPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_terminalBtn];
    [self.view addSubview:_terminalBtn];

    _clearLogsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _clearLogsBtn.frame = CGRectMake(settingsX, clearLogsY, iconW, iconW);
    _clearLogsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _clearLogsBtn.hidden = YES;
    [_clearLogsBtn addTarget:self action:@selector(clearLogsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_clearLogsBtn];
    [self.view addSubview:_clearLogsBtn];

    _refreshBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _refreshBtn.frame = CGRectMake(refreshX, topY, iconW, iconW);
    _refreshBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_refreshBtn addTarget:self action:@selector(refreshPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_refreshBtn];
    [self.view addSubview:_refreshBtn];

    _settingsBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _settingsBtn.frame = CGRectMake(settingsX, topY, iconW, iconW);
    _settingsBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [_settingsBtn addTarget:self action:@selector(settingsPressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTopButtonFeedbackToButton:_settingsBtn];
    [self.view addSubview:_settingsBtn];

    CGFloat btnSize = 122.0f;
    _connectBtn = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _connectBtn.frame = CGRectMake((b.size.width - btnSize) * 0.5f, 60.0f, btnSize, btnSize);
    _connectBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20.0f];
    _connectBtn.layer.cornerRadius = btnSize * 0.5f;
    _connectBtn.layer.borderWidth = 2.0f;
    _connectBtn.layer.borderColor = [UIColor colorWithWhite:1.0f alpha:0.95f].CGColor;
    _connectBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_connectBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_connectBtn addTarget:self action:@selector(togglePressed) forControlEvents:UIControlEventTouchUpInside];
    [self applyTouchFeedbackToButton:_connectBtn];
    [self.view addSubview:_connectBtn];

    _uptimeLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 190, b.size.width - 32, 20)];
    _uptimeLabel.font = [UIFont boldSystemFontOfSize:13.0f];
    _uptimeLabel.text = @"00:00:00";
    _uptimeLabel.textColor = VCPrimaryTextColor();
    _uptimeLabel.textAlignment = NSTextAlignmentCenter;
    _uptimeLabel.backgroundColor = [UIColor clearColor];
    _uptimeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_uptimeLabel];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 216, b.size.width - 32, 30)];
    _statusLabel.font = [UIFont systemFontOfSize:12.5f];
    _statusLabel.numberOfLines = 2;
    _statusLabel.text = @"Ready";
    _statusOK = YES;
    _statusLabel.backgroundColor = [UIColor clearColor];
    _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_statusLabel];

    CGFloat listY = 246.0f;
    CGFloat listH = b.size.height - listY;
    if (listH < 120.0f) listH = 120.0f;

    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, listY, b.size.width, listH) style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.opaque = YES;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    _tableView.tableFooterView = footer;
    [self.view addSubview:_tableView];

    CGFloat logSelectorWidth = 188.0f;
    if (logSelectorWidth > b.size.width - 24.0f) logSelectorWidth = b.size.width - 24.0f;
    _logSelector = [[UIView alloc] initWithFrame:CGRectZero];
    _logSelector.frame = CGRectMake((b.size.width - logSelectorWidth) * 0.5f,
                                    listY + 2.0f,
                                    logSelectorWidth,
                                    28.0f);
    _logSelector.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                    UIViewAutoresizingFlexibleRightMargin;
    _logSelector.backgroundColor = [UIColor clearColor];
    _logSelector.hidden = YES;

    NSArray *logTitles = [NSArray arrayWithObjects:@"vpnctld", @"vless-core", nil];
    CGFloat logButtonWidth = logSelectorWidth * 0.5f;
    for (NSInteger i = 0; i < 2; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        button.frame = CGRectMake(logButtonWidth * i, 0.0f, logButtonWidth, 26.0f);
        button.tag = i;
        button.titleLabel.font = [UIFont systemFontOfSize:12.0f];
        [button setTitle:[logTitles objectAtIndex:i] forState:UIControlStateNormal];
        [button addTarget:self
                   action:@selector(logSourceChanged:)
         forControlEvents:UIControlEventTouchUpInside];
        _logSelectorButtons[i] = button;
        [_logSelector addSubview:button];
    }

    _logSelectionIndicator = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 26.0f, 32.0f, 2.0f)];
    _logSelectionIndicator.layer.cornerRadius = 1.0f;
    [_logSelector addSubview:_logSelectionIndicator];
    [self.view addSubview:_logSelector];

    _activeLogIndex = 0;
    _logFollowsTail[0] = YES;
    _logFollowsTail[1] = YES;
    [self updateLogSelectorAnimated:NO];
    CGRect logFrame = CGRectMake(0.0f, listY + 32.0f, b.size.width, listH - 32.0f);
    _logView = [[UITextView alloc] initWithFrame:logFrame];
    _logView.editable = NO;
    _logView.font = [UIFont systemFontOfSize:10.0f];
    _logView.backgroundColor = bg;
    _logView.textColor = VCPrimaryTextColor();
    _logView.indicatorStyle = VCAppearanceIsDark() ? UIScrollViewIndicatorStyleWhite
                                                    : UIScrollViewIndicatorStyleDefault;
    _logView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logView.hidden = YES;
    _logView.text = @"";
    _logView.delegate = self;
    [self.view addSubview:_logView];

    [self updateConnectButton];
    [self applyTheme];
    [self queryInitialStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startLaunchAutoUpdateIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateStickyMainSectionHeader];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (NSUInteger)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    if (IsPadDevice()) {
        UIInterfaceOrientation current = CurrentInterfaceOrientation();
        if (current == UIInterfaceOrientationPortraitUpsideDown) {
            return UIInterfaceOrientationPortrait;
        }
        return current;
    }
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
    [_clearLogsBtn release];
    [_refreshBtn release];
    [_settingsBtn release];
    [_statusLabel release];
    [_uptimeLabel release];
    [_titleLabel release];

    [_tableView release];
    [_logSelector release];
    [_logSelectionIndicator release];
    [_logView release];
    [_logTexts[0] release];
    [_logTexts[1] release];
    [_stickySectionHeaderView release];
    [_importBrowserItems release];
    [_pendingImportDoneStatus release];
    [_pendingImportRefreshIndices release];
    [_pendingInsecureImportURLs release];

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
    if (section == 0) {
        return _configurationsSectionExpanded ? [_configs count] : 0;
    }
    return _subscriptionsSectionExpanded ? [self subscriptionSectionRowCount] : 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return (section == 0) ? @"Configurations" : @"Subscriptions";
}

- (void)mainSectionHeaderPressed:(UIButton *)sender {
    NSInteger section = sender.tag - kVCMainSectionHeaderButtonTagBase;
    if (section < 0 || section > 1) return;
    NSInteger oldRowCount = [_tableView numberOfRowsInSection:section];

    if (section == 0) {
        _configurationsSectionExpanded = !_configurationsSectionExpanded;
    } else {
        _subscriptionsSectionExpanded = !_subscriptionsSectionExpanded;
    }
    NSInteger newRowCount = [self tableView:_tableView numberOfRowsInSection:section];

    NSUInteger transitionToken = ++_mainSectionTransitionToken;
    NSNumber *transitionNumber = [NSNumber numberWithUnsignedInteger:transitionToken];
    _mainSectionTransitionInProgress = YES;
    [CATransaction begin];

    [self updateMainSectionHeaderButton:sender section:section animated:YES];

    UIButton *normalButton = (UIButton *)[_tableView viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
    if (normalButton != sender) {
        [self updateMainSectionHeaderButton:normalButton section:section animated:YES];
    }
    if (_stickySectionHeaderSection == section) {
        UIButton *stickyButton = (UIButton *)[_stickySectionHeaderView viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
        if (stickyButton != sender && stickyButton != normalButton) {
            [self updateMainSectionHeaderButton:stickyButton section:section animated:YES];
        }
    }

    [CATransaction setCompletionBlock:^{
        [self finishMainSectionTransition:transitionNumber];
    }];

    NSMutableArray *changedRows = [NSMutableArray array];
    NSInteger changedRowCount = (newRowCount > oldRowCount) ? newRowCount : oldRowCount;
    for (NSInteger row = 0; row < changedRowCount; row++) {
        [changedRows addObject:[NSIndexPath indexPathForRow:row inSection:section]];
    }

    @try {
        if (newRowCount > oldRowCount) {
            [_tableView insertRowsAtIndexPaths:changedRows withRowAnimation:UITableViewRowAnimationFade];
        } else if (oldRowCount > newRowCount) {
            [_tableView deleteRowsAtIndexPaths:changedRows withRowAnimation:UITableViewRowAnimationFade];
        }
    } @catch (NSException *exception) {
        (void)exception;
        [self reloadMainTableDataAfterExternalChange];
    }
    [CATransaction commit];
    [self performSelector:@selector(finishMainSectionTransition:)
               withObject:transitionNumber
               afterDelay:0.35];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return kVCMainSectionHeaderHeight;
}

- (UIView *)mainSectionHeaderViewForTable:(UITableView *)tableView section:(NSInteger)section {
    CGFloat width = tableView.bounds.size.width;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0.0f,
                                                               0.0f,
                                                               width,
                                                               kVCMainSectionHeaderHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];

    BOOL expanded = (section == 0) ? _configurationsSectionExpanded : _subscriptionsSectionExpanded;
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(10.0f, 5.0f, width - 20.0f, 36.0f);
    button.tag = kVCMainSectionHeaderButtonTagBase + section;
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    button.contentEdgeInsets = UIEdgeInsetsMake(0.0f, 14.0f, 0.0f, 104.0f);
    button.titleLabel.font = [UIFont boldSystemFontOfSize:15.0f];
    [button setTitle:[self tableView:tableView titleForHeaderInSection:section] forState:UIControlStateNormal];
    [button setTitleColor:VCSecondaryTextColor() forState:UIControlStateNormal];
    [button setTitleColor:VCPrimaryTextColor() forState:UIControlStateHighlighted];
    [button setTitleShadowColor:(VCAppearanceIsDark() ? [UIColor clearColor]
                                                       : [UIColor colorWithWhite:1.0f alpha:0.85f])
                       forState:UIControlStateNormal];
    button.titleLabel.shadowOffset = VCAppearanceIsDark() ? CGSizeZero : CGSizeMake(0.0f, 1.0f);
    [button setBackgroundImage:SolidImageWithColor(VCCellBackgroundColor()) forState:UIControlStateNormal];
    [button setBackgroundImage:SolidImageWithColor(VCSelectedCellColor()) forState:UIControlStateHighlighted];
    button.layer.cornerRadius = 7.0f;
    button.layer.borderWidth = 1.0f;
    button.layer.borderColor = VCSeparatorColor().CGColor;
    button.layer.masksToBounds = YES;
    button.accessibilityLabel = (section == 0) ? @"Configurations" : @"Subscriptions";
    button.accessibilityValue = expanded ? @"Expanded" : @"Collapsed";
    button.accessibilityHint = expanded ? @"Double tap to collapse" : @"Double tap to expand";
    [button addTarget:self action:@selector(mainSectionHeaderPressed:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *countLabel = [[[UILabel alloc] initWithFrame:CGRectMake(button.bounds.size.width - 88.0f,
                                                                      7.0f,
                                                                      42.0f,
                                                                      22.0f)] autorelease];
    countLabel.tag = kVCMainSectionHeaderCountTagBase + section;
    countLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    countLabel.backgroundColor = VCAppearanceIsDark()
        ? [UIColor colorWithWhite:0.24f alpha:1.0f]
        : [UIColor colorWithWhite:0.90f alpha:1.0f];
    countLabel.textColor = VCSecondaryTextColor();
    countLabel.font = [UIFont boldSystemFontOfSize:12.0f];
    countLabel.textAlignment = NSTextAlignmentCenter;
    countLabel.adjustsFontSizeToFitWidth = YES;
    countLabel.minimumScaleFactor = 0.67f;
    countLabel.layer.cornerRadius = 11.0f;
    countLabel.layer.masksToBounds = YES;
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
    [button addSubview:countLabel];

    UIImageView *chevron = [[[UIImageView alloc] initWithFrame:CGRectMake(button.bounds.size.width - 30.0f,
                                                                          10.0f,
                                                                          16.0f,
                                                                          16.0f)] autorelease];
    chevron.tag = kVCMainSectionHeaderChevronTagBase + section;
    chevron.image = TintImageWithColor(MakeIconImage(expanded ? VCIconTypeChevronDown
                                                              : VCIconTypeChevronRight,
                                                     16.0f,
                                                     NO),
                                        VCSecondaryTextColor());
    chevron.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                               UIViewAutoresizingFlexibleTopMargin |
                               UIViewAutoresizingFlexibleBottomMargin;
    [button addSubview:chevron];
    [header addSubview:button];
    VCAppearanceApplyHeaderView(header);
    return header;
}

- (void)updateMainSectionHeaderButton:(UIButton *)button section:(NSInteger)section animated:(BOOL)animated {
    if (!button || section < 0 || section > 1) return;

    BOOL expanded = [self isMainSectionExpanded:section];
    button.accessibilityValue = expanded ? @"Expanded" : @"Collapsed";
    button.accessibilityHint = expanded ? @"Double tap to collapse" : @"Double tap to expand";

    UILabel *countLabel = (UILabel *)[button viewWithTag:(kVCMainSectionHeaderCountTagBase + section)];
    NSUInteger count = (section == 0) ? [_configs count] : [_subscriptions count];
    countLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];

    UIImageView *chevron = (UIImageView *)[button viewWithTag:(kVCMainSectionHeaderChevronTagBase + section)];
    UIImage *image = TintImageWithColor(MakeIconImage(expanded ? VCIconTypeChevronDown
                                                               : VCIconTypeChevronRight,
                                                      16.0f,
                                                      NO),
                                         VCSecondaryTextColor());
    if (animated) {
        [UIView transitionWithView:chevron
                          duration:0.16
                           options:(UIViewAnimationOptionTransitionCrossDissolve |
                                    UIViewAnimationOptionBeginFromCurrentState)
                        animations:^{
                            chevron.image = image;
                        }
                        completion:nil];
    } else {
        chevron.image = image;
    }
}

- (void)updateMainSectionHeaderView:(UIView *)header section:(NSInteger)section animated:(BOOL)animated {
    if (!header || section < 0 || section > 1) return;

    UIButton *button = (UIButton *)[header viewWithTag:(kVCMainSectionHeaderButtonTagBase + section)];
    [self updateMainSectionHeaderButton:button section:section animated:animated];
}

- (void)finishMainSectionTransition:(NSNumber *)transitionNumber {
    if ([transitionNumber unsignedIntegerValue] != _mainSectionTransitionToken) return;
    if (!_mainSectionTransitionInProgress) return;

    _mainSectionTransitionInProgress = NO;
    [_tableView layoutIfNeeded];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (void)reloadMainTableDataAfterExternalChange {
    _mainSectionTransitionToken++;
    _mainSectionTransitionInProgress = NO;
    [_tableView reloadData];
    [_tableView layoutIfNeeded];
    VCAppearanceRefreshVisibleTableHeaders(_tableView);
    [self refreshStickyMainSectionHeader];
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return [self mainSectionHeaderViewForTable:tableView section:section];
}

- (BOOL)isMainSectionExpanded:(NSInteger)section {
    if (section == 0) return _configurationsSectionExpanded;
    if (section == 1) return _subscriptionsSectionExpanded;
    return NO;
}

- (void)removeStickyMainSectionHeader {
    [_stickySectionHeaderView removeFromSuperview];
    [_stickySectionHeaderView release];
    _stickySectionHeaderView = nil;
    _stickySectionHeaderSection = -1;
}

- (void)layoutStickyMainSectionHeader {
    if (!_stickySectionHeaderView || !_tableView) return;

    _stickySectionHeaderView.frame = CGRectMake(_tableView.frame.origin.x,
                                                 _tableView.frame.origin.y,
                                                 _tableView.frame.size.width,
                                                 kVCMainSectionHeaderHeight);
    [self.view bringSubviewToFront:_stickySectionHeaderView];
}

- (NSInteger)stickyMainSectionForCurrentOffset {
    if (!_tableView || _showingTerminal || _tableView.hidden) return -1;

    CGFloat top = _tableView.contentOffset.y;
    NSInteger stickySection = -1;
    for (NSInteger section = 0; section < 2; section++) {
        if (![self isMainSectionExpanded:section]) continue;
        CGRect headerRect = [_tableView rectForHeaderInSection:section];
        if (top > CGRectGetMinY(headerRect)) {
            stickySection = section;
        }
    }
    return stickySection;
}

- (void)updateStickyMainSectionHeader {
    if (_mainSectionTransitionInProgress) {
        [self layoutStickyMainSectionHeader];
        return;
    }

    NSInteger section = [self stickyMainSectionForCurrentOffset];
    if (section < 0) {
        [self removeStickyMainSectionHeader];
        return;
    }

    if (_stickySectionHeaderView && _stickySectionHeaderSection == section) {
        [self updateMainSectionHeaderView:_stickySectionHeaderView section:section animated:NO];
        [self layoutStickyMainSectionHeader];
        return;
    }

    [self removeStickyMainSectionHeader];
    _stickySectionHeaderView = [[self mainSectionHeaderViewForTable:_tableView section:section] retain];
    _stickySectionHeaderView.backgroundColor = VCBackgroundColor();
    _stickySectionHeaderView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _stickySectionHeaderSection = section;
    [self.view addSubview:_stickySectionHeaderView];
    [self layoutStickyMainSectionHeader];
}

- (void)refreshStickyMainSectionHeader {
    [self removeStickyMainSectionHeader];
    [self updateStickyMainSectionHeader];
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

- (void)applyMarqueeDetailForMainCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    if (!cell || !indexPath) return;

    if (indexPath.section == 0) {
        if (indexPath.row < 0 || indexPath.row >= (NSInteger)[_configs count]) {
            [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
            return;
        }
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *uri = [cfg objectForKey:@"uri"];
        NSString *prefix = [self configPrefixTextFromURI:uri];
        NSString *tail = [self configEndpointTextFromURI:uri];
        [self applyDetailPrefix:prefix
                    prefixColor:[self configPrefixColorForURI:uri]
                    marqueeTail:tail
                         toCell:cell];
        return;
    }

    NSInteger subIdx = -1;
    NSInteger itemIdx = -1;
    BOOL isHeader = YES;
    if (![self mapSubscriptionRow:indexPath.row toSubIndex:&subIdx itemIndex:&itemIdx isHeader:&isHeader]) {
        [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
        return;
    }

    NSDictionary *sub = [_subscriptions objectAtIndex:subIdx];
    if (isHeader) {
        NSArray *items = [self subscriptionItemsAtIndex:subIdx];
        NSString *url = [sub objectForKey:@"url"];
        NSString *shownURL = [self maskedLinkText:(url ? url : @"")];
        NSString *prefix = [NSString stringWithFormat:@"%lu configs •", (unsigned long)[items count]];
        [self applyDetailPrefix:prefix marqueeTail:shownURL toCell:cell];
        return;
    }

    NSArray *items = [self subscriptionItemsAtIndex:subIdx];
    if (itemIdx < 0 || itemIdx >= (NSInteger)[items count]) {
        [self applyDetailPrefix:@"" marqueeTail:@"" toCell:cell];
        return;
    }

    NSString *uri = [items objectAtIndex:itemIdx];
    NSString *prefix = [self configPrefixTextFromURI:uri];
    NSString *tail = [self configEndpointTextFromURI:uri];
    [self applyDetailPrefix:prefix
                prefixColor:[self configPrefixColorForURI:uri]
                marqueeTail:tail
                     toCell:cell];
}

- (void)runQueuedMainMarqueeRelayout {
    _queuedMainMarqueeRelayout = NO;
    if (!_tableView || _showingTerminal) return;

    NSArray *visible = [_tableView indexPathsForVisibleRows];
    for (NSIndexPath *ip in visible) {
        UITableViewCell *visibleCell = [_tableView cellForRowAtIndexPath:ip];
        if (visibleCell) {
            [self applyMarqueeDetailForMainCell:visibleCell atIndexPath:ip];
        }
    }
}

- (void)scheduleMainMarqueeRelayout {
    if (_queuedMainMarqueeRelayout) return;
    _queuedMainMarqueeRelayout = YES;
    [self performSelector:@selector(runQueuedMainMarqueeRelayout) withObject:nil afterDelay:0.0];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCellId = @"VCItemCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellId] autorelease];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:11.0f];
    }
    cell.clipsToBounds = YES;
    cell.contentView.clipsToBounds = YES;
    cell.indentationLevel = 0;
    cell.indentationWidth = 14.0f;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    VCAppearanceApplyCell(cell);

    if (indexPath.section == 0) {
        NSDictionary *cfg = [_configs objectAtIndex:indexPath.row];
        NSString *name = [cfg objectForKey:@"name"];
        NSString *shownConfigName = ([name length] > 0) ? name : [NSString stringWithFormat:@"Config %ld", (long)(indexPath.row + 1)];
        cell.textLabel.text = [self maskedLinkText:shownConfigName];
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

            if (isHeader) {
                NSString *shownName = ([name length] > 0) ? name : @"";
                NSString *host = [self hostFromURLString:url];
                if ([shownName length] == 0 || [shownName isEqualToString:host]) {
                    shownName = [self subscriptionNameFromURLString:url];
                }
                shownName = [self maskedLinkText:shownName];
                cell.textLabel.text = shownName;
                BOOL loading = (_updatingSubscriptionIndex == subIdx);
                cell.accessoryView = [self accessorySubscriptionHeaderExpanded:(_expandedSubscription == subIdx)
                                                                       loading:loading];
            } else {
                NSString *uri = [items objectAtIndex:itemIdx];
                cell.indentationLevel = 0;
                NSString *itemName = [self displayNameForURI:uri index:itemIdx];
                cell.textLabel.text = [self maskedLinkText:itemName];
                NSInteger tag = 20000 + (subIdx * 1000) + itemIdx;
                BOOL selected = (_selectedSubIndex == subIdx && _selectedSubItemIndex == itemIdx);
                cell.accessoryView = [self accessoryPingWithTag:tag selected:selected];
            }
        } else {
            cell.textLabel.text = @"(invalid row)";
        }
    }

    [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainMarqueeRelayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCAppearanceApplyCell(cell);
    [self applyMarqueeDetailForMainCell:cell atIndexPath:indexPath];
    [self scheduleMainMarqueeRelayout];
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    [self updateMainSectionHeaderView:view section:section animated:NO];
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
    [self updateStickyMainSectionHeader];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self updateStickyMainSectionHeader];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == _tableView) {
        [self scheduleMainMarqueeRelayout];
    } else if (scrollView == _logView) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (scrollView == _tableView && !decelerate) {
        [self scheduleMainMarqueeRelayout];
    } else if (scrollView == _logView && !decelerate) {
        [self rememberActiveLogPosition];
        [self refreshLogs];
    }
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
            [self startFileBrowserImportFlow];
        } else if (buttonIndex == 2) {
            [self startQRImportFlow];
        } else if (buttonIndex == 3) {
            UIAlertView *av = [[[UIAlertView alloc] initWithTitle:@"Manual Import"
                                                          message:@"Paste vless://, socks5://, or subscription URL"
                                                         delegate:self
                                                cancelButtonTitle:@"Cancel"
                                                otherButtonTitles:@"Import", nil] autorelease];
            av.alertViewStyle = UIAlertViewStylePlainTextInput;
            av.tag = VCAlertTagImportManual;

            UITextField *tf = [av textFieldAtIndex:0];
            tf.placeholder = @"vless://..., socks5://..., or https://...";
            tf.clearButtonMode = UITextFieldViewModeWhileEditing;
            tf.keyboardType = UIKeyboardTypeURL;
            tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
            tf.autocorrectionType = UITextAutocorrectionTypeNo;

            [av show];
        }
        return;
    }

    if (actionSheet.tag == VCActionSheetTagImportFileBrowser) {
        NSDictionary *selectedItem = nil;
        if (buttonIndex >= 0 &&
            buttonIndex != actionSheet.cancelButtonIndex &&
            buttonIndex < (NSInteger)[_importBrowserItems count]) {
            id obj = [_importBrowserItems objectAtIndex:buttonIndex];
            if ([obj isKindOfClass:[NSDictionary class]]) {
                selectedItem = [obj retain];
            }
        }
        [_importBrowserItems release];
        _importBrowserItems = nil;

        if (selectedItem) {
            NSString *path = [[selectedItem objectForKey:@"path"] copy];
            BOOL isDir = [[selectedItem objectForKey:@"is_dir"] boolValue];
            [selectedItem release];
            if (isDir) {
                [self presentImportFileBrowserAtPath:path];
            } else {
                [self importTextFileAtPath:path];
            }
            [path release];
        }
        return;
    }
}

- (void)qrScanVCDidCancel:(UIViewController *)vc {
    (void)vc;
    [self dismissViewControllerAnimated:YES completion:nil];
    [self showStatus:@"QR import canceled" ok:YES];
}

- (void)qrScanVC:(UIViewController *)vc didScanText:(NSString *)text {
    (void)vc;
    NSString *payload = [self safeTrim:text];
    [self dismissViewControllerAnimated:YES completion:nil];
    if (![payload isKindOfClass:[NSString class]] || [payload length] == 0) {
        [self showStatus:@"QR code does not contain import data" ok:NO];
        return;
    }

    NSArray *links = [self extractImportLinksFromText:payload];
    if ([links isKindOfClass:[NSArray class]] && [links count] > 0) {
        NSString *subscriptionURL = nil;
        for (NSString *candidate in links) {
            if ([self isSubscriptionURL:candidate]) {
                subscriptionURL = candidate;
                break;
            }
        }
        if ([subscriptionURL isKindOfClass:[NSString class]] && [subscriptionURL length] > 0) {
            [self importSubscriptionURL:subscriptionURL];
            return;
        }

        if ([links count] == 1) {
            NSString *single = [links objectAtIndex:0];
            [self importTextEntry:single];
            return;
        }
    }

    [self importTextEntry:payload];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (alertView.tag == VCAlertTagImportManual) {
        if (buttonIndex != 1) return;
        NSString *txt = [[alertView textFieldAtIndex:0] text];
        [self importTextEntry:txt];
        return;
    }

    if (alertView.tag == VCAlertTagImportInsecureSubscription) {
        NSArray *urlStrings = [_pendingInsecureImportURLs retain];
        [_pendingInsecureImportURLs release];
        _pendingInsecureImportURLs = nil;

        if (buttonIndex == 1) {
            if ([urlStrings count] == 1) {
                NSString *urlString = [urlStrings objectAtIndex:0];
                [self importSubscriptionURL:urlString allowInsecureFetch:YES];
            } else if ([urlStrings count] > 1) {
                [self startBackgroundSubscriptionImportForURLs:urlStrings
                                            allowInsecureFetch:YES
                                                   startStatus:@"Importing insecure subscriptions..."
                                            importedPrefixPart:nil];
            }
        } else {
            [self showStatus:([urlStrings count] == 1 ? @"Subscription import canceled"
                                                      : @"Insecure subscriptions skipped")
                          ok:YES];
        }
        [urlStrings release];
        return;
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
    VCAppearanceApplyStatusBar();
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = VCBackgroundColor();
    MainVC *vc = [[[MainVC alloc] init] autorelease];
    _window.rootViewController = vc;
    [_window makeKeyAndVisible];
    return YES;
}

- (NSUInteger)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
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
