#import "../common/foundation_logic.h"
#import "../common/profile_logic.h"
#import "../integrations/karing/karing_backup.h"
#include "../integrations/happ/happ_crypto.h"
#include "check.h"
int main(void) {
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
    FINISH("import formats"); [pool drain]; return 0;
}
