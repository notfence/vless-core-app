#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <assert.h>
#include <sys/stat.h>
#include <unistd.h>
static void *mock_open(const char *, int);
static void *mock_symbol(void *, const char *);
static int mock_close(void *);
#if !defined(VC_LEGACY_DNS_PATH) || !defined(VC_LEGACY_DNS_DIRECTORY)
#error Compile with paths inside a newly created private test directory.
#endif
#define dlopen mock_open
#define dlsym mock_symbol
#define dlclose mock_close
#include "../daemon/legacy_dns.c"
#undef dlopen
#undef dlsym
#undef dlclose
static CFMutableDictionaryRef mock_values;
static int writes, fail_write;
static CFTypeRef create(CFAllocatorRef a,CFStringRef n,void *c,void *p){(void)a;(void)n;(void)c;(void)p;return CFRetain(mock_values);}
static CFPropertyListRef copy(CFTypeRef s,CFStringRef k){(void)s;CFTypeRef v=CFDictionaryGetValue(mock_values,k);return v?CFRetain(v):NULL;}
static CFArrayRef keys(CFTypeRef s,CFStringRef p){(void)s;(void)p;const void *v[]={CFSTR("State:/Network/Service/first/IPv4"),CFSTR("State:/Network/Service/second/IPv4")};return CFArrayCreate(NULL,v,2,&kCFTypeArrayCallBacks);}
static Boolean set(CFTypeRef s,CFStringRef k,CFPropertyListRef v){(void)s;if(++writes==fail_write)return 0;CFDictionarySetValue(mock_values,k,v);return 1;}
static Boolean remove_value(CFTypeRef s,CFStringRef k){(void)s;CFDictionaryRemoveValue(mock_values,k);return 1;}
static void *mock_open(const char *p,int f){(void)p;(void)f;return (void*)1;}
static int mock_close(void *p){(void)p;return 0;}
static void *mock_symbol(void *p,const char *n){(void)p;
    if(!strcmp(n,"SCDynamicStoreCreate"))return create;if(!strcmp(n,"SCDynamicStoreCopyValue"))return copy;
    if(!strcmp(n,"SCDynamicStoreCopyKeyList"))return keys;if(!strcmp(n,"SCDynamicStoreSetValue"))return set;
    if(!strcmp(n,"SCDynamicStoreRemoveValue"))return remove_value;return NULL;
}
static CFDictionaryRef dns(CFStringRef ip){
    CFArrayRef a=CFArrayCreate(NULL,(const void**)&ip,1,&kCFTypeArrayCallBacks);
    const void *k[]={CFSTR("ServerAddresses"),CFSTR("DomainName")},*v[]={a,CFSTR("preserve.example")};
    CFDictionaryRef d=CFDictionaryCreate(NULL,k,v,2,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);CFRelease(a);return d;
}
int main(void){
    unlink(VC_LEGACY_DNS_PATH);unlink(VC_LEGACY_DNS_PATH ".tmp");
    mock_values=CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    CFStringRef first=CFSTR("Setup:/Network/Service/first/DNS"), second=CFSTR("Setup:/Network/Service/second/DNS");
    CFDictionaryRef original=dns(CFSTR("8.8.8.8")),changed=dns(CFSTR("9.9.9.9"));
    CFDictionarySetValue(mock_values,first,original);
    assert(vc_legacy_dns_start()==0);assert(vc_legacy_dns_healthy());
    struct stat info;assert(!stat(VC_LEGACY_DNS_PATH,&info)&&info.st_uid==0&&(info.st_mode&0777)==0600);
    assert(vc_legacy_dns_stop()==0);assert(CFEqual(CFDictionaryGetValue(mock_values,first),original));
    assert(!CFDictionaryContainsKey(mock_values,second));assert(access(VC_LEGACY_DNS_PATH,F_OK));
    assert(vc_legacy_dns_start()==0);CFDictionarySetValue(mock_values,first,changed);
    assert(!vc_legacy_dns_healthy());assert(vc_legacy_dns_stop()==0);
    assert(CFEqual(CFDictionaryGetValue(mock_values,first),changed));assert(!CFDictionaryContainsKey(mock_values,second));
    CFDictionarySetValue(mock_values,first,original);writes=0;fail_write=2;
    assert(vc_legacy_dns_start()!=0);fail_write=0;
    assert(CFEqual(CFDictionaryGetValue(mock_values,first),original));assert(!CFDictionaryContainsKey(mock_values,second));
    assert(access(VC_LEGACY_DNS_PATH,F_OK));
    assert(vc_legacy_dns_start()==0);running=0;assert(vc_legacy_dns_stop()==0);
    assert(CFEqual(CFDictionaryGetValue(mock_values,first),original));
    CFRelease(original);CFRelease(changed);CFRelease(mock_values);
    puts("PASS DNS: apply/restore, missing key, user changes, partial failure, restart recovery, private backup");
    return 0;
}
