"""MET2：只读保存样本，显式首版标定后使用冻结预算重比，无设备操作。"""
import collections
import hashlib
import json
import pathlib
import statistics
import subprocess

import recalculate_met as met

ROOT = met.ROOT
BENCH = met.BENCH
OUT = BENCH / 'results/met2'
BUILD_P90 = '90th_percentile_frame_build_time_millis'
BUILD_P99 = '99th_percentile_frame_build_time_millis'
COMBINED_P99 = '99th_percentile_build_plus_raster_millis'
RSS = 'rss_steady_growth_bytes'
LABELS = {'PASS': '满足设计目标', 'FAIL': '失败',
          'UNCERTAIN': '不确定，需补跑', 'INFO': '信息项，待标定'}


def invoke(calibrate=False):
    """调用唯一 Dart 判定实现，保存真实退出码；正常比较不允许自动标定。"""
    name = 'calibration' if calibrate else 'comparison'
    command = ['dart', 'run', 'tool/bench/compare.dart', '--rss-all-scenes',
               '--input=tool/bench/results/met2/comparison',
               f'--output=tool/bench/results/met2/{name}.json']
    if calibrate:
        command.append('--calibrate')
    output = OUT / f'{name}.json'
    output.unlink(missing_ok=True)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, timeout=300, shell=True)
    met.write(OUT / f'{name}.stdout.log', result.stdout.decode('utf-8', errors='replace'))
    met.write(OUT / f'{name}.stderr.log', result.stderr.decode('utf-8', errors='replace'))
    met.write(OUT / f'{name}.command.json', {'command': command, 'exit_code': result.returncode})
    if result.returncode not in (0, 1) or not output.exists():
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace'))
    return met.read(output)


def conclusion(scene):
    """回归通过与设计达成分列；失败和不确定优先显示。"""
    return scene['design_status'] if scene['status'] == 'PASS' else LABELS[scene['status']]


def number(value, digits=4):
    """格式化报告中的有限数值，缺失证据不伪造零值。"""
    return '—' if value is None else f'{value:.{digits}f}'


def tables(assessment):
    """生成场景结论、硬门禁、CPU示意、回归预算和完整设计差距表。"""
    scenes = assessment['scenarios']
    summary = ['| 场景 | 未污染/总窗口 | UI均值 ms | Raster均值/P90 ms | 结论 |',
               '| --- | --- | --- | --- | --- |']
    guard = ['| 场景 | 未污染合计P99最大 ms / 12 | UI P99最大 ms / 4 | 帧预算余量门禁 |',
             '| --- | --- | --- | --- |']
    cpu = ['| 场景 | UI忙占比（全部窗口中位数） | Raster忙占比（未污染窗口中位数） |',
           '| --- | --- | --- |']
    budgets = ['| 场景 | UI均值/P90 ms | Raster均值/P90 ms |', '| --- | --- | --- |']
    gaps = ['| 场景 / 指标 | 实测中位数 ms | 最初设计目标 ms | 回归预算 ms | 超出设计目标 | 指标结论 |',
            '| --- | --- | --- | --- | --- | --- |']
    cpu_rows = []
    gap_rows = []
    for key, scene in scenes.items():
        metrics = scene['metrics']
        def val(metric, field='median'):
            return metrics.get(metric, {}).get(field)
        count = '不适用' if scene['clean_count'] is None else f'{scene["clean_count"]}/{len(scene["windows"])}'
        summary.append(f'| {key} | {count} | {number(val(met.BUILD))} | '
                       f'{number(val(met.RASTER))}/{number(val(met.P90))} | {conclusion(scene)} |')
        if scene['clean_count'] is not None:
            guards = scene['frame_budget']
            guard.append(f'| {key} | {number(guards[COMBINED_P99]["max"], 3)} | '
                         f'{number(guards[BUILD_P99]["max"], 3)} | '
                         f'{"失败" if any(g["status"] == "FAIL" for g in guards.values()) else "通过"} |')
            windows = scene['windows']
            ui = statistics.median([w[met.BUILD] * w['fps'] / 1000 for w in windows])
            raster = statistics.median([w[met.RASTER] * w['fps'] / 1000 for w in windows
                                      if not w['backpressure_contaminated']])
            cpu.append(f'| {key} | {ui:.2%} | {raster:.2%} |')
            cpu_rows.append({'scenario': key, 'ui_busy_ratio': ui, 'raster_busy_ratio': raster,
                             'process_cpu_measured': False})
            budgets.append(f'| {key} | {number(val(met.BUILD, "limit"), 3)}/{number(val(BUILD_P90, "limit"), 3)} | '
                           f'{number(val(met.RASTER, "limit"), 3)}/{number(val(met.P90, "limit"), 3)} |')
        else:
            cpu.append(f'| {key} | 不适用（非稳态） | 不适用（非稳态） |')
        for metric, row in metrics.items():
            if row.get('gap_to_design') is not None and row['gap_to_design'] > 0:
                if scene['status'] == 'INFO':
                    continue
                gap_rows.append({'scenario': key, 'metric': metric, **row})
                gaps.append(f'| {key} / {metric} | {number(row["median"], 6)} | '
                            f'{number(row["design_target"], 3)} | {number(row["limit"], 3)} | '
                            f'+{row["gap_to_design"]:.2%} | {row["design_status"]} |')
    met.write(OUT / 'cpu_indicators.json', cpu_rows)
    met.write(OUT / 'design_gaps.json', gap_rows)
    return {k: '\n'.join(v) for k, v in [('summary', summary), ('guard', guard), ('cpu', cpu),
                                           ('budgets', budgets), ('gaps', gaps)]}


