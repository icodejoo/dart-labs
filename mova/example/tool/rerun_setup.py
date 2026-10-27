"""Initialize a separate rerun journal and capture preflight without old evidence writes."""
from pathlib import Path
import re, subprocess, json
H=Path(__file__).resolve().parent
R=H.parents[1]
O=H/'coverage_evidence'
D=R/'doc/plans/2026-10-27-device-coverage-rerun.md'
def adb(*args):
    return subprocess.check_output(['adb','-s','7NQBB23606003715',*args],text=True)
for key,args in {'window':['shell','dumpsys','window'],'audio':['shell','dumpsys','audio'],'power':['shell','settings','get','global','stay_on_while_plugged_in'],'devices':['devices','-l']}.items():
    (O/f'rerun-preflight-{key}.txt').write_text(adb(*args),encoding='utf-8')
w=(O/'rerun-preflight-window.txt').read_text(encoding='utf-8')
assert 'isKeyguardShowing=false' in w and 'isKeyguardShowing=true' not in w and 'mScreenOnFully=true' in w
old=(R/'doc/plans/2026-10-27-device-coverage-results.md').read_text(encoding='utf-8')
rows=re.findall(r'^\| ((?:[ACUFN]\d+|E\.[A-Za-z]+|E[12])) \| (PASS|FAIL|BLOCKED) \| (.*?) \|$',old,re.M)
assert len(rows)==135,len(rows)
(O/'rerun-previous-ledger.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
D.write_text('# 2026-10-27 Android 完整覆盖复跑\n\n状态：执行中。所有结论仅使用 rerun- 原始证据；上次结果不作为本次 PASS。\n\n## 基线与前置\n\n- 设备 7NQBB23606003715，STG_AL00 Android 12 arm64；已亮屏解锁，原始 window/audio/power 见 `example/tool/coverage_evidence/rerun-preflight-*`。\n- 起测 USB 常亮=7；媒体 speaker 音量=6/20。收尾恢复这两个原值。\n- Flutter 3.47.0 / Dart 3.13.0。保留已有 `test/core/engine_test.dart` 改动；禁止改库和测试。\n- 批次0：运行 flutter analyze lib test 与 flutter test，确认实际基线；随后隔离 release 构建。\n\n## 逐编号台账\n\n| 编号 | 结论 | 本次原因与证据 |\n|---|---|---|\n'+''.join(f'| {i} | BLOCKED | 本次待执行，不能沿用上次 {v}。 |\n' for i,v,d in rows),encoding='utf-8')
print(D)
