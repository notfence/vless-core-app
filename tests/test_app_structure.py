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
