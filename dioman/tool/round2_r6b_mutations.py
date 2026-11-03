"""截止时间的定向变异，串行验证断言失败并按 SHA256 恢复。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'coverage/round2-r6b-mutations'
TEST = 'test/boundary/deadline_boundary_test.dart'


def main():
    """验证失败类别、计时清理与共享归属，编译或超时失败不算击中。"""
    OUT.mkdir(parents=True, exist_ok=True)
    originals = {p: p.read_bytes() for p in (ROOT / 'lib').rglob('*.dart')}
    cases = [
        ('deadline-becomes-cancel', 'lib/src/context.dart',
         "? fail(DiomanFailureKind.timeout, reason: 'deadline')",
         "? fail(DiomanFailureKind.cancel, reason: 'deadline')"),
        ('deadline-timer-leaks', 'lib/src/client.dart',
         '      deadlineTimer?.cancel();', ''),
        ('follower-aborts-shared-transport', 'lib/src/plugins/share.dart',
         '      if (--entry.subscribers == 0) {',
         '      if (ctx.state.deadlineExpired) entry.token.cancel();\n'
         '      if (--entry.subscribers == 0) {'),
    ]
    results = []
    for name, relative, before, after in cases:
        path = ROOT / relative
        original = originals[path]
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        assert source.count(before) == 1, name
        try:
            path.write_text(source.replace(before, after), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', '--concurrency=1',
                                   TEST, '--reporter=json'], cwd=ROOT,
                                  capture_output=True, text=True, encoding='utf-8',
                                  errors='replace', timeout=180)
            output = proc.stdout + proc.stderr
            (OUT / f'{name}.jsonl').write_text(output, encoding='utf-8')
            events = [json.loads(line) for line in proc.stdout.splitlines()
                      if line.startswith('{')]
            failures = [event for event in events if event.get('type') == 'testDone'
                        and event.get('result') in ('failure', 'error')]
            assert proc.returncode != 0 and failures, name
            assert not any(value in output for value in
                           ('Failed to load', 'Compilation failed', 'Test timed out')), name
        finally:
            path.write_bytes(original)
            assert all(p.read_bytes() == value for p, value in originals.items()), name
        results.append(dict(mutation=name, failures=len(failures),
                            before_sha256=digest, restored_sha256=digest))
        (OUT / 'mutations.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
        print(f'{name}: assertion failure; SHA256 restored', flush=True)


if __name__ == '__main__':
    main()
