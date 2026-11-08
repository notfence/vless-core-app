#import "../common/profile_logic.h"
#import "../common/foundation_logic.h"
#import "../common/subscription_task.h"
#import "../common/app_constants.h"
#import "../integrations/incy/incy_links.h"
#include "check.h"
#include "support/objc/blocks_runtime.h"

enum { VCAlertTagImportCompatibility=1005, DISPATCH_QUEUE_PRIORITY_DEFAULT=0 };
static void (^work[2][32])(void);
static NSUInteger workCount[2],shownAlerts;
static NSString *alertTitle,*alertMessage,*alertCancel,*alertAction;
static int dispatch_get_global_queue(int p,int flags) { (void)p; (void)flags; return 0; }
static int dispatch_get_main_queue(void) { return 1; }
static void dispatch_async(int queue,void (^block)(void)) { if (queue==1) { block(); return; } CHECK("subscription-ui/bounded-work",workCount[queue]<32); work[queue][workCount[queue]++]=Block_copy(block); }
static void runWork(void) {
    for (NSUInteger n=0;workCount[0] || workCount[1];n++) {
        CHECK("subscription-ui/finite-work",n<32);
        for (int q=0;q<2;q++) if (workCount[q]) {
            void (^block)(void)=work[q][0]; memmove(work[q],work[q]+1,--workCount[q]*sizeof(block)); block(); Block_release(block);
        }
    }
}
static void VCRecordAppEvent(id a,id b,id c) { (void)a; (void)b; (void)c; }
@interface UIAlertView : NSObject { NSInteger _tag; }
@property NSInteger tag;
- (id)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancel otherButtonTitles:(NSString *)action,...;
- (void)show;
@end
@implementation UIAlertView
@synthesize tag=_tag;
- (id)initWithTitle:(NSString *)title message:(NSString *)message delegate:(id)delegate cancelButtonTitle:(NSString *)cancel otherButtonTitles:(NSString *)action,... {
    (void)delegate; self=[super init]; alertTitle=title; alertMessage=message; alertCancel=cancel; alertAction=action; return self;
}
- (void)show { shownAlerts++; }
@end

static NSString *const compatibilityKey=@"happ_user_agent";
static NSString *const sourceURL=@"https://provider.test/sub?token=a+b%2B%2540&x=%26#name";
static NSArray *responses;
static NSMutableArray *requests;
static BOOL invalidBody,cancelFirst;
static NSString *responseHeaders;
static NSString *failureDetails;

@interface UIDevice : NSObject
+ (id)currentDevice;
- (NSString *)systemVersion;
@end
@implementation UIDevice
+ (id)currentDevice { return [[[self alloc] init] autorelease]; }
- (NSString *)systemVersion { return @"6.1.3"; }
@end
static NSString *SubscriptionHWID(void) { return @"unchanged-test-hwid"; }
static NSString *DeviceModelName(void) { return @"test-device"; }
static NSString *AppUserAgent(void) { return @"vless-core-app/test/iOS"; }

static NSData *FetchURLViaVlessCoreCurl(NSString *url,BOOL insecure,BOOL plain,BOOL happ,BOOL hwid,NSString *agent,NSString **error,NSString **headers,int *exitCode) {
    NSUInteger index=[requests count];
    CHECK("subscription-fetch/bounded-attempts",index<[responses count]);
    [requests addObject:@{@"url":url,@"agent":agent,@"insecure":@(insecure),@"plain":@(plain),@"happ":@(happ),@"hwid":@(hwid)}];
    NSInteger status=[[responses objectAtIndex:index] integerValue];
    if (headers) *headers=responseHeaders ?: [NSString stringWithFormat:@"HTTP/2 %ld\r\nprofile-title: Provider\r\n\r\n",(long)status];
    if (error) *error=status==200 ? nil : (failureDetails ?: @"Fetch failed");
    if (exitCode) *exitCode=status==600 ? 60 : (status==700 ? 28 : (status==200 ? 0 : 22));
    if (cancelFirst && index==0) [VCCurrentSubscriptionTask() cancelWithReason:@"Cancelled"];
    return status==200 ? [(invalidBody ? @"<html>Access denied</html>" : @"socks5://test:p%2B%2540@127.0.0.1:1080#Profile") dataUsingEncoding:NSUTF8StringEncoding] : nil;
}

