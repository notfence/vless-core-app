#import "main_screen.h"
#import "diagnostics.h"

@interface AppDelegate : UIResponder <UIApplicationDelegate> {
    UIWindow *_window;
}
@property (nonatomic, retain) UIWindow *window;
@end

@implementation AppDelegate
@synthesize window = _window;

- (BOOL)openImportURL:(NSURL *)url {
    if (![url isKindOfClass:[NSURL class]] || ![url isFileURL]) return NO;
    UIViewController *root = _window.rootViewController;
    if (![root isKindOfClass:[MainVC class]]) return NO;
    VCRecordAppEvent(@"import", @"File import opened by another application", nil);
    [(MainVC *)root importFileAtURL:url];
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;

    VCRecordAppEvent(@"lifecycle", @"Application launched", nil);
    VCSendCommandAsync(@"CLEAR_LOGS\n", nil);
    VCAppearanceApplyStatusBar();
    _window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    _window.backgroundColor = VCBackgroundColor();
    MainVC *vc = [[[MainVC alloc] init] autorelease];
    _window.rootViewController = vc;
    [_window makeKeyAndVisible];

    NSURL *launchURL = [launchOptions objectForKey:UIApplicationLaunchOptionsURLKey];
    if ([launchURL isFileURL]) {
        [self performSelector:@selector(openImportURL:) withObject:launchURL afterDelay:0.15];
    }
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application became active", nil);
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application entered background", nil);
    [[VCAppEventRecorder sharedRecorder] flushNow];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    (void)application;
    return [self openImportURL:url];
}

- (BOOL)application:(UIApplication *)application
             openURL:(NSURL *)url
   sourceApplication:(NSString *)sourceApplication
          annotation:(id)annotation {
    (void)application;
    (void)sourceApplication;
    (void)annotation;
    return [self openImportURL:url];
}

- (BOOL)application:(UIApplication *)application
             openURL:(NSURL *)url
             options:(NSDictionary *)options {
    (void)application;
    (void)options;
    return [self openImportURL:url];
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown : UIInterfaceOrientationMaskPortrait;
}

- (void)applicationWillTerminate:(UIApplication *)application {
    (void)application;
    VCRecordAppEvent(@"lifecycle", @"Application will terminate", nil);
    [[VCAppEventRecorder sharedRecorder] flushNow];
    ClearLogsViaDaemon();
}

- (void)dealloc {
    [_window release];
    [super dealloc];
}

@end

int main(int argc, char **argv) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int rc = UIApplicationMain(argc, argv, nil, @"AppDelegate");
    [pool release];
    return rc;
}
