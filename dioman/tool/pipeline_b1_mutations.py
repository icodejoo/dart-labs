"""B1 定向变异：每次只改新内核文件，失败后 finally 恢复并核对 SHA256。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b1-evidence'
CASES = [
    ('wait-cleanup', 'context', 'timer?.cancel();', '/* mutation: timer not cancelled */',
     'test/unit/context_test.dart', '正常值、异常、超时'),
    ('already-cancelled', 'context', 'if (isCancelled) {', 'if (false) {',
     'test/unit/context_test.dart', '已取消立即返回'),
    ('layer-boundary', 'pipeline', 'kind: DiomanKind.internal', 'kind: DiomanKind.offline',
     'test/unit/pipeline_test.dart', '中间件异常转 internal'),
    ('settlement', 'client', 'if (!result.ok) throw', 'if (false) throw',
     'test/rule/client_rule_test.dart', '九格落定'),
    ('patch-headers', 'request', 'h.removeWhere((k, _) => k.toLowerCase() == key.toLowerCase());', '/* mutation: header deletion omitted */',
     'test/unit/request_options_test.dart', '合并、大小写删除'),
    ('factory-classification', 'response', 'code == 0', 'code == 1',
     'test/unit/response_test.dart', '终审识别'),
    ('pending-unregister', 'client', '_pending.remove(state);', '/* mutation: pending leaked */',
     'test/boundary/client_boundary_test.dart', '登记后 compose'),
    ('replay-clone-I7', 'transport', 'options.data = _clone(options.data, ctx.log);', 'options.data = options.data;',
     'test/rule/transport_rule_test.dart', 'I7 嵌套请求体'),
    ('review-original-stack', 'response', 'errorStack: error is DioException\n                ? error.stackTrace\n                : stack ?? StackTrace.current,', 'errorStack: stack ?? StackTrace.current,',
     'test/rule/transport_rule_test.dart', 'reject 的 bug 保留原始对象'),
    ('internal-over-cancel', 'client', 'if (result.kind != DiomanKind.internal) {', 'if (true) {',
     'test/boundary/client_boundary_test.dart', '同时取消不掩盖'),
]


def run():
    """逐项执行，不允许编译失败冒充杀死变异，保存失败标题及恢复哈希。"""
    DEST.mkdir(parents=True, exist_ok=True)
    dart = shutil.which('dart')
    results = []
    for name, module, old, new, test, title in CASES:
        path = ROOT / f'lib/src/pipeline/{module}.dart'
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        text = original.decode('utf-8').replace('\r\n', '\n')
        assert old in text, (name, old)
        try:
            path.write_text(text.replace(old, new), encoding='utf-8')
            command = [dart, 'test', test, '--name', title, '--reporter', 'expanded', '--timeout', '5s']
            proc = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                  encoding='utf-8', errors='replace', timeout=60)
            output = proc.stdout + proc.stderr
            (DEST / (name + '.txt')).write_text(output, encoding='utf-8')
            assert proc.returncode != 0 and '[E]' in output and 'Some tests failed' in output, name
            assert 'Failed to load' not in output and 'Compilation failed' not in output, name
        finally:
            path.write_bytes(original)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
        results.append({'mutation': name, 'test': test, 'title': title, 'killed': True,
                        'restored_sha256': digest})
        print(name + ': test failed; source restored; PASS', flush=True)
    (DEST / 'mutations.json').write_text(json.dumps(results, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


if __name__ == '__main__':
    run()
