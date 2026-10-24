#import "../integrations/incy/incy_links.h"
#import "../common/profile_logic.h"
#import "../common/foundation_logic.h"
#import "../common/subscription_task.h"
#import "../common/app_constants.h"
#include "check.h"
#include <openssl/evp.h>
#include <string.h>

static NSString *vector=@"incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg";
static NSString *config=@"trojan://a%2Bb+%2540:p@example.test:443?security=tls&type=ws&path=%2Fa%3Fx%3D%2520#name";
static BOOL failContext,failDigest;
EVP_CIPHER_CTX *__real_EVP_CIPHER_CTX_new(void);
EVP_CIPHER_CTX *__wrap_EVP_CIPHER_CTX_new(void) { return failContext ? NULL : __real_EVP_CIPHER_CTX_new(); }
int __real_EVP_Digest(const void *,size_t,unsigned char *,unsigned *,const EVP_MD *,ENGINE *);
int __wrap_EVP_Digest(const void *p,size_t n,unsigned char *out,unsigned *size,const EVP_MD *md,ENGINE *engine) {
    return failDigest ? 0 : __real_EVP_Digest(p,n,out,size,md,engine);
}

static NSString *base64(NSData *data,BOOL url) {
    NSMutableData *output=[NSMutableData dataWithLength:4*(([data length]+2)/3)+1];
    int n=EVP_EncodeBlock([output mutableBytes],[data bytes],(int)[data length]);
    NSString *text=[[[NSString alloc] initWithBytes:[output bytes] length:n encoding:NSASCIIStringEncoding] autorelease];
    if (url) {
        text=[[text stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
        while ([text hasSuffix:@"="]) text=[text substringToIndex:[text length]-1];
    }
    return text;
}

static NSString *seal(NSData *plain) {
    static const unsigned char key[32]={0xf6,0xd4,0x0e,0xa0,0xc8,0xa8,0x89,0x9d,0x7c,0x68,0x2d,0x09,0xba,0x0d,0x41,0x65,0xdf,0xe2,0xb3,0xdd,0x45,0xe6,0xbb,0x3e,0x25,0xcb,0x23,0x3c,0xf0,0x0c,0x24,0x62};
    unsigned char iv[12]={0,1,2,3,4,5,6,7,8,9,10,11};
    NSMutableData *wire=[NSMutableData dataWithLength:28+[plain length]];
    unsigned char *bytes=[wire mutableBytes]; memcpy(bytes,iv,12);
    EVP_CIPHER_CTX *ctx=EVP_CIPHER_CTX_new(); int n=0,last=0;
    CHECK("incy/fixture-context",ctx != NULL);
    CHECK("incy/fixture-init",EVP_EncryptInit_ex(ctx,EVP_aes_256_gcm(),NULL,key,iv) == 1);
    CHECK("incy/fixture-update",EVP_EncryptUpdate(ctx,bytes+12,&n,[plain bytes],(int)[plain length]) == 1);
    CHECK("incy/fixture-final",EVP_EncryptFinal_ex(ctx,bytes+12+n,&last) == 1);
    CHECK("incy/fixture-tag",EVP_CIPHER_CTX_ctrl(ctx,EVP_CTRL_GCM_GET_TAG,16,bytes+12+n+last) == 1);
    EVP_CIPHER_CTX_free(ctx);
    return [@"incy://crypt1/" stringByAppendingString:base64(wire,YES)];
}

static NSString *jsonLink(NSDictionary *fields) { return seal([NSJSONSerialization dataWithJSONObject:fields options:0 error:NULL]); }

static void cryptoTests(void) {
    NSString *error=nil;
    NSDictionary *descriptor=VCIncyImportDescriptor(vector,&error);
    CHECK("incy/official-vector",[[descriptor objectForKey:@"value"] isEqual:@"https://sub.example.com/test-vector"] && !error);
    CHECK("incy/source-preserved",[[descriptor objectForKey:@"source"] isEqual:vector]);
    NSString *special=@"https://example.test/sub?token=a+b%2B%2540&x=%26#fragment";
    NSString *link=jsonLink(@{@"v":@1,@"url":special,@"n":@"🇳🇱 Провайдер + %"});
    descriptor=VCIncySubscriptionDescriptor(link,&error);
    CHECK("incy/name-and-url-bytes",[[descriptor objectForKey:@"value"] isEqual:special] && [[descriptor objectForKey:@"name"] isEqual:@"🇳🇱 Провайдер + %"]);
    NSString *longName=[@"x" stringByPaddingToLength:127 withString:@"x" startingAtIndex:0];
    descriptor=VCIncyImportDescriptor(jsonLink(@{@"v":@1,@"url":special,@"n":[longName stringByAppendingString:@"🔥"]}),&error);
    CHECK("incy/name-limit-no-split-surrogate",[[descriptor objectForKey:@"name"] isEqual:longName]);
    for (NSDictionary *bad in @[@{@"url":special},@{@"v":@2,@"url":special},@{@"v":@"1",@"url":special},@{@"v":@(YES),@"url":special},
        @{@"v":@1,@"url":@1},@{@"v":@1,@"url":special,@"n":@1},@{@"v":@1,@"url":@"file:///tmp/private"},@{@"v":@1,@"url":@"https://"},
        @{@"v":@1,@"url":@"https://example.test/a\nb"},@{@"v":@1,@"url":@"incy://add/https://example.test"}]) {
        CHECK("incy/invalid-typed-payload",!VCIncyImportDescriptor(jsonLink(bad),&error) && [error isEqual:@"Invalid INCY crypt1 link"]);
    }
    for (NSString *bad in @[@"[]",@"{}",@"{\"v\":1,\"v\":2,\"url\":\"https://example.test\"}",@"{\"v\":1,\"url\":\"https://one.test\",\"url\":\"https://two.test\"}",@"{\"v\":1,\"url\":\"https://example.test\"}tail",@"{\"v\":1,\"url\":\"https://example.test/\\u0000hidden\"}"])
        CHECK("incy/invalid-json",!VCIncyImportDescriptor(seal([bad dataUsingEncoding:NSUTF8StringEncoding]),&error));
    const unsigned char invalidUTF8[]={0xff,0x00,0xf0,0x80};
    CHECK("incy/invalid-utf8",!VCIncyImportDescriptor(seal([NSData dataWithBytes:invalidUTF8 length:sizeof(invalidUTF8)]),&error));
    NSMutableData *wire=VCIncyDecodeBase64([vector substringFromIndex:14],YES,8192);
    for (NSUInteger i=0;i<[wire length];i++) {
        ((unsigned char *)[wire mutableBytes])[i]^=1;
        CHECK("incy/tampered-every-wire-byte",!VCIncyImportDescriptor([@"incy://crypt1/" stringByAppendingString:base64(wire,YES)],&error));
        ((unsigned char *)[wire mutableBytes])[i]^=1;
    }
    for (NSUInteger i=14;i<[vector length]-2;i++) CHECK("incy/truncated-wire",!VCIncyImportDescriptor([vector substringToIndex:i],&error));
    failContext=YES;
    CHECK("incy/context-allocation-failure",!VCIncyImportDescriptor(vector,&error)); failContext=NO;
    failDigest=YES;
    CHECK("incy/digest-failure",!VCIncyImportDescriptor(vector,&error)); failDigest=NO;
    CHECK("incy/recovery",VCIncyImportDescriptor(vector,&error) != nil);
    for (NSString *bad in @[@"!",@"A",@"AB",@"AAAA=",@"AA=A",@"AA===",@"-+AA",@" /8",@"_x"])
        CHECK("incy/base64-invalid",VCIncyDecodeBase64(bad,YES,8192) == nil);
    CHECK("incy/base64-padding",[VCIncyDecodeBase64(@"YQ==",YES,8192) isEqual:VCIncyDecodeBase64(@"YQ",YES,8192)]);
    CHECK("incy/size-check",VCIncyDecodeBase64(@"YQ==",YES,3) == nil);
    NSMutableData *clear=[NSMutableData dataWithBytes:"secret" length:6]; VCIncyClearData(clear);
    CHECK("incy/clear-owned-buffer",!memcmp([clear bytes],"\0\0\0\0\0\0",6));
    CHECK("incy/safe-fetch-error",[VCIncySafeFetchError(@"curl: https://secret.test/token") isEqual:@"INCY subscription fetch failed"]);
}

static void importTests(void) {
    VCProfileLogic *profiles=VCProfiles(); NSString *error=nil;
    NSArray *protocols=@[config,@"vless://11111111-2222-4333-8444-555555555555@example.test:443?security=tls",
        @"socks5://u:p@proxy.test",@"vmess://11111111-2222-4333-8444-555555555555@example.test:443?encryption=auto",
        @"ss://aes-128-gcm:p%2B%2540@example.test:443"];
    for (NSString *uri in protocols) {
        NSDictionary *report=[profiles textImportReportFromText:[@"incy://add/" stringByAppendingString:uri]];
        CHECK("incy/all-current-protocols",[[report objectForKey:@"uris"] isEqual:@[uri]] && ![[report objectForKey:@"skipped"] unsignedIntegerValue]);
    }
    for (NSString *command in @[@"add",@"import"]) {
        NSString *wrapper=[NSString stringWithFormat:@"incy://%@/%@",command,config];
        NSDictionary *report=[profiles textImportReportFromText:wrapper];
        CHECK("incy/direct-config-unchanged",[[report objectForKey:@"uris"] isEqual:@[config]]);
        wrapper=[NSString stringWithFormat:@"incy://%@/https://example.test/a+b?token=%@",command,@"%252F%2B"];
        CHECK("incy/subscription-unchanged",[[[profiles textImportReportFromText:wrapper] objectForKey:@"uris"] isEqual:@[@"https://example.test/a+b?token=%252F%2B"]]);
    }
    CHECK("incy/wrapper-retained-in-report",[[[profiles textImportReportFromText:vector] objectForKey:@"uris"] isEqual:@[vector]]);
    NSString *batch=[NSString stringWithFormat:@"%@\nsocks5://proxy.test\n%@",config,config];
    NSString *wrapper=[@"incy://import/" stringByAppendingString:base64([batch dataUsingEncoding:NSUTF8StringEncoding],NO)];
    NSDictionary *report=[profiles textImportReportFromText:wrapper];
    CHECK("incy/base64-list",[[report objectForKey:@"uris"] isEqual:@[config,@"socks5://proxy.test"]]);
    NSDictionary *happ=@{@"outbounds":@[@{@"protocol":@"trojan",@"settings":@{@"servers":@[@{@"address":@"example.test",@"port":@443,@"password":@"a+b%"}]}}]};
    NSData *json=[NSJSONSerialization dataWithJSONObject:happ options:0 error:NULL];
    NSString *jsonText=[[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] autorelease];
    NSArray *expected=[profiles extractConfigURIsFromHappJSONData:json];
    CHECK("incy/json-import",[[[profiles textImportReportFromText:[@"incy://import/" stringByAppendingString:jsonText]] objectForKey:@"uris"] isEqual:expected]);
    CHECK("incy/base64-json-import",[[[profiles textImportReportFromText:[@"incy://import/" stringByAppendingString:base64(json,YES)]] objectForKey:@"uris"] isEqual:expected]);
    for (NSString *bad in @[@"incy://routing/onadd/https://secret.test/token",@"incy://routing/add/trojan://p@example.test:443",@"incy://routing/onadd/{\"url\": \"https://secret.test/token\"}",@"incy://crypt1/!\"https://secret.test/token\"",@"incy://crypt2/https://secret.test/token",@"incy://connect",@"incy://import/incy://add/https://example.test",@"incy://add/happ://add/https://example.test",@"incy://import/aGVsbG8!"]) {
        report=[profiles textImportReportFromText:bad];
        CHECK("incy/unsupported-does-not-import-inner-link",![[report objectForKey:@"uris"] count] && [[report objectForKey:@"skipped"] unsignedIntegerValue] > 0);
    }
    wrapper=[@"incy://import/" stringByAppendingString:base64([vector dataUsingEncoding:NSUTF8StringEncoding],YES)];
    CHECK("incy/base64-nested-rejected",![[[profiles textImportReportFromText:wrapper] objectForKey:@"uris"] count]);
    NSString *mixed=[NSString stringWithFormat:@"%@\n%@\nincy://routing/onadd/https://secret.test/token\nincy://add/%@",vector,config,config];
    report=[profiles textImportReportFromText:mixed];
    CHECK("incy/mixed-dedup",[[report objectForKey:@"uris"] isEqual:@[vector,config]] && [[report objectForKey:@"skipped"] unsignedIntegerValue] == 1);
    CHECK("incy/remote-body-no-nested-target",![[profiles parseSubscriptionData:[@"incy://routing/add/trojan://p@example.test:443" dataUsingEncoding:NSUTF8StringEncoding]] count]);
    NSString *ending=@"trojan://pass@example.test:443#name)";
    CHECK("incy/no-trailing-rewrite",[[[profiles textImportReportFromText:[@"incy://add/" stringByAppendingString:ending]] objectForKey:@"uris"] isEqual:@[ending]]);
    CHECK("incy/unknown-command",VCIncyImportDescriptor(@"incy://toggle",&error) == nil && [error length]);
    NSDictionary *source=@{@"url":vector,@"name":@"INCY subscription",@"custom_name":@"Mine",@"items":@[config]};
    VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease];
    VCSubscriptionTask *old=VCSetCurrentSubscriptionTask(task);
    NSDictionary *updated=[profiles updatedSubscriptionFromSource:source data:[config dataUsingEncoding:NSUTF8StringEncoding] nameFromMetadata:@"Provider" userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"INCY subscription" hostName:@"INCY subscription" options:task errorText:&error];
    CHECK("incy/update-source-and-custom-name",[[updated objectForKey:@"url"] isEqual:vector] && [[updated objectForKey:@"name"] isEqual:@"Mine"]);
    CHECK("incy/no-happ-privileges",!SubscriptionDictionaryUsesHappHeaders(updated) && !SubscriptionDictionaryIsHappEncrypted(updated));
    unsigned char key[32]={1};
    NSData *serialized=[NSPropertyListSerialization dataFromPropertyList:updated format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
    NSData *encrypted=VCEncryptSecureStorePayload(serialized,key),*decrypted=VCDecryptSecureStorePayload(encrypted,key);
    NSDictionary *loaded=[NSPropertyListSerialization propertyListFromData:decrypted mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
    CHECK("incy/store-roundtrip-preserves-wrapper",[loaded isEqual:updated] && [[loaded objectForKey:@"url"] isEqual:vector]);
    [task cancelWithReason:nil];
    report=[profiles textImportReportFromText:vector];
    CHECK("incy/cancel-before-import",[report objectForKey:@"error"] != nil && ![[report objectForKey:@"uris"] count]);
    VCSetCurrentSubscriptionTask(old);
}

int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    if (argc == 2 && (!strcmp(argv[1],"--wrap") || !strcmp(argv[1],"--update"))) {
        NSData *data=[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        if (!strcmp(argv[1],"--wrap")) {
            NSString *link=seal(data);
            [[NSFileHandle fileHandleWithStandardOutput] writeData:[link dataUsingEncoding:NSUTF8StringEncoding]];
        } else {
            NSDictionary *input=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease];
            NSDictionary *updated=[VCProfiles() updatedSubscriptionFromSource:[input objectForKey:@"source"] data:[[input objectForKey:@"body"] dataUsingEncoding:NSUTF8StringEncoding] nameFromMetadata:[input objectForKey:@"title"] userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"INCY subscription" hostName:@"INCY subscription" options:task errorText:NULL];
            if (!updated) { [pool drain]; return 1; }
            [[NSFileHandle fileHandleWithStandardOutput] writeData:[NSJSONSerialization dataWithJSONObject:updated options:0 error:NULL]];
        }
        [pool drain]; return 0;
    }
    if (argc == 2 && !strcmp(argv[1],"--prepare")) {
        NSData *data=[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        NSString *text=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease],*error=nil;
        NSDictionary *descriptor=VCIncySubscriptionDescriptor(text,&error);
        if (descriptor) [[NSFileHandle fileHandleWithStandardOutput] writeData:[NSJSONSerialization dataWithJSONObject:descriptor options:0 error:NULL]];
        [pool drain]; return descriptor ? 0 : 1;
    }
    cryptoTests(); importTests();
    unsigned random=17; NSUInteger iterations=argc == 2 ? 30000 : 2000;
    for (NSUInteger i=0;i<iterations;i++) {
        NSAutoreleasePool *entry=[[NSAutoreleasePool alloc] init];
        NSMutableString *input=[NSMutableString stringWithString:@"incy://crypt1/"];
        for (NSUInteger j=0;j<i%170;j++) { random=random*1664525U+1013904223U; [input appendFormat:@"%c",(char)(32+(random%95))]; }
        NSString *error=nil; VCIncyImportDescriptor(input,&error);
        if (!(i%64)) VCIncyImportDescriptor(seal([input dataUsingEncoding:NSUTF8StringEncoding]),&error);
        [VCProfiles() textImportReportFromText:input];
        [entry drain];
    }
    FINISH("INCY import"); [pool drain]; return 0;
}
