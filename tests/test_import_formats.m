#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
#import "../common/subscription_task.h"
#import "../integrations/karing/karing_backup.h"
#include "../integrations/happ/happ_crypto.h"
#include "check.h"
#include "../../vless-core-cli/include/uri.h"
#include <openssl/evp.h>

@interface VCProfileLogic (VCConverterTests)
- (NSString *)URIFromKaringServer:(NSDictionary *)server error:(NSString **)error;
- (NSDictionary *)importReportFromHappJSONData:(NSData *)data;
@end

static vless_config_t parsed(NSString *uri) {
    vless_config_t config; char error[256];
    CHECK("happ/converted-profile-accepted-by-core", uri && parse_core_uri([uri UTF8String], &config, error, sizeof(error)) == 0);
    return config;
}

static void parserDependencies(void) {
    NSArray *links = @[@"vless://11111111-2222-4333-8444-555555555555@127.0.0.1:443",
        @"socks5://127.0.0.1", @"trojan://parser-test@127.0.0.1:443",
        @"vmess://11111111-2222-4333-8444-555555555555@127.0.0.1:443?scy=auto",
        @"ss://aes-128-gcm:parser-test@127.0.0.1:443"];
    for (NSUInteger i = 0; i < [links count]; i++) {
        vless_config_t config = parsed([links objectAtIndex:i]);
        CHECK("core-parser/all-current-protocols-linked", config.protocol == (core_protocol_t)i);
        memset(&config, 0, sizeof(config));
    }
}

static NSDictionary *profile(NSString *network, NSDictionary *transport, NSDictionary *user) {
    return @{@"outbounds": @[@{@"protocol": @"vless", @"settings": @{@"vnext": @[@{@"address": @"example.test", @"port": @443, @"users": @[user]}]},
        @"streamSettings": @{@"network": network, @"security": @"tls", @"tlsSettings": @{@"serverName": @"edge.test"},
        @"wsSettings": transport, @"grpcSettings": transport, @"xhttpSettings": transport}}]};
}

