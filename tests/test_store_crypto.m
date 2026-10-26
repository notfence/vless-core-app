#import <Foundation/Foundation.h>
#import "../common/app_constants.h"
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/crypto.h>
#include <sys/resource.h>
#include "check.h"

static NSMutableArray *allocated;
static NSUInteger allocations,allocationFailure,cryptoCalls,cryptoFailure,cleansed;
static BOOL deterministic;
@interface VCStoreData : NSObject
+ (id)dataWithLength:(NSUInteger)length;
+ (id)dataWithCapacity:(NSUInteger)capacity;
@end
@implementation VCStoreData
+ (id)record:(NSMutableData *)value {
    allocations++;
    if (allocationFailure==allocations) return nil;
    if (allocated && value) [allocated addObject:value];
    return value;
}
+ (id)dataWithLength:(NSUInteger)length { return [self record:[NSMutableData dataWithLength:length]]; }
+ (id)dataWithCapacity:(NSUInteger)capacity { return [self record:[NSMutableData dataWithCapacity:capacity]]; }
@end
static BOOL failCrypto(void) { return ++cryptoCalls==cryptoFailure; }
static int storeRandom(unsigned char *bytes,int length) {
    if (!deterministic) return RAND_bytes(bytes,length);
    for (int i=0;i<length;i++) bytes[i]=(unsigned char)i;
    return failCrypto() ? 0 : 1;
}
static EVP_CIPHER_CTX *storeContext(void) { return failCrypto() ? NULL : EVP_CIPHER_CTX_new(); }
static int storeInit(EVP_CIPHER_CTX *c,const EVP_CIPHER *cipher,ENGINE *engine,const unsigned char *key,const unsigned char *iv) {
    return failCrypto() ? 0 : EVP_EncryptInit_ex(c,cipher,engine,key,iv);
}
static int storeUpdate(EVP_CIPHER_CTX *c,unsigned char *out,int *length,const unsigned char *in,int size) {
    return failCrypto() ? 0 : EVP_EncryptUpdate(c,out,length,in,size);
}
static int storeFinal(EVP_CIPHER_CTX *c,unsigned char *out,int *length) {
    return failCrypto() ? 0 : EVP_EncryptFinal_ex(c,out,length);
}
static int storeControl(EVP_CIPHER_CTX *c,int type,int length,void *value) {
    return failCrypto() ? 0 : EVP_CIPHER_CTX_ctrl(c,type,length,value);
}
static void storeCleanse(void *bytes,size_t length) { cleansed+=length; OPENSSL_cleanse(bytes,length); }
#define NSMutableData VCStoreData
#define RAND_bytes storeRandom
#define EVP_CIPHER_CTX_new storeContext
#define EVP_EncryptInit_ex storeInit
#define EVP_EncryptUpdate storeUpdate
#define EVP_EncryptFinal_ex storeFinal
#define EVP_CIPHER_CTX_ctrl storeControl
#define OPENSSL_cleanse storeCleanse
#include "store_encrypt.inc"
#undef NSMutableData
#undef RAND_bytes
#undef EVP_CIPHER_CTX_new
#undef EVP_EncryptInit_ex
#undef EVP_EncryptUpdate
#undef EVP_EncryptFinal_ex
#undef EVP_CIPHER_CTX_ctrl
#undef OPENSSL_cleanse
#include "store_decrypt.inc"

static double seconds(struct timeval t) { return t.tv_sec+t.tv_usec/1e6; }
static void measure(NSUInteger count) {
    NSMutableData *plain=[NSMutableData dataWithLength:count*256];
    memset([plain mutableBytes],0x5a,[plain length]);
    unsigned char key[32]={0};
    struct rusage before,after; getrusage(RUSAGE_SELF,&before);
    double start=[NSDate timeIntervalSinceReferenceDate];
    for (NSUInteger i=0;i<8;i++) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        NSData *encrypted=VCEncryptSecureStorePayload(plain,key);
        CHECK("store/measure-size",[encrypted length]==[plain length]+36);
        [pool drain];
    }
    getrusage(RUSAGE_SELF,&after);
    printf("{\"count\":%lu,\"wall_ms\":%.6f,\"cpu_seconds\":%.6f,\"peak_rss\":%ld,\"containers\":%lu}\n",(unsigned long)count,([NSDate timeIntervalSinceReferenceDate]-start)*1000,seconds(after.ru_utime)+seconds(after.ru_stime)-seconds(before.ru_utime)-seconds(before.ru_stime),after.ru_maxrss,(unsigned long)allocations);
}
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if (argc==3 && !strcmp(argv[1],"--measure")) { measure(strtoul(argv[2],NULL,10)); [pool drain]; return 0; }
    unsigned char key[32]; for (NSUInteger i=0;i<sizeof(key);i++) key[i]=(unsigned char)i;
    deterministic=YES; allocated=[[NSMutableArray alloc] init];
    NSData *plain=[@"store fixture" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encrypted=VCEncryptSecureStorePayload(plain,key);
    NSUInteger operations=cryptoCalls;
    const unsigned char expected[]={0x56,0x43,0x53,0x41,0x46,0x45,0x30,0x31,0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0a,0x0b,0x06,0x02,0x0e,0x50,0x5d,0xbf,0xa8,0xbe,0x58,0xff,0x49,0xf1,0xd1,0xf1,0x95,0xdf,0x34,0x76,0xb9,0x69,0xa0,0xc5,0xa4,0x72,0xf5,0x35,0xe2,0xf9,0xd4};
    CHECK("store/independent-aes-gcm-vector",[encrypted length]==sizeof(expected) && memcmp([encrypted bytes],expected,sizeof(expected))==0);
    CHECK("store/one-container",allocations==1);
    CHECK("store/old-format-roundtrip",[VCDecryptSecureStorePayload([NSData dataWithBytes:expected length:sizeof(expected)],key) isEqual:plain]);
    CHECK("store/invalid-plaintext",VCEncryptSecureStorePayload(nil,key)==nil && VCEncryptSecureStorePayload([NSData data],key)==nil);
    for (NSUInteger failure=1;failure<=operations;failure++) {
        [allocated removeAllObjects]; allocations=0; cryptoCalls=0; cleansed=0; cryptoFailure=failure;
        CHECK("store/crypto-failure",VCEncryptSecureStorePayload(plain,key)==nil);
        for (NSData *buffer in allocated) {
            const unsigned char *p=[buffer bytes]; BOOL zero=YES;
            for (NSUInteger i=0;i<[buffer length];i++) if (p[i]) zero=NO;
            CHECK("store/failed-buffer-cleansed",zero);
        }
        CHECK("store/temporary-state-cleansed",cleansed>=28);
    }
    [allocated removeAllObjects]; allocations=0; cryptoCalls=0; cryptoFailure=0; allocationFailure=1;
    CHECK("store/allocation-failure",VCEncryptSecureStorePayload(plain,key)==nil);
    allocationFailure=0;
    [allocated release]; allocated=nil;
    deterministic=NO;
    for (NSUInteger length=1;length<=8192;length*=2) {
        NSMutableData *bytes=[NSMutableData dataWithLength:length]; memset([bytes mutableBytes],0xa5,length);
        NSData *a=VCEncryptSecureStorePayload(bytes,key),*b=VCEncryptSecureStorePayload(bytes,key);
        CHECK("store/size-and-roundtrip",[a length]==length+36 && [VCDecryptSecureStorePayload(a,key) isEqual:bytes]);
        CHECK("store/fresh-nonce",![a isEqual:b]);
    }
    FINISH("store encryption"); [pool drain]; return 0;
}
