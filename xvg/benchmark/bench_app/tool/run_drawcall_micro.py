"""Run the standalone Vulkan draw-call microbenchmark. / 运行独立的 Vulkan 绘制调用微基准。"""

import argparse
import json
import math
import random
import re
import shutil
import statistics
import tempfile
import time
import zlib
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import ProxyHandler, build_opener

from run_drawcall_merge import compare
from run_raster_cache_auto_r2 import APP, DEVICE, Phone, sha256
from run_raster_cache_image_space import Device, digest
from run_ui_thread_decode_record import restore_setting, thermal

APP_DIR = Path(__file__).resolve().parents[1]
ROOT = f"/sdcard/Android/data/{APP}/files/xvg-drawcall-micro"
INBOX = "/data/local/tmp/xvg-drawcall-micro-inbox"
OUTPUT = APP_DIR.parent / "raster_cache_auto_micro_raw.json"
ROUNDS = 5
SEED = 20261127
SIDE = 1080
WARM_FRAMES = 8
SAMPLE_FRAMES = 36
SHAPES = ("rect", "quad", "concave", "cubic")
COUNTS = (1000, 10000, 80000)
GROUPS = {"A": 1, "B": 0, "C": None, "D16": 16, "D128": 128, "D1024": 1024}
PIXELS = (("rect", 80000), ("quad", 10000), ("cubic", 80000))
SETTINGS = (
    ("global", "stay_on_while_plugged_in", "7"),
    ("system", "min_refresh_rate", "120.0"),
    ("system", "peak_refresh_rate", "120.0"),
)
FRAME_COLUMNS = ("number", "vsync", "build_start", "raster_start", "raster_finish",
                 "picture_cache_count", "layer_cache_count")
SNAPSHOT_EVENT = "DoMakeRasterSnapshot"
TRACE_OVERLAP_US = 5_000_000


class HotDevice(Exception):
    """Indicates that a timing round has to be discarded. / 表示本轮计时需要作废。"""


class TraceLoss(RuntimeError):
    """Indicates that a round has incomplete native evidence. / 表示本轮的原生时间线证据不完整。"""


