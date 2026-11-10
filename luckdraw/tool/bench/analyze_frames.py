"""只读 Chrome trace，按引擎帧号关联 UI/Raster；不调用设备或重写历史数据。"""
import argparse
import collections
import gzip
import hashlib
import json
import pathlib
import statistics
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'tool/bench/results/pend_offline'
SCENES = ('slot_raster', 'grid_steady', 'lotto_draw', 'lots_shaking')
INTERESTING = ('SurfaceFrame::Encode', 'SurfaceFrame::Submit',
               'RenderPassGLES::EncodeCommandsInReactor', 'CreateGlyphAtlas',
               'LayerTree::Paint', 'LAYOUT', 'PAINT', 'BUILD', 'Animate',
               'SEMANTICS', 'Dart_InvokeClosure', 'CollectNewGeneration', 'Scavenge')


def read(path):
    """读取 UTF-8 JSON，兼容无损 gzip。"""
    with (gzip.open(path, 'rt', encoding='utf-8') if path.suffix == '.gz'
          else path.open(encoding='utf-8')) as stream:
        return json.load(stream)


def spans(events):
    """恢复 B/E、X 和 b/e 区间；裁在窗口边界的事件不伪造时长。"""
    stacks = collections.defaultdict(list)
    asynchronous = collections.defaultdict(list)
    result = []
    unmatched = collections.Counter()
    for event in sorted((e for e in events if 'ts' in e), key=lambda e: e['ts']):
        phase = event['ph']
        key = (event.get('pid'), event.get('tid'))
        if phase == 'B':
            stacks[key].append(event)
        elif phase == 'E':
            if not stacks[key]:
                unmatched['left_boundary'] += 1
                continue
            begin = stacks[key].pop()
            if event.get('name') and event['name'] != begin['name']:
                raise ValueError(f"B/E 错配: {begin['name']} / {event['name']}")
            result.append({**begin, 'end': event['ts'], 'dur': event['ts'] - begin['ts']})
        elif phase == 'X':
            result.append({**event, 'end': event['ts'] + event['dur']})
        elif phase in ('b', 'e'):
            async_key = (event.get('pid'), event.get('cat'), event['name'],
                         str(event.get('id', event.get('id2'))))
            if phase == 'b':
                asynchronous[async_key].append(event)
            elif asynchronous[async_key]:
                begin = asynchronous[async_key].pop()
                result.append({**begin, 'end': event['ts'], 'dur': event['ts'] - begin['ts']})
            else:
                unmatched['async_left_boundary'] += 1
    unmatched['right_boundary'] = sum(map(len, stacks.values()))
    unmatched['async_right_boundary'] = sum(map(len, asynchronous.values()))
    return sorted(result, key=lambda s: s['ts']), dict(unmatched)


def inside(parent, child):
    """判断同线程完整包含；不会把重叠的其它帧事件算进当前帧。"""
    return (parent['tid'] == child['tid'] and parent['ts'] <= child['ts']
            and child['end'] <= parent['end'])


def paired_frames(intervals):
    """以 Animator/DoDraw 的 frame_number 连接异步 Frame 与 GPU 区间。"""
    animators = {s['args']['frame_number']: s for s in intervals
                 if s['name'] == 'Animator::BeginFrame'}
    ui_frames = [s for s in intervals if s['name'] == 'Frame']
    gpu_frames = [s for s in intervals if s['name'] == 'GPURasterizer::Draw']
    result = []
    for raster in (s for s in intervals if s['name'] == 'Rasterizer::DoDraw'):
        number = raster['args'].get('frame_number')
        animator = animators.get(number)
        if animator is None:
            continue
        # Frame 的 finalize 可能略晚于 Animator::BeginFrame 返回。
        candidates = [s for s in ui_frames if s['tid'] == animator['tid']
                      and animator['ts'] <= s['ts'] < animator['end']]
        parents = [s for s in gpu_frames if inside(s, raster)]
        if len(candidates) != 1 or len(parents) != 1:
            raise ValueError(f'帧 {number} 不能唯一关联: UI={len(candidates)} GPU={len(parents)}')
        ui, gpu = candidates[0], parents[0]
        children = [s for s in intervals if inside(ui, s) or inside(gpu, s)]
        costs = collections.Counter()
        ui_costs = collections.Counter()
        raster_costs = collections.Counter()
        for s in children:
            if s['name'] not in ('Frame', 'GPURasterizer::Draw', 'Rasterizer::DoDraw'):
                costs[s['name']] += s['dur']
                (ui_costs if inside(ui, s) else raster_costs)[s['name']] += s['dur']
        result.append({'frame_number': number, 'ts': ui['ts'], 'ui_us': ui['dur'],
                       'raster_us': gpu['dur'], 'combined_us': ui['dur'] + gpu['dur'],
                       'events_us': dict(costs), 'ui_thread': ui['tid'],
                       'raster_thread': gpu['tid'], 'ui_events_us': dict(ui_costs),
                       'raster_events_us': dict(raster_costs), 'animator_us': animator['dur'],
                       'raster_ts': gpu['ts']})
    return sorted(result, key=lambda f: f['ts'])


