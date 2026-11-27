"""用拟合组比较低成本的缓存门槛，并以相同定义评价留出组。"""

import itertools
import math
import statistics
from collections import Counter, defaultdict

BENEFIT_US = 1000
MIB = 1024 ** 2
TILE = 512
PADDING = 2
OVERSCAN = 64
AREA_GRID = (0, 32768, 65536, 131072, 262144, 524288)
POINT_GRID = (1000, 2500, 5000, 7500, 10000, 15000, 25000, 50000, 100000)
PATH_GRID = (0, 100, 250, 500, 1000)
EFFECT_GRID = (0, 4_000_000, 8_000_000, 16_000_000,
               32_000_000, 64_000_000, 128_000_000)
CAP_GRID = (4 * MIB, 6 * MIB, 8 * MIB, 12 * MIB)


def tile_axis(start, end, full):
    """估算一轴的 RGBA 纹素数，包含每个块的采样边和插画边缘取整。"""
    if end <= start:
        return 0
    first = math.floor(start / TILE)
    after = math.ceil(end / TILE)
    lo = first * TILE if first else -PADDING
    hi = after * TILE
    if hi >= full:
        hi = math.ceil(full / PADDING) * PADDING + PADDING
    return hi - lo + (after - first) * 2 * PADDING


def case_geometry(row, baseline):
    """从已知边界和物理裁剪计算成本特征与当前分块字节数。"""
    features = row["features"]
    factor = baseline["dpr"] * row["width_dp"] / features["picture_width"]
    width = row["width_dp"] * baseline["dpr"]
    height = row["height_dp"] * baseline["dpr"]
    screen_width = baseline["screen_width_px"]
    screen_height = baseline["screen_height_px"]
    known = features["content_overflow"] is not None
    contained = False
    bounds = features["content_bounds"]
    if known:
        left, top, right, bottom = (value * factor for value in bounds)
        contained = (left >= -0.001 and top >= -0.001
                     and right <= width + 0.001 and bottom <= height + 0.001)
    if contained:
        left, top, right, bottom = max(0, left), max(0, top), min(width, right), min(height, bottom)
    else:
        left, top, right, bottom = 0, 0, width, height
    visible_content = max(0, min(right, screen_width) - left) * max(
        0, min(bottom, screen_height) - top)
    resident = 4 * tile_axis(left, min(right, screen_width + OVERSCAN), width) * tile_axis(
        top, min(bottom, screen_height + OVERSCAN), height)
    return {
        "contained": contained,
        "occupies_width": width >= screen_width - .001,
        "covers_clip": width >= screen_width - .001 and height >= screen_height - .001,
        "content_visible_px": round(visible_content),
        "estimated_bytes": resident,
    }


def aggregate(batches):
    """校验每帧数据并对同尺寸独立轮次取模式中位数。"""
    grouped = defaultdict(list)
    seen = set()
    for batch in batches:
        rows = batch["accepted"]
        if not rows or all(row["type"] == "skip" for row in rows):
            continue
        baseline, *cases = rows
        assert baseline["type"] == "baseline", batch["id"]
        check_measurement(baseline)
        for row in cases:
            if row["type"] == "skip":
                continue
            key = row["sample"], row["size"]
            assert (*key, batch["round"]) not in seen, key
            seen.add((*key, batch["round"]))
            modes = {item["mode"]: item for item in row["measurements"]}
            assert set(modes) == {"vector", "cached"}, key
            for mode in modes.values():
                check_measurement(mode)
            grouped[key].append((row, baseline, modes, batch["round"]))
    result = []
    for key, repetitions in grouped.items():
        row, baseline, _, _ = repetitions[0]
        assert all(other["features"] == row["features"] for other, *_ in repetitions), key
        vector = [modes["vector"]["p50_us"] for _, _, modes, _ in repetitions]
        cached = [modes["cached"]["p50_us"] for _, _, modes, _ in repetitions]
        result.append({
            "sample": key[0], "size": key[1], "split": row["split"],
            "rounds": sorted(round_id for *_, round_id in repetitions),
            "features": row["features"], "visible_px": row["visible_px"],
            "width_dp": row["width_dp"], "height_dp": row["height_dp"],
            **case_geometry(row, baseline),
            "baseline_us": statistics.median(b["p50_us"] for _, b, *_ in repetitions),
            "vector_us": statistics.median(vector),
            "cached_us": statistics.median(cached),
            "gain_us": statistics.median(vector) - statistics.median(cached),
            "paired_gain_us": [a - b for a, b in zip(vector, cached)],
            "bytes": statistics.median(modes["cached"]["bytes"] for _, _, modes, _ in repetitions),
            "tiles": statistics.median(modes["cached"]["tiles"] for _, _, modes, _ in repetitions),
            "generation_us": statistics.median(
                modes["cached"]["generation_us"] for _, _, modes, _ in repetitions),
        })
    return sorted(result, key=lambda item: (item["sample"], item["width_dp"]))


