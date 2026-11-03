"""R3 定向变异：实际断言失败才算击中，每项按 SHA256 恢复原字节。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'coverage/round2-final/mutations/round2_r3_mutations'
CASES = [
    ('slot-not-cleared', 'lib/src/context_state.dart',
     [('    nativeSlot = null;', '')], 'test/boundary/native_slot_boundary_test.dart'),
    ('slot-late-write', 'lib/src/context_internal.dart',
     [('    if (_state.nativeClosed) return;', '')], 'test/boundary/native_slot_boundary_test.dart'),
    ('slot-late-result', 'lib/src/context_internal.dart',
     [('if (!_state.nativeClosed) {', 'if (true) {')], 'test/boundary/native_slot_boundary_test.dart'),
    ('slot-identity-match', 'lib/src/context.dart',
     [('!identical(slot.response, result)', 'false')], 'test/unit/native_slot_test.dart'),
    ('cache-old-request', 'lib/src/plugins/cache.dart',
     [('        okField: r.ok,', "        '_request': r.request,\n        okField: r.ok,"),
      ('        request: ctx.request);', "        request: meta['_request'] as DiomanRequest? ?? ctx.request);")],
     'test/rule/cache_snapshot_rule_test.dart'),
    ('next-cancel-keeps-native', 'lib/src/pipeline.dart',
     [('if (cancelled != null) return ctx.observeNative(cancelled);',
       'if (cancelled != null) return cancelled;')], 'test/boundary/native_slot_boundary_test.dart'),
    ('next-patch-keeps-native', 'lib/src/pipeline.dart',
     [('return ctx\n                .observeNative(ctx.factory.internalError(ctx.request, e, s));',
       'return ctx.factory.internalError(ctx.request, e, s);')], 'test/boundary/native_slot_boundary_test.dart'),
    ('retry-after-multiple-values', 'lib/src/response.dart',
     [('values != null && values.length == 1 ? values.single : null',
       "source?.headers.value('retry-after')")], 'test/boundary/native_slot_boundary_test.dart'),
    ('cache-restore-internal', 'lib/src/plugins/cache.dart',
     [('if (_diomanCacheForbidden(restored)) return restored;', '')],
     'test/rule/cache_snapshot_rule_test.dart'),
    ('cache-clone-internal', 'lib/src/plugins/cache.dart',
     [('if (_diomanCacheForbidden(cached)) return cached;', '')],
     'test/rule/cache_snapshot_rule_test.dart'),
    ('cache-retry-after', 'lib/src/plugins/cache.dart',
     [('DiomanResponseInternal.setRetryAfter(restored, hit.retryAfter);', '')],
     'test/rule/cache_snapshot_rule_test.dart'),
    ('mock-retry-after', 'lib/src/response.dart',
     [("final values = source?.headers['retry-after'];", 'final values = <String>[];')],
     'test/combo/native_share_retry_combo_test.dart'),
    ('cache-null-code', 'lib/src/plugins/cache.dart',
     [('meta.containsKey(codeField) ? meta[codeField] : 0', 'meta[codeField] ?? 0')],
     'test/rule/cache_snapshot_rule_test.dart'),
    ('reject-native-closed-early', 'lib/src/client.dart',
     [('ctx.observeNative(result);\n      if (rejectFailure && !result.ok) {',
       'ctx.observeNative(result);\n      state.closeNative();\n      if (rejectFailure && !result.ok) {')],
     'test/boundary/native_slot_boundary_test.dart'),
    ('retry-reads-raw', 'lib/src/plugins/retry.dart',
     [('DiomanResponseInternal.retryAfter(r)?.trim()', "r.raw?.headers.value('retry-after')?.trim()")],
     'test/boundary/retry_boundary_test.dart'),
]


def run():
    """串行运行最低层用例，编译错误、空跑和超时均不计为击中。"""
    DEST.mkdir(parents=True, exist_ok=True)
    results = []
    for name, relative, changes, test in CASES:
        path = ROOT / relative
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        for old, new in changes:
            assert source.count(old) == 1, (name, old, source.count(old))
            source = source.replace(old, new)
        started = time.perf_counter()
        try:
            path.write_text(source, encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', '--concurrency=1', test,
                                   '--reporter=json', '--timeout=10s'],
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
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
        results.append(dict(mutation=name, source=relative, test=test,
                            failures=len(failures), seconds=round(time.perf_counter()-started, 3),
                            before_sha256=digest, restored_sha256=digest))
        (DEST / 'mutations.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        print(f'{name}: failures={len(failures)}; SHA256 restored; PASS', flush=True)


if __name__ == '__main__':
    run()
