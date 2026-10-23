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
    if 'if (_configurationLoading) return YES;' not in action:
        raise AssertionError('app/store-loading-and-commit-must-still-block-connection-actions')
    initial_status = connection.split('- (void)queryInitialStatus {', 1)[1].split('\n}', 1)[0]
    if 'generation != _connectionActionGeneration || VCConnectionActionInProgress(_connectionActionInProgress, _reconnectInProgress, [_pendingReconnectURI length] > 0)' not in initial_status or '[self isConnectionActionInProgress]' in initial_status:
        raise AssertionError('app/initial-daemon-status-must-not-be-discarded-during-store-loading')
    state = (ROOT / 'app/main_state.m').read_text()
    save = state.split('- (void)saveData {', 1)[1].split('\n}', 1)[0]
    if 'prepareMetadataForConfigurations:' in save:
        raise AssertionError('app/save-must-not-reparse-all-profiles-on-main')
    load = state.split('- (void)loadData {', 1)[1].split('\n}', 1)[0]
    if 'dispatch_async(_configurationQueue' not in load or load.index('dispatch_async(_configurationQueue') > load.index('VCLoadProtectedConfigurationData'):
        raise AssertionError('app/configuration-load-must-run-in-background')
    completion = state.split('- (void)completeConfigurationLoad:', 1)[1].split('\n}', 1)[0]
    if 'VCSaveProtectedConfigurationData(' in completion or 'VCLoadProtectedConfigurationData(' in completion or 'prepareMetadataForConfigurations:' in completion:
        raise AssertionError('app/load-completion-must-only-apply-prepared-state')
    if '(_connected ? @"Connected" : @"Ready")' not in completion:
        raise AssertionError('app/load-completion-must-preserve-already-restored-vpn-status')
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
