#import "help_controllers.h"

@implementation FAQVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)question:(NSString *)question answer:(NSString *)answer {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            question ? question : @"", @"question",
            answer ? answer : @"", @"answer",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title questions:(NSArray *)questions {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            questions ? questions : [NSArray array], @"questions",
            nil];
}

- (void)buildSections {
    NSArray *gettingStarted = [NSArray arrayWithObjects:
        [self question:@"How do I import?"
                 answer:@"Tap + and choose Import from Clipboard, Import from File, Scan QR Code, or Manual Input. Supported configuration schemes are vless://, trojan://, vmess://, ss://, and socks5://. You can also import HTTP/HTTPS subscriptions, HAPP and INCY links, and Karing backup ZIP files or LAN Send QR codes."],
        [self question:@"How do I connect?"
                 answer:@"Select a configuration, either standalone or inside a subscription, then tap Connect. Tap Disconnect to stop it. A red protocol label means the configuration contains an unsupported setting. The core checks the selected configuration before the daemon changes the network."],
        [self question:@"How do I delete or reorder items?"
                 answer:@"Swipe a standalone configuration or subscription from right to left to delete it. To reorder the items, press and hold the button for the currently selected list (Configurations or Subscriptions), drag the rows, and then press and hold the same button again."],
        [self question:@"Is a respring needed?"
                 answer:@"Normally, no. Wait for the icon-cache update and the Installation done! message before opening the app. If the icon is still missing after installation completes, a respring may help."],
        nil];

    NSArray *subscriptions = [NSArray arrayWithObjects:
        [self question:@"Where are subscription details?"
                 answer:@"Tap the info button beside a subscription to see its source, description, configuration count, traffic, and expiry when supplied. You can rename, update, or delete it there."],
        [self question:@"How do I stop an import or update?"
                 answer:@"The power icon shows activity or processing progress. Tap the main refresh button, which becomes a stop button during an import or update. Cancellation is available until final saving begins. A failed save preserves the previous store. The result reports valid profiles, duplicates, and unsupported entries."],
        [self question:@"Why was an import rejected?"
                 answer:@"A subscription must return at least one supported proxy entry. An unavailable provider, empty or HTML response, certificate error, or unsupported settings can prevent import. Invalid entries in a mixed list are skipped with safe reasons. Support for HAPP, INCY, and Karing imports does not include every feature of those applications."],
        [self question:@"How are subscriptions updated?"
                 answer:@"The main refresh button updates subscriptions. Update Now in a subscription's details updates only that subscription. Auto-update subscriptions runs after a fresh app launch without interrupting an active VPN connection. Preserve custom names keeps user-assigned subscription names after updates."],
        [self question:@"How does sorting by ping work?"
                 answer:@"Sort configs by ping is off by default. When enabled, lower successful latencies appear first within each subscription. It changes the displayed order, not the saved source order."],
        nil];

    NSArray *protocols = [NSArray arrayWithObjects:
        [self question:@"Which protocols are supported?"
                 answer:@"VLESS, Trojan, VMess AEAD, Shadowsocks, and upstream SOCKS5. For more details, please visit a vless-core-cli repo page."],
        [self question:@"Which transports are supported?"
                 answer:@"TCP/raw, gRPC gun/multi, and XHTTP with none, TLS, or REALITY. WebSocket and HTTPUpgrade support none or TLS (REALITY unsupported). HTTPUpgrade uses HTTP/1.1. SOCKS5 is a separate upstream protocol. Supported fingerprints are chrome, firefox, edge, random, randomized, and qq."],
        [self question:@"What does XHTTP support?"
                 answer:@"XHTTP supports auto, packet-up, stream-one, and stream-up modes, XMUX, and a separate download channel. Auto selects packet-up with none/TLS. With REALITY it selects stream-one, or stream-up when a separate download channel is configured. Use XMUX controls only whether its XMUX settings are used for a new connection."],
        [self question:@"How does Use XMUX work?"
                 answer:@"Use XMUX is enabled by default. It uses XHTTP XMUX settings already present in the configuration. When disabled, those settings are removed only from the temporary VPN or Proxy GET configuration, including its download channel. Saved links are unchanged. It does not add missing XMUX settings, disable HTTP/2 or the gRPC pool, or interrupt an existing connection."],
        nil];

    NSArray *pings = [NSArray arrayWithObjects:
        [self question:@"What does each ping type check?"
                 answer:@"Proxy GET sends an HTTP request through the selected proxy. TCP only checks a connection to the proxy server's port. ICMP sends an echo request to the server, which may block ICMP even when its proxy works. Choose the type in Settings → Network → Ping. The URL is used by Proxy GET and tunnel checks, not TCP or ICMP. Only HTTP is supported and redirects are not followed."],
        [self question:@"What do ping errors mean?"
                 answer:@"DNS: Could not resolve the server's IP address.\n"
                         @"TCP: Could not establish a TCP connection to the server.\n"
                         @"Transport: A TLS/REALITY or transport error occurred (XHTTP, gRPC, WebSocket, or HTTPUpgrade).\n"
                         @"Protocol: Failed to complete proxy protocol setup.\n"
                         @"Response: Failed to receive the expected response over the connection.\n"
                         @"Failed: No failure-stage details are available."],
        nil];

    NSArray *connections = [NSArray arrayWithObjects:
        [self question:@"Why can't I connect?"
                 answer:@"Check that a supported configuration is selected, then read the message shown after Connect. Verify the server address, port, credentials, and transport settings. The daemon and core logs can help identify the stage that failed. Logs are unavailable for encrypted HAPP subscriptions."],
        [self question:@"How does routing work?"
                 answer:@"Open Settings → Network → Routing. Enable it, choose the default Proxy, Direct, or Block action, then add ordered domain, suffix, IP/CIDR, or port rules. The first matching rule wins after the optional local-network bypass. Reconnect after changing the policy."],
        [self question:@"Does closing the app stop the VPN?"
                 answer:@"No. The vpnctld daemon manages the connection after the app closes. Reopen the app to manage it or press Disconnect to stop it."],
        nil];

    NSArray *troubleshooting = [NSArray arrayWithObjects:
        [self question:@"Where can I find the logs?"
                 answer:@"Tap the terminal button on the main screen. The vpnctld log covers daemon and device routing. The vless-core log covers the proxy protocol and transport. Logs update while open and the trash button clears them. Settings → Debug → Debug and diagnostics provides state, tests, events, and a report. Review technical logs and reports before sharing them."],
        [self question:@"What does Stealth mode hide?"
                 answer:@"Stealth mode masks configuration and subscription links in the interface. It does not redact technical logs or change the connection. Configurations and subscriptions are encrypted in the local store regardless of Stealth mode. Encrypted HAPP subscriptions have separate restrictions on exposing links and connection logs."],
        nil];

    NSArray *compatibility = [NSArray arrayWithObject:
        [self question:@"Which devices are supported?"
                 answer:@"A rootful jailbreak is required.\n"
                        @"vless-core supports iOS 5 through iOS 14.\n"
                        @"On iOS 5 - iOS 10 it uses the ARMv7 runtime, including ARM64 devices through 32-bit compatibility.\n"
                        @"On iOS 11 - iOS 14 it uses the native ARM64 runtime.\n"
                        @"The package selects the correct runtime automatically during installation."]];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
        [self sectionWithTitle:@"Getting started" questions:gettingStarted],
        [self sectionWithTitle:@"Subscriptions" questions:subscriptions],
        [self sectionWithTitle:@"Protocols and transports" questions:protocols],
        [self sectionWithTitle:@"Ping" questions:pings],
        [self sectionWithTitle:@"Connections and routing" questions:connections],
        [self sectionWithTitle:@"Privacy and troubleshooting" questions:troubleshooting],
        [self sectionWithTitle:@"Compatibility" questions:compatibility],
        nil];
    [_sections release];
    _sections = newSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"FAQ";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
}

