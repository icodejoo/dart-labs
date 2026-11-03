"""R2a 契约变异：只接受实际断言失败，每项以 SHA256 核对原字节恢复。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'coverage/round2-final/mutations/round2_r2a_mutations'
CONTRACT = 'test/rule/response_contract_rule_test.dart'
UNIT = 'test/unit/response_contract_test.dart'
CASES = [
    ('post-create-marker', 'lib/src/response.dart',
     'DiomanResponseInternal.mark(result, init._failure);', '', CONTRACT),
    ('retry-effective-status', 'lib/src/plugins/retry.dart',
     'o.statusCodes!.contains(ctx.statusOf(r))', 'o.statusCodes!.contains(r.status)', CONTRACT),
    ('retry-after-effective-status', 'lib/src/plugins/retry.dart',
     'o.afterStatusCodes!.contains(ctx.statusOf(r))', 'o.afterStatusCodes!.contains(r.status)', CONTRACT),
    ('auth-effective-status', 'lib/src/plugins/auth.dart',
     'status: ctx.statusOf(r)', 'status: r.status', CONTRACT),
    ('breaker-effective-status', 'lib/src/plugins/breaker.dart',
     'ctx.statusOf(r) >= 500', 'r.status >= 500', CONTRACT),
    ('parse-envelope-threshold', 'lib/src/response.dart',
     'body.containsKey(_codeField) &&', '', UNIT),
    ('callback-internal-boundary', 'lib/src/pipeline.dart',
     '\n      } catch (e, s) {\n        return ctx.observeNative(ctx.factory.internalError(ctx.request, e, s));',
     '\n      } catch (e, s) {\n        return ctx.observeNative(ctx.factory.normalize(ctx.request, error: e, stack: s));',
     'test/boundary/internal_callback_boundary_test.dart'),
    ('runner-classification', 'test/accept/lib/client.dart',
     'error.status < 200 || error.status >= 300', 'false', 'test/unit/accept_runner_test.dart'),
]


def run():
    """逐项运行最低层回归，不将加载失败或超时当成击中。"""
    DEST.mkdir(parents=True, exist_ok=True)
    results = []
    for name, relative, old, new, test in CASES:
        path = ROOT / relative
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        assert source.count(old) == 1, (name, source.count(old))
        started = time.perf_counter()
        try:
            path.write_text(source.replace(old, new), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', '--concurrency=1', test, '--reporter', 'json'],
                                  cwd=ROOT, capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=120)
            output = proc.stdout + proc.stderr
            (DEST / f'{name}.jsonl').write_text(output, encoding='utf-8')
            events = [json.loads(line) for line in proc.stdout.splitlines() if line.startswith('{')]
            failures = [e for e in events if e.get('type') == 'testDone'
                        and e.get('result') in ('failure', 'error')]
            assert proc.returncode != 0 and failures, name
            assert not any(s in output for s in ('Failed to load', 'Compilation failed', 'Test timed out')), name
        finally:
            path.write_bytes(original)
        restored = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == restored, name
        results.append(dict(mutation=name, source=relative, test=test,
                            failures=len(failures), seconds=round(time.perf_counter()-started, 3),
                            before_sha256=digest, restored_sha256=restored))
        (DEST / 'mutations.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        print(f'{name}: failures={len(failures)}; SHA256 restored; PASS', flush=True)


if __name__ == '__main__':
    run()
