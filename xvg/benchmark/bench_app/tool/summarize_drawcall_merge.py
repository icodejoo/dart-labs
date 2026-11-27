"""Summarize paired corpus and Android runs. / 汇总配对的主机语料及 Android 真机数据。"""

import argparse
import json
import math
import statistics
from pathlib import Path

from run_drawcall_merge import SAMPLES

VERSIONS = ("old", "new")
FACTORS = (0.50, 0.90, 0.95, 0.99, 1.0)
FIELDS = ("paths", "commands", "wire_commands", "bytes", "native_us", "decode_us")
ROUTE_TRANSITION_US = 450_000
LABELS = {"legacy-014": "233KB 插画"}


def nearest(values, quantile):
    """Returns a non-interpolated percentile. / 返回最近秩分位数。"""
    return sorted(values)[max(0, math.ceil(len(values) * quantile) - 1)] if values else None


def corpus_rows(directory):
    """Loads all three DLL attempts for each asset. / 读取每张语料在两个 DLL 上的三次执行。"""
    return {
        version: {
            row["id"]: row["samples"]
            for row in map(json.loads, (directory / f"corpus-{version}.jsonl").open())
        }
        for version in VERSIONS
    }


def collect_med(values):
    """Takes a median over available measurements. / 对有效测量取中位数。"""
    return statistics.median(selected) if (selected := [v for v in values if v is not None]) else None


def frames_in(run, start, end):
    """Selects frames that begin in a monotonic window. / 选择单调时钟窗口内开始的帧。"""
    phases = {key: index for index, key in enumerate(run["frame_phases"])}
    frames = [[frame[phases[key]] for key in (
        "vsyncStart", "buildStart", "buildFinish", "rasterStart", "rasterFinish", "frameNumber"
    )] for frame in run["frames"]]
    return [frame for frame in frames if start <= frame[0] <= end]


def window_metrics(frames, hz):
    """Computes frame duration percentiles and skipped vsync slots. / 计算帧耗时分位数及错过的 vsync 节拍。"""
    period = 1_000_000 / hz
    return {
        "ui_p95": nearest([f[2] - f[1] for f in frames], .95),
        "ui_max": max((f[2] - f[1] for f in frames), default=None),
        "raster_p95": nearest([f[4] - f[3] for f in frames], .95),
        "raster_max": max((f[4] - f[3] for f in frames), default=None),
        "drops": sum(max(0, round((b[0] - a[0]) / period) - 1) for a, b in zip(frames, frames[1:])),
    }


def stage(row):
    """Collects active recording time and SSE decode time. / 汇总有效录制时间及 SSE 解码时间。"""
    times = row["times_us"]
    return {
        "decode": times["decode_done"] - times["decode"],
        "record_total": sum(row["recording_us"]),
        "record_max": max(row["recording_us"]),
        "record_slices": len(row["recording_us"]),
    }


def scenario(run, row):
    """Joins first-art and native snapshot timings to frames. / 将首个图稿及原生快照与帧时间关联。"""
    times = row["times_us"]
    mount, end = times["mount"], times["window_end"]
    first, = (frame for frame in frames_in(run, 0, float("inf"))
              if frame[5] == times["first_art_frame"])
    # Include the prior slot or the exact first-art frame if its vsync preceded mount.
    # 保留前一个节拍，并用精确帧编号找到早于数据到达时间的首个图稿帧。
    start = min(first[0], mount - round(1_000_000 / row["hz"]))
    frames = frames_in(run, start, end)
    starts = [r[0] for r in row["requests"] if r[1]]
    snapshots = [s for s in run["native_snapshots"]
                 if starts and min(starts) <= s[0] <= end]
    first_complete = first[4]
    first_tiles = [s for s in snapshots if s[0] <= first[4]]
    if first_tiles:
        first_complete = max(first_complete, max(tile[1] for tile in first_tiles))
    stable = max([first_complete, *[s[1] for s in snapshots]]) + 50_000
    return {
        **window_metrics(frames, row["hz"]),
        "display": first_complete - mount,
        "startup_drops": window_metrics([f for f in frames if f[0] <= first[0]], row["hz"])["drops"],
        "steady_raster": nearest([f[4] - f[3] for f in frames if f[0] >= stable], .50),
        "snap_peak": max((s[1] - s[0] for s in snapshots), default=None),
    }


def route(run, row):
    """Measures the active Android transition, excluding the idle target page. / 测量 Android 路由过渡，排除目标页空闲期。"""
    start = row["times_us"]["mount"]
    period = round(1_000_000 / row["hz"])
    return window_metrics(frames_in(run, start - period, start + ROUTE_TRANSITION_US),
                          row["hz"])


def medians(rows):
    """Reduces each reported metric independently across rounds. / 对各指标分别取三轮中位数。"""
    return {key: collect_med(row[key] for row in rows) for key in rows[0]}


def pair(rows, key, timing=True):
    """Formats baseline and new points in the same table cell. / 在同一单元格呈现基线和新版。"""
    def value(number):
        if number is None:
            return "—"
        return f"{number / 1000:.2f}" if timing else f"{number:,.0f}"
    return " → ".join(value(rows[version][key]) for version in VERSIONS)