class SnapshotTrace:
    """Harvests overlapping VM timeline windows during the snapshot stage. / 在快照阶段收集有重叠的 VM 时间线窗口。"""

    def __init__(self, device, pid):
        """Enables Embedder events on the verified local VM service. / 在已核验的本地 VM service 上开启 Embedder 事件。"""
        self.device = device
        self.opener = build_opener(ProxyHandler({}))
        self.events = set()
        log = device.adb("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
        uri = re.search(r"VM service is listening on http://127\.0\.0\.1:(\d+)/(\S+/)", log)
        if uri is None:
            raise RuntimeError("VM service address missing from profile process")
        self.port = device.adb("forward", "tcp:0", f"tcp:{uri[1]}")
        self.url = f"http://127.0.0.1:{self.port}/{uri[2]}"
        try:
            self.origin = self.call("getVMTimelineMicros")["timestamp"]
            self.call("setVMTimelineFlags", recordedStreams="[Embedder]")
        except Exception:
            self.close()
            raise

    def call(self, method, **params):
        """Reads a VM service result through the local adb forwarding port. / 从 adb 本地转发端口读取 VM service 结果。"""
        query = f"?{urlencode(params)}" if params else ""
        with self.opener.open(f"{self.url}{method}{query}", timeout=8) as response:
            message = json.load(response)
        if "result" not in message:
            raise RuntimeError(f"VM service {method}: {message['error']}")
        return message["result"]

    def poll(self):
        """Keeps both sides of slices even when they appear in different polls. / 保留分开出现在不同轮询中的切片起止事件。"""
        timeline = self.call("getVMTimeline", timeOriginMicros=self.origin)
        newest = self.origin
        for event in timeline["traceEvents"]:
            timestamp = event.get("ts")
            if not isinstance(timestamp, int):
                continue
            newest = max(newest, timestamp)
            if event["name"] == SNAPSHOT_EVENT:
                self.events.add((timestamp, event["tid"], event["ph"], event.get("dur", 0)))
        self.origin = max(self.origin, newest - TRACE_OVERLAP_US)

    def close(self):
        """Removes only the forwarding port owned by this collector. / 只移除此采集器创建的转发端口。"""
        self.opener.close()
        self.device.adb("forward", "--remove", f"tcp:{self.port}")


def trace_slices(events):
    """Pairs sorted begin/end events and deduplicates complete slices. / 按时间配对起止事件并对完整切片去重。"""
    active = {}
    slices = set()
    for timestamp, thread, phase, duration in sorted(events):
        if phase == "X":
            slices.add((timestamp, timestamp + duration, thread))
        elif phase == "B":
            active[thread] = timestamp
        elif phase == "E" and thread in active:
            slices.add((active.pop(thread), timestamp, thread))
    return [list(event) for event in sorted(slices)]


def case(shape, count, mode):
    """Builds a case whose ID describes its geometry and grouping. / 构造编号含几何与分组的试次。"""
    group = GROUPS[mode]
    return {"id": f"{shape}-{count}-{mode}", "shape": shape, "count": count,
            "mode": mode, "group": count if group is None else group}


def plan(round_number):
    """Shuffles all 63 cases independently per round with a fixed seed. / 以固定种子为每轮独立打乱全部 63 组。"""
    trials = [case(shape, count, mode) for shape in SHAPES for count in COUNTS
              for mode in GROUPS if mode != "B" or shape == "rect"]
    random.Random(SEED + round_number).shuffle(trials)
    return {"trials": trials, "captures": [], "warm": WARM_FRAMES, "samples": SAMPLE_FRAMES}


def smoke_plan():
    """Exercises the largest separate and merged paths with shorter frame windows. / 用较短帧窗口检查最大分开与合并路径。"""
    trials = [case(shape, COUNTS[-1], mode) for shape in SHAPES for mode in ("A", "C")]
    trials.extend([case("rect", COUNTS[-1], "B"), case("quad", COUNTS[-1], "D1024")])
    return {"trials": trials, "captures": [], "warm": WARM_FRAMES, "samples": 8}


def pixel_plan():
    """Runs the paired screenshots in a separate untimed process. / 在独立的非计时进程中截取三对图。"""
    return {"trials": [], "captures": [case(shape, count, mode)
                                       for shape, count in PIXELS for mode in ("A", "C")],
            "warm": WARM_FRAMES, "samples": SAMPLE_FRAMES}


def save(path, data):
    """Replaces a complete JSON checkpoint atomically on the host. / 在主机上原子替换完整 JSON 进度。"""
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")),
                         encoding="utf-8")
    temporary.replace(path)


def cool(phone, readings):
    """Waits for two thermal-zero readings after a hot interval. / 热状态升高后等到连续两次读数归零。"""
    reading = thermal(phone)
    readings.append(reading)
    if reading["status"] == 0:
        return
    print(f'Thermal status {reading["status"]}, waiting for cooldown', flush=True)
    zero_count = 0
    deadline = time.monotonic() + 1200
    while zero_count < 2:
        if time.monotonic() >= deadline:
            raise RuntimeError("Thermal status did not recover")
        time.sleep(8)
        reading = thermal(phone)
        readings.append(reading)
        zero_count = 0 if reading["status"] else zero_count + 1
    print("Thermal status 0, resuming", flush=True)


