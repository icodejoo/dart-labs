"""独立复核 INSTR 原始计数、逐事件区间、预算及完成状态，不将缺测当成功。"""

import collections
import hashlib
import json
import math
from pathlib import Path


OUT = Path(__file__).resolve().parent.parent


def read(path):
    """读取原始 JSON。"""
    return json.loads(path.read_text(encoding='utf-8-sig'))


def stat(text):
    """独立按Linux字段号读取utime、stime、starttime。"""
    tail = text[text.rindex(') ') + 2:].split()
    return int(text.split(' ', 1)[0]), int(tail[11]) + int(tail[12]), int(tail[19])


def snapshot(path):
    """复核两种真实文本格式；不依赖Dart被测解析函数。"""
    lines = path.read_text(encoding='utf8').splitlines()
    hz = int(next(x[3:] for x in lines if x.startswith('HZ\t')))
    process = stat(next(x[8:] for x in lines if x.startswith('PROCESS\t')))
    if 'STATS' in lines:
        a, b = lines.index('STATS'), lines.index('COMMS')
        threads = dict((v[0], v) for v in map(stat, lines[a + 1:b]))
    else:
        threads = dict((v[0], v) for v in (stat(x[5:]) for x in lines if x.startswith('STAT\t')))
    return hz, process, threads


def main():
    """仅完整性门禁；任务完成不足与手机设置问题保留为独立未完成项。"""
    audit = read(OUT / 'audit.json')
    attrs = read(OUT / 'attribution.json')
    checked, starts = 0, 0
    for folder in OUT.iterdir():
        if not folder.is_dir() or not (folder / 'runs.json').exists():
            continue
        records = read(folder / 'runs.json')
        assert len(records) <= 5
        assert [r['attempt'] for r in records] == list(range(1, len(records) + 1))
        starts += len(records)
        for record in records:
            directory = folder / record['directory'] / 'cpu'
            if not (directory / 'cpu.json').exists():
                continue
            report = read(directory / 'cpu.json')
            if 'process_cpu_percent' not in report:
                assert report['valid_cpu'] is False
                continue
            assert report['window_adb_calls'] == 2 and report['seconds'] >= 5
            hz, process, threads = snapshot(directory / 'before.txt')
            hz2, process2, threads2 = snapshot(directory / 'after.txt')
            assert hz == hz2 == report['clk_tck'] == 100
            assert process[0] == process2[0] == report['pid'] and process[2] == process2[2]
            expected = (process2[1] - process[1]) / report['seconds'] / hz * 100
            assert math.isclose(expected, report['process_cpu_percent'], abs_tol=1e-12)
            for thread in report['threads']:
                a, b = threads[thread['tid']], threads2[thread['tid']]
                assert a[2] == b[2]
                expected = (b[1] - a[1]) / report['seconds'] / hz * 100
                assert math.isclose(expected, thread['cpu_percent'], abs_tol=1e-12)
            checked += 1
    for phase, games in attrs.items():
        for game, rows in games.items():
            assert len(rows) == 3
            for row in rows:
                assert not row['unmatched_in_first_frame']
                assert math.isclose(sum(row['stages_ms'].values()), row['ui_frame_ms'], abs_tol=1e-9)
                assert row['text_painter_layout_calls'] == {'before': {'wheel': 276, 'grid': 128}, 'after': {'wheel': 63, 'grid': 22}}[phase][game]
                for event in row['events']:
                    assert row['ui_frame_start_us'] <= event['start_us'] <= event['end_us'] <= row['ui_frame_end_us']
    for path, expected in read(OUT / 'raw.sha256.json').items():
        assert hashlib.sha256((OUT / path).read_bytes()).hexdigest() == expected
    assert audit['cpu']['wheel_steady']['valid_rounds'] == 2
    assert audit['cpu']['wheel_steady']['medians'] is None
    assert all(v['valid_rounds'] == 3 for k, v in audit['cpu'].items() if k != 'wheel_steady')
    result = {'integrity': 'PASS', 'completion': 'PARTIAL', 'total_starts': starts,
              'native_cpu_raw_pairs_checked': checked, 'cold_valid_rounds': 12,
              'open_items': ['wheel完整链路2/5', 'wheel/grid未达4ms', '完整开奖CPU未测', '真实lib待补丁合并', 'stay_on最终实际值另见device_final.json，未擅自恢复']}
    (OUT / 'validation/evidence_check.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
