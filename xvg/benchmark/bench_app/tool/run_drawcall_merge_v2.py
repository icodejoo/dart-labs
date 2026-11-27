"""Measure unsliced static SVG recording on paired APKs. / 在成对的 APK 上测量一次性静态 SVG 录制。"""

import argparse
import math
import random
from functools import partial
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows
from run_drawcall_isolated import (
    APP_DIR, DEVICE, REFRESH_HZ, ROUNDS, SEED, TraceLoss, capture, compare,
    run_experiment, trial_metrics, validate_round,
)
from summarize_drawcall_merge import frames_in, stage, window_metrics

PRIMARY = ("web-543", "web-544", "web-545", "web-150", "web-002", "web-541")
ICONS = ("mdi-0", "mdi-749")
ILLUSTRATION = "illustration-233kb"
TILED = "web-543-zoom"
TILE_WINDOW_MS = 6000


def make_plan(number, samples, variants):
    """Uses the same shuffled sample order for all variants in a round. / 每轮各版本共用一次打乱后的样本顺序。"""
    rng = random.Random(SEED + number)
    return {"round": number, "trials": 1,
            "samples": rng.sample(samples, len(samples)), "tile_window_ms": TILE_WINDOW_MS,
            "combinations": rng.sample(variants, len(variants))}


def snapshot_metrics(run, parsed, row):
    """Pairs original texture requests with the native snapshot slices by submission order. / 按提交顺序配对原始纹理请求和原生快照片段。"""
    sample = row["id"]
    starts = [request for request in row["requests"] if request[1]]
    finishes = [request for request in row["requests"] if not request[1]]
    events = [event for event in run["native_snapshots"]
              if starts and starts[0][0] <= event[0] <= row["times_us"]["window_end"]]
    if len(starts) != len(events) or len(starts) != len(finishes):
        last_submit = row["times_us"]["window_end"] - starts[-1][0] if starts else None
        raise TraceLoss(f"Native snapshot coverage {sample}: {len(events)}/{len(starts)}, "
                        f"last submission to window end {last_submit} us")
    if sample == TILED and len(starts) <= 1:
        raise TraceLoss("Zoomed case did not use tiled textures")
    tiles = []
    for start, finish, event in zip(starts, finishes, events, strict=True):
        if start[2:] != finish[2:] or start[0] > min(finish[0], event[0]):
            raise TraceLoss(f"Invalid snapshot submission order for {sample}")
        tiles.append({"size": start[2:], "native_us": event[1] - event[0]})
    return {**stage(parsed), **trial_metrics(run, row, events),
            "paths": parsed["paths"], "bytes": parsed["bytes"],
            "snapshot_count": len(tiles), "tiles": tiles}


def validate(run, plan):
    """Rejects incomplete trials and records the steady raster and icon scroll windows. / 拒收不完整试次并记录稳态和图标滚动窗口。"""
    validate_round(run, plan)
    for key in ("stages", "scenarios"):
        if [row["id"] for row in run[key]] != plan["samples"]:
            raise TraceLoss(f"Wrong sample order in {key}")
    metrics = {}
    for parsed, row in zip(run["stages"], run["scenarios"], strict=True):
        if len(parsed["recording_us"]) != 1 or len(row["recording_us"]) != 1:
            raise TraceLoss(f"Expected one recording for {row['id']}")
        if not math.isclose(row["hz"], REFRESH_HZ, abs_tol=0.25):
            raise TraceLoss(f"Expected {REFRESH_HZ} Hz, got {row['hz']}")
        metrics[row["id"]] = snapshot_metrics(run, parsed, row)
    scroll = run["icon_scroll"]
    frames = frames_in(run, scroll["start"], scroll["end"])
    if len(frames) < 5:
        raise TraceLoss("Incomplete icon scroll frame data")
    run["icon_scroll_metrics"] = {**window_metrics(frames, REFRESH_HZ),
                                  "frames": len(frames), "elapsed": scroll["end"] - scroll["start"]}
    return metrics


def pixel_diffs(runs, images):
    """Checks displayed premultiplied RGBA against C0 for every variant. / 以 C0 为基线逐版本比较显示图层的预乘 RGBA。"""
    result = {}
    for variant in runs:
        if variant == "C0":
            continue
        if runs["C0"]["pixel_sizes"] != runs[variant]["pixel_sizes"]:
            raise TraceLoss(f"Pixel sizes differ for {variant}")
        result[f"C0/{variant}"] = {
            sample: compare(pixels, images[variant][sample])
            for sample, pixels in images["C0"].items()
        }
    return result


def main():
    """Loads verified build paths and the runtime-only illustration. / 读取待核验构建与仅在运行时使用的插画。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--output", type=Path, default=APP_DIR.parent / "raster_cache_auto_merge_v2_raw.json")
    parser.add_argument("--rounds", type=int, choices=range(1, ROUNDS + 1), default=ROUNDS)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--illustration", type=Path, required=True)
    parser.add_argument("--extra", nargs=3, required=True)
    parser.add_argument("--build", nargs=3, action="append", metavar=("VARIANT", "APK", "SO"), required=True)
    args = parser.parse_args()
    artifacts = {name: (Path(apk), Path(so)) for name, apk, so in args.build}
    if len(artifacts) != len(args.build) or not {"C0", "C1"} <= artifacts.keys():
        parser.error("Provide C0, C1 and distinct C2 builds")
    corpus_ids = tuple(dict.fromkeys((*PRIMARY, *args.extra)))
    inputs = {row["id"]: args.corpus / "files" / row["file"]
              for row in manifest_rows(args.corpus) if row["id"] in corpus_ids}
    inputs[ILLUSTRATION] = args.illustration
    if len(inputs) != len(corpus_ids) + 1 or any(not path.is_file() for path in inputs.values()):
        parser.error("Missing runtime input")
    samples = (*corpus_ids, ILLUSTRATION, *ICONS, TILED)
    planner = partial(make_plan, samples=samples, variants=tuple(artifacts))
    run_experiment(args, artifacts, inputs, planner, pixel_diffs,
                   partial(capture, validator=validate), lambda _: {"displayed_pixels": True})


if __name__ == "__main__":
    main()
