"""只分析已完成的 AB2 数据，输出可复核汇总与追加文档片段。"""

import datetime as dt
import json
from pathlib import Path
import re
import statistics

ROOT = Path(__file__).resolve().parent
METRICS = [
    ('Raster平均 ms', 'average_frame_rasterizer_time_millis', 1),
    ('Raster p90 ms', '90th_percentile_frame_rasterizer_time_millis', 1),
    ('Raster p99 ms', '99th_percentile_frame_rasterizer_time_millis', 1),
    ('掉帧率 %', 'dropped_frame_ratio', 100),
    ('UI平均 ms', 'average_frame_build_time_millis', 1),
]


def read_json(path):
    """读取本批 JSON 证据。"""
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, data):
    """以 LF 保存追加片段或汇总。"""
    path.write_text(data, encoding='utf-8', newline='\n')


def main():
    """要求两个后端各三轮有效，保留失败轮，不挑选快慢样本。"""
    runs = read_json(ROOT / 'runs.json')
    manifest = read_json(ROOT / 'manifest.json')
    groups = {key: [r for r in runs if r['condition'] == key and r['valid']]
              for key in ('S', 'I')}
    if len(runs) > manifest['launchLimit'] or any(len(g) != 3 for g in groups.values()):
        raise RuntimeError('无法判定：有效样本不足或启动次数超限')
    summary = {}
    evidence = []
    for key, group in groups.items():
        stats = {}
        for name, metric, scale in METRICS:
            values = [r['metrics'][metric] * scale for r in group]
            stats[name] = dict(values=values, median=statistics.median(values),
                               range=max(values)-min(values))
        high = sum(r['metrics'][METRICS[0][1]] > 10 for r in group)
        low = sum(r['metrics'][METRICS[0][1]] <= 6 for r in group)
        summary[key] = dict(metrics=stats, high=high, low=low, count=len(group))
    if summary['S']['high']:
        conclusion = '与后端无关'
        detail = ('Skia 也出现 Raster 平均>10ms的高档轮次，按预定规则判定“与后端无关”；'
                  '本样本排除了“高档只发生在 Impeller GLES”的解释，但不能证明两后端耗时分布相同。'
                  '高档的剩余原因无法由本次数据解释，不能归因于 luckdraw 或设备驱动缺陷。')
    elif summary['S']['low'] == 3 and summary['I']['high']:
        conclusion = '双峰与 Impeller GLES 路径相关'
        detail = ('Skia 三轮均≤6ms，Impeller 仍出现>10ms高档；按预定规则判定“'
                  + conclusion + '”。这支持设备/引擎路径相关性，不证明具体引擎或驱动故障点。')
    else:
        conclusion = '无法判定'
        detail = ('本次样本未同时满足“Skia三轮均≤6ms且Impeller有高档”，'
                  'Skia也未出现>10ms高档；按预定规则无法判定，不追加轮次追求结果。')
    lines = ['\n## Skia 对照（AB2）\n',
             f'**结论：{conclusion}。** {detail}\n',
             '### 固定项与样本\n',
             f'- vivo V2417 / `10AE9K17UE0011S` / Android 16；同一 profile APK，'
             f'共{len(runs)}次启动，S/I各3次有效，按S1、I1、S2、I2、S3、I3交错；未按快慢补轮。',
             '- 复用已构建的 `tool/bench/results/perf_after/perf.apk`，'
             f'{manifest["apkBytes"]} bytes；SHA-256 `{manifest["apkSha256"]}`。',
             '- `--route=/wheel_default`选择默认auto，报告场景为`wheel_steady`；'
             '12奖品、每项128×128图片和两行文字，进入cruising后采样5秒。'
             '同一APK的参照窗口和5次RSS循环照常执行，未改设备代码。',
             '- 旧AB使用`perf_ablation/perf.apk`及`wheel_picture`，APK/缓存配置均不同，'
             '故不复用其Impeller三轮，补测I1–I3。',
             '- 每轮force-stop后静置完整60秒，启动前核对`isKeyguardShowing=false`、'
             '空闲内存≥2GiB和设置0/1/2；未修改亮度、USB常亮或其它手机设置。',
             '- 本批运行中没有额外adb轮询；引擎状态由host driver一次性读取VM service。'
             '主会话看护仍在运行，按用户告知为每120秒仅查锁屏的轻量版，无法停止；'
             '这属于未独立控制的背景条件。',
             '- 每轮驱动退出后立即按SurfaceFlinger前120行→battery顺序各读一次；'
             '随后读取window/display/logcat。时间戳及退出码见各轮`snapshot_commands.json`。\n',
             '### 原始值\n',
             '| 轮次 | Raster平均 ms | p90 ms | p99 ms | 掉帧率 % | UI平均 ms | 高档>10ms |',
             '| --- | --- | --- | --- | --- | --- | --- |']
    valid = [r for r in runs if r['valid']]
    for r in valid:
        m = r['metrics']
        cells = [f'{m[metric]*scale:.3f}' for _, metric, scale in METRICS]
        high = '是' if m[METRICS[0][1]] > 10 else '否'
        lines.append('| ' + ' | '.join([r['label'], *cells, high]) + ' |')
    lines += ['\n掉帧按设备实际帧周期，UI或Raster任一超时计一帧、去重；'
              '上述值来自FrameTiming样本，原始精度见JSON，不用timeline片段重估。\n',
              '### 三轮中位数与极差\n',
              '| 后端 | 指标 | 三轮原值 | 中位数 | 极差 max−min |',
              '| --- | --- | --- | --- | --- |']
    for key, group in summary.items():
        for name, stats in group['metrics'].items():
            values = ' / '.join(f'{v:.3f}' for v in stats['values'])
            lines.append(f'| {key} | {name} | {values} | {stats["median"]:.3f} | {stats["range"]:.3f} |')
    lines += ['\n| 后端 | 高档 Raster平均>10ms | ≤6ms轮次 |',
              '| --- | --- | --- |',
              *[f'| {key} | {g["high"]}/3 | {g["low"]}/3 |' for key, g in summary.items()],
              '\n### 后端及事后设备取证\n',
              'S显式`--no-enable-impeller`，I显式`--enable-impeller`。'
              '每轮`backend.json`保存`ext.ui.window.impellerEnabled`原始响应，'
              'driver断言请求后端与实际布尔值一致；逐轮启动命令、verbose与logcat均保留。\n',
              '| 轮次 | 引擎enabled | 启动/引擎证据 | SF即时刷新率 | 电池温度 前→后 °C | SF开始距驱动退出 s | 空闲主机 GiB | 静置 s |',
              '| --- | --- | --- | --- | --- | --- | --- | --- |']
    for r in valid:
        directory = ROOT / r['directory']
        snaps = read_json(directory / 'snapshot_commands.json')
        logs = '\n'.join((directory / file).read_text(encoding='utf-8', errors='replace')
                         for file in ('stdout.log', 'stderr.log', 'logcat_after.txt'))
        backend_lines = list(dict.fromkeys(line for line in logs.splitlines()
                              if 'Using the Impeller rendering backend' in line or
                              'Using the Skia rendering backend' in line or
                              'shell am start ' in line and '--ez enable-impeller ' in line or
                              'All tests passed. Backend verified:' in line))
        sf = (directory / 'surfaceflinger.txt').read_text(encoding='utf-8')
        refresh = re.search(r'renderRate=([\d.]+\s*Hz)', sf)
        if not refresh:
            refresh = re.search(r'activeMode=\{[^\n]*vsyncRate=([\d.]+\s*Hz)', sf)
        refresh_value = (refresh[1] if refresh and refresh.lastindex else refresh[0]) if refresh else '前120行未暴露'
        temps = []
        for file in ('battery_before.txt', 'battery_after.txt'):
            match = re.search(r'^\s*temperature:\s*(-?\d+)', (directory / file).read_text(encoding='utf-8'), re.M)
            temps.append(f'{int(match[1])/10:.1f}' if match else '未暴露')
        delay = (dt.datetime.fromisoformat(snaps['surfaceflinger']['startedAt']) -
                 dt.datetime.fromisoformat(r['endedAt'])).total_seconds()
        rest = (dt.datetime.fromisoformat(r['restEndedAt']) -
                dt.datetime.fromisoformat(r['restStartedAt'])).total_seconds()
        composition = [line for line in sf.splitlines() if re.search(r'CLIENT|DEVICE|GLES|HWC|composition', line, re.I)]
        timeline_path = next(directory.glob('wheel_steady_[0-9]*.timeline.json'))
        trace = read_json(timeline_path)['traceEvents']
        gles_count = sum(event.get('name') == 'RenderPassGLES::EncodeCommandsInReactor'
                         for event in trace)
        evidence.append(dict(label=r['label'], backend=r['backendEvidence'],
                             backendLogLines=backend_lines, surfaceFlingerRefresh=refresh_value,
                             compositionLines=composition, temperatures=temps,
                             surfaceFlingerDelaySeconds=delay, restSeconds=rest,
                             renderPassGlesTimelineEvents=gles_count))
        brief = (f'OpenGLES日志；GLES事件{gles_count}个' if any('OpenGLES' in s for s in backend_lines)
                 else f'启动enable-impeller=false；GLES事件{gles_count}个')
        lines.append(f'| {r["label"]} | {str(r["backendEvidence"]["impeller_enabled"]).lower()} | '
                     f'{brief} | {refresh_value} | {"→".join(temps)} | {delay:.3f} | '
                     f'{r["freeKB"]/1048576:.3f} | {rest:.3f} |')
    lines += ['\nSF是驱动退出后的瞬时快照，应用已由flutter drive清理，'
              '不能用事后层列表推断采样窗口内应用的CLIENT/DEVICE合成方式。'
              '前120行未暴露的字段保持“未暴露”，不把引擎OpenGLES日志等同于HWC合成类型。'
              '未在采样期间查询刷新率或温度。\n',
              'I启动日志可先出现Vulkan初始化，随后记录OpenGLES；'
              '以最后的OpenGLES日志、引擎enabled=true及采样timeline的GLES事件交叉确认。'
              'S以启动参数false和引擎enabled=false确认Skia，timeline无GLES事件仅作辅助。'
              '主机UTC与设备本地时钟未校准，不直接用两者绝对时间相减；'
              '静置和快照延迟均由主机同一时钟计算，logcat起点使用设备date。\n',
              '### 限制、保守处理与文档建议\n',
              '1. AB2明确禁止重负载验证，因此未运行flutter analyze、flutter test、pub get或build；'
              '不将既有覆盖率当成本批新采集。保留原集成测试名'
              '`perf > selected device scenario`，六轮真实通过数按驱动日志核验。',
              '2. ARCHITECTURE §8.1保留旧picture默认，当前PERF实现/报告已将默认设为auto。'
              '遵循本批指定auto，使用已构建perf_after APK；未改设计或lib。建议统一文档默认值，'
              '并将路由、APK哈希、缓存模式列为旧数据可复用的前提。',
              '3. 原AB结论中的“设备GLES路径固有双峰”超出亮度实验可证明范围；'
              '按仅追加要求保留历史文字，本节只按实际后端证据和预定判定规则下结论。',
              '4. 每后端仅三次；不能据此推断高档发生概率或解释底层原因。'
              '建议真机后端实验模板强制记录引擎状态，并明确事后SF快照的解释边界。\n']
    if conclusion == '双峰与 Impeller GLES 路径相关':
        lines += ['### 使用者建议\n',
                  '对出现同类问题的设备，可先用`flutter run --no-enable-impeller`复核；'
                  '部署时可在宿主应用的`AndroidManifest.xml`的`<application>`下设置：\n',
                  '```xml\n<meta-data\n'
                  '    android:name="io.flutter.embedding.android.EnableImpeller"\n'
                  '    android:value="false" />\n```\n',
                  '以上为设备/Flutter引擎层面的Skia规避，不应据本次结果登记为luckdraw缺陷；'
                  '本批没有修改Manifest或包代码。入口按'
                  '[Flutter官方Impeller文档](https://docs.flutter.dev/perf/impeller#android)核实。\n']
    else:
        lines += ['本次结果不足以推荐切换Skia作为该双峰的已验证规避；'
                  '没有修改Manifest或包代码。\n']
    final = read_json(ROOT / 'final_settings_confirmation.json')
    lines.append(f'最终只读实测（`{final["verifiedAt"]}`）：`mode={final["settings"]["mode"]}、'
                 f'brightness={final["settings"]["brightness"]}、stay_on={final["settings"]["stayon"]}`；'
                 '见`final_settings_confirmation.json`。本批没有写入手机设置。\n')
    lines.append('所有原值、后端响应、命令与快照：'
                 '[skia_compare](../tool/bench/results/ab_experiment/skia_compare/)；'
                 '汇总见`analysis.json`。\n')
    result = dict(conclusion=conclusion, detail=detail, launchCount=len(runs),
                  validCount=len(valid), groups=summary, evidence=evidence)
    write(ROOT / 'analysis.json', json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    write(ROOT / 'report_append.md', '\n'.join(lines))
    acceptance = ['\n## AB2 Skia 与 Impeller GLES 对照\n',
                  '| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |',
                  '| --- | --- | --- | --- | --- | --- |']
    for index, key in enumerate(('S', 'I'), 1):
        g = summary[key]
        acceptance.append(f'| AB2-0{index} | {key}后端默认auto三轮 | AB2；TEST_STRATEGY §5.3 R2-10、§7 | '
                          '`tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` '
                          f'| 真机 | 已落地：3/3；Raster中位数{g["metrics"][METRICS[0][0]]["median"]:.3f}ms；'
                          f'高档{g["high"]}/3；见AB_REPORT的Skia对照 |')
    acceptance += [
        '| AB2-03 | APK、后端响应、原值/中位数/极差、即时SF和温度证据 | AB2；TEST_STRATEGY §7 | '
        '`cmd: python tool/bench/results/ab_experiment/skia_compare/analyze_compare.py` | 工具/真机 | '
        f'已落地：{len(valid)}/{len(runs)}有效；{conclusion}；保留120秒轻量看护限制 |',
        '| AB2-04 | 结束手动最低与USB常亮只读确认 | AB2 | '
        '`cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness_mode`<br>'
        '`cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness`<br>'
        '`cmd: adb -s 10AE9K17UE0011S shell settings get global stay_on_while_plugged_in` '
        '| 真机 | 已落地：实测0、1、2；未写入设置；见skia_compare/final_settings_confirmation.json |\n']
    write(ROOT / 'acceptance_append.md', '\n'.join(acceptance))
    print(json.dumps({k: result[k] for k in ('conclusion', 'launchCount', 'validCount')}, ensure_ascii=False))
    for key, group in summary.items():
        print(key, 'rasterMedian=', group['metrics'][METRICS[0][0]]['median'], 'high=', group['high'])


if __name__ == '__main__':
    main()