- (NSDictionary *)questionAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *section = [_sections objectAtIndex:indexPath.section];
    return [[section objectForKey:@"questions"] objectAtIndex:indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return [[[_sections objectAtIndex:section] objectForKey:@"questions"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = [self questionAtIndexPath:indexPath];
    NSString *answer = [item objectForKey:@"answer"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize answerSize = [answer sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 2000.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 31.0f + answerSize.height + 17.0f;
    return (height < 64.0f) ? 64.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kFAQCellId = @"FAQCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kFAQCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kFAQCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *item = [self questionAtIndexPath:indexPath];
    cell.textLabel.text = [item objectForKey:@"question"];
    cell.detailTextLabel.text = [item objectForKey:@"answer"];
    VCAppearanceApplyCell(cell);
    return cell;
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
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@implementation AboutVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSString *coreVersion = DetectCoreBinaryVersion();
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();
    NSString *redsocksVersion = DetectRedsocksVersion();

    NSArray *components = [NSArray arrayWithObjects:
                           [self rowWithTitle:@"vless-core-cli" detail:coreVersion],
                           [self rowWithTitle:@"vless-core-curl"
                                       detail:[NSString stringWithFormat:@"curl %@, OpenSSL %@ (%@), zlib %@",
                                               [deps objectForKey:@"curl"],
                                               [deps objectForKey:@"openssl"],
                                               opensslPatchStatus,
                                               [deps objectForKey:@"zlib"]]],
                           [self rowWithTitle:@"redsocks-vless-core" detail:redsocksVersion],
                           nil];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"Bundled components" rows:components],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (UIView *)tableHeaderForWidth:(CGFloat)width {
    CGFloat headerHeight = 212.0f;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, headerHeight)] autorelease];
    header.backgroundColor = [UIColor clearColor];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImage *icon = LoadBundledIconScaled(@"Icon", 82.0f);
    UIImageView *iconView = [[[UIImageView alloc] initWithImage:icon] autorelease];
    iconView.frame = CGRectMake((width - 82.0f) / 2.0f, 22.0f, 82.0f, 82.0f);
    iconView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    iconView.layer.cornerRadius = 14.0f;
    iconView.layer.masksToBounds = YES;
    [header addSubview:iconView];

    UILabel *nameLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 112.0f, width - 32.0f, 28.0f)] autorelease];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    nameLabel.backgroundColor = [UIColor clearColor];
    nameLabel.textAlignment = NSTextAlignmentCenter;
    nameLabel.textColor = VCPrimaryTextColor();
    nameLabel.font = [UIFont boldSystemFontOfSize:22.0f];
    nameLabel.text = AppDisplayName();
    [header addSubview:nameLabel];

    UILabel *versionLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 140.0f, width - 32.0f, 22.0f)] autorelease];
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    versionLabel.backgroundColor = [UIColor clearColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.textColor = VCSecondaryTextColor();
    versionLabel.font = [UIFont systemFontOfSize:14.0f];
    versionLabel.text = AppVersionSummary();
    [header addSubview:versionLabel];

    UILabel *buildLabel = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 162.0f, width - 32.0f, 44.0f)] autorelease];
    buildLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    buildLabel.backgroundColor = [UIColor clearColor];
    buildLabel.textAlignment = NSTextAlignmentCenter;
    buildLabel.textColor = VCSecondaryTextColor();
    buildLabel.font = [UIFont systemFontOfSize:14.0f];
    buildLabel.numberOfLines = 2;
    buildLabel.text = AppBuildMetadataSummary();
    [header addSubview:buildLabel];

    return header;
}

