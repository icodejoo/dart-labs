"""Verify interval arithmetic for the device report. / 验证真机报告的区间计算。"""

import unittest

from summarize_ui_thread_decode_record import trial_frames, trial_stages


class TimeWindowsTest(unittest.TestCase):
    """Exercise worker, UI, and frame-window boundaries. / 验证 worker、UI 和帧窗口边界。"""

    def test_worker_and_ui_have_disjoint_intervals(self):
        """Worker ends at message delivery and UI is a paired sum. / worker 在消息送达时截断，UI 按同一次试次求和。"""
        row = {"times_us": {"call": 10, "call_return": 20, "message": 70,
                            "decode": 72, "decode_done": 95, "record": 102,
                            "record_done": 129}}
        self.assertEqual(trial_stages(row), {"worker": 60, "dispatch": 10,
                                           "decode": 23, "record": 27,
                                           "decode_to_record": 7, "ui": 50})

    def test_frame_number_and_spinner_cadence_bound_missing_slots(self):
        """Use the engine ID and estimate misses on both sides of first art. / 用引擎帧号定位，并分别估算首显前后漏帧。"""
        phases = ["vsyncStart", "buildStart", "buildFinish", "rasterStart",
                  "rasterFinish", "frameNumber"]
        stamps = list(range(0, 130_000, 8_333)) + [149_995, 166_661, 174_994, 183_327, 191_660]
        frames = [[stamp, stamp + 120, stamp + 620, stamp + 700, stamp + 1300, index]
                  for index, stamp in enumerate(stamps)]
        art = frames[17]
        art[1] += 19_000
        art[2] += 19_000
        art[3] += 19_000
        art[4] += 27_000
        row = {"id": "fixture", "dispatch": "worker", "times_us": {
            "mount": 115_000, "call": 121_000, "call_return": 122_000,
            "message": 130_000, "decode": 130_000, "decode_done": 134_000,
            "record": 134_020, "record_done": 147_000, "first_art_frame": 17,
            "window_end": 190_000,
        }}
        actual = trial_frames(row, frames, phases)
        self.assertEqual(actual["period"], 8333)
        self.assertEqual(actual["art_late_slots"], 2)
        self.assertEqual(actual["missed_window"], 3)
        self.assertEqual(actual["frames"], 5)
        self.assertEqual(actual["first_art_raster"], 8600)
        self.assertEqual(actual["raster"], 8600)
        self.assertEqual(actual["result_to_art"], art[2] - 130_000)


if __name__ == "__main__":
    unittest.main()