static void extendedProfiles(void) {
    VCProfileLogic *logic = VCProfiles();
    NSString *encryption = @"mlkem768x25519plus.native.0rtt.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
    NSDictionary *user = @{@"id": @"11111111-2222-4333-8444-555555555555", @"encryption": encryption, @"flow": @"xtls-rprx-vision"};
    for (NSString *network in @[@"tcp", @"ws", @"grpc", @"xhttp"]) {
        NSString *uri = [logic vlessURIFromHappJSONConfig:profile(network, @{}, user)];
        CHECK("happ/encryption-retains-case-and-mode", uri && [[logic queryValueForURLString:uri key:@"encryption"] isEqual:encryption]);
        CHECK("happ/encrypted-flow-is-retained", [[logic queryValueForURLString:uri key:@"flow"] isEqual:@"xtls-rprx-vision"]);
        vless_config_t config = parsed(uri);
        CHECK("happ/core-encryption-and-flow", config.encryption_enabled && config.encryption_zero_rtt && !strcmp(config.flow, "xtls-rprx-vision") && config.encryption_relays[0].key_len == 32);
        for (unsigned i = 0; i < 32; i++) CHECK("happ/core-relay-key-bytes", config.encryption_relays[0].key[i] == i);
    }
    NSDictionary *plain = @{@"id": [user objectForKey:@"id"]};
    NSString *uri = [logic vlessURIFromHappJSONConfig:profile(@"ws", @{@"host": @"preferred.test", @"headers": @{@"Host": @"legacy.test", @"X-Vless-Core": @"Value"}, @"path": @"/socket?ed=64", @"maxEarlyData": @128, @"heartbeatPeriod": @3}, plain)];
    CHECK("happ/ws-independent-host", [[logic queryValueForURLString:uri key:@"host"] isEqual:@"preferred.test"]);
    NSDictionary *headers = [NSJSONSerialization JSONObjectWithData:[[logic queryValueForURLString:uri key:@"headers"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    CHECK("happ/ws-user-headers-without-host", [headers isEqual:@{@"X-Vless-Core": @"Value"}]);
    CHECK("happ/ws-early-data-and-heartbeat", [[logic queryValueForURLString:uri key:@"ed"] isEqual:@"128"] && [[logic queryValueForURLString:uri key:@"heartbeatPeriod"] isEqual:@"3"]);
    vless_config_t config = parsed(uri);
    CHECK("happ/core-ws-early-data", config.ws_early_data == 128 && config.ws_heartbeat_period == 3);
    CHECK("happ/core-ws-path-and-host", !strcmp(config.xhttp_path, "/socket") && !strcmp(config.xhttp_host, "preferred.test"));
    CHECK("happ/core-ws-headers", strstr(config.ws_headers, "Value") && !strstr(config.ws_headers, "legacy.test"));
    NSDictionary *grpc = @{@"serviceName": @"vless-core", @"authority": @"edge.test", @"multi_mode": @(YES), @"idle_timeout": @5,
        @"healthCheckTimeout": @20, @"permit_without_stream": @(NO), @"initial_windows_size": @65536, @"user_agent": @"vless-core"};
    uri = [logic vlessURIFromHappJSONConfig:profile(@"grpc", grpc, plain)];
    for (NSString *key in @[@"idleTimeout", @"healthCheckTimeout", @"permitWithoutStream", @"initialWindowsSize", @"userAgent"])
        CHECK("happ/grpc-settings-retained", [logic queryValueForURLString:uri key:key] != nil);
    CHECK("happ/grpc-false-is-not-lost", [[logic queryValueForURLString:uri key:@"permitWithoutStream"] isEqual:@"0"]);
    config = parsed(uri);
    CHECK("happ/core-grpc-settings", !strcmp(config.xhttp_mode, "multi") && config.grpc_idle_timeout == 5 && config.grpc_health_timeout == 20 && !config.grpc_permit_without_stream && config.grpc_initial_window == 65536 && !strcmp(config.grpc_user_agent, "vless-core"));
    CHECK("happ/grpc-alias-conflict-rejected", [logic vlessURIFromHappJSONConfig:profile(@"grpc", @{@"idle_timeout": @5, @"idleTimeout": @6}, plain)] == nil);
    for (NSDictionary *bad in @[@{@"ed": @16385}, @{@"heartbeatPeriod": @-1}, @{@"headers": @{@"X-Test": @"bad\r\ninjection"}}, @{@"ed": @1, @"maxEarlyData": @2}])
        CHECK("happ/ws-invalid-settings-rejected", [logic vlessURIFromHappJSONConfig:profile(@"ws", bad, plain)] == nil);
    for (NSDictionary *bad in @[@{@"initial_windows_size": @262145}, @{@"multiMode": @"false"}, @{@"idleTimeout": @1.5}])
        CHECK("happ/grpc-invalid-settings-rejected", [logic vlessURIFromHappJSONConfig:profile(@"grpc", bad, plain)] == nil);
    NSDictionary *download = @{@"network": @"xhttp", @"address": @"download.test", @"port": @443};
    uri = [logic vlessURIFromHappJSONConfig:profile(@"xhttp", @{@"path": @"/vless-core", @"downloadSettings": download, @"xmux": @{@"maxConnections": @2}}, plain)];
    NSDictionary *extra = [NSJSONSerialization JSONObjectWithData:[[logic queryValueForURLString:uri key:@"extra"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    CHECK("happ/xhttp-top-level-settings-retained", [[extra objectForKey:@"downloadSettings"] isEqual:download] && [[extra objectForKey:@"xmux"] isEqual:@{@"maxConnections": @2}]);
    config = parsed(uri);
    CHECK("happ/core-download-and-xmux", config.xhttp_download_settings[0] && config.xmux.present && config.xmux.max_connections.min == 2 && config.xmux.max_connections.max == 2);
    uri = [logic vlessURIFromHappJSONConfig:profile(@"xhttp", @{@"path": @"/explicit", @"downloadSettings": download, @"extra": @{@"path": @"/ignored", @"noGRPCHeader": @(YES)}}, plain)];
    extra = [NSJSONSerialization JSONObjectWithData:[[logic queryValueForURLString:uri key:@"extra"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    CHECK("happ/xray-extra-semantics", [[logic queryValueForURLString:uri key:@"path"] isEqual:@"/explicit"] && ![extra objectForKey:@"downloadSettings"] && [[extra objectForKey:@"noGRPCHeader"] boolValue]);
    uri = [logic vlessURIFromHappJSONConfig:profile(@"xhttp", @{@"extra": @{@"headers": @{@"Host": @"legacy.test", @"X-Test": @"Value"}}}, plain)];
    config = parsed(uri);
    CHECK("happ/xhttp-legacy-host-preserved", !strcmp(config.xhttp_host, "legacy.test") && strstr(config.xhttp_headers, "Value"));
    NSDictionary *good = profile(@"tcp", @{}, plain), *bad = profile(@"grpc", @{@"idle_timeout": @-1}, plain);
    NSData *batch = [NSJSONSerialization dataWithJSONObject:@{@"configs": @[bad, good]} options:0 error:NULL];
    CHECK("happ/invalid-entry-does-not-remove-valid-entry", [[logic extractConfigURIsFromHappJSONData:batch] count] == 1);
    CHECK("happ/import-warning-readable-reason", [[[logic importReportFromHappJSONData:batch] objectForKey:@"issues"] isEqual:@[@"Invalid or unsupported grpcSettings"]]);
    NSString *longPath = [@"/" stringByPaddingToLength:4096 withString:@"a" startingAtIndex:0];
    CHECK("happ/oversized-result-rejected", [logic vlessURIFromHappJSONConfig:profile(@"ws", @{@"path": longPath}, plain)] == nil);
}

static void socketProfiles(void) {
    VCProfileLogic *logic=VCProfiles();
    NSDictionary *original=profile(@"tcp",@{},@{@"id":@"11111111-2222-4333-8444-555555555555"});
    NSMutableDictionary *config=[[original mutableCopy] autorelease];
    NSMutableDictionary *outbound=[[[[original objectForKey:@"outbounds"] objectAtIndex:0] mutableCopy] autorelease];
    NSMutableDictionary *stream=[[[outbound objectForKey:@"streamSettings"] mutableCopy] autorelease];
    [stream setObject:@{@"tcpUserTimeout":@1234,@"tcpKeepAliveIdle":@17,@"tcpKeepAliveInterval":@9} forKey:@"sockopt"];
    [stream setObject:@{@"header":@{@"type":@"none"}} forKey:@"tcpSettings"];
    [outbound setObject:stream forKey:@"streamSettings"]; [config setObject:@[outbound] forKey:@"outbounds"];
    NSString *uri=[logic URIFromHappJSONConfig:config];
    CHECK("sockopt/json-converter-preserves-settings",[uri length] && [[logic queryValueForURLString:uri key:@"sockopt"] length]);
    if (uri) {
        vless_config_t parsedConfig=parsed(uri);
        CHECK("sockopt/app-core-parity",parsedConfig.sockopt.present==7 && parsedConfig.sockopt.user_timeout==1234 && parsedConfig.sockopt.keepalive_idle==17 && parsedConfig.sockopt.keepalive_interval==9);
        for (NSNumber *enabled in @[@(NO),@(YES)]) CHECK("sockopt/xmux-preserves-tcp-uri",[[logic runtimeURI:uri useXmux:[enabled boolValue] error:NULL] isEqual:uri]);
    }
    NSMutableArray *profiles=[NSMutableArray array];
    for (NSUInteger i=0;i<8;i++) {
        NSMutableDictionary *item=[[config mutableCopy] autorelease]; [item setObject:[NSString stringWithFormat:@"Fixture %lu",(unsigned long)i] forKey:@"remarks"]; [profiles addObject:item];
        [profiles addObject:@{@"outbounds":@[@{@"protocol":@"hysteria"}]}];
    }
    NSDictionary *report=[logic subscriptionImportReportFromData:[NSJSONSerialization dataWithJSONObject:profiles options:0 error:NULL]];
    CHECK("sockopt/sixteen-profile-subscription",[[report objectForKey:@"uris"] count]==8 && [[report objectForKey:@"skipped"] unsignedIntegerValue]==8);
    CHECK("sockopt/unsupported-protocol-reason",[[report objectForKey:@"issues"] containsObject:@"Unsupported proxy protocol: hysteria"]);
    CHECK("sockopt/import-report-without-socket-notices",![report objectForKey:@"warnings"]);
    for (NSString *timeout in @[@"1234",@"2147483647"]) {
        NSString *link=[NSString stringWithFormat:@"vless://11111111-2222-4333-8444-555555555555@127.0.0.1:443?sockopt=%%7B%%22tcpUserTimeout%%22%%3A%@%%7D",timeout];
        NSDictionary *entry=[logic metadataForURI:link];
        CHECK("sockopt/timeout-valid-without-warning",![entry objectForKey:@"reason"] && ![[entry objectForKey:@"warnings"] count]);
    }
    NSString *raw=[NSString stringWithFormat:@"{\"outbounds\":[{\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"example.test\",\"port\":443,\"users\":[{\"id\":\"11111111-2222-4333-8444-555555555555\"}]}]},\"streamSettings\":{\"sockopt\":%@}}]}",@"{\"tcpUserTimeout\":1,\"tcpUserTimeout\":2}"];
    for (NSString *bad in @[raw,[raw stringByReplacingOccurrencesOfString:@"1,\"tcpUserTimeout\":2" withString:@"1.0"],[raw stringByReplacingOccurrencesOfString:@"{\"tcpUserTimeout\":1,\"tcpUserTimeout\":2}" withString:@"{},\"sockopt\":{\"tcpUserTimeout\":2}"]]) {
        report=[logic subscriptionImportReportFromData:[bad dataUsingEncoding:NSUTF8StringEncoding]];
        CHECK("sockopt/invalid-raw-json-not-normalized",![[report objectForKey:@"uris"] count]);
        NSString *mixed=[NSString stringWithFormat:@"[%@,%@]",bad,[[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:original options:0 error:NULL] encoding:NSUTF8StringEncoding] autorelease]];
        report=[logic subscriptionImportReportFromData:[mixed dataUsingEncoding:NSUTF8StringEncoding]];
        CHECK("sockopt/invalid-json-keeps-neighbor",[[report objectForKey:@"uris"] count]==1 && [[report objectForKey:@"skipped"] unsignedIntegerValue]==1);
    }
    for (NSDictionary *bad in @[@{@"sockopt":@{@"mark":@1}},@{@"tcpSettings":@{@"header":@{@"type":@"http"}}},@{@"tcpSettings":@{},@"rawSettings":@{@"header":@{@"type":@"http"}}}]) {
        NSMutableDictionary *variant=[[original mutableCopy] autorelease],*out=[[outbound mutableCopy] autorelease];
        [out setObject:bad forKey:@"streamSettings"]; [variant setObject:@[out] forKey:@"outbounds"];
        report=[logic subscriptionImportReportFromData:[NSJSONSerialization dataWithJSONObject:variant options:0 error:NULL]];
        CHECK("sockopt/unsupported-settings-have-reason",![[report objectForKey:@"uris"] count] && [[report objectForKey:@"issues"] count]);
    }
    uint32_t seed=13371337;
    NSData *originalData=[raw dataUsingEncoding:NSUTF8StringEncoding];
    for (NSUInteger i=0;i<512;i++) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        NSMutableData *mutated=[[originalData mutableCopy] autorelease];
        unsigned char *bytes=[mutated mutableBytes];
        for (unsigned j=0;j<3;j++) { seed=seed*1664525U+1013904223U; NSUInteger offset=seed%[mutated length]; seed=seed*1664525U+1013904223U; bytes[offset]=(unsigned char)(seed>>24); }
        NSDictionary *result=[logic subscriptionImportReportFromData:mutated];
        CHECK("sockopt/bounded-json-mutations",[[result objectForKey:@"uris"] count]<=1 && [[result objectForKey:@"issues"] count]<=16);
        [pool drain];
    }
}

static void converterParity(void) {
    VCProfileLogic *p=VCProfiles();
    CHECK("converters/shared-karing-converter",[p respondsToSelector:@selector(URIFromKaringServer:error:)]);
    NSString *encryption=@"mlkem768x25519plus.native.0rtt.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8";
    NSDictionary *server=@{@"type":@"vless",@"server":@"example.test",@"server_port":@443,@"uuid":@"11111111-2222-4333-8444-555555555555",@"encryption":encryption,@"flow":@"xtls-rprx-vision",@"tls":@{@"enabled":@(YES),@"server_name":@"edge.test",@"utls":@{@"fingerprint":@"firefox"}},@"transport":@{@"type":@"ws",@"path":@"/socket",@"headers":@{@"Host":@"ws.test",@"X-Fixture":@"Value"},@"max_early_data":@128,@"heartbeat_period":@2}};
    NSString *error=nil,*uri=[p URIFromKaringServer:server error:&error];
    CHECK("converters/karing-valid",uri && !error);
    vless_config_t config=parsed(uri);
    CHECK("converters/karing-encryption-not-none",config.encryption_enabled && config.encryption_zero_rtt && !strcmp(config.flow,"xtls-rprx-vision"));
    CHECK("converters/karing-ws-preserved",config.ws_early_data == 128 && config.ws_heartbeat_period == 2 && strstr(config.ws_headers,"Value") && !strcmp(config.xhttp_host,"ws.test"));
    NSMutableDictionary *variant=[[server mutableCopy] autorelease];
    [variant setObject:@{@"type":@"grpc",@"service_name":@"service",@"multi_mode":@(NO),@"idle_timeout":@0,@"health_check_timeout":@10,@"permit_without_stream":@(NO),@"initial_windows_size":@65536,@"user_agent":@"fixture"} forKey:@"transport"];
    uri=[p URIFromKaringServer:variant error:&error]; config=parsed(uri);
    CHECK("converters/karing-grpc-preserved",config.grpc_idle_timeout == 0 && config.grpc_health_timeout == 10 && !config.grpc_permit_without_stream && config.grpc_initial_window == 65536 && !strcmp(config.grpc_user_agent,"fixture"));
    NSDictionary *xmux=@{@"maxConcurrency":@"",@"maxConnections":@3,@"cMaxReuseTimes":@0,@"hMaxRequestTimes":@"600-900",@"hMaxReusableSecs":@"1800-3000",@"hKeepAlivePeriod":@0};
    NSDictionary *down=@{@"address":@"download.test",@"port":@8443,@"network":@"xhttp",@"xhttpSettings":@{@"path":@"/download",@"xmux":xmux}};
    [variant setObject:@{@"type":@"xhttp",@"path":@"/upload",@"mode":@"stream-up",@"extra":@{@"xmux":xmux,@"downloadSettings":down}} forKey:@"transport"];
    uri=[p URIFromKaringServer:variant error:&error]; config=parsed(uri);
    CHECK("converters/karing-xmux-and-download",config.xmux.present && config.xmux.max_connections.min == 3 && config.xmux.max_concurrency.max == 0 && strstr(config.xhttp_download_settings,"download.test"));
    [variant setObject:@{@"enabled":@(YES),@"certificate_public_key_sha256":@[@"secret-pin"]} forKey:@"tls"];
    CHECK("converters/unsupported-trust-not-ignored",[p URIFromKaringServer:variant error:&error] == nil && error && ![error containsString:@"secret-pin"]);
    NSDictionary *bad=profile(@"ws",@{@"headers":@{@"X-Fixture":@"bad\r\nInjected"}},@{@"id":@"11111111-2222-4333-8444-555555555555"});
    NSDictionary *good=profile(@"tcp",@{},@{@"id":@"11111111-2222-4333-8444-555555555555"});
    for (id mux in @[@[],@{@"enabled":@[]},@{@"enabled":@"false"}]) {
        NSMutableDictionary *outbound=[[[[good objectForKey:@"outbounds"] objectAtIndex:0] mutableCopy] autorelease];
        [outbound setObject:mux forKey:@"mux"];
        CHECK("converters/mux-types-rejected",[p URIFromHappJSONConfig:@{@"outbounds":@[outbound]}] == nil);
    }
    NSDictionary *report=[p importReportFromHappJSONData:[NSJSONSerialization dataWithJSONObject:@[bad,good] options:0 error:NULL]];
    CHECK("converters/partial-import-reported",[[report objectForKey:@"uris"] count] == 1 && [[report objectForKey:@"skipped"] unsignedIntegerValue] == 1 && [[report objectForKey:@"issues"] count] == 1);
}

static void trojanProfiles(void) {
    VCProfileLogic *p=VCProfiles(); unichar zero=0;
    NSString *password=[[@" A+:%@é" stringByAppendingString:[NSString stringWithCharacters:&zero length:1]] stringByAppendingString:@"Z "];
    NSData *bytes=[password dataUsingEncoding:NSUTF8StringEncoding]; unsigned length=0; unsigned char expected[28];
    CHECK("trojan/expected-password-bytes",EVP_Digest([bytes bytes],[bytes length],expected,&length,EVP_sha224(),NULL) && length == 28);
    for (NSString *transport in @[@"tcp",@"ws",@"grpc",@"xhttp"]) for (NSString *security in @[@"none",@"tls",@"reality"]) {
        NSMutableDictionary *stream=[NSMutableDictionary dictionaryWithObjectsAndKeys:transport,@"network",security,@"security",@{@"serverName":@"edge.test",@"fingerprint":@"firefox"},@"tlsSettings",@{@"serverName":@"edge.test",@"publicKey":@"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",@"fingerprint":@"firefox"},@"realitySettings",nil];
        NSDictionary *target=@{@"address":@"example.test",@"port":@443,@"password":password};
        for (NSDictionary *settings in @[target,@{@"servers":@[target]}]) {
            NSDictionary *profile=@{@"outbounds":@[@{@"protocol":@"trojan",@"settings":settings,@"streamSettings":stream}]};
            NSString *uri=[p URIFromHappJSONConfig:profile];
            if ([transport isEqual:@"ws"] && [security isEqual:@"reality"]) { CHECK("trojan/ws-reality-rejected",!uri); continue; }
            vless_config_t config=parsed(uri);
            CHECK("trojan/happ-password-unchanged",config.protocol == CORE_PROTOCOL_TROJAN && !memcmp(config.trojan_hash,expected,28));
            CHECK("trojan/happ-security-preserved",!strcmp(config.security,[security UTF8String]));
            CHECK("trojan/metadata-does-not-contain-password",![[[p metadataForURI:uri] description] containsString:@"A+:%"]);
        }
    }
    NSDictionary *server=@{@"type":@"trojan",@"server":@"example.test",@"server_port":@443,@"password":password};
    NSString *uri=[p URIFromKaringServer:server error:NULL]; vless_config_t config=parsed(uri);
    CHECK("trojan/karing-no-trim-or-double-decode",!memcmp(config.trojan_hash,expected,28) && !strcmp(config.security,"none"));
    CHECK("trojan/default-tls",[[p securityTypeFromURI:@"trojan://a+b%00%FF@example.test:443"] isEqual:@"tls"]);
    for (NSString *suffix in @[@"?flow=xtls-rprx-vision",@"?encryption=mlkem768x25519plus.native.0rtt.secret",@"?type=ws&security=reality",@"?fp=android",@"?security=",@"?security=none&security=tls"])
        CHECK("trojan/unsupported-options-rejected",[p unsupportedConfigReasonForURI:[@"trojan://private@example.test:443" stringByAppendingString:suffix]] != nil);
    for (NSString *credential in @[@"",@"a%",@"a%0",@"a%GG"])
        CHECK("trojan/invalid-password-envelope",[p unsupportedConfigReasonForURI:[NSString stringWithFormat:@"trojan://%@@example.test:443",credential]] != nil);
    NSString *direct=@"trojan://a+b%3A%40%25@example.test:443#Fixture";
    CHECK("trojan/text-and-subscription-original",[[p parseSubscriptionData:[direct dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[direct]] && [[p extractImportLinksFromText:direct] isEqual:@[direct]]);
}

static NSString *vmessJSONURI(NSDictionary *json) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:json options:0 error:NULL];
    return [@"vmess://" stringByAppendingString:[data base64EncodedStringWithOptions:0]];
}

static void vmessProfiles(void) {
    VCProfileLogic *p=VCProfiles(); NSString *identifier=@"11111111-2222-4333-8444-555555555555";
    NSString *address=[NSString stringWithFormat:@"vmess://%@@example.test:443?type=ws&security=tls&scy=chacha20-poly1305",identifier];
    CHECK("vmess/app-address-supported",[p isSupportedConfigTupleForURI:address]);
    NSDictionary *json=@{@"v":@"2",@"add":@"example.test",@"port":@"443",@"id":identifier,@"aid":@0,@"scy":@"chacha20-poly1305",@"net":@"ws",@"tls":@"tls",@"ps":@"JSON title"};
    NSString *encoded=vmessJSONURI(json); NSDictionary *metadata=[p metadataForURI:encoded];
    CHECK("vmess/json-metadata",[p isSupportedConfigTupleForURI:encoded] && [[metadata objectForKey:@"host"] isEqual:@"example.test"] && [[metadata objectForKey:@"port"] intValue] == 443 && [[metadata objectForKey:@"transport"] isEqual:@"ws"] && [[metadata objectForKey:@"security"] isEqual:@"tls"]);
    CHECK("vmess/json-title",[[metadata objectForKey:@"title"] isEqual:@"JSON title"] && [[[[p metadataForURI:[encoded stringByAppendingString:@"#Outer%20title"]] objectForKey:@"title"] description] isEqual:@"Outer title"]);
    CHECK("vmess/no-id-in-metadata",![[metadata description] containsString:identifier] && ![metadata objectForKey:@"id"]);
    vless_config_t a=parsed(address),b=parsed(encoded);
    CHECK("vmess/effective-config-matches",a.protocol == CORE_PROTOCOL_VMESS && b.protocol == a.protocol && a.transport_mode == b.transport_mode && a.vmess_security == b.vmess_security && !memcmp(a.uuid,b.uuid,16));
    for (NSString *cipher in @[@"auto",@"aes-128-gcm",@"chacha20-poly1305",@"none",@"zero"]) {
        NSDictionary *target=@{@"address":@"example.test",@"port":@443,@"users":@[@{@"id":identifier,@"security":cipher,@"alterId":@0}]};
        NSDictionary *happ=@{@"outbounds":@[@{@"protocol":@"vmess",@"settings":@{@"vnext":@[target]}}]};
        NSString *uri=[p URIFromHappJSONConfig:happ]; a=parsed(uri);
        CHECK("vmess/happ-body-cipher",!strcmp(a.encryption,[cipher UTF8String]) && !strcmp(a.security,"none"));
        uri=[p URIFromKaringServer:@{@"type":@"vmess",@"server":@"example.test",@"server_port":@443,@"uuid":identifier,@"security":cipher,@"alter_id":@0} error:NULL];
        b=parsed(uri); CHECK("vmess/karing-effective-cipher",a.vmess_security == b.vmess_security && !memcmp(a.uuid,b.uuid,16));
    }
    for (NSString *suffix in @[@"?aid=1",@"?alterId=18446744073709551616",@"?scy=aes-128-cfb",@"?flow=xtls-rprx-vision",@"?encryption=auto&scy=none",@"?type=ws&security=reality"])
        CHECK("vmess/unsupported-options",[p unsupportedConfigReasonForURI:[[NSString stringWithFormat:@"vmess://%@@example.test:443",identifier] stringByAppendingString:suffix]] != nil);
    for (NSString *bad in @[@"A",@"AAAA=",@"AAAA===",@"AAAA!",@"_AAA+AAA"])
        CHECK("vmess/strict-base64",![p isSupportedConfigTupleForURI:[@"vmess://" stringByAppendingString:bad]]);
    for (NSDictionary *fields in @[@{@"aid":@1},@{@"scy":@"aes-128-cfb"},@{@"v":@3},@{@"port":@65536},@{@"add":@[]},@{@"tls":@"tls",@"security":@"none"}]) {
        NSMutableDictionary *bad=[[json mutableCopy] autorelease]; [bad addEntriesFromDictionary:fields];
        CHECK("vmess/json-invalid-shape",![p isSupportedConfigTupleForURI:vmessJSONURI(bad)]);
    }
    NSMutableDictionary *grpc=[[json mutableCopy] autorelease];
    [grpc addEntriesFromDictionary:@{@"net":@"grpc",@"type":@"multi",@"multiMode":@(YES),@"path":@"service",@"host":@"authority.test",@"sni":@"tls.test"}];
    NSString *grpcURI=vmessJSONURI(grpc);
    CHECK("vmess/json-grpc-metadata",[p isSupportedConfigTupleForURI:grpcURI] && [[p queryValueForURLString:grpcURI key:@"serviceName"] isEqual:@"service"] && [[p queryValueForURLString:grpcURI key:@"authority"] isEqual:@"authority.test"] && [[p queryValueForURLString:grpcURI key:@"mode"] isEqual:@"multi"] && [[p queryValueForURLString:grpcURI key:@"sni"] isEqual:@"tls.test"]);
    [grpc setObject:@(NO) forKey:@"multiMode"];
    CHECK("vmess/json-grpc-conflict",![p isSupportedConfigTupleForURI:vmessJSONURI(grpc)]);
    NSString *duplicate=[NSString stringWithFormat:@"{\"add\":\"example.test\",\"add\":\"other.test\",\"id\":\"%@\",\"port\":443}",identifier];
    CHECK("vmess/conflicting-duplicate-rejected",![p isSupportedConfigTupleForURI:[@"vmess://" stringByAppendingString:[[duplicate dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]]]);
    NSString *unpadded=[encoded stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
    CHECK("vmess/unpadded-json",[p isSupportedConfigTupleForURI:unpadded]);
    NSArray *mixed=[p parseSubscriptionData:[[NSString stringWithFormat:@"%@\n%@\ntrojan://secret@example.test:443",encoded,vmessJSONURI(@{@"add":@"bad"})] dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("vmess/mixed-subscription",[mixed count] == 2 && [[mixed objectAtIndex:0] isEqual:encoded]);
    CHECK("vmess/subscription-keeps-original",[[p parseSubscriptionData:[encoded dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[encoded]]);
}

static void shadowsocksProfiles(void) {
    VCProfileLogic *p=VCProfiles();
    NSString *raw=@"ss://aes-128-gcm:A%2B%3A%40%25%00z@example.test:443";
    CHECK("ss/raw-supported",[p isSupportedConfigTupleForURI:raw]);
    NSDictionary *metadata=[p metadataForURI:raw];
    CHECK("ss/metadata-no-credential",[[metadata objectForKey:@"host"] isEqual:@"example.test"] && [[metadata objectForKey:@"port"] intValue] == 443 && [[metadata objectForKey:@"method"] isEqual:@"aes-128-gcm"] && ![[metadata description] containsString:@"A+"]);
    NSString *password=@"A+:@%\0z";
    NSArray *methods=@[@"aes-128-gcm",@"aes-256-gcm",@"chacha20-poly1305",@"xchacha20-poly1305",@"2022-blake3-aes-128-gcm",@"2022-blake3-aes-256-gcm",@"2022-blake3-chacha20-poly1305"];
    for (NSString *method in methods) {
        BOOL modern=[method hasPrefix:@"2022-"];
        NSString *key=modern ? [[NSMutableData dataWithLength:[method hasSuffix:@"128-gcm"] ? 16 : 32] base64EncodedStringWithOptions:0] : password;
        NSDictionary *happ=@{@"outbounds":@[@{@"protocol":@"shadowsocks",@"settings":@{@"servers":@[@{@"address":@"example.test",@"port":@443,@"method":method,@"password":key}]}}]};
        NSString *uri=[p URIFromHappJSONConfig:happ]; vless_config_t a=parsed(uri);
        CHECK("ss/happ-method",a.protocol == CORE_PROTOCOL_SHADOWSOCKS && a.ss.count == 1 && !strcmp(a.security,"none"));
        uri=[p URIFromKaringServer:@{@"type":@"shadowsocks",@"server":@"example.test",@"server_port":@443,@"method":method,@"password":key} error:NULL];
        vless_config_t b=parsed(uri); CHECK("ss/karing-effective-keys",a.ss.method == b.ss.method && !memcmp(a.ss.keys,b.ss.keys,sizeof(a.ss.keys)));
        if (!modern) for (BOOL legacy=NO;;legacy=YES) {
            NSString *userinfo=[NSString stringWithFormat:@"%@:%@%@",method,password,legacy ? @"@example.test:443" : @""];
            NSString *encoded=[[userinfo dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
            NSString *link=[NSString stringWithFormat:@"ss://%@%@#Old",encoded,legacy ? @"" : @"@example.test:443/"];
            CHECK("ss/base64-envelopes",[p isSupportedConfigTupleForURI:link] && [[[p metadataForURI:link] objectForKey:@"host"] isEqual:@"example.test"]);
            b=parsed(link); CHECK("ss/base64-exact-password",a.ss.method == b.ss.method && !memcmp(a.ss.keys,b.ss.keys,sizeof(a.ss.keys)));
            CHECK("ss/original-subscription-uri",[[p parseSubscriptionData:[link dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[link]]);
            if (legacy) break;
        }
    }
    NSString *key=@"AAECAwQFBgcICQoLDA0ODw==";
    NSString *chain=[NSString stringWithFormat:@"ss://2022-blake3-aes-128-gcm:%@%%3A%@@example.test:443",key,key];
    CHECK("ss/sip023-kept",[p isSupportedConfigTupleForURI:chain] && parsed(chain).ss.count == 2);
    for (NSString *bad in @[@"ss://none:p@example.test:443",@"ss://aes-128-cfb:p@example.test:443",@"ss://aes-128-gcm:@example.test:443",@"ss://aes-128-gcm:p%GG@example.test:443",@"ss://aes-128-gcm:p@example.test:443?plugin=v2ray-plugin",@"ss://aes-128-gcm:p@example.test:443?flow=xtls-rprx-vision",@"ss://aes-128-gcm:p@example.test:443?encryption=auto",@"ss://aes-128-gcm:p@example.test:443?type=ws&security=reality",@"ss://A===@example.test:443",@"ss://_AAA+AAA@example.test:443"])
        CHECK("ss/invalid-envelope-or-options",![p isSupportedConfigTupleForURI:bad]);
    NSString *legacy2022=[NSString stringWithFormat:@"ss://%@",[[[NSString stringWithFormat:@"2022-blake3-aes-128-gcm:%@@example.test:443",key] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0]];
    CHECK("ss/2022-legacy-rejected",![p isSupportedConfigTupleForURI:legacy2022]);
    CHECK("ss/outer-none-keeps-method",[[[p metadataForURI:[raw stringByAppendingString:@"?encryption=none&security=none"]] objectForKey:@"method"] isEqual:@"aes-128-gcm"]);
    for (NSString *alias in @[@"aead_aes_128_gcm",@"aead_aes_256_gcm",@"chacha20-ietf-poly1305",@"aead_chacha20_poly1305",@"xchacha20-ietf-poly1305",@"aead_xchacha20_poly1305"])
        CHECK("ss/core-method-aliases",[p isSupportedConfigTupleForURI:[NSString stringWithFormat:@"ss://%@:p@example.test:443",alias]]);
    for (NSString *value in @[@"ss://@example.test:443",@"ss://?",@"ss://",@"ss://aes-128-gcm:p@[::1]:0",@"ss://aes-128-gcm:p@example.test:65536"])
        CHECK("ss/empty-and-endpoint-bounds",![p isSupportedConfigTupleForURI:value]);
}
static void crypt3Fixtures(void) {
    NSData *data=[NSData dataWithContentsOfFile:@"happ_crypt3_fixtures.json"];
    NSDictionary *fixtures=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    CHECK("happ/crypt3-fixtures-present",[fixtures count]==9);
    for (NSString *name in fixtures) {
        NSDictionary *fixture=[fixtures objectForKey:name];
        NSString *link=[fixture objectForKey:@"link"];
        CHECK("happ/crypt3-c-recognized",VCHappIsEncryptedLink([link UTF8String]));
        CHECK("happ/crypt3-foundation-recognized",HappURLStringIsEncrypted(link));
        CHECK("happ/crypt3-protected-subscription",SubscriptionDictionaryIsHappEncrypted(@{@"url":link}));
        CHECK("happ/crypt3-provider-headers",SubscriptionDictionaryUsesHappHeaders(@{@"url":link}));
        NSData *expected=DecodeBase64String([fixture objectForKey:@"plaintext_base64"]) ?: [NSData data];
        unsigned char *plain=NULL; size_t size=0; char mode[16],error[256];
        CHECK("happ/crypt3-independent-vector",VCHappDecryptLink([link UTF8String],&plain,&size,mode,sizeof(mode),error,sizeof(error))==1);
        CHECK("happ/crypt3-mode",!strcmp(mode,"crypt3"));
        CHECK("happ/crypt3-exact-plaintext",plain && size==[expected length] && (!size || !memcmp(plain,[expected bytes],size)));
        VCHappFreePlaintext(plain);
        NSString *errorText=nil,*decoded=VCHappDecryptedLink(link,&errorText);
        BOOL invalid=[@[@"invalid_utf8",@"nul",@"empty"] containsObject:name];
        if (invalid) CHECK("happ/crypt3-invalid-text-rejected",!decoded && [errorText length]);
        else CHECK("happ/crypt3-utf8-preserved",[decoded isEqual:[[[NSString alloc] initWithData:expected encoding:NSUTF8StringEncoding] autorelease]] && !errorText);
    }
    NSString *link=[[fixtures objectForKey:@"short"] objectForKey:@"link"];
    CHECK("happ/crypt3-text-import",[[VCProfiles() extractImportLinksFromText:link] isEqual:@[link]]);
    CHECK("happ/crypt3-photo-import",[[[VCProfiles() textImportReportFromTexts:@[link]] objectForKey:@"uris"] isEqual:@[link]]);
    NSString *uppercase=[@"HAPP://CRYPT3/" stringByAppendingString:[link substringFromIndex:14]];
    CHECK("happ/crypt3-case-insensitive",[VCHappDecryptedLink(uppercase,NULL) isEqual:VCHappDecryptedLink(link,NULL)]);
    NSString *unpadded=[link stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"="]];
    NSString *urlSafe=[@"happ://crypt3/" stringByAppendingString:[[[unpadded substringFromIndex:14] stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"]];
    for (NSString *variant in @[unpadded,urlSafe]) CHECK("happ/crypt3-base64-variants",[VCHappDecryptedLink(variant,NULL) isEqual:VCHappDecryptedLink(link,NULL)]);
    NSString *config=@"socks5://127.0.0.1:1080#Unchanged";
    NSString *mixed=[NSString stringWithFormat:@"%@\n%@\n%@",link,config,link];
    CHECK("happ/crypt3-mixed-dedup",[[[VCProfiles() textImportReportFromText:mixed] objectForKey:@"uris"] isEqual:@[link,config]]);
    NSString *encoded=[[mixed dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    CHECK("happ/crypt3-base64-list",[[[VCProfiles() textImportReportFromText:encoded] objectForKey:@"uris"] isEqual:@[link,config]]);
    CHECK("happ/crypt3-multiple-photo-values",[[[VCProfiles() textImportReportFromTexts:@[link,config,link]] objectForKey:@"uris"] isEqual:@[link,config]]);
    NSString *error=nil;
    NSDictionary *source=@{@"url":link,@"name":@"HAPP subscription",@"items":@[config]};
    NSDictionary *edited=[VCProfiles() subscriptionByEditingSource:source name:@"Provider" link:link userAgent:nil error:&error];
    CHECK("happ/crypt3-edit-preserves-wrapper",[[edited objectForKey:@"url"] isEqual:link] && SubscriptionDictionaryIsHappEncrypted(edited) && !error);
    for (NSString *name in @[@"invalid_utf8",@"nul",@"empty",@"unsupported",@"nested"]) {
        NSString *bad=[[fixtures objectForKey:name] objectForKey:@"link"];
        CHECK("happ/crypt3-invalid-edit-rejected",![VCProfiles() subscriptionByEditingSource:source name:@"Provider" link:bad userAgent:nil error:&error] && [error length]);
    }
    for (NSString *payload in @[@"",@"!",@"A",@"AA=A",@"AAAA=",@"AA===",@"AA",@"AB",@"AAB",@"AAAA"]) {
        NSString *bad=[@"happ://crypt3/" stringByAppendingString:payload];
        unsigned char *plain=NULL; size_t size=123; char reason[256];
        CHECK("happ/crypt3-malformed-rejected",VCHappDecryptLink([bad UTF8String],&plain,&size,NULL,0,reason,sizeof(reason))==-1 && !plain && !size && reason[0]);
    }
    NSMutableData *wire=[NSMutableData dataWithData:DecodeBase64String([link substringFromIndex:14])];
    memset([wire mutableBytes],0,[wire length]);
    NSString *badPadding=[@"happ://crypt3/" stringByAppendingString:[wire base64EncodedStringWithOptions:0]];
    CHECK("happ/crypt3-rsa-padding",!VCHappDecryptedLink(badPadding,&error) && [error rangeOfString:@"example.test"].location==NSNotFound);
    NSString *oversized=[@"happ://crypt3/" stringByPaddingToLength:8193 withString:@"A" startingAtIndex:0];
    CHECK("happ/crypt3-size-limit",!VCHappDecryptedLink(oversized,&error) && [error length]);
    unsigned char *plain=NULL; size_t size=0;
    CHECK("happ/crypt3-c-size-limit",VCHappDecryptLink([oversized UTF8String],&plain,&size,NULL,0,NULL,0)==-1 && !plain && !size);
    NSString *goldens=[NSString stringWithContentsOfFile:@"happ_fixtures.txt" encoding:NSUTF8StringEncoding error:NULL];
    NSString *crypt4=[[[goldens componentsSeparatedByString:@"\n"] objectAtIndex:0] substringFromIndex:7];
    CHECK("happ/crypt3-no-key-fallback",!VCHappDecryptedLink([crypt4 stringByReplacingOccurrencesOfString:@"crypt4/" withString:@"crypt3/"],&error));
    CHECK("happ/crypt4-no-key-fallback",!VCHappDecryptedLink([link stringByReplacingOccurrencesOfString:@"crypt3/" withString:@"crypt4/"],&error));
    for (NSString *bad in @[@"happ://crypt3/ https://must-not-fetch.test",@"happ://crypt3/! https://must-not-fetch.test",@"happ://crypt2/https://must-not-fetch.test"]) {
        NSArray *links=[VCProfiles() extractImportLinksFromText:bad];
        CHECK("happ/crypt3-no-inner-url-fallback",![links containsObject:@"https://must-not-fetch.test"]);
    }
    VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease];
    VCSubscriptionTask *previous=VCSetCurrentSubscriptionTask(task);
    NSDictionary *updated=[VCProfiles() updatedSubscriptionFromSource:source data:[config dataUsingEncoding:NSUTF8StringEncoding] nameFromMetadata:@"Provider" userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"HAPP subscription" hostName:@"HAPP subscription" options:task errorText:&error];
    CHECK("happ/crypt3-update-keeps-source",[[updated objectForKey:@"url"] isEqual:link] && SubscriptionDictionaryIsHappEncrypted(updated));
    unsigned char key[32]={1};
    NSData *serialized=[NSPropertyListSerialization dataFromPropertyList:updated format:NSPropertyListBinaryFormat_v1_0 errorDescription:NULL];
    NSData *encrypted=VCEncryptSecureStorePayload(serialized,key),*decrypted=VCDecryptSecureStorePayload(encrypted,key);
    NSDictionary *loaded=[NSPropertyListSerialization propertyListFromData:decrypted mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:NULL];
    CHECK("happ/crypt3-store-roundtrip",[loaded isEqual:updated] && [[loaded objectForKey:@"url"] isEqual:link]);
    [task cancelWithReason:nil];
    CHECK("happ/crypt3-cancelled-import",![[[VCProfiles() textImportReportFromText:mixed] objectForKey:@"uris"] count]);
    VCSetCurrentSubscriptionTask(previous);
}

static void modernFingerprints(void) {
    VCProfileLogic *logic=VCProfiles();
    NSArray *names=@[@"chrome",@"firefox",@"edge",@"qq",@"random",@"randomized",@"ios",@"safari",@"360",
        @"hellochrome_120",@"hellochrome_131",@"hellochrome_133",@"hellofirefox_120",@"hellofirefox_148",
        @"helloios_13",@"helloios_14",@"helloedge_106",@"hellosafari_26_3",@"hello360_11_0",@"helloqq_11_1",
        @"hellochrome_auto",@"hellofirefox_auto",@"helloedge_auto",@"helloqq_auto",@"helloios_auto",@"hellosafari_auto",@"hello360_auto"];
    for (NSString *name in names) {
        NSString *uri=[NSString stringWithFormat:@"vless://11111111-2222-4333-8444-555555555555@198.51.100.1:443?security=tls&fp=%@#Original%%20name",name];
        CHECK("fingerprint/direct-import",[logic isSupportedConfigTupleForURI:uri]);
        NSDictionary *report=[logic textImportReportFromText:uri];
        CHECK("fingerprint/original-uri-preserved",[[report objectForKey:@"uris"] isEqual:@[uri]]);
        for (NSNumber *enabled in @[@(NO),@(YES)]) CHECK("fingerprint/xmux-keeps-original-uri",[[logic runtimeURI:uri useXmux:[enabled boolValue] error:NULL] isEqual:uri]);
        for (NSString *prefix in @[@"trojan://fixture-password",@"vmess://11111111-2222-4333-8444-555555555555",@"ss://aes-128-gcm:fixture-password"]) {
            NSString *link=[NSString stringWithFormat:@"%@@198.51.100.1:443?security=tls&fp=%@",prefix,name];
            CHECK("fingerprint/all-protocols",[logic isSupportedConfigTupleForURI:link]);
            parsed(link);
        }
        NSDictionary *karing=@{@"type":@"vless",@"server":@"example.test",@"server_port":@443,@"uuid":@"11111111-2222-4333-8444-555555555555",
            @"tls":@{@"enabled":@(YES),@"utls":@{@"enabled":@(YES),@"fingerprint":name}}};
        NSString *karingURI=[logic URIFromKaringServer:karing error:NULL];
        CHECK("fingerprint/karing-import",karingURI && [[logic queryValueForURLString:karingURI key:@"fp"] isEqual:name]);
        parsed(karingURI);
        NSMutableDictionary *config=[profile(@"tcp",@{},@{@"id":@"11111111-2222-4333-8444-555555555555"}) mutableCopy];
        NSMutableDictionary *outbound=[[[config objectForKey:@"outbounds"] objectAtIndex:0] mutableCopy];
        NSMutableDictionary *stream=[[outbound objectForKey:@"streamSettings"] mutableCopy];
        [stream setObject:@{@"serverName":@"example.test",@"fingerprint":name} forKey:@"tlsSettings"];
        [outbound setObject:stream forKey:@"streamSettings"]; [config setObject:@[outbound] forKey:@"outbounds"];
        NSString *converted=[logic URIFromHappJSONConfig:config];
        CHECK("fingerprint/json-import",converted && [[logic queryValueForURLString:converted key:@"fp"] isEqual:name]);
        if (converted) {
            vless_config_t a=parsed(uri),b=parsed(converted);
            CHECK("fingerprint/converter-core-parity",a.fp_mode == b.fp_mode);
        }
        NSDictionary *vmess=@{@"v":@"2",@"add":@"example.test",@"port":@443,@"id":@"11111111-2222-4333-8444-555555555555",@"aid":@0,@"net":@"tcp",@"tls":@"tls",@"fp":name};
        CHECK("fingerprint/vmess-json-import",[logic isSupportedConfigTupleForURI:vmessJSONURI(vmess)]);
        [stream release]; [outbound release]; [config release];
    }
    NSMutableArray *mixed=[NSMutableArray array];
    for (NSUInteger i=0;i<49;i++) {
        NSString *name=i<33 ? @"hellofirefox_120" : i<37 ? @"ios" : i<41 ? @"firefox" : @"chrome";
        [mixed addObject:[NSString stringWithFormat:@"vless://11111111-2222-4333-8444-555555555555@198.51.100.1:%lu?security=tls&fp=%@",(unsigned long)443+i,name]];
    }
    NSDictionary *report=[logic subscriptionImportReportFromData:[[mixed componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("fingerprint/mixed-49-supported",[[report objectForKey:@"uris"] count] == 49 && ![[report objectForKey:@"skipped"] unsignedIntegerValue]);
    NSData *encoded=[[[[mixed componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0] dataUsingEncoding:NSUTF8StringEncoding];
    report=[logic subscriptionImportReportFromData:encoded];
    CHECK("fingerprint/base64-subscription",[[report objectForKey:@"uris"] count] == 49 && ![[report objectForKey:@"skipped"] unsignedIntegerValue]);
    CHECK("fingerprint/360-grpc-rejected",![logic isSupportedConfigTupleForURI:@"vless://11111111-2222-4333-8444-555555555555@198.51.100.1:443?security=tls&type=grpc&fp=360&alpn=h2"]);
    CHECK("fingerprint/360-reality-rejected",![logic isSupportedConfigTupleForURI:@"vless://11111111-2222-4333-8444-555555555555@198.51.100.1:443?security=reality&fp=360&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"]);
}

int main(int argc, char **argv) {
    if (argc==2 && (!strcmp(argv[1],"--happ-prepare") || !strcmp(argv[1],"--happ-update"))) {
        NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
        NSData *data=[[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        NSDictionary *output=nil;
        if (!strcmp(argv[1],"--happ-prepare")) {
            NSString *link=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
            NSString *target=VCHappDecryptedLink(link,NULL);
            if (VCValidatedProviderURLString(target)) output=@{@"value":target,@"happ":@(HappURLStringIsEncrypted(link)),@"agent":VCSubscriptionUserAgent(@{@"url":link},@"vless-core-app/test")};
        } else {
            NSDictionary *input=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease];
            output=[VCProfiles() updatedSubscriptionFromSource:[input objectForKey:@"source"] data:[[input objectForKey:@"body"] dataUsingEncoding:NSUTF8StringEncoding] nameFromMetadata:[input objectForKey:@"title"] userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"HAPP subscription" hostName:@"HAPP subscription" options:task errorText:NULL];
        }
        if (output) [[NSFileHandle fileHandleWithStandardOutput] writeData:[NSJSONSerialization dataWithJSONObject:output options:0 error:NULL]];
        int status=output ? 0 : 1;
        [pool drain]; return status;
    }
    if (argc == 2 && (!strcmp(argv[1], "--convert") || !strcmp(argv[1],"--convert-karing") || !strcmp(argv[1],"--convert-backup"))) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        NSArray *uris=nil;
        if (!strcmp(argv[1],"--convert-backup")) {
            NSMutableArray *items=[NSMutableArray array];
            for (NSDictionary *subscription in VCKaringSubscriptionsFromBackupData(data,NULL)) [items addObjectsFromArray:[subscription objectForKey:@"items"] ?: @[]];
            uris=items;
        } else if (!strcmp(argv[1],"--convert-karing")) {
            NSString *uri=[VCProfiles() URIFromKaringServer:[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] error:NULL];
            uris=uri ? @[uri] : @[];
        } else uris=[VCProfiles() extractConfigURIsFromHappJSONData:data];
        for (NSString *uri in uris) printf("%s\n", [uri UTF8String]);
        int result = [uris count] ? 0 : 1;
        [pool drain]; return result;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    crypt3Fixtures();
    NSString *incyAdd = @"incy://add/https://example.test/subscription?token=a%2Bb+%2540";
    CHECK("incy/import-keeps-whole-wrapper", [[VCProfiles() extractImportLinksFromText:incyAdd] isEqual:@[incyAdd]]);
    NSString *incyUnsupported = @"incy://routing/onadd/https://example.test/rules";
    CHECK("incy/unsupported-command-not-unwrapped", [[VCProfiles() extractImportLinksFromText:incyUnsupported] isEqual:@[incyUnsupported]]);
    NSString *fixtures = [NSString stringWithContentsOfFile:@"happ_fixtures.txt" encoding:NSUTF8StringEncoding error:NULL];
    CHECK("happ/golden-fixtures-present", [fixtures length] > 0);
    unsigned count = 0;
    for (NSString *line in [fixtures componentsSeparatedByString:@"\n"]) {
        NSRange separator = [line rangeOfString:@" "]; if (separator.location == NSNotFound) continue;
        NSString *name = [line substringToIndex:separator.location], *link = [line substringFromIndex:separator.location + 1];
        unsigned char *plain = NULL; size_t size = 0; char mode[32], error[256];
        CHECK([name UTF8String], VCHappDecryptLink([link UTF8String], &plain, &size, mode, sizeof(mode), error, sizeof(error)) == 1);
        CHECK("happ/known-plaintext", size == strlen("https://example.test/subscription?token=vless-core") && !memcmp(plain, "https://example.test/subscription?token=vless-core", size));
        VCHappFreePlaintext(plain); count++;
        NSString *truncated = [link substringToIndex:[link length] / 2]; plain = NULL;
        CHECK("happ/truncated-ciphertext-rejected", VCHappDecryptLink([truncated UTF8String], &plain, &size, mode, sizeof(mode), error, sizeof(error)) == -1 && plain == NULL);
    }
    CHECK("happ/all-modes-tested", count == 3);
    for (NSString *bad in @[@"happ://crypt4/!", @"happ://crypt4/A", @"happ://crypt5/short", @"happ://crypt5/AAAAAAAAAAAAAAAAAA"]) {
        unsigned char *plain = NULL; size_t size = 0; char error[256];
        CHECK("happ/malformed-encrypted-link", VCHappDecryptLink([bad UTF8String], &plain, &size, NULL, 0, error, sizeof(error)) == -1 && plain == NULL);
    }
    CHECK("happ/nonencrypted-link-distinguished", VCHappDecryptLink("https://example.test", NULL, NULL, NULL, 0, NULL, 0) == 0);
    NSString *encoded = [NSString stringWithContentsOfFile:@"karing_fixture.b64" encoding:NSUTF8StringEncoding error:NULL];
    NSData *archive = DecodeBase64String(encoded); NSString *error = nil;
    CHECK("karing/local-zip-fixture", VCKaringBackupDataLooksLikeZip(archive));
    NSArray *subscriptions = VCKaringSubscriptionsFromBackupData(archive, &error);
    CHECK("karing/zip-parse-and-url-dedup", [subscriptions count] == 2 && error == nil);
    CHECK("karing/socks-server-conversion", [[[[subscriptions objectAtIndex:0] objectForKey:@"items"] objectAtIndex:0] isEqual:@"socks5://u:p@proxy.test:1080#vless-core"]);
    CHECK("karing/zip-truncation", VCKaringSubscriptionsFromBackupData([archive subdataWithRange:NSMakeRange(0, 10)], &error) == nil && [error length] > 0);
    CHECK("karing/nonzip-rejected", VCKaringSubscriptionsFromBackupData([@"plain" dataUsingEncoding:NSUTF8StringEncoding], &error) == nil);
    NSDictionary *lan = VCKaringLANDownloadDescriptor(@"karing://sync-download/?ips=192.168.1.3,192.168.1.3,203.0.113.1&port=1234", &error);
    CHECK("karing/lan-only-dedup", [[lan objectForKey:@"hosts"] count] == 1 && [[lan objectForKey:@"port"] intValue] == 1234);
    CHECK("karing/public-lan-target-rejected", VCKaringLANDownloadDescriptor(@"karing://sync-download/?ips=203.0.113.1&port=1234", &error) == nil);
    CHECK("karing/invalid-lan-port", VCKaringLANDownloadDescriptor(@"karing://sync-download/?ips=192.168.1.3&port=0", &error) == nil);
    NSDictionary *config = @{@"outbounds": @[@{@"protocol": @"vless", @"settings": @{@"vnext": @[@{@"address": @"example.test", @"port": @443, @"users": @[@{@"id": @"11111111-2222-4333-8444-555555555555"}]}]}, @"streamSettings": @{@"network": @"tcp", @"security": @"tls", @"tlsSettings": @{@"serverName": @"edge.test"}}}]};
    NSData *json = [NSJSONSerialization dataWithJSONObject:config options:0 error:NULL];
    NSArray *uris = [VCProfiles() extractConfigURIsFromHappJSONData:json];
    CHECK("happ/json-conversion", [uris count] == 1 && [[uris objectAtIndex:0] rangeOfString:@"security=tls"].location != NSNotFound);
    NSDictionary *outbound = [[config objectForKey:@"outbounds"] objectAtIndex:0];
    for (NSString *security in @[@"none", @"tls", @"reality"]) {
        NSMutableDictionary *rawOutbound = [[outbound mutableCopy] autorelease];
        NSMutableDictionary *stream = [[[outbound objectForKey:@"streamSettings"] mutableCopy] autorelease];
        [stream setObject:@"raw" forKey:@"network"];
        [stream setObject:security forKey:@"security"];
        [stream setObject:@{@"serverName": @"edge.test", @"publicKey": @"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"} forKey:@"realitySettings"];
        [rawOutbound setObject:stream forKey:@"streamSettings"];
        NSDictionary *rawConfig = @{@"outbounds": @[rawOutbound]};
        NSString *rawURI = [VCProfiles() vlessURIFromHappJSONConfig:rawConfig];
        CHECK("happ/raw-network-supported", rawURI != nil && [VCProfiles() isSupportedConfigTupleForURI:rawURI]);
        NSData *rawJSON = [NSJSONSerialization dataWithJSONObject:rawConfig options:0 error:NULL];
        CHECK("happ/raw-network-json-import", [[VCProfiles() extractConfigURIsFromHappJSONData:rawJSON] isEqual:@[rawURI]]);
        [stream setObject:@"tcp" forKey:@"network"];
        CHECK("happ/raw-network-matches-tcp", [rawURI isEqual:[VCProfiles() vlessURIFromHappJSONConfig:rawConfig]]);
    }
    parserDependencies();
    extendedProfiles();
    socketProfiles();
    modernFingerprints();
    converterParity();
    trojanProfiles();
    vmessProfiles();
    shadowsocksProfiles();
    FINISH("import formats"); [pool drain]; return 0;
}
