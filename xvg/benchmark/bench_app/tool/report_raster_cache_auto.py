"""校验并汇总自动位图缓存基准的逐帧数据。"""

import argparse
import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path

# 表中按以下顺序列出以免遗漏原生场景特征。
FEATURES = (
    "paths", "verbs", "points", "strokes", "gradients",
    "opacity", "clips", "masks", "blurs", "images",
)
MODES = ("baseline", "vector", "cached")
ROUNDS = (1, 2, 3)
SIZES = ("16", "48", "200", "full")
SAMPLE_COUNT = 38
CASE_COUNT = 120
CLIP_SAMPLES = {"mdi-0", "aurora", "233KB", "synthetic-5000-layers-grad",
                "synthetic-20000-layers-grad"}
CLIP_CASE_COUNT = 18
MIN_FRAMES = 18
BENEFIT_US = 1000
MIN_AREA = 131_072
COVERED_POINT_THRESHOLD = 10_000
BLUR_AREA_THRESHOLD = 32_000_000
PARTIAL_POINT_THRESHOLD = 100_000
PARTIAL_AREA_THRESHOLD = 1_000_000
SCREEN_HEIGHT_PX = 2340
CASE_FIELDS = (
    "sample", "size", "validation", "width_dp", "height_dp", "area_px",
    "visible_px", "dpr", *FEATURES,
)
RAW_FIELDS = set(CASE_FIELDS) | {
    "round", "mode", "display_hz", "p50_us", "p95_us", "raster_us", "fps",
    "bytes", "tiles", "generation_us", "first_output_us", "preparation_raster_us",
}


def check(condition, message):
    """校验失败时指出对应的样本、轮次及模式。"""
    if not condition:
        raise ValueError(message)


def read_session(directory, *, clip=False):
    """读取和验证一次完整测试的三轮输出。"""
    metadata = []
    runs = []
    for number in ROUNDS:
        stem = directory / f"round-{number}"
        with Path(f"{stem}-frames.jsonl").open(encoding="utf-8-sig") as source:
            records = [json.loads(line) for line in source if line.strip()]
        check(all(run["round"] == number for run in records), f"round {number}")
        runs.extend(records)
        with Path(f"{stem}-thermal.csv").open(encoding="utf-8-sig", newline="") as source:
            thermal = [
                [int(row["elapsed_s"]), int(row["thermal_status"])]
                for row in csv.DictReader(source)
            ]
        backend = Path(f"{stem}-backend.txt").read_text(encoding="utf-8-sig")
        check("backend (Vulkan)" in backend and thermal, f"device log {number}")
        metadata.append({"round": number, "backend": "Impeller Vulkan", "thermal": thermal})
    aggregate(runs, clip=clip)
    return metadata, runs


def pack(directory, output, clip_directory):
    """合并逐轮设备输出和热状态，并保存可逐帧复算的 JSON。"""
    metadata, runs = read_session(directory)
    result = {"rounds": metadata, "runs": runs}
    if clip_directory is not None:
        clip_metadata, clip_runs = read_session(clip_directory, clip=True)
        result.update(clip_rounds=clip_metadata, clip_runs=clip_runs)
    with output.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("{")
        for index, (key, rows) in enumerate(result.items()):
            if index:
                handle.write(",")
            handle.write(f'"{key}":[\n')
            handle.write(",\n".join(json.dumps(row, separators=(",", ":")) for row in rows))
            handle.write("\n]")
        handle.write("}\n")


