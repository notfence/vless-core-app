#import "../common/profile_logic.h"
#import "../common/foundation_logic.h"
#import "../integrations/incy/incy_links.h"
#import "../common/secure_store.h"
#include "../../vless-core-cli/include/uri.h"
#include "check.h"
#include <unistd.h>

static NSString *const identifier=@"11111111-2222-4333-8444-555555555555";

static NSString *jsonURI(NSDictionary *object) {
    return [@"vmess://" stringByAppendingString:[[NSJSONSerialization dataWithJSONObject:object options:0 error:NULL] base64EncodedStringWithOptions:0]];
}

static void accepted(NSString *uri) {
    VCProfileLogic *p=VCProfiles();
    CHECK("httpupgrade/app-supported",![p unsupportedConfigReasonForURI:uri]);
    CHECK("httpupgrade/metadata-transport",[[p transportTypeFromURI:uri] isEqual:@"httpupgrade"]);
    CHECK("httpupgrade/metadata-no-secrets",![[[p metadataForURI:uri] description] containsString:identifier]);
    NSString *host=nil; uint16_t port=0;
    CHECK("httpupgrade/server-metadata",[p parseServerHost:&host port:&port fromURI:uri] && [host length] && port);
    for (unsigned enabled=0;enabled<2;enabled++) {
        NSString *error=@"previous";
        CHECK("httpupgrade/xmux-byte-identical",[p runtimeURI:uri useXmux:enabled error:&error] == uri && !error);
    }
    vless_config_t config; char error[256];
    CHECK("httpupgrade/core-accepts",!parse_core_uri([uri UTF8String],&config,error,sizeof(error)) && config.transport_mode == TRANSPORT_HTTPUPGRADE);
    memset(&config,0,sizeof(config));
}

static void rejected(NSString *uri) {
    NSString *reason=[VCProfiles() unsupportedConfigReasonForURI:uri];
    CHECK("httpupgrade/invalid-app-rejected",[reason length] && ![reason containsString:uri] && ![reason containsString:@"private-fixture"]);
    vless_config_t config; char error[256];
    CHECK("httpupgrade/invalid-core-rejected",parse_core_uri([uri UTF8String],&config,error,sizeof(error)) != 0);
    memset(&config,0,sizeof(config));
}

