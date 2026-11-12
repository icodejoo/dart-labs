"""汇总物理碰撞模式的真机 A/B：参数化（capsule_mixing / lotto_draw）对物理（*_physics）。

读取 run_perf.ps1 的结果目录（每轮含 *.timeline_summary.json 与 *.timeline.json），
输出每个变体的有效轮数、帧时均值、P90/P99、掉帧与 luckdraw.physics.step 耗时，
并给出同场景物理相对参数化的增量。不修改任何指标、预算或有效轮数。

用法：python tool/bench/summarize_physics_ab.py tool/bench/results/phys_ab [输出.json]
"""

import json
import statistics
import sys
from pathlib import Path

PAIRS = {"capsule": ("capsule_mixing", "capsule_physics"),
         "lotto": ("lotto_draw", "lotto_physics")}
METRICS = {
    "ui_avg_ms": "average_frame_build_time_millis",
    "ui_p90_ms": "90th_percentile_frame_build_time_millis",
    "ui_p99_ms": "99th_percentile_frame_build_time_millis",
    "raster_avg_ms": "average_frame_rasterizer_time_millis",
    "raster_p90_ms": "90th_percentile_frame_rasterizer_time_millis",
    "raster_p99_ms": "99th_percentile_frame_rasterizer_time_millis",
    "frame_count": "frame_count",
    "new_gen_gc": "new_gen_gc_count",
}
STEP = "luckdraw.physics.step"


def load(path):
    """读取 JSON，兼容 BOM。"""
    return json.loads(Path(path).read_bytes().decode("utf-8-sig"))


def physics_steps(timeline_path):
    """返回 luckdraw.physics.step 的耗时列表（毫秒），支持 B/E 与 X 事件。"""
    stacks, values = {}, []
    for event in load(timeline_path)["traceEvents"]:
        if event.get("name") != STEP and event.get("ph") != "E":
            continue
        thread = event.get("pid"), event.get("tid")
        phase = event.get("ph")
        if phase == "X" and event.get("name") == STEP:
            values.append(event["dur"] / 1000)
        elif phase == "B" and event.get("name") == STEP:
            stacks.setdefault(thread, []).append(event["ts"])
        elif phase == "E" and stacks.get(thread):
            values.append((event["ts"] - stacks[thread].pop()) / 1000)
    return values


def run_stats(directory, variant):
    """汇总单轮：主 timeline 的帧指标与物理步耗时。"""
    summary = next((p for p in directory.glob("*.timeline_summary.json")
                    if "_reference_" not in p.name), None)
    timeline = next((p for p in directory.glob("*.timeline.json")
                     if "_reference_" not in p.name), None)
    if summary is None or timeline is None:
        return None
    data = load(summary)
    row = {name: data.get(key) for name, key in METRICS.items()}
    steps = physics_steps(timeline)
    row["physics_step_count"] = len(steps)
    if steps:
        steps.sort()
        row["physics_step_avg_ms"] = statistics.fmean(steps)
        row["physics_step_p99_ms"] = steps[min(len(steps) - 1, int(len(steps) * 0.99))]
        row["physics_step_max_ms"] = steps[-1]
    return row


def median_of(rows, key):
    """若全部轮次都有该指标则返回中位数，否则返回 None。"""
    values = [r[key] for r in rows if r.get(key) is not None]
    return statistics.median(values) if values else None


def main(root, out):
    """汇总所有有效轮并写出 JSON 与表格。"""
    runs = {r["variant"] + str(r["attempt"]): r
            for r in load(root / "runs.json")}
    result = {"variants": {}, "deltas": {}}
    for variant in {v for pair in PAIRS.values() for v in pair}:
        rows = []
        for key, record in runs.items():
            if record["variant"] != variant or not record["valid"]:
                continue
            row = run_stats(root / record["directory"], variant)
            if row is not None:
                rows.append(row)
        keys = sorted({k for r in rows for k in r})
        result["variants"][variant] = {
            "valid_runs": len(rows),
            "median": {k: median_of(rows, k) for k in keys},
            "runs": rows,
        }
    for name, (base, physics) in PAIRS.items():
        a = result["variants"][base]["median"]
        b = result["variants"][physics]["median"]
        result["deltas"][name] = {
            k: (b[k] - a[k]) for k in METRICS
            if a.get(k) is not None and b.get(k) is not None
            and k not in ("frame_count",)
        }
    out.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                   encoding="utf-8")
    header = ["variant", "runs", "ui_avg", "ui_p99", "raster_avg", "raster_p99",
              "step_avg", "step_p99", "step_max"]
    print(" | ".join(header))
    for variant, data in sorted(result["variants"].items()):
        m = data["median"]

        def f(k):
            return "-" if m.get(k) is None else f"{m[k]:.3f}"

        print(" | ".join([variant, str(data["valid_runs"]), f("ui_avg_ms"),
                          f("ui_p99_ms"), f("raster_avg_ms"), f("raster_p99_ms"),
                          f("physics_step_avg_ms"), f("physics_step_p99_ms"),
                          f("physics_step_max_ms")]))
    for name, delta in result["deltas"].items():
        print(name, {k: round(v, 3) for k, v in delta.items()})


if __name__ == "__main__":
    base = Path(sys.argv[1])
    main(base, Path(sys.argv[2]) if len(sys.argv) > 2 else base / "summary.json")
