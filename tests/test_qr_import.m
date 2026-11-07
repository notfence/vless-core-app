#import "../common/profile_logic.h"
#import "../common/subscription_task.h"
#include "check.h"
#include <openssl/evp.h>
int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    VCProfileLogic *profiles=[[[VCProfileLogic alloc] init] autorelease];
    VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:NO observer:nil selector:NULL] autorelease];
    VCSetCurrentSubscriptionTask(task);
    NSString *uri=@"socks5://user:p%2B%25%40@127.0.0.1:1080#Name";
    NSString *json=@"{\"outbounds\":[{\"protocol\":\"vless\",\"settings\":{\"vnext\":[{\"address\":\"127.0.0.2\",\"port\":443,\"users\":[{\"id\":\"11111111-2222-4333-8444-555555555555\"}]}]}}]}";
    NSDictionary *report=[profiles textImportReportFromTexts:@[uri,@"https://first.test/sub?a=b+c%25",@"https://second.test/sub",uri,json,@"not a proxy QR",@"incy://autorouting/https://must-not-fetch.test"]];
    NSArray *values=[report objectForKey:@"uris"];
    CHECK("photo-import/all-subscriptions",[values containsObject:@"https://first.test/sub?a=b+c%25"] && [values containsObject:@"https://second.test/sub"]);
    CHECK("photo-import/original-uri",[[values objectAtIndex:0] isEqual:uri]);
    CHECK("photo-import/json-independent",[values count]==4);
    CHECK("photo-import/unsupported-count",[[report objectForKey:@"skipped"] unsignedIntegerValue]==2);
    CHECK("photo-import/duplicate-count",[[[task consumeProgress] objectForKey:@"duplicates"] unsignedIntegerValue]==1);
    CHECK("photo-import/metadata",[[report objectForKey:@"metadata"] objectForKey:uri]!=nil);
    report=[profiles textImportReportFromTexts:@[@"incy://import/%%%",uri]];
    CHECK("photo-import/bad-wrapper-does-not-drop-next",[[report objectForKey:@"uris"] containsObject:uri]);
    report=[profiles textImportReportFromTexts:@[@"   ",uri]];
    CHECK("photo-import/empty-first-code-keeps-next",[[report objectForKey:@"uris"] count]==1 && [[report objectForKey:@"skipped"] intValue]==1);
    unichar zero=0;
    report=[profiles textImportReportFromTexts:@[[NSString stringWithCharacters:&zero length:1],uri]];
    CHECK("photo-import/binary-code-keeps-next",[[report objectForKey:@"uris"] count]==1 && [[report objectForKey:@"skipped"] intValue]==1);
    report=[profiles textImportReportFromTexts:@[@"happ://routing/onadd/https://not-a-subscription.test",uri]];
    CHECK("photo-import/unknown-wrapper-does-not-extract-url",[[report objectForKey:@"uris"] count]==1 && ![[report objectForKey:@"uris"] containsObject:@"https://not-a-subscription.test"]);
    NSString *crypt=@"incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg";
    NSString *happ=@"happ://add/https://provider.test/sub?a=1+2%25";
    report=[profiles textImportReportFromTexts:@[crypt,happ,@"trojan://test@example.test:443"]];
    values=[report objectForKey:@"uris"];
    CHECK("photo-import/incy-wrapper-preserved",[values containsObject:crypt] && ![values containsObject:@"https://sub.example.com/test-vector"]);
    CHECK("photo-import/happ-wrapper-preserved",[values containsObject:happ]);
    CHECK("photo-import/mixed-protocol",[values containsObject:@"trojan://test@example.test:443"]);
    unsigned char encoded[256];
    int encodedLength=EVP_EncodeBlock(encoded,(const unsigned char *)[uri UTF8String],(int)[uri lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    NSString *base64=[[[NSString alloc] initWithBytes:encoded length:encodedLength encoding:NSASCIIStringEncoding] autorelease];
    report=[profiles textImportReportFromTexts:@[base64,@"https://separate.test"]];
    CHECK("photo-import/base64-kept-independent",[[report objectForKey:@"uris"] containsObject:uri] && [[report objectForKey:@"uris"] containsObject:@"https://separate.test"]);
    [task cancelWithReason:nil];
    report=[profiles textImportReportFromTexts:@[uri]];
    CHECK("photo-import/cancel",![[report objectForKey:@"uris"] count]);
    VCSetCurrentSubscriptionTask(nil);
    FINISH("photo QR import"); [pool drain]; return 0;
}
