#import <Foundation/Foundation.h>
#import "../common/secure_store.h"
#import "../common/list_logic.h"
#import "../common/app_constants.h"
#include "check.h"
#include <sys/resource.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

@class SettingsVC;
static BOOL gVCSecureStoreWritable=YES;
static NSUInteger keyRequests;
static NSString *storeCommand(NSString *command) {
    CHECK("state/store-key-command",[command isEqual:@"STORE_KEY\tCREATE\n"]);
    keyRequests++;
    return @"OK 0101010101010101010101010101010101010101010101010101010101010101\n";
}
static BOOL protectFile(NSString *path) { (void)path; return YES; }
static void VCRecordAppEvent(NSString *category,NSString *action,NSString *detail) { (void)category; (void)action; (void)detail; }

@interface VCStateView : NSObject
- (void)reloadData;
@end
@implementation VCStateView
- (void)reloadData {}
@end
@interface VCStateChecker : NSObject { id delegate; }
@property(assign) id delegate;
@end
@implementation VCStateChecker
@synthesize delegate;
@end

@interface MainVC : NSObject {
@public
    BOOL _configurationLoading,_applyingConfigurationDraft,_configurationCommitInProgress;
    BOOL _autoUpdateSubscriptions,_preserveCustomSubscriptionNames,_stealthModeEnabled,_darkThemeEnabled,_automaticUpdateChecksEnabled;
    NSUInteger _configurationRevision,_storeSequence,metadataPreparations,mainStateSaves,completions;
    NSMutableArray *_configs,*_subscriptions;
    VCSubscriptionPingOrder *_subscriptionPingOrder;
    VCConfigurationStoreWriter *_configurationWriter;
    VCStateView *_tableView;
    VCStateChecker *_updateChecker;
}
- (void)saveMainState;
- (void)saveSettings;
- (void)saveData;
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index;
- (NSInteger)subscriptionRowsExpandedIndex;
- (void)prepareProfileMetadata;
- (void)keepConfigurationWriteAlive;
- (void)configurationStoreFinished:(NSDictionary *)result;
- (void)updateMainEmptyState;
- (void)refreshMainSwitcher;
- (void)showStatus:(NSString *)text ok:(BOOL)ok;
- (void)applyTheme;
- (void)settingsVC:(SettingsVC *)vc didChangeAutoUpdate:(BOOL)value;
- (void)settingsVC:(SettingsVC *)vc didChangeAutomaticUpdateChecks:(BOOL)value;
- (void)settingsVC:(SettingsVC *)vc didChangePreserveCustomSubscriptionNames:(BOOL)value;
- (void)settingsVC:(SettingsVC *)vc didChangeStealthMode:(BOOL)value;
- (void)settingsVC:(SettingsVC *)vc didChangeDarkTheme:(BOOL)value;
@end

@implementation MainVC
- (void)saveMainState { mainStateSaves++; }
- (NSArray *)subscriptionItemsAtIndex:(NSInteger)index { (void)index; return @[]; }
- (NSInteger)subscriptionRowsExpandedIndex { return -1; }
- (void)prepareProfileMetadata { metadataPreparations++; }
- (void)keepConfigurationWriteAlive {}
- (void)configurationStoreFinished:(NSDictionary *)result { CHECK("state/save-succeeded",[[result objectForKey:@"saved"] boolValue]); completions++; }
- (void)updateMainEmptyState {}
- (void)refreshMainSwitcher {}
- (void)showStatus:(NSString *)text ok:(BOOL)ok { (void)text; (void)ok; }
- (void)applyTheme {}
- (void)dealloc { [_configs release]; [_subscriptions release]; [_subscriptionPingOrder release]; [_configurationWriter release]; [_tableView release]; [_updateChecker release]; [super dealloc]; }
#include "main_state_save.inc"
#include "main_state_settings.inc"
@end