@interface SubscriptionEditVC : NSObject {
@public
    NSDictionary *source,*saved;
    NSString *errorText;
}
@property(readonly) NSDictionary *subscription;
- (void)finishSavingWithSubscription:(NSDictionary *)subscription errorText:(NSString *)error;
@end
@implementation SubscriptionEditVC
- (NSDictionary *)subscription { return source; }
- (void)finishSavingWithSubscription:(NSDictionary *)subscription errorText:(NSString *)error { [saved release]; saved=[subscription copy]; [errorText release]; errorText=[error copy]; }
- (void)dealloc { [source release]; [saved release]; [errorText release]; [super dealloc]; }
@end

@interface MainVC : VCProfileLogic <VCSubscriptionUpdateOptions> {
@public
    NSMutableArray *_configs,*_subscriptions,*_photoQRQueue;
    VCSubscriptionTask *_subscriptionTask;
    NSDictionary *_pendingCompatibilityImport;
    id _configurationDraft;
    NSUInteger _configurationRevision,_photoQRFailures,commits,failures,insecurePrompts,refreshes;
    NSInteger refreshedIndex;
    BOOL _launchAutoUpdateInProgress,_pendingInsecureImportUsesCompatibleUserAgent,_pendingInsecureImportAllowsPlainHTTP,saveFails,mutationBlocked,connectionBusy;
    NSString *lastStatus;
}
- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)source errorText:(NSString **)error insecureRetryAvailable:(BOOL *)retry;
- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)source errorText:(NSString **)error;
- (void)performSubscriptionImportForURLs:(NSArray *)urls allowInsecureFetch:(BOOL)insecure fallbackSubscriptionsByURL:(NSDictionary *)fallback allowPlainHTTP:(BOOL)plain useCompatibleUserAgent:(BOOL)compatible;
@end
@implementation MainVC
- (id)init { if ((self=[super init])) { _configs=[[NSMutableArray alloc] init]; _subscriptions=[[NSMutableArray alloc] init]; } return self; }
- (void)dealloc { [_configs release]; [_subscriptions release]; [_pendingCompatibilityImport release]; [_subscriptionTask release]; [_photoQRQueue release]; [lastStatus release]; [super dealloc]; }
- (BOOL)preserveCustomSubscriptionNames { return YES; }
- (NSTimeInterval)subscriptionUpdateTimestamp { return 12345; }
- (BOOL)isHappEncryptedLink:(NSString *)url { return HappURLStringIsEncrypted(url); }
- (NSString *)decryptedHappLink:(NSString *)url errorText:(NSString **)error { return VCHappDecryptedLink(url,error); }
- (NSString *)subscriptionNameFromURLString:(NSString *)url { (void)url; return @"Subscription"; }
- (NSString *)hostFromURLString:(NSString *)url { return [[NSURL URLWithString:url] host]; }
- (NSString *)safeTrim:(NSString *)text { return TrimSimpleString(text); }
- (BOOL)isHappAddLink:(NSString *)text { return [[text lowercaseString] hasPrefix:kHappAddPrefix]; }
- (NSString *)targetFromHappAddLink:(NSString *)text { return [text substringFromIndex:[kHappAddPrefix length]]; }
- (BOOL)isSubscriptionURL:(NSString *)text { return VCValidatedProviderURLString(text)!=nil; }
- (BOOL)configurationMutationBlocked { return mutationBlocked; }
- (BOOL)isConnectionActionInProgress { return connectionBusy; }
- (NSInteger)existingSubscriptionIndexForURL:(NSString *)url { for (NSUInteger i=0;i<[_subscriptions count];i++) if ([[[_subscriptions objectAtIndex:i] objectForKey:@"url"] isEqual:url]) return i; return -1; }
- (VCSubscriptionTask *)beginSubscriptionTaskWithKind:(VCSubscriptionTaskKind)kind {
    CHECK("subscription-ui/no-concurrent-task",!_subscriptionTask);
    _subscriptionTask=[[VCSubscriptionTask alloc] initWithPreserveNames:YES kind:kind observer:nil selector:NULL]; return _subscriptionTask;
}
- (void)finishSubscriptionTask:(VCSubscriptionTask *)task success:(BOOL)success { (void)success; [task finish]; [_subscriptionTask release]; _subscriptionTask=nil; _launchAutoUpdateInProgress=NO; }
- (NSDictionary *)updatedSubscriptionDictionaryFromSource:(NSDictionary *)source errorText:(NSString **)error { return [self updatedSubscriptionDictionaryFromSource:source errorText:error insecureRetryAvailable:NULL]; }
- (void)showStatus:(NSString *)text ok:(BOOL)ok { (void)ok; [lastStatus release]; lastStatus=[text copy]; }
- (void)showPlainHTTPSubscriptionWarningForCount:(NSUInteger)count confirmation:(void (^)(void))block { (void)count; (void)block; CHECK("subscription-ui/http-not-silently-approved",NO); }
- (void)showInsecureSubscriptionImportPromptForURLs:(id)urls fromBatchImport:(BOOL)batch happSource:(BOOL)happ { (void)urls; (void)batch; (void)happ; insecurePrompts++; }
- (void)showSubscriptionImportFailures:(id)texts { (void)texts; failures++; }
- (void)showProfileImportWarnings:(id)profiles { (void)profiles; }
- (void)saveData {}
- (void)reloadData {}
- (void)normalizeSelection {}
- (void)reloadMainTableDataAfterExternalChange {}
- (void)refreshPresentedSubscriptionInfoIfNeeded {}
- (BOOL)refreshSubscriptionAtIndex:(NSInteger)index showStatus:(BOOL)status { (void)status; refreshedIndex=index; refreshes++; return NO; }
- (void)selectSubscriptionAtIndex:(NSInteger)index { (void)index; }
- (NSString *)shortImportFailureTextForURL:(id)url errorText:(NSString *)error { (void)url; return error; }
- (void)commitConfigurations:(id)configs subscriptions:(NSArray *)subscriptions completion:(void (^)(BOOL))completion {
    (void)configs; commits++;
    if (!saveFails) { [_subscriptions setArray:subscriptions]; _configurationRevision++; }
    completion(!saveFails);
}
#define _tableView self
#include "subscription_update.inc"
#include "subscription_compatibility.inc"
#include "subscription_save.inc"
#undef _tableView
@end

