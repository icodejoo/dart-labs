"""从原始 Timeline 重算 INSTR 冷首帧归因；嵌套区间用并集/差集避免重复计时。"""

import collections
import json
import statistics
from pathlib import Path


def intervals(events):
    """分别按线程、名字和异步 id 配对；不补造缺失端点。"""
    stacks = collections.defaultdict(list)
    result = []
    for event in events:
        phase = event.get('ph')
        if phase == 'X':
            result.append({**event, 'end': event['ts'] + event['dur']})
            continue
        if phase not in ('B', 'E', 'b', 'e'):
            continue
        key = (event.get('pid'), event.get('tid'), event.get('name'),
               event.get('id') if phase in ('b', 'e') else None)
        if phase in ('B', 'b'):
            stacks[key].append(event)
        elif stacks[key]:
            opening = stacks[key].pop()
            if event['ts'] < opening['ts']:
                raise ValueError('事件结束早于开始')
            result.append({**opening, 'end': event['ts']})
    unmatched = [e for stack in stacks.values() for e in stack
                 if e.get('name', '').startswith('luckdraw.')]
    return result, unmatched


def union(values):
    """返回不重叠的区间并集。"""
    result = []
    for start, end in sorted(values):
        if result and start <= result[-1][1]:
            result[-1] = (result[-1][0], max(end, result[-1][1]))
        elif end > start:
            result.append((start, end))
    return result


def duration(values):
    """并集墙钟微秒，转换为毫秒。"""
    return sum(b - a for a, b in union(values)) / 1000


def subtract(values, removed):
    """从区间并集中减去子事件，保证阶段互斥。"""
    result = union(values)
    for start, end in union(removed):
        remaining = []
        for a, b in result:
            if b <= start or a >= end:
                remaining.append((a, b))
            else:
                if a < start:
                    remaining.append((a, start))
                if b > end:
                    remaining.append((end, b))
        result = remaining
    return result


def attribute(path):
    """选包含首次玩法 layout 的 UI Frame；另外保留 FrameTiming，二者边界不同。"""
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    paired, unmatched = intervals(data['traceEvents'])
    layouts = [e for e in paired if e['name'].startswith('luckdraw.')
               and e['name'].endswith('.layout')
               and e['name'] not in ('luckdraw.text.layout', 'luckdraw.text.painter.layout')]
    if not layouts:
        raise ValueError(f'{path}: 没有玩法 layout 事件')
    first = min(layouts, key=lambda e: e['ts'])
    frames = [e for e in paired if e['name'] == 'Frame' and e['tid'] == first['tid']
              and e['ts'] <= first['ts'] and e['end'] >= first['end']]
    if len(frames) != 1:
        raise ValueError(f'{path}: 首帧不唯一 {len(frames)}')
    frame = frames[0]
    start, end = frame['ts'], frame['end']
    events = []
    for event in paired:
        if event['tid'] == first['tid'] and event['name'].startswith('luckdraw.') and event['ts'] < end and event['end'] > start:
            events.append({
                'name': event['name'], 'start_us': max(event['ts'], start),
                'end_us': min(event['end'], end), 'args': event.get('args', {}),
                'relative_start_ms': (max(event['ts'], start) - start) / 1000,
                'relative_end_ms': (min(event['end'], end) - start) / 1000,
            })

    def select(predicate):
        """选择并裁剪当前首帧内的阶段区间。"""
        return [(e['start_us'], e['end_us']) for e in events if predicate(e['name'])]

    text = select(lambda n: n.startswith('luckdraw.text.'))
    layout = select(lambda n: n.endswith('.layout') and not n.startswith('luckdraw.text.'))
    record = select(lambda n: n.endswith('.record'))
    raster = select(lambda n: n.startswith('luckdraw.raster.'))
    image = select(lambda n: n == 'luckdraw.image.update')
    paint = select(lambda n: n.endswith('.paint'))
    stages = {
        'text': duration(text),
        'layout_excluding_text': duration(subtract(layout, text)),
        'record_excluding_text_raster': duration(subtract(record, text + raster)),
        'raster': duration(raster),
        'image_update': duration(image),
        'paint': duration(subtract(paint, text + record + raster)),
        'other_uninstrumented': duration(subtract([(start, end)], text + layout + record + raster + image + paint)),
    }
    painter_events = [e for e in events if e['name'] == 'luckdraw.text.painter.layout']
    calls = sum(e['args']['layouts'] for e in painter_events)
    painter_ms = duration([(e['start_us'], e['end_us']) for e in painter_events])
    summary = json.loads(path.with_name(path.name.replace('.timeline.json', '.timeline_summary.json')).read_text(encoding='utf-8-sig'))
    return {
        'source': path.as_posix(), 'ui_frame_start_us': start, 'ui_frame_end_us': end,
        'ui_frame_ms': (end - start) / 1000, 'frame_timing_build_ms': summary['first_frame_ui_millis'],
        'inclusive_layout_ms': duration(layout), 'inclusive_record_ms': duration(record),
        'stages_ms': stages, 'stage_percent_of_ui_frame': {k: v / ((end - start) / 1000) * 100 for k, v in stages.items()},
        'text_painter_layout_calls': calls, 'text_painter_layout_total_ms': painter_ms,
        'text_painter_layout_mean_ms': painter_ms / calls if calls else None,
        'first_paint': next(e for e in sorted(events, key=lambda e: e['start_us']) if e['name'].endswith('.paint')),
        'events': sorted(events, key=lambda e: e['start_us']),
        'unmatched_in_first_frame': [e for e in unmatched if start <= e['ts'] <= end],
        'unmatched_entire_trace': unmatched,
    }


def main():
    """只分析本批原始产物并输出逐轮完整事件，缺失数据直接报错。"""
    root = Path(__file__).parent / 'results/pending2'
    results = {}
    for phase in ('before', 'after'):
        results[phase] = {}
        for game in ('wheel', 'grid'):
            folder = root / f'{phase}_{game}'
            records = json.loads((folder / 'runs.json').read_text(encoding='utf-8-sig')) if (folder / 'runs.json').exists() else []
            files = [p for record in records if record['valid']
                     for p in (folder / record['directory']).glob('*.timeline.json')]
            rows = [attribute(path) for path in files]
            if rows:
                if len(rows) < 3:
                    print('采集中，保留完整原文，不报告不满三轮的统计:', phase, game, len(rows))
                    continue
                if len(rows) != 3:
                    raise ValueError(f'{phase}/{game}: {len(rows)} 轮，要求3轮')
                results[phase][game] = rows
                print(phase, game, 'FrameTiming', [r['frame_timing_build_ms'] for r in rows],
                      'median', statistics.median(r['frame_timing_build_ms'] for r in rows),
                      'layout calls', [r['text_painter_layout_calls'] for r in rows])
    (root / 'attribution.json').write_text(json.dumps(results, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')


if __name__ == '__main__':
    main()
