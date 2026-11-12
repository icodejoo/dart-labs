"""从本批原始产物生成审核表，不重写 runs 或预算，不访问设备。"""
import collections
import json
import statistics
from pathlib import Path

OUT = Path(__file__).resolve().parent
SESSION = OUT.parent
ROOT = OUT.parents[4]
SCENES = ('slot_raster', 'grid_steady', 'lotto_draw', 'lots_shaking')


def read(path):
    """保留 PowerShell UTF-8 BOM 兼容。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    """统一新报告的 LF，不更改原始采集文件。"""
    path.write_text(value + '\n', encoding='utf-8', newline='\n')


def main():
    """要求每项三有效轮，输出每个尖峰和三轮 CPU 原值与中位数。"""
    records = read(SESSION / 'runs.json')
    evidence = read(SESSION / 'frames.json')
    assessment = read(SESSION / 'frame_assessment.json')['scenarios']
    result = {'scenarios': {}, 'cpu': []}
    lines = ['# STEADY 审核原值', '', '| 场景 | 有效/启动/未污染 | trace尖峰各轮 | 合计/UI P99最大ms | 冻结门禁 |', '| --- | --- | --- | --- | --- |']
    for scene in SCENES:
        attempts = [r for r in records if r['scene'] == scene]
        valid = [r for r in attempts if r['valid']]
        if len(valid) < 3 or len(attempts) > 5:
            raise ValueError(f'{scene}: insufficient or excessive starts')
        windows = [w for w in evidence['windows'] if w['scenario'] == scene]
        data = assessment[scene]
        spikes = [f for w in windows for f in w['frames'] if f['spike']]
        normals = [f for w in windows for f in w['frames'] if not f['spike']]
        total = sum(f['combined_us'] for f in spikes)
        costs = collections.Counter()
        for frame in spikes:
            costs.update(frame['events_us'])
        key = 'luckdraw.' + scene.split('_')[0] + '.paint'
        result['scenarios'][scene] = {
            'valid': len(valid), 'attempts': len(attempts), 'clean': len(windows),
            'status': data['status'], 'frame_budget': data['frame_budget'],
            'metrics': data['metrics'], 'spikes': len(spikes),
            'spike_counts': [w['spike_count'] for w in windows],
            'spike_offsets_ms': [f['offset_ms'] for f in spikes],
            'events_in_spikes': {n: {'total_ms': cost/1000, 'mean_ms': cost/len(spikes)/1000,
                                            'percent_combined': cost/total*100}
                                  for n, cost in sorted(costs.items())},
            'normal_paint_mean_ms': sum(f['events_us'].get(key, 0) for f in normals)/len(normals)/1000 if normals else None,
            'per_window': [{k: w[k] for k in ('run_id', 'ui_mean_ms', 'raster_mean_ms', 'spike_count', 'first_five_spikes', 'second_bins')} for w in windows],
        }
        budget = data['frame_budget']
        lines.append(f'| {scene} | {len(valid)}/{len(attempts)}/{len(windows)} | {[w["spike_count"] for w in windows]} | '
                     f'{budget["99th_percentile_build_plus_raster_millis"]["max"]}/'
                     f'{budget["99th_percentile_frame_build_time_millis"]["max"]} | {data["status"]} |')
    lines += ['', '| wheel轮 | 进程% | UI+platform% | Raster% | 实际秒数 | 首/尾读取ms | 同轮帧数/fps |', '| --- | --- | --- | --- | --- | --- | --- |']
    cpu_records = [r for r in records if r['scene'] == 'cpu_wheel_steady']
    for record in cpu_records:
        if not record['valid']:
            continue
        folder = SESSION / record['directory']
        data = read(folder / 'cpu/cpu.json')
        ui = [t for t in data['threads'] if t['tid'] == data['pid']]
        raster = [t for t in data['threads'] if t['name'].endswith('.raster')]
        if len(ui) != 1 or len(raster) != 1 or not data['valid_cpu']:
            raise ValueError('CPU role/validity missing')
        summary = next(read(p) for p in folder.glob('*.timeline_summary.json') if read(p)['report_key'] == 'wheel_steady')
        value = {
            'attempt': record['attempt'], 'process': data['process_cpu_percent'],
            'ui_platform': ui[0]['cpu_percent'], 'raster': raster[0]['cpu_percent'],
            'ui_platform_tid': ui[0]['tid'], 'ui_platform_name': ui[0]['name'],
            'raster_tid': raster[0]['tid'], 'raster_name': raster[0]['name'],
            'seconds': data['seconds'], 'before_read_ms': data['before_read_micros']/1000,
            'after_read_ms': data['after_read_micros']/1000,
            'frame_count': summary['frame_count'], 'fps': summary['fps'],
            'frame_timing_elapsed_micros': summary['elapsed_micros'],
            'average_build_ms': summary['average_frame_build_time_millis'],
            'average_raster_ms': summary['average_frame_rasterizer_time_millis'],
            'new_threads': data['new_threads'], 'exited_threads': data['exited_threads'],
        }
        result['cpu'].append(value)
        lines.append(f'| {value["attempt"]} | {value["process"]:.6f} | {value["ui_platform"]:.6f} | '
                     f'{value["raster"]:.6f} | {value["seconds"]:.6f} | '
                     f'{value["before_read_ms"]:.3f}/{value["after_read_ms"]:.3f} | {value["frame_count"]}/{value["fps"]:.3f} |')
    if len(result['cpu']) != 3 or len(cpu_records) > 5:
        raise ValueError('CPU requires exactly three valid rounds within five starts')
    result['cpu_medians'] = {key: statistics.median(v[key] for v in result['cpu']) for key in ('process', 'ui_platform', 'raster')}
    lines += ['', 'CPU 中位数：' + json.dumps(result['cpu_medians'], ensure_ascii=False)]
    write(SESSION / 'audit.json', json.dumps(result, ensure_ascii=False, indent=2))
    write(SESSION / 'TABLES.md', '\n'.join(lines))
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
