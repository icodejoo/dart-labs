"""STEADY 原始 trace 归因；复用 PEND 帧号配对，不把墙钟区间当 CPU。"""
import argparse
import collections
import json
import pathlib
import unittest
from unittest import mock

import analyze_frames as frames
from analyze_instr import duration

ROOT = frames.ROOT
SCENES = frames.SCENES


def event_comparison(values):
    """分别统计尖峰/普通帧的事件包含耗时；占比以同帧 UI+Raster 为分母。"""
    result = {}
    names = sorted({name for frame in values for name in frame['events_us']})
    for name in names:
        groups = {}
        for label, selected in (
                ('spike', [f for f in values if f['spike']]),
                ('normal', [f for f in values if not f['spike']])):
            total = sum(f['events_us'].get(name, 0) for f in selected)
            denominator = sum(f['combined_us'] for f in selected)
            groups[label] = {
                'total_ms': total / 1000,
                'mean_ms': total / len(selected) / 1000 if selected else None,
                'percent_combined': total / denominator * 100 if denominator else None,
                'frames_with_event': sum(name in f['events_us'] for f in selected),
                'frames': len(selected),
            }
        result[name] = groups
    return result


def entry_events(path):
    """列出 slot 入场所有 atlas 调用所在 UI 帧与线程；缺证据保留 None。"""
    intervals, clipped = frames.spans(frames.read(path)['traceEvents'])
    ui = sorted((e for e in intervals if e['name'] == 'Frame'), key=lambda e: e['ts'])
    calls = []
    for event in intervals:
        if event['name'] != 'luckdraw.raster.atlas':
            continue
        parents = [(i + 1, f) for i, f in enumerate(ui) if frames.inside(f, event)]
        if len(parents) > 1:
            raise ValueError('atlas UI frame ambiguous')
        parent = parents[0][1] if parents else None
        animator = next((e for e in intervals if parent and e['name'] == 'Animator::BeginFrame'
                         and e['tid'] == parent['tid'] and e['ts'] <= parent['ts'] < e['end']), None)
        calls.append({
            'start_us': event['ts'], 'end_us': event['end'], 'tid': event['tid'],
            'duration_ms': event['dur'] / 1000,
            'ui_frame_index': parents[0][0] if parents else None,
            'engine_frame_number': animator.get('args', {}).get('frame_number') if animator else None,
            'ui_frame_ms': parent['dur'] / 1000 if parent else None,
            'on_ui_thread': True if parent else None,
            'events': [e for e in intervals if frames.inside(event, e)],
        })
    return {'source': path.relative_to(ROOT).as_posix(), 'calls': calls,
            'status': 'observed' if calls else '无法判定', 'clipped': clipped}