- (UIView *)tableFooterForWidth:(CGFloat)width {
    UIView *footer = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 48.0f)] autorelease];
    footer.backgroundColor = [UIColor clearColor];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(16.0f, 8.0f, width - 32.0f, 24.0f)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    label.backgroundColor = [UIColor clearColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = VCSecondaryTextColor();
    label.font = [UIFont boldSystemFontOfSize:14.0f];
    label.text = @"made by notfence";
    [footer addSubview:label];

    return footer;
}

- (void)updateTableHeaderAndFooterForWidth:(CGFloat)width {
    if (width <= 0.0f) {
        return;
    }

    _headerWidth = width;
    _tableView.tableHeaderView = [self tableHeaderForWidth:width];
    _tableView.tableFooterView = [self tableFooterForWidth:width];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
    [self updateTableHeaderAndFooterForWidth:_tableView.bounds.size.width];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = _tableView.bounds.size.width;
    if (fabs(_headerWidth - width) > 0.5f) {
        [self updateTableHeaderAndFooterForWidth:width];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kAboutCellId = @"AboutCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kAboutCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kAboutCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    VCAppearanceApplyCell(cell);
    return cell;
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
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@implementation LicenseDocumentVC

- (id)initWithTitle:(NSString *)title resourceName:(NSString *)resourceName marker:(NSString *)marker {
    self = [super init];
    if (self) {
        self.title = title;
        _resourceName = [resourceName copy];
        _marker = [marker copy];
    }
    return self;
}

- (void)dealloc {
    [_textView release];
    [_documentText release];
    [_resourceName release];
    [_marker release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = VCBackgroundColor();

    NSString *path = [[NSBundle mainBundle] pathForResource:_resourceName ofType:nil];
    NSString *text = path
        ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]
        : nil;
    if (![text length]) {
        text = @"License information is unavailable.";
    }
    _documentText = [text copy];

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.backgroundColor = VCBackgroundColor();
    _textView.textColor = VCPrimaryTextColor();
    _textView.font = [UIFont systemFontOfSize:13.0f];
    _textView.editable = NO;
    _textView.text = _documentText;
    [self.view addSubview:_textView];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_didScrollToMarker || ![_marker length]) {
        return;
    }

    NSRange range = [_documentText rangeOfString:_marker options:NSCaseInsensitiveSearch];
    if (range.location != NSNotFound) {
        [_textView scrollRangeToVisible:range];
        _textView.selectedRange = NSMakeRange(range.location, 0);
    }
    _didScrollToMarker = YES;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end

@implementation CreditsVC

- (void)dealloc {
    [_tableView release];
    [_sections release];
    [super dealloc];
}

- (NSDictionary *)rowWithTitle:(NSString *)title detail:(NSString *)detail {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            nil];
}

- (NSDictionary *)licensedRowWithTitle:(NSString *)title detail:(NSString *)detail marker:(NSString *)marker {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            detail ? detail : @"", @"detail",
            @"THIRD_PARTY_LICENSES.txt", @"licenseResource",
            marker ? marker : @"", @"licenseMarker",
            nil];
}