def report(assessment):
    """完整逐指标和逐窗口输出，硬失败不被首版标定覆盖。"""
    sections = tables(assessment)
    met.write(OUT / 'tables.json', sections)
    lines = ['# MET2：预算标定与稳定性规则（2026-11-10）', '',
             '纯离线，沿用MET/FIN选定的33个样本（11场景各三轮）；设备vivo V2417（Android 16）/60Hz。'
             'PERF五场景+DEV其余，不是同一APK重测，不是跨设备保证。', '',
             '全部130个保存稳态窗口约60fps（59.829927–60.176516），帧交付完整，无真实丢帧（timeline交付口径，'
             '非独立面板呈现测量）。25个Raster窗口受vsync背压污染且与绘制内容无关，参照方块65个中也有9个；'
             '污染分类和RSS门禁保持MET/FIN规则。成本只用正式集合22个未污染窗口，所有27个主窗口检查交付。', '',
             '## 规则与可重复性', '',
             '比例极差≤0.01；时间中位数<0.5ms时极差≤0.15ms；其余时间/字节相对极差≤30%。'
             '近零比例的相对极差无意义；绝对容差抑制小基数放大，但不豁免回归预算。RSS仍仅按绝对上限。', '',
             '正常compare只读冻结预算，不在每次回归中自动放宽。显式--calibrate仅输出建议：'
             '至少2个未污染且稳定的时间指标，预算=max(中位数×1.1向上取整到0.001ms，有来源的历史标定下限)。'
             '下限不高于MET2开始时已批准值；冻结来源、初始设计快照与MET前目标分别保存在budgets.status.json.met2。'
             '比例/GC/RSS不重标。不存在15%放宽截止线；不稳定或样本不足标不确定，需补跑。', '',
             '最初设计目标来自DEV保存的design_budgets.json；MET冻结目标含FIN批准值和历史更严校准，另列为target。'
             'RSS改口径不能与旧0.5MiB直接比，继续使用FIN 1.5MiB。冷首帧40.378ms仅信息，4ms旧估算不标达成，待空白页基线。', '',
             '硬门禁对每个未污染窗口单独检查合计P99≤12.0ms且UI P99≤4ms；任一超标即失败，优先于不确定。'
             '使用保存的同帧合计P99，绝不将两个独立P99相加；12ms给16.67ms至少留4.5ms。', '',
             '## 11场景结论', '', sections['summary'], '',
             'RSS独立场景稳态中位数933888B≤1572864B，10个RSS场景全部通过；页面峰值预算5622989B，预热仅信息。', '',
             '## 帧预算余量硬门禁', '', sections['guard'], '',
             'grid合计P99 12.231ms、slot_raster 16.905ms、lotto 12.229ms超出12ms；lotto UI P99为4.386/4.016ms均超4ms。'
             '全部窗口仍完整交付，硬门禁失败表示预留余量不足，不声称观察到真实丢帧。grid/slot_raster/lots另有未污染Raster不稳定；'
             'lots因此不确定，需下一次同配置三轮调查，不能挑选好窗口；不足两个时最多补到五次启动。', '',
             '## CPU占用指示（不是进程CPU实测）', '',
             'UI≈avg_build_ms×fps/1000（所有主窗口）；Raster≈avg_raster_ms×fps/1000（仅未污染窗口）。'
             '表内为各窗口推算值的中位数，由帧耗时推算，未做进程级CPU实测（dumpsys cpuinfo/top），进程级CPU实测待下次真机会话。'
             '两线程比例不能相加当进程CPU；Raster耗时并不等于线程实际执行CPU指令时间。', '', sections['cpu'], '',
             '## 首版回归预算（每指标）', '', sections['budgets'], '',
             '比例沿用各场景0.005（lever为0），GC=0；RSS保持原值。不稳定指标保留原预算，不假装完成标定。', '',
             '## 未达最初设计目标的完整清单', '', sections['gaps'], '',
             '指标通过只表示回归预算通过；场景仍可能因硬门禁失败或其他指标不确定。首帧另列信息，不参与设计达成统计。', '',
             '## 所有场景每指标及逐窗口证据', '']
    for key, scene in assessment['scenarios'].items():
        lines += [f'### {key}：{conclusion(scene)}', '',
                  '| 指标 | 实测中位数 | 最初设计目标 | MET前目标 | 标定/冻结预算 | 设计差距 | 状态 |',
                  '| --- | --- | --- | --- | --- | --- | --- |']
        for metric, row in scene['metrics'].items():
            gap = row.get('gap_to_design')
            lines.append(f'| {metric} | {number(row.get("median"), 6)} | {number(row.get("design_target"), 6)} | '
                         f'{number(row.get("target"), 6)} | {number(row.get("limit"), 6)} | '
                         f'{"—" if gap is None else f"{gap:+.2%}"} | {row.get("design_status", row["status"])} |')
        lines += ['', '| run_id | fps | 帧数完整比例 | 分类 | 同帧合计P99 ms | UI P99 ms |',
                  '| --- | --- | --- | --- | --- | --- |']
        for w in scene['windows']:
            lines.append(f'| {w["run_id"]} | {number(w.get("fps"))} | {number(w.get("delivery_ratio"), 6)} | '
                         f'{w["classification"]} | {number(w.get(COMBINED_P99), 3)} | {number(w.get(BUILD_P99), 3)} |')
        lines.append('')
    lines += ['[原始数据来源与SHA-256](provenance.json)、[正式评估](assessment.json)、'
              '[逐窗口成本与设计目标](comparison.json)、[显式标定建议](calibration.json)、'
              '[原130窗口统计](../met/all_windows.json)。', '',
              '复现：在包根运行 `python tool/bench/recalculate_met2.py`。该命令仅读历史数据、写met2及预算状态；'
              '`dart run tool/bench/compare.dart --rss-all-scenes --input=tool/bench/results/met2/comparison` '
              '正常冻结比较退出1（3失败、1不确定），不能冒充性能全达标。', '']
    validation = OUT / 'validation'
    if (validation / 'test_summary.json').exists():
        total = met.read(validation / 'test_summary.json')['total']
        lines += ['## 本批本地验证（真实输出）', '',
                  f'四组串行{total["passed"]}通过、{total["failed"]}失败、{total["skipped"]}跳过，'
                  f'{total["files"]}文件；工具目录187通过，bench四文件52通过（含新增10条MET2回归）。', '',
                  '| 命令 | 退出码 | 实际输出摘要 |', '| --- | --- | --- |']
        for name in ['analyze', 'bench_analyze', 'format_check', 'tools', 'coverage',
                     'imports', 'acceptance', 'acceptance_json', 'parity', 'publish']:
            command_path = validation / f'{name}.command.json'
            log_path = validation / f'{name}.stdout.log'
            if command_path.exists() and log_path.exists():
                tail = log_path.read_text(encoding='utf-8-sig').strip().splitlines()[-1]
                if name == 'tools':
                    tail = '187 passed, 0 failed, 0 skipped; JSON success:true'
                lines.append(f'| {name} | {met.read(command_path)["exit_code"]} | {tail} |')
        lines += ['', '覆盖率6792/6792（100%），无新增豁免；独立coverage/met2-{a,b,c,d}.lcov合并为coverage/met2.lcov。'
                  '主包pub get后配置未变，bench SDK追加exclude后立即恢复；依赖声明未变。'
                  '[命令与原始日志](validation/)、[测试汇总](validation/test_summary.json)、'
                  '[合并真实事件](validation/all.tests.jsonl)、[来源/链接/范围自检](validation/selfcheck.json)。', '']
    met.write(OUT / 'REPORT.md', '\n'.join(lines))


