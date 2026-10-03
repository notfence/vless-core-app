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
