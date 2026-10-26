#import "diagnostics.h"

NSString *ClearLogsViaDaemon(void) {
    return SendCommand(@"CLEAR_LOGS\n");
}

static NSString *VCLogTextFromResponse(NSString *response, NSInteger index, NSUInteger maxBytes) {
    NSString *name = index == 1 ? @"core" : @"daemon";
    if (![response hasPrefix:@"OK\n"]) {
        return [NSString stringWithFormat:@"(cannot read %@ log: %@)\n", name, response ? response : @"no response"];
    }

    NSData *data = [[response substringFromIndex:3] dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || [data length] == 0) {
        return @"(empty)\n";
    }
    if (maxBytes > 0 && [data length] > maxBytes) {
        NSUInteger start = [data length] - maxBytes;
        const unsigned char *bytes = (const unsigned char *)[data bytes];
        if (start > 0 && bytes[start - 1] != '\n') {
            NSUInteger nextLine = start;
            while (nextLine < [data length] && bytes[nextLine] != '\n') nextLine++;
            if (nextLine < [data length]) start = nextLine + 1;
        }
        data = [data subdataWithRange:NSMakeRange(start, [data length] - start)];
    }

    NSString *txt = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    if (!txt) {
        txt = [[[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding] autorelease];
    }
    if (!txt) {
        return @"(unreadable)\n";
    }
    return txt;
}

NSString *ReadDaemonLog(NSInteger index, NSUInteger maxBytes) {
    NSString *name = index == 1 ? @"core" : @"daemon";
    return VCLogTextFromResponse(SendCommand([NSString stringWithFormat:@"LOG\t%@\n", name]), index, maxBytes);
}

NSString *ReadLogAtIndex(NSInteger index) {
    return ReadDaemonLog(index, 8192);
}

void ReadLogAtIndexAsync(NSInteger index, void (^completion)(NSString *)) {
    NSString *name = index == 1 ? @"core" : @"daemon";
    VCSendCommandAsync([NSString stringWithFormat:@"LOG\t%@\n", name], ^(NSString *response) {
        if (completion) completion(VCLogTextFromResponse(response, index, 8192));
    });
}

UIFont *VCLogRegularFont(void) {
    UIFont *font = [UIFont fontWithName:@"CourierNewPSMT" size:10.0f];
    if (!font) font = [UIFont fontWithName:@"Courier" size:10.0f];
    return font ? font : [UIFont systemFontOfSize:10.0f];
}

static UIFont *VCLogBoldFont(void) {
    UIFont *font = [UIFont fontWithName:@"CourierNewPS-BoldMT" size:10.0f];
    if (!font) font = [UIFont fontWithName:@"Courier-Bold" size:10.0f];
    return font ? font : [UIFont boldSystemFontOfSize:10.0f];
}

static UIColor *VCLogLevelColor(unichar level) {
    if (level == 'E') return VCErrorColor();
    if (level == 'W') {
        return VCAppearanceIsDark()
            ? [UIColor colorWithRed:1.0f green:0.70f blue:0.22f alpha:1.0f]
            : [UIColor colorWithRed:0.72f green:0.40f blue:0.02f alpha:1.0f];
    }
    if (level == 'I') return VCDefaultAccentColor();
    return VCSecondaryTextColor();
}

NSAttributedString *VCFormattedLogText(NSString *text) NS_AVAILABLE_IOS(6_0);
NSAttributedString *VCFormattedLogText(NSString *text) {
    NSString *source = text ? text : @"";
    NSMutableParagraphStyle *paragraph = [[[NSMutableParagraphStyle alloc] init] autorelease];
    paragraph.lineSpacing = 1.0f;
    paragraph.paragraphSpacing = 5.0f;
    paragraph.firstLineHeadIndent = 0.0f;
    paragraph.headIndent = 12.0f;
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;

    NSDictionary *baseAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        VCLogRegularFont(), NSFontAttributeName,
        VCPrimaryTextColor(), NSForegroundColorAttributeName,
        paragraph, NSParagraphStyleAttributeName,
        nil];
    NSMutableAttributedString *formatted = [[[NSMutableAttributedString alloc]
        initWithString:source attributes:baseAttributes] autorelease];

    NSUInteger sourceLength = [source length];
    NSUInteger lineStart = 0;
    while (lineStart < sourceLength) {
        NSRange searchRange = NSMakeRange(lineStart, sourceLength - lineStart);
        NSRange newline = [source rangeOfString:@"\n" options:0 range:searchRange];
        NSUInteger lineEnd = newline.location == NSNotFound ? sourceLength : newline.location;
        NSUInteger lineLength = lineEnd - lineStart;

        if (lineLength >= 26 &&
            [source characterAtIndex:lineStart + 4] == '-' &&
            [source characterAtIndex:lineStart + 10] == ' ' &&
            [source characterAtIndex:lineStart + 23] == ' ' &&
            [source characterAtIndex:lineStart + 25] == ' ') {
            unichar level = [source characterAtIndex:lineStart + 24];
            if (level == 'D' || level == 'I' || level == 'W' || level == 'E') {
                [formatted addAttribute:NSForegroundColorAttributeName
                                  value:VCSecondaryTextColor()
                                  range:NSMakeRange(lineStart, 23)];
                [formatted addAttribute:NSFontAttributeName
                                  value:VCLogBoldFont()
                                  range:NSMakeRange(lineStart + 24, 1)];
                [formatted addAttribute:NSForegroundColorAttributeName
                                  value:VCLogLevelColor(level)
                                  range:NSMakeRange(lineStart + 24, 1)];

                if (lineLength > 27 && [source characterAtIndex:lineStart + 26] == '[') {
                    NSUInteger componentStart = lineStart + 26;
                    NSRange componentSearch = NSMakeRange(lineStart + 27, lineLength - 27);
                    NSRange componentEnd = [source rangeOfString:@"]" options:0 range:componentSearch];
                    if (componentEnd.location != NSNotFound) {
                        NSRange componentRange = NSMakeRange(componentStart,
                                                             componentEnd.location - componentStart + 1);
                        [formatted addAttribute:NSForegroundColorAttributeName
                                          value:VCSecondaryTextColor()
                                          range:componentRange];
                        [formatted addAttribute:NSFontAttributeName
                                          value:VCLogBoldFont()
                                          range:componentRange];
                    }
                }
            }
        }

        if (newline.location == NSNotFound) break;
        lineStart = newline.location + 1;
    }
    return formatted;
}

typedef NS_ENUM(NSInteger, VCDebugSection) {
    VCDebugSectionLiveState = 0,
    VCDebugSectionConnectionQuality,
    VCDebugSectionActivityLogging,
    VCDebugSectionRecentActivity,
    VCDebugSectionDiagnostics,
    VCDebugSectionCount,
};

void VCRecordDaemonAuthorizationFailure(NSString *response) {
    static NSString *previousDetail = nil;
    static NSTimeInterval previousTimestamp = 0;
    if (![response isKindOfClass:[NSString class]] ||
        ![response hasPrefix:@"ERR unauthorized client"]) return;

    NSString *safeDetail = VCSanitizeDiagnosticText(response, 192);
    NSTimeInterval timestamp = CACurrentMediaTime();
    BOOL shouldRecord = NO;
    @synchronized([VCAppEventRecorder class]) {
        if (![previousDetail isEqualToString:safeDetail] || timestamp - previousTimestamp >= 60.0) {
            [previousDetail release];
            previousDetail = [safeDetail copy];
            previousTimestamp = timestamp;
            shouldRecord = YES;
        }
    }
    if (shouldRecord) {
        VCRecordAppEvent(@"daemon", @"Daemon authorization rejected", safeDetail);
    }
}

