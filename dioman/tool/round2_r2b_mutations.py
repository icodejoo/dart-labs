"""R2b 契约变异：只接受实际断言失败，每项以 SHA256 核对原字节恢复。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'coverage/r2b-mutations'
CASES = [
    ('retry-overflow-saturation', 'lib/src/plugins/retry.dart',
     'min(300 * pow(2.0, attempt - 1), _diomanMaxDelayMilliseconds)',
     '(300 * pow(2.0, attempt - 1))', 'test/unit/retry_delay_test.dart'),
    ('next-cancellation-scope', 'lib/src/pipeline.dart',
     'final cancelled = target.cancelled();', 'final cancelled = ctx.cancelled();',
     'test/combo/share_retry_cancel_combo_test.dart'),
    ('native-network-classification', 'lib/src/network_error_io.dart',
     'cause is SocketException || cause is HttpException || cause is TlsException',
     'false', 'test/unit/response_platform_test.dart'),
    ('deep-key-response-type', 'lib/src/key.dart',
     '      o.responseType.name,', '', 'test/unit/key_types_test.dart'),
    ('fast-key-response-type', 'lib/src/key.dart',
     'jsonEncode([_fastKey(request), request.responseType.name])',
     'jsonEncode([_fastKey(request)])', 'test/unit/key_types_test.dart'),
    ('cache-internal-veto', 'lib/src/plugins/cache.dart',
     'failureOf(r)?.kind != DiomanFailureKind.internal &&', '', 'test/rule/cache_veto_rule_test.dart'),
    ('cache-cancel-veto', 'lib/src/plugins/cache.dart',
     'failureOf(r)?.kind != DiomanFailureKind.cancel &&', '', 'test/rule/cache_veto_rule_test.dart'),
    ('retry-default-max', 'lib/src/plugins/retry.dart',
     'this.max = 2,', 'this.max = 0,', 'test/rule/retry_defaults_rule_test.dart'),
    ('retry-default-delay', 'lib/src/plugins/retry.dart',
     '300 * pow(2.0, attempt - 1)', '301 * pow(2.0, attempt - 1)', 'test/rule/retry_defaults_rule_test.dart'),
    ('retry-default-cap', 'lib/src/plugins/retry.dart',
     'this.delayMax = const Duration(seconds: 10)',
     'this.delayMax = const Duration(seconds: 11)', 'test/rule/retry_defaults_rule_test.dart'),
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
            proc = subprocess.run([shutil.which('dart'), 'test', test, '--reporter', 'json', '--timeout', '3s'],
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
