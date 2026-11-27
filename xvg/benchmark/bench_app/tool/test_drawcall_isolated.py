"""Tests the experiment matrix and frame attribution. / 测试实验矩阵与帧计时归属。"""

import unittest

from run_drawcall_isolated import COMBINATIONS, ROUNDS, SAMPLES, resume_rounds, round_plan, trial_metrics
from run_drawcall_merge_v3 import SAMPLES as QUICK_SAMPLES, VARIANTS, make_plan, validate
from run_drawcall_micro import TraceLoss


class DrawcallIsolatedTest(unittest.TestCase):
    """Validates independent randomization and startup timing. / 验证独立随机化及启动耗时。"""

    def test_all_samples_and_combinations_are_randomized(self):
        """Runs each combination and sample exactly once in each round. / 每轮每个组合和样本恰好执行一次。"""
        plans = [round_plan(i) for i in range(1, ROUNDS + 1)]
        for plan in plans:
            self.assertCountEqual(plan["samples"], SAMPLES)
            self.assertCountEqual(plan["combinations"], COMBINATIONS)
        self.assertGreater(len({tuple(plan["samples"]) for plan in plans}), 1)
        self.assertGreater(len({tuple(plan["combinations"]) for plan in plans}), 1)

    def test_resume_retires_the_partial_round(self):
        """Preserves whole pixel comparisons and rejects mismatched artifacts. / 保留整轮像素比较，同时拒绝产物不符的断点。"""
        identity = {key: key for key in ("device", "model", "android", "backend", "sdk",
                                         "builds", "inputs", "seed")}
        first, second = round_plan(1), round_plan(2)
        complete = {"plan": first, "runs": dict.fromkeys(first["combinations"]), "pixel_diffs": {}}
        partial = {"plan": second, "runs": dict.fromkeys(second["combinations"][:1])}
        checkpoint = {**identity, "rounds": [complete, partial], "retries": ["timeout"]}
        raw = {**identity, "rounds": []}
        resume_rounds(raw, checkpoint)
        self.assertEqual(raw["rounds"], [complete])
        self.assertEqual(raw["discarded_partial_rounds"], [partial])
        self.assertEqual(raw["retries"], ["timeout"])
        with self.assertRaisesRegex(RuntimeError, "Checkpoint differs in builds"):
            resume_rounds(raw, {**checkpoint, "builds": "different"})

    def test_separates_first_art_snapshot_and_steady_state(self):
        """Measures frame overruns and gaps before steady-state work. / 在稳态前分别统计帧超时与缺失节拍。"""
        run = {"frame_phases": ["vsyncStart", "buildStart", "buildFinish", "rasterStart",
                                "rasterFinish", "frameNumber"], "frames": [
            [8333, 8400, 9000, 9000, 10000, 1],
            [16666, 17000, 26000, 26100, 27100, 2],
            [33332, 34000, 34500, 36000, 45000, 3],
            *[[i * 8333, i * 8333, i * 8333 + 700, i * 8333 + 800,
               i * 8333 + 800 + duration, i] for i, duration in enumerate(
                [9999, 1000, 1200, 1400, 1600, 1800], 12)],
        ]}
        row = {"id": "fixture", "hz": 120.00000762939453, "times_us": {
            "mount": 12000, "window_end": 150000, "first_art_frame": 3,
        }}
        result = trial_metrics(run, row, [[35000, 39000, 8], [45000, 52000, 8]])
        self.assertEqual(result["display"], 33000)
        self.assertEqual(result["ui_over_budget"], 1)
        self.assertEqual(result["raster_over_budget"], 1)
        self.assertEqual(result["drops"], 1)
        self.assertEqual(result["snap_first"], 4000)
        self.assertEqual(result["snap_peak"], 7000)
        self.assertEqual(result["steady_frames"], 5)
        self.assertEqual(result["steady_raster"], 1400)


class DrawcallQuickTest(unittest.TestCase):
    """Checks the quick matrix and the native snapshot attribution. / 检查快速矩阵和原生快照归属。"""

    def test_reverses_orders(self):
        """Runs each sample and build once, then reverses both. / 每张图和每档各跑一次，第二轮两种顺序都反转。"""
        first, second = make_plan(1), make_plan(2)
        self.assertEqual(first["samples"], list(QUICK_SAMPLES))
        self.assertEqual(first["combinations"], list(VARIANTS))
        self.assertEqual(second["samples"], first["samples"][::-1])
        self.assertEqual(second["combinations"], first["combinations"][::-1])

    def test_counts_only_the_snapshot_in_the_window(self):
        """Excludes later readbacks and rejects a missing native slice. / 排除后续像素读回，并拒绝原生片段缺失的试次。"""
        sample = QUICK_SAMPLES[0]
        plan = {"round": 1, "samples": [sample], "trials": 1}
        row = {"id": sample, "trial": 1, "bytes": 500, "paths": 100,
               "units": 20_000, "dispatch": "worker", "recording_us": [8],
               "times_us": {"call": 1, "call_return": 2, "decode": 3, "decode_done": 4,
                            "record": 5, "record_done": 13, "first_art_frame": 1,
                            "window_end": 40},
               "requests": [[14, 1, 50, 60], [15, 0, 50, 60]]}
        run = {"round": 1, "stages": [row], "scenarios": [row],
               "frame_phases": ["frameNumber"], "frames": [[1]],
               "native_snapshots": [[17, 29, 1], [43, 48, 1]]}
        self.assertEqual(validate(run, plan)[sample],
                         {"recording_us": 8, "snap_first_us": 12, "size": [50, 60], "paths": 100})
        run["native_snapshots"].pop(0)
        with self.assertRaises(TraceLoss):
            validate(run, plan)


if __name__ == "__main__":
    unittest.main()