static BOOL VCAppActivityLoggingEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kDefaultsDiagnosticAppActivityKey];
}

static NSArray *VCLoadDiagnosticEventDatabase(void) {
    VCStoragePaths paths = VCMainStoragePaths();
    return VCLoadDiagnosticEventDatabaseAtPaths(&paths);
}

static BOOL VCInsertDiagnosticEventBatch(NSArray *events) {
    VCStoragePaths paths = VCMainStoragePaths();
    return VCInsertDiagnosticEventBatchAtPaths(events, &paths);
}

static void VCClearDiagnosticEventDatabase(void) {
    VCStoragePaths paths = VCMainStoragePaths();
    VCClearDiagnosticEventDatabaseAtPaths(&paths);
}

static void VCPurgeOptionalDiagnosticEvents(void) {
    VCStoragePaths paths = VCMainStoragePaths();
    VCPurgeOptionalDiagnosticEventsAtPaths(&paths);
}

@implementation VCAppEventRecorder

+ (VCAppEventRecorder *)sharedRecorder {
    static VCAppEventRecorder *recorder = nil;
    @synchronized(self) {
        if (!recorder) recorder = [[VCAppEventRecorder alloc] init];
    }
    return recorder;
}

- (id)init {
    self = [super init];
    if (!self) return nil;
    _events = [[NSMutableArray alloc] init];
    _pendingEvents = [[NSMutableArray alloc] init];
    _writeQueue = dispatch_queue_create("com.vlesscore.diagnostics.write", DISPATCH_QUEUE_SERIAL);
    BOOL appActivityEnabled = VCAppActivityLoggingEnabled();
    NSArray *stored = VCLoadDiagnosticEventDatabase();
    for (NSDictionary *event in stored) {
        if (appActivityEnabled ||
            !VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                            [event objectForKey:@"action"])) {
            [_events addObject:event];
        }
    }
    if (!appActivityEnabled && _writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCPurgeOptionalDiagnosticEvents();
            [pool drain];
        });
    }
    return self;
}

- (void)scheduleFlushOnMainThread {
    @synchronized(self) {
        if (!_flushScheduled) return;
    }
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    [self performSelector:@selector(flushPendingEvents) withObject:nil afterDelay:2.0];
}

- (void)recordCategory:(NSString *)category action:(NSString *)action detail:(NSString *)detail {
    if (!VCAppActivityLoggingEnabled() && VCIsOptionalAppDiagnosticEvent(category, action)) return;
    NSTimeInterval seconds = [[NSDate date] timeIntervalSince1970];
    NSDictionary *event = VCMakeAppDiagnosticEvent((long long)(seconds * 1000.0),
                                                   category,
                                                   action,
                                                   detail);
    if (!event) return;
    @synchronized(self) {
        [_events addObject:event];
        [_pendingEvents addObject:event];
        if ([_events count] > kVCDiagnosticEventCapacity) {
            [_events removeObjectsInRange:
             NSMakeRange(0, [_events count] - kVCDiagnosticEventCapacity)];
        }
        if ([_pendingEvents count] > kVCDiagnosticEventCapacity) {
            [_pendingEvents removeObjectsInRange:
             NSMakeRange(0, [_pendingEvents count] - kVCDiagnosticEventCapacity)];
        }
        _flushScheduled = YES;
    }
    [self performSelectorOnMainThread:@selector(scheduleFlushOnMainThread)
                           withObject:nil
                        waitUntilDone:NO];
}

- (NSArray *)eventsSnapshot {
    @synchronized(self) {
        return [[_events copy] autorelease];
    }
}

- (void)flushPendingEvents {
    NSArray *pending = nil;
    @synchronized(self) {
        if (!_flushScheduled) return;
        _flushScheduled = NO;
        if ([_pendingEvents count] == 0) return;
        pending = [_pendingEvents copy];
        [_pendingEvents removeAllObjects];
    }
    if (_writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCInsertDiagnosticEventBatch(pending);
            [pending release];
            [pool drain];
        });
    } else {
        [pending release];
    }
}

- (void)flushNow {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    NSArray *pending = nil;
    @synchronized(self) {
        _flushScheduled = NO;
        if ([_pendingEvents count] > 0) {
            pending = [_pendingEvents copy];
            [_pendingEvents removeAllObjects];
        }
    }
    if (_writeQueue && pending) {
        dispatch_sync(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCInsertDiagnosticEventBatch(pending);
            [pool drain];
        });
    }
    [pending release];
}

- (void)clearEvents {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(flushPendingEvents)
                                               object:nil];
    @synchronized(self) {
        _flushScheduled = NO;
        [_events removeAllObjects];
        [_pendingEvents removeAllObjects];
    }
    if (_writeQueue) {
        dispatch_sync(_writeQueue, ^{
            VCClearDiagnosticEventDatabase();
        });
    } else {
        VCClearDiagnosticEventDatabase();
    }
}

- (void)setAppActivityEnabled:(BOOL)enabled {
    if (enabled) return;
    @synchronized(self) {
        for (NSInteger index = (NSInteger)[_events count] - 1; index >= 0; index--) {
            NSDictionary *event = [_events objectAtIndex:index];
            if (VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                               [event objectForKey:@"action"])) {
                [_events removeObjectAtIndex:index];
            }
        }
        for (NSInteger index = (NSInteger)[_pendingEvents count] - 1; index >= 0; index--) {
            NSDictionary *event = [_pendingEvents objectAtIndex:index];
            if (VCIsOptionalAppDiagnosticEvent([event objectForKey:@"category"],
                                               [event objectForKey:@"action"])) {
                [_pendingEvents removeObjectAtIndex:index];
            }
        }
    }
    if (_writeQueue) {
        dispatch_async(_writeQueue, ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            VCPurgeOptionalDiagnosticEvents();
            [pool drain];
        });
    }
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
#if !OS_OBJECT_USE_OBJC
    if (_writeQueue) dispatch_release(_writeQueue);
#endif
    [_pendingEvents release];
    [_events release];
    [super dealloc];
}

@end

void VCRecordAppEvent(NSString *category, NSString *action, NSString *detail) {
    [[VCAppEventRecorder sharedRecorder] recordCategory:category action:action detail:detail];
}

static NSString *VCEventTimeText(NSDictionary *event) {
    long long milliseconds = [[event objectForKey:@"timestamp"] longLongValue];
    time_t seconds = (time_t)(milliseconds / 1000LL);
    struct tm local;
    memset(&local, 0, sizeof(local));
    if (!localtime_r(&seconds, &local)) return @"--:--:--";
    return [NSString stringWithFormat:@"%02d:%02d:%02d",
            local.tm_hour, local.tm_min, local.tm_sec];
}

static NSString *VCEventMessage(NSDictionary *event) {
    NSString *message = [event objectForKey:@"message"];
    if ([message isKindOfClass:[NSString class]] && [message length] > 0) {
        return VCSanitizeDiagnosticText(message, 192);
    }
    return VCSanitizeDiagnosticText([event objectForKey:@"action"], 96);
}

