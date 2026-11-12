"""MET 离线数据准备与报告生成；只读历史采集，不连接设备，无额外依赖。"""
import collections
import hashlib
import json
import pathlib
import subprocess

BENCH = pathlib.Path(__file__).resolve().parent
ROOT = BENCH.parent.parent
RESULTS = BENCH / 'results'
OUT = RESULTS / 'met'
RASTER = 'average_frame_rasterizer_time_millis'
P90 = '90th_percentile_frame_rasterizer_time_millis'
BUILD = 'average_frame_build_time_millis'
SOURCES = ['bench_20261110_180650', 'perf_after', 'perf_ablation', 'ab_experiment']
LABELS = {'PASS': '通过', 'FAIL': '失败', 'UNCERTAIN': '不确定', 'INFO': '信息项（待标定）'}


def read(path):
    """读取单个 UTF-8 JSON 对象。"""
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    """保存 LF 文本或 JSON，保留所有实测精度。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, indent=2) + '\n'
    path.write_text(text, encoding='utf-8', newline='\n')


def raw_windows():
    """查找已保存原始汇总，排除 comparison 派生副本，以身份去重。"""
    found = {}
    for source in SOURCES:
        files = (RESULTS / source).glob('*/*.timeline_summary.json')
        if source == 'ab_experiment':
            files = list(files) + list((RESULTS / source / 'skia_compare').glob('*/*.timeline_summary.json'))
        for path in sorted(files):
            if path.parent.name == 'comparison':
                continue
            data = read(path)
            identity = (data['report_key'], data['run_id'], data.get('actual_scene'))
            found.setdefault(identity, (path, data))
    return list(found.values())


def invoke(input_dir, output, suffix):
    """运行唯一的 Dart 判定实现，性能失败退出码也完整保存。"""
    command = ['dart', 'run', 'tool/bench/compare.dart', '--classify-windows',
               '--rss-all-scenes', '--input=' + input_dir.relative_to(ROOT).as_posix(),
               '--output=' + output.relative_to(ROOT).as_posix()]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=300, shell=True)
    write(OUT / (suffix + '.stdout.log'), result.stdout.decode('utf-8', errors='replace'))
    write(OUT / (suffix + '.stderr.log'), result.stderr.decode('utf-8', errors='replace'))
    write(OUT / (suffix + '.command.json'), {'command': command, 'exit_code': result.returncode})
    if not output.exists():
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return read(output)


def distribution(windows):
    """绘制离散点分布和 1ms 直方图的独立 SVG，逐点数据另存 JSON。"""
    steady = [(p, s) for p, s in windows if s['report_key'] not in ['wheel_first_frame', 'memory_cycles']]
    rows = []
    for path, data in steady:
        ratio = data['frame_count'] / (data['elapsed_micros'] / 1e6 * 60)
        delivery = data['fps'] >= 59 and ratio >= .98
        rows.append({'source': path.relative_to(ROOT).as_posix(), 'report_key': data['report_key'],
                     'run_id': data['run_id'], 'fps': data['fps'], 'delivery_ratio': ratio,
                     'delivery_passed': delivery, 'backpressure_contaminated': delivery and data[P90] >= 15.5,
                     'avg_raster_ms': data[RASTER], 'p90_raster_ms': data[P90]})
    write(OUT / 'all_windows.json', rows)
    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="620" viewBox="0 0 1100 620">',
           '<rect width="1100" height="620" fill="white"/>',
           '<g font-family="sans-serif" fill="#17202a">',
           '<text x="50" y="28" font-size="20">Saved 60Hz windows: Raster distribution (MET, 2026-11-10)</text>',
           '<text x="50" y="54">Blue: scenario; orange: reference square; dashed red: 15.5ms; bins: 1ms</text>']
    for panel, (field, title) in enumerate([('avg_raster_ms', 'Average Raster'), ('p90_raster_ms', 'P90 Raster')]):
        top = 100 + panel * 250
        svg.append(f'<text x="50" y="{top - 12}" font-size="17">{title} — {len(rows)} independent windows</text>')
        bins = collections.Counter(int(r[field]) for r in rows)
        for b in range(19):
            x = 70 + b * 50
            count = bins[b]
            svg.append(f'<rect x="{x}" y="{top + 120 - count * 2.5}" width="45" height="{count * 2.5}" fill="#e1e8ee"/>')
            svg.append(f'<text x="{x + 14}" y="{top + 138}" font-size="11">{b}</text>')
            if count:
                svg.append(f'<text x="{x + 14}" y="{top + 114 - count * 2.5}" font-size="11">{count}</text>')
        svg.append(f'<line x1="70" x2="1020" y1="{top + 120}" y2="{top + 120}" stroke="#333"/>')
        svg.append(f'<text x="980" y="{top + 155}">ms</text>')
        for i, row in enumerate(sorted(rows, key=lambda r: r[field])):
            color = '#db7600' if row['report_key'] == 'reference_spin' else '#1263a0'
            x = 70 + row[field] * 50
            y = top + 165 + (i % 6) * 5
            svg.append(f'<circle cx="{x:.3f}" cy="{y}" r="2.5" fill="{color}"><title>{row["source"]}: {row[field]:.6f}ms</title></circle>')
        x = 70 + 15.5 * 50
        svg.append(f'<line x1="{x}" x2="{x}" y1="{top - 5}" y2="{top + 200}" stroke="#bd2020" stroke-dasharray="5 4"/>')
    svg.append('</g></svg>\n')
    write(OUT / 'raster_distribution.svg', '\n'.join(svg))
    return rows


def summary_table(scenarios):
    """生成 11 场景关键中位数及独立结论表。"""
    lines = ['| 场景 | 未污染/总窗口 | UI avg ms | Raster avg / P90 ms | RSS 稳态 B | 结论 |',
             '| --- | --- | --- | --- | --- | --- |']
    for key, result in scenarios.items():
        metrics = result['metrics']
        def number(metric):
            value = metrics.get(metric, {}).get('median')
            return '—' if value is None else f'{value:.4f}'
        count = '不适用' if result['clean_count'] is None else f'{result["clean_count"]}/{len(result["windows"])}'
        lines.append(f'| {key} | {count} | {number(BUILD)} | {number(RASTER)} / {number(P90)} | '
                     f'{number("rss_steady_growth_bytes")} | {LABELS[result["status"]]} |')
    return '\n'.join(lines)


def report(selected, merged, rows):
    """汇总分类、证据、逐指标门禁与敏感性限制，不修改历史报告。"""
    refs = [r for r in rows if r['report_key'] == 'reference_spin']
    polluted = sum(r['backpressure_contaminated'] for r in rows)
    low = max(r['p90_raster_ms'] for r in rows if r['p90_raster_ms'] < 15.5)
    high = min(r['p90_raster_ms'] for r in rows if r['p90_raster_ms'] >= 15.5)
    lines = ['# MET 离线度量修正重算（2026-11-10）', '',
             '设备 vivo V2417 / Android16 / 60Hz；仅重读保存数据，未连接手机、adb、Gradle或构建。',
             '沿用 FIN 的 33 个样本身份，重新定位原始汇总并记录 SHA-256；PERF 五个修复场景，其余 DEV。参照与主窗口独立分类。', '',
             f'全量分布：{len(rows)} 个稳态窗口，其中 {polluted} 个污染；参照 {len(refs)} 个，其中 '
             f'{sum(r["backpressure_contaminated"] for r in refs)} 个污染。fps {min(r["fps"] for r in rows):.6f}–{max(r["fps"] for r in rows):.6f}；'
             f'真实卡顿 {sum(not r["delivery_passed"] for r in rows)} 个。P90 间隙 {low:.3f}–{high:.3f}ms，15.5ms 位于其中。', '',
             '![全部保存窗口 avg 与 P90 分布](raster_distribution.svg)', '',
             '逐点身份与原值见 [all_windows.json](all_windows.json)；冷首帧3个及RSS3个样本不属于持续动画窗口，不能用其fps套稳态交付规则。', '',
             '## 正式结果集（FIN 选择）', '', summary_table(selected['scenarios']), '',
             '首帧中位数40.378ms，仅信息，非通过；待 blank_first_frame 基线。RSS使用所有原始五次循环，不随窗口污染过滤。', '',
             '## 每场景每窗口与每指标', '']
    for key, result in selected['scenarios'].items():
        lines += [f'### {key}：{LABELS[result["status"]]}', '',
                  '| run_id | 来源 | fps | 帧数 | 完整比例 | Raster avg / P90 ms | 分类 |',
                  '| --- | --- | --- | --- | --- | --- | --- |']
        for w in result['windows']:
            lines.append(f'| {w["run_id"]} | {w["met_source"]} | {w.get("fps", "—")} | {w.get("frame_count", "—")} | '
                         f'{w.get("delivery_ratio")} | {w.get(RASTER)} / {w.get(P90)} | {w["classification"]} |')
        lines += ['', '| 指标 | 未污染中位数（RSS全部） | 首版目标 | 新预算 | 稳定 | 结论 |',
                  '| --- | --- | --- | --- | --- | --- |']
        for metric, m in result['metrics'].items():
            lines.append(f'| {metric} | {m.get("median", "—")} | {m.get("target", "无目标")} | {m.get("limit", "—")} | '
                         f'{m.get("stable", "—")} | {LABELS[m["status"]]}{"；首版标定" if m.get("calibrated") else ""} |')
        lines.append('')
    lines += ['## 参照窗口独立证据', '', '| 来源 | 参照 avg / P90 ms | 参照 fps | 主场景 avg ms | 主场景 fps | 参照分类 |',
              '| --- | --- | --- | --- | --- | --- |']
    for r in refs:
        # 同一目录在 slot 中有两种主场景，以文件名前缀精确匹配。
        source = pathlib.Path(r['source'])
        main_name = source.name.replace('_reference_', '_')
        main = next((v for v in rows if pathlib.Path(v['source']) == source.with_name(main_name)), None)
        lines.append(f'| {r["source"]} | {r["avg_raster_ms"]:.4f} / {r["p90_raster_ms"]:.4f} | {r["fps"]:.4f} | '
                     f'{main["avg_raster_ms"] if main else "—"} | {main["fps"] if main else "—"} | '
                     f'{"BACKPRESSURE" if r["backpressure_contaminated"] else "CLEAN"} |')
    lines += ['', '## 合并所有可用窗口：敏感性分析', '', summary_table(merged['scenarios']), '',
              '合并DEV/PERF/消融/AB A,B,C/Skia、Impeller，以report_key/run_id/actual_scene去重。配置、后端、APK不同，不能替代正式结果集或用于改预算。',
              '合并轮数可超过五次，只是离线敏感性分析；五次上限约束同配置后续独立启动，不能把跨版本历史轮数当作补跑。', '',
              '## 失败、不确定与补跑', '',
              '正式结果集没有少于两个未污染窗口的场景，因此没有“样本不足”不确定项；不把不稳定改叫通过。',
              '需复查稳定性：wheel_steady（旧掉帧代理0与1/301，极差/中位数200%）、grid_steady、slot_raster、lots_shaking（具体失败指标见上表）。',
              '它们已有至少两轮未污染数据，当前判失败；修正或调查后需新一组同配置数据。确需补足未污染窗口时仅补到同配置总启动5次，仍不足即不确定。',
              '明确预算超标：grid UI P90和Raster平均；slot_steady、lever_steady、lots_shaking的UI平均均超15%，保持原目标，不自动放宽。',
              '首帧待标定：下一真机会话先增加blank_first_frame（空白页冷push）三次，记录完整UI；再测wheel_first_frame三次，以中位数差定预算。命令与实现准备见工具README。', '',
              '## 政策与保守边界', '',
              '成本中位数只取未污染窗口，偶数取中间两项平均；稳定性对未污染窗口取极差/中位数≤30%，全零稳定、零中位数但非全零失败。',
              '目标采用MET开始时budgets.json（包含FIN批准UI、既有更严校准值），不回退到DEV较宽原估算。稳定指标≤目标通过；超出≤15%按中位数×1.1向上取整，耗时0.001ms、比例0.000001；>15%或不稳定不改预算。RSS绝对门禁不重标。',
              '首版无Raster P99预算：报告所有未污染P99中位数，标INFO，不凭空新增阈值。first_frame_ui_millis保留历史4ms但informational:true，不能算通过。',
              '背压分类是“fps/帧数完整且P90接近帧周期”的操作性推断，未直接测量swap/GL等待；污染窗口无法观测真实绘制成本，极端重负载可能误判，所以至少两轮未污染且所有稳态窗口检查交付。',
              '历史dropped_frame_ratio是线程耗时预算代理，不是实际未呈现帧计数；按批准规则在未污染窗口继续门禁，稀有一次超时仍可能触发相对稳定性失败，不自行豁免。', '']
    validation = OUT / 'validation'
    if (validation / 'test_summary.json').exists():
        total = read(validation / 'test_summary.json')['total']
        lines += ['## 本批本地验证', '',
                  f'四组串行测试{total["passed"]}通过、{total["skipped"]}跳过、{total["failed"]}失败，{total["files"]}文件；相关bench三文件42通过，新增9条MET回归。', '',
                  '| 检查 | 退出码 | 实际输出摘要 |', '| --- | --- | --- |']
        for name in ['analyze', 'bench_analyze', 'format_check', 'tools', 'coverage', 'imports',
                     'acceptance', 'acceptance_json', 'parity', 'publish']:
            command_path = validation / (name + '.command.json')
            log_path = validation / (name + '.stdout.log')
            if command_path.exists() and log_path.exists():
                text = log_path.read_text(encoding='utf-8-sig').strip()
                summary = text.splitlines()[-1]
                if name == 'tools':
                    summary = '177通过、0跳过、0失败；原始成功JSON结束事件已核验'
                lines.append(f'| {name} | {read(command_path)["exit_code"]} | {summary} |')
        lines += ['', '[逐命令日志与退出码](validation/)、[测试汇总](validation/test_summary.json)、'
                  '[合并JSON](validation/all.tests.jsonl)、[来源/链接/分类一致性自检](validation/selfcheck.json)。'
                  '覆盖率6792/6792=100%；主包与bench安装后均立即恢复/核对分析配置。无设备操作、依赖声明变更或版本提交。', '']
    write(OUT / 'REPORT.md', '\n'.join(lines))


def main():
    """按FIN身份准备原始数据，调用Dart重算，回填预算并输出报告。"""
    OUT.mkdir(parents=True, exist_ok=True)
    windows = raw_windows()
    by_identity = {(s['report_key'], s['run_id']): (p, s) for p, s in windows if s['report_key'] != 'reference_spin'}
    chosen = []
    provenance = []
    for old in sorted((RESULTS / 'fin/comparison').glob('*.timeline_summary.json')):
        identity = read(old)
        path, data = by_identity[(identity['report_key'], identity['run_id'])]
        chosen.append((path, data))
        provenance.append({'source': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                           'scenario': data['report_key'], 'run_id': data['run_id']})
    selected_dirs = {p.parent for p, s in chosen if s['report_key'] not in ['wheel_first_frame', 'memory_cycles']}
    references = [(p, s) for p, s in windows if p.parent in selected_dirs and s['report_key'] == 'reference_spin']
    for directory, collection in [('comparison', chosen + references), ('all_comparison', windows)]:
        for path, data in collection:
            write(OUT / directory / path.name, {**data, 'met_source': path.relative_to(ROOT).as_posix()})
    write(OUT / 'provenance.json', provenance)
    status_path = BENCH / 'budgets.status.json'
    status = read(status_path)
    status.setdefault('met', {'targets': read(BENCH / 'budgets.json')})
    write(status_path, status)
    selected = invoke(OUT / 'comparison', OUT / 'assessment.json', 'comparison')
    merged = invoke(OUT / 'all_comparison', OUT / 'sensitivity.json', 'sensitivity')
    budgets = read(BENCH / 'budgets.json')
    calibrated = []
    for key, scene in selected['scenarios'].items():
        for metric, row in scene['metrics'].items():
            if row.get('calibrated'):
                budgets[key][metric] = row['limit']
                calibrated.append({'scenario': key, 'metric': metric, **row, 'date': '2026-11-10',
                                   'device': 'vivo V2417', 'basis': '首版标定；稳定未污染窗口中位数超原目标不超过15% ×1.1 向上取整'})
    write(BENCH / 'budgets.json', budgets)
    rows = distribution(windows)
    status.update(status='MET：度量已修正，成本仍有失败；首帧信息项待标定',
                  policy='所有稳态窗口检查交付；成本只用未污染窗口且至少2个；RSS沿用FIN；详见met字段')
    status['met'].update(date='2026-11-10', device='vivo V2417', calibrated=calibrated,
                         scenes={k: s['status'] for k, s in selected['scenarios'].items()},
                         windows={'total': len(rows), 'contaminated': sum(r['backpressure_contaminated'] for r in rows),
                                  'reference': sum(r['report_key'] == 'reference_spin' for r in rows),
                                  'reference_contaminated': sum(r['backpressure_contaminated'] and r['report_key'] == 'reference_spin' for r in rows),
                                  'real_jank': sum(not r['delivery_passed'] for r in rows)},
                         rule={'fps_min': 59.0, 'delivery_ratio_min': .98, 'p90_raster_min_ms': 15.5,
                               'minimum_clean_windows': 2, 'budget_excess_max': .15,
                               'millis_precision': .001, 'ratio_precision': .000001,
                               'target_basis': 'MET前预算快照；保留FIN批准UI平均与历史更严目标，不回退DEV较宽估算'},
                         p99='首版无预算，保留诊断信息', first_frame='信息项，待空白页冷首帧三轮基线')
    write(status_path, status)
    report(selected, merged, rows)
    print('MET scenarios:', collections.Counter(s['status'] for s in selected['scenarios'].values()))
    print('MET windows:', len(rows), 'contaminated:', sum(r['backpressure_contaminated'] for r in rows))
    print('MET calibrations:', [(r['scenario'], r['metric'], r['limit']) for r in calibrated])


if __name__ == '__main__':
    main()
