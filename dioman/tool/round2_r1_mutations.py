"""R1 资源作用域变异：实际断言失败并按 SHA256 恢复源码。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/round2-r1-evidence'
CASES = [
    ('session-not-shared', 'plugins/auth', 'var session = _sessions[tokens];',
     '_AuthSession? session;', 'test/combo/auth_session_combo_test.dart', '轮换刷新凭证'),
    ('late-failure-clears', 'plugins/auth', 'if (session.owners == 0) return;',
     '', 'test/boundary/auth_lifecycle_boundary_test.dart', '迟到失败 keepOwner=false'),
    ('callback-identity', 'plugins/loading',
     'final _displays = <void Function(bool), _Display>{};',
     'final _displays = Map<void Function(bool), _Display>.identity();',
     'test/boundary/loading_resources_boundary_test.dart', '请求级 tear-off'),
    ('window-owner-not-transferred', 'plugins/loading', 'state.owner = this;',
     'state.owner ??= this;', 'test/boundary/loading_resources_boundary_test.dart', '隐藏窗口交接'),
]


def run():
    """加载失败和超时不算击中，大日志只留 coverage。"""
    DEST.mkdir(parents=True, exist_ok=True)
    logs = ROOT / 'coverage/r1-mutations'
    logs.mkdir(parents=True, exist_ok=True)
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
            (logs / f'{name}.jsonl').write_text(output, encoding='utf-8')
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
