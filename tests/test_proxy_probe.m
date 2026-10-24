#import "../app/proxy_probe.h"
#import "../common/subscription_task.h"
#include "check.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>

static int probe_running,probe_fd=-1,partial_io,write_interrupted,read_interrupted;
static const char *default_request="GET /generate_204 HTTP/1.1\r\nHost: www.gstatic.com\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n";
static void install_defaults(NSUserDefaults *defaults, NSDictionary *values) {
    [defaults removeVolatileDomainForName:NSArgumentDomain];
    [defaults setVolatileDomain:values forName:NSArgumentDomain];
}
int __real_socket(int,int,int);
ssize_t __real_write(int,const void *,size_t);
ssize_t __real_read(int,void *,size_t);
int __wrap_socket(int domain,int type,int protocol) {
    int fd=__real_socket(domain,type,protocol);
    if (probe_running) probe_fd=fd;
    return fd;
}
ssize_t __wrap_write(int fd,const void *data,size_t length) {
    if (partial_io && fd == probe_fd) {
        if (!write_interrupted++) { errno=EINTR; return -1; }
        if (length>2) length=2;
    }
    return __real_write(fd,data,length);
}
ssize_t __wrap_read(int fd,void *data,size_t length) {
    if (partial_io && fd == probe_fd) {
        if (!read_interrupted++) { errno=EINTR; return -1; }
        if (length>1) length=1;
    }
    return __real_read(fd,data,length);
}

static int probe(uint16_t port,int timeout,int *ms) {
    probe_running=1; probe_fd=-1;
    int result=TunnelConnectOnceMs(port,timeout,ms); probe_running=0;
    CHECK("probe/client-socket-released",probe_fd >= 0 && fcntl(probe_fd,F_GETFD) == -1 && errno == EBADF);
    return result;
}

typedef struct {
    int listener,request_read,connected;
    const char *response;
    const char *expected_host,*expected_request;
    uint16_t expected_port;
    size_t response_length;
    int fragmented,hold,release,delay_us;
    pthread_mutex_t lock;
    pthread_cond_t condition;
} peer_t;

