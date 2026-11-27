"""Run the Android 2×2 draw-call experiment. / 在 Android 真机测量合并绘制与分帧录制的 2×2 对照。"""

import argparse
import hashlib
import json
import math
import random
import shutil
import statistics
import tempfile
import time
import zipfile
import zlib
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows, save_json
from run_drawcall_merge import compare, verify
from run_drawcall_micro import HotDevice, SETTINGS, SnapshotTrace, TraceLoss, cool, trace_slices
from run_raster_cache_auto_r2 import APP, DEVICE, Phone, sha256
from run_raster_cache_image_space import Device
from run_ui_thread_decode_record import INBOX, LIB_HASH, ROOT, restore_setting, stage, thermal, validate_round
from summarize_drawcall_merge import frames_in, stage as stage_metrics, window_metrics

APP_DIR = Path(__file__).resolve().parents[1]
SAMPLES = ("web-543", "web-544", "web-545", "web-150", "web-002", "web-541", "web-540")
COMBINATIONS = ("C0A0", "C1A0", "C0A1", "C1A1")
SO_HASHES = {"C0": LIB_HASH,
             "C1": "f06d1e9747e73d0b75c6a9399f6f4dfad448f7f55b711e62bdf02b7156b93583"}
ROUNDS = 5
SEED = 20261127
STEADY_DELAY_US = 50_000
REFRESH_HZ = 120


def round_plan(number):
    """Keeps sample order paired and randomizes both orders each round. / 每轮分别随机化组合和样本顺序，同轮四组复用样本顺序。"""
    rng = random.Random(SEED + number)
    return {"round": number, "trials": 1, "capture_pixels": True,
            "samples": rng.sample(SAMPLES, len(SAMPLES)),
            "combinations": rng.sample(COMBINATIONS, len(COMBINATIONS))}


