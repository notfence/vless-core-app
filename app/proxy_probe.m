#import "proxy_probe.h"
#import "../common/app_constants.h"
#import "../common/subscription_task.h"
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

NSString *const kVCDefaultProxyPingURL = @"http://www.gstatic.com/generate_204";

NSDictionary *VCProxyPingTargetForURL(NSString *url) {
    if (![url isKindOfClass:[NSString class]] || [url length] < 8 || [url length] > 2048 ||
        [[url substringToIndex:7] caseInsensitiveCompare:@"http://"] != NSOrderedSame) return nil;
    for (NSUInteger index=0;index<[url length];index++) {
        unichar c=[url characterAtIndex:index];
        if (c <= 0x20 || c >= 0x7f || c == '#' || c == '\\') return nil;
    }
    NSRange separator=[url rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?"]
                                          options:0 range:NSMakeRange(7,[url length]-7)];
    NSUInteger authorityEnd=separator.location == NSNotFound ? [url length] : separator.location;
    NSString *authority=[url substringWithRange:NSMakeRange(7,authorityEnd-7)];
    if (![authority length]) return nil;
    NSString *host=nil,*portText=nil;
    if ([authority hasPrefix:@"["]) {
        NSRange closing=[authority rangeOfString:@"]"];
        if (closing.location == NSNotFound) return nil;
        host=[authority substringWithRange:NSMakeRange(1,closing.location-1)];
        struct in6_addr address;
        if (inet_pton(AF_INET6,[host UTF8String],&address) != 1) return nil;
        if (NSMaxRange(closing) < [authority length]) {
            if ([authority characterAtIndex:NSMaxRange(closing)] != ':') return nil;
            portText=[authority substringFromIndex:NSMaxRange(closing)+1];
        }
    } else {
        NSRange colon=[authority rangeOfString:@":"];
        host=colon.location == NSNotFound ? authority : [authority substringToIndex:colon.location];
        if (colon.location != NSNotFound) portText=[authority substringFromIndex:colon.location+1];
        for (NSUInteger index=0;index<[host length];index++) {
            unichar c=[host characterAtIndex:index];
            if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_')) return nil;
        }
    }
    if (![host length] || [host length] > 255) return nil;
    unsigned port=80;
    if (portText) {
        port=0;
        if (![portText length]) return nil;
        for (NSUInteger index=0;index<[portText length];index++) {
            unsigned digit=(unsigned)([portText characterAtIndex:index]-'0');
            if (digit > 9 || port > (65535-digit)/10) return nil;
            port=port*10+digit;
        }
        if (!port) return nil;
    }
    NSString *target=authorityEnd == [url length] ? @"/" : [url substringFromIndex:authorityEnd];
    if ([target hasPrefix:@"?"]) target=[@"/" stringByAppendingString:target];
    for (NSUInteger index=0;index<[target length];index++) {
        unichar c=[target characterAtIndex:index];
        if (c == '%') {
            if (index+2 >= [target length]) return nil;
            for (NSUInteger n=1;n<=2;n++) {
                unichar digit=[target characterAtIndex:index+n];
                if (!((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f') ||
                      (digit >= 'A' && digit <= 'F'))) return nil;
            }
            index+=2;
        } else if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                     (c >= '0' && c <= '9') || strchr("-._~!$&'()*+,;=:@/?[]",c))) return nil;
    }
    NSString *request=[NSString stringWithFormat:@"GET %@ HTTP/1.1\r\nHost: %@\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n",target,authority];
    return @{@"url":url,@"host":host,@"port":@(port),@"request":request};
}

NSString *VCProxyPingURLInDefaults(id defaults) {
    id value=[defaults objectForKey:kDefaultsProxyPingURLKey];
    return VCProxyPingTargetForURL(value) ? value : kVCDefaultProxyPingURL;
}

NSString *VCSelectedProxyPingURL(void) {
    return VCProxyPingURLInDefaults([NSUserDefaults standardUserDefaults]);
}

static long long probe_now_ms(void) {
    return (long long)(VCSubscriptionMonotonicTime()*1000.0);
}

static int probe_io_timeout(int fd, long long deadline, int option) {
    if (!deadline) return 0;
    long long remaining=deadline-probe_now_ms();
    if (remaining <= 0) { errno=ETIMEDOUT; return -1; }
    struct timeval timeout={remaining/1000,(remaining%1000)*1000};
    return setsockopt(fd,SOL_SOCKET,option,&timeout,sizeof(timeout));
}

