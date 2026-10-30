"""旧版一轮基准：python tool/bench_legacy.py --out <结果.json>。

B6 交错 A/B：本命令与 dart run benchmark/pipeline.dart 轮流各跑三轮。
只从固定提交 895d959 运行；临时 worktree 位于本工作区内，finally 移除。
stdout 仅输出和新版 runner 相同的 JSON；git/pub 日志写 stderr。
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import uuid

ROOT = Path(__file__).resolve().parents[1]
REVISION = '895d959'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    temporary = ROOT / ('.bench-legacy-' + uuid.uuid4().hex)
    dart = shutil.which('dart')
    if not dart:
        raise RuntimeError('dart unavailable')
    added = False
    try:
        subprocess.run(['git', 'worktree', 'add', '--detach', str(temporary), REVISION],
                       cwd=ROOT, check=True, stdout=sys.stderr)
        added = True
        package = temporary / 'dioman'
        subprocess.run([dart, 'pub', 'get', '--offline'], cwd=package,
                       check=True, stdout=sys.stderr)
        result = subprocess.run([dart, 'run', 'benchmark/legacy.dart'],
                                cwd=package, check=True, capture_output=True, text=True)
        sys.stderr.write(result.stderr)
        data = json.loads(result.stdout.strip())
        data['implementation'] = 'legacy-' + REVISION
        output = json.dumps(data, indent=2) + '\n'
        if args.out:
            args.out.write_text(output, encoding='utf-8')
        else:
            sys.stdout.write(output)
    finally:
        if added:
            assert temporary.resolve().is_relative_to(ROOT) and temporary.name.startswith('.bench-legacy-')
            subprocess.run(['git', 'worktree', 'remove', '--force', str(temporary)],
                           cwd=ROOT, check=True, stdout=sys.stderr)


if __name__ == '__main__':
    main()
