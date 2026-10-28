"""B4 定向变异，失败必须来自运行时断言，finally 恢复原字节并核对哈希。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b4-evidence'
CASES = [('share-leave-listener',
  'context',
  'state.listeners.remove(cancel);',
  '',
  'test/boundary/source_boundary_test.dart',
  '首发取消不连累跟随者'),
 ('share-leader-dio-timeout',
  'plugins/share',
  'connectTimeout: Duration.zero',
  'connectTimeout: const Duration(seconds: 3)',
  'test/boundary/source_boundary_test.dart',
  '首发三个 Dio 超时清零'),
 ('share-policy-table',
  'plugins/share',
  'final table = tables[o.policy]!;',
  'final table = tables[DiomanSharePolicy.start]!;',
  'test/boundary/source_boundary_test.dart',
  '同 key 四策略互不读取'),
 ('cache-failure-write',
  'plugins/cache',
  'o.shouldStore?.call(r) ?? r.ok',
  'o.shouldStore?.call(r) ?? true',
  'test/rule/source_rule_test.dart',
  'business 失败不存储'),
 ('cache-clear-generation',
  'plugins/cache',
  'floor = sequence;',
  'floor = 0;',
  'test/boundary/source_boundary_test.dart',
  'clear 作废在途写入'),
 ('cache-barrier-reclaim',
  'plugins/cache',
  'if (--barrier.pending == 0) barriers.remove(key);',
  'barrier.pending--;',
  'test/boundary/source_boundary_test.dart',
  'clear 作废在途写入'),
 ('mock-probe-cache-marker',
  'plugins/mock',
  'ctx.set(sourceProbe, true);',
  'ctx.set(sourceProbe, false);',
  'test/combo/source_combo_test.dart',
  '探测不缓存不共享'),
 ('mock-replayable', 'plugins/mock', 'ctx.markReplayable();', '', 'test/combo/source_combo_test.dart', '每次尝试探测回落且 I7'),
 ('offline-timeout-timer-cleanup',
  'context',
  'timer?.cancel();',
  '',
  'test/boundary/source_boundary_test.dart',
  'timeout cancel flush dispose'),
 ('offline-queue-evict-oldest',
  'plugins/offline',
  "queue.removeFirst().ready.complete(_queueFullReason);",
  "queue.removeLast().ready.complete(_queueFullReason);",
  'test/boundary/source_boundary_test.dart',
  '队满挤出最早'),
 ('cache-old-response-after-evict',
  'plugins/cache',
  'ticket > floor && ticket > barrier.latest',
  'ticket > floor',
  'test/boundary/source_boundary_test.dart',
  '新结果淘汰后旧在途不得回写'),
 ('share-shared-state-retain',
  'plugins/share',
  'ctx.state.retain();',
  '',
  'test/combo/source_combo_test.dart',
  '首发离场仍等恢复'),
 ('review-mock-query',
  'plugins/mock',
  '$path$query',
  '$path',
  'test/boundary/source_review_boundary_test.dart',
  '自审：path 内嵌'),
 ('review-cache-status',
  'plugins/cache',
  'final meta = saved[resultField];',
  "final meta = saved['missing'];",
  'test/boundary/source_review_boundary_test.dart',
  '自审：显式缓存失败'),
 ('review-offline-disposed',
  'plugins/offline',
  '    if (disposed) {\n'
  '      ctx.set(cancellationFailure, _disposedFailure);\n'
  '      return ctx.fail(_disposedFailure);\n'
  '    }\n',
  '',
  'test/boundary/source_review_boundary_test.dart',
  '自审：旧链晚到'),
 ('cache-write-snapshot',
  'plugins/cache',
  'clone(ctx, r, o.clone!),',
  'r,',
  'test/boundary/cache_persist_boundary_test.dart',
  '写入快照隔离来源'),
 ('share-retry-replayable',
  'plugins/share',
  'if (o.policy == DiomanSharePolicy.retry) ctx.markReplayable();',
  '',
  'test/boundary/share_replay_boundary_test.dart',
  '内部重放独立保护 I7')]

CASES += [('final-share-minimum-timeout',
  'plugins/share',
  '  Duration? timeout(DiomanRequest request) {\n'
  '    var total = Duration.zero;\n'
  '    for (final stage in [\n'
  '      request.connectTimeout,\n'
  '      request.receiveTimeout,\n'
  '      if (request.data != null) request.sendTimeout\n'
  '    ]) {\n'
  '      if (stage == null || stage <= Duration.zero) return null;\n'
  '      total += stage;\n'
  '    }\n'
  '    return total;\n'
  '  }\n'
  '\n',
  '  Duration? timeout(DiomanRequest request) {\n'
  '    Duration? value;\n'
  '    for (final t in [request.connectTimeout, request.receiveTimeout, request.sendTimeout]) '
  '{\n'
  '      if (t != null && t > Duration.zero && (value == null || t < value)) value = t;\n'
  '    }\n'
  '    return value;\n'
  '  }\n'
  '\n',
  'test/boundary/b4_final_review_boundary_test.dart',
  '连接五秒接收三十秒'),
 ('final-offline-online-callback',
  'plugins/offline',
  '        config.isOnline() ||\n        !(o.shouldQueue?.call(ctx.request) ?? true)',
  '        !(o.shouldQueue?.call(ctx.request) ?? true) ||\n        config.isOnline()',
  'test/boundary/b4_final_review_boundary_test.dart',
  '在线直接放行且不调用')]


def run():
    """逐项运行指定回归，拒绝编译错误冒充变异被杀死。"""
    DEST.mkdir(parents=True, exist_ok=True)
    results = []
    for name, module, old, new, test, title in CASES:
        path = ROOT / f'lib/src/pipeline/{module}.dart'
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        assert old in source, (name, old)
        try:
            path.write_text(source.replace(old, new), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', test, '--name', title,
                                   '--reporter', 'expanded', '--timeout', '3s'],
                                  cwd=ROOT, capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=45)
            output = proc.stdout + proc.stderr
            (DEST / f'{name}.txt').write_text(output, encoding='utf-8')
            assert proc.returncode != 0 and '[E]' in output and 'Some tests failed' in output, name
            assert 'Failed to load' not in output and 'Compilation failed' not in output, name
        finally:
            path.write_bytes(original)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
        results.append(dict(mutation=name, test=test, title=title, killed=True, restored_sha256=digest))
        (DEST / 'mutations.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        print(f'{name}: test failed; source restored; PASS', flush=True)
    assert len(results) == 19
    print('19/19 mutations killed (original 17/17 + final review 2/2); all source hashes restored', flush=True)


if __name__ == '__main__':
    run()