static int probe_write_all(int fd, const void *buf, size_t len, long long deadline) {
    const unsigned char *p = (const unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        if (probe_io_timeout(fd,deadline,SO_SNDTIMEO)) return -1;
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

int write_all(int fd, const void *buf, size_t len) {
    return probe_write_all(fd,buf,len,0);
}

static int read_full(int fd, void *buf, size_t len, long long deadline) {
    unsigned char *p = (unsigned char *)buf;
    size_t left = len;
    while (left > 0) {
        if (probe_io_timeout(fd,deadline,SO_RCVTIMEO)) return -1;
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

int connect_loopback_port(uint16_t port, int timeout_ms, VCPingCancellation *cancellation) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    if (cancellation && ![cancellation registerSocket:fd]) return -1;
#ifdef SO_NOSIGPIPE
    int no_sigpipe = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));
#endif

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

static int socks5_negotiate_noauth(int fd, long long deadline) {
    unsigned char hello[3] = {0x05, 0x01, 0x00};
    if (probe_write_all(fd, hello, sizeof(hello),deadline) != 0) return -1;

    unsigned char hello_resp[2];
    if (read_full(fd, hello_resp, sizeof(hello_resp),deadline) != 0) return -1;
    if (hello_resp[0] != 0x05 || hello_resp[1] != 0x00) return -1;
    return 0;
}

static int socks5_read_connect_response(int fd, long long deadline) {
    unsigned char resp[4];
    if (read_full(fd, resp, sizeof(resp),deadline) != 0) return -1;
    if (resp[0] != 0x05 || resp[1] != 0x00) return -1;

    size_t tail = 0;
    if (resp[3] == 0x01) {
        tail = 4 + 2;
    } else if (resp[3] == 0x04) {
        tail = 16 + 2;
    } else if (resp[3] == 0x03) {
        unsigned char domain_len = 0;
        if (read_full(fd, &domain_len, 1,deadline) != 0) return -1;
        tail = (size_t)domain_len + 2;
    } else {
        return -1;
    }

    unsigned char bound_address[257];
    if (tail > sizeof(bound_address)) return -1;
    return read_full(fd, bound_address, tail,deadline);
}

static int socks5_connect_until(int fd, const char *host, uint16_t port, long long deadline) {
    if (!host || !*host) return -1;
    size_t host_len = strlen(host);
    if (host_len > 255) return -1;
    if (socks5_negotiate_noauth(fd,deadline) != 0) return -1;

    unsigned char req[4 + 1 + 255 + 2];
    size_t n = 0;
    req[n++] = 0x05;
    req[n++] = 0x01;
    req[n++] = 0x00;
    struct in_addr ip4;
    struct in6_addr ip6;
    if (inet_pton(AF_INET,host,&ip4) == 1) {
        req[n++]=0x01; memcpy(req+n,&ip4,sizeof(ip4)); n+=sizeof(ip4);
    } else if (inet_pton(AF_INET6,host,&ip6) == 1) {
        req[n++]=0x04; memcpy(req+n,&ip6,sizeof(ip6)); n+=sizeof(ip6);
    } else {
        req[n++] = 0x03;
        req[n++] = (unsigned char)host_len;
        memcpy(&req[n], host, host_len);
        n += host_len;
    }
    req[n++] = (unsigned char)((port >> 8) & 0xFF);
    req[n++] = (unsigned char)(port & 0xFF);

    if (probe_write_all(fd, req, n,deadline) != 0) return -1;

    return socks5_read_connect_response(fd,deadline);
}

int socks5_connect_domain(int fd, const char *host, uint16_t port) {
    return socks5_connect_until(fd,host,port,0);
}

int TunnelConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms) {
    return ProxyGetConnectOnceMs(local_port, timeout_ms, latency_ms, nil);
}

int ProxyGetConnectOnceMs(uint16_t local_port, int timeout_ms, int *latency_ms,
                                 VCPingCancellation *cancellation) {
    return ProxyGetConnectToURLOnceMs(local_port,VCSelectedProxyPingURL(),timeout_ms,latency_ms,cancellation);
}

int ProxyGetConnectToURLOnceMs(uint16_t local_port, NSString *url, int timeout_ms, int *latency_ms,
                             VCPingCancellation *cancellation) {
    NSDictionary *target=VCProxyPingTargetForURL(url);
    if (!target || timeout_ms <= 0 || [cancellation isCancelled]) return -1;
    long long started=probe_now_ms(),deadline=started+timeout_ms;
    int fd = connect_loopback_port(local_port, timeout_ms, cancellation);
    if (fd < 0) {
        return -1;
    }

    long long first_byte=0;

    NSData *request=[[target objectForKey:@"request"] dataUsingEncoding:NSASCIIStringEncoding];
    if (socks5_connect_until(fd, [[target objectForKey:@"host"] UTF8String], [[target objectForKey:@"port"] unsignedIntValue],deadline) != 0 ||
        probe_write_all(fd, [request bytes], [request length],deadline) != 0) {
        VCClosePingSocket(fd, cancellation);
        return -2;
    }

    char response[512];
    size_t response_len = 0;
    BOOL got_first_byte = NO;
    while (response_len + 1 < sizeof(response) && ![cancellation isCancelled]) {
        if (probe_io_timeout(fd,deadline,SO_RCVTIMEO)) break;
        ssize_t rd = read(fd, response + response_len, sizeof(response) - response_len - 1);
        if (rd < 0 && errno == EINTR) continue;
        if (rd <= 0) break;
        if (!got_first_byte) {
            first_byte=probe_now_ms();
            got_first_byte = YES;
        }
        response_len += (size_t)rd;
        response[response_len] = '\0';
        if (strstr(response, "\r\n") != NULL) break;
    }
    VCClosePingSocket(fd, cancellation);

    char *line_end = got_first_byte ? strstr(response, "\r\n") : NULL;
    if ([cancellation isCancelled] || !line_end || line_end - response < 13 ||
        (memcmp(response, "HTTP/1.1 ", 9) != 0 && memcmp(response, "HTTP/1.0 ", 9) != 0) ||
        response[9] < '1' || response[9] > '5' || response[10] < '0' || response[10] > '9' ||
        response[11] < '0' || response[11] > '9' || response[12] != ' ') {
        return -3;
    }

    long long ms = first_byte-started;
    if (ms < 0) ms = 0;
    if (latency_ms) *latency_ms = (int)ms;
    return 0;
}
