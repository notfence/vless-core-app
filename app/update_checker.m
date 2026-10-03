#import "update_checker.h"

static NSDictionary *VCPerformUpdateCheck(void) {
    NSString *userAgent = AppUserAgent();
    NSString *fetchError = nil;
    NSData *data = FetchURLViaVlessCoreCurl(kUpdateAPIURL,
                                            NO,
                                            NO,
                                            NO,
                                            NO,
                                            userAgent,
                                            &fetchError,
                                            NULL,
                                            NULL);
    if (!data) {
        NSString *message = ([fetchError length] > 0) ? fetchError : @"Unable to reach GitHub";
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                message, @"error",
                nil];
    }

    NSError *jsonError = nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (![json isKindOfClass:[NSDictionary class]]) {
        NSString *message = jsonError ? [jsonError localizedDescription] : @"Invalid update response";
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                message, @"error",
                nil];
    }

    NSString *tag = [(NSDictionary *)json objectForKey:@"tag_name"];
    NSString *releaseURL = [(NSDictionary *)json objectForKey:@"html_url"];
    if (![tag isKindOfClass:[NSString class]] || [VCNumericVersionComponents(tag) count] == 0) {
        return [NSDictionary dictionaryWithObjectsAndKeys:
                @"error", @"status",
                @"The latest release has no valid version", @"error",
                nil];
    }
    if (![releaseURL isKindOfClass:[NSString class]] || [releaseURL length] == 0) {
        releaseURL = kUpdateReleasesURL;
    }
    tag = VCNormalizedReleaseVersion(tag);

    NSString *currentVersion = AppShortVersion();
    BOOL updateAvailable = (VCCompareVersions(currentVersion, tag) == NSOrderedAscending);
    return [NSDictionary dictionaryWithObjectsAndKeys:
            (updateAvailable ? @"update" : @"current"), @"status",
            currentVersion, @"current_version",
            tag, @"latest_version",
            releaseURL, @"release_url",
            nil];
}

void VCCacheSuccessfulUpdateResult(NSDictionary *result) {
    VCCacheSuccessfulUpdateResultAtTime(result, [NSUserDefaults standardUserDefaults], [[NSDate date] timeIntervalSince1970]);
}

BOOL VCAutomaticUpdateCheckIsFresh(void) {
    return VCAutomaticUpdateCheckIsFreshAtTime([NSUserDefaults standardUserDefaults], [[NSDate date] timeIntervalSince1970]);
}

@class VCUpdateChecker;

@implementation VCUpdateChecker
@synthesize delegate = _delegate;

- (id)initWithDelegate:(id<VCUpdateCheckerDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

- (void)start {
    if (_started) return;
    _started = YES;
    [NSThread detachNewThreadSelector:@selector(checkWorker) toTarget:self withObject:nil];
}

- (void)checkWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *result = [VCPerformUpdateCheck() retain];
    [self retain];
    [self performSelectorOnMainThread:@selector(deliverResult:) withObject:result waitUntilDone:YES];
    [result release];
    [pool drain];
}

- (void)deliverResult:(NSDictionary *)result {
    id<VCUpdateCheckerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(updateChecker:didFinishWithResult:)]) {
        [delegate updateChecker:self didFinishWithResult:result];
    }
    [self release];
}

@end

void VCShowUpdateAvailableAlert(NSDictionary *result,
                                       id<UIAlertViewDelegate> delegate,
                                       NSInteger tag) {
    NSString *message = [NSString stringWithFormat:@"Version %@ is available.\n Currently installed: %@.",
                         [result objectForKey:@"latest_version"],
                         [result objectForKey:@"current_version"]];
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Update Available"
                                                     message:message
                                                    delegate:delegate
                                           cancelButtonTitle:@"Later"
                                           otherButtonTitles:@"View Release", nil] autorelease];
    alert.tag = tag;
    [alert show];
}
