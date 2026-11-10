"""在副本完成轻量门禁，只回拷授权结果和文档追加内容。"""

import hashlib
import json
from pathlib import Path
import shutil
import subprocess as sp

ROOT = Path(__file__).resolve().parent
COPY = ROOT.parents[4]
REAL = Path(r'E:\workspaces\dart-labs\luckdraw')
DART = r'E:\sdk\flutter\bin\dart.bat'


def dump(path, value):
    """保存本批核验结果，使用 LF。"""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n',
                    encoding='utf-8', newline='\n')


def command(name, args):
    """在副本串行执行轻量检查并保留真实输出。"""
    result = sp.run(args, cwd=COPY, capture_output=True, timeout=300)
    output = (result.stdout + result.stderr).decode('utf-8', errors='replace').replace('\r\n', '\n')
    (ROOT / f'{name}.log').write_text(output, encoding='utf-8', newline='\n')
    print(name, 'exit=', result.returncode, '\n', '\n'.join(output.splitlines()[-3:]), flush=True)
    return dict(command=args, exitCode=result.returncode, output=output)


def main():
    """追加矩阵、检查、核对源码与设置，最后按白名单回拷。"""
    assert COPY == Path(r'C:\ldp\luckdraw'), COPY
    results = {}
    for rel, fragment in [('docs/AB_REPORT.md', 'report_append.md'),
                          ('test/ACCEPTANCE.md', 'acceptance_append.md')]:
        text = (COPY / rel).read_text(encoding='utf-8')
        if '\n## Skia 对照（AB2）' in text or '\n## AB2 Skia 与 Impeller GLES 对照' in text:
            raise RuntimeError('拒绝重复追加')
        addition = (ROOT / fragment).read_text(encoding='utf-8')
        with (COPY / rel).open('a', encoding='utf-8', newline='\n') as file:
            file.write(addition)
    for name, args in [
        ('format_apply', [DART, 'format', 'lib', 'test', 'tool']),
        ('format_gate', [DART, 'format', '--output=none', '--set-exit-if-changed', 'lib', 'test', 'tool']),
        ('imports_gate', [DART, 'tool/check_imports.dart']),
        ('acceptance_gate', [DART, 'tool/check_acceptance.dart']),
        ('coverage_gate_historical', [DART, 'tool/coverage.dart', '--min=100', '--lcov=coverage/PERF.lcov']),
    ]:
        results[name] = command(name, args)
    dump(ROOT / 'gates.json', results)
    if any(r['exitCode'] for r in results.values()):
        raise RuntimeError('门禁失败，先检查，不复制半成品')
    before = json.loads((ROOT / 'real_source_hashes_before.json').read_text(encoding='utf-8'))
    after = {name: hashlib.sha256((REAL/name).read_bytes()).hexdigest() for name in before}
    verification = dict(files=len(after), unchanged=before == after,
                        changed=[name for name in after if before[name] != after[name]])
    dump(ROOT / 'real_source_verification.json', verification)
    if not verification['unchanged']:
        raise RuntimeError('真实仓库源码已变化，先保留证据')
    notes = ['\n### AB2实际门禁输出\n',
             '- analyze / flutter test / pub get / build：按AB2禁令未运行；'
             '真实profile集成测试为同名用例六轮，6/6有效通过。',
             '- 使用Dart直接执行门禁，避免`dart run`潜在隐式pub；'
             '覆盖率仅复核既有`coverage/PERF.lcov`，并非AB2新采集。']
    for name, result in results.items():
        output = result['output'].splitlines()
        excerpt = ' / '.join(output[-2:])
        notes.append(f'- `{name}`：exit={result["exitCode"]}；{excerpt}')
    source_check = json.loads((ROOT / 'source_verification.json').read_text(encoding='utf-8'))
    notes += [f'- 副本源码/配置/APK共{source_check["files"]}份哈希全部未变；'
              f'真实仓库lib {verification["files"]}份哈希未变。'
              '副本与真实源码文本一致（3份文件仅换行字节不同），不拷回源码。\n']
    log = command('git_log_final', ['git', '-C', r'E:\workspaces\dart-labs', 'log', '--oneline', '-2'])
    notes += ['最终git log（本批未add/commit/push）：\n', f'```text\n{log["output"].rstrip()}\n```\n']
    gate_append = '\n'.join(notes)
    with (ROOT / 'report_append.md').open('a', encoding='utf-8', newline='\n') as file:
        file.write(gate_append)
    with (COPY / 'docs/AB_REPORT.md').open('a', encoding='utf-8', newline='\n') as file:
        file.write(gate_append)
    copied = {}
    for rel, fragment in [('docs/AB_REPORT.md', 'report_append.md'),
                          ('test/ACCEPTANCE.md', 'acceptance_append.md')]:
        target = REAL / rel
        original = target.read_bytes()
        addition = (ROOT / fragment).read_bytes()
        if b'## Skia ' in original and rel.endswith('AB_REPORT.md') or b'## AB2 ' in original:
            raise RuntimeError('真实仓库已包含AB2，拒绝重复追加')
        combined = original + addition
        # 用当前真实文件作为前缀，保留其它会话可能已追加的内容。
        (COPY / rel).write_bytes(combined)
        target.write_bytes(combined)
        assert target.read_bytes()[:len(original)] == original
        copied[rel] = dict(originalBytes=len(original), appendedBytes=len(addition),
                          prefixPreserved=True, sha256=hashlib.sha256(combined).hexdigest())
    dump(ROOT / 'copy_verification.json', copied)
    destination = REAL / ROOT.relative_to(COPY)
    if destination.exists():
        raise RuntimeError('目标结果目录已存在，拒绝合并覆盖')
    shutil.copytree(ROOT, destination, ignore=shutil.ignore_patterns('__pycache__'))
    checks = [p for p in ROOT.rglob('*') if p.is_file() and '__pycache__' not in p.parts]
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() ==
               hashlib.sha256((destination / p.relative_to(ROOT)).read_bytes()).hexdigest()
               for p in checks)
    print('COPY VERIFIED:', len(checks), 'artifact files; docs/ACCEPTANCE append-only', flush=True)


if __name__ == '__main__':
    main()
