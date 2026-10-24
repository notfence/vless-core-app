#import "../common/profile_logic.h"
#import "../common/foundation_logic.h"
#import "../common/app_constants.h"
#include "../../vless-core-cli/include/uri.h"
#include "../../vless-core-cli/include/xhttp_download.h"
#include "check.h"

static NSString *const base=@"vless://11111111-2222-4333-8444-555555555555@example.test:443?type=xhttp";

static NSString *encoded(NSString *text) {
    return [VCProfiles() percentEncodedHappURIValue:text];
}

static vless_config_t parsed(NSString *uri) {
    vless_config_t config; char error[256];
    CHECK("runtime/core-accepts-result",uri && !parse_core_uri([uri UTF8String],&config,error,sizeof(error)));
    return config;
}

static NSString *disabled(NSString *uri) {
    NSString *error=nil,*result=[VCProfiles() runtimeURI:uri useXmux:NO error:&error];
    if (!result) fprintf(stderr,"runtime fixture rejected: %s\n",[uri UTF8String]);
    CHECK("runtime/preparation-succeeds",result && !error);
    return result;
}

static void unchanged(NSString *uri) {
    NSString *error=@"old";
    CHECK("runtime/enabled-is-byte-identical",[VCProfiles() runtimeURI:uri useXmux:YES error:&error] == uri && !error);
    CHECK("runtime/absent-is-byte-identical",disabled(uri) == uri);
}

static void parity(NSString *uri) {
    NSString *source=[[uri copy] autorelease],*result=disabled(uri);
    vless_config_t before=parsed(uri),after=parsed(result);
    CHECK("runtime/disabled-primary-xmux",!after.xmux.present);
    if (before.xhttp_download_settings[0]) {
        vless_config_t oldDownload,newDownload; char error[256];
        CHECK("runtime/download-parser",!core_xhttp_download_config(&before,&oldDownload,error,sizeof(error)) &&
              !core_xhttp_download_config(&after,&newDownload,error,sizeof(error)));
        CHECK("runtime/disabled-download-xmux",!newDownload.xmux.present);
        memset(&oldDownload.xmux,0,sizeof(oldDownload.xmux));
        CHECK("runtime/download-settings-preserved",!memcmp(&oldDownload,&newDownload,sizeof(oldDownload)));
    }
    memset(&before.xmux,0,sizeof(before.xmux));
    memset(before.xhttp_download_settings,0,sizeof(before.xhttp_download_settings));
    memset(after.xhttp_download_settings,0,sizeof(after.xhttp_download_settings));
    CHECK("runtime/other-effective-settings-preserved",!memcmp(&before,&after,sizeof(before)));
    CHECK("runtime/original-not-mutated",[uri isEqual:source]);
    NSString *error=nil;
    CHECK("runtime/enabled-preserves-policy",[VCProfiles() runtimeURI:uri useXmux:YES error:&error] == uri && !error);
}