def run_app(phone, device, scratch, name, run_plan, readings):
    """Runs one profile process with thermal checks and an isolated native trace. / 在单个 profile 进程执行热检查并采集原生时间线。"""
    job = scratch / name
    job.mkdir()
    local = job / "plan.json"
    save(local, run_plan)
    device.stop()
    device.app(f"rm -rf {ROOT} && mkdir -p {ROOT}")
    try:
        device.adb("push", local, INBOX)
        device.app(f"cp {INBOX} {ROOT}/plan.json")
    finally:
        device.shell(f"rm -f {INBOX}")
    cool(phone, readings)
    trace = None
    started = False
    last_status = ""
    last_report = 0.0
    last_thermal = 0.0
    last_status_read = 0.0
    deadline = time.monotonic() + 720
    try:
        phone.launch()
        pid = phone.pid()
        if phone.backend(pid) != "Impeller Vulkan":
            raise RuntimeError("Expected Impeller Vulkan in Flutter profile startup log")
        while time.monotonic() < deadline:
            now = time.monotonic()
            if now - last_thermal >= 0.9:
                reading = thermal(phone)
                readings.append(reading)
                last_thermal = now
                if reading["status"] > 0:
                    raise HotDevice(f'{name}: thermal={reading["status"]} at {last_status}')
            if now - last_status_read >= 0.6:
                last_status_read = now
                status = device.read("status", root=ROOT)
                if status != last_status and (now - last_report >= 8
                                              or status in ("ready", "trace", "done")):
                    print(f"{name}: {status}", flush=True)
                    last_report = now
                last_status = status
                if status == "ready" and not started:
                    device.app(f"touch {ROOT}/start")
                    started = True
                if status == "trace" and trace is None:
                    trace = SnapshotTrace(device, pid)
                    device.app(f"touch {ROOT}/trace.start")
                if status == "done":
                    reading = thermal(phone)
                    readings.append(reading)
                    if reading["status"] > 0:
                        raise HotDevice(f'{name}: thermal={reading["status"]} at completion')
                    if trace:
                        trace.poll()
                    break
                if status == "error":
                    raise RuntimeError(device.read("error", root=ROOT))
                if phone.pid() != pid:
                    raise RuntimeError(f"{name}: app exited at {status}: {phone.exit_reason(pid)}")
            if trace:
                trace.poll()
            time.sleep(0.2 if trace else 0.6)
        else:
            raise RuntimeError(f"{name}: timed out at {last_status}")
    finally:
        try:
            if trace:
                trace.close()
        finally:
            device.stop()
    if run_plan["captures"]:
        return read_pixels(device, run_plan["captures"])
    frames = read_rows(device.read("frames.jsonl", root=ROOT))
    snapshots = read_rows(device.read("snapshots.jsonl", root=ROOT))
    native = trace_slices(trace.events)
    return {"view": frames[0], "trials": join(run_plan, frames[1:], snapshots, native),
            "thermal": readings, "trace_collector": "overlapping VM service HTTP windows"}


def read_rows(lines):
    """Decodes JSON records written one per line. / 解码逐行保存的 JSON 记录。"""
    return [json.loads(line) for line in lines.splitlines()]


def sample_stats(rows, warm, samples):
    """Validates frame measurements and computes two raster quantiles. / 核验帧采样并计算两个 raster 分位数。"""
    if len(rows) != warm + samples or {len(row) for row in rows} != {len(FRAME_COLUMNS)}:
        raise RuntimeError("Wrong FrameTiming sample dimensions")
    if any(a[0] >= b[0] for a, b in zip(rows, rows[1:])):
        raise RuntimeError("Duplicate or out-of-order FrameTiming")
    if any(row[1] > row[2] or row[2] > row[3] or row[3] > row[4] or any(row[5:])
           for row in rows):
        raise RuntimeError("Invalid FrameTiming chronology or an active raster cache")
    values = sorted(row[4] - row[3] for row in rows[warm:])
    return {"p50_us": statistics.median(values), "p90_us": values[math.ceil(samples * .9) - 1]}


