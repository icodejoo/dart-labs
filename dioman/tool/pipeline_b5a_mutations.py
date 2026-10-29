"""只跑 powerset 的七项变异，按 JSON testDone 事件统计实际失败条数。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b5b-evidence'
TEST = 'test/combo/powerset_combo_test.dart'
CASES = [
    ('leave-listener', 'context', 'state.listeners.remove(cancel);', ''),
    ('loading-close', 'plugins/loading', 'fn(visible);', 'if (visible) fn(visible);'),
    ('notify-double', 'plugins/notify',
     'if (text.isNotEmpty) config.notify(text, result);',
     'if (text.isNotEmpty) { config.notify(text, result); config.notify(text, result); }'),
    ('auth-singleflight', 'plugins/auth',
     'return _refreshing ??= (() async {', 'return (() async {'),
    ('retry-replayable', 'plugins/retry', 'ctx.markReplayable();', ''),
    ('cache-barrier', 'plugins/cache',
     'if (--barrier.pending == 0) barriers.remove(key);', 'barrier.pending--;'),
    ('mock-replayable', 'plugins/mock', 'ctx.markReplayable();', ''),
]


def run():
    """逐项原字节恢复，不把编译、加载错误或超时当成击中。"""
    results = []
    for name, module, old, new in CASES:
        path = ROOT / f'lib/src/{module}.dart'
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        assert source.count(old) == 1, (name, source.count(old))
        start = time.perf_counter()
        try:
            path.write_text(source.replace(old, new), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', TEST,
                                   '--reporter', 'json', '--timeout', '10s'],
                                  cwd=ROOT, capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=120)
            output = proc.stdout + proc.stderr
            (DEST / f'mutation-{name}.jsonl').write_text(output, encoding='utf-8')
            events = [json.loads(s) for s in proc.stdout.splitlines() if s.startswith('{')]
            failures = [e for e in events if e.get('type') == 'testDone'
                        and e.get('result') in ('failure', 'error')]
            tests = {e['test']['id']: e['test']['name'] for e in events if e.get('type') == 'testStart'}
            powerset = [e for e in failures if ' mask=' in tests[e['testID']]]
            assert proc.returncode != 0 and powerset, name
            assert not any(s in output for s in ('Failed to load', 'Compilation failed',
                                                  'Test timed out')), name
        finally:
            path.write_bytes(original)
        restored = hashlib.sha256(path.read_bytes()).hexdigest()
        assert restored == digest, name
        results.append(dict(mutation=name, source=str(path.relative_to(ROOT)),
                            test=TEST, failures=len(failures), powerset_failures=len(powerset),
                            baseline_failures=len(failures)-len(powerset),
                            seconds=round(time.perf_counter()-start, 3),
                            before_sha256=digest, restored_sha256=restored))
        (DEST / 'mutations.json').write_text(json.dumps(results, ensure_ascii=False,
                                                      indent=2)+'\n', encoding='utf-8')
        print(f'{name}: powerset failures={len(powerset)}; source restored; PASS', flush=True)


if __name__ == '__main__':
    run()
