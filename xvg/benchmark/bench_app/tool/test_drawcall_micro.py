"""Tests the host-side benchmark checks. / 测试基准的主机端校验。"""

import unittest

from run_drawcall_micro import case, join, plan, sample_stats, trace_slices


class DrawcallMicroTest(unittest.TestCase):
    """Protects case coverage and the two timing reductions. / 保护组合覆盖和两种耗时统计。"""

    def setUp(self):
        """Prepares one warmup frame, four samples and one native request. / 准备一帧预热、四帧采样与一次原生请求。"""
        trial = case("rect", 80000, "A")
        self.plan = {"trials": [trial], "warm": 1, "samples": 4}
        self.frames = self.frame_rows((900, 12, 18, 22, 48))
        self.frame = {
            **trial,
            "record_us": 42,
            "frames": self.frames,
            "baseline": self.frame_rows((900, 2, 3, 4, 8)),
        }
        self.request = {**trial, "request_us": 1000, "handle_us": 1020, "readback_us": 2000}
        self.native = [1030, 1140, 1]

    @staticmethod
    def frame_rows(durations):
        """Builds FrameTiming rows with controlled raster durations. / 构造 raster 耗时可控的 FrameTiming 记录。"""
        return [[i, i * 1000, i * 1000 + 1, i * 1000 + 2, i * 1000 + 2 + ms, 0, 0]
                for i, ms in enumerate(durations, 1)]

    def test_matrix(self):
        """Checks unique case coverage and independent ordering. / 检查组合覆盖、唯一性和独立排序。"""
        first, second = (plan(round_number)["trials"] for round_number in (1, 2))
        first_ids = [row["id"] for row in first]
        second_ids = [row["id"] for row in second]
        self.assertEqual(len(set(first_ids)), 63)
        self.assertCountEqual(first_ids, second_ids)
        self.assertNotEqual(first_ids, second_ids)
        self.assertEqual({row["shape"] for row in first if row["mode"] == "B"}, {"rect"})
        self.assertEqual(sum(row["group"] == row["count"] for row in first), 12)

    def test_timing_reductions(self):
        """Checks quantiles, warmup exclusion and baseline subtraction. / 检查分位数、排除预热和扣除基线。"""
        self.assertEqual(sample_stats(self.frames, 1, 4), {"p50_us": 20.0, "p90_us": 48})
        entry, = join(self.plan, [self.frame], [self.request], [self.native])
        self.assertEqual(entry["net"], {"p50_us": 16.5, "p90_us": 40})
        self.assertEqual(entry["snapshot_us"], 110)

    def test_rejects_cached_frames(self):
        """Rejects a raster sample containing a cached picture. / 拒绝含缓存 Picture 的 raster 样本。"""
        self.frames[1][-2] = 1
        with self.assertRaises(RuntimeError):
            sample_stats(self.frames, 1, 4)

    def test_rejects_snapshot_mismatches(self):
        """Rejects missing, duplicated and out-of-window native slices. / 拒绝缺失、重复和窗口外的原生切片。"""
        for events in ([], [self.native, self.native], [[999, 1140, 1]], [[1030, 2010, 1]]):
            with self.subTest(events=events), self.assertRaises(RuntimeError):
                join(self.plan, [self.frame], [self.request], events)

    def test_stitches_trace_windows(self):
        """Pairs out-of-order endpoints and deduplicates overlapping slices. / 配对乱序切片起止并去除重叠窗口重复项。"""
        events = [(150, 7, "E", 0), (100, 7, "B", 0), (180, 8, "X", 25),
                  (100, 7, "X", 50), (180, 8, "X", 25)]
        self.assertEqual(trace_slices(events), [[100, 150, 7], [180, 205, 8]])


if __name__ == "__main__":
    unittest.main()
