import unittest
import json
from pathlib import Path
import tempfile
from unittest.mock import patch
from coverage_perf import Android, Windows
import coverage_perf
from perf_judge import judge, summarize, trend


def series(cpu=20, slope=0):
    return [dict(t=t, cpu=cpu, pss_kb=100000 + slope * t / 3600,
                 native_kb=50000, threads=20, fd=50, frames=t*25,
                 drops=0, decoder_drops=0, janky=0, gfx_frames=t*60)
            for t in range(0, 3601, 2)]


class JudgeTests(unittest.TestCase):
    def setUp(self):
        self.base = summarize(series())

    def test_stable(self):
        self.assertEqual(judge(self.base, self.base)['status'], 'PASS')

    def test_cpu(self):
        self.assertIn('regression:cpu', judge(summarize(series(30)), self.base)['failures'])

    def test_slow_leak(self):
        self.assertIn('leak:pss_kb', judge(summarize(series(slope=16000)), self.base)['failures'])

    def test_noise(self):
        rows = series()
        for i, row in enumerate(rows):
            row['pss_kb'] += 14000 * (-1 if i % 2 else 1)
        self.assertEqual(judge(summarize(rows), self.base)['status'], 'PASS')

    def test_no_baseline(self):
        self.assertIn('no-baseline', judge(self.base)['blocked'])
        # 泄漏不依赖基线，没有基线也判 FAIL。
        self.assertEqual(judge(summarize(series(slope=16000)))['status'], 'FAIL')

    def test_warmup(self):
        rows = series()
        for row in rows:
            if row['t'] < 60:
                row.update(cpu=10000, pss_kb=9000000)
        self.assertEqual(summarize(rows), self.base)

    def test_missing(self):
        rows = series()
        for r in rows:
            r['fd'] = None
        self.assertEqual(judge(summarize(rows), self.base)['status'], 'BLOCKED')

    def test_zero_baseline_drop(self):
        # 基线掉帧率为 0 时，零星掉帧不算回归，超出绝对下限才算。
        self.assertNotIn('regression:drop_rate',
                         judge(dict(self.base, drop_rate=.001), self.base)['failures'])
        self.assertIn('regression:drop_rate',
                      judge(dict(self.base, drop_rate=.01), self.base)['failures'])

    def test_small_cpu_baseline(self):
        # audioOnly 一类基线 CPU 很低时，相对涨幅大但绝对量小，不算回归。
        base = summarize(series(2))
        self.assertNotIn('regression:cpu', judge(summarize(series(3)), base)['failures'])
        self.assertIn('regression:cpu', judge(summarize(series(9)), base)['failures'])

    def test_short(self):
        self.assertEqual(judge(summarize(series()[:35]), self.base)['status'], 'BLOCKED')

    def test_slope_units(self):
        self.assertEqual(trend([(0, 0), (1800, 5), (3600, 10)])['per_hour'], 10)

    def test_android_sampler(self):
        sampler = Android.__new__(Android)
        sampler.package, sampler.hz, sampler.last, sampler.thermal = 'test.app', 100, (100, 100), False
        fields = ['S'] + ['0'] * 10 + ['150', '50'] + ['0'] * 10
        def shell(script):
            if script.startswith('pidof'): return '123'
            if script.endswith('/stat'): return '123 (name with spaces) ' + ' '.join(fields)
            if script.endswith('/status'): return 'Threads:\t22'
            if script.startswith('ls '): return '0\n1\n2'
            if script == 'cat /proc/uptime': return '102.0 500.0'
            if script.startswith('dumpsys meminfo'):
                return 'Native Heap 1000 0 0\n EGL mtrack 200\n Graphics: 300\n TOTAL PSS: 5000'
            if script.startswith('dumpsys gfxinfo'):
                return 'Janky frames: 2 (1%)\nTotal frames rendered: 200'
            raise AssertionError(script)
        sampler.shell = shell
        sampler.proc = shell
        row = sampler.sample(123)
        self.assertEqual(row['cpu'], 50)
        self.assertEqual([row[k] for k in ('pss_kb','native_kb','graphics_kb','egl_kb','threads','fd')],
                         [5000,1000,300,200,22,3])
        # gfxinfo 仅作辅助字段；janky/gfx_frames 由设备端 Flutter 帧耗时提供，采样器不得覆盖。
        self.assertEqual((row['gfxinfo_janky'], row['gfxinfo_frames']), (2, 200))
        self.assertNotIn('janky', row)
        self.assertNotIn('gfx_frames', row)
        with self.assertRaises(RuntimeError): sampler.sample(999)

    def test_windows_sampler(self):
        sampler = Windows()
        with patch('coverage_perf.command', side_effect=[
                '{"cpu":2,"rss":1048576,"threads":5,"handles":10,"start":"same"}',
                '{"cpu":3,"rss":2097152,"threads":5,"handles":10,"start":"same"}']), \
             patch('coverage_perf.time.monotonic', side_effect=[10, 12]):
            self.assertNotIn('cpu', sampler.sample(123))
            row = sampler.sample(123)
            self.assertEqual(row['cpu'], 50)
            self.assertEqual(row['rss_kb'], 2048)

    def test_sparse_cpu_blocks(self):
        rows = series()
        for r in rows[100:]:
            r.pop('cpu')
        self.assertIn('sparse:cpu', judge(summarize(rows), self.base)['blocked'])

    def test_runner_baseline_roundtrip(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'perf_baseline').mkdir()
            argv = ['coverage_perf.py', '--platform', 'windows', '--scenes', 'vod-hw',
                    '--seconds', '184', '--output', str(root / 'run'), '--record-baseline']
            def run():
                states = iter([{'busy': t < 184, 'pid': 123,
                    'sample': dict(t=t, frames=t*30, drops=0, decoder_drops=0),
                    'result': {'status': 'COLLECTED'}} for t in range(0,185,2)])
                def control(endpoint, data=None):
                    if endpoint == 'finish': return {'running': False}
                    return {'pid': 123} if endpoint == 'start' else next(states)
                with patch('sys.argv', argv), patch.object(coverage_perf, 'TOOL', root), \
                     patch.object(coverage_perf, 'control', side_effect=control), \
                     patch.object(coverage_perf, 'command', return_value='commit'), \
                     patch.object(coverage_perf, 'Windows') as cls, \
                     patch.object(coverage_perf.time, 'sleep'), patch('builtins.print'):
                    cls.return_value.identity.return_value = {'device':'windows-test','os':'test','model':'test'}
                    cls.return_value.sample.return_value = {'cpu':20, 'rss_kb':100000, 'threads':20}
                    return coverage_perf.main()
            try:
                self.assertEqual(run(), 2)  # Recording data is not itself PASS.
                saved = json.loads((root / 'perf_baseline/windows-test.json').read_text())
                self.assertIn('vod-hw', saved['scenarios'])
                self.assertEqual(run(), 0)  # JSON roundtrip preserves compatibility.
            finally:
                coverage_perf.DRIVER = None


    def test_record_baseline_per_scene(self):
        # 按场景记录：失败场景不写入，合格场景写入，已有的同名场景不被失败证据覆盖。
        ok = {'summary': {'x': 1}, 'verdict': {'status': 'BLOCKED', 'failures': [], 'blocked': ['no-baseline']}}
        bad = {'summary': {'x': 2}, 'verdict': {'status': 'FAIL', 'failures': ['leak:threads'], 'blocked': ['no-baseline']}}
        report = {'identity': {'device': 'd'}, 'configuration': {}, 'sources': {}, 'commit': 'c1',
                  'scenarios': {'vod-hw': ok, 'feed': bad}}
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'sub' / 'd.json'
            self.assertEqual(coverage_perf.record_baseline(report, None, False, path), ['vod-hw'])
            saved = json.loads(path.read_text(encoding='utf-8'))
            self.assertEqual(list(saved['scenarios']), ['vod-hw'])
            old = {'identity': {'device': 'd'}, 'commit': 'c0', 'scenarios': {'feed': {'summary': {'x': 0}}}}
            report['scenarios'] = {'feed': bad}
            self.assertEqual(coverage_perf.record_baseline(report, old, True, path), [])
            self.assertEqual(json.loads(path.read_text(encoding='utf-8'))['scenarios'].keys(), {'vod-hw'})


if __name__ == '__main__':
    unittest.main()
