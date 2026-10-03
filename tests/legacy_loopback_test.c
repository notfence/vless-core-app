#include <arpa/inet.h>
#include <assert.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#include <stdio.h>
static int mock_socket(int,int,int),mock_close(int),mock_poll(struct pollfd*,nfds_t,int);
static ssize_t mock_write(int,const void*,size_t),mock_read(int,void*,size_t);
#define socket mock_socket
#define close mock_close
#define poll mock_poll
#define write mock_write
#define read mock_read
#ifndef VC_LOOPBACK_STATE_PATH
#error Compile with a state path inside a newly created private test directory.
#endif
#include "../daemon/legacy_loopback.c"
#undef socket
#undef close
#undef poll
#undef write
#undef read
static route_t table[ROUTE_LIMIT], physical;
static unsigned table_count, adds, fail_add, deletes;
static unsigned char response[2048];static size_t response_length;
static int mock_socket(int a,int b,int c){(void)a;(void)b;(void)c;return 9000;}
static int mock_close(int fd){return fd==9000?0:close(fd);}
static int mock_poll(struct pollfd*p,nfds_t n,int t){(void)p;(void)n;(void)t;return 1;}
static ssize_t mock_read(int fd,void*p,size_t n){if(fd!=9000)return read(fd,p,n);assert(n>=response_length);memcpy(p,response,response_length);return response_length;}
static ssize_t mock_write(int fd,const void *bytes,size_t size){
    if(fd!=9000)return write(fd,bytes,size);
    const route_header_t *h=bytes;route_t requested;memset(&requested,0,sizeof(requested));
    requested.index=h->index;requested.flags=h->flags;size_t offset=sizeof(*h);
    for(unsigned bit=1;bit<=128;bit<<=1){if(!(h->addrs&bit))continue;
        const struct sockaddr *sa=(const void*)((const unsigned char*)bytes+offset);
        if(bit==1)requested.destination=((const struct sockaddr_in*)sa)->sin_addr.s_addr;
        if(bit==2)memcpy(&requested.gateway,sa,sa->sa_len);
        if(bit==4)requested.mask=((const struct sockaddr_in*)sa)->sin_addr.s_addr;
        if(bit==32)memcpy(&requested.source,sa,sa->sa_len);
        offset+=sa->sa_len?(sa->sa_len+3U)&~3U:4;
    }
    if((h->type!=4&&(h->flags&4))||(h->type==4&&!(h->addrs&4)))requested.mask=UINT32_MAX;
    unsigned match=table_count;
    for(unsigned i=0;i<table_count;i++)if(table[i].destination==requested.destination&&table[i].mask==requested.mask){match=i;break;}
    memset(response,0,sizeof(response));route_header_t*r=(void*)response;*r=*h;
    if(h->type==1){
        if(match<table_count)r->error=EEXIST;
        else if(++adds==fail_add)r->error=EIO;
        else{assert(table_count<ROUTE_LIMIT);table[table_count++]=requested;}
    } else if(h->type==2){
        if(match==table_count)r->error=ESRCH;
        else{memmove(&table[match],&table[match+1],(table_count-match-1)*sizeof(route_t));table_count--;deletes++;}
    }
    response_length=sizeof(*r);
    if(h->type==4){
        route_t answer=match<table_count?table[match]:physical;
        r->index=answer.index;r->flags=answer.flags;r->addrs=1|2|4|32;
        struct sockaddr_in dst=ipv4(answer.destination),mask=ipv4(answer.mask);
        mask.sin_family=0;
        if(!answer.mask)mask.sin_len=0;
        else while(mask.sin_len>4&&((const unsigned char*)&mask)[mask.sin_len-1]==0)mask.sin_len--;
        append_address(response,&response_length,&dst);append_address(response,&response_length,&answer.gateway);
        append_address(response,&response_length,&mask);append_address(response,&response_length,&answer.source);
    }
    r->length=response_length;return size;
}
static void reset(void){
    assert(vc_legacy_loopback_stop()==0);adds=deletes=fail_add=table_count=0;
    memset(&physical,0,sizeof(physical));physical.index=7;physical.flags=0x803;
    physical.source=ipv4(inet_addr("192.168.1.3"));struct sockaddr_in gw=ipv4(inet_addr("192.168.1.1"));memcpy(&physical.gateway,&gw,sizeof(gw));
}
int main(void){
    unlink(VC_LOOPBACK_STATE_PATH);unlink(VC_LOOPBACK_STATE_PATH ".tmp");reset();
    assert(!vc_legacy_loopback_start("203.0.113.1, 198.51.100.2",1));
    assert(active&&state.count==9&&table_count==9&&vc_legacy_loopback_healthy());
    assert(!vc_legacy_loopback_direct("203.0.113.20",1)&&table_count==10);
    assert(!vc_legacy_loopback_direct("203.0.113.20",0)&&table_count==9);
    state.count=0;active=0;assert(!vc_legacy_loopback_stop()&&table_count==0);
    for(unsigned step=1;step<=8;step++){
        reset();fail_add=step;assert(vc_legacy_loopback_start("203.0.113.1",1)!=0);
        assert(table_count==0&&deletes==step-1);
        assert(access(VC_LOOPBACK_STATE_PATH,F_OK));
    }
    reset();table[0]=physical;table[0].mask=htonl(0x80000000);table_count=1;
    assert(vc_legacy_loopback_start("203.0.113.1",0)!=0);assert(table_count==1&&(table[0].flags&OWN_FLAGS)!=OWN_FLAGS);
    table_count=0;reset();table[0]=physical;table[0].destination=inet_addr("203.0.113.1");table[0].mask=UINT32_MAX;table_count=1;
    assert(!vc_legacy_loopback_start("203.0.113.1",0)&&state.count==2&&table_count==3);
    physical.index=8;assert(!vc_legacy_loopback_healthy());assert(!vc_legacy_loopback_stop()&&table_count==1);
    table_count=0;reset();assert(!vc_legacy_loopback_start("203.0.113.1",0));
    table[table_count-1].flags &= ~OWN_FLAGS;assert(!vc_legacy_loopback_stop()&&table_count==1);
    assert(access(VC_LOOPBACK_STATE_PATH,F_OK));
    table_count=0;reset();table[0]=physical;table[0].destination=inet_addr("203.0.113.1");
    table[0].mask=UINT32_MAX;table[0].flags=0x20007;table_count=1;
    assert(!vc_legacy_loopback_start("203.0.113.1",0)&&state.count==3&&table_count==3);
    assert(!vc_legacy_loopback_stop()&&table_count==0);
    puts("PASS routes: serialization, activation, direct bypass, restart, partial failure, prefix conflict, foreign replacement, network change");
    return 0;
}
