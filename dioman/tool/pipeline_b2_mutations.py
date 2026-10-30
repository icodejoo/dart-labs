"""B2 定向变异：每次只改新内核文件，失败后 finally 恢复并核对 SHA256。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b2-evidence'
CASES = [('review-url-authority', 'plugins/repath', r'://[^/?#]*', r'://[^/]*', 'test/boundary/stateless_prepare_boundary_test.dart', '无路径绝对 URL'), ('loading-count', 'plugins/loading', '++state.count == 1', '++state.count == 2', 'test/rule/stateless_outer_rule_test.dart', '同回调并发聚合'), ('notify-final', 'plugins/notify', 'if (text.isNotEmpty) config.notify(text, result);', 'if (text.isEmpty) config.notify(text, result);', 'test/rule/stateless_outer_rule_test.dart', '默认忽略成功'), ('repath-consume', 'plugins/repath', 'removeQuery: usedQuery', 'removeQuery: const {}', 'test/rule/stateless_prepare_rule_test.dart', '三语法'), ('filter-nan', 'plugins/filter', '(value is num && value.isNaN)', 'false', 'test/rule/stateless_prepare_rule_test.dart', 'C9'), ('timeout-patch', 'plugins/timeout', 't.receive ?? ctx.request.receiveTimeout', 'ctx.request.receiveTimeout', 'test/rule/stateless_prepare_rule_test.dart', '按档并集'), ('envs-clone', 'config', 'MapEntry(k, cloneDiomanConfig(v))', 'MapEntry(k, v)', 'test/boundary/envs_boundary_test.dart', '写前深克隆'), ('internal-fallback', 'client', "result.error ?? StateError('internal result without error')", 'result.error!', 'test/boundary/internal_settlement_boundary_test.dart', '缺 error'), ('extend-precedence', 'client', 'if (options != null) mergeDiomanOptions(child.dio.options, options);', 'if (false) mergeDiomanOptions(child.dio.options, options!);', 'test/combo/stateless_combo_test.dart', '先 setup 再显式覆盖')]


def run():
    """逐项执行，不允许编译失败冒充杀死变异，保存失败标题及恢复哈希。"""
    DEST.mkdir(parents=True, exist_ok=True)
    dart = shutil.which('dart')
    results = []
    for name, module, old, new, test, title in CASES:
        path = ROOT / f'lib/src/{module}.dart'
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