static void setup(NSArray *statuses) {
    responses=statuses; requests=[NSMutableArray array];
    invalidBody=cancelFirst=NO; responseHeaders=nil; failureDetails=nil;
    VCSetCurrentSubscriptionTask(nil);
}

static void importWithMode(MainVC *screen,BOOL compatible) {
    [screen performSubscriptionImportForURLs:@[sourceURL] allowInsecureFetch:NO fallbackSubscriptionsByURL:nil allowPlainHTTP:NO useCompatibleUserAgent:compatible]; runWork();
}
static MainVC *newImport(void) { return [[[MainVC alloc] init] autorelease]; }
static void editRefreshTests(void) {
    NSDictionary *source=@{@"url":sourceURL,@"name":@"Original",@"items":@[]};
    for (NSUInteger scenario=0;scenario<8;scenario++) {
        MainVC *screen=newImport(); setup(@[]);
        SubscriptionEditVC *editor=[[[SubscriptionEditVC alloc] init] autorelease]; editor->source=[source copy];
        NSString *agent=scenario==2 || scenario==4 ? kHappSubscriptionUserAgent : nil;
        NSString *link=scenario==1 || scenario==3 ? @"https://new.test/sub?x=+%25" : sourceURL;
        NSDictionary *updated=[VCProfiles() subscriptionByEditingSource:source name:@"Renamed" link:link userAgent:agent error:NULL];
        [screen->_subscriptions addObject:updated];
        if (scenario==3) [screen->_subscriptions removeAllObjects];
        if (scenario==4) {
            [screen->_subscriptions insertObject:@{@"url":@"https://other.test/sub"} atIndex:0];
        }
        if (scenario==5) {
            NSMutableDictionary *stale=[NSMutableDictionary dictionaryWithDictionary:updated]; [stale setObject:@"Newer" forKey:@"name"];
            [screen->_subscriptions setArray:@[stale]];
        }
        if (scenario==6 || scenario==7) {
            [editor->source release]; editor->source=[@{@"url":sourceURL,@"name":@"Original",kSubscriptionHappSourceKey:@(YES)} copy];
            updated=[VCProfiles() subscriptionByEditingSource:editor->source name:@"Renamed" link:sourceURL userAgent:scenario==6 ? kHappSubscriptionUserAgent : nil error:NULL];
            [screen->_subscriptions setArray:@[updated]];
        }
        [screen subscriptionEditVC:editor didSaveSubscription:updated];
        BOOL refresh=scenario==1 || scenario==2 || scenario==4 || scenario==7;
        CHECK("subscription-edit/refresh-only-for-current-link-or-agent-change",screen->refreshes==(refresh ? 1 : 0));
        if (refresh) CHECK("subscription-edit/refresh-correct-subscription",screen->refreshedIndex==(scenario==4 ? 1 : 0));
        CHECK("subscription-edit/name-only-and-unchanged-agent-no-fetch",![requests count]);
    }
}
static void editSaveTests(void) {
    NSDictionary *original=@{@"url":sourceURL,@"name":@"Original",@"items":@[@"socks5://old.test"]};
    NSDictionary *other=@{@"url":@"https://other.test/sub",@"name":@"Other",@"items":@[]};
    NSDictionary *updated=[VCProfiles() subscriptionByEditingSource:original name:@"Renamed" link:sourceURL userAgent:kHappSubscriptionUserAgent error:NULL];
    for (NSUInteger scenario=0;scenario<7;scenario++) {
        setup(@[]); MainVC *screen=newImport(); [screen->_subscriptions addObjectsFromArray:@[original,other]];
        SubscriptionEditVC *editor=[[[SubscriptionEditVC alloc] init] autorelease]; editor->source=[original copy];
        NSDictionary *replacement=updated;
        if (scenario==1) screen->saveFails=YES;
        else if (scenario==2) { NSMutableDictionary *stale=[NSMutableDictionary dictionaryWithDictionary:original]; [stale setObject:@"Changed" forKey:@"name"]; [screen->_subscriptions replaceObjectAtIndex:0 withObject:stale]; }
        else if (scenario==3) replacement=[VCProfiles() subscriptionByEditingSource:original name:@"Name" link:[other objectForKey:@"url"] userAgent:nil error:NULL];
        else if (scenario==4) screen->connectionBusy=YES;
        else if (scenario==5) screen->_configurationDraft=@{};
        else if (scenario==6) [screen->_subscriptions exchangeObjectAtIndex:0 withObjectAtIndex:1];
        [screen subscriptionEditVC:editor requestedSave:replacement];
        CHECK("subscription-edit/save-never-fetches",![requests count]);
        CHECK("subscription-edit/other-subscription-unchanged",[screen->_subscriptions containsObject:other]);
        if (scenario==0 || scenario==6) {
            CHECK("subscription-edit/atomic-success",editor->saved && !editor->errorText && screen->commits==1 && [screen->_subscriptions containsObject:updated]);
        } else {
            CHECK("subscription-edit/failed-save-not-applied",!editor->saved && editor->errorText && ![screen->_subscriptions containsObject:updated]);
            CHECK("subscription-edit/failed-save-retains-records",[screen->_subscriptions count]==2);
        }
    }
    for (NSDictionary *source in @[@{@"url":sourceURL},@{@"url":sourceURL,kSubscriptionHappSourceKey:@(YES)}]) {
        setup(@[@200]); NSMutableDictionary *custom=[NSMutableDictionary dictionaryWithDictionary:source]; [custom setObject:@"Custom client/1.0 (+ % @)" forKey:kSubscriptionUserAgentKey];
        MainVC *screen=newImport(); NSString *error=nil;
        CHECK("subscription-edit/custom-agent-used-by-fetch",[screen updatedSubscriptionDictionaryFromSource:custom errorText:&error insecureRetryAvailable:NULL] && [[[requests objectAtIndex:0] objectForKey:@"agent"] isEqual:[custom objectForKey:kSubscriptionUserAgentKey]]);
    }
    setup(@[]); MainVC *screen=newImport();
    CHECK("subscription-edit/invalid-stored-agent-no-request",![screen updatedSubscriptionDictionaryFromSource:@{@"url":sourceURL,kSubscriptionUserAgentKey:@"bad\r\ninjection"} errorText:NULL insecureRetryAvailable:NULL] && ![requests count]);
}
static void promptTests(void) {
    MainVC *screen=newImport(); setup(@[@403]); shownAlerts=0;
    importWithMode(screen,NO);
    CHECK("subscription-ui/403-awaits-consent",shownAlerts==1 && screen->_pendingCompatibilityImport && !screen->_subscriptionTask && [requests count]==1 && ![screen->_subscriptions count] && !screen->commits);
    CHECK("subscription-ui/correct-window",[alertTitle isEqual:@"Compatibility mode"] && [alertCancel isEqual:@"OK"] && [alertAction isEqual:@"Retry"] && [alertMessage rangeOfString:@"HAPP User-Agent"].location!=NSNotFound && [alertMessage rangeOfString:sourceURL].location==NSNotFound);
    [screen finishCompatibilityImportPrompt:NO]; runWork();
    CHECK("subscription-ui/ok-no-request-or-save",[requests count]==1 && !screen->commits && !screen->_pendingCompatibilityImport && ![screen->_subscriptions count]);
    screen=newImport(); setup(@[@403,@200]); importWithMode(screen,NO);
    [screen finishCompatibilityImportPrompt:YES];
    CHECK("subscription-ui/retry-remains-background",[requests count]==1 && screen->_subscriptionTask);
    runWork(); NSDictionary *saved=[screen->_subscriptions lastObject];
    CHECK("subscription-ui/retry-saves-agent-on-success",[requests count]==2 && screen->commits==1 && [[saved objectForKey:compatibilityKey] boolValue] && [[saved objectForKey:@"url"] isEqual:sourceURL] && !SubscriptionDictionaryUsesHappHeaders(saved) && !SubscriptionDictionaryAllowsInsecureFetch(saved) && !SubscriptionDictionaryAllowsPlainHTTP(saved));
    for (NSUInteger i=0;i<2;i++) CHECK("subscription-ui/retry-uses-one-identity",[[[requests objectAtIndex:i] objectForKey:@"hwid"] boolValue] && ![[[requests objectAtIndex:i] objectForKey:@"insecure"] boolValue]);
    CHECK("subscription-ui/agent-selected-only-after-consent",[[[requests objectAtIndex:0] objectForKey:@"agent"] isEqual:AppUserAgent()] && [[[requests objectAtIndex:1] objectForKey:@"agent"] isEqual:kHappSubscriptionUserAgent]);
    screen=newImport(); setup(@[@403,@403]); shownAlerts=0; importWithMode(screen,NO); [screen finishCompatibilityImportPrompt:YES]; runWork();
    CHECK("subscription-ui/failed-retry-no-loop-or-record",[requests count]==2 && shownAlerts==1 && ![screen->_subscriptions count] && !screen->commits && screen->failures==1);
    screen=newImport(); setup(@[@403,@200]); importWithMode(screen,NO); screen->saveFails=YES; [screen finishCompatibilityImportPrompt:YES]; runWork();
    CHECK("subscription-ui/failed-save-no-record",[requests count]==2 && ![screen->_subscriptions count] && !screen->_pendingCompatibilityImport);
    screen=newImport(); setup(@[@403,@200]); importWithMode(screen,NO); invalidBody=YES; [screen finishCompatibilityImportPrompt:YES]; runWork();
    CHECK("subscription-ui/invalid-retry-data-no-record",[requests count]==2 && ![screen->_subscriptions count] && !screen->commits);
    screen=newImport(); setup(@[@403,@600]); importWithMode(screen,NO); [screen finishCompatibilityImportPrompt:YES]; runWork();
    CHECK("subscription-ui/tls-failure-still-needs-consent",screen->insecurePrompts==1 && ![screen->_subscriptions count] && screen->_pendingInsecureImportUsesCompatibleUserAgent && !screen->_pendingInsecureImportAllowsPlainHTTP);
    for (unsigned change=0;change<5;change++) {
        screen=newImport(); setup(@[@403]); importWithMode(screen,NO);
        if (change==0) screen->_configurationRevision++;
        else if (change==1) [screen->_subscriptions addObject:@{@"url":sourceURL,@"items":@[]}];
        else if (change==2) screen->mutationBlocked=YES;
        else if (change==3) screen->connectionBusy=YES;
        else screen->_configurationDraft=@{};
        [screen finishCompatibilityImportPrompt:YES]; runWork();
        CHECK("subscription-ui/stale-retry-does-not-run",[requests count]==1 && !screen->commits && !screen->_pendingCompatibilityImport);
    }
    screen=newImport(); setup(@[@403]); [screen->_subscriptions addObject:@{@"url":sourceURL,@"items":@[]}]; shownAlerts=0; importWithMode(screen,NO);
    CHECK("subscription-ui/existing-source-not-offered-compatibility",!shownAlerts && !screen->_pendingCompatibilityImport && screen->failures==1);
    screen=newImport(); setup(@[@403]); [screen showCompatibilityImportPromptForURLs:@[sourceURL] allowInsecureFetch:NO allowPlainHTTP:NO]; [screen finishCompatibilityImportPrompt:YES]; [screen->_subscriptionTask cancelWithReason:nil]; runWork();
    CHECK("subscription-ui/cancelled-retry-not-applied",![screen->_subscriptions count] && !screen->commits && !screen->_pendingCompatibilityImport);
    screen=newImport(); setup(@[@403]); screen->_photoQRQueue=[[NSMutableArray alloc] init]; importWithMode(screen,NO);
    CHECK("subscription-ui/photo-awaiting-choice-not-failed-yet",screen->_pendingCompatibilityImport && !screen->_photoQRFailures);
    [screen finishCompatibilityImportPrompt:NO]; CHECK("subscription-ui/photo-declined-records-one-failure",screen->_photoQRFailures==1);
    screen=newImport(); setup(@[]);
    NSMutableArray *urls=[NSMutableArray arrayWithObject:sourceURL];
    [screen showCompatibilityImportPromptForURLs:urls allowInsecureFetch:NO allowPlainHTTP:NO]; [urls removeAllObjects];
    CHECK("subscription-ui/prompt-owns-immutable-snapshot",[[screen->_pendingCompatibilityImport objectForKey:@"urls"] isEqual:@[sourceURL]]);
    [screen finishCompatibilityImportPrompt:NO];
}
static void crypt3FetchTests(void) {
    NSData *data=[NSData dataWithContentsOfFile:@"happ_crypt3_fixtures.json"];
    NSDictionary *fixtures=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSString *link=[[fixtures objectForKey:@"short"] objectForKey:@"link"];
    NSString *target=VCHappDecryptedLink(link,NULL);
    CHECK("happ/crypt3-fetch-fixture",[target isEqual:@"https://example.test/subscription?token=vless-core"]);
    NSDictionary *source=@{@"url":link,@"name":@"Provider",@"items":@[@"socks5://old.test:1080"]};
    MainVC *screen=newImport();
    for (NSUInteger attempt=0;attempt<2;attempt++) {
        setup(@[@200]); NSString *error=nil;
        NSDictionary *updated=[screen updatedSubscriptionDictionaryFromSource:source errorText:&error];
        CHECK("happ/crypt3-fetch-success",updated && !error && [requests count]==1);
        NSDictionary *request=[requests objectAtIndex:0];
        CHECK("happ/crypt3-fetch-target",[[request objectForKey:@"url"] isEqual:target]);
        CHECK("happ/crypt3-fetch-headers",[[request objectForKey:@"happ"] boolValue] && [[request objectForKey:@"hwid"] boolValue] && [[request objectForKey:@"agent"] isEqual:kHappSubscriptionUserAgent]);
        CHECK("happ/crypt3-fetch-source-preserved",[[updated objectForKey:@"url"] isEqual:link] && SubscriptionDictionaryIsHappEncrypted(updated));
        source=[NSJSONSerialization JSONObjectWithData:[NSJSONSerialization dataWithJSONObject:updated options:0 error:NULL] options:0 error:NULL];
    }
    for (NSNumber *status in @[@403,@600,@700]) {
        setup(@[status]); failureDetails=[NSString stringWithFormat:@"curl: failed to fetch %@",target];
        NSString *error=nil; BOOL retry=NO;
        CHECK("happ/crypt3-fetch-failure",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry]);
        CHECK("happ/crypt3-fetch-no-retry",[requests count]==1);
        CHECK("happ/crypt3-fetch-safe-error",[error length] && [error rangeOfString:@"example.test"].location==NSNotFound && [error rangeOfString:@"token="].location==NSNotFound);
        CHECK("happ/crypt3-fetch-retains-tls-confirmation",retry==([status intValue]==600));
    }
    setup(@[]); NSString *error=nil;
    CHECK("happ/crypt3-bad-wrapper-no-fetch",![screen updatedSubscriptionDictionaryFromSource:@{@"url":@"happ://crypt3/!"} errorText:&error] && ![requests count]);
    for (NSUInteger failure=0;failure<2;failure++) {
        BOOL fail=failure!=0;
        screen=newImport(); screen->saveFails=fail; setup(@[@200]);
        [screen performSubscriptionImportForURLs:@[link] allowInsecureFetch:NO fallbackSubscriptionsByURL:nil allowPlainHTTP:NO useCompatibleUserAgent:NO]; runWork();
        CHECK("happ/crypt3-import-single-commit",screen->commits==1);
        CHECK("happ/crypt3-import-atomic",[screen->_subscriptions count]==(fail ? 0 : 1));
        if (!fail) CHECK("happ/crypt3-import-wrapper",[[[screen->_subscriptions objectAtIndex:0] objectForKey:@"url"] isEqual:link]);
    }
    setup(@[@200]); cancelFirst=YES;
    VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease];
    VCSetCurrentSubscriptionTask(task);
    CHECK("happ/crypt3-cancelled-fetch-not-applied",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error] && [requests count]==1);
    VCSetCurrentSubscriptionTask(nil);
}