def check_measurement(row):
    """检查逐帧分位数、样本窗口及位图驻留状态。"""
    frames = sorted(row["raster_us"])
    assert len(frames) >= 18 and frames[0] >= 0
    assert row["p50_us"] == frames[(len(frames) - 1) // 2]
    assert row["p95_us"] == frames[(len(frames) * 95 + 99) // 100 - 1]
    assert row["fps"] > 0
    if row["mode"] == "cached":
        assert row["bytes"] > 0 and row["tiles"] > 0
        assert row["generation_us"] >= row["first_output_us"] > 0
        assert row["preparation_raster_us"]
    else:
        assert row["bytes"] == row["tiles"] == 0


def is_icon(case, by_id):
    """用元数据辨识对照组，只用于评价和限制误开。"""
    name = case["sample"]
    return (name.startswith("mdi-") or by_id.get(name, {}).get("category") in
            {"small", "emoji", "logo"})


def predict(case, rule):
    """在当前裁剪和缓存预算允许时应用拟合后的内容及成本门槛。"""
    if rule is None:
        return False
    if not case["contained"] and not (
        rule["geometry"] == "legacy_fallback" and case["covers_clip"]
    ):
        return False
    if rule["geometry"] == "full_width" and not case["occupies_width"]:
        return False
    area = case["content_visible_px"]
    if not area or area < rule["area"] or case["estimated_bytes"] > rule["cap"]:
        return False
    features = case["features"]
    paths = rule.get("paths", 0)
    return (features["points"] >= rule["points"] or
            bool(paths and features["paths"] >= paths) or
            bool(rule.get("any_blur") and features["blurs"]) or
            bool(rule["blur_area"] and features["blurs"] * area >= rule["blur_area"]))


def evaluate(cases, rule, by_id):
    """按净收益定义评价，启用后低于 1 ms 的记录另外统计。"""
    counts = Counter()
    opened = []
    false_cost = []
    for case in cases:
        gain = case["gain_us"]
        if predict(case, rule):
            opened.append(case)
            counts["icon_open"] += is_icon(case, by_id)
            outcome = "hit" if gain > BENEFIT_US else "weak" if gain > 0 else "false"
            if outcome == "false":
                false_cost.append({"sample": case["sample"], "size": case["size"],
                                   "bytes": case["bytes"], "gain_us": gain})
        else:
            outcome = "miss" if gain > BENEFIT_US else "closed"
        counts[outcome] += 1
    result = {key: counts[key] for key in ("hit", "false", "weak", "miss", "closed", "icon_open")}
    result["opened"] = len(opened)
    result["total"] = len(cases)
    result["false_cost"] = false_cost
    return result


def fit(cases, by_id, geometry="contained", *, fixed_area=None, allow_blur=True,
        path_grid=(0,), allow_any_blur=False):
    """只在拟合计时上选规则，优先拒绝图标、负收益及不稳定的正收益。"""
    train = [c for c in cases if c["split"] == "fit"]
    winner = None
    best = (0, 0, 0, 0, 0, 0, 0)
    decorated = [(case, is_icon(case, by_id)) for case in train]
    areas = AREA_GRID if fixed_area is None else (fixed_area,)
    effects = [(threshold, False) for threshold in (EFFECT_GRID if allow_blur else (0,))]
    if allow_any_blur:
        effects.append((0, True))
    contenders = itertools.product(areas, POINT_GRID, path_grid, effects, CAP_GRID)
    for area, points, paths, (blur_area, any_blur), cap in contenders:
        rule = dict(area=area, points=points, blur_area=blur_area, cap=cap, geometry=geometry)
        if paths:
            rule["paths"] = paths
        if any_blur:
            rule["any_blur"] = True
        hits = weak = benefit = 0
        for case, icon in decorated:
            if not predict(case, rule):
                continue
            gain = case["gain_us"]
            if icon or gain <= 0 or min(case["paired_gain_us"]) <= 0:
                break
            hits += gain > BENEFIT_US
            weak += gain <= BENEFIT_US
            benefit += gain
        else:
            if hits:
                score = (hits - 2 * weak, hits, -weak, -cap,
                         not (blur_area or any_blur), not paths, benefit)
                if score > best:
                    winner, best = rule, score
    return winner


def needs_confirmation(case, rule):
    """重跑 0.3–3 ms 的组合以及候选判定边界上下约 20% 的组合。"""
    if 300 <= case["gain_us"] <= 3000:
        return True
    if rule is None or not case["contained"]:
        return False
    area = case["content_visible_px"]
    points = case["features"]["points"]
    blur_area = case["features"]["blurs"] * area
    memory = case["estimated_bytes"]
    near = lambda value, threshold: threshold and .8 * threshold <= value <= 1.2 * threshold
    cost = points >= .8 * rule["points"] or (
        rule["blur_area"] and blur_area >= .8 * rule["blur_area"])
    return bool(
        cost and near(area, rule["area"]) and memory <= 1.2 * rule["cap"]
        or cost and near(memory, rule["cap"]) and area >= .8 * rule["area"]
        or area >= .8 * rule["area"] and memory <= 1.2 * rule["cap"]
        and (near(points, rule["points"]) or near(blur_area, rule["blur_area"]))
    )
