#import "../common/foundation_logic.h"
#import "../common/app_constants.h"
#include "check.h"

@interface SubscriptionInfoVC : NSObject {
@public
    NSDictionary *_subscription;
}
- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail;
- (NSString *)formattedTimestamp:(unsigned long long)timestamp includeTime:(BOOL)includeTime;
- (NSArray *)lastUpdateRows;
@end
@implementation SubscriptionInfoVC
#include "subscription_info_rows.inc"
@end

static NSString *detail(NSArray *rows,NSString *title) {
    for (NSDictionary *row in rows) if ([[row objectForKey:@"title"] isEqual:title]) return [row objectForKey:@"detail"];
    return nil;
}

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    SubscriptionInfoVC *info=[[[SubscriptionInfoVC alloc] init] autorelease];
    info->_subscription=@{@"items":@[]};
    CHECK("subscription-info/no-invented-update",![[info lastUpdateRows] count]);
    NSDictionary *source=@{@"url":@"https://private-fixture.test/sub/private-token",@"items":@[@"socks5://private-user:private-password@private-fixture.test:1080",@"socks5://second.test:1080"],
        kSubscriptionMetadataKey:@{kSubscriptionLastUpdatedKey:@12345},@"import_skipped":@3,
        @"import_issues":@[@"configs[]: Unsupported proxy protocol: hysteria",@"Unsupported proxy protocol: hysteria",@"",@123,@"Unsupported fp"]};
    info->_subscription=source;
    NSArray *rows=[info lastUpdateRows];
    CHECK("subscription-info/last-successful-update-counts",[detail(rows,@"Accepted configurations") isEqual:@"2"] && [detail(rows,@"Skipped configurations") isEqual:@"3"]);
    CHECK("subscription-info/update-time",[detail(rows,@"Updated") isEqual:[info formattedTimestamp:12345 includeTime:YES]]);
    CHECK("subscription-info/unique-readable-reasons",[detail(rows,@"Reasons") isEqual:@"Unsupported proxy protocol: hysteria\nUnsupported fp"]);
    for (NSString *secret in @[@"private-fixture",@"private-token",@"private-user",@"private-password"])
        CHECK("subscription-info/summary-excludes-credentials-and-links",[[rows description] rangeOfString:secret].location==NSNotFound);
    info->_subscription=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:source options:0 error:NULL] options:0 error:NULL];
    CHECK("subscription-info/report-survives-reload",[[info lastUpdateRows] isEqual:rows]);
    info->_subscription=@{@"items":@[@"socks5://other.test:1080"],@"import_skipped":@1,@"import_issues":@[@"Other reason"]};
    rows=[info lastUpdateRows];
    CHECK("subscription-info/legacy-report-without-date",!detail(rows,@"Updated") && [detail(rows,@"Accepted configurations") isEqual:@"1"]);
    CHECK("subscription-info/single-reason",[detail(rows,@"Reason") isEqual:@"Other reason"] && !detail(rows,@"Reasons"));
    info->_subscription=@{@"items":@[@"socks5://clean.test:1080"],kSubscriptionMetadataKey:@{kSubscriptionLastUpdatedKey:@12346},@"import_skipped":@0,@"import_issues":@[@"Stale reason"]};
    rows=[info lastUpdateRows];
    CHECK("subscription-info/clean-result-without-stale-reasons",[detail(rows,@"Skipped configurations") isEqual:@"0"] && !detail(rows,@"Reason") && !detail(rows,@"Reasons"));
    info->_subscription=@{@"items":@123,@"import_skipped":@-1,kSubscriptionMetadataKey:@"bad",@"import_issues":@"bad"};
    CHECK("subscription-info/malformed-optional-report",![[info lastUpdateRows] count]);
    info->_subscription=@{@"items":@[@"socks5://test.test:1080"],@"import_skipped":@1,@"import_issues":@"bad"};
    rows=[info lastUpdateRows];
    CHECK("subscription-info/malformed-reasons-do-not-hide-count",[detail(rows,@"Skipped configurations") isEqual:@"1"] && !detail(rows,@"Reason"));
    NSMutableArray *reasons=[NSMutableArray array];
    for (NSUInteger i=0;i<32;i++) [reasons addObject:[NSString stringWithFormat:@"Reason %lu",(unsigned long)i]];
    info->_subscription=@{@"items":@[],@"import_skipped":@32,@"import_issues":reasons};
    CHECK("subscription-info/reasons-remain-bounded",[[detail([info lastUpdateRows],@"Reasons") componentsSeparatedByString:@"\n"] count]==16);
    FINISH("subscription information model"); [pool drain]; return 0;
}
