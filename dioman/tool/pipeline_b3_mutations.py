"""B3 定向变异，失败必须来自运行时断言，finally 恢复原字节并核对哈希。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b3-evidence'
CASES = [
    ('final-auth-ready-exhausted', 'auth', 'if (current == token) break;', "if (current == token) break;\n        if (i == DiomanAuth.readyStableAttempts - 1) throw StateError('unstable');", 'test/boundary/auth_boundary_test.dart', '三次都不稳定以最后快照发出'),
    ('final-breaker-retryable-at', 'breaker', 'return b.openedAt!.add(b.resetDuration);', 'return b.openedAt!.add(config.resetDuration);', 'test/boundary/breaker_boundary_test.dart', '保存开启时请求冷却'),
    ('migration-auth-force-protection', 'auth', '(o.enabled != true && o.isProtected?.call(ctx.request) == false)', 'o.isProtected?.call(ctx.request) == false', 'test/boundary/b3_options_boundary_test.dart', 'true 强制保护优先'),
    ('retry-replayable', 'retry', 'ctx.markReplayable();', '', 'test/combo/b3_combo_test.dart', 'Transformer 原地修改'),
    ('auth-replayable', 'auth', 'ctx.markReplayable();', '', 'test/combo/b3_combo_test.dart', 'Transformer 原地修改'),
    ('auth-recheck-credentials', 'auth', 'if (!_hasToken) {', 'if (!_hasToken && !replayed) {', 'test/boundary/auth_boundary_test.dart', '刷新成功后登出'),
    ('auth-ready-snapshot', 'auth', 'if (current == token) break;', 'if (true) break;', 'test/boundary/auth_boundary_test.dart', 'ready 期间换 token'),
    ('auth-cancel-after-failure', 'auth', 'if (cancelledAfterFailure != null) return cancelledAfterFailure;', '', 'test/boundary/auth_boundary_test.dart', 'ready 与 onFailure 异步返回后'),
    ('breaker-cancel-failure', 'breaker', 'if (cancelled != null || r.kind == DiomanKind.cancel) return cancelled ?? r;', '''if (cancelled != null || r.kind == DiomanKind.cancel) {
      b.failures++;
      if (b.failures >= o.failureThreshold!) {
        b.openedAt = _now(ctx);
        _transition(ctx, key, b, DiomanBreakerState.open);
      }
      return cancelled ?? r;
    }''', 'test/boundary/breaker_boundary_test.dart', 'cancel 只归还名额'),
    ('retry-logical-status', 'retry', 'o.statusCodes!.contains(r.status)', 'o.statusCodes!.contains(r.httpStatus)', 'test/rule/retry_rule_test.dart', 'HTTP 与 business 逻辑状态全表'),
    ('retry-max-boundary', 'retry', 'attempt <= o.max!', 'attempt < o.max!', 'test/rule/retry_rule_test.dart', 'HTTP 与 business 逻辑状态全表'),
    ('retry-method-veto', 'retry', '.contains(ctx.request.method.toUpperCase())', '.contains("GET")', 'test/rule/retry_rule_test.dart', '成功也交判定'),
    ('auth-stale-session', 'auth', 'if (_hasToken && current != session) return;', '', 'test/boundary/auth_boundary_test.dart', '旧请求的 expired'),
    ('auth-expiry-dedup', 'auth', 'if (!_hasToken && session == _expiredSession) return;', '', 'test/boundary/b3_await_boundary_test.dart', '同会话多个在途'),
    ('breaker-generation', 'breaker', 'if (generation != b.generation)', 'if (false)', 'test/boundary/breaker_boundary_test.dart', '真实取消探测释放槽位'),
    ('review-ready-wait', 'auth', '''await ctx.wait(Future<RequestPatch>.sync(
                () => o.ready!(_tokens, ctx.request)))''', 'await o.ready!(_tokens, ctx.request)', 'test/boundary/b3_await_boundary_test.dart', '取消未完成的 ready'),
    ('review-failure-wait', 'auth', '''await ctx.wait(Future<DiomanAuthFailureAction>.sync(
              () => o.onFailure!(r, _tokens)))''', 'await o.onFailure!(r, _tokens)', 'test/boundary/b3_await_boundary_test.dart', '取消未完成的 ready'),
    ('review-notice-wait', 'auth', 'await ctx.wait(_notice(ctx, o.onAccessDenied ?? o.onAccessExpired!, r));', 'await _notice(ctx, o.onAccessDenied ?? o.onAccessExpired!, r);', 'test/boundary/b3_await_boundary_test.dart', '取消未完成的 ready'),
]


def run():
    """逐项运行指定回归，拒绝编译错误冒充变异被杀死。"""
    DEST.mkdir(parents=True, exist_ok=True)
    results = []
    for name, module, old, new, test, title in CASES:
        path = ROOT / f'lib/src/plugins/{module}.dart'
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


if __name__ == '__main__':
    run()