- (NSDictionary *)projectLicenseRow {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"vless-core-app", @"title",
            @"vless-core-app Source License 1.0. Tap to read the license.", @"detail",
            @"LICENSE", @"licenseResource",
            @"", @"licenseMarker",
            nil];
}

- (NSDictionary *)sectionWithTitle:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            title ? title : @"", @"title",
            rows ? rows : [NSArray array], @"rows",
            nil];
}

- (void)buildSections {
    NSDictionary *deps = DetectCurlDependencyVersions();
    NSString *opensslPatchStatus = DetectOpenSSLPatchStatus();

    NSArray *libraries = [NSArray arrayWithObjects:
                          [self licensedRowWithTitle:@"Twemoji flags"
                                              detail:@"Flag graphics 17.0.3 by Twitter and contributors. License: CC BY 4.0. Unicode Emoji 17.0 data."
                                              marker:@"Twemoji 17.0.3 flag graphics"],
                          [self licensedRowWithTitle:@"curl"
                                              detail:[NSString stringWithFormat:@"HTTP client library, version %@. License: curl license.", [deps objectForKey:@"curl"]]
                                              marker:@"curl 8.21.0"],
                          [self licensedRowWithTitle:@"OpenSSL"
                                              detail:[NSString stringWithFormat:@"TLS library, version %@, %@. License: Apache 2.0.", [deps objectForKey:@"openssl"], opensslPatchStatus]
                                              marker:@"OpenSSL 3.5.7"],
                          [self licensedRowWithTitle:@"zlib"
                                              detail:[NSString stringWithFormat:@"Compression library, version %@. License: zlib license.", [deps objectForKey:@"zlib"]]
                                              marker:@"zlib 1.3.1"],
                          [self licensedRowWithTitle:@"libevent"
                                              detail:@"Event loop library used by redsocks. License: BSD-style licenses."
                                              marker:@"libevent 2.1.12-stable"],
                          [self licensedRowWithTitle:@"ZBar"
                                              detail:@"QR code recognition library, version 0.23.93. License: LGPL 2.1 or later."
                                              marker:@"ZBar 0.23.93"],
                          [self licensedRowWithTitle:@"CA certificates"
                                              detail:@"Mozilla CA bundle packaged as cacert.pem. License: MPL 2.0."
                                              marker:@"Mozilla CA certificate bundle"],
                          [self licensedRowWithTitle:@"redsocks"
                                              detail:@"SOCKS5 redirector used for full-device routing. License: Apache 2.0."
                                              marker:@"redsocks"],
                          [self licensedRowWithTitle:@"INCY link format"
                                              detail:@"crypt1 compatibility with incy-link-encoder 1.3.0. License: MIT."
                                              marker:@"INCY link encoder"],
                          nil];

    NSArray *thanks = [NSArray arrayWithObject:
                       [self rowWithTitle:@"Special thanks to:" detail:@"@kirillshpitalev for testing and debugging\n"
                                                                       @"@rafal_official for testing and debugging\n"
                                                                       @"@polin0m for testing and debugging\n"
                                                                       @"@cmp_73 for testing and debugging"]];

    NSArray *newSections = [[NSArray alloc] initWithObjects:
                            [self sectionWithTitle:@"License" rows:[NSArray arrayWithObject:[self projectLicenseRow]]],
                            [self sectionWithTitle:@"Third-party software" rows:libraries],
                            [self sectionWithTitle:@"Special thanks" rows:thanks],
                            nil];
    [_sections release];
    _sections = newSections;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Credits";
    self.view.backgroundColor = VCBackgroundColor();
    [self buildSections];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    VCAppearanceApplyTable(_tableView);
    [self.view addSubview:_tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [_sections count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    NSDictionary *sectionInfo = [_sections objectAtIndex:section];
    return [[sectionInfo objectForKey:@"rows"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [[_sections objectAtIndex:section] objectForKey:@"title"];
}

- (NSDictionary *)rowForIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *sectionInfo = [_sections objectAtIndex:indexPath.section];
    return [[sectionInfo objectForKey:@"rows"] objectAtIndex:indexPath.row];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *detail = [row objectForKey:@"detail"];
    CGFloat width = tableView.bounds.size.width - 52.0f;
    CGSize detailSize = [detail sizeWithFont:[UIFont systemFontOfSize:13.0f]
                           constrainedToSize:CGSizeMake(width, 200.0f)
                               lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat height = 28.0f + detailSize.height + 16.0f;
    return (height < 58.0f) ? 58.0f : height;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kCreditsCellId = @"CreditsCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCreditsCellId];
    if (!cell) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCreditsCellId] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15.0f];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
    }

    NSDictionary *row = [self rowForIndexPath:indexPath];
    cell.textLabel.text = [row objectForKey:@"title"];
    cell.detailTextLabel.text = [row objectForKey:@"detail"];
    BOOL hasLicense = [[row objectForKey:@"licenseResource"] length] > 0;
    cell.selectionStyle = hasLicense ? UITableViewCellSelectionStyleBlue
                                     : UITableViewCellSelectionStyleNone;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = hasLicense ? VCCreateDisclosureAccessoryView() : nil;
    VCAppearanceApplyCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowForIndexPath:indexPath];
    NSString *resourceName = [row objectForKey:@"licenseResource"];
    NSString *marker = [row objectForKey:@"licenseMarker"];
    if ([resourceName length]) {
        LicenseDocumentVC *license = [[[LicenseDocumentVC alloc]
            initWithTitle:[row objectForKey:@"title"] resourceName:resourceName marker:marker] autorelease];
        [self.navigationController pushViewController:license animated:YES];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
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
    if (IsPadDevice()) {
        return UIInterfaceOrientationIsPortrait(interfaceOrientation) || UIInterfaceOrientationIsLandscape(interfaceOrientation);
    }
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}

- (BOOL)shouldAutorotate {
    return IsPadDevice();
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (IsPadDevice()) {
        return UIInterfaceOrientationMaskAllButUpsideDown;
    }
    return UIInterfaceOrientationMaskPortrait;
}

@end
