"""分析 PERF 原始帧时、配对 timeline 和 RSS；不更改指标、预算或有效轮数。"""

import argparse
import collections
import gzip
import json
import statistics
from pathlib import Path


SCENES = {
    "wheel_steady": "wheel_default",
    "number_wheel_spin": "number_wheel_spin",
    "capsule_mixing": "capsule_mixing",
    "lotto_draw": "lotto_draw",
    "grid_steady": "grid_steady",
}
METRICS = {
    "Raster平均 ms": "average_frame_rasterizer_time_millis",
    "Raster p90 ms": "90th_percentile_frame_rasterizer_time_millis",
    "Raster p99 ms": "99th_percentile_frame_rasterizer_time_millis",
    "掉帧率 %": "dropped_frame_ratio",
    "UI平均 ms": "average_frame_build_time_millis",
    "UI p90 ms": "90th_percentile_frame_build_time_millis",
    "UI p99 ms": "99th_percentile_frame_build_time_millis",
    "RSS页面峰值 MiB": "rss_delta_bytes",
    "RSS五次增长 MiB": "rss_growth_5_cycles_bytes",
    "RSS稳态窗口增量 MiB": "rss_steady_delta_bytes",
}
EVENTS = (
    "Rasterizer::DoDraw", "SurfaceFrame::Encode",
    "RenderPassGLES::EncodeCommandsInReactor", "Animator::BeginFrame",
    "LAYOUT", "BUILD", "PAINT", "COMPOSITING", "SEMANTICS",
    "CreateGlyphAtlas", "luckdraw.layout", "luckdraw.record",
)


def read(path):
    """兼容已归档 gzip 和原始 UTF-8 JSON。"""
    path = Path(path)
    data = gzip.decompress(path.read_bytes()) if path.suffix == ".gz" else path.read_bytes()
    return json.loads(data.decode("utf-8-sig"))


def timeline(path):
    """按进程和线程配对 B/E；嵌套事件均为含子事件的耗时，不能相加。"""
    if not path.exists():
        path = path.with_suffix(path.suffix + ".gz")
    stacks = collections.defaultdict(list)
    values = collections.defaultdict(list)
    for event in read(path)["traceEvents"]:
        thread = event.get("pid"), event.get("tid")
        phase = event.get("ph")
        if phase == "B":
            stacks[thread].append(event)
        elif phase == "E" and stacks[thread]:
            opening = stacks[thread].pop()
            duration = event["ts"] - opening["ts"]
            if duration >= 0:
                values[opening.get("name")].append(duration / 1000)
        elif phase == "X":
            values[event.get("name")].append(event.get("dur", 0) / 1000)
    return {name: {"count": len(values[name]), "mean_ms": statistics.mean(values[name]),
                   "max_ms": max(values[name])}
            for name in EVENTS if values.get(name)}


def summaries(root, records=None):
    """只读取有效轮，拒绝锁屏、无帧和重复身份；保留每轮原文件路径。"""
    root = Path(root)
    records = read(root / "runs.json") if records is None else records
    result = collections.defaultdict(list)
    seen = set()
    for record in records:
        if not record["valid"]:
            continue
        if record["exitCode"] != 0 or record.get("lockedDuring") or not record["unlockedBefore"]:
            raise ValueError("有效轮与运行状态矛盾")
        for path in (root / record["directory"]).glob("*.timeline_summary.json"):
            data = read(path)
            if data["report_key"] in ("reference_spin", "wheel_first_frame"):
                continue
            identity = data["report_key"], data["run_id"]
            if identity in seen:
                raise ValueError("重复 run_id")
            seen.add(identity)
            if data["report_key"] != "memory_cycles" and data["frame_count"] <= 0:
                raise ValueError("零帧数据")
            if data["device_serial"] != "10AE9K17UE0011S" or data["rss_cycles"] != 5:
                raise ValueError("设备或 RSS 次数不一致")
            if len(data["rss_pages"]) != 5 or len(data["rss_blank"]) != 5:
                raise ValueError("RSS 缺样")
            data["source"] = path.as_posix()
            data["variant"] = record.get("variant", record.get("target"))
            result[data["report_key"]].append(data)
    return dict(result)


def converted(data, key):
    """仅转换显示单位，保留原始指标定义和负增长。"""
    value = data[key]
    if key.endswith("bytes"):
        return value / 1048576
    if key == "dropped_frame_ratio":
        return value * 100
    return value


def main():
    """输出每轮值、中位数、极差、timeline 证据和 RSS 热身诊断。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", default="results/bench_20261110_180650")
    parser.add_argument("--after", default="results/perf_after")
    parser.add_argument("--ablation", default="results/perf_ablation")
    args = parser.parse_args()
    before, after, ablation = (summaries(path) for path in (args.before, args.after, args.ablation))
    output = {"device": "vivo V2417", "serial": "10AE9K17UE0011S", "scenes": {}, "ablation": [], "rss": []}
    lines = ["场景 | 指标 | DEV 三轮原值 | PERF 三轮原值 | DEV 中位数 | PERF 中位数 | PERF 极差 | 极差/中位数", "--- | --- | --- | --- | --- | --- | --- | ---"]
    evidence = {}
    for scene, variant in SCENES.items():
        old = before[scene]
        new = [data for data in after.get(scene, []) if data["variant"] == variant]
        if len(old) != 3 or len(new) != 3:
            raise ValueError(f"{scene} 有效轮不是三次：{len(old)}/{len(new)}")
        output["scenes"][scene] = {"before": old, "after": new, "metrics": {}}
        for label, key in METRICS.items():
            old_values = [converted(data, key) for data in old]
            new_values = [converted(data, key) for data in new]
            med = statistics.median(new_values)
            spread = max(new_values) - min(new_values)
            ratio = spread / med if med else (0 if spread == 0 else None)
            output["scenes"][scene]["metrics"][key] = {
                "before_values": old_values, "after_values": new_values,
                "before_median": statistics.median(old_values), "after_median": med,
                "after_range": spread, "spread_over_median": ratio,
            }
            joined_old = " / ".join(f"{value:.3f}" for value in old_values)
            joined_new = " / ".join(f"{value:.3f}" for value in new_values)
            relative = "未定义" if ratio is None else f"{ratio:.1%}"
            lines.append(f"{scene} | {label} | {joined_old} | {joined_new} | {statistics.median(old_values):.3f} | {med:.3f} | {spread:.3f} | {relative}")
        for label, group in (("before", old), ("after", new)):
            for data in group:
                source = Path(data["source"])
                path = source.with_name(source.name.replace(".timeline_summary.json", ".timeline.json"))
                evidence[f"{scene}/{label}/{data['run_id']}"] = timeline(path)
    for data in ablation.get("wheel_steady", []):
        output["ablation"].append(data)
        path = Path(data["source"])
        evidence[f"ablation/{data['variant']}/{data['run_id']}"] = timeline(path.with_name(path.name.replace(".timeline_summary.json", ".timeline.json")))
    for data in before["memory_cycles"]:
        values = data["rss_blank"]
        output["rss"].append({
            "source": data["source"], "baseline": data["rss_baseline"], "blank": values,
            "warmup_bytes": values[0] - data["rss_baseline"],
            "steady_net_bytes": values[-1] - values[0],
            "steady_steps_bytes": [values[i] - values[i - 1] for i in range(1, 5)],
        })
    directory = Path(args.after)
    (directory / "analysis.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (directory / "timeline_evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    (directory / "comparison.md").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"PASS: {len(SCENES)} scenes x 3 valid rounds; {len(evidence)} timeline files; budgets unchanged")


if __name__ == "__main__":
    main()
