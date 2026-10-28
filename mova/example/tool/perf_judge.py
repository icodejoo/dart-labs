"""Dependency-free performance statistics. CPU uses 100% per logical core.

Memory is KiB; slopes are units/hour. Missing evidence never becomes PASS.
"""
import math
import statistics

VERSION = 1
LEAK_LIMITS = {'pss_kb': (10240, 5120), 'native_kb': (5120, 2048),
               'rss_kb': (10240, 5120), 'fd': (10, 5), 'threads': (4, 2)}
# 回归还要求超出基线一个绝对量，避免基线接近 0（掉帧率常为 0、audioOnly CPU 约 2%）时一点抖动就误报。
ABS_FLOORS = {'cpu': 5.0, 'pss_kb': 10240, 'rss_kb': 10240,
              'drop_rate': .005, 'decoder_drop_rate': .005, 'jank_rate': .02}


def regressed(key, current, old, regression):
    """当前值同时超出基线的相对比例与绝对下限才算回归。"""
    return current > old * (1 + regression) and current - old > ABS_FLOORS.get(key, 0)


def percentile(values, q):
    values = sorted(values)
    pos = (len(values) - 1) * q
    lo = math.floor(pos)
    return values[lo] + (values[math.ceil(pos)] - values[lo]) * (pos - lo)


def trend(points):
    if len(points) < 3:
        return None
    xs, ys = zip(*points)
    xm, ym = statistics.mean(xs), statistics.mean(ys)
    xx = sum((x - xm) ** 2 for x in xs)
    yy = sum((y - ym) ** 2 for y in ys)
    if not xx:
        return None
    xy = sum((x - xm) * (y - ym) for x, y in points)
    slope = xy / xx
    return {'per_hour': slope * 3600, 'r2': xy * xy / (xx * yy) if yy else 0,
            'delta': slope * (max(xs) - min(xs))}


def summarize(samples, warmup=60):
    rows = [r for r in samples if r['t'] >= warmup]
    result = {'count': len(rows), 'steady_seconds': 0, 'metrics': {}, 'trends': {}, 'metric_counts': {}}
    if not rows:
        return result
    result['steady_seconds'] = rows[-1]['t'] - rows[0]['t']
    for key in ('cpu', 'pss_kb', 'rss_kb', 'native_kb', 'graphics_kb', 'egl_kb', 'threads', 'fd'):
        points = [(r['t'], r[key]) for r in rows
                  if isinstance(r.get(key), (float, int)) and math.isfinite(r[key])]
        if points:
            result['metric_counts'][key] = len(points)
            values = [v for _, v in points]
            result['metrics'][key] = {'mean': statistics.mean(values),
                                      'p50': percentile(values, .5), 'p95': percentile(values, .95)}
            result['trends'][key] = trend(points)
    # Counters reset on reopen/reuse. Device supplies monotonic accumulated
    # positive deltas across engine lifetimes, rather than subtracting endpoints.
    for key, numerator, denominator in [('drop_rate', 'drops', 'frames'),
                                         ('decoder_drop_rate', 'decoder_drops', 'frames'),
                                         ('jank_rate', 'janky', 'gfx_frames')]:
        valid = [r for r in rows if r.get(numerator) is not None and r.get(denominator) is not None]
        if len(valid) >= 2:
            n = valid[-1][numerator] - valid[0][numerator]
            d = valid[-1][denominator] - valid[0][denominator]
            if d > 0 and n >= 0:
                result[key] = n / d
    return result


def judge(summary, baseline=None, regression=.20, platform='android', audio=False,
          leak_limits=None, min_seconds=120):
    failures, blocked = [], []
    required = ('cpu', 'rss_kb') if platform == 'windows' else ('cpu', 'pss_kb', 'native_kb', 'threads', 'fd')
    if summary['count'] < 10 or summary['steady_seconds'] < min_seconds:
        blocked.append('insufficient-steady-data')
    if baseline is None:
        blocked.append('no-baseline')
    for key in required:
        if key not in summary['metrics']:
            blocked.append('unavailable:' + key)
        elif summary.get('metric_counts', {}).get(key, 0) < .8 * summary['count']:
            blocked.append('sparse:' + key)
    for key, stat in [('cpu', 'p95'), ('rss_kb' if platform == 'windows' else 'pss_kb', 'mean')]:
        current = summary['metrics'].get(key, {}).get(stat)
        old = (baseline or {}).get('metrics', {}).get(key, {}).get(stat)
        if baseline is not None and old is None:
            blocked.append('baseline-missing:' + key)
        if current is not None and old is not None and regressed(key, current, old, regression):
            failures.append('regression:' + key)
    for key in (() if audio else ('drop_rate', 'decoder_drop_rate') + (() if platform == 'windows' else ('jank_rate',))):
        current, old = summary.get(key), (baseline or {}).get(key)
        if current is None or (baseline is not None and old is None):
            blocked.append('unavailable:' + key)
        elif old is not None and regressed(key, current, old, regression):
            failures.append('regression:' + key)
    for key, (slope, delta) in (leak_limits or LEAK_LIMITS).items():
        fit = summary['trends'].get(key)
        if fit and fit['per_hour'] > slope and fit['delta'] > delta and fit['r2'] >= .7:
            failures.append('leak:' + key)
    # 泄漏不依赖基线：无基线时也照样判 FAIL，其余情况无基线一律 BLOCKED。
    status = 'FAIL' if failures else 'BLOCKED' if baseline is None or blocked else 'PASS'
    return {'status': status,
            'failures': failures, 'blocked': blocked}
