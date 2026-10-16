#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
#import "../common/secure_store.h"
#import "../common/connection_logic.h"
#import "../common/list_logic.h"
#import "../common/app_constants.h"
#include "check.h"
#include <sys/stat.h>
#include <unistd.h>

@interface VCFakePingOwner : NSObject { @public NSUInteger cancellations; }
- (void)stopAllPings;
@end
@implementation VCFakePingOwner
- (void)stopAllPings { cancellations++; }
@end

@interface VCUpdateOptions : NSObject <VCSubscriptionUpdateOptions> {
@public
    BOOL preserve;
    NSTimeInterval timestamp;
    NSUInteger timestampReads;
}
@end
@implementation VCUpdateOptions
- (BOOL)preserveCustomSubscriptionNames { return preserve; }
- (NSTimeInterval)subscriptionUpdateTimestamp { timestampReads++; return timestamp; }
@end

@interface VCMemoryDefaults : NSObject { NSMutableDictionary *values; }
- (id)objectForKey:(NSString *)key;
- (NSString *)stringForKey:(NSString *)key;
- (NSArray *)arrayForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
- (double)doubleForKey:(NSString *)key;
- (void)setObject:(id)value forKey:(NSString *)key;
- (void)setBool:(BOOL)value forKey:(NSString *)key;
- (void)setDouble:(double)value forKey:(NSString *)key;
- (BOOL)synchronize;
@end
@implementation VCMemoryDefaults
- (id)init { self = [super init]; if (self) values = [[NSMutableDictionary alloc] init]; return self; }
- (void)dealloc { [values release]; [super dealloc]; }
- (id)objectForKey:(NSString *)key { return [values objectForKey:key]; }
- (NSString *)stringForKey:(NSString *)key { return [values objectForKey:key]; }
- (NSArray *)arrayForKey:(NSString *)key { return [values objectForKey:key]; }
- (BOOL)boolForKey:(NSString *)key { return [[values objectForKey:key] boolValue]; }
- (double)doubleForKey:(NSString *)key { return [[values objectForKey:key] doubleValue]; }
- (void)setObject:(id)value forKey:(NSString *)key { [values setObject:value forKey:key]; }
- (void)setBool:(BOOL)value forKey:(NSString *)key { [values setObject:[NSNumber numberWithBool:value] forKey:key]; }
- (void)setDouble:(double)value forKey:(NSString *)key { [values setObject:[NSNumber numberWithDouble:value] forKey:key]; }
- (BOOL)synchronize { return YES; }
@end

static NSString *keyReply;
static NSString *lastCommand;
static NSString *fakeCommand(NSString *command) { lastCommand = command; return keyReply; }
static BOOL protectionOK = YES;
static BOOL fakeProtection(NSString *path) { (void)path; return protectionOK; }

static void connectionTests(void) {
    CHECK("connection/idle-connect-allowed", VCConnectionToggleGate(NO, NO, NO) == VCConnectionGateAllowed);
    CHECK("connection/update-busy", VCConnectionToggleGate(YES, NO, NO) == VCConnectionGateBusy);
    CHECK("connection/action-busy", VCConnectionToggleGate(NO, YES, NO) == VCConnectionGateBusy);
    CHECK("connection/switch-in-progress", VCConnectionToggleGate(NO, NO, YES) == VCConnectionGateSwitching);
    for (NSUInteger flags = 0; flags < 8; flags++) {
        CHECK("connection/refresh-conflict-matrix", VCConnectionActionInProgress(!!(flags & 1), !!(flags & 2), !!(flags & 4)) == (flags != 0));
    }
    CHECK("connection/offline-selection-during-refresh", !VCConfigurationSelectionBlocked(NO, NO, YES));
    CHECK("connection/online-selection-during-refresh", VCConfigurationSelectionBlocked(NO, YES, YES));
    CHECK("connection/offline-config-change-no-switch", !VCConfigSwitchNeeded(NO, @"old", @"new", NO, NO));
    CHECK("connection/online-config-change-switches", VCConfigSwitchNeeded(YES, @"old", @"new", NO, NO));
    CHECK("connection/same-config-no-switch", !VCConfigSwitchNeeded(YES, @"old", @"old", NO, NO));
    CHECK("connection/log-protection-change-switches", VCConfigSwitchNeeded(YES, @"old", @"old", NO, YES));
    CHECK("connection/invalid-selection-no-switch", !VCConfigSwitchNeeded(YES, nil, @"new", NO, NO));
    VCFakePingOwner *owner = [[[VCFakePingOwner alloc] init] autorelease];
    VCConnectionTouchDown(owner, YES);
    CHECK("connection/pings-cancel-on-press", owner->cancellations == 1);
    VCConnectionTouchDown(owner, NO);
    CHECK("connection/other-button-does-not-cancel", owner->cancellations == 1);
    VCConnectionTouchDown(owner, YES);
    CHECK("connection/disconnect-press-also-cancels", owner->cancellations == 2);
    CHECK("connection/uptime-restored", VCConnectedSince(@"OK connected socks=1080 since=900", 1000) == 900);
    CHECK("connection/uptime-whitespace", VCConnectedSince(@"OK\nsince=900\tprotected=1", 1000) == 900);
    for (NSString *response in @[@"OK", @"OK since=0", @"OK since=-1", @"OK since=1001", @"OK since=900x", @"OK since=x"])
        CHECK("connection/invalid-since-falls-back", VCConnectedSince(response, 1000) == 1000);
    CHECK("connection/uptime-format", [VCFormatDuration(3661) isEqual:@"01:01:01"]);
    CHECK("connection/negative-uptime", [VCFormatDuration(-12) isEqual:@"00:00:00"]);
    CHECK("connection/long-uptime", [VCFormatDuration(360000) isEqual:@"100:00:00"]);
    CHECK("connection/helper-loss-current-session", VCConnectionLossApplies(YES, YES, 1, 1, NO, 900, 900));
    CHECK("connection/helper-loss-stale-generation", !VCConnectionLossApplies(YES, YES, 1, 2, NO, 900, 900));
    CHECK("connection/helper-loss-during-switch", !VCConnectionLossApplies(YES, YES, 1, 1, YES, 900, 900));
    CHECK("connection/helper-loss-new-session", !VCConnectionLossApplies(YES, YES, 1, 1, NO, 900, 950));
}

