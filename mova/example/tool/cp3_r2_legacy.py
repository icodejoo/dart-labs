"""Narrow repaired-fixture selectors; preserve the original command counts."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

TOOL = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('scene', choices=['subtitles', 'pool', 'stt', 'receipt'])
    args = parser.parse_args()
    commands = {
        'subtitles': [('subtitles', 'new', ['case=subtitles'])],
        'pool': [('feed', 'new', ['case=feed']),
                 ('s00d-resources', 'new', ['case=s00dResources'])],
        'stt': [('stt', 'new', ['case=stt'])],
        'receipt': [('basic', 'basic', []), ('basic-cutover', 'basic', ['cutover=true']),
                    ('abr', 'new', ['case=abr'])],
    }
    failed = False
    for tag, group, values in commands[args.scene]:
        name = 'cp3-r2-' + tag
        argv = [sys.executable, str(TOOL / 'coverage_device.py'), group,
                '--name', name, '--timeout', '180']
        for value in values:
            argv += ['--arg', value]
        code = subprocess.run(argv, cwd=TOOL.parents[1]).returncode
        path = TOOL / 'coverage_evidence' / (name + '.json')
        data = json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
        records = data.get('records', [])
        start = max((i for i, r in enumerate(records) if r.get('kind') == 'BEGIN'), default=0)
        records = records[start:]
        checks = [r for r in records if r.get('kind') == 'CHECK']
        complete = any(r.get('kind') == 'END' and r.get('status') == 'done' for r in records)
        print('R2 COMMAND', tag, 'exit', code, 'complete', complete, 'checks', len(checks), flush=True)
        failed |= bool(code) or not complete or not checks
    return int(failed)


if __name__ == '__main__':
    sys.exit(main())
