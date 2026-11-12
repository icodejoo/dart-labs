"""只回拷INSTR工具/测试/证据，重读并定点追加共享文档；lib交付补丁不覆盖。"""

import hashlib
import json
import shutil
from pathlib import Path


SRC = Path('C:/ldq/luckdraw')
DST = Path('E:/workspaces/dart-labs/luckdraw')
OUT = SRC / 'tool/bench/results/pending2'


def digest(path):
    """返回文件原始字节SHA-256。"""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def append(path, addition):
    """一次读取核对后用单次append写入，保留共享文件已有字节。"""
    current = path.read_text(encoding='utf8')
    if '## INSTR 第五轮实际结果' in addition:
        assert '## INSTR 第五轮实际结果' not in current
    with path.open('a', encoding='utf8', newline='\n') as output:
        output.write(addition)


def main():
    """全部预检通过才开始拷贝；任何并行源冲突显式失败。"""
    original = json.loads(Path('C:/ldq/instr-baseline/real_hashes.json').read_text())
    paths = [
        'tool/bench/test_driver/perf_driver.dart', 'tool/bench/integration_test/bench_support.dart',
        'tool/bench/response_writer.dart', 'tool/bench/proc_cpu.dart', 'tool/bench/proc_cpu_sampler.dart',
        'tool/bench/proc_cpu_replay.dart', 'tool/bench/run_instr_device_checks.ps1',
        'tool/bench/analyze_instr.py', 'tool/bench/summarize_instr.py',
        'tool/bench/fixtures/proc_stat_android16.txt', 'tool/bench/fixtures/proc_threads_android16.txt',
        'tool/bench/fixtures/proc_buffered_android16.txt', 'test/tool/bench_instr_test.dart',
    ]
    for relative in paths:
        target = DST / relative
        key = str(Path(relative))
        if key in original:
            assert target.exists() and digest(target) == original[key], f'并行冲突: {relative}'
        else:
            assert not target.exists(), f'新文件已有同名目标: {relative}'
    assert not (DST / 'tool/bench/results/pending2').exists(), '目标证据目录已存在，拒绝覆盖'
    for relative in paths:
        target = DST / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(SRC / relative, target)
    shutil.copytree(OUT, DST / 'tool/bench/results/pending2')
    copied = paths + [p.relative_to(SRC).as_posix() for p in OUT.rglob('*') if p.is_file()]
    sections = json.loads((OUT / 'validation/document_sections.json').read_text(encoding='utf8'))
    shared = []
    for relative, addition in sections.items():
        target = DST / relative
        # 共享文件必须在实际写入前重读；不使用副本旧正文。
        current = target.read_bytes().decode('utf8')
        assert 'INSTR（2026-11-11，副本候选实现）' not in current and 'INSTR (2026-11-11, isolated candidate)' not in current
        if relative.startswith('README'):
            heading = '## Performance' if relative == 'README.md' else '## 性能'
            anchor = heading + ('\r\n' if heading + '\r\n' in current else '\n')
            assert current.count(anchor) == 1
            target.write_bytes(current.replace(anchor, anchor + addition, 1).encode('utf8'))
        elif relative.endswith('TEST_STRATEGY.md'):
            marker = '## 8. 摇树验证（需求 6）'
            assert current.count(marker) == 1 and '### 7.8 INSTR' not in current
            target.write_bytes(current.replace(marker, addition + '\n' + marker, 1).encode('utf8'))
        else:
            with target.open('a', encoding='utf8', newline='\n') as output:
                output.write(addition)
        shared.append({'path': relative, 'change': '定点插入性能小节' if relative.startswith('README') else '追加INSTR，不覆盖已有正文'})
    # 核心测试与COV-02必须随核心补丁合并，当前真实仓库不登记尚不存在的核心测试。
    extra = Path('C:/ldq/instr-acceptance-append.md').read_text(encoding='utf8')
    rows = [line for line in extra.splitlines() if line.startswith('| INSTR-') and 'test/core/text/instr_text_equivalence_test.dart ::' not in line]
    matrix = '\n## 需求和不变量\n\n### INSTR 第五轮（工具与真机；核心追加随补丁）\n\n| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |\n| --- | --- | --- | --- | --- | --- |\n' + '\n'.join(rows) + '\n'
    target = DST / 'test/ACCEPTANCE.md'
    current = target.read_bytes()
    assert b'INSTR-01' not in current
    with target.open('a', encoding='utf8', newline='\n') as output:
        output.write(matrix)
    assert target.read_bytes().startswith(current)
    shared.append({'path': 'test/ACCEPTANCE.md', 'change': f'仅追加{len(rows)}行；核心2行和COV-02留待补丁合并'})
    for relative in ('tool/bench/budgets.json', 'tool/bench/budgets.status.json'):
        target = DST / relative
        current = json.loads(target.read_text(encoding='utf-8-sig'))
        proposed = json.loads((SRC / relative).read_text(encoding='utf8'))
        if relative.endswith('budgets.status.json'):
            assert 'instr' not in current
            current['instr'] = proposed['instr']
            current['status'] += '；INSTR最新候选结果见instr，CPU及库合并仍有未完成项'
        else:
            marker = ' INSTR 有效增量与原4ms差距另见 budgets.status.json.instr；不是绝对首帧达标。'
            assert marker not in current['wheel_first_frame']['reason']
            current['wheel_first_frame']['reason'] += marker
        target.write_text(json.dumps(current, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
        shared.append({'path': relative, 'change': '重读后仅更新INSTR字段或reason，不放宽已有门槛'})
    manifest = {'copied': [{'path': p, 'sha256': digest(DST / p)} for p in copied],
                'shared': shared, 'lib_copied': False,
                'deferred': ['C:/ldq/core_patch.diff', 'C:/ldq/gameplay_patch.diff', 'C:/ldq/core_acceptance_append.md']}
    for root in (OUT, DST / 'tool/bench/results/pending2'):
        (root / 'validation/copy_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print('copied', len(copied), 'files; shared', len(shared), '; lib deferred as patches')


if __name__ == '__main__':
    main()
