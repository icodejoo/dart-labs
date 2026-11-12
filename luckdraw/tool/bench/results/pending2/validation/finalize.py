"""追加真实仓库复验和最终手机实测，刷新完整路径清单，不覆盖共享历史。"""

import hashlib
import json
import re
import shutil
from pathlib import Path


SRC = Path('C:/ldq/luckdraw')
DST = Path('E:/workspaces/dart-labs/luckdraw')
REL = Path('tool/bench/results/pending2')


def read(path):
    """读取实际保存的JSON证据。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def append(path, text, marker):
    """重读后一次追加；同一收尾不重复写入。"""
    current = path.read_text(encoding='utf8')
    assert marker not in current
    with path.open('a', encoding='utf8', newline='\n') as output:
        output.write(text)


def main():
    """只整理已经完成的真实命令输出，不生成虚拟通过记录。"""
    cv, rv = SRC / REL / 'validation', DST / REL / 'validation'
    for path in rv.glob('real_*'):
        if path.is_file():
            shutil.copy2(path, cv / path.name)
    for name in ('final_process_check.json', 'patch_check.json', 'plan_only.json'):
        shutil.copy2(cv / name, rv / name)
    shutil.copy2(Path(__file__), rv / Path(__file__).name)
    device = read(cv / 'device_final.json')
    result = read(rv / 'real_validation_summary.json')
    assert result['tools_passed'] == 223 and result['failed'] == result['skipped'] == 0
    command_names = ['real_format', 'real_tools', 'real_imports', 'real_acceptance']
    assert all(read(rv / f'{name}.command.json')['exit_code'] == 0 for name in command_names)
    report = (SRC / REL / 'REPORT.md').read_text(encoding='utf8')
    phase = report.split('## 冷首帧归因\n', 1)[1].split('## 修复、复测和标定\n', 1)[0]
    phase = phase.replace('[attribution.json](attribution.json)', '[attribution.json](../tool/bench/results/pending2/attribution.json)')
    cold_table = '\n### INSTR 冷首帧阶段原值与占比\n\n' + phase
    phone = (f'最终实测 {device["checked_at"]}：屏幕ON={device["screen_on"]}、Awake={device["awake"]}、未锁={device["unlocked"]}，'
             f'stay_on={device["stay_on"]}（要求2，未通过）、亮度模式={device["brightness_mode"]}、亮度={device["brightness"]}；'
             '当前用户bench包列表及pm path为空。卸载命令exit1/DELETE_FAILED_INTERNAL_ERROR，未冒充退出0。常亮变化来源未定位，本批没有执行任何设置写入命令。')
    footer = ('\n## INSTR 真实仓库回拷复验\n\n'
              '共享路径重读后定点追加；真实lib未覆盖。23个库候选文件（核心8、玩法15）和核心等价测试以两份diff交付，'
              '两补丁在快照上git apply --check --ignore-space-change均exit0；核心矩阵2行/COV-02见core_acceptance_append.md。'
              '真实仓库格式检查7个自有Dart路径exit0；flutter test test/tool为223/223、0失败/跳过（45.310s）；'
              'check_imports为145 lib PASS；check_acceptance为1552 references/1131 registered tests PASS。'
              '副本四组全量1108/1108（144文件，554/130/401/23），行覆盖6878/6878=100%，'
              '主包/bench分析均0 issue，format360文件0改动；矩阵静态与from-json均1554/1133，parity16例/96产物未变，'
              'publish --dry-run压缩包248KB、Package has 0 warnings。登记与主包执行计数差25是独立example/bench注册，不冒充全部设备运行。\n\n' + phone +
              '\n\n进程末检没有自有dart/flutter_tester；两次single-use Gradle已退出，接手前Kotlin PID7968保留，没有按java.exe批杀。'
              '首尾git log仍443589a3/f0b64ae1，未add/commit/push。完整路径和共享文件变更见validation/copy_manifest.json，'
              '真实复验日志见validation/real_*。CPU完整链路wheel仅2/5，其余四项各三轮；lotto仅搅拌阶段，任务完成状态为PARTIAL。\n')
    doc_footer = footer.replace('见validation/copy_manifest.json', '见tool/bench/results/pending2/validation/copy_manifest.json')
    for root in (SRC, DST):
        append(root / 'docs/PERF_ROOTCAUSE_REPORT.md', cold_table, '### INSTR 冷首帧阶段原值与占比')
        for relative in ('docs/RELEASE_CHECKLIST.md', 'docs/METRIC_FIX_REPORT.md'):
            append(root / relative, doc_footer, '## INSTR 真实仓库回拷复验')
        append(root / REL / 'REPORT.md', footer, '## INSTR 真实仓库回拷复验')
    # README代码块必须与接手快照逐字相同。
    for relative in ('README.md', 'README.zh-CN.md'):
        baseline = (Path('C:/ldq/instr-baseline') / relative).read_text(encoding='utf8')
        current = (DST / relative).read_text(encoding='utf8')
        assert re.findall(r'```dart\s*\n(.*?)```', baseline, re.S) == re.findall(r'```dart\s*\n(.*?)```', current, re.S)
    summary = {'completion': 'PARTIAL', 'copy_full_tests': 1108, 'real_tool_tests': 223,
               'coverage': '6878/6878 (100.00%)', 'publish_warnings': 0,
               'phone': {k: v for k, v in device.items() if k != 'raw'},
               'uncompleted': ['真实lib待核心/玩法补丁合并', 'wheel CPU完整链路2/5不足三轮', '完整开奖CPU未测', 'wheel/grid未达到原4ms目标', 'stay_on实测0而非2，未擅自改设置']}
    for root in (SRC, DST):
        (root / REL / 'validation/final_local_checks.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    manifest = read(rv / 'copy_manifest.json')
    direct = [item['path'] for item in manifest['copied'] if not item['path'].startswith(REL.as_posix() + '/')]
    evidence = [p.relative_to(DST).as_posix() for p in (DST / REL).rglob('*') if p.is_file() and p.name != 'copy_manifest.json']
    manifest['copied'] = [{'path': path, 'sha256': hashlib.sha256((DST / path).read_bytes()).hexdigest()} for path in sorted(set(direct + evidence))]
    for item in manifest['shared']:
        item['sha256'] = hashlib.sha256((DST / item['path']).read_bytes()).hexdigest()
    manifest['final_additions'] = ['PlanOnly启动数按Scenes计算；冷6/CPU15，未调用设备', '真实仓库复验日志、最终手机和进程状态、归因原值表']
    for root in (SRC, DST):
        (root / REL / 'validation/copy_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print('finalized; copied paths', len(manifest['copied']), 'shared', len(manifest['shared']), '; completion PARTIAL')


if __name__ == '__main__':
    main()