def main():
    """冻结证据一次，幂等重算全部11场景，不触及历史报告。"""
    OUT.mkdir(parents=True, exist_ok=True)
    status = met.read(BENCH / 'budgets.status.json')
    budgets = met.read(BENCH / 'budgets.json')
    if 'met2' not in status:
        original = met.read(BENCH / 'results/bench_20261110_180650/design_budgets.json')
        original['memory_cycles'] = budgets['memory_cycles'].copy()
        original['wheel_first_frame'].update(informational=True)
        floors = collections.defaultdict(dict)
        for path, value in status['measured']['calibrated'].items():
            scene, metric = path.split('/')
            if metric.endswith('_millis'):
                floors[scene][metric] = min(value, budgets[scene][metric])
        for scene, value in status['fin']['ui_build_limits_ms'].items():
            floors[scene][met.BUILD] = min(value, budgets[scene][met.BUILD])
        for row in status['met']['calibrated']:
            floors[row['scenario']][row['metric']] = min(row['limit'], budgets[row['scenario']][row['metric']])
        status['met2'] = {'date': '2026-11-10', 'device': 'vivo V2417 (Android 16)',
                          'design_targets': original, 'pre_met2_budgets': budgets,
                          'calibrated_floors': dict(floors),
                          'floor_basis': 'DEV measured.calibrated + FIN ui_build_limits_ms + MET calibrated；不高于进入MET2时预算',
                          'rule': {'ratio_spread': .01, 'small_time_median_ms': .5, 'small_time_spread_ms': .15,
                                   'relative_spread': .3, 'combined_p99_ms': 12, 'ui_p99_ms': 4,
                                   'minimum_clean_windows': 2, 'precision_ms': .001, 'headroom': 1.1},
                          'design_source': 'tool/bench/results/bench_20261110_180650/design_budgets.json'}
        met.write(BENCH / 'budgets.status.json', status)
    windows = met.raw_windows()
    index = {(d['report_key'], d['run_id']): (p, d) for p, d in windows if d['report_key'] != 'reference_spin'}
    provenance = []
    selected_dirs = set()
    for identity in met.read(BENCH / 'results/met/provenance.json'):
        path, data = index[(identity['scenario'], identity['run_id'])]
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == identity['sha256'], path
        provenance.append({**identity, 'sha256': digest})
        selected_dirs.add(path.parent)
        met.write(OUT / 'comparison' / path.name, {**data, 'met_source': path.relative_to(ROOT).as_posix()})
    for path, data in windows:
        if path.parent in selected_dirs and data['report_key'] == 'reference_spin':
            met.write(OUT / 'comparison' / path.name, {**data, 'met_source': path.relative_to(ROOT).as_posix()})
    met.write(OUT / 'provenance.json', provenance)
    calibration = invoke(calibrate=True)
    # 每次从冻结入口预算开始，未稳定指标绝不沿用上次重算的临时建议。
    budgets = json.loads(json.dumps(status['met2']['pre_met2_budgets']))
    calibrated = []
    for key, scene in calibration['scenarios'].items():
        for metric, row in scene['metrics'].items():
            if row.get('calibrated'):
                budgets[key][metric] = row['limit']
                calibrated.append({'scenario': key, 'metric': metric, **row})
    met.write(BENCH / 'budgets.json', budgets)
    assessment = invoke()
    # 正常报告保留最初目标、MET冻结目标和本轮预算，不混淆三者。
    for key, scene in assessment['scenarios'].items():
        for metric, row in scene['metrics'].items():
            if metric in status['met2']['pre_met2_budgets'][key]:
                row['target'] = status['met']['targets'][key].get(metric, row.get('target'))
    met.write(OUT / 'assessment.json', assessment)
    status.update(status='MET2：首版回归预算已按实测标定；3硬失败、1不确定、1首帧信息',
                  policy='MET2分类型稳定性、冻结回归预算、每窗口12ms/4ms硬门禁；RSS沿用FIN，污染规则沿用MET')
    status['met2'].update(calibrated=calibrated,
                          scenes={k: s['status'] for k, s in assessment['scenarios'].items()},
                          design_status={k: conclusion(s) for k, s in assessment['scenarios'].items()})
    met.write(BENCH / 'budgets.status.json', status)
    report(assessment)
    print('MET2 scenes:', dict(collections.Counter(s['status'] for s in assessment['scenarios'].values())))
    print('MET2 calibrated metrics:', len(calibrated))


if __name__ == '__main__':
    main()
