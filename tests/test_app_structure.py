from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def tokens(source):
    pattern = r'//[^\n]*|/\*[\s\S]*?\*/|@?"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|@?[A-Za-z_]\w*|[^\s]'
    for match in re.finditer(pattern, source):
        text = match.group()
        if text.startswith(('//', '/*', '"', '@"', "'")):
            continue
        yield text

def implementations(path):
    stream = list(tokens(path.read_text()))
    owner = None
    depth = 0
    index = 0
    while index < len(stream):
        token = stream[index]
        if token == '@implementation':
            owner = stream[index + 1]
            index += 2
            continue
        if token == '@end':
            owner = None
        if token == '{':
            depth += 1
        elif token == '}':
            depth -= 1
        elif owner and depth == 0 and token in ('-', '+') and stream[index + 1] == '(':
            header = []
            cursor = index + 1
            while stream[cursor] != '{':
                header.append(stream[cursor])
                cursor += 1
            parenthesis = 0
            names = []
            for offset, value in enumerate(header):
                if value == '(':
                    parenthesis += 1
                elif value == ')':
                    parenthesis -= 1
                elif parenthesis == 0 and re.fullmatch(r'[A-Za-z_]\w*', value):
                    if offset + 1 < len(header) and header[offset + 1] == ':':
                        names.append(value + ':')
                    elif not names:
                        names.append(value)
            yield owner, token + ''.join(names)
            index = cursor - 1
        index += 1

