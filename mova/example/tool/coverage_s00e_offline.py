"""Publish one completed device-free S00e single-file Flutter run.

The artifact describes harness completion. Null/false CHECKs are preserved;
in particular an old product snapshot never becomes a new-contract PASS.
"""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess

TOOL = Path(__file__).resolve().parent
EXAMPLE = TOOL.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case', choices=['widgets', 'contract'])
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    target = args.output.resolve()
    if not target.is_relative_to(EXAMPLE): parser.error('output must stay inside mova/example')
    flutter = shutil.which('flutter')
    if not flutter: parser.error('flutter is unavailable')
    command = [flutter, 'test', f'test/s00e_{args.case}_test.dart', '--concurrency=2', '--no-pub']
    result = subprocess.run(command, cwd=EXAMPLE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    content = result.stdout.decode('utf-8', errors='replace')
    # Only the deliberately published CHECK stream, not duplicate COVERAGE logs.
    rows = [json.loads(match[1]) for line in content.splitlines()
            if (match := re.search(r'MATRIX_RECORD (\{.*\})', line))]
    target.parent.mkdir(parents=True, exist_ok=True)
    target.with_suffix('.log').write_text(content, encoding='utf-8')
    target.write_text(json.dumps(dict(status='done' if result.returncode == 0 else 'error',
        origin='offline-flutter-single-file', command=command, exitCode=result.returncode,
        records=rows), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    return result.returncode


if __name__ == '__main__': raise SystemExit(main())
