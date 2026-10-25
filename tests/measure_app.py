import argparse
import hashlib
import json
from pathlib import Path
import statistics
import subprocess


def run(binary, count):
    command = [str(binary), '--measure', str(count)]
    result = subprocess.run(command, check=True, capture_output=True, text=True, timeout=330)
    return json.loads(next(line for line in reversed(result.stdout.splitlines()) if line.startswith('{')))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pairs', type=int, default=15)
    parser.add_argument('--counts', type=int, nargs='+', default=[1000, 6000, 20000])
    args = parser.parse_args()
    if args.pairs < 15:
        parser.error('At least 15 pairs are required')
    records = []
    summary = []
    binaries = {label: getattr(args, label).resolve() for label in ('before', 'after')}
    binary_hashes = {label: hashlib.sha256(binary.read_bytes()).hexdigest() for label, binary in binaries.items()}
    for count in args.counts:
        grouped = {'before': [], 'after': []}
        for pair in range(args.pairs):
            for label in (['before', 'after'] if pair % 2 == 0 else ['after', 'before']):
                value = run(binaries[label], count)
                records.append({'pair': pair, 'label': label, **value})
                grouped[label].append(value)
        for metric in grouped['before'][0]:
            if metric == 'count':
                continue
            before = statistics.median(value[metric] for value in grouped['before'])
            after = statistics.median(value[metric] for value in grouped['after'])
            def percentile(values):
                ordered = sorted(value[metric] for value in values)
                return ordered[min(len(ordered)-1, (95*len(ordered)+99)//100-1)]
            summary.append({'count': count, 'metric': metric, 'before': before, 'after': after,
                            'before_p95': percentile(grouped['before']), 'after_p95': percentile(grouped['after']),
                            'delta': after-before, 'percent': (after-before)*100/before if before else None})
    result = {'pairs': args.pairs, 'records': records, 'summary': summary,
              'sha256': binary_hashes}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(summary, indent=2))


if __name__ == '__main__':
    main()
