"""门控回归：均值、连续窗口、进程树扣除及整对重试。"""
import tempfile
import unittest
import subprocess
import sys
import json
from pathlib import Path
from unittest.mock import patch

from dioman_bench_load import DiomanBenchGate, DiomanBenchJob, classify, point


class DiomanBenchLoadTest(unittest.TestCase):
    """验证污染轮不会进入已接受的三轮。"""

    def test_mean_boundary(self):
        """均值边界允许，超过边界作废。"""
        self.assertTrue(classify([{'externalPercent': 20, 'seconds': 1}] * 3)['clean'])
        self.assertFalse(classify([{'externalPercent': 20.01, 'seconds': 1}] * 3)['clean'])

    def test_sustained_spike(self):
        """平均低但连续三秒高仍须作废。"""
        points = [{'externalPercent': value, 'seconds': 1} for value in [36]*3 + [0]*10]
        self.assertIn('连续三秒外部占用超过35%', classify(points)['reasons'])
        points[1]['externalPercent'] = 0
        self.assertTrue(classify(points)['clean'])

    def test_missing_sample(self):
        """调度丢点时拒绝把未知区间认作干净。"""
        self.assertFalse(classify([{'externalPercent': 0, 'seconds': 3}] * 3)['clean'])

    def test_process_cpu_subtraction(self):
        """CPU 使用同一系统分母且进程标识含创建时间。"""
        before = {'time': 1, 'idle': 100, 'total': 1000, 'processes': {'1': (1, 100)}}
        after = {'time': 2, 'idle': 150, 'total': 1100, 'processes': {'1': (1, 130)}}
        self.assertEqual(point(before, after)['externalPercent'], 20)
        after['processes']['1'] = (2, 130)
        self.assertEqual(point(before, after)['externalPercent'], 50)

    def test_pair_retry(self):
        """B 污染时连同 A 作废，保持下一对的执行顺序。"""
        with tempfile.TemporaryDirectory() as raw:
            gate = DiomanBenchGate(raw)
            calls = []

            def run(command, stem):
                """注入第二次调用污染，其他进程均干净。"""
                calls.append(command)
                return len(calls), {'clean': len(calls) != 2}

            with patch.object(gate, 'run', side_effect=run):
                result = gate.pairs('test', {'A': 'a', 'B': 'b'})
            self.assertEqual(calls, ['a', 'b'] * 4)
            self.assertEqual(result, {'A': [3, 5, 7], 'B': [4, 6, 8]})
            self.assertFalse(gate.records[0]['accepted'])

    def test_job_descendants(self):
        """已退出子进程仍被计时，普通与高优先级均传给后代。"""
        child = ('import ctypes as c,time; k=c.WinDLL("kernel32"); '
                 'k.GetPriorityClass.argtypes=[c.c_void_p]; '
                 'print(k.GetPriorityClass(c.c_void_p(-1))); '
                 'end=time.monotonic()+0.3\n'
                 'while time.monotonic()<end: pass')
        for high in (False, True):
            flags = subprocess.HIGH_PRIORITY_CLASS if high else 0
            parent = ('import time,subprocess,sys;time.sleep(0.3);'
                      f'subprocess.run([sys.executable,"-c",{child!r}],check=True,creationflags={flags})')
            proc = subprocess.Popen([sys.executable, '-c', parent], stdout=subprocess.PIPE,
                                    text=True, creationflags=subprocess.HIGH_PRIORITY_CLASS if high else 0)
            job = None
            try:
                job = DiomanBenchJob(proc.pid, high)
                output, _ = proc.communicate(timeout=15)
                self.assertEqual(proc.returncode, 0)
                self.assertEqual(int(output.strip()), subprocess.HIGH_PRIORITY_CLASS if high else subprocess.NORMAL_PRIORITY_CLASS)
                self.assertGreater(job.cpu(), 1000000)
            finally:
                proc.wait(timeout=15)
                if job:
                    job.close()
                if proc.stdout:
                    proc.stdout.close()

    def test_summary_dependencies(self):
        """S5 不稳定不传染 S4，比例仍逐轮计算且选中行不拼接。"""
        with tempfile.TemporaryDirectory() as raw:
            dest = Path(raw)
            for label in ('legacy', 'pipeline'):
                for index, speed in enumerate((1000, 1020, 1010), 1):
                    rows = []
                    for scene in range(1, 7):
                        overhead = 1 if scene == 1 else (1.1 if label == 'legacy' else 1.3)
                        ops = speed / overhead
                        if scene == 5 and index == 2:
                            ops *= 2
                        rows.append({'scenario': f'S{scene}', 'opsPerSecond': ops,
                                     'meanMicros': 1000000/ops, 'p99Micros': index*100,
                                     'elapsedSeconds': 2, 'operations': 100,
                                     'sends': 0 if scene == 4 else 100})
                    (dest / f'bench-{index}-{label}.json').write_text(json.dumps({
                        'warmupMillis': 500, 'measurementMillis': 2000, 'results': rows}), encoding='utf-8')
            proc = subprocess.run([sys.executable, str(Path(__file__).with_name('pipeline_b6_bench_summary.py')),
                                   '--out', str(dest)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            gates = json.loads((dest / 'bench-gates.json').read_text())
            self.assertTrue(gates['S4']['eligible'])
            self.assertFalse(gates['S5']['eligible'])
            self.assertFalse(gates['S2']['passed'])
            self.assertFalse(gates['S4']['groupStable'])
            summary = json.loads((dest / 'bench-summary.json').read_text())
            self.assertEqual(summary['S1']['legacy']['selectedRound'], 3)
            self.assertEqual(summary['S1']['legacy']['median']['p99Micros'], 300)
            self.assertAlmostEqual(summary['S2']['pipeline']['medianOverheadRatio'], .3)


if __name__ == '__main__':
    unittest.main()