static int receive_bytes(int fd,void *data,size_t size) {
    size_t offset=0;
    while (offset<size) {
        ssize_t count=recv(fd,(char *)data+offset,size-offset,0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return -1;
        offset+=(size_t)count;
    }
    return 0;
}

static void *serve(void *opaque) {
    peer_t *peer=opaque;
    int fd=accept(peer->listener,NULL,NULL);
    if (fd < 0) return NULL;
    struct timeval timeout={1,0}; setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    unsigned char hello[3],head[4],address[257];
    if (receive_bytes(fd,hello,3) || memcmp(hello,"\x05\x01\x00",3)) goto done;
    if (send(fd,"\x05\x00",2,0) != 2 || receive_bytes(fd,head,4) || memcmp(head,"\x05\x01\x00",3)) goto done;
    size_t length;
    if (head[3] == 1) length=6;
    else if (head[3] == 3) {
        unsigned char size;
        if (receive_bytes(fd,&size,1)) goto done;
        length=(size_t)size+2;
    } else if (head[3] == 4) length=18;
    else goto done;
    if (receive_bytes(fd,address,length)) goto done;
    if (peer->expected_host) {
        unsigned char expected[256];
        size_t expected_length;
        int expected_type;
        if (inet_pton(AF_INET,peer->expected_host,expected) == 1) { expected_length=4; expected_type=1; }
        else if (inet_pton(AF_INET6,peer->expected_host,expected) == 1) { expected_length=16; expected_type=4; }
        else { expected_length=strlen(peer->expected_host); expected_type=3; memcpy(expected,peer->expected_host,expected_length); }
        if (head[3] != expected_type || length != expected_length+2 || memcmp(address,expected,expected_length) ||
            ((unsigned)address[length-2]*256+address[length-1]) != peer->expected_port) goto done;
    }
    peer->connected=1;
    if (send(fd,"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00",10,0) != 10) goto done;
    char request[2304]; size_t used=0;
    while (used+1<sizeof(request)) {
        ssize_t count=recv(fd,request+used,1,0);
        if (count < 0 && errno == EINTR) continue;
        if (count != 1) goto done;
        request[++used]=0;
        if (strstr(request,"\r\n\r\n")) break;
    }
    int valid_request=!strcmp(request,peer->expected_request ?: default_request);
    pthread_mutex_lock(&peer->lock);
    peer->request_read=valid_request;
    pthread_cond_signal(&peer->condition);
    while (peer->hold && !peer->release) pthread_cond_wait(&peer->condition,&peer->lock);
    pthread_mutex_unlock(&peer->lock);
    if (!valid_request) goto done;
    for (size_t offset=0;offset<peer->response_length;) {
        size_t size=peer->fragmented ? 1 : peer->response_length-offset;
        ssize_t count=send(fd,peer->response+offset,size,0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        offset+=(size_t)count;
        if (peer->fragmented) usleep(peer->delay_us ?: 1000);
    }
done:
    close(fd); return NULL;
}

static uint16_t listen_peer(peer_t *peer,pthread_t *worker) {
    peer->lock=(pthread_mutex_t)PTHREAD_MUTEX_INITIALIZER;
    peer->condition=(pthread_cond_t)PTHREAD_COND_INITIALIZER;
    peer->listener=socket(AF_INET,SOCK_STREAM,0);
    CHECK("probe/create-listener",peer->listener >= 0);
    struct sockaddr_in address={0}; address.sin_family=AF_INET; address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    CHECK("probe/bind-loopback",bind(peer->listener,(struct sockaddr *)&address,sizeof(address)) == 0 && listen(peer->listener,1) == 0);
    socklen_t size=sizeof(address);
    CHECK("probe/assigned-port",getsockname(peer->listener,(struct sockaddr *)&address,&size) == 0);
    CHECK("probe/start-peer",pthread_create(worker,NULL,serve,peer) == 0);
    return ntohs(address.sin_port);
}

static void finish_peer(peer_t *peer,pthread_t worker) {
    pthread_mutex_lock(&peer->lock); peer->release=1;
    pthread_cond_signal(&peer->condition); pthread_mutex_unlock(&peer->lock);
    CHECK("probe/peer-finished",pthread_join(worker,NULL) == 0);
    close(peer->listener); pthread_cond_destroy(&peer->condition); pthread_mutex_destroy(&peer->lock);
}

typedef struct { uint16_t port; VCPingCancellation *cancellation; int result; } cancelling_probe_t;
static void *cancellable_probe(void *opaque) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    cancelling_probe_t *operation=opaque; int ms=-1;
    operation->result=ProxyGetConnectOnceMs(operation->port,1000,&ms,operation->cancellation);
    [pool drain]; return NULL;
}

static void target_tests(void) {
    CHECK("probe-url/default-remains-unchanged",[kVCDefaultProxyPingURL isEqual:@"http://www.gstatic.com/generate_204"]);
    NSDictionary *target=VCProxyPingTargetForURL(kVCDefaultProxyPingURL);
    CHECK("probe-url/default-wire-unchanged",[[target objectForKey:@"request"] isEqual:[NSString stringWithUTF8String:default_request]]);
    NSArray *urls=@[@"http://Example.COM",@"HTTP://probe.example:1?key=+%2B",@"http://127.0.0.1:65535/a",
        @"http://[::1]:8080/check",@"http://[2001:db8::1]/",@"http://probe.example:00080/?empty=&encoded=%23%26%40",
        @"http://probe.example/a%0D%0A+test"];
    for (NSString *url in urls) CHECK("probe-url/valid-target",VCProxyPingTargetForURL(url) != nil);
    target=VCProxyPingTargetForURL([urls objectAtIndex:1]);
    CHECK("probe-url/query-plus-and-escapes-preserved",[[target objectForKey:@"request"] hasPrefix:@"GET /?key=+%2B HTTP/1.1\r\nHost: probe.example:1\r\n"]);
    target=VCProxyPingTargetForURL([urls objectAtIndex:3]);
    CHECK("probe-url/ipv6-host-separated-from-authority",[[target objectForKey:@"host"] isEqual:@"::1"] && [[target objectForKey:@"port"] intValue] == 8080 &&
        [[target objectForKey:@"request"] rangeOfString:@"Host: [::1]:8080\r\n"].location != NSNotFound);
    NSArray *invalid=@[@"",@"http://",@"https://probe.example/",@"ftp://probe.example/",@"probe.example",@"//probe.example/",
        @" http://probe.example/",@"http://probe.example/ ",@"http://probe.example/\n",@"http://probe.example\r\nX: injected/",
        @"http://probe.example/a\tb",@"http://probe.example/a\0b",@"http://user:password@probe.example/",@"http://@probe.example/",
        @"http://probe.example/#fragment",@"http://probe.example:0/",@"http://probe.example:65536/",@"http://probe.example:/",
        @"http://probe.example:+80/",@"http://probe.example:-1/",@"http://probe.example:80x/",@"http://probe.example:999999999999999999999999/",
        @"http://[::1",@"http://[]/",@"http://[not-ip]/",@"http://[::1]x/",@"http://[::1]]/",@"http://[::1]:/",
        @"http://::1/",@"http://probe.example\\evil/",@"http://probe%2Eexample/",@"http://probe.example/%",@"http://probe.example/%0",
        @"http://probe.example/%XY",@"http://probe.example/\"",@"http://probe.example/{a}",@"http://probe.example/тест"];
    for (NSString *url in invalid) {
        CHECK("probe-url/reject-unsafe-or-unsupported-input",VCProxyPingTargetForURL(url) == nil);
        probe_fd=-1; probe_running=1; int ms=777;
        int result=ProxyGetConnectToURLOnceMs(1,url,50,&ms,nil);
        probe_running=0;
        CHECK("probe-url/invalid-target-never-opens-socket",result != 0 && probe_fd == -1 && ms == 777);
    }
    CHECK("probe-url/reject-non-string",VCProxyPingTargetForURL((id)@42) == nil && VCProxyPingTargetForURL(nil) == nil);
    NSString *prefix=@"http://probe.example/";
    NSString *maximum=[prefix stringByPaddingToLength:2048 withString:@"a" startingAtIndex:0];
    CHECK("probe-url/length-boundaries",VCProxyPingTargetForURL(maximum) && !VCProxyPingTargetForURL([maximum stringByAppendingString:@"a"]));
    NSMutableDictionary *defaults=[NSMutableDictionary dictionary];
    CHECK("probe-url/unset-default",[VCProxyPingURLInDefaults(defaults) isEqual:kVCDefaultProxyPingURL]);
    [defaults setObject:[urls objectAtIndex:1] forKey:@"vlesscore.ping.url"];
    CHECK("probe-url/saved-value-roundtrip",[VCProxyPingURLInDefaults(defaults) isEqual:[urls objectAtIndex:1]]);
    for (id value in @[@"",@42,@"https://probe.example/",@"http://probe.example/\r\n"]) {
        [defaults setObject:value forKey:@"vlesscore.ping.url"];
        CHECK("probe-url/corrupt-setting-falls-back-safely",[VCProxyPingURLInDefaults(defaults) isEqual:kVCDefaultProxyPingURL]);
    }
    uint32_t state=42;
    for (unsigned attempt=0;attempt<10000;attempt++) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        unichar chars[80]; size_t count=attempt%80;
        for (size_t index=0;index<count;index++) { state=state*1664525+1013904223; chars[index]=(state>>16)&0xffff; }
        NSString *suffix=[NSString stringWithCharacters:chars length:count];
        NSDictionary *parsed=VCProxyPingTargetForURL([prefix stringByAppendingString:suffix]);
        if (parsed) {
            NSString *request=[parsed objectForKey:@"request"];
            CHECK("probe-url/fuzz-cannot-inject-headers",[[request componentsSeparatedByString:@"\r\n"] count] == 6 && [[parsed objectForKey:@"host"] isEqual:@"probe.example"]);
        }
        [pool drain];
    }
}

