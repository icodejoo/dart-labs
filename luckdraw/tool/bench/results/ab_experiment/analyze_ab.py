"""从 AB 原始记录生成中文报告，不追加手机运行。"""

from collections import defaultdict
import hashlib
import json
from pathlib import Path
import re
import statistics as stats

ROOT = Path(__file__).resolve().parent
PACKAGE = ROOT.parents[3]
MEAN = 'average_frame_rasterizer_time_millis'
UI = 'average_frame_build_time_millis'
METRICS = {
    'Raster平均 ms': MEAN,
    'Raster p90 ms': '90th_percentile_frame_rasterizer_time_millis',
    'Raster p99 ms': '99th_percentile_frame_rasterizer_time_millis',
    '掉帧率 %': 'dropped_frame_ratio',
    'UI平均 ms': UI,
    'UI+Raster平均 ms': 'average_build_plus_raster_millis',
}


def read(path):
    """读取 UTF-8 原始记录。"""
    return json.loads(path.read_text(encoding='utf-8'))


def value(text, pattern):
    """找不到的字段明确记录为不可见。"""
    match = re.search(pattern, text, re.M)
    return match[1].strip() if match else '未暴露'


def selected(text, pattern):
    """保留可核验字段原文，不推测厂商字段含义。"""
    return [line.strip() for line in text.splitlines() if re.search(pattern, line, re.I)]


def thermals(text):
    """按 zone 配对名称和温度，保留无效哨兵及不可读项。"""
    rows = []
    for block in text.split('/sys/class/thermal/')[1:]:
        lines = block.strip().splitlines()
        readings = [int(line) for line in lines[1:] if re.fullmatch(r'-?\d+', line)]
        rows.append(dict(zone=lines[0], name=lines[1] if len(lines) > 1 else '不可读',
                         milliC=readings[-1] if readings else None))
    return rows


def timeline(path):
    """配对嵌套事件，单独比较 GLES 编码均值，禁止跨层相加。"""
    stacks, times = defaultdict(list), defaultdict(list)
    for event in read(path)['traceEvents']:
        thread = event.get('pid'), event.get('tid')
        phase = event.get('ph')
        if phase == 'B':
            stacks[thread].append(event)
        elif phase == 'E' and stacks[thread]:
            begin = stacks[thread].pop()
            duration = event['ts'] - begin['ts']
            if duration >= 0:
                times[begin.get('name')].append(duration / 1000)
        elif phase == 'X':
            times[event.get('name')].append(event.get('dur', 0) / 1000)
    names = ('Rasterizer::DoDraw', 'SurfaceFrame::Encode',
             'RenderPassGLES::EncodeCommandsInReactor', 'CreateGlyphAtlas', 'PAINT')
    return {name: dict(count=len(times[name]), mean_ms=stats.mean(times[name]))
            for name in names if times.get(name)}


