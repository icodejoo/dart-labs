"""验证测量脚本的分组、几何与门槛行为。"""

import unittest
from collections import Counter

from raster_cache_auto_r2_plan import make_plan, reduce_plan
from raster_cache_auto_r2_rules import case_geometry, evaluate, fit, needs_confirmation, predict


def make_case(sample, gain, points=15000, *, split="fit"):
    """构造在框内且有独立重复的规则评价组合。"""
    return {
        "sample": sample, "size": "200", "split": split,
        "gain_us": gain, "paired_gain_us": [gain, gain, gain],
        "contained": True, "covers_clip": False, "occupies_width": False,
        "content_visible_px": 200000, "estimated_bytes": 850000, "bytes": 850000,
        "features": {"points": points, "paths": 1, "blurs": 0},
    }


class SamplingTest(unittest.TestCase):
    """约束按文件划分与缩样时的固定留出比例。"""

    def test_same_seed_same_plan_and_reduced_split(self):
        """重复生成固定十图，缩样后不泄漏原组别。"""
        manifest = [
            {"id": f"web-{i:03}", "category": f"cat-{i % 9}", "bytes": 512 * (i + 1),
             "image_count": int(i % 5 == 0), "has_blur": int(i % 3 == 0),
             "has_mask": 0, "has_pattern": 0, "text_count": 0, "has_filter": 0}
            for i in range(714)
        ]
        features = {"images": 0, "blurs": 0, "masks": 0, "patterns": 0,
                    "paths": 15, "points": 45, "clips": 0, "gradients": 0, "opacity": 0}
        native = [{"id": row["id"], "status": "ok", "features": features} for row in manifest]
        legacy = [{"sample": f"sample-{i}", "validation": bool(i % 2)} for i in range(38)]
        plan = make_plan(manifest, native, legacy)
        self.assertEqual(plan, make_plan(manifest, native, legacy))
        self.assertEqual(len(set(plan["pilot"])), 10)
        reduced = reduce_plan(plan["web"], plan["pilot"], 120)
        self.assertEqual(Counter(row["split"] for row in reduced),
                         {"fit": 84, "holdout": 36})
        self.assertTrue(set(plan["pilot"]) <= {row["id"] for row in reduced})
        self.assertTrue(all(row in plan["web"] for row in reduced))


class RuleTest(unittest.TestCase):
    """校验成本特征和以文件划分隔离的拟合。"""

    def test_tile_estimate_includes_sampling_edges_and_overscan(self):
        """复算满宽长图与只接触一个块的内缩内容。"""
        baseline = {"dpr": 2.8125, "screen_width_px": 1080, "screen_height_px": 2340}
        row = {
            "width_dp": 384, "height_dp": 1000,
            "features": {"picture_width": 384, "content_overflow": False,
                         "content_bounds": [0, 0, 384, 1000]},
        }
        self.assertEqual(case_geometry(row, baseline)["estimated_bytes"], 11319488)
        row["features"]["content_bounds"] = [1, 1, 60, 60]
        geometry = case_geometry(row, baseline)
        self.assertEqual(geometry["estimated_bytes"], 4 * 518 * 518)
        self.assertTrue(geometry["contained"])

    def test_poisoned_holdout_does_not_change_fit(self):
        """确认规则只看拟合组，且把同条件的负收益留出暴露为误开。"""
        train = [make_case("web-001", 2300), make_case("mdi-0", -200, points=100)]
        holdout = make_case("web-200", -25, split="holdout")
        rule = fit(train, {})
        self.assertIsNotNone(rule)
        self.assertEqual(rule, fit([*train, holdout], {}))
        self.assertTrue(predict(holdout, rule))
        self.assertEqual(evaluate([holdout], rule, {})["false"], 1)
        self.assertFalse(predict({**train[0], "contained": False}, rule))
        self.assertTrue(needs_confirmation(train[0], rule))

    def test_no_area_gate_still_rejects_a_slower_round(self):
        """点数门槛跳过单轮退化，路径和模糊仍可独立识别高成本小图。"""
        unstable = make_case("web-001", 400, points=12078)
        unstable["paired_gain_us"] = [632, -35, 953]
        path = make_case("web-002", 2200, points=300)
        path["features"]["paths"] = 100
        blur = make_case("web-003", 2100, points=30)
        blur["features"]["blurs"] = 1
        dense = make_case("web-004", 2300)
        for case in (unstable, path, blur, dense):
            case["content_visible_px"] = 100

        rule = fit([unstable, path, blur, dense], {}, fixed_area=0,
                   allow_blur=False, path_grid=(0, 100), allow_any_blur=True)
        self.assertEqual(rule["points"], 15000)
        self.assertFalse(predict(unstable, rule))
        self.assertTrue(all(predict(case, rule) for case in (path, blur, dense)))


if __name__ == "__main__":
    unittest.main()