static NSString *VCEventMetadata(NSDictionary *event) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:VCEventTimeText(event)];
    NSString *source = [event objectForKey:@"source"];
    NSString *category = [event objectForKey:@"category"];
    if ([source isEqualToString:@"daemon"]) {
        [parts addObject:@"daemon"];
    } else if ([category length] > 0) {
        [parts addObject:category];
    } else if ([source length] > 0) {
        [parts addObject:source];
    }
    NSString *detail = VCSanitizeDiagnosticText([event objectForKey:@"detail"], 192);
    if ([detail length] > 0) [parts addObject:detail];
    return [parts componentsJoinedByString:@" · "];
}

@implementation DiagnosticEventsVC

- (id)initWithEvents:(NSArray *)events {
    self = [super init];
    if (self) _events = [events copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"All Events";
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc]
                                                initWithTitle:@"Clear"
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(clearPressed)] autorelease];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    UIBarButtonItem *clearButton = self.navigationItem.rightBarButtonItem;
    clearButton.tintColor = VCErrorColor();
    if ([[[UIDevice currentDevice] systemVersion] integerValue] < 7) {
        clearButton.style = UIBarButtonItemStyleDone;
    } else {
        [clearButton setTitleTextAttributes:
            [NSDictionary dictionaryWithObject:VCErrorColor()
                                        forKey:NSForegroundColorAttributeName]
                                  forState:UIControlStateNormal];
    }
    clearButton.enabled = [_events count] > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return MAX((NSInteger)1, (NSInteger)[_events count]);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [NSString stringWithFormat:@"Activity (%u)", (unsigned)[_events count]];
}

- (void)clearPressed {
    if ([_events count] == 0) return;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Clear Activity?"
                                                     message:@"Are you sure you want to delete all recorded diagnostic activity?"
                                                    delegate:self
                                           cancelButtonTitle:@"Cancel"
                                           otherButtonTitles:@"Clear", nil] autorelease];
    [alert show];
#pragma clang diagnostic pop
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) return;
#pragma clang diagnostic pop
    [[VCAppEventRecorder sharedRecorder] clearEvents];
    [_events release];
    _events = [[NSArray alloc] init];
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [_tableView reloadData];
    VCSendCommandAsync(@"CLEAR_EVENTS\n", ^(NSString *response) {
        (void)response;
        [[NSNotificationCenter defaultCenter]
            postNotificationName:kVCDiagnosticEventsClearedNotification
                          object:nil];
    });
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"DiagnosticEventListCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    if ([_events count] == 0) {
        cell.textLabel.text = @"No events recorded";
        cell.detailTextLabel.text = @"Actions will appear here as they happen";
    } else {
        NSDictionary *event = [_events objectAtIndex:[_events count] - 1 - indexPath.row];
        cell.textLabel.text = VCEventMessage(event);
        cell.detailTextLabel.text = VCEventMetadata(event);
    }
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.numberOfLines = 2;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    return 62.0f;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    VCAppearanceApplyCell(cell);
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate { return IsPadDevice(); }

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    [_tableView release];
    [_events release];
    [super dealloc];
}

@end

static NSString *VCMachineIdentifier(void) {
    struct utsname info;
    if (uname(&info) != 0 || info.machine[0] == '\0') return @"unknown";
    return [NSString stringWithUTF8String:info.machine];
}

static NSString *VCActiveNetworkDescription(void) {
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_len = sizeof(address);
    address.sin_family = AF_INET;

    SCNetworkReachabilityRef reachability =
        SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault,
                                                (const struct sockaddr *)&address);
    if (!reachability) return @"Unknown";

    SCNetworkReachabilityFlags flags = 0;
    BOOL valid = SCNetworkReachabilityGetFlags(reachability, &flags);
    CFRelease(reachability);
    if (!valid) return @"Unknown";

    BOOL reachable = (flags & kSCNetworkReachabilityFlagsReachable) != 0;
    BOOL needsConnection = (flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0;
    if (!reachable || needsConnection) return @"No active route";
#if TARGET_OS_IPHONE
    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
        return @"pdp_ip (Cellular)";
    }
#endif
    return @"en0 (Wi-Fi)";
}

static NSString *VCExternalIPThroughSOCKS(uint16_t socksPort) {
    int fd = connect_loopback_port(socksPort, 8000, nil);
    if (fd < 0) return nil;
    if (socks5_connect_domain(fd, "api.ipify.org", 80) != 0) {
        close(fd);
        return nil;
    }

    static const char request[] =
        "GET / HTTP/1.0\r\n"
        "Host: api.ipify.org\r\n"
        "User-Agent: vless-core-app-diagnostics\r\n"
        "Connection: close\r\n\r\n";
    if (write_all(fd, request, sizeof(request) - 1) != 0) {
        close(fd);
        return nil;
    }

    char response[8192];
    size_t used = 0;
    while (used + 1 < sizeof(response)) {
        ssize_t count = read(fd, response + used, sizeof(response) - used - 1);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        used += (size_t)count;
    }
    close(fd);
    response[used] = '\0';
    if (used < 12 || strncmp(response, "HTTP/", 5) != 0) return nil;

    char *status = strchr(response, ' ');
    if (!status || atoi(status + 1) < 200 || atoi(status + 1) >= 300) return nil;
    char *body = strstr(response, "\r\n\r\n");
    if (!body) return nil;
    body += 4;
    NSString *bodyText = [[[NSString alloc] initWithBytes:body
                                                   length:used - (size_t)(body - response)
                                                 encoding:NSUTF8StringEncoding] autorelease];
    return VCNormalizedIPAddress(bodyText);
}

static NSString *VCExternalIPThroughSystemHTTP(void) {
    BOOL usesATS = [[[UIDevice currentDevice] systemVersion] integerValue] >= 9;
    NSURL *url = [NSURL URLWithString:(usesATS
                                      ? @"https://api.ipify.org/"
                                      : @"http://api.ipify.org/")];
    if (!url) return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:10.0];
    [request setValue:@"vless-core-app-diagnostics" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSURLResponse *response = nil;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSURLConnection sendSynchronousRequest:request
                                         returningResponse:&response
                                                     error:&error];
#pragma clang diagnostic pop
    if (!data || error) return nil;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (status < 200 || status >= 300) return nil;
    }
    NSString *body = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    return VCNormalizedIPAddress(body);
}

static BOOL VCSystemHTTPProbe(void) {
    BOOL usesATS = [[[UIDevice currentDevice] systemVersion] integerValue] >= 9;
    NSURL *url = [NSURL URLWithString:(usesATS
                                      ? @"https://www.gstatic.com/generate_204"
                                      : @"http://www.gstatic.com/generate_204")];
    if (!url) return NO;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:8.0];
    [request setValue:@"vless-core-app-diagnostics" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"close" forHTTPHeaderField:@"Connection"];
    NSURLResponse *response = nil;
    NSError *error = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    (void)[NSURLConnection sendSynchronousRequest:request
                                returningResponse:&response
                                            error:&error];
#pragma clang diagnostic pop
    if (error || ![response isKindOfClass:[NSHTTPURLResponse class]]) return NO;
    NSInteger status = [(NSHTTPURLResponse *)response statusCode];
    return status >= 200 && status < 400;
}

typedef struct {
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    int finished;
    int result;
    int waiter_timed_out;
} VCDNSCheckContext;

