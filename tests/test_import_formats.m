#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
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
    NSString *longPath = [@"/" stringByPaddingToLength:4096 withString:@"a" startingAtIndex:0];
    CHECK("happ/oversized-result-rejected", [logic vlessURIFromHappJSONConfig:profile(@"ws", @{@"path": longPath}, plain)] == nil);
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
    for (NSString *suffix in @[@"?flow=xtls-rprx-vision",@"?encryption=mlkem768x25519plus.native.0rtt.secret",@"?type=ws&security=reality",@"?fp=safari",@"?security=",@"?security=none&security=tls"])
        CHECK("trojan/unsupported-options-rejected",[p unsupportedConfigReasonForURI:[@"trojan://private@example.test:443" stringByAppendingString:suffix]] != nil);
    for (NSString *credential in @[@"",@"a%",@"a%0",@"a%GG"])
        CHECK("trojan/invalid-password-envelope",[p unsupportedConfigReasonForURI:[NSString stringWithFormat:@"trojan://%@@example.test:443",credential]] != nil);
    NSString *direct=@"trojan://a+b%3A%40%25@example.test:443#Fixture";
    CHECK("trojan/text-and-subscription-original",[[p parseSubscriptionData:[direct dataUsingEncoding:NSUTF8StringEncoding]] isEqual:@[direct]] && [[p extractImportLinksFromText:direct] isEqual:@[direct]]);
}
int main(int argc, char **argv) {
    if (argc == 2 && (!strcmp(argv[1], "--convert") || !strcmp(argv[1],"--convert-karing"))) {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSData *data = [[NSFileHandle fileHandleWithStandardInput] readDataToEndOfFile];
        NSArray *uris=nil;
        if (!strcmp(argv[1],"--convert-karing")) {
            NSString *uri=[VCProfiles() URIFromKaringServer:[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] error:NULL];
            uris=uri ? @[uri] : @[];
        } else uris=[VCProfiles() extractConfigURIsFromHappJSONData:data];
        for (NSString *uri in uris) printf("%s\n", [uri UTF8String]);
        int result = [uris count] ? 0 : 1;
        [pool drain]; return result;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
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
    converterParity();
    trojanProfiles();
    FINISH("import formats"); [pool drain]; return 0;
}