def analyze_window(path):
    """保留每个事件的起止、所在帧与并集耗时，核对 SDK 数组而非最近时间匹配。"""
    window = frames.analyze(path, set())
    raw = frames.read(ROOT / window['trace'])['traceEvents']
    intervals, _ = frames.spans(raw)
    events = [e for e in intervals if e['name'].startswith('luckdraw.')]
    if not events:
        raise ValueError(f'{path}: missing luckdraw instrumentation')
    for frame in window['frames']:
        draw = [e for e in intervals if e['name'] == 'Rasterizer::DoDraw'
                and e.get('args', {}).get('frame_number') == frame['frame_number']]
        if len(draw) != 1:
            raise ValueError('Rasterizer::DoDraw identity ambiguous')
        frame['events_us']['Rasterizer::DoDraw'] = draw[0]['dur']
        frame['raster_events_us']['Rasterizer::DoDraw'] = draw[0]['dur']
        children = [e for e in events if e['tid'] == frame['ui_thread']
                    and frame['ts'] <= e['ts'] and e['end'] <= frame['ts'] + frame['ui_us']]
        frame['luckdraw_events'] = children
        frame['luckdraw_union_ms'] = duration([(e['ts'], e['end']) for e in children])
        frame['luckdraw_percent_ui'] = frame['luckdraw_union_ms'] * 100000 / frame['ui_us']
    spikes = [f for f in window['frames'] if f['spike']]
    window['spike_count'] = len(spikes)
    window['first_five_spikes'] = sum(f['index'] <= 5 for f in spikes)
    window['second_bins'] = dict(sorted(collections.Counter(int(f['offset_ms'] // 1000) for f in spikes).items()))
    window['events'] = events
    window['event_comparison'] = event_comparison(window['frames'])
    return window


def make_report(windows, entries):
    """生成每个尖峰的完整事件表及普通帧对照；结论由审核者依据证据补入。"""
    lines = ['# STEADY 带打点逐帧证据', '',
             '按引擎 frame_number 配对并逐项校验 SDK 时长数组；仅未污染窗口参与归因。',
             '尖峰为 trace 同帧 UI+Raster>12ms 或 UI>4ms，硬门禁另用 FrameTiming P99。',
             '包含耗时/占比可嵌套，不能相加；墙钟不能直接当 CPU。普通帧包含零次该事件的帧。', '',
             '| 场景/run_id | 帧数 | 尖峰/首5帧 | 每秒尖峰桶 |', '| --- | --- | --- | --- |']
    for w in windows:
        lines.append(f'| {w["scenario"]}/{w["run_id"]} | {len(w["frames"])} | {w["spike_count"]}/{w["first_five_spikes"]} | {w["second_bins"]} |')
    lines += ['', '| 场景/run_id | UI/Raster均值ms | paint均值ms | Encode/Submit均值ms | layout/record/text事件次数 |',
              '| --- | --- | --- | --- | --- |']
    for w in windows:
        count = len(w['frames'])
        paint = sum(e['dur'] for f in w['frames'] for e in f['luckdraw_events'] if e['name'].endswith('.paint')) / count / 1000
        encode = sum(f['events_us'].get('SurfaceFrame::Encode', 0) for f in w['frames']) / count / 1000
        submit = sum(f['events_us'].get('SurfaceFrame::Submit', 0) for f in w['frames']) / count / 1000
        low = [sum(predicate(e['name']) for e in w['events']) for predicate in (
            lambda n: n.endswith('.layout') and not n.startswith('luckdraw.text.'),
            lambda n: n.endswith('.record'), lambda n: n.startswith('luckdraw.text.'))]
        lines.append(f'| {w["scenario"]}/{w["run_id"]} | {w["ui_mean_ms"]:.3f}/{w["raster_mean_ms"]:.3f} | '
                     f'{paint:.3f} | {encode:.3f}/{submit:.3f} | {low} |')
    for scene in SCENES:
        selected = [w for w in windows if w['scenario'] == scene]
        lines += ['', f'## {scene}', '',
                  '| run_id/序号/引擎帧号 | 位置ms | UI/Raster/合计ms | 库并集ms/%UI | 每个luckdraw事件ms（包含耗时） |',
                  '| --- | --- | --- | --- | --- |']
        spikes = [(w, f) for w in selected for f in w['frames'] if f['spike']]
        for w, f in spikes:
            lib = '；'.join(f'{e["name"]} {e["dur"]/1000:.3f}' for e in f['luckdraw_events']) or '无'
            lines.append(f'| {w["run_id"]}/{f["index"]}/{f["frame_number"]} | {f["offset_ms"]:.3f} | '
                         f'{f["ui_us"]/1000:.3f}/{f["raster_us"]/1000:.3f}/{f["combined_us"]/1000:.3f} | '
                         f'{f["luckdraw_union_ms"]:.3f}/{f["luckdraw_percent_ui"]:.2f}% | {lib} |')
        if not spikes:
            lines.append('| — | 无尖峰 | — | — | — |')
        comparisons = event_comparison([f for w in selected for f in w['frames']])
        lines += ['', '| 事件 | 尖峰累计ms / 每帧ms / %合计 | 普通累计ms / 每帧ms / %合计 |', '| --- | --- | --- |']
        for name, group in comparisons.items():
            if not (name.startswith('luckdraw.') or name in frames.INTERESTING or
                    name in ('Rasterizer::DoDraw', 'Rasterizer::DrawToSurfaces', 'COMPOSITING')):
                continue
            cells = []
            for label in ('spike', 'normal'):
                g = group[label]
                cells.append(f'{g["total_ms"]:.3f} / {g["mean_ms"]:.3f} / {g["percent_combined"]:.2f}%' if g['frames'] else '无样本')
            lines.append(f'| {name} | {cells[0]} | {cells[1]} |')
        lines += ['', '所有尖峰的框架事件与毫秒占比（父子不可累加）：', '',
                  '| run_id/帧 | 框架事件 ms / %合计 |', '| --- | --- |']
        for w, f in spikes:
            names = sorted((n, v) for n, v in f['events_us'].items() if n in frames.INTERESTING or
                           n in ('COMPOSITING', 'Rasterizer::DoDraw', 'Rasterizer::DrawToSurfaces'))
            lines.append(f'| {w["run_id"]}/{f["index"]} | ' + '；'.join(f'{n} {v/1000:.3f}/{v/f["combined_us"]*100:.2f}%' for n, v in names) + ' |')
    lines += ['', '## slot 入场 atlas 调用（稳态前独立窗口）', '',
              '| 来源 | UI帧/引擎帧号 | atlas ms | UI帧ms | UI线程 |', '| --- | --- | --- | --- | --- |']
    for entry in entries:
        for call in entry['calls']:
            lines.append(f'| {entry["source"]} | {call["ui_frame_index"]}/{call["engine_frame_number"]} | {call["duration_ms"]:.3f} | {call["ui_frame_ms"]} | {call["on_ui_thread"]} |')
    lines += ['', '## GC（含 UI 帧外事件）', '', '| 场景/run_id | 事件/线程 | 位置ms/耗时ms | 与UI帧重叠序号 |', '| --- | --- | --- | --- |']
    for w in windows:
        for event in w['gc_intervals']:
            lines.append(f'| {w["scenario"]}/{w["run_id"]} | {event["name"]}/{event["tid"]} | '
                         f'{event["offset_ms"]:.3f}/{event["dur_us"]/1000:.3f} | {event["ui_overlap_indices"]} |')
    return '\n'.join(lines) + '\n'


def main(directory):
    """只读取本批 runs.json 的有效轮，污染轮保留原始文件并明确列示。"""
    records = json.loads((directory / 'runs.json').read_text(encoding='utf-8-sig'))
    windows, entries, excluded = [], [], []
    for record in records:
        if record['scene'] not in SCENES or not record['valid']:
            continue
        folder = directory / record['directory']
        paths = list(folder.glob(f'{record["scene"]}_*.timeline_summary.json'))
        paths = [p for p in paths if frames.read(p)['report_key'] == record['scene']]
        if len(paths) != 1:
            raise ValueError(f'{folder}: summary not unique')
        summary = frames.read(paths[0])
        clean = (summary['fps'] >= 59 and summary['frame_count'] >=
                 .98 * summary['elapsed_micros'] / 1000000 * 60 and
                 summary['90th_percentile_frame_rasterizer_time_millis'] < 15.5)
        if clean:
            windows.append(analyze_window(paths[0]))
        else:
            excluded.append({'source': paths[0].relative_to(ROOT).as_posix(), 'reason': 'MET2 delivery or Raster P90 pollution'})
        entries.extend(entry_events(p) for p in folder.glob('*_entry_reference_*.timeline.json*'))
    result = {'windows': windows, 'entries': entries, 'excluded': excluded}
    frames.write(directory / 'frames.json', json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    frames.write(directory / 'ATTRIBUTION.md', make_report(windows, entries))
    for scene in SCENES:
        selected = [w for w in windows if w['scenario'] == scene]
        print(scene, 'clean', len(selected), 'spikes', [w['spike_count'] for w in selected])


class EvidenceTests(unittest.TestCase):
    """合成区间验证不混淆包含耗时、零次调用与缺失证据。"""

    def test_nested_and_zero(self):
        """嵌套阶段保持各自包含值，普通零调用帧必须进入均值分母。"""
        values = [
            {'spike': True, 'combined_us': 20000, 'events_us': {'luckdraw.lotto.paint': 1000, 'luckdraw.raster.prepare': 500}},
            {'spike': False, 'combined_us': 5000, 'events_us': {'luckdraw.lotto.paint': 100}},
            {'spike': False, 'combined_us': 5000, 'events_us': {}},
        ]
        result = event_comparison(values)
        self.assertEqual(result['luckdraw.lotto.paint']['spike']['percent_combined'], 5)
        self.assertEqual(result['luckdraw.lotto.paint']['normal']['mean_ms'], .05)
        self.assertEqual(result['luckdraw.raster.prepare']['normal']['frames_with_event'], 0)
        self.assertEqual(duration([(0, 1000), (100, 600)]), 1)

    def test_frame_identity(self):
        """Raster 顺序颠倒仍以帧号匹配，跨线程同时间事件不能冒充库UI工作。"""
        def event(name, ts, end, tid, number=None):
            """生成带完整边界的测试区间。"""
            return {'name': name, 'ts': ts, 'end': end, 'dur': end-ts, 'tid': tid,
                    'args': {'frame_number': number} if number else {}}
        values = []
        for number, start in [(1, 0), (2, 20000)]:
            values += [event('Animator::BeginFrame', start, start+2000, 1, number),
                       event('Frame', start+10, start+1000, 1),
                       event('luckdraw.grid.paint', start+100, start+200, 1)]
        for number, start in [(2, 25000), (1, 5000)]:
            values += [event('GPURasterizer::Draw', start, start+3000, 2),
                       event('Rasterizer::DoDraw', start+10, start+2900, 2, number)]
        values.append(event('luckdraw.other.paint', 100, 200, 99))
        paired = frames.paired_frames(values)
        self.assertEqual([f['frame_number'] for f in paired], [1, 2])
        self.assertEqual([f['raster_ts'] for f in paired], [5000, 25000])
        self.assertTrue(all('luckdraw.other.paint' not in f['events_us'] for f in paired))

    def test_missing_entry_evidence(self):
        """没有 atlas 事件时明确无法判定，不能把空列表解释为零耗时构建。"""
        with mock.patch.object(frames, 'read', return_value={'traceEvents': []}):
            result = entry_events(ROOT / 'synthetic-entry.timeline.json')
        self.assertEqual(result['status'], '无法判定')
        self.assertEqual(result['calls'], [])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=pathlib.Path, default=ROOT / 'tool/bench/results/steady')
    parser.add_argument('--self-test', action='store_true')
    arguments = parser.parse_args()
    if arguments.self_test:
        unittest.main(argv=['analyze_steady'], exit=True)
    else:
        main(arguments.input.resolve())