static void importTests(void) {
    VCProfileLogic *p = VCProfiles();
    CHECK("import/empty-text-data", [p decodeImportTextData:[NSData data]] == nil);
    NSString *unicode = @"socks5://proxy.test:1080#vless-core Тест";
    CHECK("import/utf8-text", [[p decodeImportTextData:[unicode dataUsingEncoding:NSUTF8StringEncoding]] isEqual:unicode]);
    CHECK("import/cp1251-text", [[p decodeImportTextData:[unicode dataUsingEncoding:NSWindowsCP1251StringEncoding]] isEqual:unicode]);
    NSString *base = @"vless://11111111-2222-4333-8444-555555555555@example.test:443";
    for (NSString *transport in @[@"tcp", @"raw", @"xhttp", @"splithttp", @"grpc", @"ws", @"websocket"]) {
        for (NSString *security in @[@"none", @"tls", @"reality"]) {
            NSString *uri = [NSString stringWithFormat:@"%@?type=%@&security=%@", base, transport, security];
            BOOL supported = !(([transport isEqual:@"ws"] || [transport isEqual:@"websocket"]) && [security isEqual:@"reality"]);
            CHECK("import/transport-security-matrix", [p isSupportedConfigTupleForURI:uri] == supported);
        }
    }
    for (NSString *key in @[@"type", @"transport", @"network", @"net"]) {
        for (NSString *value in @[@"raw", @"RAW", @"%72aw"]) {
            NSString *uri = [base stringByAppendingFormat:@"?%@=%@", key, value];
            CHECK("import/raw-alias-normalized", [[p transportTypeFromURI:uri] isEqual:@"tcp"]);
            CHECK("import/raw-alias-supported", [p isSupportedConfigTupleForURI:uri]);
        }
        for (NSString *security in @[@"none", @"tls", @"reality"]) {
            NSString *uri = [base stringByAppendingFormat:@"?%@=raw&security=%@&flow=xtls-rprx-vision", key, security];
            CHECK("import/raw-vision-security-policy", [p isSupportedConfigTupleForURI:uri] == ![security isEqual:@"none"]);
            CHECK("import/raw-invalid-flow-rejected", ![p isSupportedConfigTupleForURI:[base stringByAppendingFormat:@"?%@=raw&security=%@&flow=unsupported", key, security]]);
        }
        CHECK("import/raw-invalid-fingerprint-rejected", ![p isSupportedConfigTupleForURI:[base stringByAppendingFormat:@"?%@=raw&security=reality&fp=unknown", key]]);
    }
    for (NSString *mode in @[@"auto", @"packet-up", @"stream-one", @"stream-up"])
        CHECK("import/xhttp-mode-matrix", [p isSupportedConfigTupleForURI:[base stringByAppendingFormat:@"?type=xhttp&security=tls&mode=%@", mode]]);
    for (NSString *query in @[@"type=tcp&type=ws", @"type=raw&network=tcp", @"type=raw&type=ws", @"type=raw-invalid", @"security=tls&security=none", @"type=tcp&flow=unsupported", @"type=xhttp&mode=invalid", @"type=grpc&mode=invalid", @"type=tcp&security=reality&fp=unknown", @"type=quic", @"type=%ZZ"]) {
        const char *scenario = [[@"import/rejected/" stringByAppendingString:query] UTF8String];
        CHECK(scenario, ![p isSupportedConfigTupleForURI:[base stringByAppendingFormat:@"?%@", query]]);
    }
    CHECK("import/socks-plain", [p isSupportedConfigTupleForURI:@"socks5://proxy.test:1080"]);
    CHECK("import/socks-explicit-none", [p isSupportedConfigTupleForURI:@"socks5://proxy.test:1080?security=none"]);
    CHECK("import/socks-tls-is-not-supported", ![p isSupportedConfigTupleForURI:@"socks5://proxy.test:1080?security=tls"]);
    NSString *encryptedVision = [base stringByAppendingString:@"?type=tcp&security=none&flow=xtls-rprx-vision&encryption=mlkem768x25519plus.native.0rtt.AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8"];
    CHECK("import/encrypted-vision-without-outer-tls", [p isSupportedConfigTupleForURI:encryptedVision]);
    for (NSString *transport in @[@"tcp", @"ws", @"grpc", @"xhttp"]) {
        NSString *candidate = [encryptedVision stringByReplacingOccurrencesOfString:@"type=tcp" withString:[@"type=" stringByAppendingString:transport]];
        CHECK("import/encrypted-vision-transport-matrix", [p isSupportedConfigTupleForURI:candidate]);
        NSString *bad = [candidate stringByReplacingOccurrencesOfString:@"flow=xtls-rprx-vision" withString:@"flow=not-supported"];
        CHECK("import/unsupported-flow-rejected", ![p isSupportedConfigTupleForURI:bad]);
    }
    CHECK("import/socks-credentials-ipv6", [p isSupportedConfigTupleForURI:@"socks5://user:pass@[2001:db8::1]:1080#vless-core"]);
    CHECK("import/socks-zero-port", ![p isSupportedConfigTupleForURI:@"socks5://proxy.test:0"]);
    CHECK("import/foreign-protocol", ![p isSupportedConfigTupleForURI:@"trojan://secret@example.test:443"]);
    NSString *feed = [NSString stringWithFormat:@"%@?type=tcp\n%@?type=tcp\nsocks5://proxy.test:1080\n", base, base];
    CHECK("import/text-deduplication", [[p parseSubscriptionData:[feed dataUsingEncoding:NSUTF8StringEncoding]] count] == 2);
    NSString *b64 = [[feed dataUsingEncoding:NSUTF8StringEncoding] base64EncodedStringWithOptions:0];
    CHECK("import/base64-subscription", [[p parseSubscriptionData:[b64 dataUsingEncoding:NSUTF8StringEncoding]] count] == 2);
    NSString *rawURI = [base stringByAppendingString:@"?type=raw&security=tls#vless-core"];
    NSArray *rawSubscription = [p parseSubscriptionData:[rawURI dataUsingEncoding:NSUTF8StringEncoding]];
    CHECK("import/raw-subscription-preserves-uri", [rawSubscription count] == 1 && [[rawSubscription objectAtIndex:0] isEqual:rawURI]);
    CHECK("import/raw-subscription-supported", [p isSupportedConfigTupleForURI:[rawSubscription firstObject]]);
    CHECK("import/empty-subscription", [[p parseSubscriptionData:[NSData data]] count] == 0);
    NSDictionary *info = [p subscriptionUserInfoFromHeaderValue:@"upload=1024; download=2048; total=4096; expire=1900000000"];
    CHECK("subscription/usage-metadata", [[info objectForKey:@"download"] unsignedLongLongValue] == 2048);
    CHECK("subscription/invalid-negative-metadata", [[p subscriptionUserInfoFromHeaderValue:@"download=-1"] count] == 0);
    NSDictionary *headers = @{@"Subscription-Userinfo": @"total=999"};
    CHECK("subscription/case-insensitive-headers", [[[p subscriptionUserInfoFromHTTPHeaders:headers] objectForKey:@"total"] intValue] == 999);
    CHECK("subscription/body-metadata", [[[p subscriptionUserInfoFromData:[@"# subscription-userinfo: total=123\n" dataUsingEncoding:NSUTF8StringEncoding]] objectForKey:@"total"] intValue] == 123);
    CHECK("http/plain-recognized", URLStringUsesPlainHTTP(@"http://example.test/feed"));
    CHECK("http/https-not-plain", !URLStringUsesPlainHTTP(@"https://example.test/feed"));
    CHECK("http/plain-denied-by-default", !SubscriptionDictionaryAllowsPlainHTTP(@{@"url": @"http://example.test"}));
    CHECK("http/plain-explicit-approval", SubscriptionDictionaryAllowsPlainHTTP(@{@"allow_plain_http": @(YES)}));
    CHECK("tls/no-insecure-default", !SubscriptionDictionaryAllowsInsecureFetch(@{}));
    CHECK("tls/certificate-errors-retry-policy", CurlExitCodeCanRetryInsecurely(60) && !CurlExitCodeCanRetryInsecurely(7));
    CHECK("subscription/html-rejected", SubscriptionDataLooksLikeHTML([@"<!DOCTYPE html><html>error</html>" dataUsingEncoding:NSUTF8StringEncoding]));
    CHECK("subscription/provider-url-no-script", VCValidatedProviderURLString(@"javascript:alert(1)") == nil);
    CHECK("subscription/happ-headers", SubscriptionDictionaryUsesHappHeaders(@{@"happ_source": @(YES)}));
    CHECK("subscription/happ-protected", SubscriptionDictionaryIsHappEncrypted(@{@"url": @"happ://crypt5/vless-core"}));
    CHECK("tls/certificate-error-retry", NSURLErrorCanRetryInsecurely([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorServerCertificateUntrusted userInfo:nil]));
    CHECK("tls/network-error-no-insecure-retry", !NSURLErrorCanRetryInsecurely([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil]));
    NSDictionary *subscription = @{kSubscriptionMetadataKey: @{kSubscriptionDescriptionKey: @"  Description\n", kSubscriptionWebPageURLKey: @"https://example.test/", kSubscriptionLastUpdatedKey: @0}};
    CHECK("subscription/description-trimmed", [VCSubscriptionDescription(subscription) isEqual:@"Description"]);
    CHECK("subscription/provider-link", [VCSubscriptionProviderURL(subscription, kSubscriptionWebPageURLKey) isEqual:@"https://example.test/"]);
    CHECK("subscription/no-update-date", [VCSubscriptionLastUpdatedText(subscription) isEqual:@"Updated: Never"]);
    CHECK("subscription/malformed-metadata", VCSubscriptionMetadataDictionary(@{kSubscriptionMetadataKey: @"invalid"}) == nil);
}

