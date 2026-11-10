"""从本轮原始审计与冻结 MET2 比较器结果生成诚实的 DEVFIN 报告。"""
import collections
import datetime
import importlib.util
import json
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent.parent
EDITS = pathlib.Path(r'C:/ldq/devfin/document_edits.json')


def read(path):
    """读取 UTF-8 JSON。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, text):
    """以 LF 保存单个结果。"""
    path.write_text(text, encoding='utf-8', newline='\n')


def main():
    """生成本轮报告，旧 MET2 与前三轮度量报告保持可追溯。"""
    audit = read(OUT / 'audit.json')
    frames = read(OUT / 'frame_assessment.json')['scenarios']
    old = read(ROOT / 'tool/bench/results/met2/assessment.json')['scenarios']
    translations = {'PASS': '通过', 'FAIL': '失败', 'UNCERTAIN': '不确定',
                    'UNSTABLE': '不确定', 'CALIBRATED_NOT_DESIGN': '已标定未达设计目标'}
    def status(row):
        """设计目标和冻结回归预算分开判断。"""
        if row['status'] == 'PASS' and row['design_status'] != '满足设计目标':
            return '已标定未达设计目标'
        return translations.get(row['status'], row['status'])
    def maximum(row, metric):
        """只取未污染窗口，不把污染墙钟当纯绘制。"""
        values = [w[metric] for w in row['windows'] if not w['backpressure_contaminated']]
        return max(values) if values else None
    def number(value):
        """缺测不格式化成零。"""
        return '缺测' if value is None else f'{value:.3f}'
    lines = ['# DEVFIN 真机收尾复测（2026-11-11）', '',
             '仅一台 vivo V2417 / Android 16，APK 与首次会话身份见 session.json、validation/apk.json。'
             '原始脚本未通过：转盘冷帧五次仅两次 driver 成功即提前退出；续跑只执行未启动项目，'
             '不清零计数、不覆盖 runs.json，不超过每项五次。CPU 五项目均缺少有效轮。'
             '首帧数值可从原始 driver 响应恢复，但不把 driver 失败改写为通过。'
             '所有正式成本预算、RSS 与 12ms/4ms 硬门禁均未放宽。', '',
             '## APK 与测量身份', '',
             f"APK SHA-256：`{audit['session']['binary_sha256']}`。"
             '构建指定 integration_test/pending_bench_test.dart 与 LUCKDRAW_TIMELINE=true；'
             'arm64 libapp.so 检出 pending 测试名和新增路由。首轮因 Maven JVM 证书链失败（56.372s），'
             '使用 Windows 证书库重试成功（33.427s），Gradle workers=2。'
             '没有升级依赖或关闭证书校验；临时 Gradle 属性已恢复。', '',
             '## 冷 push 首帧 UI（ms）', '',
             '固定取启动顺序前3份完整设备 FrameTiming；全部额外轮仍在 audit.json。'
             '计时为 FrameTiming.buildDuration，不是启动时间或纯 layout/record。'
             'wheel/grid 的 driver 汇总失败来自冷窗口缺少完整 Raster timeline 事件，'
             '恢复值来自原始 Flutter driver JSON 响应，原 valid=false 保留。', '',
             '| 场景 | 前三次原值 | 中位数 | 极差 | 玩法−空白 | 增量预算 | 与原4ms差距 | driver成功/启动 |',
             '| --- | --- | --- | --- | --- | --- | --- | --- |']
    for name, row in audit['cold_frames'].items():
        lines.append(f"| {name} | {' / '.join(number(x) for x in row['primary_samples_ms'])} | "
                     f"{number(row['median_ms'])} | {number(row['range_ms'])} | "
                     f"{number(row.get('increment_ms'))} | {number(row.get('increment_budget_ms'))} | "
                     f"{row['gap_to_design'] * 100:+.3f}%" + ' | '
                     f"{row['driver_valid_rounds']}/{len(audit['scenes'][name])} |"
                     if 'gap_to_design' in row else
                     f"| {name} | {' / '.join(number(x) for x in row['primary_samples_ms'])} | "
                     f"{number(row['median_ms'])} | {number(row['range_ms'])} | — | — | — | {row['driver_valid_rounds']}/{len(audit['scenes'][name])} |")
    lines += ['', '有效增量预算为实测中位数差×1.1向上取整到0.001ms，冻结在 '
              '`budgets.status.json.devfin.first_frame_increment_budgets_ms`。'
              'wheel 比4ms多34.087ms，grid多6.520ms；不能写成达到设计目标。'
              '九宫格、老虎机三轮极差明显，标定不是稳定性或跨设备保证。'
              '既有 MET2 schema 只支持 wheel 的绝对 first_frame_ui_millis，无法表达空白基线及 grid/slot 有符号增量；'
              '因此 budgets.json 保留旧绝对信息字段并写明兼容原因，本轮有效增量预算由 DEVFIN 审计测试检查。'
              '不得将增量阈值套到旧绝对40.378ms；建议维护者另行扩展比较器 schema。', '',
              '## 原生进程/线程 CPU（%）', '',
              '协议为 before/start/end TCP 握手，计划五秒窗口第0/1/2/3/4秒各一次 cpuinfo+top，'
              '窗口前后各一次。每轮应取五次样本的角色/进程中位数，再取三轮中位数；单核100%，多核进程可超过100%。'
              '本次全部在 before 阶段失败，没有任何有效五秒 CPU 窗口。'
              'cpuinfo 是系统原生历史统计，不覆盖本次五秒；部分返回区间结束于采样前数分钟，匹配不到当前PID或命中旧PID。'
              'top 随后返回0线程/不被当前解析器识别的列头。不能用旧PID、框架墙钟或零值填空。', '',
              '| 场景 | UI三轮 / 中位数 | Raster三轮 / 中位数 | 总进程三轮 / 中位数 | 有效/启动 | 结论 |',
              '| --- | --- | --- | --- | --- | --- |']
    for scene, row in audit['cpu'].items():
        lines.append(f"| {scene} | 缺测 / 缺测 | 缺测 / 缺测 | 缺测 / 缺测 | {row['valid_rounds']}/{row['attempts']} | 不确定（采样链路失败） |")
    lines += ['', '全部25次失败原文与错误保留在各 cpu_*/cpu/；错误分类与完整轮次见 audit.json。'
              '没有统计区间足够新且进程身份正确的完整样本，不宣称完成CPU标定。', '',
              '## 四场景：MET2 与本次并排', '',
              '| 场景 | MET2结论；合计/UI P99最大ms | 本次未污染/总窗口 | 每轮合计P99 ms | 每轮UI P99 ms | 稳定性 | 本次结论 |',
              '| --- | --- | --- | --- | --- | --- | --- |']
    for scene in ['slot_raster', 'grid_steady', 'lotto_draw', 'lots_shaking']:
        row = frames[scene]
        unstable = [key for key, metric in row['metrics'].items() if metric.get('stable') is False]
        lines.append(f"| {scene} | {status(old[scene])}；{number(maximum(old[scene], '99th_percentile_build_plus_raster_millis'))}/"
                     f"{number(maximum(old[scene], '99th_percentile_frame_build_time_millis'))} | {row['clean_count']}/{len(row['windows'])} | "
                     + ' / '.join(number(w['99th_percentile_build_plus_raster_millis']) + ('（污染）' if w['backpressure_contaminated'] else '') for w in row['windows'])
                     + ' | ' + ' / '.join(number(w['99th_percentile_frame_build_time_millis']) for w in row['windows'])
                     + f" | {'不稳定：' + ', '.join(unstable) if unstable else '稳定'} | {status(row)} |")
    lines += ['', '所有未污染窗口独立检查 build+raster 同帧P99≤12ms且UI P99≤4ms，'
              '至少两个未污染窗口才评估成本；失败优先于不确定。'
              '冻结时间预算不因本次更慢而重标；比例、GC、RSS继续原门槛。'
              '各指标原值、中位数、原设计差距、硬门禁与RSS见 frame_assessment.json。', '',
              '## 全部持续动画窗口交付', '',
              '| 场景/轮 | 主/参照 | fps | 帧数/期望 | 交付比例 | fps≥59且≥98% |',
              '| --- | --- | --- | --- | --- | --- |']
    delivery = []
    for scene in frames:
        for run in audit['scenes'][scene]:
            for path in sorted((OUT / run['directory']).glob('*.timeline_summary.json')):
                row = read(path)
                expected = row['elapsed_micros'] / 1e6 * 60
                ratio = row['frame_count'] / expected
                passed = row['fps'] >= 59 and ratio >= 0.98
                delivery.append({'path': str(path.relative_to(OUT)).replace('\\', '/'),
                                 'fps': row['fps'], 'frame_count': row['frame_count'],
                                 'expected': expected, 'ratio': ratio, 'passed': passed})
                lines.append(f"| {run['directory']} | {'参照' if row['report_key'] == 'reference_spin' else '主场景'} | "
                             f"{row['fps']:.6f} | {row['frame_count']:g}/{expected:.3f} | {ratio:.6%} | {'通过' if passed else '失败'} |")
    write(OUT / 'delivery.json', json.dumps(delivery, ensure_ascii=False, indent=2) + '\n')
    lines += ['', f"{sum(w['passed'] for w in delivery)}/{len(delivery)}个持续动画窗口交付通过；"
              f"fps={min(w['fps'] for w in delivery):.6f}–{max(w['fps'] for w in delivery):.6f}；"
              f"fps=0轮数={sum(w['fps'] == 0 for w in delivery)}。"
              '冷push事件窗不按持续60fps验收；CPU项目没有有效窗口。'
              '这是timeline交付检查，不是独立面板呈现测量。', '',
              '## 异常、根因与边界', '',
              '1. 原脚本在首个项目有效轮不足时全局退出；本次续跑脚本位于 validation/resume_pending.ps1，'
              '只执行未启动项目，保留首次session和所有启动次数。原始脚本与产品lib未改。',
              '2. 冷窗口的 SDK TimelineSummary 因 Raster 事件未闭合而失败；设备测试与FrameTiming仍有原始响应，'
              '恢复数据单独保存为 device_response.original.json，并保留driver失败。wheel/grid设备用例验收仍不确定。',
              '3. CPU五项目0/5有效；统计区间/PID/线程列不符合协议。CPU未完成，不提供伪造百分比。',
              '4. 本轮首帧仅增量预算标定，原4ms设计目标差距及波动不抹去；历史40.378ms外壳不同。',
              '5. 本轮亮度按用户要求保持最低1、手动0、USB常亮2；主会话每120秒有锁屏看护。'
              '本脚本没有额外窗口内adb轮询；不能独立排除系统抢占、DIM或外部看护影响。',
              '6. 若本次仍有硬失败，库代码根因为「无法判定」；没有可靠线程CPU或luckdraw函数采样栈，'
              '不将引擎GLES等待解释成可避免的库内工作，不改lib。', '',
              '本报告由validation/summarize.py及finalize.py对本次原始响应、runs.json与冻结compare输出生成；'
              '所有失败保留。完整采集链路未通过不影响离线工具回归可以通过，两者分别报告。']
    report = '\n'.join(lines) + '\n'
    write(OUT / 'REPORT.md', report)
    assessment = {'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  'generated_by': 'DEVFIN independent audit; assess_pending.dart rejected incomplete original rounds',
                  'collection_status': '未通过：冷首帧driver不足及CPU0/5',
                  'cold_frames': audit['cold_frames'], 'cpu': audit['cpu'],
                  'frame_results': {key: status(row) for key, row in frames.items()},
                  'delivery_passed': all(w['passed'] for w in delivery)}
    write(OUT / 'assessment.json', json.dumps(assessment, ensure_ascii=False, indent=2) + '\n')
    path = ROOT / 'tool/bench/budgets.status.json'
    budgets = read(path)
    budgets['devfin'].update({'measurement_status': assessment['collection_status'],
                              'cold_frames': audit['cold_frames'], 'cpu': audit['cpu'],
                              'frame_results': assessment['frame_results'],
                              'frame_assessment': 'results/pending/frame_assessment.json',
                              'report': 'results/pending/REPORT.md'})
    budgets['status'] = 'DEVFIN：四场景复测见devfin；冷帧增量已标定、driver不足；CPU缺测；历史MET2保留'
    write(path, json.dumps(budgets, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(assessment['frame_results'], ensure_ascii=False))


if __name__ == '__main__':
    main()