static double nowMS(void) {
    struct timeval value; gettimeofday(&value,NULL);
    return value.tv_sec*1000.0+value.tv_usec/1000.0;
}
static void awaitWrites(MainVC *controller) {
    double deadline=nowMS()+300000;
    while ((!controller->_configurationWriter.isIdle || controller->completions < keyRequests) && nowMS()<deadline)
        if (![[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:.001]]) usleep(1000);
    CHECK("state/writer-drained",controller->_configurationWriter.isIdle);
}
int main(int argc,char **argv) {
    NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
    BOOL measure=argc>1 && !strcmp(argv[1],"--measure");
    NSUInteger count=measure && argc>2 ? strtoul(argv[2],NULL,10) : 1;
    char temporary[]="/tmp/vless-state-test-XXXXXX";
    CHECK("state/private-directory",mkdtemp(temporary)!=NULL);
    NSString *directory=[NSString stringWithUTF8String:temporary];
    VCStoragePaths paths={directory,[directory stringByAppendingPathComponent:@"configs.dat"],[directory stringByAppendingPathComponent:@"events.db"],storeCommand,protectFile};
    MainVC *controller=[[MainVC alloc] init];
    controller->_configs=[[NSMutableArray alloc] init]; controller->_subscriptions=[[NSMutableArray alloc] init];
    for (NSUInteger i=0;i<count;i++) [controller->_configs addObject:@{@"name":[NSString stringWithFormat:@"Profile %lu",(unsigned long)i],@"uri":[NSString stringWithFormat:@"vless://11111111-2222-4333-8444-555555555555@profile%lu.test:443?type=ws&security=tls#Profile%lu",(unsigned long)i,(unsigned long)i]}];
    controller->_configurationWriter=[[VCConfigurationStoreWriter alloc] initWithPaths:&paths];
    controller->_tableView=[[VCStateView alloc] init];
    NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
    NSArray *keys=@[kDefaultsAutoUpdateSubsKey,kDefaultsPreserveCustomSubscriptionNamesKey,kDefaultsStealthModeKey,kDefaultsDarkThemeKey,kDefaultsAutomaticUpdateChecksKey];
    NSMutableDictionary *previous=[NSMutableDictionary dictionary];
    for (NSString *key in keys) if ([defaults objectForKey:key]) [previous setObject:[defaults objectForKey:key] forKey:key];
    double began=nowMS();
    [controller settingsVC:nil didChangeStealthMode:YES]; awaitWrites(controller);
    if (!measure) {
        [controller settingsVC:nil didChangeAutoUpdate:YES]; awaitWrites(controller);
        [controller settingsVC:nil didChangePreserveCustomSubscriptionNames:YES]; awaitWrites(controller);
        [controller settingsVC:nil didChangeDarkTheme:YES]; awaitWrites(controller);
        [controller settingsVC:nil didChangeAutomaticUpdateChecks:NO]; awaitWrites(controller);
    }
    double elapsed=nowMS()-began;
    if (!measure) {
        CHECK("state/settings-do-not-request-key",keyRequests==0);
        CHECK("state/settings-do-not-rebuild-metadata",controller->metadataPreparations==0);
        CHECK("state/settings-do-not-change-config-revision",controller->_configurationRevision==0);
        CHECK("state/settings-do-not-write-profiles",![[NSFileManager defaultManager] fileExistsAtPath:paths.file]);
        CHECK("state/settings-save-ui-state",controller->mainStateSaves==5);
        for (NSString *key in keys) CHECK("state/settings-persist-values",[defaults boolForKey:key]==![key isEqual:kDefaultsAutomaticUpdateChecksKey]);
        [controller saveData]; awaitWrites(controller);
        CHECK("state/profiles-still-write",keyRequests==1 && controller->_configurationRevision==1 && controller->metadataPreparations==1);
        controller->_configurationLoading=YES;
        [controller settingsVC:nil didChangeDarkTheme:NO];
        CHECK("state/loading-does-not-save",controller->mainStateSaves==6 && keyRequests==1);
    }
    struct rusage usage; getrusage(RUSAGE_SELF,&usage);
    printf("{\"count\":%lu,\"settings_ms\":%.6f,\"store_writes\":%lu,\"metadata_preparations\":%lu,\"cpu_s\":%.6f,\"maxrss\":%ld}\n",(unsigned long)count,elapsed,(unsigned long)keyRequests,(unsigned long)controller->metadataPreparations,usage.ru_utime.tv_sec+usage.ru_utime.tv_usec/1e6+usage.ru_stime.tv_sec+usage.ru_stime.tv_usec/1e6,usage.ru_maxrss);
    for (NSString *key in keys) { id value=[previous objectForKey:key]; if (value) [defaults setObject:value forKey:key]; else [defaults removeObjectForKey:key]; }
    [NSObject cancelPreviousPerformRequestsWithTarget:controller]; [controller release];
    CHECK("state/remove-fixture",[[NSFileManager defaultManager] removeItemAtPath:directory error:NULL]);
    [pool drain]; return 0;
}