def join(run_plan, frames, snapshots, native):
    """Requires a unique native snapshot fully within each request. / 要求每个请求内有一条唯一且完整的原生快照切片。"""
    trials = run_plan["trials"]
    keys = [item["id"] for item in trials]
    if keys != [item["id"] for item in frames] or keys != [item["id"] for item in snapshots]:
        raise RuntimeError("Case order or completed trial count differs from plan")
    joined = []
    mismatches = []
    for row, request in zip(frames, snapshots):
        begin, end = request["request_us"], request["readback_us"]
        matched = [event for event in native if begin <= event[0] < event[1] <= end]
        if len(matched) != 1 or not begin <= request["handle_us"] <= end:
            mismatches.append((row["id"], len(matched)))
            continue
        steady = sample_stats(row["frames"], run_plan["warm"], run_plan["samples"])
        baseline = sample_stats(row["baseline"], run_plan["warm"], run_plan["samples"])
        event = matched[0]
        joined.append({**row, "snapshot_request": request, "native_snapshot": event,
                       "snapshot_us": event[1] - event[0], "steady": steady,
                       "spinner": baseline,
                       "net": {key: steady[key] - baseline[key] for key in steady}})
    if (mismatches or len(native) != len(trials)
            or len({tuple(row["native_snapshot"]) for row in joined}) != len(trials)):
        raise TraceLoss(f"Expected {len(trials)} native snapshots, captured {len(native)}. "
                        f"Unpaired requests: {mismatches}")
    return joined


def read_pixels(device, captures):
    """Validates image dimensions and compares raw premultiplied RGBA. / 核对图片尺寸并比较预乘 RGBA。"""
    images = {}
    for item in captures:
        name = item["id"]
        png = device.read(f"{name}.png", binary=True, root=ROOT)
        rgba = zlib.decompress(device.read(f"{name}.rgba.z", binary=True, root=ROOT))
        if (png[:16] != b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
                or int.from_bytes(png[16:20]) != SIDE or int.from_bytes(png[20:24]) != SIDE
                or len(rgba) != SIDE * SIDE * 4 or not any(rgba[3::4])):
            raise RuntimeError(f"Invalid or blank screenshot: {name}")
        images[name] = (rgba, {"png_sha256": digest(png), "rgba_sha256": digest(rgba),
                               "nontransparent": sum(alpha > 0 for alpha in rgba[3::4])})
    diffs = []
    for shape, count in PIXELS:
        a_id, c_id = (case(shape, count, mode)["id"] for mode in ("A", "C"))
        a, a_info = images[a_id]
        c, c_info = images[c_id]
        diffs.append({"shape": shape, "count": count, "A": a_info, "C": c_info,
                      **compare(a, c)})
    return diffs