def verify_builds(artifacts, inputs, expected_hashes=SO_HASHES):
    """Confirms native hashes, identical Dart AOT and runtime-only inputs. / 核验原生哈希、相同的 Dart AOT 和素材仅运行时传入。"""
    markers = []
    for path in inputs.values():
        data = path.read_bytes()
        markers.append(path.name.encode("utf-8"))
        for position in (len(data) // 5, len(data) // 2, len(data) * 4 // 5):
            markers.append(data[position:position + 192])
    result = {}
    for variant, (apk, so) in artifacts.items():
        build = verify(apk, so, "old" if variant == "C0" else "new")
        if variant in expected_hashes and build["so_sha256"] != expected_hashes[variant]:
            raise RuntimeError(f"Unexpected {variant} so SHA-256")
        with zipfile.ZipFile(apk) as package:
            for item in package.infolist():
                if item.is_dir():
                    continue
                if item.filename.lower().endswith((".svg", ".svgz")):
                    raise RuntimeError("Found an SVG entry in the APK")
                payload = package.read(item)
                if any(marker in payload or marker in item.filename.encode() for marker in markers):
                    raise RuntimeError(f"Found a corpus marker in APK entry {item.filename}")
            build["dart_aot_sha256"] = hashlib.sha256(package.read("lib/arm64-v8a/libapp.so")).hexdigest()
            build["assets_verified"] = True
        result[variant] = build
    if len({build["dart_aot_sha256"] for build in result.values()}) != 1:
        raise RuntimeError("Dart AOT differs between the two APKs")
    return result


def trial_metrics(run, row, snapshots):
    """Measures the first displayed frame and budget misses by thread. / 计量首个显示帧、逐线程超预算帧及实际漏节拍。"""
    times = row["times_us"]
    period = 1_000_000 / row["hz"]
    mount, end = times["mount"], times["window_end"]
    reported = sorted(frames_in(run, 0, end))
    first, = (frame for frame in reported if frame[5] == times["first_art_frame"])
    preceding = [frame[0] for frame in reported if frame[0] < min(mount, first[0])]
    start = max(preceding, default=first[0])
    frames = [frame for frame in reported if frame[0] >= start]
    startup = [frame for frame in frames if frame[0] <= first[0]]
    if len(startup) < 2 or first[4] < mount:
        raise TraceLoss(f"Missing startup frame coverage for {row['id']}")
    steady_start = max([first[4], *(event[1] for event in snapshots)]) + STEADY_DELAY_US
    steady = [frame[4] - frame[3] for frame in frames if frame[0] >= steady_start]
    if len(steady) < 5:
        raise TraceLoss(f"Fewer than five steady-state frames for {row['id']}")
    durations = [event[1] - event[0] for event in snapshots]
    return {
        **window_metrics(startup, row["hz"]),
        "ui_over_budget": sum(frame[2] >= mount and frame[2] - frame[1] > period for frame in startup),
        "raster_over_budget": sum(frame[4] >= mount and frame[4] - frame[3] > period for frame in startup),
        "display": first[4] - mount,
        "snap_first": durations[0] if durations else None,
        "snap_peak": max(durations, default=None),
        "steady_raster": statistics.median(steady),
        "steady_frames": len(steady),
    }


def validate_and_summarize(run, plan):
    """Checks coverage and associates queued textures with the native slices. / 核对覆盖范围并把纹理请求与原生快照片段配对。"""
    validate_round(run, plan)
    sliced = plan["recording_sliced"]
    if run["recording_sliced"] != sliced:
        raise TraceLoss("Wrong recording mode")
    stages, scenarios = run["stages"], run["scenarios"]
    for key in ("stages", "scenarios"):
        if [row["id"] for row in run[key]] != plan["samples"]:
            raise TraceLoss(f"Wrong sample order in {key}")
        for row in run[key]:
            yields = row["recording_yields"]
            if len(row["recording_us"]) != yields + 1 or (not sliced and yields):
                raise TraceLoss(f"Wrong slice count for {row['id']}")
    if sliced and not any(row["recording_yields"] for row in stages):
        raise TraceLoss("Sliced recording produced no continuation frames")
    metrics = {}
    for parsed, row in zip(stages, scenarios, strict=True):
        sample, times = row["id"], row["times_us"]
        if not math.isclose(row["hz"], REFRESH_HZ, abs_tol=0.25):
            raise TraceLoss(f"Expected {REFRESH_HZ} Hz for {sample}, got {row['hz']}")
        requests = row["requests"]
        starts = [request[0] for request in requests if request[1]]
        snapshots = [event for event in run["native_snapshots"]
                     if starts and starts[0] <= event[0] <= times["window_end"]]
        if (len(requests) != 2 * len(starts) or len(snapshots) != len(starts)
                or any(start > event[0] for start, event in zip(starts, snapshots))):
            raise TraceLoss(f"Native snapshot coverage {sample}: {len(snapshots)}/{len(starts)}")
        metrics[sample] = {**stage_metrics(parsed), **trial_metrics(run, row, snapshots),
                           "paths": parsed["paths"], "bytes": parsed["bytes"],
                           "snapshot_count": len(snapshots)}
    return metrics


def capture(phone, device, scratch, plan, readings, validator=validate_and_summarize):
    """Runs one fresh process with thermal polling and native trace collection. / 每组启动新进程，同时轮询热状态并采集原生快照。"""
    name = f"r{plan['round']}/{plan['combination']}"
    local_plan = scratch / "plan.json"
    save_json(local_plan, plan)
    phone.app(f"rm -f {ROOT}/status {ROOT}/result.json {ROOT}/trace.ready")
    stage(phone, local_plan, "plan.json")
    cool(phone, readings)
    trace = None
    last_poll = last_trace = 0.0
    previous_state = ""
    deadline = time.monotonic() + 150
    try:
        phone.launch()
        pid = phone.pid()
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now - last_poll >= 0.9:
                readings.append(thermal(phone))
                last_poll = now
                if readings[-1]["status"]:
                    raise HotDevice(f"{name}: thermal status {readings[-1]['status']}")
                state = device.read("status", root=ROOT)
                if state != previous_state:
                    print(f"{name} {state}", flush=True)
                    previous_state = state
                if state == "ready" and trace is None:
                    trace = SnapshotTrace(device, pid)
                    phone.app(f"touch {ROOT}/trace.ready")
                if state == "done":
                    trace.poll()
                    break
                if state.startswith("error"):
                    if state.startswith("error scenario ") and state.endswith(" TimeoutException"):
                        raise TraceLoss(f"{name}: {state}")
                    raise RuntimeError(f"{name}: {state}\n{device.read('error-stack', root=ROOT)}")
                if phone.pid() != pid:
                    raise RuntimeError(f"{name}: app exited at {state}: {phone.exit_reason(pid)}")
            if trace and now - last_trace >= 0.6:
                trace.poll()
                last_trace = now
            time.sleep(0.15)
        else:
            raise RuntimeError(f"{name}: timed out at {previous_state}")
        if phone.backend(pid) != "Impeller Vulkan":
            raise RuntimeError("Expected Impeller Vulkan in profile startup log")
        data = json.loads(device.read("result.json", root=ROOT))
        data["native_snapshots"] = trace_slices(trace.events)
        data["native_snapshot_events"] = sorted(trace.events)
        data["metrics"] = validator(data, plan)
        images = {}
        for sample in plan["samples"]:
            width, height = data["pixel_sizes"][sample]
            pixels = zlib.decompress(device.read(f"{sample}.rgba.z", binary=True, root=ROOT))
            if len(pixels) != width * height * 4 or not any(memoryview(pixels)[3::4]):
                raise TraceLoss(f"Invalid or empty RGBA for {sample}")
            images[sample] = pixels
        data["rgba_sha256"] = {sample: hashlib.sha256(pixels).hexdigest()
                               for sample, pixels in images.items()}
        return data, images
    finally:
        try:
            if trace:
                trace.close()
        finally:
            phone.stop()


def pixel_diffs(runs, images):
    """Compares C and A within the same randomized block. / 在同一随机轮次中分别比较 C 和 A 的像素。"""
    result = {}
    for old, new in (("C0A0", "C1A0"), ("C0A1", "C1A1"),
                     ("C0A0", "C0A1"), ("C1A0", "C1A1")):
        if runs[old]["pixel_sizes"] != runs[new]["pixel_sizes"]:
            raise RuntimeError("Pixel sizes differ between combinations")
        result[f"{old}/{new}"] = {sample: compare(images[old][sample], images[new][sample])
                                   for sample in SAMPLES}
    return result


def resume_rounds(raw, checkpoint, planner=round_plan):
    """Keeps identity-checked whole blocks and retires incomplete blocks. / 保留身份符合的完整轮次，归档未完成的轮次。"""
    for key in ("device", "model", "android", "backend", "sdk", "builds", "inputs", "seed"):
        if checkpoint[key] != raw[key]:
            raise RuntimeError(f"Checkpoint differs in {key}")
    for number, block in enumerate(checkpoint["rounds"], 1):
        plan = planner(number)
        if block["plan"] != plan or list(block["runs"]) != plan["combinations"][:len(block["runs"])]:
            raise RuntimeError(f"Unexpected checkpoint block {number}")
        if "pixel_diffs" in block and len(block["runs"]) == len(plan["combinations"]):
            raw["rounds"].append(block)
        else:
            if number != len(checkpoint["rounds"]):
                raise RuntimeError(f"Incomplete checkpoint block {number} before final block")
            raw.setdefault("discarded_partial_rounds", []).append(block)
    raw["retries"] = checkpoint["retries"]


def run(args):
    """Collects five complete blocks and restores device state on exit. / 采集五个完整轮次，退出时恢复设备状态。"""
    artifacts = {"C0": (args.c0_apk, args.c0_so), "C1": (args.c1_apk, args.c1_so)}
    inputs = {row["id"]: args.corpus / "files" / row["file"]
              for row in manifest_rows(args.corpus) if row["id"] in SAMPLES}
    return run_experiment(args, artifacts, inputs, round_plan, pixel_diffs, capture,
                          lambda combination: {"recording_sliced": combination.endswith("A1")})


def run_experiment(args, artifacts, inputs, planner, compare_pixels, capture_run, mode):
    """Runs paired APKs and restores settings and the original installation. / 成对运行 APK 并恢复设置与原有安装。"""
    builds = verify_builds(artifacts, inputs)
    for variant, build in builds.items():
        print(f"{variant} APK so {build['so_sha256']}", flush=True)
    phone, device = Phone(args.device), Device(args.device)
    sdk = Path(shutil.which("flutter.bat")).parents[1] / "bin/cache/flutter.version.json"
    raw = {"device": args.device, "model": phone.shell("getprop ro.product.model"),
           "android": phone.shell("getprop ro.build.version.release"), "backend": "Impeller Vulkan",
           "sdk": json.loads(sdk.read_text(encoding="utf-8")), "builds": builds, "seed": SEED,
           "inputs": {sample: {"bytes": path.stat().st_size, "sha256": sha256(path)}
                      for sample, path in inputs.items()},
           "rounds": [], "retries": []}
    if args.resume:
        checkpoint = json.loads(args.output.read_text(encoding="utf-8"))
        raw["discarded_partial_rounds"] = checkpoint.get("discarded_partial_rounds", [])
        resume_rounds(raw, checkpoint, planner)
        if len(raw["rounds"]) >= args.rounds:
            if not (checkpoint["device_cleanup"] and checkpoint["apk_restored"]
                    and checkpoint["forwarding_restored"] and all(checkpoint["settings_restored"].values())):
                raise RuntimeError(f"Device restoration incomplete, see {args.output}")
            print(f"Requested rounds already complete: {args.output}", flush=True)
            return
    if device.shell(f"test ! -e {ROOT} && test ! -e {INBOX} && echo clean") != "clean":
        raise RuntimeError("Device stage directory or inbox is already in use")
    saved = {(namespace, key): phone.shell(f"settings get {namespace} {key}")
             for namespace, key, _ in SETTINGS}
    forwards = device.adb("forward", "--list")
    with tempfile.TemporaryDirectory(prefix="xvg-drawcall-isolated-") as directory:
        scratch = Path(directory)
        previous = scratch / "previous.apk"
        installed = phone.shell(f"pm path {APP}").splitlines()
        if installed:
            if len(installed) != 1 or not installed[0].startswith("package:"):
                raise RuntimeError("Existing benchmark APK is split")
            device.adb("pull", installed[0].removeprefix("package:"), previous, timeout=120)
            raw["previous_apk_sha256"] = sha256(previous)
        active_variant = None
        try:
            for number in range(len(raw["rounds"]) + 1, args.rounds + 1):
                plan = planner(number)
                runs, images = {}, {}
                raw["rounds"].append({"plan": plan, "runs": runs})
                print(f"Round {number}: {' '.join(plan['combinations'])}", flush=True)
                for combination in plan["combinations"]:
                    variant = combination if combination in artifacts else combination[:2]
                    if variant != active_variant:
                        if "Success" not in device.adb("install", "-r", artifacts[variant][0], timeout=120):
                            raise RuntimeError(f"Could not install {variant}")
                        if active_variant is None:
                            active_variant = variant
                            for namespace, key, value in SETTINGS:
                                device.shell(f"settings put {namespace} {key} {value}")
                            device.shell("input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard")
                            phone.app(f"mkdir -p {ROOT}")
                            for sample, path in inputs.items():
                                stage(phone, path, f"{sample}.svg")
                        active_variant = variant
                    trial = {**plan, "combination": combination, **mode(combination)}
                    for attempt in range(1, 4):
                        readings = []
                        try:
                            data, images[combination] = capture_run(phone, device, scratch, trial, readings)
                        except (HotDevice, TraceLoss) as error:
                            print(f"Retry {number}/{combination}: {error}", flush=True)
                            raw["retries"].append({"round": number, "combination": combination,
                                                   "attempt": attempt, "error": str(error), "thermal": readings})
                            save_json(args.output, raw)
                        else:
                            runs[combination] = {**data, "thermal": readings}
                            save_json(args.output, raw)
                            break
                    else:
                        raise RuntimeError(f"Retries exhausted at {number}/{combination}")
                raw["rounds"][-1]["pixel_diffs"] = compare_pixels(runs, images)
                save_json(args.output, raw)
        finally:
            if active_variant is not None:
                try:
                    phone.stop()
                    phone.app(f"rm -rf {ROOT}")
                    phone.shell(f"rm -f {INBOX}")
                    raw["device_cleanup"] = (phone.app(f"test ! -e {ROOT} && echo clean") == "clean"
                                             and phone.shell(f"test ! -e {INBOX} && echo clean") == "clean")
                    raw["forwarding_restored"] = device.adb("forward", "--list") == forwards
                finally:
                    try:
                        raw["settings_restored"] = {
                            key: restore_setting(phone, namespace, key, value)
                            for (namespace, key), value in saved.items()
                        }
                    finally:
                        raw["apk_restored"] = "Success" in (
                            device.adb("install", "-r", previous, timeout=120)
                            if previous.exists() else device.adb("uninstall", APP))
                        if previous.exists() and raw["apk_restored"]:
                            path = phone.shell(f"pm path {APP}").removeprefix("package:")
                            raw["apk_restored"] = device.shell(f"sha256sum {path}").split()[0] == raw["previous_apk_sha256"]
                        save_json(args.output, raw)
    if not (raw["device_cleanup"] and raw["apk_restored"] and raw["forwarding_restored"]
            and all(raw["settings_restored"].values())):
        raise RuntimeError(f"Device restoration incomplete, see {args.output}")
    print(f"Device cleaned and restored. Raw data: {args.output}", flush=True)


def main():
    """Reads verified build paths and the runtime corpus location. / 读取待核验的构建和运行时语料位置。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--output", type=Path, default=APP_DIR.parent / "raster_cache_auto_isolated_raw.json")
    parser.add_argument("--rounds", type=int, choices=range(1, ROUNDS + 1), default=ROUNDS)
    parser.add_argument("--resume", action="store_true")
    for variant in ("c0", "c1"):
        for kind in ("apk", "so"):
            parser.add_argument(f"--{variant}-{kind}", type=Path, required=True)
    run(parser.parse_args())


if __name__ == "__main__":
    main()