static void subscriptionUpdateTests(void) {
    VCProfileLogic *profile = VCProfiles();
    VCUpdateOptions *options = [[[VCUpdateOptions alloc] init] autorelease];
    options->timestamp = 123456;
    options->preserve = YES;
    NSDictionary *source = @{@"url": @"https://example.test/sub", @"name": @"Custom", kSubscriptionCustomNameKey: @"Custom", @"items": @[@"old"], kSubscriptionUserInfoKey: @{kSubscriptionTotalKey: @999}, kSubscriptionMetadataKey: @{kSubscriptionDescriptionKey: @"Old description"}};
    NSString *feed = @"# profile-title: Body title\n# announce: Body description\nsocks5://proxy.test:1080\nsocks5://proxy.test:1080\nsocks5://second.test:1080\n";
    NSData *data = [feed dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *metadata = @{kSubscriptionDescriptionKey: @"Header description"};
    NSString *error = nil;
    NSDictionary *updated = [profile updatedSubscriptionFromSource:source data:data nameFromMetadata:@"Header title" userInfoFromMetadata:@{kSubscriptionTotalKey: @123} metadataFromResponse:metadata nameFromURL:@"URL name" hostName:@"example.test" options:options errorText:&error];
    CHECK("subscription/update-deduplicates-items", [[updated objectForKey:@"items"] count] == 2);
    CHECK("subscription/update-preserves-custom-name", [[updated objectForKey:@"name"] isEqual:@"Custom"] && [[updated objectForKey:kSubscriptionCustomNameKey] isEqual:@"Custom"]);
    CHECK("subscription/header-metadata-precedes-body", [[VCSubscriptionMetadataDictionary(updated) objectForKey:kSubscriptionDescriptionKey] isEqual:@"Header description"]);
    CHECK("subscription/update-traffic-replaced", [[[updated objectForKey:kSubscriptionUserInfoKey] objectForKey:kSubscriptionTotalKey] intValue] == 123);
    CHECK("subscription/update-clock-injected", [[VCSubscriptionMetadataDictionary(updated) objectForKey:kSubscriptionLastUpdatedKey] longLongValue] == 123456 && options->timestampReads == 1);
    CHECK("subscription/update-source-not-mutated", [[[source objectForKey:@"items"] objectAtIndex:0] isEqual:@"old"] && [VCSubscriptionDescription(source) isEqual:@"Old description"]);
    options->preserve = NO;
    updated = [profile updatedSubscriptionFromSource:source data:data nameFromMetadata:nil userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"URL name" hostName:@"example.test" options:options errorText:&error];
    CHECK("subscription/update-body-title-fallback", [[updated objectForKey:@"name"] isEqual:@"Body title"] && [updated objectForKey:kSubscriptionCustomNameKey] == nil);
    CHECK("subscription/update-old-traffic-cleared", [updated objectForKey:kSubscriptionUserInfoKey] == nil);
    CHECK("subscription/update-body-description-fallback", [VCSubscriptionDescription(updated) isEqual:@"Body description"]);
    NSDictionary *headers = @{@"Profile-Title": @"base64:SGVhZGVyIHRpdGxl", @"Announce": @"Description%20text", @"Profile-Update-Interval": @"12"};
    CHECK("subscription/title-header-decoding", [[profile subscriptionTitleFromHTTPHeaders:headers] isEqual:@"Header title"]);
    CHECK("subscription/metadata-header-decoding", [[[profile subscriptionMetadataFromHTTPHeaders:headers] objectForKey:kSubscriptionDescriptionKey] isEqual:@"Description text"]);
    CHECK("subscription/metadata-update-interval", [[[profile subscriptionMetadataFromHTTPHeaders:headers] objectForKey:kSubscriptionUpdateIntervalKey] intValue] == 12);
    CHECK("subscription/bytes-scaling", [[profile formattedSubscriptionBytes:1024] isEqual:@"1.0 KB"] && [[profile formattedSubscriptionBytes:11 * 1024] isEqual:@"11 KB"]);
    CHECK("subscription/unlimited-traffic", [[profile subscriptionTrafficTextFromDictionary:@{kSubscriptionUserInfoKey: @{kSubscriptionDownloadKey: @1024, kSubscriptionTotalKey: @0}}] isEqual:@"1.0 KB / ∞"]);
    CHECK("subscription/no-expiry", [[profile subscriptionExpiryTextFromDictionary:@{kSubscriptionUserInfoKey: @{kSubscriptionExpireKey: @0}}] isEqual:@"No expiry"]);
    NSUInteger before = options->timestampReads;
    error = nil;
    updated = [profile updatedSubscriptionFromSource:source data:[@"<!doctype html><html>error</html>" dataUsingEncoding:NSUTF8StringEncoding] nameFromMetadata:nil userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"URL name" hostName:@"example.test" options:options errorText:&error];
    CHECK("subscription/update-html-error", updated == nil && [error isEqual:@"Server returned a web page, not subscription data"]);
    CHECK("subscription/failed-update-no-clock-or-mutation", options->timestampReads == before && [[[source objectForKey:@"items"] objectAtIndex:0] isEqual:@"old"]);
    error = nil;
    updated = [profile updatedSubscriptionFromSource:source data:[NSData data] nameFromMetadata:nil userInfoFromMetadata:nil metadataFromResponse:nil nameFromURL:@"URL name" hostName:@"example.test" options:options errorText:&error];
    CHECK("subscription/empty-update-rejected", updated == nil && [error isEqual:@"Subscription has no valid config entries"]);
}

static void dataTests(void) {
    unsigned char key[32] = {1};
    NSData *plain = [@"vless-core secret vless://uuid@example.test" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *encrypted = VCEncryptSecureStorePayload(plain, key);
    CHECK("storage/encrypt-decrypt", [VCDecryptSecureStorePayload(encrypted, key) isEqual:plain]);
    CHECK("storage/nonces-are-fresh", ![VCEncryptSecureStorePayload(plain, key) isEqual:encrypted]);
    key[1] = 2;
    CHECK("storage/wrong-key", VCDecryptSecureStorePayload(encrypted, key) == nil);
    key[1] = 0;
    for (NSUInteger i = 0; i < [encrypted length]; i++) {
        NSMutableData *damaged = [encrypted mutableCopy]; ((unsigned char *)[damaged mutableBytes])[i] ^= 1;
        CHECK("storage/tamper-every-byte", VCDecryptSecureStorePayload(damaged, key) == nil); [damaged release];
    }
    CHECK("storage/truncated-header", VCDecryptSecureStorePayload([encrypted subdataWithRange:NSMakeRange(0, 20)], key) == nil);
    char directory[] = "/tmp/vless-host-storage.XXXXXX";
    CHECK("storage/private-temp-directory", mkdtemp(directory) != NULL);
    NSString *root = [NSString stringWithUTF8String:directory];
    VCStoragePaths paths = {root, [root stringByAppendingPathComponent:@"configs.dat"], [root stringByAppendingPathComponent:@"events.sqlite3"], fakeCommand, fakeProtection};
    keyReply = @"OK 0100000000000000000000000000000000000000000000000000000000000000\n";
    NSArray *configs = @[@{@"uri": @"socks5://example.test:1080"}];
    VCConfigurationDataSelection initial = VCInitialConfigurationData(nil, NO, configs, @[], YES);
    CHECK("storage/legacy-migration-source", initial.configs == configs && initial.writable);
    initial = VCInitialConfigurationData(nil, YES, nil, nil, YES);
    CHECK("storage/corrupt-store-not-overwritten", !initial.writable && initial.configs == nil);
    initial = VCInitialConfigurationData(@{@"configs": @[], @"subscriptions": @[]}, YES, configs, nil, YES);
    CHECK("storage/protected-data-preferred", [initial.configs count] == 0 && initial.writable);
    CHECK("storage/save-real-file", VCSaveProtectedConfigurationDataAtPaths(configs, @[], &paths));
    CHECK("storage/create-key-command", [lastCommand isEqual:@"STORE_KEY\tCREATE\n"]);
    BOOL exists = NO;
    CHECK("storage/load-real-file", [[[VCLoadProtectedConfigurationDataAtPaths(&exists, &paths) objectForKey:@"configs"] firstObject] isEqual:[configs firstObject]] && exists);
    CHECK("storage/get-key-command", [lastCommand isEqual:@"STORE_KEY\tGET\n"]);
    struct stat st; CHECK("storage/file-permissions", stat([paths.file fileSystemRepresentation], &st) == 0 && (st.st_mode & 0777) == 0600);
    keyReply = @"OK invalid";
    CHECK("storage/malformed-key-no-overwrite", !VCSaveProtectedConfigurationDataAtPaths(@[], @[], &paths));
    keyReply = @"OK 0100000000000000000000000000000000000000000000000000000000000000";
    protectionOK = NO;
    CHECK("storage/protection-failure-keeps-old-file", !VCSaveProtectedConfigurationDataAtPaths(@[], @[], &paths));
    protectionOK = YES;
    NSMutableArray *events = [NSMutableArray array];
    for (NSInteger i = 1; i <= 300; i++) [events addObject:VCMakeAppDiagnosticEvent(i, @"connection", @"Connection action blocked", @"subscription update in progress")];
    CHECK("diagnostics/write-sqlite", VCInsertDiagnosticEventBatchAtPaths(events, &paths));
    NSArray *loaded = VCLoadDiagnosticEventDatabaseAtPaths(&paths);
    CHECK("diagnostics/capacity-and-order", [loaded count] == 250 && [[[loaded objectAtIndex:0] objectForKey:@"timestamp"] intValue] == 51);
    CHECK("diagnostics/redaction-keeps-busy-reason", [VCSanitizeDiagnosticText(@"subscription update in progress", 192) isEqual:@"subscription update in progress"]);
    NSString *safe = VCSanitizeDiagnosticText(@"vless://uuid@example.test:443 192.0.2.1 11111111-2222-4333-8444-555555555555", 192);
    CHECK("diagnostics/secrets-redacted", [safe rangeOfString:@"example.test"].location == NSNotFound && [safe rangeOfString:@"192.0.2.1"].location == NSNotFound);
    CHECK("diagnostics/length-limit", [VCSanitizeDiagnosticText(@"plain diagnostic phrase", 5) length] == 5);
    CHECK("diagnostics/http-summary", [VCDiagnosticErrorSummary(@"HTTP 503") isEqual:@"http http_status=503"]);
    CHECK("diagnostics/helper-summary", [VCDiagnosticErrorSummary(@"curl exited with code 7") isEqual:@"transport helper_exit=7"]);
    NSMutableDictionary *categories = [NSMutableDictionary dictionary];
    VCIncrementDiagnosticCategory(categories, @"TLS certificate error"); VCIncrementDiagnosticCategory(categories, @"DNS failed"); VCIncrementDiagnosticCategory(categories, @"DNS failed");
    CHECK("diagnostics/category-counts-sorted", [VCDiagnosticCategoryCountsText(categories) isEqual:@"dns:2,tls:1"]);
    CHECK("diagnostics/parse-daemon-error", [[VCParseDaemonDiagnostics(nil) objectForKey:@"error"] isEqual:@"daemon unavailable"]);
    CHECK("diagnostics/parse-daemon-values", [[VCParseDaemonDiagnostics(@"OK diagnostics\nconnected=1\ninvalid\nmode=pf\n") objectForKey:@"mode"] isEqual:@"pf"]);
    CHECK("diagnostics/parse-events-filter-malformed", [VCParseDaemonEvents(@"OK events\nEVENT\t100\tconnected\nEVENT\t0\tinvalid\nEVENT\t200\t\n") count] == 1);
    CHECK("diagnostics/essential-events-not-optional", !VCIsOptionalAppDiagnosticEvent(@"connection", @"pressed") && !VCIsOptionalAppDiagnosticEvent(@"subscription", @"Update finished"));
    CHECK("diagnostics/ui-events-optional", VCIsOptionalAppDiagnosticEvent(@"ui", @"opened"));
    NSArray *combined = VCCombinedDiagnosticEvents(@[@{@"timestamp": @300}], @[@{@"timestamp": @100}], @[@{@"timestamp": @200}]);
    CHECK("diagnostics/combined-events-order", [[[combined objectAtIndex:0] objectForKey:@"timestamp"] intValue] == 100 && [[[combined objectAtIndex:2] objectForKey:@"timestamp"] intValue] == 300);
    VCClearDiagnosticEventDatabaseAtPaths(&paths);
    CHECK("diagnostics/clear-sqlite", [VCLoadDiagnosticEventDatabaseAtPaths(&paths) count] == 0);
    NSString *outside = [root stringByAppendingPathComponent:@"outside"], *inside = [root stringByAppendingPathComponent:@"imports"];
    CHECK("import/root-fixtures", [[NSFileManager defaultManager] createDirectoryAtPath:outside withIntermediateDirectories:NO attributes:nil error:NULL] && [[NSFileManager defaultManager] createDirectoryAtPath:inside withIntermediateDirectories:NO attributes:nil error:NULL]);
    CHECK("import/root-and-child-allowed", VCImportPathIsInsideRoot(inside, inside) && VCImportPathIsInsideRoot(inside, [inside stringByAppendingPathComponent:@"feed.txt"]));
    CHECK("import/root-prefix-collision-rejected", !VCImportPathIsInsideRoot(inside, [inside stringByAppendingString:@"-other/feed.txt"]));
    CHECK("import/dotdot-escape-rejected", !VCImportPathIsInsideRoot(inside, [inside stringByAppendingPathComponent:@"../outside/feed.txt"]));
    NSString *escape = [inside stringByAppendingPathComponent:@"escape"];
    CHECK("import/symlink-escape-rejected", symlink([outside fileSystemRepresentation], [escape fileSystemRepresentation]) == 0 && !VCImportPathIsInsideRoot(inside, escape));
    unlink([paths.file fileSystemRepresentation]);
    CHECK("storage/no-symlink-follow", symlink("/dev/null", [paths.file fileSystemRepresentation]) == 0 && VCLoadProtectedConfigurationDataAtPaths(&exists, &paths) == nil && exists);
    CHECK("storage/remove-test-directory", [[NSFileManager defaultManager] removeItemAtPath:root error:NULL]);
    CHECK("updates/numeric-version", VCCompareVersions(@"0.6.10", @"0.6.9") == NSOrderedDescending);
    CHECK("updates/prefix-normalization", [VCNormalizedReleaseVersion(@" v0.6.3 ") isEqual:@"0.6.3"]);
    CHECK("settings/xray-version-validation", VCXrayVersionIsValid(@"26.3.27") && !VCXrayVersionIsValid(@"26.3.x"));
    CHECK("routing/ipv4-normalization", [VCNormalizedIPAddress(@" 192.0.2.1 ") isEqual:@"192.0.2.1"]);
    CHECK("routing/ipv6-normalization", [VCNormalizedIPAddress(@"2001:db8::1") isEqual:@"2001:db8::1"]);
    CHECK("routing/host-is-not-ip", VCNormalizedIPAddress(@"example.test") == nil);
    VCMemoryDefaults *defaults = [[[VCMemoryDefaults alloc] init] autorelease];
    VCAppearanceSetAccentIndexInDefaults(5, defaults); VCAppearanceSetDarkInDefaults(YES, defaults);
    CHECK("settings/theme-and-accent-roundtrip", VCAppearanceAccentIndexInDefaults(defaults) == 5 && VCAppearanceIsDarkInDefaults(defaults));
    VCAppearanceSetAccentIndexInDefaults(99, defaults); CHECK("settings/invalid-accent-fallback", VCAppearanceAccentIndexInDefaults(defaults) == 0);
    CHECK("updates/no-previous-check", !VCAutomaticUpdateCheckIsFreshAtTime(defaults, 100000));
    [defaults setDouble:100000 forKey:kDefaultsLastUpdateCheckKey];
    CHECK("updates/fresh-before-24h", VCAutomaticUpdateCheckIsFreshAtTime(defaults, 186399));
    CHECK("updates/stale-after-24h", !VCAutomaticUpdateCheckIsFreshAtTime(defaults, 186400));
    CHECK("updates/future-timestamp-not-fresh", !VCAutomaticUpdateCheckIsFreshAtTime(defaults, 99999));
    NSDictionary *success = @{@"status": @"update", @"latest_version": @"0.6.4", @"release_url": @"https://github.com/notfence/vless-core-app/releases/tag/v0.6.4"};
    VCCacheSuccessfulUpdateResultAtTime(success, defaults, 200000);
    CHECK("updates/success-cached", [defaults doubleForKey:kDefaultsLastUpdateCheckKey] == 200000 && [[defaults stringForKey:kDefaultsLatestVersionKey] isEqual:@"0.6.4"]);
    VCCacheSuccessfulUpdateResultAtTime(@{@"error": @"offline"}, defaults, 300000);
    CHECK("updates/failure-does-not-change-cache", [defaults doubleForKey:kDefaultsLastUpdateCheckKey] == 200000);
    CHECK("routing/default-policy-unchanged", [RoutingPolicyTextInDefaults(defaults) isEqual:@"0;proxy;1"]);
    [defaults setBool:YES forKey:kDefaultsRoutingEnabledKey]; [defaults setBool:NO forKey:kDefaultsRoutingBypassLANKey]; [defaults setObject:@"DIRECT" forKey:kDefaultsRoutingDefaultKey];
    [defaults setObject:@[@{@"action": @"PROXY", @"type": @"DOMAIN", @"value": @" Example.Test "}, @{@"action": @"block", @"type": @"port", @"value": @"443"}, @{@"action": @"direct", @"type": @"domain", @"value": @"bad;injection"}] forKey:kDefaultsRoutingRulesKey];
    CHECK("routing/rule-serialization-and-rejection", [RoutingPolicyTextInDefaults(defaults) isEqual:@"1;direct;0;proxy,domain,example.test;block,port,443"]);
}

static void listTests(void) {
    NSMutableArray *large = [NSMutableArray array]; for (NSUInteger i = 0; i < 705; i++) [large addObject:@"socks5://example.test:1080"];
    NSArray *subs = @[@{@"items": large}, @{@"items": @[@"a", @"b", @"c", @"d", @"e", @"f"]}, @{}];
    CHECK("list/large-expanded-count", VCSubscriptionRowCount(subs, 0) == 708);
    CHECK("list/small-expanded-count", VCSubscriptionRowCount(subs, 1) == 9);
    CHECK("list/collapsed-count", VCSubscriptionRowCount(subs, -1) == 3);
    NSInteger sub = -1, item = -1; BOOL header = NO;
    CHECK("list/map-large-last-item", VCMapSubscriptionRow(subs, 0, 705, &sub, &item, &header) && sub == 0 && item == 704 && !header);
    CHECK("list/map-next-header", VCMapSubscriptionRow(subs, 0, 706, &sub, &item, &header) && sub == 1 && header);
    CHECK("list/new-header-position-after-switch", VCSubscriptionHeaderRow(subs, 1, 1) == 1);
    NSInteger ci = 9, si = 1, ii = 99;
    VCNormalizeSelection(2, subs, &ci, &si, &ii);
    CHECK("list/selection-normalization", ci == -1 && si == 1 && ii == 0);
    NSMutableArray *items = [NSMutableArray arrayWithObjects:[[NSObject new] autorelease], [[NSObject new] autorelease], [[NSObject new] autorelease], nil];
    id selected = [items objectAtIndex:0]; ci = 0; VCMoveListItem(items, 0, 2, &ci);
    CHECK("list/reorder-preserves-selection", ci == 2 && [items objectAtIndex:ci] == selected);
    VCMoveListItem(items, 2, 0, &ci); CHECK("list/reverse-reorder", ci == 0 && [items objectAtIndex:0] == selected);
    NSMutableArray *changingSubs = [[subs mutableCopy] autorelease];
    [changingSubs addObject:@{@"items": @[@"new"]}];
    CHECK("list/import-counter-updates-immediately", VCSubscriptionRowCount(changingSubs, -1) == 4);
    CHECK("list/refreshed-items-counter", VCSubscriptionRowCount(changingSubs, 3) == 5);
    CHECK("list/out-of-range-map", !VCMapSubscriptionRow(subs, -1, 3, &sub, &item, &header));
    CHECK("list/malformed-items-empty", [VCSubscriptionItemsAtIndex(@[@{@"items": @"bad"}], 0) count] == 0);
    ci = -1; si = 2; ii = 0; VCNormalizeSelection(0, subs, &ci, &si, &ii);
    CHECK("list/empty-subscription-selection", ci == -1 && si == 2 && ii == -1);
}

int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    connectionTests(); importTests(); subscriptionUpdateTests(); dataTests(); listTests(); FINISH("app logic");
    [pool drain]; return 0;
}
