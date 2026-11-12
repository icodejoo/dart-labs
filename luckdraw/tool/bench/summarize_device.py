"""核对本次设备原始轮次，输出中位数、预算结论与波动，不追加任何测试。"""

import argparse
import json
import math
import re
import shutil
import statistics
from pathlib import Path


def read_json(path):
    """读取 UTF-8 JSON，损坏输入直接失败。"""
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def main():
    """只接受指定的新采集目录，拒绝旧 RSS 数据和重复运行标识。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--calibrate", action="store_true")
    args = parser.parse_args()
    bench = Path(__file__).resolve().parent
    root = Path(args.input).resolve()
    cycles = int(re.search(r"const int kRssCycles = (\d+);", (bench / "metrics.dart").read_text())[1])
    repetitions = int(re.search(r"const int kBenchRepetitions = (\d+);", (bench / "metrics.dart").read_text())[1])
    records = read_json(root / "runs.json")
    budgets = read_json(bench / "budgets.json")
    original = root / "design_budgets.json"
    if not original.exists():
        original.write_text(json.dumps(budgets, indent=2) + "\n", newline="\n")
    design = read_json(original)
    grouped = {}
    ids = set()
    collection = root / "comparison"
    collection.mkdir(exist_ok=True)
    for record in records:
        if not record["valid"]:
            continue
        if not record["unlockedBefore"] or record["lockedDuring"] or record["exitCode"] != 0:
            raise ValueError("轮次有效标记与设备状态矛盾")
        for path in (root / record["directory"]).glob("*.timeline_summary.json"):
            data = read_json(path)
            key = data["report_key"]
            if key == "reference_spin":
                continue
            if data["device_serial"] != "10AE9K17UE0011S" or data["device_model"] != "vivo V2417":
                raise ValueError("设备身份不一致")
            if not record["startedAt"] <= data["recorded_at"] <= record["endedAt"]:
                raise ValueError("报告不是本轮新生成")
            identity = (key, data["run_id"])
            if identity in ids:
                raise ValueError("重复 run_id")
            ids.add(identity)
            if key != "wheel_first_frame":
                if data["rss_cycles"] != cycles or any(len(data[k]) != cycles for k in ("rss_pages", "rss_blank")):
                    raise ValueError("RSS 样本数不一致")
                if key != "memory_cycles" and (data["fps"] <= 0 or data["frame_count"] <= 0):
                    raise ValueError("零帧无效数据")
            grouped.setdefault(key, []).append(data)
            shutil.copy2(path, collection / path.name)
    output = {"device": "vivo V2417", "serial": "10AE9K17UE0011S", "rss_cycles": cycles,
              "source": root.name, "valid_rounds": {}, "scenarios": {}, "calibrated": {}}
    lines = ["场景 | 有效轮 | UI p50/p90/p99 ms | Raster p50/p90/p99 ms | 合计 p50/p90/p99 ms | 掉帧率 | RSS增量/增长 MiB | GC/参照", "--- | --- | --- | --- | --- | --- | --- | ---"]
    for key, limits in design.items():
        runs = grouped.get(key, [])
        output["valid_rounds"][key] = len(runs)
        if len(runs) != repetitions:
            output["scenarios"][key] = {"error": f"仅得到 {len(runs)} 次有效数据"}
            lines.append(f"{key} | {len(runs)}/{repetitions} | 缺少有效轮 | — | — | — | — | —")
            continue
        metrics = {}
        for metric, value in runs[0].items():
            if isinstance(value, (int, float)) and not isinstance(value, bool) and all(isinstance(r.get(metric), (int, float)) for r in runs):
                values = [r[metric] for r in runs]
                median = statistics.median(values)
                metrics[metric] = {"median": median, "min": min(values), "max": max(values),
                                   "spread_ratio": (max(values) - min(values)) / median if median else (0 if max(values) == 0 else None),
                                   "stable": max(values) - min(values) <= median * 0.30}
        effective_limits = dict(limits)
        if "dropped_frame_ratio" in effective_limits:
            if metrics["refresh_rate_hz"]["median"] >= 100:
                effective_limits["dropped_frame_ratio"] = min(effective_limits["dropped_frame_ratio"] * 2, 0.01)
            effective_limits.update(design["memory_cycles"])
        results = {}
        for metric, limit in effective_limits.items():
            m = metrics[metric]
            results[metric] = {**m, "limit": limit, "within_budget": m["median"] <= limit}
            if args.calibrate and metric in limits and m["median"] <= limit and m["stable"]:
                # 使用明确精度向上取整，再与原设计上限取较严者；刷新率掉帧倍数只在比较时应用。
                precision = 1 if metric.endswith("bytes") or metric == "new_gen_gc_over_reference" else (1000 if metric.endswith("_millis") else 1_000_000)
                ceiling = math.ceil(m["median"] * 1.1 * precision) / precision
                calibrated = min(ceiling, limits[metric])
                if metric == "dropped_frame_ratio" and metrics["refresh_rate_hz"]["median"] >= 100:
                    calibrated = min(math.ceil(m["median"] * 1.1 / 2 * precision) / precision, limits[metric])
                budgets[key][metric] = calibrated
                output["calibrated"][f"{key}/{metric}"] = calibrated
        output["scenarios"][key] = {"metrics": metrics, "budget_results": results,
                                     "run_ids": [r["run_id"] for r in runs]}
        def median_value(metric):
            """返回可读中位数，未采集的指标显示横线。"""
            return f'{metrics[metric]["median"]:.3f}' if metric in metrics else "—"
        def quantiles(part):
            """按 p50/p90/p99 输出同一配对指标组。"""
            return "/".join(median_value(f"{p}th_percentile_{part}_millis") for p in (50, 90, 99))
        rss = "/".join(f'{metrics[m]["median"] / 1024**2:.3f}' for m in design["memory_cycles"]) if key != "wheel_first_frame" else "—"
        drop = f'{metrics["dropped_frame_ratio"]["median"]:.4%}' if "dropped_frame_ratio" in metrics else "—"
        lines.append(f'{key} | {len(runs)}/{repetitions} | {quantiles("frame_build_time")} | {quantiles("frame_rasterizer_time")} | {quantiles("build_plus_raster")} | {drop} | {rss} | {median_value("new_gen_gc_count")}/{median_value("reference_new_gen_gc_count")}')
    (root / "profile_summary.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (root / "profile_table.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    if args.calibrate:
        (bench / "budgets.json").write_text(json.dumps(budgets, indent=2) + "\n", newline="\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