def main():
    layout = (ROOT / 'app/main_layout.m').read_text()
    connect_button = layout.split('- (void)updateConnectButton {', 1)[1].split('\n}', 1)[0]
    if 'setLoading:_subscriptionRefreshInProgress || VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0)' not in connect_button:
        raise AssertionError('app/power-spinner-must-only-follow-network-operations-not-store-loading')
    connection = (ROOT / 'app/main_connection.m').read_text()
    action = connection.split('- (BOOL)isConnectionActionInProgress {', 1)[1].split('\n}', 1)[0]
    if 'if ([self configurationMutationBlocked]) return YES;' not in action:
        raise AssertionError('app/store-loading-and-commit-must-still-block-connection-actions')
    initial_status = connection.split('- (void)queryInitialStatus {', 1)[1].split('\n}', 1)[0]
    if 'generation != _connectionActionGeneration || VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0)' not in initial_status or '[self isConnectionActionInProgress]' in initial_status:
        raise AssertionError('app/initial-daemon-status-must-not-be-discarded-during-store-loading')
    state = (ROOT / 'app/main_state.m').read_text()
    settings_source = (ROOT / 'app/settings.m').read_text()
    main_settings = (ROOT / 'app/main_settings.m').read_text()
    if '@implementation VCPingSettingsVC' not in settings_source:
        raise AssertionError('app/ping-type-and-url-must-have-a-dedicated-ping-menu')
    ping_settings = settings_source.split('@implementation VCPingSettingsVC', 1)[1].split('@end', 1)[0]
    parent_settings = settings_source.split('@implementation SettingsVC', 1)[1].split('@end', 1)[0]
    if 'return @"Ping";' not in parent_settings or 'if (section == 1) return 4;' not in parent_settings or 'VCPingSettingsVC alloc' not in parent_settings:
        raise AssertionError('app/network-must-open-ping-menu-instead-of-exposing-its-fields')
    if 'kVCSettingsProxyPingURLAlertTag' in parent_settings or 'otherButtonTitles:@"Proxy GET"' in parent_settings:
        raise AssertionError('app/ping-editors-must-not-remain-in-parent-settings')
    for required in ('self.title = @"Ping";', 'return 3;', '@"Ping type"', '@"URL"', '@"Timeout"', 'VCSelectedPingTypeText()', 'VCSelectedProxyPingURL()', 'kDefaultsPingTypeKey'):
        if required not in ping_settings:
            raise AssertionError('app/ping-menu-must-contain-working-type-url-and-timeout-rows')
    ping_sections = ping_settings.split('- (NSInteger)numberOfSectionsInTableView:', 1)[1].split('\n}', 1)[0]
    ping_rows = ping_settings.split('numberOfRowsInSection:', 1)[1].split('\n}', 1)[0]
    if 'return 3;' not in ping_sections or 'return 1;' not in ping_rows:
        raise AssertionError('app/each-ping-setting-must-have-its-own-section')
    ping_footer = ping_settings.split('titleForFooterInSection:', 1)[1].split('\n}', 1)[0]
    if any(';' in text for text in re.findall(r'@"(?:\\.|[^"\\])*"', ping_footer)):
        raise AssertionError('app/ping-descriptions-must-use-sentences-without-semicolons')
    for required in ('if (section == 0)', 'if (section == 1)', 'Proxy GET', 'TCP', 'ICMP', 'Only HTTP', 'Empty restores', 'per attempt', 'two attempts', 'DNS and core startup'):
        if required not in ping_footer:
            raise AssertionError('app/ping-settings-must-have-separate-explanations-for-type-url-and-timeout')
    if 'indexPath.row' in ping_settings or 'titleForRow:' in ping_settings or 'detailForRow:' in ping_settings:
        raise AssertionError('app/ping-cards-and-editors-must-address-sections-not-row-numbers')
    for required in ('indexPathForRow:0 inSection:0', 'indexPathForRow:0 inSection:1', 'indexPathForRow:0 inSection:2', 'indexPath.section == 2', 'titleForSection:indexPath.section', 'detailForSection:indexPath.section'):
        if required not in ping_settings:
            raise AssertionError('app/ping-section-layout-must-preserve-editor-refresh-and-slider-targets')
    parent_detail = parent_settings.split('- (NSString *)settingsDetailTextForIndexPath:', 1)[1].split('\n}', 1)[0]
    if 'return @"Ping settings";' not in parent_detail or 'VCSelectedPingTypeText()' in parent_detail:
        raise AssertionError('app/ping-menu-description-must-describe-settings-not-selection')
    if 'VCApplyStaticSettingsCell(' not in ping_settings or 'rowHeight = 56' in ping_settings or 'systemFontOfSize:12' in ping_settings:
        raise AssertionError('app/ping-cards-must-use-shared-settings-style-and-native-row-height')
    if 'VCApplySettingsCell(' in ping_settings or 'Marquee' in ping_settings or 'viewDidLayoutSubviews' in ping_settings:
        raise AssertionError('app/ping-menu-must-use-native-labels-without-marquee-layout-passes')
    static_settings_cell = settings_source.split('static void VCApplyStaticSettingsCell(', 1)[1].split('\n}', 1)[0]
    if any(value in static_settings_cell for value in ('Marquee', 'layoutIfNeeded', 'clearColor')) or 'VCAppearanceApplyCell(cell);' not in static_settings_cell:
        raise AssertionError('app/static-settings-style-must-keep-native-visible-labels-without-scrolling')
    marquee_settings_cell = settings_source.split('static void VCApplySettingsCell(', 1)[1].split('\n}', 1)[0]
    if 'VCApplyStaticSettingsCell(cell,title,detail);' not in marquee_settings_cell or 'VCSettingsMarqueeForCell(' not in marquee_settings_cell:
        raise AssertionError('app/main-settings-must-keep-marquee-on-top-of-shared-native-style')
    if 'VCApplySettingsCell(cell,title,detail);' not in parent_settings:
        raise AssertionError('app/ping-and-main-settings-must-share-one-card-renderer')
    for required in ('UISlider alloc', 'kVCPingTimeoutMinimumSeconds', 'kVCPingTimeoutMaximumSeconds', 'VCNormalizedPingTimeoutSeconds', 'kDefaultsPingTimeoutSecondsKey', 'UIControlEventTouchUpInside', 'UIControlEventTouchUpOutside', 'UIControlEventTouchCancel'):
        if required not in ping_settings:
            raise AssertionError('app/ping-timeout-slider-must-be-bounded-snapped-and-saved-after-drag')
    if 'else if (indexPath.section == 1)' not in ping_settings:
        raise AssertionError('app/timeout-row-must-not-open-the-url-editor')
    drag = ping_settings.split('- (void)timeoutChanged:', 1)[1].split('\n}', 1)[0]
    if 'synchronize' in drag or 'reloadRowsAtIndexPaths:' in drag:
        raise AssertionError('app/slider-drag-must-not-write-preferences-or-replace-the-active-cell')
    if 'sender.tracking' not in drag or 'accessibilityValue' not in drag:
        raise AssertionError('app/slider-must-support-live-values-and-accessibility-changes')
    if 'pingSettingsVCDidChangeProbeSettings:' not in parent_settings or 'settingsVCDidChangePingSettings:self' not in parent_settings:
        raise AssertionError('app/ping-menu-must-forward-setting-changes-to-invalidate-results')
    save_probe_url = ping_settings.split('if (alertView.tag == kVCSettingsProxyPingURLAlertTag)', 1)[1]
    if save_probe_url.index('VCProxyPingTargetForURL(value)') > save_probe_url.index('[defaults setObject:value'):
        raise AssertionError('app/proxy-get-url-must-be-validated-before-saving')
    if 'VCRecordAppEvent(@"settings",@"Proxy GET URL changed",nil)' not in save_probe_url or 'saveData' in save_probe_url:
        raise AssertionError('app/proxy-get-url-must-not-log-url-or-rewrite-profile-store')
    changed_url = main_settings.split('- (void)settingsVCDidChangePingSettings:', 1)[1].split('\n}', 1)[0]
    for required in ('stopAllPings', '++_pingNetworkGeneration', 'removeAllObjects', 'scheduleSubscriptionPingSort', 'refreshVisiblePingAccessoriesForURI:'):
        if required not in changed_url:
            raise AssertionError('app/proxy-get-url-change-must-cancel-and-invalidate-results')
    if 'if (section == 0) return 4;' not in settings_source or 'SettingsPingSortCell' not in settings_source or 'settings.sortSubscriptionsByPing = _sortSubscriptionsByPing;' not in main_settings:
        raise AssertionError('app/ping-sort-must-have-a-subscriptions-setting')
    settings_controller = settings_source.split('@implementation SettingsVC', 1)[1].split('@end', 1)[0]
    settings_theme = settings_controller.split('- (void)applyTheme {', 1)[1].split('\n}', 1)[0]
    settings_load = settings_controller.split('- (void)viewDidLoad {', 1)[1].split('\n}', 1)[0]
    for switch in re.findall(r'(_\w+Switch)\s*=\s*\[\[UISwitch alloc\]', settings_controller):
        if f'{switch}.onTintColor = VCAccentColor();' not in settings_theme:
            raise AssertionError(f'app/settings-switch-must-follow-accent:{switch}')
        if settings_load.index(f'{switch} = [[UISwitch alloc]') > settings_load.index('[self applyTheme];'):
            raise AssertionError('app/settings-must-apply-accent-after-creating-switches')
    accent_change = settings_controller.split('- (void)accentColorVCDidChange {', 1)[1].split('\n}', 1)[0]
    if '[self applyTheme];' not in accent_change:
        raise AssertionError('app/settings-must-refresh-switches-after-accent-change')
    sort_setting = main_settings.split('- (void)settingsVC:(SettingsVC *)vc didChangeSortSubscriptionsByPing:', 1)[1].split('\n}', 1)[0]
    if '[defaults setBool:enabled forKey:kDefaultsSortSubscriptionsByPingKey]' not in sort_setting or 'saveData' in sort_setting:
        raise AssertionError('app/ping-sort-setting-must-persist-without-reserializing-profiles')
    if '_sortSubscriptionsByPing=[defaults boolForKey:kDefaultsSortSubscriptionsByPingKey];' not in state or '_sortSubscriptionsByPing = [ud boolForKey:kDefaultsSortSubscriptionsByPingKey];' not in state:
        raise AssertionError('app/ping-sort-must-default-off-and-reload-saved-setting')
    mapping = state.split('- (BOOL)mapSubscriptionRow:', 1)[1].split('\n}', 1)[0]
    if 'matchesItems:items' not in mapping or 'sourceIndexForDisplayIndex:item' not in mapping or '_selectedSubItemIndex' in mapping:
        raise AssertionError('app/sorted-display-must-cache-and-map-to-original-indices-without-changing-selection')
    apply_sort = state.split('- (void)applySubscriptionPingSort {', 1)[1].split('\n}', 1)[0]
    for required in ('isSubscriptionPingInProgressAtIndex:', '_mainSectionTransitionInProgress', '_tableView.dragging', '_tableView.decelerating', '_tableView.editing', 'updateWithDisplays:', 'reloadSections:'):
        if required not in apply_sort:
            raise AssertionError('app/ping-sort-must-wait-for-batch-and-interactions-and-only-reload-on-change')
    ping_source = (ROOT / 'app/main_ping.m').read_text()
    for required in ('return @"Use XMUX";', 'return @"Use XMUX for supported configs";', 'SettingsUseXmuxCell', 'cell.accessoryView = _useXmuxSwitch;', '[_useXmuxSwitch release]'):
        if required not in parent_settings:
            raise AssertionError('app/xmux-must-use-the-requested-title-description-and-shared-settings-style')
    xmux_setting = main_settings.split('- (void)settingsVC:(SettingsVC *)vc didChangeUseXmux:', 1)[1].split('\n}', 1)[0]
    if '[defaults setBool:enabled forKey:kDefaultsUseXmuxKey]' not in xmux_setting or 'VCSelectedPingType() == VCPingTypeProxyGET' not in xmux_setting or 'saveData' in xmux_setting or 'SendCommand' in xmux_setting:
        raise AssertionError('app/xmux-setting-must-save-without-rewriting-profiles-or-interrupting-vpn-and-tcp-icmp')
    reconnect_prepare = connection.split('- (void)reconnectToURIIfNeededFrom:', 1)[1].split('- (void)beginPendingReconnect', 1)[0]
    if reconnect_prepare.index('runtimeURI:newURI') > reconnect_prepare.index('_pendingReconnectURI = [newURI copy]') or '_pendingReconnectRuntimeURI = [runtimeURI copy]' not in reconnect_prepare:
        raise AssertionError('app/reconnect-must-prepare-and-snapshot-xmux-before-queuing-disconnect')
    reconnect = connection.split('- (void)beginPendingReconnect {', 1)[1].split('- (void)togglePressed', 1)[0]
    if 'ConnectCommandForURI(runtimeURI, protectLogs)' not in reconnect or 'ConnectCommandForURI(uri, protectLogs)' in connection or '[_pendingReconnectRuntimeURI isEqualToString:runtimeURI]' not in reconnect:
        raise AssertionError('app/connect-and-reconnect-must-use-the-prepared-uri-without-losing-new-settings')
    if '[payload setObject:@(VCUseXmuxInDefaults([NSUserDefaults standardUserDefaults])) forKey:@"use_xmux"]' not in ping_source:
        raise AssertionError('app/proxy-get-must-snapshot-xmux-before-enqueuing')
    worker = ping_source.split('- (void)pingWorker:', 1)[1].split('- (void)pingResultOnMain:', 1)[0]
    if 'runtimeURI:uri useXmux:[[payload objectForKey:@"use_xmux"] boolValue]' not in worker or 'if (runtimeURI) rc = ProxyGetViaTempCoreMs([runtimeURI UTF8String]' not in worker or '[out setObject:([uri isKindOfClass:[NSString class]] ? uri : @"") forKey:@"uri"]' not in worker:
        raise AssertionError('app/proxy-get-must-use-runtime-settings-but-report-the-original-profile-and-not-fallback-on-failure')
    if '[payload objectForKey:@"timeout_ms"]' not in worker or 'VCPingTimeoutSecondsInDefaults' not in ping_source:
        raise AssertionError('app/ping-timeout-must-be-snapshotted-before-enqueuing')
    if '3500, 2' in worker or '5000, 2' in worker or worker.count('timeoutMs, 2, &latencyMs') != 3:
        raise AssertionError('app/all-ping-types-must-use-the-selected-timeout')
    tcp_ping = (ROOT / 'app/network_ping.m').read_text().split('int ConnectLatencyMs(', 1)[1].split('int ConnectLatencyBestOfNMs(', 1)[0]
    if 'deadline-PingMonotonicMs()' not in tcp_ping or 'VCWaitForPingSocket(fd, YES, remaining, cancellation)' not in tcp_ping:
        raise AssertionError('app/tcp-address-fallback-must-not-restart-the-selected-timeout')
    if '[[VCSelectedProxyPingURL() copy] autorelease]' not in ping_source or '[payload objectForKey:@"probe_url"]' not in ping_source:
        raise AssertionError('app/proxy-get-workers-must-use-the-enqueued-url-snapshot')
    attempts = (ROOT / 'app/network_ping.m').read_text().split('int ProxyGetViaTempCoreMs(', 1)[1].split('static uint16_t ICMPChecksum', 1)[0]
    if 'ProxyGetConnectToURLOnceMs((uint16_t)port, probeURL,' not in attempts or 'VCSelectedProxyPingURL' in attempts:
        raise AssertionError('app/proxy-get-retries-must-not-switch-url-mid-operation')
    ping_press = ping_source.split('- (void)pingButtonPressed:', 1)[1].split('\n}', 1)[0]
    if 'indexPathForCell:' not in ping_press or 'mapSubscriptionRow:' not in ping_press or 'sender.tag' in ping_press or '1000' in ping_press:
        raise AssertionError('app/ping-buttons-must-resolve-current-sorted-row-without-1000-item-tags')
    if '_sortSubscriptionsByPing && (!batchIdentifier || completedSubscriptionPing)' not in ping_source:
        raise AssertionError('app/ping-sort-must-not-reorder-on-every-batch-result')
    table_source = (ROOT / 'app/main_table.m').read_text()
    if 'didEndEditingRowAtIndexPath:' not in table_source or '[_subscriptionPingOrder release]; _subscriptionPingOrder=nil;' not in state:
        raise AssertionError('app/ping-order-must-resume-after-editing-and-release-old-imported-profiles')
    editing_end = table_source.split('didEndEditingRowAtIndexPath:', 1)[1].split('\n}', 1)[0]
    if '[self scheduleSubscriptionPingSort];' not in editing_end or 'if (_sortSubscriptionsByPing)' in editing_end:
        raise AssertionError('app/ending-editing-must-also-apply-pending-sort-disable')
    if '(mappedItemIdx == 0)' in table_source or '(itemIdx == 0)' in table_source or 'subIdx * 1000' in table_source:
        raise AssertionError('app/sorted-card-edges-and-buttons-must-use-display-rows')
    save = state.split('- (void)saveData {', 1)[1].split('\n}', 1)[0]
    if 'prepareMetadataForConfigurations:' in save:
        raise AssertionError('app/save-must-not-reparse-all-profiles-on-main')
    if 'VCSaveProtectedConfigurationData(' in save or 'enqueueConfigurations:' not in save:
        raise AssertionError('app/save-must-use-background-writer')
    load = state.split('- (void)loadData {', 1)[1].split('\n}', 1)[0]
    if 'dispatch_async(_configurationQueue' not in load or load.index('dispatch_async(_configurationQueue') > load.index('VCLoadProtectedConfigurationData'):
        raise AssertionError('app/configuration-load-must-run-in-background')
    completion = state.split('- (void)completeConfigurationLoad:', 1)[1].split('\n}', 1)[0]
    if 'VCSaveProtectedConfigurationData(' in completion or 'VCLoadProtectedConfigurationData(' in completion or 'prepareMetadataForConfigurations:' in completion:
        raise AssertionError('app/load-completion-must-only-apply-prepared-state')
    if '(_connected ? @"Connected" : @"Ready")' not in completion:
        raise AssertionError('app/load-completion-must-preserve-already-restored-vpn-status')
    applied = state.split('- (void)finishConfigurationDraft:', 1)[1].split('\n}', 1)[0]
    if applied.index('if (saved)') > applied.index('[_configs release]') or 'installPreparedMetadata:' not in applied:
        raise AssertionError('app/import-must-only-apply-after-successful-save')
    imports = (ROOT / 'app/main_import.m').read_text()
    single_import = imports.split('- (void)importSubscriptionURL:', 1)[1].split('\n}', 1)[0]
    if 'updatedSubscriptionDictionaryFromSource:' in single_import or 'startBackgroundSubscriptionImportForURLs:' not in single_import:
        raise AssertionError('app/QR-and-single-subscription-import-must-be-background')
    text_import = imports.split('- (void)importTextEntry:', 1)[1].split('\n}', 1)[0]
    file_import = imports.split('- (void)importTextFileAtPath:', 1)[1].split('\n}', 1)[0]
    if 'startTextImport:' not in text_import or 'startTextImport:' not in file_import or 'dataWithContentsOfFile:' in file_import:
        raise AssertionError('app/text-and-file-import-must-use-worker')
    subscriptions = (ROOT / 'app/main_subscriptions.m').read_text()
    for source in (imports, subscriptions, (ROOT / 'app/main_screen.h').read_text(), (ROOT / 'app/subscription_work.m').read_text()):
        if any(unused in source for unused in ('startStatus', 'importedPrefixPart', '_pendingImportDoneStatus', 'refreshAllSubscriptions:')):
            raise AssertionError('app/subscription-code-must-not-retain-unused-status-plumbing')
    if '[self approvePlainHTTPForSubscriptionAtIndex:' in subscriptions:
        raise AssertionError('app/update-approval-must-not-mutate-store-before-commit')
    refresh = subscriptions.split('- (BOOL)refreshSubscriptionAtIndex:', 1)[1].split('\n}', 1)[0]
    if 'updatedSubscriptionDictionaryFromSource:' in refresh or 'startBackgroundSubscriptionRefresh]' not in refresh:
        raise AssertionError('app/single-refresh-must-be-background')
    work = (ROOT / 'app/subscription_work.m').read_text()
    if 'incy' in (ROOT / 'app/Info.plist').read_text().lower():
        raise AssertionError('app/incy-must-not-register-a-third-party-url-scheme')
    if 'textImportReportFromText:decoded' not in work or 'VCIncyIsCryptLink(uri)' not in work:
        raise AssertionError('app/incy-must-use-background-import-and-preserve-crypt-wrapper')
    if 'VCIncySubscriptionDescriptor(urlString,errorTextOut)' not in subscriptions or 'fetchURLString=[incy objectForKey:@"value"]' not in subscriptions:
        raise AssertionError('app/incy-update-must-resolve-source-without-replacing-stored-wrapper')
    if 'if (incy) fetchErr=VCIncySafeFetchError(fetchErr)' not in subscriptions or 'if (plain && !allowPlainHTTP && !SubscriptionDictionaryAllowsPlainHTTP' not in imports:
        raise AssertionError('app/incy-must-redact-fetch-errors-and-preserve-http-approval')
    if 'plainHTTPURLs arrayByAddingObjectsFromArray:insecureURLs' not in imports:
        raise AssertionError('app/incy-http-confirmation-must-preserve-pending-tls-prompts')
    if 'task != _subscriptionTask' not in work or 'revision != _configurationRevision' not in work:
        raise AssertionError('app/import-results-must-be-generation-checked')
    progress = work.split('- (void)subscriptionTaskProgress:', 1)[1].split('\n}', 1)[0]
    cancel = work.split('- (void)cancelSubscriptionTask {', 1)[1].split('\n}', 1)[0]
    if 'cancelWithReason:nil' not in cancel or 'VCSubscriptionTaskUpdate ? @"Cancel update"' not in layout:
        raise AssertionError('app/cancel-and-accessibility-must-follow-subscription-operation-kind')
    warning = (ROOT / 'app/main_screen.m').read_text().split('- (void)didReceiveMemoryWarning {', 1)[1].split('\n}', 1)[0]
    if 'cancellationReason stringByAppendingString:@": low memory"' not in warning:
        raise AssertionError('app/memory-warning-cancellation-must-follow-operation-kind')
    if 'showStatus:' in progress or 'showStatus:' in cancel or 'shows_notice' in progress:
        raise AssertionError('app/transient-progress-must-not-use-status-or-notice')
    if 'VCSubscriptionNotice' in work or '_subscriptionNotice' in (ROOT / 'app/main_screen.h').read_text():
        raise AssertionError('app/subscription-progress-must-not-create-an-overlay')
    if 'setProgress:[[progress objectForKey:@"fraction"] doubleValue]' not in progress or 'objectForKey:@"determinate"' not in progress or 'setLoading:YES' not in progress:
        raise AssertionError('app/subscription-progress-must-fill-power-ring-with-real-fraction')
    if progress.index('task != _subscriptionTask') > progress.index('consumeProgress') or 'updateConnectButton' in progress or '_refreshBtn.enabled=[[progress objectForKey:@"stoppable"] boolValue]' not in progress:
        raise AssertionError('app/progress-must-ignore-stale-tasks-and-keep-cancel-without-rebuilding-button')
    if 'if (_subscriptionTask) [self subscriptionTaskProgress:_subscriptionTask];' not in connect_button or 'BOOL refreshCancels=_subscriptionTask != nil;' not in layout:
        raise AssertionError('app/button-refresh-must-preserve-progress-and-cancel-for-all-import-kinds')
    finish = work.split('- (void)finishSubscriptionTask:', 1)[1].split('\n}', 1)[0]
    if 'else [self updateConnectButton];' not in finish or finish.index('_subscriptionTask=nil') > finish.index('else [self updateConnectButton];'):
        raise AssertionError('app/finishing-task-must-reset-ring-even-if-refresh-flag-was-cleared-earlier')
    power = (ROOT / 'app/connection_button.m').read_text()
    if '_progressTrackLayer' in power or '_progressLayer' in power or 'setProgressVisible:' in power:
        raise AssertionError('app/power-progress-must-use-one-contour-without-translucent-background-or-crossfade')
    ring = power.split('- (void)setProgress:', 1)[1].split('\n}', 1)[0]
    for expected in ('_progressRequested=YES', '++_transitionGeneration', 'animatePath:_progressPath progress:fraction spinning:NO'):
        if expected not in ring:
            raise AssertionError('app/determinate-ring-must-stop-spin-and-invalidate-delayed-transitions')
    transition = power.split('- (void)animatePath:(CGPathRef)path progress:(CGFloat)progress spinning:(BOOL)spinning {', 1)[1].split('\n}', 1)[0]
    if transition.index('CGPathCreateCopy(visible.path') > transition.index('removeAnimationForKey:@"powerSpin"') or 'rotation.fromValue = [NSNumber numberWithFloat:angle]' not in transition or 'animateProgress:progress duration:kVCPowerMorphDuration' not in transition:
        raise AssertionError('app/power-transitions-must-preserve-visible-path-angle-and-stroke')
    filling = power.split('- (void)animateProgress:(CGFloat)progress duration:(CFTimeInterval)duration {', 1)[1].split('\n}', 1)[0]
    if 'presentationLayer' not in filling or '_symbolLayer.strokeEnd=progress' not in filling or 'fabs(progress-from)' not in filling or 'progress > from' in filling:
        raise AssertionError('app/progress-changes-and-resets-must-animate-from-presentation-state-in-both-directions')
    loading = power.split('- (void)setLoading:', 1)[1].split('\n}', 1)[0]
    if '!_progressRequested' not in loading or '_progressRequested=NO' not in loading:
        raise AssertionError('app/spinner-and-idle-must-replace-progress-without-stale-callbacks')
    if 'task.kind == VCSubscriptionTaskProfiles' not in work or '@"Subscriptions updated"' not in work:
        raise AssertionError('app/subscription-summary-must-keep-result-counts')
    if 'beginSubscriptionTaskWithKind:VCSubscriptionTaskAddition' not in imports or 'beginSubscriptionTaskWithKind:VCSubscriptionTaskAddition' in subscriptions:
        raise AssertionError('app/import-and-update-must-retain-operation-kinds')
    for source in (work, imports, subscriptions, state, (ROOT / 'app/main_screen.m').read_text()):
        if re.search(r'showStatus:@"(?:Downloading|Processing|Reading import|Reading Karing|Receiving Karing|Saving configurations\.\.\.|Cancelling import|Loading configurations|Updating subscription)', source):
            raise AssertionError('app/import-progress-must-not-replace-status-line')
    if 'beginCommit]' not in state or 'cancelSubscriptionTask' not in (ROOT / 'app/main_settings.m').read_text():
        raise AssertionError('app/import-cancel-and-commit-must-be-gated')
    runtime = (ROOT / 'app/runtime_info.m').read_text()
    core_version = runtime.split('NSString *DetectCoreBinaryVersion(void) {', 1)[1].split('\n}', 1)[0]
    if 'return v;' not in core_version or 'substring' in core_version or 'componentsSeparated' in core_version:
        raise AssertionError('app/core-version-must-preserve-full-output')
    help_source = (ROOT / 'app/help_controllers.m').read_text()
    if '[self rowWithTitle:@"vless-core-cli" detail:coreVersion]' not in help_source:
        raise AssertionError('app/core-version-display-must-use-full-string')
    settings = (ROOT / 'app/settings.m').read_text().split('- (BOOL)saveVersion {', 1)[1].split('\n}', 1)[0]
    if 'stringByTrimming' in settings:
        raise AssertionError('app/xray-version-must-validate-unmodified-input')
    with tempfile.TemporaryDirectory(prefix='vless-source-manifest-') as directory:
        manifest = Path(directory) / 'manifest.mk'
        manifest.write_text('.PHONY: vc_test_source_manifest\nvc_test_source_manifest:\n\t@printf "VC_TEST_APP_SOURCES=%s\\n" "$(APP_SRC)"\n')
        result = subprocess.run(['make', '-s', '-j1', '--no-print-directory', '-f', 'Makefile', '-f', str(manifest), 'vc_test_source_manifest'], cwd=ROOT, capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            raise AssertionError('app/source-manifest: ' + result.stderr)
    lines = [line for line in result.stdout.splitlines() if line.startswith('VC_TEST_APP_SOURCES=')]
    if len(lines) != 1:
        raise AssertionError('app/invalid-source-manifest: ' + result.stdout)
    sources = [ROOT / name for name in lines[0].split('=', 1)[1].split()]
    registered = {path.resolve() for path in sources}
    actual = {path.resolve() for path in (ROOT / 'app').glob('*.m')}
    if not actual.issubset(registered):
        raise AssertionError('app/unregistered-source: ' + ', '.join(str(path.relative_to(ROOT)) for path in actual - registered))
    seen = {}
    main_count = 0
    for path in sources:
        if not path.is_file():
            raise AssertionError('app/missing-source: ' + str(path))
        if path.suffix != '.m':
            continue
        for owner, selector in implementations(path):
            key = owner, selector
            if key in seen:
                raise AssertionError(f'app/duplicate-selector: {owner} {selector}: {seen[key]} and {path}')
            seen[key] = path
            if owner == 'MainVC':
                main_count += 1
    if not main_count:
        raise AssertionError('app/main-controller-has-no-implementation')
    print(f'PASS app composition: {len(seen)} unique selectors, all app sources registered')

if __name__ == '__main__':
    try:
        main()
    except (AssertionError, OSError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f'FAIL {error}')
