"""Explicit supplemental keepAlive attempts under the matrix job/cleanup policy."""
import argparse
import hashlib
import json
from pathlib import Path
from types import SimpleNamespace

import run_matrix as matrix


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run-id', required=True)
    p.add_argument('--apk', type=Path, required=True)
    p.add_argument('--runs', type=int, default=1)
    args = p.parse_args()
    if args.runs < 1:
        p.error('runs must be positive')
    manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports'] = [18080, 18082, 18083, 18087]
    d = matrix.Driver(SimpleNamespace(run_id=args.run_id), manifest)
    try:
        d.preflight()
        expected = hashlib.sha256(args.apk.read_bytes()).hexdigest()
        d.adb('install', '-r', str(args.apk.resolve()))
        remote = d.adb('shell', 'pm', 'path', matrix.PACKAGE).strip().removeprefix('package:')
        pulled = d.out/'supplement-device.apk'
        d.adb('pull', remote, str(pulled))
        actual = hashlib.sha256(pulled.read_bytes()).hexdigest()
        (d.out/'supplement-build.json').write_text(json.dumps(dict(expected=expected, actual=actual)), encoding='utf-8')
        if actual != expected:
            raise ValueError('supplement APK hash mismatch')
        return 0 if d.batch(dict(id='cp1-keepalive-s7s14', description='显式补采keepAlive缺失样本',
            why='保留缺测尝试，另取完整原生与阶段令牌/相邻帧证据',
            argv=['{python}', '{tool}/coverage_cp1.py', 'keepalive-s7s14', '--run-id', '{run_id}',
                  '--runs', str(args.runs), '--timeout', '7200'],
            timeout=7300, native_driver=True, cp1_driver=True,
            result_path='{evidence}/{prefix}cp1-keepalive-s7s14.json')) else 1
    finally:
        d.cleanup()


if __name__ == '__main__':
    raise SystemExit(main())
