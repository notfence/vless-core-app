#import "../common/profile_logic.h"
#import "../common/foundation_logic.h"
#import "../common/app_constants.h"
#include "check.h"

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    VCProfileLogic *logic=VCProfiles(); NSString *error=nil;
    NSString *url=@"https://provider.test/sub?token=a+b%2B%2540&x=%26#frag";
    NSDictionary *source=@{@"url":url,@"name":@"Provider",@"items":@[@"socks5://test.test"],
        kSubscriptionMetadataKey:@{kSubscriptionDescriptionKey:@"Provider description"},kSubscriptionUserInfoKey:@{kSubscriptionDownloadKey:@100},
        kSubscriptionAllowInsecureFetchKey:@(YES),kSubscriptionAllowPlainHTTPKey:@(YES),kSubscriptionHappUserAgentKey:@(YES)};
    NSDictionary *edited=[logic subscriptionByEditingSource:source name:@"Provider" link:url userAgent:nil error:&error];
    CHECK("subscription-edit/default-preserves-url-and-content",edited && !error && [[edited objectForKey:@"url"] isEqual:url] && [[edited objectForKey:@"items"] isEqual:[source objectForKey:@"items"]] && [[edited objectForKey:kSubscriptionMetadataKey] isEqual:[source objectForKey:kSubscriptionMetadataKey]]);
    CHECK("subscription-edit/default-clears-only-agent-overrides",![edited objectForKey:kSubscriptionUserAgentKey] && ![edited objectForKey:kSubscriptionHappUserAgentKey] && SubscriptionDictionaryAllowsInsecureFetch(edited) && SubscriptionDictionaryAllowsPlainHTTP(edited));
    CHECK("subscription-edit/name-unchanged-not-custom",![edited objectForKey:kSubscriptionCustomNameKey]);
    edited=[logic subscriptionByEditingSource:source name:@"  🇳🇱 Моё имя  " link:url userAgent:kHappSubscriptionUserAgent error:&error];
    CHECK("subscription-edit/name-and-agent",[[edited objectForKey:@"name"] isEqual:@"🇳🇱 Моё имя"] && [[edited objectForKey:kSubscriptionCustomNameKey] isEqual:@"🇳🇱 Моё имя"] && [[edited objectForKey:kSubscriptionHappUserAgentKey] boolValue]);
    CHECK("subscription-edit/happ-agent-not-happ-source",!SubscriptionDictionaryUsesHappHeaders(edited) && !SubscriptionDictionaryIsHappEncrypted(edited));
    NSString *agent=@"Client/1.2 (custom; iOS) + % @";
    edited=[logic subscriptionByEditingSource:source name:@"Provider" link:url userAgent:agent error:&error];
    CHECK("subscription-edit/custom-agent-bytes",[[edited objectForKey:kSubscriptionUserAgentKey] isEqual:agent] && ![edited objectForKey:kSubscriptionHappUserAgentKey] && [VCSubscriptionUserAgent(edited,@"app") isEqual:agent]);
    edited=[logic subscriptionByEditingSource:source name:@"Provider" link:@"http://other.test/new?a=+%25%2B" userAgent:agent error:&error];
    CHECK("subscription-edit/link-change-clears-previous-provider",![[edited objectForKey:@"items"] count] && ![edited objectForKey:kSubscriptionMetadataKey] && ![edited objectForKey:kSubscriptionUserInfoKey] && !SubscriptionDictionaryAllowsInsecureFetch(edited) && !SubscriptionDictionaryAllowsPlainHTTP(edited));
    CHECK("subscription-edit/link-change-keeps-explicit-agent",[[edited objectForKey:kSubscriptionUserAgentKey] isEqual:agent]);
    CHECK("subscription-edit/source-never-mutated",[[source objectForKey:@"items"] count]==1 && [[source objectForKey:@"url"] isEqual:url] && [[source objectForKey:kSubscriptionHappUserAgentKey] boolValue]);
    for (NSString *bad in @[@"",@"  ",@"a\nb",@"a\rb",@"a\tb"]) CHECK("subscription-edit/bad-name",![logic subscriptionByEditingSource:source name:bad link:url userAgent:nil error:&error] && error);
    NSString *large=[@"a" stringByPaddingToLength:1025 withString:@"a" startingAtIndex:0];
    CHECK("subscription-edit/name-size",![logic subscriptionByEditingSource:source name:large link:url userAgent:nil error:&error]);
    for (id bad in @[@"",@"  ",@"file:///tmp/private",@"https://",@"https://provider.test/a\nb",@"vless://uuid@host.test:443",@"happ://connect/https://provider.test",@"happ://crypt5/broken",@"incy://autorouting/https://provider.test",@"happ://add/incy://add/https://provider.test",@1])
        CHECK("subscription-edit/bad-link",![logic subscriptionByEditingSource:source name:@"Name" link:bad userAgent:nil error:&error]);
    large=[@"https://provider.test/" stringByPaddingToLength:kVCMaximumSubscriptionURLBytes+1 withString:@"a" startingAtIndex:0];
    CHECK("subscription-edit/link-size",![logic subscriptionByEditingSource:source name:@"Name" link:large userAgent:nil error:&error]);
    for (id bad in @[@"",@" ",@"Client\r\nX-HWID: injected",@"Client\nHeader",@"A\tB",@"Клиент",@1,[NSNull null]])
        CHECK("subscription-edit/bad-agent",![logic subscriptionByEditingSource:source name:@"Name" link:url userAgent:bad error:&error]);
    for (unsigned c=0;c<128;c++) {
        unichar character=c; NSString *value=[@"Client" stringByAppendingString:[NSString stringWithCharacters:&character length:1]];
        CHECK("subscription-edit/agent-ascii-boundary",VCSubscriptionUserAgentIsValid(value)==(c>=32 && c<127));
    }
    large=[@"a" stringByPaddingToLength:256 withString:@"a" startingAtIndex:0];
    CHECK("subscription-edit/agent-256",VCSubscriptionUserAgentIsValid(large));
    CHECK("subscription-edit/agent-257",!VCSubscriptionUserAgentIsValid([large stringByAppendingString:@"a"]));
    CHECK("subscription-edit/default-agent",[VCSubscriptionUserAgent(@{},@"app") isEqual:@"app"]);
    CHECK("subscription-edit/bad-stored-agent-fails-closed",!VCSubscriptionUserAgent(@{kSubscriptionUserAgentKey:@"bad\r\nheader"},@"app"));
    edited=[logic subscriptionByEditingSource:source name:@"Name" link:[kHappAddPrefix stringByAppendingString:url] userAgent:agent error:&error];
    CHECK("subscription-edit/happ-add-normalization",[[edited objectForKey:@"url"] isEqual:url] && SubscriptionDictionaryUsesHappHeaders(edited) && [VCSubscriptionUserAgent(edited,@"app") isEqual:agent]);
    edited=[logic subscriptionByEditingSource:edited name:@"Name" link:url userAgent:nil error:&error];
    CHECK("subscription-edit/happ-default-is-app-agent",SubscriptionDictionaryUsesHappHeaders(edited) && [VCSubscriptionUserAgent(edited,@"app") isEqual:@"app"]);
    CHECK("subscription-edit/unmodified-happ-source-keeps-agent",[VCSubscriptionUserAgent(@{@"url":url,kSubscriptionHappSourceKey:@(YES)},@"app") isEqual:kHappSubscriptionUserAgent]);
    NSDictionary *reloaded=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:edited options:0 error:NULL] options:0 error:NULL];
    CHECK("subscription-edit/explicit-default-survives-reload",[VCSubscriptionUserAgent(reloaded,@"new-app-version") isEqual:@"new-app-version"]);
    NSString *incy=@"incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg";
    edited=[logic subscriptionByEditingSource:source name:@"INCY" link:incy userAgent:agent error:&error];
    CHECK("subscription-edit/incy-wrapper-preserved",[[edited objectForKey:@"url"] isEqual:incy] && !SubscriptionDictionaryUsesHappHeaders(edited) && [VCSubscriptionUserAgent(edited,@"app") isEqual:agent]);
    NSString *fixtures=[NSString stringWithContentsOfFile:@"happ_fixtures.txt" encoding:NSUTF8StringEncoding error:NULL];
    NSUInteger count=0;
    for (NSString *line in [fixtures componentsSeparatedByString:@"\n"]) {
        NSRange space=[line rangeOfString:@" "]; if (space.location==NSNotFound) continue;
        NSString *wrapper=[line substringFromIndex:space.location+1];
        edited=[logic subscriptionByEditingSource:source name:@"HAPP" link:wrapper userAgent:agent error:&error];
        CHECK("subscription-edit/protected-source-never-exposed",[[edited objectForKey:@"url"] isEqual:wrapper] && SubscriptionDictionaryIsHappEncrypted(edited) && ![[edited objectForKey:@"items"] count] && ![edited objectForKey:kSubscriptionAllowInsecureFetchKey]);
        edited=[logic subscriptionByEditingSource:edited name:@"HAPP" link:url userAgent:nil error:&error];
        CHECK("subscription-edit/leaving-protected-source-clears-flags",!SubscriptionDictionaryUsesHappHeaders(edited) && !SubscriptionDictionaryIsHappEncrypted(edited)); count++;
    }
    CHECK("subscription-edit/protected-fixtures",count==3);
    FINISH("subscription settings model"); [pool drain]; return 0;
}