static void *VCDNSCheckWorker(void *opaque) {
    VCDNSCheckContext *context = (VCDNSCheckContext *)opaque;
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo *result = NULL;
    int rc = getaddrinfo("api.ipify.org", "80", &hints, &result);
    if (result) freeaddrinfo(result);

    pthread_mutex_lock(&context->mutex);
    context->result = rc == 0;
    context->finished = 1;
    int timedOut = context->waiter_timed_out;
    if (!timedOut) pthread_cond_signal(&context->condition);
    pthread_mutex_unlock(&context->mutex);

    if (timedOut) {
        pthread_cond_destroy(&context->condition);
        pthread_mutex_destroy(&context->mutex);
        free(context);
    }
    return NULL;
}

static BOOL VCDNSCheck(void) {
    VCDNSCheckContext *context = calloc(1, sizeof(*context));
    if (!context) return NO;
    if (pthread_mutex_init(&context->mutex, NULL) != 0) {
        free(context);
        return NO;
    }
    if (pthread_cond_init(&context->condition, NULL) != 0) {
        pthread_mutex_destroy(&context->mutex);
        free(context);
        return NO;
    }

    pthread_t thread;
    if (pthread_create(&thread, NULL, VCDNSCheckWorker, context) != 0) {
        pthread_cond_destroy(&context->condition);
        pthread_mutex_destroy(&context->mutex);
        free(context);
        return NO;
    }

    struct timeval now;
    gettimeofday(&now, NULL);
    struct timespec deadline;
    deadline.tv_sec = now.tv_sec + 8;
    deadline.tv_nsec = (long)now.tv_usec * 1000L;

    pthread_mutex_lock(&context->mutex);
    int waitRC = 0;
    while (!context->finished && waitRC == 0) {
        waitRC = pthread_cond_timedwait(&context->condition, &context->mutex, &deadline);
    }
    if (!context->finished) {
        context->waiter_timed_out = 1;
        pthread_mutex_unlock(&context->mutex);
        (void)pthread_detach(thread);
        return NO;
    }
    BOOL success = context->result != 0;
    pthread_mutex_unlock(&context->mutex);
    (void)pthread_join(thread, NULL);
    pthread_cond_destroy(&context->condition);
    pthread_mutex_destroy(&context->mutex);
    free(context);
    return success;
}

static NSDictionary *VCRunConnectionQualityChecks(NSDictionary *daemonState) {
    NSMutableDictionary *quality = [NSMutableDictionary dictionary];
    BOOL connected = [[daemonState objectForKey:@"connected"] boolValue];
    NSInteger socksPort = [[daemonState objectForKey:@"socks_port"] integerValue];
    if (!connected || socksPort <= 0 || socksPort > 65535) {
        [quality setObject:@"VPN disconnected" forKey:@"server"];
        [quality setObject:@"Not running" forKey:@"core"];
        [quality setObject:@"Not checked" forKey:@"dns"];
        [quality setObject:@"Not checked" forKey:@"http"];
        [quality setObject:@"Not checked" forKey:@"webkit"];
        [quality setObject:@"Not checked" forKey:@"leak"];
        [quality setObject:@"VPN disconnected" forKey:@"internet"];
        return quality;
    }

    BOOL helperRunning = [[daemonState objectForKey:@"core"] isEqualToString:@"running"];
    BOOL listenerReady = ConnectLatencyMs("127.0.0.1", (uint16_t)socksPort, 1500,
                                         NULL, nil) == 0;
    [quality setObject:(helperRunning && listenerReady ? @"Running and listening" : @"Unavailable")
                 forKey:@"core"];

    BOOL dnsWorks = VCDNSCheck();
    [quality setObject:(dnsWorks ? @"Resolved successfully" : @"Resolution failed")
                 forKey:@"dns"];

    int proxyLatency = 0;
    BOOL proxyHTTP = helperRunning && listenerReady &&
        ProxyGetConnectOnceMs((uint16_t)socksPort, 8000, &proxyLatency, nil) == 0;
    NSString *proxyIP = proxyHTTP ? VCExternalIPThroughSOCKS((uint16_t)socksPort) : nil;
    [quality setObject:(proxyHTTP ? @"Reachable through tunnel" : @"Tunnel request failed")
                 forKey:@"server"];
    [quality setObject:(proxyHTTP
                        ? [NSString stringWithFormat:@"Passed (%d ms)", proxyLatency]
                        : @"Failed")
                 forKey:@"http"];

    BOOL systemWorks = VCSystemHTTPProbe();
    NSString *systemIP = systemWorks ? VCExternalIPThroughSystemHTTP() : nil;
    BOOL exitsMatch = proxyIP && systemIP && [proxyIP isEqualToString:systemIP];
    if (exitsMatch) {
        [quality setObject:@"Routed through VPN" forKey:@"webkit"];
        [quality setObject:@"Not detected" forKey:@"leak"];
    } else if (proxyIP && systemIP) {
        [quality setObject:@"Different network exit" forKey:@"webkit"];
        [quality setObject:@"Detected" forKey:@"leak"];
    } else {
        [quality setObject:(systemWorks ? @"HTTP works; exit not verified" : @"Request failed")
                     forKey:@"webkit"];
        [quality setObject:@"Not checked" forKey:@"leak"];
    }

    if (dnsWorks && proxyHTTP && systemWorks && exitsMatch) {
        [quality setObject:@"Working through VPN" forKey:@"internet"];
    } else if (dnsWorks && proxyHTTP && systemWorks && proxyIP && systemIP) {
        [quality setObject:@"Working with a traffic leak" forKey:@"internet"];
    } else if (dnsWorks && proxyHTTP && systemWorks) {
        [quality setObject:@"Working; exit not verified" forKey:@"internet"];
    } else if (proxyHTTP || systemWorks) {
        [quality setObject:@"Partially working" forKey:@"internet"];
    } else {
        [quality setObject:@"Unavailable" forKey:@"internet"];
    }
    return quality;
}

static NSString *VCDiagnosticValue(NSDictionary *dictionary,
                                   NSString *key,
                                   NSString *fallback) {
    NSString *value = [dictionary objectForKey:key];
    return [value isKindOfClass:[NSString class]] && [value length] > 0 ? value : fallback;
}

@implementation DebugVC

- (void)stopRefreshTimer {
    [_refreshTimer invalidate];
    [_refreshTimer release];
    _refreshTimer = nil;
}

- (void)startRefreshTimer {
    if (_refreshTimer) return;
    [self refreshDiagnostics];
    _refreshTimer = [[NSTimer scheduledTimerWithTimeInterval:2.0
                                                      target:self
                                                    selector:@selector(refreshDiagnostics)
                                                    userInfo:nil
                                                     repeats:YES] retain];
}

- (void)applicationEnteredBackground:(NSNotification *)notification {
    (void)notification;
    [self stopRefreshTimer];
}

- (void)applicationBecameActive:(NSNotification *)notification {
    (void)notification;
    if (self.view.window) [self startRefreshTimer];
}

- (NSArray *)combinedEvents {
    if (_displayEvents) return _displayEvents;
    _displayEvents = [VCCombinedDiagnosticEvents(_daemonEvents, _appEvents, _localEvents) copy];
    return _displayEvents;
}

- (void)diagnosticEventsCleared:(NSNotification *)notification {
    (void)notification;
    [_daemonEvents release];
    _daemonEvents = [[NSArray alloc] init];
    [_appEvents release];
    _appEvents = [[NSArray alloc] init];
    [_localEvents removeAllObjects];
    [_displayEvents release];
    _displayEvents = nil;
    [_tableView reloadData];
}

