"""只读 DEVFIN 原始采集；保留失败状态并从 driver 原始响应恢复冷帧数值。"""
import collections
import datetime
import hashlib
import json
import math
import pathlib
import statistics

ROOT = pathlib.Path(__file__).resolve().parents[5]
OUT = pathlib.Path(__file__).resolve().parent.parent


def load(path):
    """读取原始 JSON，兼容 PowerShell 的 UTF-8 BOM。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def save(path, value):
    """独立保存派生结果，不覆盖原始尝试。"""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def main():
    """关联时间戳、原始响应和本轮尝试，输出完整审计数据。"""
    session = load(OUT / 'session.json')
    runs = load(OUT / 'runs.json')
    log = ROOT / 'tool/bench/build/flutter_driver_commands_0.log'
    raw = log.read_text(encoding='utf-8')
    (OUT / 'validation/driver_commands.snapshot.log').write_text(
        raw, encoding='utf-8', newline='\n')
    responses = collections.defaultdict(list)
    decoder = json.JSONDecoder()
    timezone = datetime.timezone(datetime.timedelta(hours=8))
    for line in raw.splitlines():
        marker = 'response: {message: '
        if marker not in line:
            continue
        try:
            data, _ = decoder.raw_decode(line.split(marker, 1)[1])
        except ValueError:
            continue
        if data.get('result') != 'true':
            continue
        stamp = datetime.datetime.fromisoformat(line[:26]).replace(tzinfo=timezone)
        for key, metrics in data.get('data', {}).get('bench_samples', {}).items():
            responses[key].append((stamp, metrics, data))
    scenes = collections.defaultdict(list)
    provenance = []
    for run in runs:
        directory = OUT / run['directory']
        row = dict(run)
        start = datetime.datetime.fromisoformat(run['started_at'].replace('Z', '+00:00'))
        end = datetime.datetime.fromisoformat(run.get('ended_at', run['started_at']).replace('Z', '+00:00'))
        matching = [(stamp, metrics, data) for stamp, metrics, data in responses[run['scene']]
                    if start <= stamp <= end]
        if len(matching) == 1:
            stamp, metrics, data = matching[0]
            row['device_metrics'] = metrics
            row['device_response_at'] = stamp.astimezone(datetime.timezone.utc).isoformat()
            recovery = directory / 'device_response.original.json'
            save(recovery, data)
            row['device_response_file'] = str(recovery.relative_to(OUT)).replace('\\', '/')
        cpu = directory / 'cpu/cpu.json'
        if cpu.exists():
            report = load(cpu)
            row['cpu'] = report
            values = report['samples']
            row['cpu_medians'] = {'process': statistics.median(v['process_cpu_percent'] for v in values)}
            for role in ['UI', 'Raster']:
                row['cpu_medians'][role] = statistics.median(
                    sum(t['cpu_percent'] for t in v['threads'] if t['role'] == role) for v in values)
        error = directory / 'cpu/error.txt'
        if error.exists():
            row['cpu_error'] = error.read_text(encoding='utf-8')
        for file in directory.rglob('*'):
            if file.is_file():
                provenance.append({'path': str(file.relative_to(OUT)).replace('\\', '/'),
                                   'bytes': file.stat().st_size,
                                   'sha256': hashlib.sha256(file.read_bytes()).hexdigest()})
        scenes[run['scene']].append(row)
    cold = {}
    for scene in ['blank_first_frame', 'wheel_first_frame', 'grid_first_frame', 'slot_first_frame']:
        rows = scenes[scene]
        values = [r['device_metrics']['first_frame_ui_millis'] for r in rows if 'device_metrics' in r]
        primary = values[:3]
        cold[scene] = {'all_samples_ms': values, 'primary_samples_ms': primary,
                       'primary_policy': '按启动顺序固定前3份完整设备FrameTiming，不按耗时挑轮；driver失败原样保留',
                       'driver_valid_rounds': sum(r['valid'] for r in rows),
                       'raw_frame_timing_rounds': len(values),
                       'median_ms': statistics.median(primary) if len(primary) == 3 else None,
                       'range_ms': max(primary) - min(primary) if primary else None}
    blank = cold['blank_first_frame']['median_ms']
    for scene, row in cold.items():
        if scene == 'blank_first_frame' or row['median_ms'] is None or blank is None:
            continue
        delta = row['median_ms'] - blank
        row.update({'increment_ms': delta, 'increment_budget_ms': math.ceil(delta * 1.1 * 1000 - 1e-9) / 1000,
                    'original_design_target_ms': 4, 'gap_to_design': delta / 4 - 1,
                    'status': '已标定未达设计目标' if delta > 4 else '已标定'})
    cpu = {}
    for scene, rows in scenes.items():
        if not scene.startswith('cpu_'):
            continue
        valid = [r for r in rows if r.get('valid') and 'cpu_medians' in r]
        cpu[scene] = {'valid_rounds': len(valid), 'attempts': len(rows),
                      'round_medians': [r['cpu_medians'] for r in valid],
                      'medians': {role: statistics.median(r['cpu_medians'][role] for r in valid)
                                  for role in ['process', 'UI', 'Raster']} if valid else None,
                      'errors': [r.get('cpu_error', r.get('error')) for r in rows if not r.get('valid')],
                      'status': '已标定' if len(valid) >= 3 else '不确定：有效轮不足3'}
    save(OUT / 'audit.json', {'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                             'session': session, 'scenes': dict(scenes), 'cold_frames': cold, 'cpu': cpu,
                             'provenance': provenance})
    print(json.dumps({'cold_frames': cold, 'cpu': cpu}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