static void links(void) {
    VCProfileLogic *p=VCProfiles();
    NSArray *credentials=@[[NSString stringWithFormat:@"vless://%@",identifier],@"trojan://private-fixture+%3A%40%25",[NSString stringWithFormat:@"vmess://%@",identifier],@"ss://aes-128-gcm:private-fixture+%3A%40%25"];
    for (NSString *credential in credentials) for (NSString *security in @[@"none",@"tls"]) for (NSString *alias in @[@"type",@"network",@"transport",@"net"]) {
        NSString *uri=[NSString stringWithFormat:@"%@@example.test:443?%@=httpupgrade&security=%@&path=%%2Fname%%20%%3Fx%%3Da%%252Fb%%26y%%3Da%%2Bb&headers=%%7B%%22X-Fixture%%22%%3A%%22A%%2BB%%2520%%22%%7D#Original%%20name",credential,alias,security];
        accepted(uri);
        CHECK("httpupgrade/plain-import-keeps-uri",[[p parseSubscriptionData:[uri dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[uri]]);
        NSString *wrapper=[[uri dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
        CHECK("httpupgrade/base64-subscription-keeps-uri",[[p parseSubscriptionData:[wrapper dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[uri]]);
        NSDictionary *incy=VCIncyImportDescriptor([@"incy://add/" stringByAppendingString:uri],NULL);
        CHECK("httpupgrade/incy-keeps-uri",[[incy objectForKey:@"value"] isEqual:uri]);
        CHECK("httpupgrade/qr-clipboard-extraction",[[p extractConfigURIsFromText:[@"Imported:\n" stringByAppendingString:uri]] isEqual:@[uri]]);
    }
    NSString *base=[NSString stringWithFormat:@"vless://%@@example.test:443?type=httpupgrade&security=tls",identifier];
    for (NSString *extra in @[@"",@"&ed=0",@"&ed=4294967295",@"&maxEarlyData=16385",@"&host=%5B2001%3Adb8%3A%3A1%5D%3A8443",@"&sni=example.test",@"&alpn=h2%2Chttp%2F1.1",@"&path=%2Fu%3Fed%3D1%26keep%3Da%252Fb&ed=0",@"&path=%2Fu%3Fz%3D2%26ed%3D4294967295%26a%3D1",@"&path=",@"&headers=%7B%22X-Test%22%3A%22a%22%2C%22x-test%22%3A%22a%22%7D"])
        accepted([base stringByAppendingString:extra]);
    for (NSString *extra in @[@"&ed=",@"&ed=-1",@"&ed=%2B1",@"&ed=1.0",@"&ed=4294967296",@"&ed=%201",@"&ed=1&maxEarlyData=2",@"&heartbeatPeriod=0",@"&alpn=h2",@"&host=private-fixture%0D%0AInjected%3Ax",@"&host=host%3A0",@"&headers=%7B%22Host%22%3A%22private-fixture%22%7D",@"&headers=%7B%22TE%22%3A%22trailers%22%7D",@"&headers=%7B%22X-Test%22%3A%22a%22%2C%22x-test%22%3A%22b%22%7D",@"&headers=%7B%22X-Test%22%3A%22a%22%2C%22X-Test%22%3A%22b%22%7D",@"&headers=[]",@"&headers=",@"&path=%2Fu%3Fed%3D1%26ed%3D2",@"&path=%2Fu%3Fed%3D1%26ed%3D1",@"&path=%2Fu%3Fed%3D",@"&path=%2Fu%3Fed%3D4294967296&ed=0",@"&path=%2Fprivate-fixture%5Cbad",@"&flow=xtls-rprx-vision"])
        rejected([base stringByAppendingString:extra]);
    rejected([base stringByReplacingOccurrencesOfString:@"security=tls" withString:@"security=reality"]);
    NSString *encryption=@"mlkem768x25519plus.native.0rtt.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
    accepted([base stringByAppendingFormat:@"&flow=xtls-rprx-vision&encryption=%@",encryption]);
    accepted([NSString stringWithFormat:@"vless://%@@[2001:db8::1]:443?type=httpupgrade&security=none",identifier]);
    rejected([base stringByAppendingFormat:@"&path=%@",[@"a" stringByPaddingToLength:256 withString:@"a" startingAtIndex:0]]);
    rejected([base stringByAppendingFormat:@"&host=%@",[@"a" stringByPaddingToLength:256 withString:@"a" startingAtIndex:0]]);
    NSString *bad=[base stringByAppendingString:@"&ed=bad"];
    NSDictionary *report=[p subscriptionImportReportFromData:[[NSString stringWithFormat:@"%@\n%@\n%@",base,base,bad] dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("httpupgrade/mixed-subscription",[[report objectForKey:@"uris"] isEqual:@[base]] && [[report objectForKey:@"skipped"] unsignedIntValue] == 1);
}

static void vmess(void) {
    NSDictionary *original=@{@"v":@"2",@"add":@"example.test",@"port":@443,@"id":identifier,@"net":@"httpupgrade",@"tls":@"tls",@"path":@"/upgrade?ed=1&keep=a%2Fb",@"maxEarlyData":@0,@"headers":@{@"X-Fixture":@"A+B%20"},@"ps":@"Original"};
    accepted(jsonURI(original));
    NSMutableDictionary *same=[[original mutableCopy] autorelease]; [same setObject:@"0" forKey:@"ed"];
    accepted(jsonURI(same));
    NSString *raw=[NSString stringWithFormat:@"{\"id\":\"%@\",\"add\":\"example.test\",\"port\":443,\"net\":\"httpupgrade\",\"ed\":1.0}",identifier];
    rejected([@"vmess://" stringByAppendingString:[[raw dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]]);
    for (id early in @[@0,@4294967295U,@"16385"]) {
        NSMutableDictionary *object=[[original mutableCopy] autorelease];
        [object removeObjectForKey:@"maxEarlyData"]; [object setObject:early forKey:@"ed"];
        accepted(jsonURI(object));
    }
    for (NSDictionary *change in @[@{@"ed":@1},@{@"maxEarlyData":@(YES)},@{@"maxEarlyData":@4294967296ULL},@{@"maxEarlyData":@""},@{@"maxEarlyData":@1.5},@{@"headers":@{@"Host":@"private-fixture"}},@{@"headers":@[]},@{@"alpn":@"h2"},@{@"heartbeatPeriod":@0},@{@"tls":@"reality"}]) {
        NSMutableDictionary *object=[[original mutableCopy] autorelease]; [object addEntriesFromDictionary:change];
        rejected(jsonURI(object));
    }
}

static void converters(void) {
    VCProfileLogic *p=VCProfiles();
    NSDictionary *user=@{@"id":identifier,@"encryption":@"none"};
    NSDictionary *settings=@{@"host":@"edge.test",@"path":@"/name ?ed=1&keep=a%2Fb",@"headers":@{@"X-Fixture":@"A+B%20"},@"maxEarlyData":@4294967295U};
    NSDictionary *stream=@{@"network":@"httpupgrade",@"security":@"tls",@"tlsSettings":@{@"serverName":@"sni.test",@"alpn":@[@"http/1.1"]},@"httpupgradeSettings":settings};
    NSDictionary *happ=@{@"outbounds":@[@{@"protocol":@"vless",@"settings":@{@"vnext":@[@{@"address":@"example.test",@"port":@443,@"users":@[user]}]},@"streamSettings":stream}]};
    NSDictionary *karing=@{@"type":@"vless",@"server":@"example.test",@"server_port":@443,@"uuid":identifier,@"tls":@{@"enabled":@(YES),@"server_name":@"sni.test",@"alpn":@[@"http/1.1"]},@"transport":@{@"type":@"httpupgrade",@"host":@"edge.test",@"path":@"/name ?ed=1&keep=a%2Fb",@"headers":@{@"X-Fixture":@[@"A+B%20"]},@"max_early_data":@4294967295U}};
    NSString *first=[p URIFromHappJSONConfig:happ],*second=[p URIFromKaringServer:karing error:NULL];
    accepted(first); accepted(second);
    NSData *json=[NSJSONSerialization dataWithJSONObject:happ options:0 error:NULL];
    CHECK("httpupgrade/happ-numeric-json",[[p extractConfigURIsFromHappJSONData:json] isEqual:@[first]]);
    vless_config_t a,b; char error[256];
    CHECK("httpupgrade/converters-core-equivalent",!parse_core_uri([first UTF8String],&a,error,sizeof(error)) && !parse_core_uri([second UTF8String],&b,error,sizeof(error)) && !memcmp(&a,&b,sizeof(a)));
    CHECK("httpupgrade/converters-path-not-rewritten",[[p queryValueForURLString:first key:@"path"] isEqual:[settings objectForKey:@"path"]]);
    CHECK("httpupgrade/converters-uint32",a.httpupgrade_early_data == UINT32_MAX && !strcmp(a.xhttp_host,"edge.test") && strstr(a.ws_headers,"A+B%20"));
    for (NSDictionary *change in @[@{@"ed":@0},@{@"maxEarlyData":@-1},@{@"maxEarlyData":@1.5},@{@"maxEarlyData":@(YES)},@{@"heartbeatPeriod":@0},@{@"headers":@{@"Host":@"private-fixture"}},@{@"acceptProxyProtocol":@(YES)},@{@"early_data_header_name":@"Sec-WebSocket-Protocol"}]) {
        NSMutableDictionary *badSettings=[[settings mutableCopy] autorelease]; [badSettings addEntriesFromDictionary:change];
        NSMutableDictionary *badStream=[[stream mutableCopy] autorelease]; [badStream setObject:badSettings forKey:@"httpupgradeSettings"];
        NSMutableDictionary *proxy=[[[[happ objectForKey:@"outbounds"] objectAtIndex:0] mutableCopy] autorelease]; [proxy setObject:badStream forKey:@"streamSettings"];
        NSDictionary *bad=@{@"outbounds":@[proxy]};
        CHECK("httpupgrade/happ-invalid-rejected",![p URIFromHappJSONConfig:bad]);
    }
    NSMutableDictionary *badKaring=[[karing mutableCopy] autorelease];
    NSMutableDictionary *transport=[[[karing objectForKey:@"transport"] mutableCopy] autorelease];
    [transport setObject:@"Sec-WebSocket-Protocol" forKey:@"early_data_header_name"]; [badKaring setObject:transport forKey:@"transport"];
    CHECK("httpupgrade/karing-no-ws-early-data",![p URIFromKaringServer:badKaring error:NULL]);
}

static NSString *storeKey(NSString *command) { (void)command; return @"OK 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"; }
static BOOL protectedFile(NSString *path) { (void)path; return YES; }

static void persistence(void) {
    NSString *uri=[NSString stringWithFormat:@"vless://%@@example.test:443?type=httpupgrade&ed=4294967295&path=%%2Fkeep%%3Fx%%3Da%%252Fb#Original%%20name",identifier];
    char temporary[]="/tmp/vless-httpupgrade-store-XXXXXX";
    CHECK("httpupgrade/store-directory",mkdtemp(temporary));
    NSString *directory=[NSString stringWithUTF8String:temporary],*file=[directory stringByAppendingPathComponent:@"configs.dat"];
    VCStoragePaths paths={directory,file,nil,storeKey,protectedFile};
    NSArray *configs=@[uri],*subscriptions=@[@{@"url":@"https://example.test/sub",@"items":configs}];
    CHECK("httpupgrade/store-save",VCSaveProtectedConfigurationDataAtPaths(configs,subscriptions,&paths));
    BOOL exists=NO; NSDictionary *loaded=VCLoadProtectedConfigurationDataAtPaths(&exists,&paths);
    CHECK("httpupgrade/store-original-uri",exists && [[loaded objectForKey:@"configs"] isEqual:configs] && [[loaded objectForKey:@"subscriptions"] isEqual:subscriptions]);
    CHECK("httpupgrade/store-cleanup",!unlink([file fileSystemRepresentation]) && !rmdir(temporary));
}

static void bulk(void) {
    for (unsigned count=1000;count<=6000;count+=5000) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        VCProfileLogic *p=[[[VCProfileLogic alloc] init] autorelease];
        NSMutableString *source=[NSMutableString string];
        for (unsigned i=0;i<count;i++) [source appendFormat:@"vless://%@@example.test:443?type=%@#%u\n",identifier,i%2 ? @"httpupgrade" : @"tcp",i];
        NSDictionary *report=[p subscriptionImportReportFromData:[source dataUsingEncoding:NSUTF8StringEncoding]];
        CHECK("httpupgrade/bulk-mixed-no-loss",[[report objectForKey:@"uris"] count] == count && ![[report objectForKey:@"skipped"] unsignedIntValue]);
        NSDictionary *metadata=[report objectForKey:@"metadata"];
        [p installPreparedMetadata:[p preparedMetadataForConfigurations:@[] subscriptions:@[@{@"items":[report objectForKey:@"uris"]}] additionalMetadata:metadata]];
        NSString *uri=[[report objectForKey:@"uris"] lastObject];
        CHECK("httpupgrade/bulk-metadata-reused",[p metadataForURI:uri] == [metadata objectForKey:uri]);
        [pool drain];
    }
}

static void mutations(void) {
    NSString *base=[NSString stringWithFormat:@"vless://%@@example.test:443?type=httpupgrade&security=tls&",identifier];
    uint32_t state=0x42f1a79;
    NSArray *keys=@[@"ed",@"path",@"headers",@"host",@"alpn"];
    for (unsigned i=0;i<3000;i++) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        state=state*1664525U+1013904223U;
        NSString *value=[NSString stringWithFormat:@"%x%%2F%u",state,state%9];
        if (i%4 == 0) value=[NSString stringWithFormat:@"%u",state];
        if (i%4 == 1) value=[NSString stringWithFormat:@"%%2Fu%%3Fed%%3D%u%%26keep%%3Da%%252Fb",state];
        if (i%4 == 2) value=[NSString stringWithFormat:@"%%7B%%22X-Test%%22%%3A%%22%u%%22%%7D",state];
        NSString *uri=[base stringByAppendingFormat:@"%@=%@",[keys objectAtIndex:i%[keys count]],value];
        BOOL supported=[VCProfiles() isSupportedConfigTupleForURI:uri];
        vless_config_t config; char error[256];
        int result=parse_core_uri([uri UTF8String],&config,error,sizeof(error));
        CHECK("httpupgrade/mutation-validation-matches-core",supported == (result == 0));
        memset(&config,0,sizeof(config)); [pool drain];
    }
}

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    links(); vmess(); converters(); persistence(); bulk(); mutations();
    FINISH("HTTPUpgrade imports"); [pool drain]; return 0;
}
