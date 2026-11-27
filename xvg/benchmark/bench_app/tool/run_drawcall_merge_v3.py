"""Measure two whole-image snapshots per build on Android. / 在 Android 上为每档测两张图的整图快照。"""

import argparse
from functools import partial
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows
from run_drawcall_isolated import APP_DIR, DEVICE, TraceLoss, capture, run_experiment, validate_round
from run_drawcall_merge_v2 import pixel_diffs

SAMPLES = ("web-543", "web-481")
VARIANTS = ("C0", "128x128", "512x1024", "1024x1024")
ROUNDS = 2


def make_plan(number):
    """Reverses both orders in round two. / 第二轮将档位和样本顺序都倒过来。"""
    order = 1 if number == 1 else -1
    return {"round": number, "trials": 1, "samples": list(SAMPLES[::order]),
            "combinations": list(VARIANTS[::order])}


def validate(run, plan):
    """Pairs each whole-image request with its native snapshot slice. / 将每张整图请求与原生快照片段配对。"""
    validate_round(run, plan)
    metrics = {}
    for expected, stage, scenario in zip(plan["samples"], run["stages"], run["scenarios"], strict=True):
        if stage["id"] != expected or scenario["id"] != expected:
            raise TraceLoss(f"Wrong sample order for {expected}")
        requests = scenario["requests"]
        if len(requests) != 2:
            raise TraceLoss(f"Expected exactly one texture request for {expected}: {requests}")
        start, finish = requests
        events = [(begin, end) for begin, end, _ in run["native_snapshots"]
                  if start[0] <= begin <= end <= scenario["times_us"]["window_end"]]
        if start[1] != 1 or finish[1] != 0 or start[2:] != finish[2:] or len(events) != 1:
            raise TraceLoss(f"Incomplete whole-image snapshot for {expected}")
        begin, end = events[0]
        recording, = stage["recording_us"]
        if recording <= 0 or end <= begin or stage["paths"] != scenario["paths"]:
            raise TraceLoss(f"Invalid recording or snapshot duration for {expected}")
        metrics[expected] = {"recording_us": recording, "snap_first_us": end - begin,
                             "size": start[2:], "paths": stage["paths"]}
    return metrics


def main():
    """Uses only the two runtime corpus fixtures. / 只使用这两份运行时语料夹具。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--output", type=Path, default=APP_DIR.parent / "raster_cache_auto_merge_v3_raw.json")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--build", nargs=3, action="append", metavar=("VARIANT", "APK", "SO"), required=True)
    args = parser.parse_args()
    args.rounds = ROUNDS
    artifacts = {name: (Path(apk), Path(so)) for name, apk, so in args.build}
    if tuple(artifacts) != VARIANTS or len(args.build) != len(VARIANTS):
        parser.error(f"Provide builds in this order: {', '.join(VARIANTS)}")
    inputs = {row["id"]: args.corpus / "files" / row["file"]
              for row in manifest_rows(args.corpus) if row["id"] in SAMPLES}
    if set(inputs) != set(SAMPLES) or any(not path.is_file() for path in inputs.values()):
        parser.error("Missing runtime input")
    run_experiment(args, artifacts, inputs, make_plan, pixel_diffs,
                   partial(capture, validator=validate),
                   lambda _: {"displayed_pixels": True, "quick_merge": True})


if __name__ == "__main__":
    main()