int main(int argc,char **argv) {
    alarm(10); signal(SIGPIPE,SIG_IGN);
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if (argc == 3 && !strcmp(argv[1],"--probe")) {
        int ms=-1,result=probe((uint16_t)atoi(argv[2]),3500,&ms);
        printf("result=%d latency_ms=%d\n",result,ms);
        [pool drain]; return result == 0 ? 0 : 1;
    }
    if (argc == 4 && !strcmp(argv[1],"--probe-url")) {
        int ms=-1,result=ProxyGetConnectToURLOnceMs((uint16_t)atoi(argv[2]),[NSString stringWithUTF8String:argv[3]],3500,&ms,nil);
        printf("result=%d latency_ms=%d\n",result,ms);
        [pool drain]; return result == 0 ? 0 : 1;
    }
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSDictionary *saved_domain=[[defaults volatileDomainForName:NSArgumentDomain] copy];
    NSMutableDictionary *probe_defaults=[NSMutableDictionary dictionaryWithDictionary:saved_domain ?: @{}];
    [probe_defaults setObject:kVCDefaultProxyPingURL forKey:@"vlesscore.ping.url"];
    install_defaults(defaults,probe_defaults);
    target_tests();
    const char *responses[]={"HTTP/1.1 204 No Content\r\n\r\n","HTTP/1.0 200 OK\r\n\r\n","HTTP/1.1 403 Forbidden\r\n\r\n",
        "","HTTP/","HTTP/1.1 204 No Content","not HTTP\r\n","HTTP/1.1 abc Invalid\r\n","HTTP/1.1 099 Invalid\r\n","HTTP/1.1 600 Invalid\r\n"};
    for (size_t i=0;i<sizeof(responses)/sizeof(responses[0]);i++) {
        peer_t peer={.response=responses[i],.response_length=strlen(responses[i]),.fragmented=1};
        pthread_t worker; uint16_t port=listen_peer(&peer,&worker);
        int ms=-1,result=probe(port,300,&ms);
        finish_peer(&peer,worker);
        CHECK("health-check-sends-application-request",peer.request_read);
        CHECK("health-check-validates-response",(result == 0) == (i < 3));
        if (i < 3) CHECK("health-check-measures-first-response",ms >= 0);
    }
    peer_t silent={.hold=1}; pthread_t worker;
    uint16_t port=listen_peer(&silent,&worker); int ms=-1;
    CHECK("health-check-silent-server-not-success",probe(port,50,&ms) != 0);
    finish_peer(&silent,worker);
    CHECK("health-check-request-before-timeout",silent.request_read && ms == -1);
    const char *valid="HTTP/1.1 204 No Content\r\n\r\n";
    peer_t partial={.response=valid,.response_length=strlen(valid)};
    port=listen_peer(&partial,&worker); partial_io=1; write_interrupted=read_interrupted=0;
    CHECK("probe/partial-io-and-eintr",probe(port,300,&ms) == 0);
    partial_io=0; finish_peer(&partial,worker);
    CHECK("probe/partial-io-preserves-request",partial.request_read && write_interrupted>1 && read_interrupted>1);
    peer_t waiting={.hold=1}; port=listen_peer(&waiting,&worker);
    VCPingCancellation *token=[[[VCPingCancellation alloc] init] autorelease];
    cancelling_probe_t operation={.port=port,.cancellation=token}; pthread_t operation_worker;
    probe_running=1; probe_fd=-1;
    CHECK("probe/cancellable-worker",pthread_create(&operation_worker,NULL,cancellable_probe,&operation) == 0);
    pthread_mutex_lock(&waiting.lock);
    while (!waiting.request_read) pthread_cond_wait(&waiting.condition,&waiting.lock);
    pthread_mutex_unlock(&waiting.lock); [token cancel];
    CHECK("probe/cancellation-finishes",pthread_join(operation_worker,NULL) == 0 && operation.result != 0);
    probe_running=0; finish_peer(&waiting,worker);
    CHECK("probe/cancellation-closes-socket",probe_fd >= 0 && fcntl(probe_fd,F_GETFD) == -1 && errno == EBADF);
    VCPingCancellation *cancelled=[[[VCPingCancellation alloc] init] autorelease]; [cancelled cancel];
    CHECK("probe-cancelled-before-connect",ProxyGetConnectOnceMs(1,50,&ms,cancelled) != 0);
    id saved=[[defaults objectForKey:@"vlesscore.ping.url"] retain];
    [probe_defaults setObject:@"http://probe.example:8088/check%2Fpath?q=a+b%26c" forKey:@"vlesscore.ping.url"];
    install_defaults(defaults,probe_defaults);
    peer_t custom={.response=valid,.response_length=strlen(valid),.expected_host="probe.example",.expected_port=8088,
        .expected_request="GET /check%2Fpath?q=a+b%26c HTTP/1.1\r\nHost: probe.example:8088\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n"};
    port=listen_peer(&custom,&worker);
    int custom_result=probe(port,300,&ms);
    finish_peer(&custom,worker);
    if (saved) [probe_defaults setObject:saved forKey:@"vlesscore.ping.url"];
    else [probe_defaults removeObjectForKey:@"vlesscore.ping.url"];
    install_defaults(defaults,probe_defaults);
    [saved release];
    CHECK("probe/configured-url-controls-socks-and-http-target",custom_result == 0 && custom.request_read);
    NSArray *wire_urls=@[@"http://Example.COM",@"http://127.0.0.1:65535/?q=+%2B",@"http://[::1]:8080/check"];
    NSArray *wire_hosts=@[@"Example.COM",@"127.0.0.1",@"::1"];
    NSArray *wire_ports=@[@80,@65535,@8080];
    NSArray *wire_requests=@[@"GET / HTTP/1.1\r\nHost: Example.COM\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n",
        @"GET /?q=+%2B HTTP/1.1\r\nHost: 127.0.0.1:65535\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n",
        @"GET /check HTTP/1.1\r\nHost: [::1]:8080\r\nUser-Agent: vless-core-app-ping\r\nConnection: close\r\n\r\n"];
    saved=[[defaults objectForKey:@"vlesscore.ping.url"] retain];
    [probe_defaults setObject:@"http://different.example/" forKey:@"vlesscore.ping.url"];
    install_defaults(defaults,probe_defaults);
    for (NSUInteger index=0;index<[wire_urls count];index++) {
        peer_t peer={.response=valid,.response_length=strlen(valid),.fragmented=1,
            .expected_host=[[wire_hosts objectAtIndex:index] UTF8String],.expected_port=[[wire_ports objectAtIndex:index] unsignedIntValue],
            .expected_request=[[wire_requests objectAtIndex:index] UTF8String]};
        port=listen_peer(&peer,&worker);
        int result=ProxyGetConnectToURLOnceMs(port,[wire_urls objectAtIndex:index],300,&ms,nil);
        finish_peer(&peer,worker);
        CHECK("probe/custom-host-port-request-and-atyp-on-wire",result == 0 && peer.request_read && peer.connected);
    }
    if (saved) [probe_defaults setObject:saved forKey:@"vlesscore.ping.url"];
    else [probe_defaults removeObjectForKey:@"vlesscore.ping.url"];
    install_defaults(defaults,probe_defaults);
    [saved release];
    peer_t trickle={.response=valid,.response_length=strlen(valid),.fragmented=1,.delay_us=20000};
    port=listen_peer(&trickle,&worker);
    double started=VCSubscriptionMonotonicTime(); ms=-1;
    int result=probe(port,50,&ms);
    double elapsed=VCSubscriptionMonotonicTime()-started;
    finish_peer(&trickle,worker);
    CHECK("probe/trickled-status-does-not-extend-deadline",result != 0 && ms == -1 && elapsed < 0.5);
    install_defaults(defaults,saved_domain ?: @{});
    [saved_domain release];
    FINISH("proxy health check");
    [pool drain]; return 0;
}
