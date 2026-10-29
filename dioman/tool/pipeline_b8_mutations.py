"""B8 六项变异：断言实际失败、无加载失败、原字节恢复。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b8-evidence'
CASES = [
    ('1-share-withdrawal', 'plugins/share', 'entry.candidates.remove(sequence);',
     'entry.candidates[sequence] = ctx.fail(const DiomanFailure(kind: DiomanKind.cancel));',
     'test/combo/b8_share_withdrawal_test.dart', 'DiomanSharePolicy.end latest timeout=false'),
    ('2-byte-key', 'key', '[data.length, hash, base64Encode(data)]', '[data.length]',
     'test/unit/b8_core_test.dart', 'B8 安全内容键'),
    ('3-auth-session', 'plugins/auth',
     'if (_tokens.accessToken != snapshot) return true;',
     'if (_tokens.accessToken != snapshot) return false;',
     'test/rule/b8_regression_test.dart', 'B8 刷新异常遇到新登录'),
    ('4-retry-after-limit', 'plugins/retry',
     'this.retryAfterMax = const Duration(seconds: 60)',
     'this.retryAfterMax = const Duration(seconds: 59)',
     'test/rule/b8_regression_test.dart', 'B8 服务端等待超限'),
    ('5-cache-cancel', 'plugins/cache', 'return ctx.cancelled() ?? result;',
     'return result;', 'test/rule/b8_regression_test.dart', 'B8 命中返回边界'),
    ('6-one-shot', 'plugins/retry', 'if (!ctx.canReplay()) return r;', '',
     'test/rule/b8_regression_test.dart', 'B8 一次性体 retry'),
]


def run():
    results = []
    for name, module, old, new, test, pattern in CASES:
        path = ROOT / f'lib/src/{module}.dart'
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8')
        assert old in source, name
        try:
            path.write_text(source.replace(old, new), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', test, '--name', pattern,
                                   '--reporter', 'json', '--timeout', '8s'], cwd=ROOT,
                                  capture_output=True, encoding='utf-8', errors='replace', timeout=90)
            output = proc.stdout + proc.stderr
            (DEST / f'mutation-{name}.jsonl').write_text(output, encoding='utf-8')
            events = [json.loads(s) for s in proc.stdout.splitlines() if s.startswith('{')]
            failures = [e for e in events if e.get('type') == 'testDone'
                        and e.get('result') in ('failure', 'error')]
            assert failures and proc.returncode != 0, name
            assert not any(s in output for s in ['Failed to load', 'Compilation failed', 'Test timed out']), name
        finally:
            path.write_bytes(original)
        restored = hashlib.sha256(path.read_bytes()).hexdigest()
        assert restored == digest
        results.append(dict(mutation=name, failures=len(failures), test=test,
                            before_sha256=digest, restored_sha256=restored))
        (DEST / 'mutations.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
        print(f'{name}: {len(failures)} failures; SHA256 restored', flush=True)


if __name__ == '__main__':
    run()