- (void)addLocalEvent:(NSString *)message {
    if (![message isKindOfClass:[NSString class]] || [message length] == 0) return;
    NSDictionary *last = [_localEvents lastObject];
    if ([[last objectForKey:@"message"] isEqualToString:message]) return;
    NSTimeInterval seconds = [[NSDate date] timeIntervalSince1970];
    [_localEvents addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithLongLong:(long long)(seconds * 1000.0)], @"timestamp",
                             @"debug", @"source",
                             message, @"message",
                             nil]];
    if ([_localEvents count] > 32) [_localEvents removeObjectAtIndex:0];
    [_displayEvents release];
    _displayEvents = nil;
}

- (void)applyTheme {
    self.view.backgroundColor = VCBackgroundColor();
    VCAppearanceApplyNavigationBar(self.navigationController.navigationBar);
    VCAppearanceApplyStatusBar();
    VCAppearanceApplyTable(_tableView);
    _appActivitySwitch.onTintColor = VCAccentColor();
    [_tableView reloadData];
    VCAppearanceScheduleVisibleTableHeadersRefresh(_tableView);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Debug";
    _localEvents = [[NSMutableArray alloc] init];
    VCRecordAppEvent(@"ui", @"Debug screen opened", nil);
    _appEvents = [[[VCAppEventRecorder sharedRecorder] eventsSnapshot] copy];
    _appActivitySwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    [_appActivitySwitch setOn:VCAppActivityLoggingEnabled() animated:NO];
    [_appActivitySwitch addTarget:self
                           action:@selector(appActivitySwitchChanged:)
                 forControlEvents:UIControlEventValueChanged];
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_tableView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationEnteredBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationBecameActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(diagnosticEventsCleared:)
                                                 name:kVCDiagnosticEventsClearedNotification
                                               object:nil];
    [self applyTheme];
}

- (void)appActivitySwitchChanged:(UISwitch *)sender {
    BOOL enabled = [sender isOn];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enabled forKey:kDefaultsDiagnosticAppActivityKey];
    [defaults synchronize];
    [[VCAppEventRecorder sharedRecorder] setAppActivityEnabled:enabled];
    VCRecordAppEvent(@"diagnostics", @"App activity logging changed",
                     enabled ? @"enabled=1" : @"enabled=0");
    [_appEvents release];
    _appEvents = [[[VCAppEventRecorder sharedRecorder] eventsSnapshot] copy];
    [_displayEvents release];
    _displayEvents = nil;
    [_tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self startRefreshTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopRefreshTimer];
}

- (void)refreshDiagnostics {
    if (_refreshing) return;
    _refreshing = YES;
    [NSThread detachNewThreadSelector:@selector(diagnosticsWorker) toTarget:self withObject:nil];
}

- (void)diagnosticsWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = VCParseDaemonDiagnostics(SendCommand(@"DIAGNOSTICS\n"));
    NSArray *events = VCParseDaemonEvents(SendCommand(@"EVENTS\n"));
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             state, @"state",
                             events, @"events",
                             nil];
    [self performSelectorOnMainThread:@selector(diagnosticsFinished:)
                           withObject:payload
                        waitUntilDone:NO];
    [pool drain];
}

- (void)diagnosticsFinished:(NSDictionary *)payload {
    _refreshing = NO;
    NSDictionary *newState = [payload objectForKey:@"state"];
    NSArray *newEvents = [payload objectForKey:@"events"];
    NSArray *newAppEvents = [[VCAppEventRecorder sharedRecorder] eventsSnapshot];
    BOOL hadDaemonState = _daemonState != nil;
    BOOL stateChanged = ![_daemonState isEqual:newState];
    BOOL eventsChanged = ![_daemonEvents isEqual:newEvents];
    BOOL appEventsChanged = ![_appEvents isEqual:newAppEvents];
    [_daemonState release];
    _daemonState = [newState copy];
    [_daemonEvents release];
    _daemonEvents = [newEvents copy];
    [_appEvents release];
    _appEvents = [newAppEvents copy];
    if (eventsChanged || appEventsChanged) {
        [_displayEvents release];
        _displayEvents = nil;
    }

    NSString *network = VCActiveNetworkDescription();
    BOOL networkChanged = !_lastNetwork || ![_lastNetwork isEqualToString:network];
    BOOL hadNetworkState = _lastNetwork != nil;
    if (networkChanged) {
        BOOL changedNetwork = _lastNetwork != nil;
        if (_lastNetwork && ![_lastNetwork isEqualToString:@"No active route"] &&
            ![_lastNetwork isEqualToString:@"Unknown"]) {
            NSString *oldName = [_lastNetwork rangeOfString:@"Cellular"].location != NSNotFound
                ? @"Cellular network"
                : @"Wi-Fi";
            [self addLocalEvent:[NSString stringWithFormat:@"%@ disconnected", oldName]];
        }
        if (![network isEqualToString:@"No active route"] && ![network isEqualToString:@"Unknown"]) {
            [self addLocalEvent:[NSString stringWithFormat:@"%@ active", network]];
        } else if ([network isEqualToString:@"No active route"]) {
            [self addLocalEvent:@"No active network route"];
        }
        [_lastNetwork release];
        _lastNetwork = [network copy];
        if (changedNetwork && [[_daemonState objectForKey:@"connected"] boolValue]) {
            if ([[_daemonState objectForKey:@"pf_routing"] isEqualToString:@"active"]) {
                [self addLocalEvent:@"PF routing verified after network change"];
            }
            if ([[_daemonState objectForKey:@"pac"] isEqualToString:@"active"]) {
                [self addLocalEvent:@"PAC verified after network change"];
            }
        }
    }

    if ((hadDaemonState && stateChanged) || (hadNetworkState && networkChanged)) {
        _qualityGeneration++;
        [_qualityState release];
        _qualityState = nil;
    }

    if (stateChanged || eventsChanged || appEventsChanged || networkChanged) [_tableView reloadData];
    if (!_qualityState && !_checking && [[_daemonState objectForKey:@"connected"] boolValue]) {
        [self runQualityCheck];
    }
}

- (void)runQualityCheck {
    if (_checking || _reporting) return;
    if (!_daemonState || [_daemonState objectForKey:@"error"] ||
        ![[_daemonState objectForKey:@"connected"] boolValue]) {
        BOOL loading = _daemonState == nil;
        BOOL unavailable = [_daemonState objectForKey:@"error"] != nil;
        VCRecordAppEvent(@"diagnostics", @"Connection check blocked",
                         loading ? @"reason=status_loading" :
                         (unavailable ? @"reason=daemon_unavailable" : @"reason=vpn_disconnected"));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc]
                               initWithTitle:(loading ? @"Please Wait" :
                                              (unavailable ? @"Status Unavailable" : @"VPN Is Disconnected"))
                               message:(loading
                                        ? @"Connection status is still loading. Try again in a moment."
                                        : (unavailable
                                           ? @"The VPN daemon status could not be read."
                                           : @"Connect to a configuration before running the connection check."))
                               delegate:nil
                               cancelButtonTitle:@"OK"
                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
        return;
    }
    VCRecordAppEvent(@"diagnostics", @"Connection check started", nil);
    _checking = YES;
    [_tableView reloadData];
    NSDictionary *input = [NSDictionary dictionaryWithObjectsAndKeys:
                           (_daemonState ? _daemonState : [NSDictionary dictionary]), @"state",
                           [NSNumber numberWithUnsignedInteger:_qualityGeneration], @"generation",
                           nil];
    [NSThread detachNewThreadSelector:@selector(qualityWorker:) toTarget:self withObject:input];
}