static void cases(void) {
    unchanged(base);
    unchanged([base stringByAppendingString:@"&extra=%7B%22headers%22%3A%7B%22xmux%22%3A%22keep%22%7D%7D#%F0%9F%87%B3%F0%9F%87%B1"]);
    for (NSString *transport in @[@"tcp",@"ws",@"grpc"]) unchanged([NSString stringWithFormat:@"trojan://A+%%3A%%40%%25@example.test:443?type=%@&extra=%%7B%%22xmux%%22%%3A%%7B%%7D%%7D",transport]);
    unchanged(@"socks5://example.test");
    for (NSString *uri in @[@"trojan://A+%00%FF%3A%40%25@example.test:443?type=xhttp",@"ss://YWVzLTEyOC1nY206QStAOiU=@example.test:443?type=xhttp",@"ss://YWVzLTEyOC1nY206QStAOiVAZXhhbXBsZS50ZXN0OjQ0Mw==?type=xhttp"]) {
        parity([uri stringByAppendingFormat:@"&extra=%@",encoded(@"{\"xmux\":{\"maxConnections\":3}}")]);
    }
    parity([base stringByAppendingFormat:@"&flow=xtls-rprx-vision&encryption=mlkem768x25519plus.native.0rtt.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8&extra=%@",encoded(@"{\"xmux\":{}}")]);
    for (NSString *xmux in @[@"{}",@"{\"maxConnections\":3,\"maxConcurrency\":\"\"}",@"{\"hKeepAlivePeriod\":-1,\"hMaxRequestTimes\":\"600-900\"}"]) {
        NSString *extra=[NSString stringWithFormat:@"{\"path\":\"/extra\",\"xmux\":%@,\"headers\":{\"X-Marker\":\"A+B%%20\",\"xmux\":\"keep\"},\"xPaddingBytes\":\"100-200\"}",xmux];
        for (NSString *prefix in @[@"vless://11111111-2222-4333-8444-555555555555",@"trojan://A+%3A%40%25",@"vmess://11111111-2222-4333-8444-555555555555",@"ss://aes-128-gcm:A+%3A%40%25"]) {
            NSString *uri=[NSString stringWithFormat:@"%@@example.test:443?type=xhttp&extra=%@&path=%%2Fquery%%3Fx%%3D1&security=tls#Original%%20name",prefix,encoded(extra)];
            parity(uri);
            CHECK("runtime/unrelated-uri-bytes-preserved",[disabled(uri) hasPrefix:[prefix stringByAppendingString:@"@example.test:443?type=xhttp&extra="]] && [disabled(uri) hasSuffix:@"&path=%2Fquery%3Fx%3D1&security=tls#Original%20name"]);
        }
    }
    for (NSString *alias in @[@"xhttpSettings",@"splithttpSettings"]) for (BOOL nested=NO;;nested=YES) {
        NSString *settings=[NSString stringWithFormat:@"{\"path\":\"/down\",\"xmux\":{\"maxConnections\":2}%@}",nested ? @",\"extra\":{\"xmux\":{},\"xPaddingBytes\":\"200-300\"}" : @""];
        NSString *download=[NSString stringWithFormat:@"{\"address\":\"download.test\",\"port\":8443,\"network\":\"xhttp\",\"%@\":%@}",alias,settings];
        parity([base stringByAppendingFormat:@"&downloadSettings=%@&extra=%@",encoded(download),encoded(@"{\"xmux\":{}}")]);
        NSString *extra=[NSString stringWithFormat:@"{\"downloadSettings\":%@,\"xmux\":{\"maxConnections\":1}}",download];
        parity([base stringByAppendingFormat:@"&extra=%@",encoded(extra)]);
        if (nested) break;
    }
    for (NSString *extra in @[@"{\"xmux\":{},\"headers\":{\"X-Test\":\"keep\"},\"xPaddingBytes\":\"100-200\"}",@"{\"headers\":{\"X-Test\":\"keep\"},\"XMUX\":{}}",@"{\"xmux\":{},\"xMuX\":{}}",@"{\"xmux\":{\"maxConcurrency\":\"\",\"MaxConcurrency\":0,\"maxConnections\":3}}"]) parity([base stringByAppendingFormat:@"&extra=%@",encoded(extra)]);
    parity([base stringByAppendingFormat:@"&extra=%@",encoded(@"{\"x\\u006dux\":{},\"xPaddingBytes\":\"100-200\",\"XPaddingBytes\":\"100-200\"}")]);
    NSString *duplicates=@"{\"headers\":{\"X-Test\":\"one\",\"X-Test\":\"one\"},\"xmux\":{}}";
    CHECK("runtime/unrelated-duplicates-stay-on-wire",[[VCProfiles() queryValueForURLString:disabled([base stringByAppendingFormat:@"&extra=%@",encoded(duplicates)]) key:@"extra"] containsString:@"\"X-Test\":\"one\",\"X-Test\":\"one\""]);
    for (BOOL stringExtra=NO;;stringExtra=YES) {
        NSDictionary *json=@{@"v":@"2",@"id":@"11111111-2222-4333-8444-555555555555",@"add":@"example.test",@"port":@443,@"net":@"xhttp",@"xmux":@{@"maxConnections":@3},@"extra":stringExtra ? @"{\"xmux\":{},\"xPaddingBytes\":\"100-200\"}" : (id)@{@"xmux":@{},@"xPaddingBytes":@"100-200"}};
        NSData *data=[NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
        NSString *body=[data base64EncodedStringWithOptions:0];
        parity([@"vmess://" stringByAppendingFormat:@"%@#Raw%%20fragment",body]);
        body=[[[body stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
        parity([@"vmess://" stringByAppendingString:body]);
        if (stringExtra) break;
    }
    NSString *plainJSON=@"{\"v\":\"2\",\"id\":\"11111111-2222-4333-8444-555555555555\",\"add\":\"example.test\",\"port\":443,\"net\":\"xhttp\",\"extra\":{\"headers\":{\"xmux\":\"keep\"}}}";
    unchanged([@"vmess://" stringByAppendingString:[[plainJSON dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]]);
    NSString *downloadJSON=@"{\"id\":\"11111111-2222-4333-8444-555555555555\",\"add\":\"example.test\",\"port\":443,\"net\":\"xhttp\",\"downloadSettings\":{\"address\":\"download.test\",\"port\":8443,\"network\":\"xhttp\",\"xhttpSettings\":{\"extra\":{\"xmux\":{}}}}}";
    parity([@"vmess://" stringByAppendingString:[[downloadJSON dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]]);
    for (NSString *extra in @[@"{\"xmux\":{},}",@"{\"xmux\":{},\"XMUX\":{\"maxConnections\":3}}",@"{\"xmux\":{\"maxConnections\":2,\"MaxConnections\":3}}",@"{\"xmux\":{\"maxConcurrency\":1,\"maxConnections\":2}}",@"{\"xmux\":{\"maxConnections\":null}}",@"[]"]) {
        NSString *error=nil,*uri=[base stringByAppendingFormat:@"&extra=%@",encoded(extra)];
        CHECK("runtime/invalid-xmux-not-hidden",![VCProfiles() runtimeURI:uri useXmux:NO error:&error] && [error length] && ![error containsString:extra] && ![error containsString:uri]);
    }
    for (NSString *extra in @[@"{\"xmux\":{\"maxConnections\":1.0}}",@"{\"xmux\":{\"hKeepAlivePeriod\":\"-1\"}}",@"{\"xmux\":{\"unknown\":\"\\u0000\"}}",@"{\"xmux\":{\"maxConnections\":2147483648}}",@"{\"xmux\":{},\"downloadSettings\":{\"network\":\"xhttp\",\"xhttpSettings\":{\"xmux\":{},\"XMUX\":{\"maxConnections\":3}}}}"])
        CHECK("runtime/invalid-settings-stay-invalid",![VCProfiles() runtimeURI:[base stringByAppendingFormat:@"&extra=%@",encoded(extra)] useXmux:NO error:NULL]);
    NSMutableString *deep=[NSMutableString stringWithString:@"0"];
    for (unsigned i=0;i<24;i++) deep=[NSMutableString stringWithFormat:@"[%@]",deep];
    CHECK("runtime/depth-limit-before-foundation",![VCProfiles() runtimeURI:[base stringByAppendingFormat:@"&extra=%@",encoded([NSString stringWithFormat:@"{\"xmux\":{\"unknown\":%@}}",deep])] useXmux:NO error:NULL]);
    NSString *large=[@"x" stringByPaddingToLength:4096 withString:@"x" startingAtIndex:0];
    CHECK("runtime/input-limit",![VCProfiles() runtimeURI:large useXmux:YES error:NULL]);
    NSString *wide=[@"|" stringByPaddingToLength:1400 withString:@"|" startingAtIndex:0];
    NSString *unescaped=[base stringByAppendingFormat:@"&extra={\"xmux\":{},\"unknown\":\"%@\"}",wide];
    CHECK("runtime/output-growth-source-is-supported",[VCProfiles() isSupportedConfigTupleForURI:unescaped]);
    CHECK("runtime/output-limit",![VCProfiles() runtimeURI:unescaped useXmux:NO error:NULL]);
    NSString *seed=@"{\"xmux\":{\"maxConnections\":3},\"headers\":{\"X-Test\":\"kept\"},\"xPaddingBytes\":\"100-200\"}";
    for (NSUInteger i=0;i<[seed length];i++) for (NSString *insertion in @[@"",@"\"",@"\\",@",",@"\u00e9"]) {
        NSAutoreleasePool *iteration=[[NSAutoreleasePool alloc] init];
        NSString *mutated=[seed stringByReplacingCharactersInRange:NSMakeRange(i,1) withString:insertion];
        NSString *uri=[base stringByAppendingFormat:@"&extra=%@",encoded(mutated)];
        NSString *runtime=[VCProfiles() runtimeURI:uri useXmux:NO error:NULL];
        vless_config_t before,after; char error[256];
        int original=parse_core_uri([uri UTF8String],&before,error,sizeof(error));
        int prepared=runtime ? parse_core_uri([runtime UTF8String],&after,error,sizeof(error)) : -1;
        if (original && !prepared) fprintf(stderr,"mutation index=%lu replacement=%s JSON=%s\n",(unsigned long)i,[insertion UTF8String],[mutated UTF8String]);
        CHECK("runtime/mutation-does-not-sanitize-invalid-input",!original || prepared != 0);
        CHECK("runtime/mutation-removes-effective-xmux",prepared || !after.xmux.present);
        [iteration drain];
    }
    NSMutableDictionary *defaults=[NSMutableDictionary dictionary];
    CHECK("runtime/default-on",VCUseXmuxInDefaults(defaults));
    [defaults setObject:@(NO) forKey:kDefaultsUseXmuxKey];
    CHECK("runtime/explicit-off",!VCUseXmuxInDefaults(defaults));
    [defaults setObject:@(YES) forKey:kDefaultsUseXmuxKey];
    CHECK("runtime/explicit-on",VCUseXmuxInDefaults(defaults));
}

int main(int argc,const char **argv) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    CHECK("runtime/preparation-interface",[VCProfiles() respondsToSelector:@selector(runtimeURI:useXmux:error:)]);
    if (argc == 2 && (!strcmp(argv[1],"--runtime-on") || !strcmp(argv[1],"--runtime-off"))) {
        NSString *uri=[[[NSString alloc] initWithData:[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile] encoding:NSUTF8StringEncoding] autorelease];
        NSString *error=nil,*result=[VCProfiles() runtimeURI:uri useXmux:!strcmp(argv[1],"--runtime-on") error:&error];
        if (result) puts([result UTF8String]); else fprintf(stderr,"%s\n",[error UTF8String]);
        [pool drain]; return result ? 0 : 1;
    }
    cases(); FINISH("runtime URI"); [pool drain]; return 0;
}