def analyze(path, formal):
    """分析一个未污染窗口，核对 SDK 时长数组与 trace 重建帧身份。"""
    summary = read(path)
    trace_path = pathlib.Path(str(path).replace('.timeline_summary.json', '.timeline.json'))
    if not trace_path.exists():
        trace_path = pathlib.Path(str(trace_path) + '.gz')
    raw = read(trace_path)['traceEvents']
    intervals, clipped = spans(raw)
    frames = paired_frames(intervals)
    builds = summary['frame_build_times']
    rasters = summary['frame_rasterizer_times']
    # SDK 分别按线程排序，本批必须核对一一同序且 frame_number 严格递增。
    assert [s['dur'] for s in intervals if s['name'] == 'Frame'] == builds, path
    assert [s['dur'] for s in intervals if s['name'] == 'GPURasterizer::Draw'] == rasters, path
    assert all(int(a['frame_number']) < int(b['frame_number']) for a, b in zip(frames, frames[1:]))
    for index, frame in enumerate(frames):
        frame['index'] = index + 1
        frame['offset_ms'] = (frame['ts'] - frames[0]['ts']) / 1000
        frame['spike'] = frame['combined_us'] > 12000 or frame['ui_us'] > 4000
    paired_starts = {f['ts'] for f in frames}
    unpaired = [{'ts': s['ts'], 'ui_us': s['dur']} for s in intervals
                if s['name'] == 'Frame' and s['ts'] not in paired_starts]
    gc = []
    for span in intervals:
        if span['name'] not in ('CollectNewGeneration', 'Scavenge'):
            continue
        overlaps = [f['index'] for f in frames if
                    span['ts'] < f['ts'] + f['ui_us'] and span['end'] > f['ts']]
        gc.append({'name': span['name'], 'tid': span['tid'], 'dur_us': span['dur'],
                   'offset_ms': (span['ts'] - frames[0]['ts']) / 1000,
                   'ui_overlap_indices': overlaps})
    return {'source': path.relative_to(ROOT).as_posix(), 'trace': trace_path.relative_to(ROOT).as_posix(),
            'sha256': hashlib.sha256(trace_path.read_bytes()).hexdigest(),
            'scenario': summary['report_key'], 'run_id': summary['run_id'],
            'formal': summary['run_id'] in formal, 'clipped': clipped, 'frames': frames,
            'unpaired_ui': len(builds) - len(frames), 'unpaired_raster': len(rasters) - len(frames),
            'unpaired_ui_frames': unpaired,
            'gc_intervals': gc,
            'summary_p99_ms': summary['99th_percentile_build_plus_raster_millis'],
            'special_events': dict(collections.Counter(e['name'] for e in raw
                if any(w in e['name'].lower() for w in ('toimage', 'imagedecode', 'decodeimage', 'gc',
                                                      'scavenge', 'collectnewgeneration', 'atlas', 'luckdraw')))),
            'ui_mean_ms': statistics.mean(builds) / 1000,
            'raster_mean_ms': statistics.mean(rasters) / 1000}


