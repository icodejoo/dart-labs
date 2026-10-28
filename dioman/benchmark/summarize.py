"""核对三轮原始 bench 场景及传输计数，输出报告表格。"""
import json
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parent
ROUNDS = 3
SCENARIOS = 6
STABILITY_LIMIT = 10


def load_runs():
    """校验正式测量时间与发送次数，拒绝空输出或场景语义失效。"""
    runs = []
    for index in range(1, ROUNDS + 1):
        run = json.loads((DIRECTORY / f'run-{index}.json').read_text(encoding='utf-8-sig').strip())
        assert run['mode'] == 'JIT (dart run)'
        assert run['warmupMillis'] >= 500 and run['measurementMillis'] >= 2000
        assert len(run['results']) == SCENARIOS
        for row in run['results']:
            assert row['elapsedSeconds'] >= 2 and row['operations'] > 0
            assert row['sends'] == (0 if row['scenario'] == 'S4' else row['operations'])
            assert row['requestsPerOperation'] == (100 if row['scenario'] == 'S5' else 1)
        runs.append(run)
    return runs


def spread(values):
    """计算三轮相对最小值的最大离散度（百分比）。"""
    return (max(values) / min(values) - 1) * 100


def markdown():
    """输出三轮完整数据与同一吞吐中位轮的指标。"""
    runs = load_runs()
    lines = ['| 场景 | 轮次 | ops/s | 平均 μs/op | p99 μs/op | 操作数 | 测量秒数 | 发送数 |',
             '|---|---:|---:|---:|---:|---:|---:|---:|']
    for scenario in range(SCENARIOS):
        for index, run in enumerate(runs, 1):
            row = run['results'][scenario]
            lines.append(f"| {row['scenario']} | {index} | {row['opsPerSecond']:.2f} | {row['meanMicros']:.3f} | {row['p99Micros']:.3f} | {row['operations']} | {row['elapsedSeconds']:.6f} | {row['sends']} |")
    lines += ['', '| 场景 | 吞吐离散度 | 均值离散度 | p99 离散度 | 吞吐中位轮 | 该轮 ops/s | 该轮平均 μs | 该轮 p99 μs | 吞吐达标 |',
              '|---|---:|---:|---:|---:|---:|---:|---:|---|']
    for scenario in range(SCENARIOS):
        rows = [run['results'][scenario] for run in runs]
        middle = sorted(range(ROUNDS), key=lambda i: rows[i]['opsPerSecond'])[1]
        row = rows[middle]
        delta = spread([r['opsPerSecond'] for r in rows])
        lines.append(f"| {row['scenario']} | {delta:.2f}% | {spread([r['meanMicros'] for r in rows]):.2f}% | {spread([r['p99Micros'] for r in rows]):.2f}% | {middle + 1} | {row['opsPerSecond']:.2f} | {row['meanMicros']:.3f} | {row['p99Micros']:.3f} | {'是' if delta < STABILITY_LIMIT else '否：只留档'} |")
    return '\n'.join(lines)


if __name__ == '__main__':
    print(markdown())
    print('\n6 scenarios x 3 processes; elapsed >= 2s; sends/cache/share semantics: PASS')