def aggregate(runs, *, clip=False):
    """验证完整矩阵及原始分位数，再返回样本和尺寸的三轮中位数。"""
    grouped = defaultdict(dict)
    for row in runs:
        check(set(row) == RAW_FIELDS, "unexpected raw fields")
        case = row["sample"], row["size"]
        key = row["round"], row["mode"]
        label = (case, key)
        check(key not in grouped[case], f"duplicate {label}")
        raster = sorted(row["raster_us"])
        check(len(raster) >= MIN_FRAMES and raster[0] >= 0, f"raster samples {label}")
        check(row["p50_us"] == raster[(len(raster) - 1) // 2], f"p50 {label}")
        check(row["p95_us"] == raster[(len(raster) * 95 + 99) // 100 - 1], f"p95 {label}")
        check(0 < row["fps"] <= row["display_hz"] * 1.1, f"frame rate {label}")
        check(0 < row["visible_px"] <= row["area_px"], f"area {label}")
        if row["mode"] == "cached":
            check(
                row["bytes"] > 0 and row["tiles"] > 0
                and row["generation_us"] >= row["first_output_us"] > 0
                and row["preparation_raster_us"],
                f"cache residency or readiness {label}",
            )
        else:
            check(
                row["bytes"] == row["tiles"] == 0
                and row["generation_us"] is None and row["first_output_us"] is None,
                f"non-cache residency {label}",
            )
        grouped[case][key] = row
    samples = defaultdict(set)
    cases = []
    for (sample, size), rows in grouped.items():
        check(set(rows) == {(number, mode) for number in ROUNDS for mode in MODES},
              f"missing repetition {(sample, size)}")
        samples[sample].add(size)
        case = {key: rows[1, "vector"][key] for key in CASE_FIELDS}
        check(all(row[key] == case[key] for row in rows.values() for key in CASE_FIELDS),
              f"inconsistent dimensions or features {(sample, size)}")
        for mode in MODES:
            case[mode] = statistics.median(rows[number, mode]["p50_us"] for number in ROUNDS)
        case["benefit"] = case["vector"] - case["cached"]
        case["paired_gains"] = [
            rows[number, "vector"]["p50_us"] - rows[number, "cached"]["p50_us"]
            for number in ROUNDS
        ]
        for key in ("bytes", "tiles", "generation_us"):
            case[key] = statistics.median(rows[number, "cached"][key] for number in ROUNDS)
        cases.append(case)
    if clip:
        check(set(samples) == CLIP_SAMPLES and len(cases) == CLIP_CASE_COUNT, "clip matrix")
    else:
        check(len(samples) == SAMPLE_COUNT and len(cases) == CASE_COUNT, "sample matrix")
    check(all({"48", "200", "full"} <= sizes <= set(SIZES) for sizes in samples.values()),
          "size coverage")
    return sorted(cases, key=lambda case: (case["sample"], SIZES.index(case["size"])))


def print_table(cases):
    """输出带完整结构计数及稳态、准备数据的 Markdown 表。"""
    columns = [
        "样本", "组", "档", "宽 × 高 dp", "完整 px²", "在屏 px²",
        "路径", "动词", "点", "描边", "渐变", "透明", "裁剪", "遮罩", "模糊", "图片",
        "基线 ms", "向量 ms", "缓存 ms", "净收益 ms", "纹理 B", "齐备 ms",
    ]
    print("| " + " | ".join(columns) + " |")
    print("| " + " | ".join(["---"] * 4 + ["---:"] * (len(columns) - 4)) + " |")
    for case in cases:
        values = [
            "233KB 插画" if case["sample"] == "233KB" else case["sample"],
            "验证" if case["validation"] else "拟合",
            case["size"],
            f"{case['width_dp']:.0f} × {case['height_dp']:.1f}",
            f"{case['area_px']:,}",
            f"{case['visible_px']:,}",
            *(str(case[key]) for key in FEATURES),
            *(f"{case[key] / 1000:.3f}" for key in (*MODES, "benefit")),
            f"{case['bytes']:,}",
            f"{case['generation_us'] / 1000:.2f}",
        ]
        print("| " + " | ".join(values) + " |")


def recommend(case, *, clip=False):
    """用基准几何复算报告中的静态资格，重放条件在稳态窗口中已满足。"""
    area = case["visible_px"]
    if area < MIN_AREA:
        return False
    # 主场景贴左上。贴边对照中的有效裁剪由额外的 ClipRect 提供。
    spans_width = case["size"] == "full"
    covers_clip = clip or (spans_width and case["height_dp"] * case["dpr"] >= SCREEN_HEIGHT_PX)
    if covers_clip:
        return (case["points"] >= COVERED_POINT_THRESHOLD
                or case["blurs"] * area >= BLUR_AREA_THRESHOLD)
    return (spans_width and area >= PARTIAL_AREA_THRESHOLD
            and case["points"] >= PARTIAL_POINT_THRESHOLD
            and (case["blurs"] == 0 or case["clips"] > 0))


def print_evaluation(cases, *, clip=False):
    """按拟合和留出分别列出命中、误开、微利启用及漏开。"""
    for name, validation in (("fit", False), ("validation", True)):
        partition = [case for case in cases if case["validation"] == validation]
        outcomes = defaultdict(list)
        for case in partition:
            benefit = case["benefit"]
            if recommend(case, clip=clip):
                outcome = (
                    "hit" if benefit > BENEFIT_US else "false_open" if benefit <= 0 else "weak_open"
                )
            else:
                outcome = "miss" if benefit > BENEFIT_US else "closed"
            outcomes[outcome].append(case)
        print(name, len(partition), "cases")
        for outcome in ("hit", "false_open", "weak_open", "miss", "closed"):
            matches = outcomes[outcome]
            print(outcome, len(matches))
            if outcome != "closed":
                for case in matches:
                    print(" ", case["sample"], case["size"], case["benefit"], case["paired_gains"])


def main():
    """提供原始数据打包和分组表格重算入口。"""
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    pack_command = commands.add_parser("pack")
    pack_command.add_argument("directory", type=Path)
    pack_command.add_argument("output", type=Path)
    pack_command.add_argument("--clip-directory", type=Path)
    table_command = commands.add_parser("table")
    table_command.add_argument("data", type=Path)
    table_command.add_argument("--partition", choices=("fit", "validation", "all"), default="all")
    table_command.add_argument("--clip", action="store_true")
    evaluate_command = commands.add_parser("evaluate")
    evaluate_command.add_argument("data", type=Path)
    evaluate_command.add_argument("--clip", action="store_true")
    args = parser.parse_args()
    if args.command == "pack":
        pack(args.directory, args.output, args.clip_directory)
    else:
        data = json.loads(args.data.read_text(encoding="utf-8"))
        cases = aggregate(data["clip_runs" if args.clip else "runs"], clip=args.clip)
        if args.command == "evaluate":
            print_evaluation(cases, clip=args.clip)
        else:
            if args.partition != "all":
                cases = [case for case in cases if case["validation"] == (args.partition == "validation")]
            print_table(cases)


if __name__ == "__main__":
    main()