int main(void) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    MainVC *screen=[[[MainVC alloc] init] autorelease];
    NSDictionary *source=@{@"url":sourceURL,@"name":@"Mine",kSubscriptionCustomNameKey:@"Mine",@"items":@[@"socks5://old.test"]};
    NSString *error=nil; BOOL retry=NO;
    setup(@[@403]);
    NSDictionary *updated=[screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry];
    CHECK("subscription-fetch/403-no-automatic-retry",!updated && [requests count]==1 && [error hasPrefix:@"Subscription fetch failed: HTTP 403."]);
    CHECK("subscription-fetch/403-source-not-modified",![source objectForKey:compatibilityKey] && [[source objectForKey:@"items"] isEqual:@[@"socks5://old.test"]]);
    NSMutableDictionary *approvedSource=[NSMutableDictionary dictionaryWithDictionary:source];
    [approvedSource setObject:@(YES) forKey:compatibilityKey];
    setup(@[@200]);
    updated=[screen updatedSubscriptionDictionaryFromSource:approvedSource errorText:&error insecureRetryAvailable:&retry];
    CHECK("subscription-fetch/explicit-compatible-request",updated && !error && [requests count]==1);
    CHECK("subscription-fetch/source-and-name-preserved",[[updated objectForKey:@"url"] isEqual:sourceURL] && [[updated objectForKey:@"name"] isEqual:@"Mine"]);
    CHECK("subscription-fetch/remembers-successful-agent",[[updated objectForKey:compatibilityKey] isEqual:@(YES)]);
    CHECK("subscription-fetch/no-happ-privileges",!SubscriptionDictionaryUsesHappHeaders(updated) && !SubscriptionDictionaryIsHappEncrypted(updated) && !SubscriptionDictionaryAllowsPlainHTTP(updated) && !SubscriptionDictionaryAllowsInsecureFetch(updated));
    CHECK("subscription-fetch/only-agent-changes",[[requests objectAtIndex:0] isEqual:@{@"url":sourceURL,@"agent":kHappSubscriptionUserAgent,@"insecure":@(NO),@"plain":@(NO),@"happ":@(NO),@"hwid":@(YES)}]);
    NSData *stored=[NSJSONSerialization dataWithJSONObject:updated options:0 error:NULL];
    NSDictionary *reloaded=[NSJSONSerialization JSONObjectWithData:stored options:0 error:NULL];
    setup(@[@200]);
    CHECK("subscription-fetch/reload-skips-failed-negotiation",[screen updatedSubscriptionDictionaryFromSource:reloaded errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && [[[requests objectAtIndex:0] objectForKey:@"agent"] isEqual:kHappSubscriptionUserAgent]);
    setup(@[@200]);
    updated=[screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry];
    CHECK("subscription-fetch/normal-source-no-spoof",updated && [requests count]==1 && [[[requests objectAtIndex:0] objectForKey:@"agent"] isEqual:AppUserAgent()] && ![updated objectForKey:compatibilityKey]);
    for (NSNumber *status in @[@401,@404,@429,@500,@600,@700]) {
        setup(@[status]);
        CHECK("subscription-fetch/other-failures-no-retry",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && error);
        CHECK("subscription-fetch/tls-confirmation-preserved",retry==([status intValue]==600));
    }
    setup(@[@403]);
    CHECK("subscription-fetch/no-unbounded-retry",![screen updatedSubscriptionDictionaryFromSource:approvedSource errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && !retry);
    setup(@[@600]);
    CHECK("subscription-fetch/retry-never-disables-tls",![screen updatedSubscriptionDictionaryFromSource:approvedSource errorText:&error insecureRetryAvailable:&retry] && retry && ![[[requests objectAtIndex:0] objectForKey:@"insecure"] boolValue]);
    setup(@[@200]); invalidBody=YES;
    CHECK("subscription-fetch/invalid-data-does-not-enable-agent",![screen updatedSubscriptionDictionaryFromSource:approvedSource errorText:&error insecureRetryAvailable:&retry] && ![source objectForKey:compatibilityKey] && [[source objectForKey:@"items"] isEqual:@[@"socks5://old.test"]]);
    setup(@[@403]); cancelFirst=YES;
    VCSubscriptionTask *task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease]; VCSetCurrentSubscriptionTask(task);
    CHECK("subscription-fetch/cancel-before-retry",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry] && [requests count]==1);
    setup(@[@200]); cancelFirst=YES;
    task=[[[VCSubscriptionTask alloc] initWithPreserveNames:YES observer:nil selector:NULL] autorelease]; VCSetCurrentSubscriptionTask(task);
    CHECK("subscription-fetch/cancelled-result-not-applied",![screen updatedSubscriptionDictionaryFromSource:approvedSource errorText:&error insecureRetryAvailable:&retry] && [requests count]==1);
    setup(@[@403]);
    CHECK("subscription-fetch/happ-does-not-retry-same-agent",![screen updatedSubscriptionDictionaryFromSource:@{@"url":sourceURL,kSubscriptionHappSourceKey:@(YES)} errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && [[[requests objectAtIndex:0] objectForKey:@"happ"] boolValue]);
    setup(@[@403]);
    CHECK("subscription-fetch/remembered-agent-does-not-loop",![screen updatedSubscriptionDictionaryFromSource:reloaded errorText:&error insecureRetryAvailable:&retry] && [requests count]==1);
    for (id value in @[@(NO),@"YES",[NSNull null]]) {
        setup(@[@200]); NSMutableDictionary *bad=[NSMutableDictionary dictionaryWithDictionary:source]; [bad setObject:value forKey:compatibilityKey];
        CHECK("subscription-fetch/invalid-marker-does-not-select-agent",[screen updatedSubscriptionDictionaryFromSource:bad errorText:&error insecureRetryAvailable:&retry] && [[[requests objectAtIndex:0] objectForKey:@"agent"] isEqual:AppUserAgent()]);
    }
    for (NSString *headers in @[@"HTTP/1.0 403 Forbidden\r\n\r\n",@"HTTP/1.1 403\r\n\r\n",@"HTTP/2 403\r\n\r\n",@"HTTP/3 403 Forbidden\n\n",
        @"HTTP/1.1 200 Connection established\r\n\r\nHTTP/2 403\r\n\r\n",@"HTTP/1.1 302 Found\r\nLocation: https://provider.test/sub\r\n\r\nHTTP/1.1 403 Forbidden\r\n\r\n"]) {
        setup(@[@403]); responseHeaders=headers;
        CHECK("subscription-fetch/final-forbidden-response",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && [error hasPrefix:@"Subscription fetch failed: HTTP 403."]);
    }
    for (id headers in @[@"",@"HTTP/2 403\r\n\r\nHTTP/2 404\r\n\r\n",@"HTTP/1.1 200 OK\r\nX-Error: HTTP/1.1 403\r\n\r\n",
        @"HTTP/1.1 +403\r\n",@"HTTP/1.1 4030\r\n",@"HTTP/1.1 403x\r\n",@"HTTP/1.1 40\r\n",@"HTTP/1.1\r\n"]) {
        setup(@[@403]); responseHeaders=headers;
        CHECK("subscription-fetch/not-forbidden-no-retry",![screen updatedSubscriptionDictionaryFromSource:source errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && ![error hasPrefix:@"Subscription fetch failed: HTTP 403."]);
    }
    setup(@[@200]);
    NSMutableDictionary *approved=[NSMutableDictionary dictionaryWithDictionary:approvedSource];
    [approved setObject:@(YES) forKey:kSubscriptionAllowPlainHTTPKey]; [approved setObject:@(YES) forKey:kSubscriptionAllowInsecureFetchKey];
    CHECK("subscription-fetch/explicit-approvals-retained",[screen updatedSubscriptionDictionaryFromSource:approved errorText:&error insecureRetryAvailable:&retry] && [requests count]==1 && [[[requests objectAtIndex:0] objectForKey:@"plain"] boolValue] && [[[requests objectAtIndex:0] objectForKey:@"insecure"] boolValue]);
    setup(@[@403]);
    NSString *incy=@"incy://crypt1/AAECAwQFBgcICQoLNyIQL3rDwRZqnyoD8pGKSLXP6o8NdSXQVSSALNbbUyIr__tWGFUexdIfKvvmDnuDGbmBvuppfNef6aKNZUwOm4c-Sg";
    CHECK("subscription-fetch/incy-safe-403",![screen updatedSubscriptionDictionaryFromSource:@{@"url":incy} errorText:&error insecureRetryAvailable:&retry] && [error hasPrefix:@"Subscription fetch failed: HTTP 403."] && [error rangeOfString:@"sub.example.com"].location==NSNotFound);
    setup(@[@200]);
    updated=[screen updatedSubscriptionDictionaryFromSource:@{@"url":incy,compatibilityKey:@(YES)} errorText:&error insecureRetryAvailable:&retry];
    CHECK("subscription-fetch/incy-keeps-original-wrapper",updated && [[updated objectForKey:@"url"] isEqual:incy] && !SubscriptionDictionaryUsesHappHeaders(updated));
    VCSetCurrentSubscriptionTask(nil);
    promptTests();
    editSaveTests();
    editRefreshTests();
    crypt3FetchTests();
    FINISH("subscription fetch compatibility"); [pool drain]; return 0;
}