- (void)qualityWorker:(NSDictionary *)input {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = [input objectForKey:@"state"];
    NSDictionary *quality = VCRunConnectionQualityChecks(state);
    NSDictionary *output = [NSDictionary dictionaryWithObjectsAndKeys:
                            quality, @"quality",
                            [input objectForKey:@"generation"], @"generation",
                            nil];
    [self performSelectorOnMainThread:@selector(qualityFinished:)
                           withObject:output
                        waitUntilDone:NO];
    [pool drain];
}

- (void)qualityFinished:(NSDictionary *)output {
    _checking = NO;
    if ([[output objectForKey:@"generation"] unsignedIntegerValue] != _qualityGeneration) {
        if ([[_daemonState objectForKey:@"connected"] boolValue]) {
            [self runQualityCheck];
        } else {
            [_tableView reloadData];
        }
        return;
    }
    NSDictionary *quality = [output objectForKey:@"quality"];
    [_qualityState release];
    _qualityState = [quality copy];
    NSString *leak = [_qualityState objectForKey:@"leak"];
    if ([leak isEqualToString:@"Detected"]) {
        [self addLocalEvent:@"Traffic leak detected: system and tunnel exits differ"];
    } else if ([leak isEqualToString:@"Not detected"]) {
        [self addLocalEvent:@"External IP confirmed through VPN"];
    } else if ([[[_qualityState objectForKey:@"internet"] lowercaseString] hasPrefix:@"working"]) {
        [self addLocalEvent:@"Connection works; external IP comparison unavailable"];
    } else {
        [self addLocalEvent:@"Connection quality check could not be completed"];
    }
    VCRecordAppEvent(@"diagnostics", @"Connection check finished",
                     [NSString stringWithFormat:@"core=%@ dns=%@ proxy=%@ webkit=%@ leak=%@ internet=%@",
                      VCDiagnosticValue(_qualityState, @"core", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"dns", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"http", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"webkit", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"leak", @"unknown"),
                      VCDiagnosticValue(_qualityState, @"internet", @"unknown")]);
    [_tableView reloadData];
}

- (NSString *)buildReportWithState:(NSDictionary *)state
                            quality:(NSDictionary *)quality
                             events:(NSArray *)events {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss ZZZZ";
    NSMutableString *report = [NSMutableString string];
    [report appendString:@"vless-core diagnostic report\n"];
    [report appendFormat:@"Generated: %@\n\n", [formatter stringFromDate:[NSDate date]]];
    [report appendString:@"Privacy: configuration URIs, subscription URLs, server addresses, external IP addresses, UUIDs, credentials and keys are omitted.\n\n"];
    [report appendString:@"Application\n-----------\n"];
    [report appendFormat:@"Version: %@ (%@)\n", AppShortVersion(), AppBuildVersion()];
    [report appendFormat:@"Device: %@ (%@)\n", DeviceModelName(), VCMachineIdentifier()];
    [report appendFormat:@"iOS: %@\n", [[UIDevice currentDevice] systemVersion]];
#if defined(__LP64__)
    [report appendString:@"Application architecture: arm64\n"];
#else
    [report appendString:@"Application architecture: armv7\n"];
#endif
    [report appendFormat:@"App activity logging: %@\n",
     VCAppActivityLoggingEnabled() ? @"enabled" : @"disabled"];
    NSString *daemonControlError = [state objectForKey:@"error"];
    if ([daemonControlError isKindOfClass:[NSString class]] && [daemonControlError length] > 0) {
        [report appendFormat:@"Daemon control: %@\n",
         VCSanitizeDiagnosticText(daemonControlError, 192)];
    } else {
        [report appendString:@"Daemon control: online\n"];
    }
    [report appendFormat:@"Daemon architecture: %@\n", VCDiagnosticValue(state, @"architecture", @"unknown")];
    [report appendFormat:@"Active network: %@\n\n", VCActiveNetworkDescription()];

    [report appendString:@"Routing and helpers\n-------------------\n"];
    [report appendFormat:@"Connection: %@\n", [[state objectForKey:@"connected"] boolValue] ? @"connected" : @"disconnected"];
    [report appendFormat:@"Mode: %@\n", VCDiagnosticValue(state, @"mode", @"unknown")];
    [report appendFormat:@"PF engine: %@\n", VCDiagnosticValue(state, @"pf", @"unknown")];
    [report appendFormat:@"PF routing: %@\n", VCDiagnosticValue(state, @"pf_routing", @"unknown")];
    [report appendFormat:@"PAC: %@\n", VCDiagnosticValue(state, @"pac", @"unknown")];
    [report appendFormat:@"Core helper: %@\n", VCDiagnosticValue(state, @"core", @"unknown")];
    [report appendFormat:@"Traffic redirector: %@\n", VCDiagnosticValue(state, @"redsocks", @"unknown")];
    [report appendFormat:@"DNS helper: %@\n\n", VCDiagnosticValue(state, @"dns", @"unknown")];

    [report appendString:@"Connection quality\n------------------\n"];
    NSArray *qualityRows = [NSArray arrayWithObjects:
                            [NSArray arrayWithObjects:@"Server path", @"server", nil],
                            [NSArray arrayWithObjects:@"Core", @"core", nil],
                            [NSArray arrayWithObjects:@"DNS", @"dns", nil],
                            [NSArray arrayWithObjects:@"HTTP through proxy", @"http", nil],
                            [NSArray arrayWithObjects:@"Safari/WebKit path", @"webkit", nil],
                            [NSArray arrayWithObjects:@"Traffic leak", @"leak", nil],
                            [NSArray arrayWithObjects:@"Internet", @"internet", nil],
                            nil];
    for (NSArray *row in qualityRows) {
        [report appendFormat:@"%@: %@\n",
         [row objectAtIndex:0],
         VCDiagnosticValue(quality, [row objectAtIndex:1], @"not checked")];
    }

    [report appendString:@"\nPrivacy-safe activity history\n-----------------------------\n"];
    if ([events count] == 0) {
        [report appendString:@"No events recorded.\n"];
    } else {
        for (NSDictionary *event in events) {
            [report appendFormat:@"%@ — %@\n",
             VCEventMetadata(event),
             VCEventMessage(event)];
        }
    }
    return report;
}

- (void)createReport {
    if (_reporting || _checking) return;
    VCRecordAppEvent(@"diagnostics", @"Diagnostic report requested", nil);
    _reporting = YES;
    [_tableView reloadSections:[NSIndexSet indexSetWithIndex:VCDebugSectionDiagnostics]
              withRowAnimation:UITableViewRowAnimationNone];
    [NSThread detachNewThreadSelector:@selector(reportWorker) toTarget:self withObject:nil];
}