def run(args):
    """Installs the benchmark temporarily and restores device resources on exit. / 临时安装基准并在退出时恢复设备资源。"""
    phone, device = Phone(args.device), Device(args.device)
    version = Path(shutil.which("flutter.bat")).parents[1] / "bin/cache/flutter.version.json"
    raw = {
        "device": args.device, "model": phone.shell("getprop ro.product.model"),
        "android": phone.shell("getprop ro.build.version.release"), "mode": "profile",
        "backend": "Impeller Vulkan", "apk_sha256": sha256(args.apk),
        "sdk": json.loads(version.read_text(encoding="utf-8")), "side": SIDE,
        "frame_columns": list(FRAME_COLUMNS), "warm_frames": WARM_FRAMES,
        "sample_frames": SAMPLE_FRAMES, "seed": SEED, "rounds": [], "thermal_retries": [],
        "trace_retries": [],
    }
    if args.resume:
        checkpoint = json.loads(args.output.read_text(encoding="utf-8"))
        for key in ("device", "apk_sha256", "sdk", "frame_columns", "warm_frames",
                    "sample_frames", "seed"):
            if checkpoint[key] != raw[key]:
                raise RuntimeError(f"Checkpoint differs in {key}")
        for i, measured in enumerate(checkpoint["rounds"], 1):
            if (measured["id"] != f"round-{i}" or
                    [t["id"] for t in measured["trials"]] != [t["id"] for t in plan(i)["trials"]]):
                raise RuntimeError(f"Incomplete or unexpected checkpoint round {i}")
        raw.update(checkpoint)
    saved = {(namespace, key): phone.shell(f"settings get {namespace} {key}")
             for namespace, key, _ in SETTINGS}
    if device.shell(f"test ! -e {ROOT} && test ! -e {INBOX} && echo clean") != "clean":
        raise RuntimeError("Microbenchmark temporary directory or inbox already exists")
    with tempfile.TemporaryDirectory(prefix="xvg-drawcall-micro-") as directory:
        scratch = Path(directory)
        previous = scratch / "previous.apk"
        installed = phone.shell(f"pm path {APP}").splitlines()
        if installed:
            if len(installed) != 1 or not installed[0].startswith("package:"):
                raise RuntimeError("Existing benchmark package is split")
            device.adb("pull", installed[0].removeprefix("package:"), previous, timeout=120)
            raw["previous_apk_sha256"] = sha256(previous)
        changed = False
        try:
            if "Success" not in device.adb("install", "-r", args.apk, timeout=120):
                raise RuntimeError("Benchmark APK installation failed")
            changed = True
            for namespace, key, value in SETTINGS:
                device.shell(f"settings put {namespace} {key} {value}")
            device.shell("input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard")
            jobs = [] if "smoke" in raw else [("smoke", smoke_plan())]
            if not args.smoke:
                jobs.extend((f"round-{i}", plan(i))
                            for i in range(len(raw["rounds"]) + 1, ROUNDS + 1))
            if "pixel_diffs" not in raw:
                jobs.append(("pixels", pixel_plan()))
            for name, run_plan in jobs:
                readings = []
                for attempt in range(1, 4):
                    try:
                        run_data = run_app(phone, device, scratch, f"{name}-{attempt}",
                                           run_plan, readings)
                        break
                    except HotDevice as error:
                        print(error, flush=True)
                        raw["thermal_retries"].append({"job": name, "attempt": attempt,
                                                       "thermal": readings})
                        readings = []
                        save(args.output, raw)
                    except TraceLoss as error:
                        print(error, flush=True)
                        raw["trace_retries"].append({"job": name, "attempt": attempt,
                                                     "detail": str(error), "thermal": readings})
                        readings = []
                        save(args.output, raw)
                else:
                    raise RuntimeError(f"Retries exhausted at {name}")
                if name.startswith("round-"):
                    raw["rounds"].append({"id": name, **run_data})
                elif name == "smoke":
                    raw["smoke"] = run_data
                else:
                    raw["pixel_diffs"] = run_data
                    raw["pixel_thermal"] = readings
                save(args.output, raw)
        finally:
            if changed:
                try:
                    device.stop()
                    device.app(f"rm -rf {ROOT}")
                    device.shell(f"rm -f {INBOX}")
                    raw["device_cleanup"] = (
                        device.app(f"test ! -e {ROOT} && echo clean") == "clean"
                        and device.shell(f"test ! -e {INBOX} && echo clean") == "clean"
                    )
                finally:
                    try:
                        raw["settings_restored"] = {
                            key: restore_setting(phone, namespace, key, value)
                            for (namespace, key), value in saved.items()
                        }
                    finally:
                        raw["apk_restored"] = "Success" in (
                            device.adb("install", "-r", previous, timeout=120)
                            if previous.exists() else device.adb("uninstall", APP)
                        )
                        if previous.exists() and raw["apk_restored"]:
                            package_path = phone.shell(f"pm path {APP}").removeprefix("package:")
                            remote_hash = device.shell(f"sha256sum {package_path}").split()[0]
                            raw["apk_restored"] = remote_hash == raw["previous_apk_sha256"]
                        save(args.output, raw)
    if not (raw["device_cleanup"] and raw["apk_restored"]
            and all(raw["settings_restored"].values())):
        raise RuntimeError(f"Device restoration incomplete, see {args.output}")
    print(f"Device cleaned, settings and APK restored. Raw data: {args.output}", flush=True)


def main():
    """Reads the requested APK and optionally runs the preflight alone. / 读取目标 APK，支持只跑预检。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