def write(path, text):
    """写入本批产物，统一 LF。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8', newline='\n')


def report(windows):
    """输出完整尖峰清单与嵌套事件累计表，不把嵌套时长相加当 CPU。"""
    lines = ['# PEND 离线逐帧根因分析', '',
             '仅分析保存的原始 timeline，没有连接手机、adb、Gradle、build 或 drive。', '',
             '## 方法与边界', '',
             '从 MET 全量130窗口索引选择四场景全部未污染窗口；按 report_key/run_id 去重，保留旧 DEV 与正式 PERF 身份。'
             '不混合它们计算当前实现的预算。B/E 用同线程栈配对，b/e 按进程/分类/名称/id 配对，X 直接读 dur。'
             '按 Animator::BeginFrame 与 Rasterizer::DoDraw 的 frame_number 关联异步 Frame 和 GPURasterizer::Draw；'
             '逐项核对重建 UI/Raster 时长数组与 SDK summary 完全相等，拒绝按时间最近或独立分位数相加。', '',
             '尖峰定义：同帧 UI Frame + GPURasterizer::Draw >12ms，或 UI Frame >4ms。位置从窗口首个完整 Frame 起算，序号从1开始。'
             '这里是 SDK trace 区间；保存的硬门禁来自 FrameTiming，二者采集边界可能不同，原 MET2 FrameTiming P99 仍为门禁依据。'
             '表内事件为包含时长（inclusive），父子嵌套不能相加；墙钟时间不等于 CPU 执行时间。'
             '普通帧指上述条件都不触发的帧。未闭合的边界事件记录到 JSON，不伪造耗时。', '',
             '所有逐帧原始统计、事件时长、帧号、来源与 SHA-256：'
             '[frames.json](../tool/bench/results/pend_offline/frames.json)。离线重放：'
             '`python tool/bench/analyze_frames.py`。', '',
             '## 每窗口汇总', '',
             '| 场景 / run_id | 身份 | 帧数 | 合计>12 / UI>4 / 并集 | 尖峰位置 ms | UI/Raster均值 ms |',
             '| --- | --- | --- | --- | --- | --- |']
    for window in windows:
        frames = window['frames']
        spikes = [f for f in frames if f['spike']]
        position = '无' if not spikes else f'{min(f["offset_ms"] for f in spikes):.1f}–{max(f["offset_ms"] for f in spikes):.1f}'
        lines.append(f'| {window["scenario"]} / {window["run_id"]} | {"MET2正式" if window["formal"] else "历史DEV"} | '
                     f'{len(frames)} | {sum(f["combined_us"] > 12000 for f in frames)} / '
                     f'{sum(f["ui_us"] > 4000 for f in frames)} / {len(spikes)} | {position} | '
                     f'{window["ui_mean_ms"]:.3f}/{window["raster_mean_ms"]:.3f} |')
    for scene in SCENES:
        selected = [w for w in windows if w['scenario'] == scene]
        lines += ['', f'## {scene} 尖峰帧完整清单', '',
                  '| run_id | 帧序号 / 引擎帧号 | 位置 ms | UI / Raster / 合计 ms | 最长三个内层事件 ms（含嵌套） | UI最长事件 ms |',
                  '| --- | --- | --- | --- | --- | --- |']
        for window in selected:
            for frame in window['frames']:
                if not frame['spike']:
                    continue
                top = sorted(frame['events_us'].items(), key=lambda p: -p[1])[:3]
                ui_top = sorted(frame['ui_events_us'].items(), key=lambda p: -p[1])[:2]
                lines.append(f'| {window["run_id"]} | {frame["index"]} / {frame["frame_number"]} | '
                             f'{frame["offset_ms"]:.3f} | {frame["ui_us"]/1000:.3f} / '
                             f'{frame["raster_us"]/1000:.3f} / {frame["combined_us"]/1000:.3f} | '
                             + '；'.join(f'{name} {cost/1000:.3f}' for name, cost in top) + ' | '
                             + '；'.join(f'{name} {cost/1000:.3f}' for name, cost in ui_top) + ' |')
        if not any(f['spike'] for w in selected for f in w['frames']):
            lines.append('| — | 无尖峰 | — | — | — | — |')
        lines += ['', '位置统计（每秒分桶；首5帧单列；仅说明分布，不推断随机性）：', '',
                  '| run_id | 首5帧尖峰数 | 秒桶 [0,1,2,3,4] | 无配对UI / Raster | 无配对UI>4ms |',
                  '| --- | --- | --- | --- | --- |']
        for window in selected:
            spikes = [f for f in window['frames'] if f['spike']]
            bins = [sum(int(f['offset_ms'] // 1000) == second for f in spikes) for second in range(5)]
            lines.append(f'| {window["run_id"]} | {sum(f["index"] <= 5 for f in spikes)} | {bins} | '
                         f'{window["unpaired_ui"]} / {window["unpaired_raster"]} | '
                         f'{sum(f["ui_us"] > 4000 for f in window["unpaired_ui_frames"])} |')
        lines += ['', '### 事件归因与普通帧对照', '',
                  '| 身份 / 事件 | 尖峰累计 ms / 每帧均值 ms | 普通累计 ms / 每帧均值 ms |',
                  '| --- | --- | --- |']
        for formal in (True, False):
            frames = [f for w in selected if w['formal'] == formal for f in w['frames']]
            if not frames:
                continue
            groups = [[f for f in frames if f['spike']], [f for f in frames if not f['spike']]]
            names = set(INTERESTING)
            for frame in groups[0]:
                names.update(name for name, _ in sorted(frame['events_us'].items(), key=lambda p: -p[1])[:4])
            for name in sorted(names):
                cells = []
                for group in groups:
                    total = sum(f['events_us'].get(name, 0) for f in group) / 1000
                    cells.append(f'{total:.3f} / {total/len(group):.3f}' if group else '—（无帧）')
                lines.append(f'| {"正式" if formal else "历史"} / {name} | {cells[0]} | {cells[1]} |')
        lines += ['', '各窗口普通帧事件均值（ms，框架事件包含时长）：', '',
                  '| run_id | 普通帧数 | Encode | GLES Encode | PAINT | Animate | COMPOSITING |',
                  '| --- | --- | --- | --- | --- | --- | --- |']
        for window in selected:
            ordinary = [f for f in window['frames'] if not f['spike']]
            means = [statistics.mean(f['events_us'].get(name, 0) for f in ordinary)/1000
                     for name in ('SurfaceFrame::Encode', 'RenderPassGLES::EncodeCommandsInReactor',
                                  'PAINT', 'Animate', 'COMPOSITING')]
            lines.append(f'| {window["run_id"]} | {len(ordinary)} | ' + ' | '.join(f'{v:.3f}' for v in means) + ' |')
    lines += ['', '## GC 完整区间表（含UI空闲区间）', '',
              '| 场景 / run_id | 事件 | 线程ID | 位置 ms | 耗时 ms | 与UI Frame重叠序号 |',
              '| --- | --- | --- | --- | --- | --- |']
    for window in windows:
        for gc in window['gc_intervals']:
            lines.append(f'| {window["scenario"]} / {window["run_id"]} | {gc["name"]} | '
                         f'{gc["tid"]} | {gc["offset_ms"]:.3f} | {gc["dur_us"]/1000:.3f} | '
                         f'{gc["ui_overlap_indices"]} |')
    lines += ['', 'CollectNewGeneration/Scavenge 是嵌套的区间，不能累加为独立停顿。'
              '本批列出的GC与UI Frame均无时间重叠；slot的6.857ms收集在1.672秒，'
              '并非1.050/1.883/4.067秒的尖峰。分配来源和GC是否影响窗口外响应无法由这些事件判定。', '',
              '## 分布与根因结论表', '',
              '| 场景 | 全部未污染 / 正式尖峰数 | 位置 | 事件层定位 | 代码根因结论 |',
              '| --- | --- | --- | --- | --- |',
              '| slot_raster | 5 / 5 | 第64/65/114/245/246帧，1.050–4.084秒；成对突发，非开头几帧 | Encode累计61.273ms；GLES Encode60.209ms，普通帧Encode均值1.695ms | 框架/驱动路径长墙钟；无法判定库或设备根因 |',
              '| grid_steady | 10 / 8 | 正式1.617–4.901秒，连续2–3帧突发及单次UI；历史另2帧 | 正式Encode尖峰与GLES嵌套；UI单次COMPOSITING2.550ms，未见重复BUILD | 无法判定；现有缓存实现未证明有可避免重复工作 |',
              '| lotto_draw | 171 / 24 | 正式0.450–4.551秒，散布搅拌及开奖；不是只在开头，无固定周期证据 | Raster编码/提交及UI PAINT/COMPOSITING；见逐帧UI列 | 无函数采样栈，无法判定可避免分配/布局 |',
              '| lots_shaking | 0 / 0 | 未污染两窗口均无12/4ms尖峰 | 普通帧Raster均值4.760/3.139ms；逐窗口Encode/GLES成本有差异 | 无法判定；窗口不稳定仍待复测 |', '',
              '保存 trace 无 ImageDecode/Picture.toImage/实际分配栈可用于以上尖峰归因；'
              'CreateGlyphAtlas 在有文字的场景是反复出现的引擎区间，累计表并不等同于新建整张图集。'
              '未配对帧只出现在采集边界，已列出而不补零；本批这些帧均未触发UI>4ms。', '',
              '## slot 图集构建与结论限制', '',
              '`SlotPainter` 构造时调用 `SlotAtlas.prepare`，后者在布局/图片身份改变时同步调用 `Picture.toImageSync`；'
              '稳态 paint 仅回放图集。`runSteadyBench` 在 mount、图片 ready、稳定等待、play 与 cruising 后才打开 traceAction。'
              '所有保存的 slot_raster trace 中没有 toImage/图集构建打点，不能给出进入 raster 模式那一帧的帧号、耗时或实际线程。'
              '源代码表明调用发起于布局所在 UI isolate，但位图真正执行/上传的线程、耗时及是否影响进入首帧无法从本次 trace 判定。'
              '不能把稳态 SurfaceFrame::Encode 尖峰冒充图集构建；不据此搬动构建时机。', '',
              '## 根因判定与待真机复测', '',
              '事件层定位与代码根因判定分开：SurfaceFrame::Encode、GLES Reactor、CreateGlyphAtlas 等是框架/引擎事件，'
              '它们的长墙钟区间可以包含驱动等待与线程抢占，不能仅凭名称断言设备故障或库工作过多。'
              'UI 的 Animate/PAINT/SEMANTICS 也没有 luckdraw 函数级采样栈，无法由其时长证明重复分配/布局。'
              '本批没有证据支持某个可避免的 luckdraw 热路径工作，四场景的代码根因均为「无法判定」，不改产品 lib。'
              'lots 窗口级 Raster 差异仍不稳定，普通帧事件表仅描述差异，不证明非确定性代码成本。', '',
              '三项硬失败、lots 不确定、14项原设计目标差距继续保留；没有已修复或已达标声明。'
              '下一次使用同一新 APK 完成空白/玩法冷首帧、进程与线程CPU及四场景三轮复测，详见'
              '[发布检查清单](RELEASE_CHECKLIST.md)。']
    write(ROOT / 'docs/PERF_ROOTCAUSE_REPORT.md', '\n'.join(lines) + '\n')


class ParserTests(unittest.TestCase):
    """合成 trace 验证事件恢复、帧关联与严格阈值。"""

    def test_intervals(self):
        """同名跨线程和异步 id 不得错配，边界明确记录。"""
        events = [dict(name='x', ph='E', tid=1, ts=0),
                  dict(name='x', ph='B', tid=1, ts=1),
                  dict(name='x', ph='B', tid=2, ts=2),
                  dict(name='x', ph='E', tid=1, ts=4),
                  dict(name='x', ph='E', tid=2, ts=8),
                  dict(name='a', ph='b', tid=1, ts=3, id='1'),
                  dict(name='a', ph='e', tid=1, ts=9, id='1'),
                  dict(name='z', ph='X', tid=1, ts=10, dur=2)]
        values, clipped = spans(events)
        self.assertEqual([v['dur'] for v in values], [3, 6, 6, 2])
        self.assertEqual(clipped['left_boundary'], 1)
        with self.assertRaises(ValueError):
            spans([dict(name='a', ph='B', tid=1, ts=1), dict(name='b', ph='E', tid=1, ts=2)])

    def test_frame_join(self):
        """凭帧号连接，不按最近时间把相邻帧混淆。"""
        values = [dict(name='Animator::BeginFrame', tid=1, ts=1, end=10, dur=9, args={'frame_number': '7'}),
                  dict(name='Frame', tid=1, ts=2, end=11, dur=9),
                  dict(name='Rasterizer::DoDraw', tid=2, ts=20, end=30, dur=10, args={'frame_number': '7'}),
                  dict(name='GPURasterizer::Draw', tid=2, ts=19, end=31, dur=12)]
        result = paired_frames(values)
        self.assertEqual((result[0]['frame_number'], result[0]['combined_us']), ('7', 21))
        with self.assertRaises(ValueError):
            paired_frames(values + [values[1]])


def main():
    """默认生成独立报告与统计，不改变预算、基线或历史报告。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test', action='store_true')
    options = parser.parse_args()
    if options.self_test:
        unittest.main(argv=['analyze_frames'], exit=True)
        return
    rows = read(ROOT / 'tool/bench/results/met/all_windows.json')
    formal = {r['run_id'] for r in read(ROOT / 'tool/bench/results/met2/provenance.json')}
    windows = [analyze(ROOT / r['source'], formal) for r in rows
               if r['report_key'] in SCENES and not r['backpressure_contaminated']]
    write(OUT / 'frames.json', json.dumps(windows, ensure_ascii=False, indent=2) + '\n')
    report(windows)
    for scene in SCENES:
        frames = [f for w in windows if w['scenario'] == scene for f in w['frames']]
        print(scene, 'windows', sum(w['scenario'] == scene for w in windows),
              'frames', len(frames), 'combined>12', sum(f['combined_us'] > 12000 for f in frames),
              'ui>4', sum(f['ui_us'] > 4000 for f in frames), 'union', sum(f['spike'] for f in frames))


if __name__ == '__main__':
    main()
