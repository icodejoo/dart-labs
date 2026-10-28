"""Append an honest blocked inventory when the common device prerequisite fails.

从矩阵生成逐编号台账，未执行项不伪造通过。
"""
from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[2]
# Historical append-only inventory. It describes the 2026-10-27 run, not the
# current acceptance matrix. Never parse the replacement pointer page.
matrix = subprocess.run(
    ['git', '-C', str(ROOT), 'show',
     'dbf95f6:mova/doc/plans/2026-10-27-device-coverage-test-matrix.md'],
    check=True, capture_output=True, encoding='utf-8').stdout
result = ROOT / 'doc/plans/2026-10-27-device-coverage-results.md'
sections = {}
for prefix in ['A', 'C', 'U', 'F']:
    sections[prefix] = re.findall(r'^\| (' + prefix + r'\d+) \| (.*?) \| (.*?) \|$', matrix, re.M)
event_text = matrix.split('## E. 事件', 1)[1].split('## U.', 1)[0]
events = [e for e in re.findall(r'`(Mova\w+)`', event_text.split('每个事件')[0]) if e != 'MovaEvent']
rows = sum(len(v) for v in sections.values()) + len(events) + 2
lines = [
    '\n## 批次 0 结论与本轮台账\n',
    '- 基线最终结果：`00:52 +1503: All tests passed!`；分析 `No issues found! (ran in 20.8s)`。',
    '- 环境：Flutter 3.47.0 / Dart 3.13.0；Android 12 / arm64-v8a。',
    '- 公共阻塞 K：`isKeyguardShowing=true`，WAKEUP / dismiss-keyguard / swipe 后仍锁定；未获得人工解锁完成信号。',
    '- K 证据：`example/tool/coverage_evidence/preflight.devices.txt`、`preflight.window.txt`、`preflight.locked.png`（同目录）。',
    '- 以下 BLOCKED 是**本轮未执行**，不是功能失败，也不是历史测试结论。解除 K 后逐批更新，不能把单元测试当真机验证。',
    f'- 矩阵计数口径：A 33、C 17、E {len(events) + 2}（每个事件单列 + E1/E2）、U 9、F 16；总计 {rows}。当前 PASS 0 / FAIL 0 / BLOCKED {rows}。\n',
]
for prefix in ['A', 'C']:
    lines += [f'### {prefix} 组\n', '| 编号 | 结论 | 测试点与缺失证据 |', '|---|---|---|']
    for ident, name, detail in sections[prefix]:
        lines.append(f'| {ident} | BLOCKED | {name}：{detail}。本轮尚无真机事件/状态证据，受 K 阻塞。 |')
lines += ['\n### E 组\n', '| 编号/事件 | 结论 | 动作、载荷、重复与状态一致性 |', '|---|---|---|']
for event in events:
    lines.append(f'| E.{event} | BLOCKED | K；本轮未触发，无实际载荷；重复次数与 state 一致性未核对。 |')
lines += [
    '| E1 | BLOCKED | K；未记录完整点播实际事件顺序。 |',
    '| E2 | BLOCKED | K；未采集默认关闭功能事件数。 |',
]
for prefix in ['U', 'F']:
    lines += [f'\n### {prefix} 组\n', '| 编号 | 结论 | 测试点与缺失证据 |', '|---|---|---|']
    for ident, name, detail in sections[prefix]:
        lines.append(f'| {ident} | BLOCKED | {name}：{detail}。本轮未执行，受 K 阻塞。 |')
lines += [
    '\n## FAIL 最小复现\n',
    '当前无真机 FAIL 结论。PiP、WarmPlan、pod 等历史问题没有在本轮重现，不能记为本轮 FAIL。',
    '\n## 与 CLAUDE.md 的差异\n',
    '- 测试数量：文档 1472；本轮实际 1503（+31）。原始日志见批次 0。按照范围约束，不修改 CLAUDE.md。',
    '- 功能结论：本轮受设备锁屏阻塞，尚无证据支持推翻或确认任何已记录的 Android 行为。',
]
with result.open('a', encoding='utf-8') as file:
    file.write('\n'.join(lines) + '\n')
print(f'Wrote {rows} rows ({len(events)} event types).')