def main():
    """核对九次有效轮后生成统计、快照表和有边界的结论。"""
    records = read(ROOT / 'runs.json')
    valid = [r for r in records if r['valid']]
    groups = {c: [r for r in valid if r['condition'] == c] for c in 'ABC'}
    assert all(len(group) == 3 for group in groups.values()), '各条件必须恰好三次有效轮'
    manifest = read(ROOT / 'manifest.json')
    restored = read(ROOT / 'restored_settings.json')
    assert restored['settings'] == dict(mode='0', brightness='1', stayon='2')
    raw, snapshots = [], []
    for record in valid:
        folder = ROOT / record['directory']
        metric = dict(record['metrics'])
        metric['average_build_plus_raster_millis'] = metric[MEAN] + metric[UI]
        record['derivedMetrics'] = metric
        texts = {name: (folder / f'{name}.txt').read_text(encoding='utf-8')
                 for name in ('battery_before', 'battery_after', 'display', 'surfaceflinger', 'thermal', 'getprop')}
        zones = thermals(texts['thermal'])
        cpu = [z['milliC'] / 1000 for z in zones
               if z['name'].startswith('cpu-') and z['milliC'] is not None and z['milliC'] > 0]
        snapshot = dict(label=record['label'], endedAt=record['endedAt'],
            settingsBefore=record['settingsBefore'], settingsAfter=record['settingsAfter'],
            batteryBefore=int(value(texts['battery_before'], r'^\s*level:\s*(\d+)')),
            batteryAfter=int(value(texts['battery_after'], r'^\s*level:\s*(\d+)')),
            tempBefore=int(value(texts['battery_before'], r'^\s*temperature:\s*(\d+)')) / 10,
            tempAfter=int(value(texts['battery_after'], r'^\s*temperature:\s*(\d+)')) / 10,
            displayBrightness=value(texts['display'], r'^\s*Display Brightness=(.*)'),
            currentScreenBrightness=value(texts['display'], r'^\s*mCurrentScreenBrightness=(.*)'),
            displayMode=value(texts['display'], r'^\s*mActiveModeId=(.*)'),
            sfRenderRate=value(texts['surfaceflinger'], r'^\s*renderRate=(.*)'),
            policy=value(texts['display'], r'^\s*mPowerRequest=policy=([^,]+)'),
            lowPower=value(texts['display'], r'^\s*mLowPowerMode=(.*)'),
            cpuMin=min(cpu) if cpu else None, cpuMax=max(cpu) if cpu else None,
            zones=zones,
            displayFields=selected(texts['display'], r'brightness|refresh.?rate|active.*mode|low.?power|power.?sav|dimming'),
            compositionFields=selected(texts['surfaceflinger'], r'composition|client|device|gles|egl|renderengine|renderRate|activeMode'),
            thermalPerformanceProperties=selected(texts['getprop'], r'thermal|perf|power.?sav|refresh|dimming'),
            timeline=timeline(next(folder.glob('wheel_steady_[0-9]*.timeline.json'))))
        snapshots.append(snapshot)
        raw.append(dict(label=record['label'], **{label: metric[key] * (100 if key == 'dropped_frame_ratio' else 1)
                                               for label, key in METRICS.items()}))
    summary = {}
    for condition, group in groups.items():
        summary[condition] = dict(high=sum(r['metrics'][MEAN] > 10 for r in group),
                                  low=sum(r['metrics'][MEAN] <= 10 for r in group), metrics={})
        for label, key in METRICS.items():
            numbers = [r['derivedMetrics'][key] * (100 if key == 'dropped_frame_ratio' else 1) for r in group]
            summary[condition]['metrics'][label] = dict(raw=numbers, median=stats.median(numbers),
                min=min(numbers), max=max(numbers), range=max(numbers)-min(numbers))
    data = dict(launches=len(records), valid=len(valid), raw=raw, summary=summary, snapshots=snapshots)
    (ROOT / 'analysis.json').write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')
    a, b = summary['A']['high'], summary['B']['high']
    if a == 0 and b > 0:
        verdict = '按预定判据，低亮度设置是本次高档轮次的诱因；基准应在正常亮度下测。'
    elif a > 0 and b > 0:
        verdict = ('按预定分类，A、B均出现高档，记为“与亮度无关，是设备 GLES 路径的固有双峰”。'
                   '这一分类仅说明恢复设置后仍能复现，不能证明物理亮度完全无影响或确认设备驱动缺陷。')
    else:
        verdict = '无法判定：本次 A/B 对照未满足预设的两类因果判据。'
    lines = [
        '# AB 受控真机实验报告', '', f'日期：2026-11-10；vivo V2417 / {manifest["device"]} / Android 16。', '',
        f'**结论：恢复原设置仍复现双峰；本轮无法区分设备设置/测量干扰与真实缺陷。{verdict}**', '',
        f'共 {len(records)} 次启动，{len(valid)} 次有效，三条件各3轮；未因快慢追加轮次。', '',
        '## 固定项与执行方式', '',
        '- 工作副本 `C:\\ldp\\luckdraw`，不修改 lib、不构建、不新增依赖。',
        '- 复用消融原版 `tool/bench/results/perf_ablation/perf.apk`，而非修复后默认 auto APK。',
        f'- APK：{manifest["apkBytes"]} bytes；SHA-256 `{manifest["apkSha256"]}`。',
        '- 固定 profile、`--use-application-binary`、`--route=/wheel_picture`、12奖品/图片/两行文字，`wheel_steady` cruising 5秒。',
        '- 原测试名逐字保留：`perf > selected device scenario`。同一 APK 也执行原参照窗口和5次 RSS 循环，未改应用场景。',
        '- 顺序 A1,B1,C1,A2,B2,C2,A3,B3,C3；每轮设置后强停并静置完整60秒；每次启动前确认 `isKeyguardShowing=false` 和主机空闲≥2GiB。',
        '- A/C：写入`screen_brightness_mode=1`、`screen_brightness=12`；B：mode=0、brightness=1；所有条件 `stayon usb`。自动模式允许系统动态改写亮度值，实际读回逐轮保留，不关闭自动模式强行固定。',
        '- 主机 driver 仅调整 metrics 导入 URI、当前目录和输出目录，使结果与通信日志写入本批授权目录；设备 APK 不变。',
        '- 所有条件运行中均无本批额外 adb 查询，仅等待驱动；结束后立即依次读 battery/window/display/SurfaceFlinger 前200行/getprop/thermal/logcat。各命令起止时间和退出码保留。',
        '- 主会话看护脚本仍每15秒查询 power/window等；不能暂停。A与C没有可控制的轮询差异，C只作重复对照，不能评价“停看护”的因果效果。', '',
        '## 每轮原值', '',
        '| 轮次 | Raster平均 ms | p90 ms | p99 ms | 掉帧率 % | UI平均 ms | UI+Raster平均 ms | 档位 |',
        '| --- | --- | --- | --- | --- | --- | --- | --- |',
    ]
    for row in raw:
        lines.append('| '+row['label']+' | '+' | '.join(f'{row[label]:.3f}' for label in METRICS)+' | '+('高' if row['Raster平均 ms'] > 10 else '低')+' |')
    lines += ['', '掉帧率：UI或Raster任一超过实际帧周期计一帧，去重；高档定义为Raster平均>10ms。',
              'UI+Raster平均为同一FrameTiming样本的两个线程耗时均值之和；不等于端到端呈现延迟或FrameTiming.totalSpan，原APK未记录后两者。', '',
              '## 三条件中位数与极差', '',
              '| 条件 | 指标 | 三轮原值 | 中位数 | 极差 max−min |', '| --- | --- | --- | --- | --- |']
    for condition, group in summary.items():
        for label, values in group['metrics'].items():
            lines.append(f'| {condition} | {label} | '+ ' / '.join(f'{n:.3f}' for n in values['raw'])+f' | {values["median"]:.3f} | {values["range"]:.3f} |')
    lines += ['', '| 条件 | 高档 | 低档 |', '| --- | --- | --- |']
    for condition, group in summary.items():
        lines.append(f'| {condition} | {group["high"]} | {group["low"]} |')
    lines += ['', '## 运行后显示、合成与温度快照', '',
              '| 轮次 | 电量 前→后 % | 电池温度 前→后 °C | CPU传感器范围 °C | 亮度设置读回 前→后 | USB常亮读回 前→后 | Display Brightness | 设置对应当前亮度 | Display模式 / SF Hz | policy / lowPower |',
              '| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |']
    for s in snapshots:
        lines.append(f'| {s["label"]} | {s["batteryBefore"]}→{s["batteryAfter"]} | {s["tempBefore"]:.1f}→{s["tempAfter"]:.1f} | {s["cpuMin"]}–{s["cpuMax"]} | {s["settingsBefore"]["brightness"]}→{s["settingsAfter"]["brightness"]} | {s["settingsBefore"]["stayon"]}→{s["settingsAfter"]["stayon"]} | {s["displayBrightness"]} | {s["currentScreenBrightness"]} | {s["displayMode"]} / {s["sfRenderRate"]} | {s["policy"]} / {s["lowPower"]} |')
    lines += ['', '表中为运行后的瞬时快照，不能当作整个5秒窗口的GPU频率/面板亮度记录。',
              'USB常亮不保证policy一直为BRIGHT；自动亮度设置值12也不保证实际面板亮度高于手动1。保持指定设置，不自行调整实验变量。',
              'SurfaceFlinger前200行与getprop完整输出分别保存；逐轮相关字段见 `analysis.json`。驱动退出会卸载应用，快照显示的是退出后的层，不能反推应用窗口的HWC/GPU合成方式。',
              'thermal原始值、名称、无效哨兵与不可读项均保留；CPU范围排除负哨兵，不把-273000当实测温度。未暴露的DC dimming/GPU频率字段不猜测。', '',
              '| 轮次 | HWC CLIENT/DEVICE类型 | DC dimming | 温控/性能属性 |',
              '| --- | --- | --- | --- |']
    for s in snapshots:
        lines.append(f'| {s["label"]} | 前200行未明确暴露应用合成类型 | 未明确暴露 | thermal HAL/thermal-engine/vperf HAL状态原文见analysis.json |')
    lines += ['',
              '| 轮次 | GLES编码平均 ms | SurfaceFrame编码平均 ms | PAINT平均 ms |', '| --- | --- | --- | --- |']
    for s in snapshots:
        def event(name):
            return f'{s["timeline"][name]["mean_ms"]:.3f}' if name in s['timeline'] else '未记录'
        lines.append(f'| {s["label"]} | {event("RenderPassGLES::EncodeCommandsInReactor")} | {event("SurfaceFrame::Encode")} | {event("PAINT")} |')
    lines += ['', '这些timeline事件包含子事件，只逐项比较，不能相加或用来区分GPU执行、CPU调度和驱动等待。', '',
              '## 异常启动', '']
    failures = [r for r in records if not r['valid']]
    if failures:
        for failure in failures:
            lines.append(f'- 第{failure["launchNumber"]}次启动 {failure["label"]}：exit={failure["exitCode"]}，timeout={failure.get("timedOut")}，耗时{failure["elapsedSeconds"]:.3f}秒；无有效性能汇总。目录 `{failure["directory"]}`。')
        lines.append('B2首次安装后没有Flutter服务日志，按5分钟上限结束自有进程树并恢复B；窗口/事后日志无锁屏证据，未见明确崩溃原因。核对无自有Dart孤儿进程后复用同一APK、重新静置60秒补跑该无效轮，不将其当作高/低档样本；失败及额外冷却时间是实验限制。')
    else:
        lines.append('无无效启动或补跑。')
    if (ROOT / 'setup_anomalies.json').exists():
        lines.append('C3第一次配置时，自动模式下写入12后立即读回23，严格核对中止于启动之前并恢复B，不计启动；续跑同样写入12后系统读回20，结束后为50。保留自动模式并如实记录，没有关闭自动亮度或新增应用启动。自动更新意味着C3不是固定数值12的物理亮度对照；见setup_anomalies.json与每轮设置读回。')
    lines.append('B3启动前stay_on_while_plugged_in=2，运行结束后快照之后读回0；只能确认发生过变化，无法确定在测量窗口内还是驱动退出清理阶段，也无证据归因于某个进程。其后重新写入USB常亮；最终独立确认0/1/2。B3与C3的事后policy为BRIGHT，其余七次为DIM。保留九份有效性能数据，不额外追加有效轮；控制条件完整性不足限制因果判定。')
    lines += ['',
              '## 判定边界与建议', '', verdict,
              '每组只有3轮，所有轮共享同一看护进程、USB供电与驱动通道；无法独立排除看护、时间漂移、温控或显示策略，也不能由双峰直接宣布库内缺陷或驱动缺陷。', '',
              '建议主会话将性能测量规程固定为：测量时手动固定正常亮度（例如96/255，数值需先核验实际面板亮度），关闭自动调节、USB常亮、屏幕超时覆盖整轮，确认未进入DIM；固定环境光，记录运行前后亮度/常亮/刷新率/省电状态。结束后恢复用户要求的B。此为后续建议，本批没有执行这组额外设置或追加启动。',
              '看护改为启动前解锁检查、测量窗口暂停dumpsys、结束后立即恢复；无法暂停则保留同一看护且将其标为受干扰条件，不能声称无轮询基准。不要在运行中另开状态采集。',
              '沿用预定三轮及全部原值；锁屏/超时作废才补，双峰不能靠筛选低档轮获得通过。需定位频率/驱动等待时另行设计跟踪，不在本批增加启动或改库。', '',
              '## 恢复与验证', '',
              f'结束恢复B，实测核验时间 `{restored["verifiedAt"]}`：mode=0、brightness=1、stay_on_while_plugged_in=2。',
              'lib/pubspec/analysis_options哈希核对、门禁结果与交付清单见 `verification.json`；无提交、无暂存、无push。', '',
              '本批按明确资源约束不运行pub get/build/flutter test/flutter analyze/覆盖率重采集；不将PERF批次历史输出冒充AB门禁结果。仅运行只读静态脚本与新driver格式检查，真实输出附存。', '',
              '## 文档冲突、偏离与修正建议', '',
              '1. TEST_STRATEGY §7.3要求三轮极差>30%整组重跑，与本批每条件恰好3轮/≤15次启动冲突；按本批授权不因波动追加。',
              '2. 通用实现卡要求pub get/test/analyze与本批禁止重负载、只写三处冲突；采用专批约束，代码门禁未重跑；没有新增库测试或覆盖豁免。',
              '3. C名义“暂停看护”，但主进程无法停用；依指定近似，A/C均不增加运行中轮询，无法隔离看护效应。建议文档将C写为重复对照，待真正停看护后再称干扰A/B。',
              '4. 运行中核验锁屏与禁止运行中adb采集冲突；按后者执行，用运行前后明确状态及结束后日志追溯；未检出事件不等于连续状态证明。建议后续用独立看护事件记录提供连续证据。',
              '5. 预定“A/B均高→固有双峰”结论强于实验可辨识性；保留预定分类及观察值，同时明确只能排除“切回原设置即可消失”，不能证明固有驱动缺陷或物理亮度无关。',
              '6. 原driver硬编码主机build输出，与只写三处冲突；仅在本批results内派生driver更改输出路径，不改原driver/APK/场景。',
              '7. 原APK没有totalSpan；按UI+Raster算术和报告平均处理时间，建议未来独立基准显式记录FrameTiming.totalSpan，避免将处理耗时与呈现延迟混称。', '',
              '8. 自动模式会改写screen_brightness（C3实测23/20），无法同时保证自动调节且始终保持数值12；保留命令输入12、自动模式与实际读回，未改变B。建议后续将“写入设置”与“实际亮度有效范围”分别定义，并固定环境光。', '',
              '9. B3运行后USB常亮读回0，前后状态无法定位变化时间；保留性能有效样本并标明控制条件受限，不声称所有窗口中USB常亮持续为2。建议将驱动退出清理与测量状态分开记录，并在每轮结束恢复2。', '',
              '所有原始值、命令、快照和锁屏候选日志位于 `tool/bench/results/ab_experiment/`。']
    (PACKAGE / 'docs/AB_REPORT.md').write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')
    print(json.dumps({c: dict(median=summary[c]['metrics']['Raster平均 ms']['median'], high=summary[c]['high']) for c in 'ABC'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