def print_corpus(raw):
    """Prints corpus totals, quantiles and the twenty largest path reductions. / 输出语料总量、分位数及路径减少最多的二十张。"""
    ids = [id for id in raw["old"] if all(
        id in raw[version] and len(raw[version][id]) == 3
        and all("paths" in sample for sample in raw[version][id]) for version in VERSIONS
    )]
    by_version = {
        version: {id: medians(raw[version][id]) for id in ids} for version in VERSIONS
    }
    old, new = (by_version[version] for version in VERSIONS)
    reduced = sorted(ids, key=lambda id: (old[id]["paths"] - new[id]["paths"], old[id]["paths"]),
                     reverse=True)
    print(f"两版均解析成功 {len(ids)} / {len(raw['old'])} 张，"
          f"{sum(old[id]['paths'] > new[id]['paths'] for id in ids)} 张减少路径。\n")
    print("| 指标 | 总量 | p50 | p90 | p95 | p99 | 最大 |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for key in FIELDS:
        cell = {}
        for version in VERSIONS:
            values = [row[key] for row in by_version[version].values()]
            cell[version] = dict(zip(("total", *FACTORS), (sum(values), *(nearest(values, q) for q in FACTORS))))
        print(f"| {key} | " + " | ".join(pair(cell, q, key.endswith("_us")) for q in ("total", *FACTORS)) + " |")
    print("\n| 样本 | 路径 | 有效命令 | SSE 字节 | 原生调用 ms |")
    print("|---|---:|---:|---:|---:|")
    for id in reduced[:20]:
        row = {"old": old[id], "new": new[id]}
        print(f"| {id} | " + " | ".join(pair(row, k, k.endswith("_us"))
              for k in ("paths", "commands", "bytes", "native_us")) + " |")


def print_phone(data):
    """Prints device stage, frame, and RGBA comparisons. / 输出真机分段、帧时间及 RGBA 对照。"""
    runs = {v: [r for r in data["rounds"] if r["version"] == v] for v in VERSIONS}
    if any(len(runs[v]) != 3 for v in VERSIONS):
        raise RuntimeError(f"Runs are incomplete: {[len(runs[v]) for v in VERSIONS]}")
    print("\n| 样本 | ②a 解码 | ②b 总量 | ②b 单帧最大 | 切片数 | ③ 原生快照峰值 | 稳态 raster p50 |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    scenarios = {}
    for sample in SAMPLES:
        scenarios[sample] = {}
        staged = {}
        for version in VERSIONS:
            staged[version] = medians([stage(row) for run in runs[version] for row in run["stages"]
                                       if row["id"] == sample])
            scenarios[sample][version] = medians([scenario(run, row) for run in runs[version]
                                                  for row in run["scenarios"] if row["id"] == sample])
        metrics = [pair(staged, k, k != "record_slices")
                   for k in ("decode", "record_total", "record_max", "record_slices")]
        metrics += [pair(scenarios[sample], k) for k in ("snap_peak", "steady_raster")]
        print(f"| {LABELS.get(sample, sample)} | " + " | ".join(metrics) + " |")
    print("\n| 样本 | 转圈 UI p95 / 峰值 | 转圈 raster p95 / 峰值 | 首图前漏 vsync | 完整显示 ms | 跳转漏 vsync |")
    print("|---|---:|---:|---:|---:|---:|")
    for sample in SAMPLES:
        jumps = {v: medians([route(run, row) for run in runs[v] for row in run["jumps"]
                             if row["id"] == sample]) for v in VERSIONS}
        rows = scenarios[sample]
        print(f"| {LABELS.get(sample, sample)} | {pair(rows, 'ui_p95')} / {pair(rows, 'ui_max')} | "
              f"{pair(rows, 'raster_p95')} / {pair(rows, 'raster_max')} | {pair(rows, 'startup_drops', False)} | "
              f"{pair(rows, 'display')} | {pair(jumps, 'drops', False)} |")
    scroll = {v: medians([window_metrics(frames_in(run, run["icon_scroll"]["start"],
                   run["icon_scroll"]["end"]), run["scenarios"][0]["hz"]) for run in runs[v]])
              for v in VERSIONS}
    print("\n千图标滚动 UI p95 " + pair(scroll, "ui_p95") + " ms，raster p95 "
          + pair(scroll, "raster_p95") + " ms，漏 vsync " + pair(scroll, "drops", False) + "。")
    print("\n| 样本 | 变化像素数 / 总像素 | 最大通道差 |")
    print("|---|---:|---:|")
    for sample in SAMPLES:
        rows = [r["samples"][sample] for r in data["pixel_diffs"]]
        print(f"| {LABELS.get(sample, sample)} | {collect_med(r['changed'] for r in rows):,} / {rows[0]['pixels']:,} | "
              f"{max(r['max_channel_delta'] for r in rows)} |")


def main():
    """Prints Markdown tables and optionally attaches corpus data to the raw report. / 输出 Markdown 表格并可把语料数据附入原始报告。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--scratch", type=Path, default=Path(".dart_tool/drawcall"))
    parser.add_argument("--raw", type=Path, default=Path("../raster_cache_auto_drawcall_raw.json"))
    parser.add_argument("--attach-corpus", action="store_true")
    args = parser.parse_args()
    corpus = corpus_rows(args.scratch)
    print_corpus(corpus)
    if args.raw.is_file():
        data = json.loads(args.raw.read_text(encoding="utf-8"))
        if args.attach_corpus:
            data["corpus"] = corpus
            args.raw.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        print_phone(data)


if __name__ == "__main__":
    main()
