"""Summarize UI-stage runs from raw timestamps. / 用原始时间戳汇总 UI 阶段测量。"""

import argparse
import bisect
import json
import math
import statistics
from collections import defaultdict
from pathlib import Path

MIB = 1024 ** 2
FRAME_120_US = 1_000_000 / 120
AFTER_ART = 4
BASELINE_US = 140_000
LABELS = {"legacy-014": "233KB 插画"}


def trial_stages(row):
    """Calculate disjoint decode and recording times in microseconds. / 计算互不重叠的解码、录制微秒数。"""
    ts = row["times_us"]
    decode = ts["decode_done"] - ts["decode"]
    record = ts["record_done"] - ts["record"]
    return {
        "dispatch": ts["call_return"] - ts["call"],
        "worker": ts.get("message", ts["decode"]) - ts["call"],
        "decode": decode, "record": record, "ui": decode + record,
        "decode_to_record": ts["record"] - ts["decode_done"],
    }


def gaps(stamps):
    """Read gaps between adjacent reported frame slots. / 读取相邻报告帧时隙的间隔。"""
    return [b - a for a, b in zip(stamps, stamps[1:])]


def slots_missed(stamps, period):
    """Estimate unreported slots from gaps at observed spinner cadence. / 用已观测的转圈节奏估算没有 FrameTiming 的时隙。"""
    return sum(max(0, math.floor(gap / period + 0.5) - 1) for gap in gaps(stamps))


def trial_frames(row, frames, phases):
    """Find the result window and four submitted frames after artwork appears. / 定位结果窗及首显后提交的四帧。"""
    vsync, build, built, raster, rastered, frame_number = (phases.index(name) for name in (
        "vsyncStart", "buildStart", "buildFinish", "rasterStart", "rasterFinish", "frameNumber"))
    stamps = [frame[vsync] for frame in frames]
    ts = row["times_us"]
    event = ts["decode"] if row["dispatch"] == "worker" else ts["call"]
    first_art = next((i for i, frame in enumerate(frames)
                      if frame[frame_number] == ts["first_art_frame"]), None)
    if first_art is None:
        raise ValueError(f"Missing first art frame for {row['id']}")
    start = min(first_art - 1, bisect.bisect_left(stamps, event) - 1)
    end = min(first_art + AFTER_ART + 1, bisect.bisect_right(stamps, ts["window_end"]))
    baseline = stamps[bisect.bisect_left(stamps, ts["mount"] - BASELINE_US)
                      :bisect.bisect_left(stamps, ts["mount"])]
    if not 0 <= start < first_art < end or len(baseline) < 3:
        raise ValueError(f"Incomplete spinner window for {row['id']}")
    period = statistics.median(gaps(baseline))
    window = frames[start:end]
    art = frames[first_art]
    return {
        "period": period,
        "frames": len(window),
        "build": max(frame[built] - frame[build] for frame in window),
        "raster": max(frame[rastered] - frame[raster] for frame in window),
        "vsync_wait": max(frame[build] - frame[vsync] for frame in window),
        "first_art_build": art[built] - art[build],
        "first_art_raster": art[rastered] - art[raster],
        "art_late_slots": max(0, math.floor((art[built] - art[vsync]) / period)),
        "missed_window": slots_missed(stamps[start:end], period),
        "result_to_art": art[built] - event,
        "ui": trial_stages(row)["ui"],
    }


def summarize(data):
    """Discard the first repeat per sample and round and validate scene counts. / 每图每轮剔除首测，并核对场景计数。"""
    stages = defaultdict(list)
    scenarios = defaultdict(list)
    features = {}
    dispatch = defaultdict(set)
    for batch in data["rounds"]:
        phases = batch["frame_phases"]
        frames = sorted(batch["frames"], key=lambda frame: frame[phases.index("vsyncStart")])
        for key in ("stages", "scenarios"):
            for row in batch[key]:
                sample = row["id"]
                props = tuple(row[name] for name in ("units", "bytes", "paths", "commands", "images"))
                if features.setdefault(sample, props) != props:
                    raise ValueError(f"Scene counters changed for {sample}")
                if row["trial"] == 1:
                    continue
                if key == "stages":
                    stages[sample].append(trial_stages(row))
                else:
                    dispatch[sample].add(row["dispatch"])
                    scenarios[sample].append(trial_frames(row, frames, phases))
    return features, stages, scenarios, dispatch


def pair(rows, key, scale=1000, precision=2):
    """Render median and maximum of retained trials. / 格式化保留试次的中位数和最大值。"""
    values = [row[key] / scale for row in rows]
    return f"{statistics.median(values):.{precision}f} / {max(values):.{precision}f}"


def fit_rows(features, stages, samples):
    """Fit the median stage time to path count and wire size separately. / 按路径数和 wire 大小分别拟合分段中位数。"""
    for name in ("decode", "record", "ui"):
        times_ms = [statistics.median(row[name] for row in stages[sample]) / 1000 for sample in samples]
        inputs = ([features[sample][2] / 1000 for sample in samples],
                  [features[sample][1] / MIB for sample in samples])
        for unit, values in zip(("千路径", "MiB"), inputs):
            slope, intercept = statistics.linear_regression(values, times_ms)
            yield name, unit, slope, intercept, statistics.correlation(values, times_ms) ** 2


def tables(data):
    """Produce Markdown tables and descriptive fit diagnostics. / 输出 Markdown 测量表与拟合诊断。"""
    features, stages, scenes, dispatch = summarize(data)
    samples = [sample for group in data["groups"].values() for sample in group]
    yield "| 样本 | 路径 | 显式命令 | SSE 字节 | ① Worker 往返上界 | ②a Dart 解码 | ②b 录制 | ② 合计 |"
    yield "|---|---:|---:|---:|---:|---:|---:|---:|"
    for sample in samples:
        _, size, paths, commands, _ = features[sample]
        row = [LABELS.get(sample, sample), f"{paths:,}", f"{commands:,}", f"{size:,}"]
        row.extend(pair(stages[sample], key) for key in ("worker", "decode", "record", "ui"))
        yield "| " + " | ".join(row) + " |"
    yield ""
    yield "| 样本 | 派发 | ② 合计 | Build 峰值 | Raster 峰值 | vsync 等待峰值 | 结果到首显提交 | 首显逾期帧 | 全窗漏帧 |"
    yield "|---|---|---:|---:|---:|---:|---:|---:|---:|"
    for sample in samples:
        label = LABELS.get(sample, sample)
        row = [label, "/".join(sorted(dispatch[sample]))]
        row.extend(pair(scenes[sample], key) for key in ("ui", "build", "raster", "vsync_wait", "result_to_art"))
        row.extend(pair(scenes[sample], key, 1, 1) for key in ("art_late_slots", "missed_window"))
        yield "| " + " | ".join(row) + " |"
    yield ""
    yield "| 时间 | 自变量 | 斜率（ms / 单位） | 截距（ms） | R² |"
    yield "|---|---|---:|---:|---:|"
    for name, unit, slope, intercept, r2 in fit_rows(features, stages, samples):
        yield f"| {name} | {unit} | {slope:.2f} | {intercept:.2f} | {r2:.3f} |"


def main():
    """Read the raw JSON and print the report tables. / 读取原始 JSON 并输出报告表格。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("raw", type=Path)
    args = parser.parse_args()
    data = json.loads(args.raw.read_text(encoding="utf-8"))
    print("\n".join(tables(data)))


if __name__ == "__main__":
    main()
