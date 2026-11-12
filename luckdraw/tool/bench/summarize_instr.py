"""汇总 INSTR 原始证据；失败尝试保留，CPU 原文可独立重算但不冒充 driver 成功。"""

import hashlib
import json
import math
import statistics
from pathlib import Path

from analyze_instr import main as attribute


ROOT = Path(__file__).parent
OUT = ROOT / 'results/pending2'


def read(path):
    """兼容 Windows 工具生成的 UTF-8 BOM。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def cpu_rows():
    """只把 driver 完成且实际有 /proc 增量的轮计为正式有效轮。"""
    games = {}
    for game, scene in [('wheel', 'wheel_steady'), ('grid', 'grid_steady'),
                        ('slot', 'slot_steady'), ('capsule', 'capsule_mixing'), ('lotto', 'lotto_draw')]:
        folder = OUT / f'cpu_{game}'
        if not (folder / 'runs.json').exists():
            continue
        records = read(folder / 'runs.json')
        rows, extra = [], []
        for record in records:
            path = folder / record['directory'] / 'cpu/cpu.json'
            if not path.exists():
                continue
            data = read(path)
            if 'process_cpu_percent' not in data:
                extra.append({'attempt': record['attempt'], 'source': path.as_posix(), 'status': '无可信 CPU 增量，历史降级原文保留'})
                continue
            main = [t for t in data['threads'] if t['tid'] == data['pid']]
            raster = [t for t in data['threads'] if t['name'] == '1.raster']
            if len(main) != 1 or len(raster) != 1:
                raise ValueError(f'{path}: UI/platform 或 raster 不唯一')
            response_paths = list(path.parent.parent.glob('response_*.json'))
            if len(response_paths) != 1:
                raise ValueError(f'{path}: response 不唯一')
            response = read(response_paths[0])
            frames = response['bench_samples'][scene]
            if response['cpu_scene'] != scene or frames['frame_count'] <= 0:
                raise ValueError('CPU 与同轮 FrameTiming 场景不符')
            row = {'attempt': record['attempt'], 'source': path.as_posix(),
                   'process_percent': data['process_cpu_percent'],
                   'ui_platform_percent': main[0]['cpu_percent'],
                   'raster_percent': raster[0]['cpu_percent'], 'seconds': data['seconds'],
                   'frame_timing': frames, 'driver_valid': record['valid'],
                   'before_read_micros': data.get('before_read_micros'),
                   'after_read_micros': data.get('after_read_micros'),
                   'new_threads': data['new_threads'], 'exited_threads': data['exited_threads']}
            (rows if record['valid'] else extra).append(row)
        medians = {key: statistics.median(r[key] for r in rows)
                   for key in ('process_percent', 'ui_platform_percent', 'raster_percent')} if len(rows) == 3 else None
        games[scene] = {'attempts': len(records), 'valid_rounds': len(rows), 'rounds': rows,
                        'medians': medians, 'other_attempts': extra,
                        'status': '已落地' if len(rows) == 3 else '未通过：有效轮不足3，不超过5次启动'}
    return games


def main():
    """重算表格和冻结预算；不覆盖任何历史 DEVFIN/MET2 字段。"""
    attribute()
    attribution = read(OUT / 'attribution.json')
    cold = {}
    baseline = 2.883
    for game in ('wheel', 'grid'):
        before = [r['frame_timing_build_ms'] for r in attribution['before'][game]]
        after = [r['frame_timing_build_ms'] for r in attribution['after'][game]]
        increment = statistics.median(after) - baseline
        cold[game] = {
            'before_ms': before, 'after_ms': after,
            'before_median_ms': statistics.median(before), 'after_median_ms': statistics.median(after),
            'improvement_fraction': 1 - statistics.median(after) / statistics.median(before),
            'increment_ms': increment, 'increment_budget_ms': math.ceil(increment * 1.1 * 1000) / 1000,
            'gap_to_original_4ms': increment - 4,
            'range_after_ms': max(after) - min(after),
            'after_relative_range': (max(after) - min(after)) / statistics.median(after),
            'status': '已标定；三轮波动大，未达到原4ms目标',
        }
    cpu = cpu_rows()
    result = {
        'device': 'vivo V2417 / Android16 / 10AE9K17UE0011S',
        'blank_baseline_ms': baseline, 'blank_source': 'results/pending/REPORT.md（DEVFIN 历史空白，INSTR 未新增空白启动）',
        'trace_enabled': True, 'cold': cold, 'cpu': cpu,
        'first_frame_increment_budgets_ms': {f'{g}_first_frame': r['increment_budget_ms'] for g, r in cold.items()},
        'cpu_method': '/proc stat delta / host read-start timestamp delta / CLK_TCK=100; single-core percent',
        'ui_note': 'Flutter3.47 Android 默认 UI/platform 合并，主线程 tid=pid；1.raster 单列，非纯 Dart UI CPU。https://docs.flutter.dev/resources/architectural-overview',
        'phone_settings_note': '接手 stay_on=2；中途外部变化实测0，本批无 settings put/svc power 写入。最终实测另见 validation/device_final.json。',
    }
    (OUT / 'audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    status_path = ROOT / 'budgets.status.json'
    status = read(status_path)
    status['instr'] = result
    status['status'] = 'INSTR：首帧宽度缓存已在副本定位修复并复测；标定不代表4ms达标；CPU逐项有效性见instr，历史结果保留'
    status_path.write_text(json.dumps(status, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    budget_path = ROOT / 'budgets.json'
    budget = read(budget_path)
    marker = ' INSTR 有效增量与原4ms差距另见 budgets.status.json.instr；不是绝对首帧达标。'
    reason = budget['wheel_first_frame']['reason']
    if marker not in reason:
        budget['wheel_first_frame']['reason'] = reason + marker
    budget_path.write_text(json.dumps(budget, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print(json.dumps({'cold': cold, 'cpu_counts': {k: (v['valid_rounds'], v['attempts']) for k, v in cpu.items()}}, ensure_ascii=False, indent=2))
    # 原始文件逐份散列，排除生成的报告/日志自引用。
    hashes = {p.relative_to(OUT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in OUT.iterdir() if folder.is_dir() and folder.name != 'validation'
              for p in folder.rglob('*') if p.is_file()}
    (OUT / 'raw.sha256.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf8', newline='\n')


if __name__ == '__main__':
    main()