- (void)reportWorker {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSDictionary *state = VCParseDaemonDiagnostics(SendCommand(@"DIAGNOSTICS\n"));
    NSArray *events = VCParseDaemonEvents(SendCommand(@"EVENTS\n"));
    NSDictionary *quality = VCRunConnectionQualityChecks(state);
    NSArray *appEvents = [[VCAppEventRecorder sharedRecorder] eventsSnapshot];
    NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
                             state, @"state",
                             events, @"events",
                             quality, @"quality",
                             appEvents, @"app_events",
                             nil];
    [self performSelectorOnMainThread:@selector(reportFinished:)
                           withObject:payload
                        waitUntilDone:NO];
    [pool drain];
}

- (void)reportFinished:(NSDictionary *)payload {
    _reporting = NO;
    NSDictionary *reportState = [payload objectForKey:@"state"];
    NSDictionary *reportQuality = [payload objectForKey:@"quality"];
    NSArray *events = VCCombinedDiagnosticEvents([payload objectForKey:@"events"],
                                                  [payload objectForKey:@"app_events"],
                                                  _localEvents);
    NSString *report = [self buildReportWithState:reportState
                                          quality:reportQuality
                                           events:events];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      @"vless-core-diagnostics.txt"];
    NSError *error = nil;
    BOOL written = [report writeToFile:path
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:&error];
    if (!written) {
        VCRecordAppEvent(@"diagnostics", @"Diagnostic report failed", @"stage=file_write");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Report Failed"
                                                         message:(error ? [error localizedDescription] : @"Unable to write the report.")
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
        [_tableView reloadData];
        return;
    }
    (void)chmod([path fileSystemRepresentation], 0600);
    VCRecordAppEvent(@"diagnostics", @"Diagnostic report created",
                     [NSString stringWithFormat:@"events=%lu bytes=%lu",
                      (unsigned long)[events count],
                      (unsigned long)[report lengthOfBytesUsingEncoding:NSUTF8StringEncoding]]);

    [_documentController release];
    _documentController = [[UIDocumentInteractionController interactionControllerWithURL:
                            [NSURL fileURLWithPath:path]] retain];
    _documentController.delegate = self;
    _documentController.name = @"vless-core diagnostics";
    CGRect anchor = CGRectMake(CGRectGetMidX(self.view.bounds),
                               CGRectGetMidY(self.view.bounds),
                               1.0f,
                               1.0f);
    if (![_documentController presentOptionsMenuFromRect:anchor
                                                  inView:self.view
                                                animated:YES]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        UIAlertView *alert = [[[UIAlertView alloc] initWithTitle:@"Report Ready"
                                                         message:path
                                                        delegate:nil
                                               cancelButtonTitle:@"OK"
                                               otherButtonTitles:nil] autorelease];
        [alert show];
#pragma clang diagnostic pop
    }
    [_tableView reloadData];
}

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    (void)controller;
    return self;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return VCDebugSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionLiveState) return 6;
    if (section == VCDebugSectionConnectionQuality) return 7;
    if (section == VCDebugSectionActivityLogging) return 1;
    if (section == VCDebugSectionRecentActivity) {
        NSInteger count = (NSInteger)[[self combinedEvents] count];
        return count == 0 ? 1 : MIN((NSInteger)5, count) + 1;
    }
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionLiveState) return @"Live state";
    if (section == VCDebugSectionConnectionQuality) return @"Connection quality";
    if (section == VCDebugSectionActivityLogging) return @"Activity logging";
    if (section == VCDebugSectionRecentActivity) return @"Recent activity";
    return @"Diagnostics";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionActivityLogging) {
        return @"Off by default. Connection, network diagnostics, ping and subscription update events are always recorded.";
    }
    if (section == VCDebugSectionRecentActivity) {
        return @"Up to 250 recent events are kept only on this device. URLs, IP addresses, UUIDs, names and secrets are omitted. Nothing is sent automatically.";
    }
    return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    (void)tableView;
    if (section == VCDebugSectionActivityLogging) return 64.0f;
    if (section == VCDebugSectionRecentActivity) return 82.0f;
    return 18.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if (section != VCDebugSectionActivityLogging &&
        section != VCDebugSectionRecentActivity) return nil;
    CGFloat height = [self tableView:tableView heightForFooterInSection:section];
    UIView *footer = [[[UIView alloc] initWithFrame:
                       CGRectMake(0.0f, 0.0f, tableView.bounds.size.width, height)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    UILabel *label = [[[UILabel alloc] initWithFrame:
                       CGRectMake(18.0f, 3.0f, tableView.bounds.size.width - 36.0f, height - 6.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont systemFontOfSize:13.0f];
    label.numberOfLines = 0;
    label.lineBreakMode = NSLineBreakByWordWrapping;
    label.text = [self tableView:tableView titleForFooterInSection:section];
    [footer addSubview:label];
    VCAppearanceApplyHeaderView(footer);
    return footer;
}

- (NSString *)qualityValueForRow:(NSInteger)row {
    if (_checking) return @"Checking...";
    NSArray *keys = [NSArray arrayWithObjects:@"server", @"core", @"dns", @"http", @"webkit", @"leak", @"internet", nil];
    return VCDiagnosticValue(_qualityState, [keys objectAtIndex:row], @"Not checked");
}

- (UIColor *)colorForStatus:(NSString *)status {
    NSString *lower = [status lowercaseString];
    if ([lower rangeOfString:@"leak"].location != NSNotFound &&
        [lower rangeOfString:@"not detected"].location == NSNotFound) {
        return VCErrorColor();
    }
    if ([lower hasPrefix:@"not detected"] ||
        [lower hasPrefix:@"active"] ||
        [lower hasPrefix:@"enabled"] ||
        [lower hasPrefix:@"connected"] ||
        [lower hasPrefix:@"running"] ||
        [lower hasPrefix:@"reachable"] ||
        [lower hasPrefix:@"resolved"] ||
        [lower hasPrefix:@"passed"] ||
        [lower hasPrefix:@"routed"] ||
        [lower hasPrefix:@"working"]) {
        return VCSuccessColor();
    }
    if ([lower hasPrefix:@"error"] ||
        [lower hasPrefix:@"missing"] ||
        [lower hasPrefix:@"unavailable"] ||
        [lower hasPrefix:@"failed"] ||
        [lower hasPrefix:@"tunnel request failed"] ||
        [lower hasPrefix:@"resolution failed"] ||
        [lower hasPrefix:@"different"] ||
        [lower isEqualToString:@"detected"]) {
        return VCErrorColor();
    }
    return VCSecondaryTextColor();
}

- (UITableViewCell *)statusCellInTable:(UITableView *)tableView
                                 title:(NSString *)title
                                detail:(NSString *)detail {
    static NSString *identifier = @"DebugStatusCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = [self colorForStatus:detail];
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == VCDebugSectionLiveState) {
        NSString *title = nil;
        NSString *detail = nil;
        NSString *error = [_daemonState objectForKey:@"error"];
        if (indexPath.row == 0) {
            title = @"Daemon control";
            detail = !_daemonState ? @"Loading..." : (error ? error : @"Online");
        } else if (indexPath.row == 1) {
            title = @"VPN connection";
            detail = error ? @"Unavailable" : ([[_daemonState objectForKey:@"connected"] boolValue] ? @"Connected" : @"Disconnected");
        } else if (indexPath.row == 2) {
            title = @"Active network";
            detail = _lastNetwork ? _lastNetwork : VCActiveNetworkDescription();
        } else if (indexPath.row == 3) {
            title = @"PF routing";
            detail = error ? @"Unavailable" : [NSString stringWithFormat:@"%@ (engine: %@)",
                                                VCDiagnosticValue(_daemonState, @"pf_routing", @"unknown"),
                                                VCDiagnosticValue(_daemonState, @"pf", @"unknown")];
        } else if (indexPath.row == 4) {
            title = @"PAC for Safari/WebKit";
            NSString *pac = VCDiagnosticValue(_daemonState, @"pac", @"unknown");
            detail = error ? @"Unavailable" : ([pac isEqualToString:@"not_required"] ? @"Not required on armv7" : [pac capitalizedString]);
        } else {
            title = @"Helper processes";
            if (error) {
                detail = @"Unavailable";
            } else {
                NSString *core = VCDiagnosticValue(_daemonState, @"core", @"unknown");
                NSString *redirector = VCDiagnosticValue(_daemonState, @"redsocks", @"unknown");
                NSString *dns = VCDiagnosticValue(_daemonState, @"dns", @"unknown");
                detail = [core isEqualToString:@"running"] &&
                         [redirector isEqualToString:@"running"] &&
                         [dns isEqualToString:@"running"]
                    ? @"All running"
                    : [NSString stringWithFormat:@"core %@ · redirector %@ · DNS %@",
                       core, redirector, dns];
            }
        }
        return [self statusCellInTable:tableView title:title detail:detail];
    }

    if (indexPath.section == VCDebugSectionConnectionQuality) {
        NSArray *titles = [NSArray arrayWithObjects:
                           @"Server path", @"Core listener", @"DNS", @"HTTP through proxy",
                           @"Safari/WebKit path", @"Traffic leak", @"Internet", nil];
        return [self statusCellInTable:tableView
                                 title:[titles objectAtIndex:indexPath.row]
                                detail:[self qualityValueForRow:indexPath.row]];
    }

    if (indexPath.section == VCDebugSectionActivityLogging) {
        static NSString *identifier = @"DebugAppActivityCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:identifier] autorelease];
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = _appActivitySwitch;
        cell.textLabel.text = @"Record app activity";
        cell.detailTextLabel.text = @"UI, imports, settings and storage";
        VCAppearanceApplyCell(cell);
        cell.textLabel.textColor = VCPrimaryTextColor();
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSArray *events = [self combinedEvents];
        NSInteger recentCount = MIN((NSInteger)5, (NSInteger)[events count]);
        BOOL viewAllRow = [events count] > 0 && indexPath.row == recentCount;
        static NSString *identifier = @"DebugEventCell";
        static NSString *viewAllIdentifier = @"DebugViewAllEventsCell";
        NSString *reuseIdentifier = viewAllRow ? viewAllIdentifier : identifier;
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!cell) {
            cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                          reuseIdentifier:reuseIdentifier] autorelease];
        }
        if (viewAllRow) {
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            cell.textLabel.text = @"View all events";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%u recorded", (unsigned)[events count]];
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = VCCreateDisclosureAccessoryView();
            cell.textLabel.numberOfLines = 1;
            cell.detailTextLabel.numberOfLines = 1;
        } else if ([events count] == 0) {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = nil;
            cell.textLabel.text = @"No events recorded";
            cell.detailTextLabel.text = @"Privacy-safe user and system actions will appear here";
            cell.textLabel.numberOfLines = 2;
            cell.detailTextLabel.numberOfLines = 2;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.accessoryView = nil;
            NSDictionary *event = [events objectAtIndex:[events count] - 1 - indexPath.row];
            cell.textLabel.text = VCEventMessage(event);
            cell.detailTextLabel.text = VCEventMetadata(event);
            cell.textLabel.numberOfLines = 2;
            cell.detailTextLabel.numberOfLines = 2;
        }
        VCAppearanceApplyCell(cell);
        cell.textLabel.textColor = VCPrimaryTextColor();
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
        return cell;
    }

    static NSString *identifier = @"DebugActionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                      reuseIdentifier:identifier] autorelease];
    }
    BOOL operationInProgress = _checking || _reporting;
    BOOL currentOperation = indexPath.row == 0 ? _checking : _reporting;
    cell.selectionStyle = operationInProgress
        ? UITableViewCellSelectionStyleNone
        : UITableViewCellSelectionStyleBlue;
    cell.textLabel.text = indexPath.row == 0 ? @"Run connection check" : @"Create diagnostic report";
    cell.detailTextLabel.text = indexPath.row == 0
        ? @"Test DNS, proxy HTTP and the Safari/WebKit path"
        : @"Export one privacy-safe text file";
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (currentOperation) {
        UIActivityIndicatorViewStyle style = VCAppearanceIsDark()
            ? UIActivityIndicatorViewStyleWhite
            : UIActivityIndicatorViewStyleGray;
        UIActivityIndicatorView *spinner = [[[UIActivityIndicatorView alloc]
                                             initWithActivityIndicatorStyle:style] autorelease];
        [spinner startAnimating];
        cell.accessoryView = spinner;
    } else if (operationInProgress) {
        cell.accessoryView = nil;
    } else {
        cell.accessoryView = VCCreateDisclosureAccessoryView();
    }
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    cell.detailTextLabel.textColor = VCSecondaryTextColor();
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSArray *events = [self combinedEvents];
        NSInteger recentCount = MIN((NSInteger)5, (NSInteger)[events count]);
        if ([events count] > 0 && indexPath.row == recentCount) {
            VCRecordAppEvent(@"ui", @"Full diagnostic event history opened", nil);
            DiagnosticEventsVC *controller = [[[DiagnosticEventsVC alloc] initWithEvents:events] autorelease];
            [self.navigationController pushViewController:controller animated:YES];
        }
        return;
    }
    if (indexPath.section != VCDebugSectionDiagnostics) return;
    if (indexPath.row == 0) [self runQualityCheck];
    else [self createReport];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.section == VCDebugSectionRecentActivity) {
        NSInteger eventCount = (NSInteger)[[self combinedEvents] count];
        NSInteger recentCount = MIN((NSInteger)5, eventCount);
        BOOL viewAllRow = eventCount > 0 && indexPath.row == recentCount;
        return viewAllRow ? 48.0f : 62.0f;
    }
    return 48.0f;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    VCAppearanceApplyCell(cell);
    cell.textLabel.textColor = VCPrimaryTextColor();
    if (indexPath.section == VCDebugSectionLiveState ||
        indexPath.section == VCDebugSectionConnectionQuality) {
        cell.detailTextLabel.textColor = [self colorForStatus:cell.detailTextLabel.text];
    } else {
        cell.detailTextLabel.textColor = VCSecondaryTextColor();
    }
}

- (void)tableView:(UITableView *)tableView willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
    VCAppearanceScheduleVisibleTableHeadersRefresh(tableView);
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    VCAppearanceApplyHeaderView(view);
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return IsPadDevice() ? (UIInterfaceOrientationIsPortrait(interfaceOrientation) ||
                            UIInterfaceOrientationIsLandscape(interfaceOrientation))
                         : interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return IsPadDevice() ? UIInterfaceOrientationMaskAllButUpsideDown
                         : UIInterfaceOrientationMaskPortrait;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self stopRefreshTimer];
    _documentController.delegate = nil;
    [_documentController release];
    [_appActivitySwitch release];
    [_tableView release];
    [_daemonState release];
    [_daemonEvents release];
    [_appEvents release];
    [_localEvents release];
    [_displayEvents release];
    [_qualityState release];
    [_lastNetwork release];
    [super dealloc];
}

@end
