#import "../app/proxy_probe.h"
#include "check.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>

static int probe_running,probe_fd=-1,partial_io,write_interrupted,read_interrupted;
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
    size_t response_length;
    int fragmented,hold,release;
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
    } else goto done;
    if (receive_bytes(fd,address,length)) goto done;
    peer->connected=1;
    if (send(fd,"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00",10,0) != 10) goto done;
    char request[1024]; size_t used=0;
    while (used+1<sizeof(request)) {
        ssize_t count=recv(fd,request+used,1,0);
        if (count < 0 && errno == EINTR) continue;
        if (count != 1) goto done;
        request[++used]=0;
        if (strstr(request,"\r\n\r\n")) break;
    }
    int valid_request=!strcmp(request,kVCProxyPingRequest);
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
        if (peer->fragmented) usleep(1000);
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

int main(int argc,char **argv) {
    alarm(10); signal(SIGPIPE,SIG_IGN);
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if (argc == 3 && !strcmp(argv[1],"--probe")) {
        int ms=-1,result=probe((uint16_t)atoi(argv[2]),3500,&ms);
        printf("result=%d latency_ms=%d\n",result,ms);
        [pool drain]; return result == 0 ? 0 : 1;
    }
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
    FINISH("proxy health check");
    [pool drain]; return 0;
}
