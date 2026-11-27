"""Retest artwork newly eligible after viewport clipping, using runtime SVGs."""

import argparse
import random
import re
from pathlib import Path

from raster_cache_auto_r2_plan import SEED, load_json, manifest_rows, save_json
from raster_cache_auto_r2_rules import BENEFIT_US, MIB, is_icon, tile_axis
from run_raster_cache_auto_mode import INBOX, ROOT, run_round, stage
from run_raster_cache_auto_r2 import DEVICE, Phone, apk_hash, sha256

DPR = 2.8125
SCREEN = (1080, 2340)
CAP = 12 * MIB
BATCH_SIZE = 8
ROUNDS = 3
SIZES = ("48", "200", "full")
STROKE_WIDTH = re.compile(rb"\bstroke-width\s*[=:]\s*['\"]?\s*([0-9.]+)")
THICK_STROKE = 0.02


def clipped_bytes(case):
    """Estimate the tiles reachable by the screen plus the runtime overscan."""
    f = case["features"]
    width = case["width_dp"] * DPR
    height = case["height_dp"] * DPR
    scale = width / f["picture_width"]
    bounds = f["content_bounds"]
    left, top, right, bottom = (0, 0, width, height) if bounds is None else (
        value * scale for value in bounds
    )
    left, top = max(0, left), max(0, top)
    right, bottom = min(width, right), min(height, bottom)
    if min(right, SCREEN[0]) <= left or min(bottom, SCREEN[1]) <= top:
        return 0
    return 4 * tile_axis(left, min(right, SCREEN[0] + 64), width) * tile_axis(
        top, min(bottom, SCREEN[1] + 64), height
    )


def select(raw, files):
    """Freeze a seeded sample across sizes and rendering features."""
    by_id = {row["id"]: row for row in raw["corpus"]}
    cases = {(row["sample"], row["size"]): row for row in raw["cases"]}
    for row in raw["anomaly_fix_refit"]["retest_cases"]:
        cases[row["sample"], row["size"]] = row

    eligible = []
    stroke_ratios = {}
    for (sample, size), case in cases.items():
        f = case["features"]
        if case["contained"] or (f["paths"] < 100 and f["points"] < 15000):
            continue
        estimate = clipped_bytes(case)
        if not 0 < estimate <= CAP:
            continue
        # Use SVG stroke-width literals as a sampling proxy for thick strokes.
        ratio = 0.0
        if f["strokes"] and sample in files:
            if sample not in stroke_ratios:
                widths = [
                    float(value) for value in STROKE_WIDTH.findall(files[sample].read_bytes())
                    if value.count(b".") <= 1 and value != b"."
                ]
                stroke_ratios[sample] = max(widths, default=0.0) / min(
                    f["picture_width"], f["picture_height"]
                )
            ratio = stroke_ratios[sample]
        effect = (
            "blur" if f["blurs"] else
            "thick_stroke" if ratio >= THICK_STROKE else
            "stroke" if f["strokes"] else "geometry"
        )
        eligible.append({
            "sample": sample, "size": size, "effect": effect,
            "icon": is_icon(case, by_id), "split": case["split"],
            "stroke_width_ratio": round(ratio, 6), "estimated_bytes": estimate,
            "features": f,
        })
    rng = random.Random(SEED)
    selected = []
    small = [row for row in eligible if row["size"] == "16"]
    for blur in (True, False):
        selected.extend(rng.sample([row for row in small if (row["effect"] == "blur") == blur], 6))
    for size in SIZES:
        pool = [row for row in eligible if row["size"] == size and row["sample"] in files]
        chosen = [row for row in pool if row["icon"]]
        for effect, count in (("blur", 5), ("thick_stroke", 4), ("geometry", 3), ("stroke", 3)):
            group = [row for row in pool if row["effect"] == effect and row not in chosen]
            chosen.extend(rng.sample(group, min(count, len(group))))
        chosen.extend(rng.sample([row for row in pool if row not in chosen], 16 - len(chosen)))
        selected.extend(chosen)
    rng.shuffle(selected)
    return selected, len(eligible)


def measure(phone, plan, record, output, scratch):
    """Measure each pair on a fresh process, preserving the result of every attempt."""
    for round_id in range(1, ROUNDS + 1):
        for start in range(0, len(plan), BATCH_SIZE):
            batch = plan[start:start + BATCH_SIZE]
            rows = [[row["sample"], row["size"]] for row in batch]
            request = {
                "illustrations": rows,
                "list_samples": [],
                "overflow_recheck": True,
                "scroll_icons": start == 0,
            }
            for _ in range(3):
                result = run_round(phone, round_id, scratch / "plan.json", request)
                record["batches"].append({"request": request, **result})
                save_json(output, record)
                if result["status"] != "thermal_restart":
                    break
            if result["status"] != "done" or result["backend"] != "Impeller Vulkan":
                raise RuntimeError(f"Round {round_id}, batch {start // BATCH_SIZE + 1}: {result['status']}")


def main():
    """Verify the built APK and clean up the device after measuring."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    digest = apk_hash(args.apk)
    if digest != sha256("../../rust/target/aarch64-linux-android/release/libxvg.so"):
        raise RuntimeError("APK library differs from the workspace release library")
    files = {row["id"]: args.corpus / "files" / row["file"] for row in manifest_rows(args.corpus)}
    plan, population = select(load_json("../raster_cache_auto_r2_raw.json"), files)
    phone = Phone(DEVICE)
    record = {
        "device": DEVICE, "model": phone.shell("getprop ro.product.model"),
        "apk_so_sha256": digest, "apk_sha256": sha256(args.apk), "build_mode": "profile",
        "seed": SEED, "eligible_population": population, "hit_min_gain_us": BENEFIT_US,
        "plan": plan, "batches": [],
    }
    previous = phone.shell("settings get global stay_on_while_plugged_in")
    try:
        phone.adb("install", "-r", str(args.apk), timeout=160)
        phone.shell("settings put global stay_on_while_plugged_in 7")
        phone.shell("input keyevent KEYCODE_WAKEUP")
        phone.shell("wm dismiss-keyguard")
        phone.app(f"mkdir -p {ROOT}/input")
        for sample in sorted({row["sample"] for row in plan} & files.keys()):
            stage(phone, files[sample], f"input/{sample}.svg")
        measure(phone, plan, record, args.output, args.output.parent)
    finally:
        phone.stop()
        phone.app(f"rm -rf {ROOT}")
        phone.shell(f"rm -f {INBOX}")
        if previous == "null":
            phone.shell("settings delete global stay_on_while_plugged_in")
        else:
            phone.shell("settings put global stay_on_while_plugged_in " + previous)
        record["device_temporary_files_removed"] = (
            phone.app(f"test ! -e {ROOT} && test ! -e {INBOX} && echo clean") == "clean"
        )
        record["wake_setting_restored"] = (
            phone.shell("settings get global stay_on_while_plugged_in") == previous
        )
        save_json(args.output, record)


if __name__ == "__main__":
    main()
