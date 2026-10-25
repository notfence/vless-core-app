from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
methods = []
for signature in sys.argv[3:]:
    optional = signature.startswith('?')
    signature = signature[1:] if optional else signature
    start = source.find(signature)
    if start < 0 and optional:
        continue
    if start < 0:
        raise ValueError(f'Missing method: {signature}')
    end = source.index('\n}', start) + 2
    methods.append(source[start:end])
Path(sys.argv[2]).write_text('\n'.join(methods) + '\n')
