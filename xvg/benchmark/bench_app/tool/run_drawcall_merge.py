"""Compare the two verified profile APKs. / 对比两份已核验的 profile APK。"""

import argparse
import hashlib
import json
import random
import tempfile
import time
import zipfile
import zlib
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows, save_json
from run_raster_cache_auto_r2 import APP, DEVICE, Phone, sha256
from run_raster_cache_image_space import Device, RasterTrace
from run_ui_thread_decode_record import (
    INBOX,
    LIB_HASH,
    ROOT,
    restore_setting,
    stage,
    thermal,
    validate_round,
)

SAMPLES = (
    "web-543", "web-544", "web-545", "web-150", "web-469", "web-078",
    "web-002", "aurora", "legacy-014", "mdi-0", "mdi-749",
)
ROUNDS = 3
SETTINGS = (
    ("global", "stay_on_while_plugged_in"),
    ("system", "min_refresh_rate"),
    ("system", "peak_refresh_rate"),
)


def verify(apk, library, version):
    """Checks the requested binary and absence of packaged corpus files. / 核对目标二进制和语料未打入 APK。"""
    with zipfile.ZipFile(apk) as package:
        entry = "lib/arm64-v8a/libxvg.so"
        if package.namelist().count(entry) != 1:
            raise RuntimeError("Missing or duplicate APK library")
        with package.open(entry) as binary:
            digest = hashlib.file_digest(binary, "sha256").hexdigest()
        assets = [name for name in package.namelist() if name.startswith("assets/")]
        if any(name.lower().endswith((".svg", ".svgz")) for name in assets):
            raise RuntimeError("SVG asset found in profile APK")
    if digest != sha256(library) or (version == "old" and digest != LIB_HASH):
        raise RuntimeError(f"Unexpected {version} profile APK library {digest}")
    return {"so_sha256": digest, "apk_sha256": sha256(apk), "assets": assets}


def capture(phone, device, scratch, plan, version):
    """Collects one process with native Impeller snapshots and heat readings. / 采集一次独立进程的 Impeller 快照及热状态。"""
    phone.stop()
    phone.app(f"rm -f {ROOT}/status {ROOT}/result.json {ROOT}/trace.ready")
    save_json(scratch / "plan.json", plan)
    stage(phone, scratch / "plan.json", "plan.json")
    readings = [thermal(phone)]
    cooldown = time.monotonic() + 600
    while readings[-1]["status"]:
        if time.monotonic() >= cooldown:
            raise RuntimeError("Device thermal status did not return to zero")
        print(f"等待降温，thermal={readings[-1]['status']}", flush=True)
        time.sleep(10)
        readings.append(thermal(phone))
    before = len(readings) - 1
    phone.launch()
    pid = phone.pid()
    name = f"{version}-{plan['round']}"
    trace_path = scratch / f"{name}.jsonl"
    trace = None
    trace_started = False
    deadline = time.monotonic() + 240
    last = ""
    try:
        while time.monotonic() < deadline:
            readings.append(thermal(phone))
            state = device.read("status", root=ROOT)
            if state != last:
                print(f"{name} {state}", flush=True)
                last = state
            if state == "ready":
                if trace is None:
                    trace = RasterTrace(device, pid, trace_path)
                if not trace_started and trace.poll_ready():
                    phone.app(f"touch {ROOT}/trace.ready")
                    trace_started = True
            if state == "done":
                break
            if state.startswith("error"):
                raise RuntimeError(f"{name}: {state}\n{device.read('error-stack', root=ROOT)}")
            if phone.pid() != pid:
                raise RuntimeError(f"{name}: app exited at {state}: {phone.exit_reason(pid)}")
            time.sleep(1)
        else:
            raise RuntimeError(f"{name}: timed out at {last}")
    finally:
        if trace is not None:
            trace.close()

    if phone.backend(pid) != "Impeller Vulkan":
        raise RuntimeError("Impeller Vulkan unavailable")
    data = json.loads(device.read("result.json", root=ROOT))
    validate_round(data, plan)
    if len(data["jumps"]) != len(plan["samples"]) or not data["icon_scroll"]:
        raise RuntimeError("Missing route or 1,000-icon scroll data")
    snapshots = [json.loads(line) for line in trace_path.read_text().splitlines()]
    if not snapshots and any(row["requests"] for row in data["scenarios"]):
        raise RuntimeError("Missing native snapshots for recorded requests")
    data.update(thermal=readings, launch_index=before, native_snapshots=snapshots)
    pixels = {}
    for sample in plan["samples"]:
        pixels[sample] = zlib.decompress(device.read(f"{sample}.rgba.z", binary=True, root=ROOT))
    phone.stop()
    return data, pixels


def compare(old, new):
    """Measures changed RGBA pixels and maximum/mean channel differences. / 统计 RGBA 变化像素和通道差极值、均值。"""
    if len(old) != len(new) or len(old) % 4:
        raise RuntimeError("RGBA dimensions differ")
    count = len(old) // 4
    changed = maximum = total = 0
    if old != new:
        for i in range(0, len(old), 4):
            a, b = old[i:i + 4], new[i:i + 4]
            if a != b:
                changed += 1
                diffs = [abs(x - y) for x, y in zip(a, b)]
                maximum = max(maximum, *diffs)
                total += sum(diffs)
    return {"pixels": count, "changed": changed, "max_channel_delta": maximum,
            "mean_channel_delta": total / len(old)}


def run(args):
    """Alternates APK order and restores the device even after failure. / 交替测试 APK，遇错也恢复设备。"""
    artifacts = {"old": (args.old_apk, args.old_so), "new": (args.new_apk, args.new_so)}
    builds = {name: verify(apk, so, name) for name, (apk, so) in artifacts.items()}
    phone, device = Phone(args.device), Device(args.device)
    result = {"model": phone.shell("getprop ro.product.model"),
              "android": phone.shell("getprop ro.build.version.release"),
              "device": args.device, "builds": builds, "rounds": [], "pixel_diffs": [],
              "thermal_retries": []}
    rows = {row["id"]: row for row in manifest_rows(args.corpus)}
    inputs = {sample: args.corpus / "files" / rows[sample]["file"]
              for sample in SAMPLES if sample.startswith("web-")}
    inputs.update({"aurora": Path("assets/raster_cache_aurora.svg"),
                   "legacy-014": args.legacy_svg})
    if not all(path.is_file() for path in inputs.values()):
        raise RuntimeError("A runtime-only SVG input is unavailable")
    settings = {key: phone.shell(f"settings get {key[0]} {key[1]}") for key in SETTINGS}
    for version, build in builds.items():
        print(f"{version} APK so SHA-256 {build['so_sha256']}", flush=True)
    with tempfile.TemporaryDirectory(prefix="xvg-drawcall-") as directory:
        scratch = Path(directory)
        installed = phone.shell(f"pm path {APP}").splitlines()
        previous = scratch / "previous.apk"
        if installed:
            if len(installed) != 1 or not installed[0].startswith("package:"):
                raise RuntimeError("Cannot restore an existing split benchmark APK")
            phone.adb("pull", installed[0].removeprefix("package:"), str(previous), timeout=120)
        modified = False
        try:
            for round_number in range(1, ROUNDS + 1):
                order = list(SAMPLES)
                random.Random(20261127 + round_number).shuffle(order)
                plan = {"round": round_number, "trials": 1, "samples": order, "drawcall": True}
                images = {}
                for version in (("old", "new") if round_number % 2 else ("new", "old")):
                    apk = artifacts[version][0]
                    if "Success" not in phone.adb("install", "-r", str(apk), timeout=120):
                        raise RuntimeError(f"Cannot install {version} profile APK")
                    if not modified:
                        modified = True
                        phone.shell("settings put system peak_refresh_rate 120.0; "
                                    "settings put system min_refresh_rate 120.0; "
                                    "input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard; svc power stayon true")
                        phone.app(f"mkdir -p {ROOT}")
                        for sample, path in inputs.items():
                            stage(phone, path, f"{sample}.svg")
                    for _ in range(3):
                        data, images[version] = capture(phone, device, scratch, plan, version)
                        if max(row["status"] for row in data["thermal"][data["launch_index"]:]) == 0:
                            result["rounds"].append({"version": version, **data})
                            save_json(args.output, result)
                            break
                        result["thermal_retries"].append({"version": version, "round": round_number,
                                                          "thermal": data["thermal"]})
                    else:
                        raise RuntimeError("Thermal load stayed above status zero")
                result["pixel_diffs"].append({
                    "round": round_number,
                    "samples": {sample: compare(images["old"][sample], images["new"][sample])
                                for sample in SAMPLES},
                })
                save_json(args.output, result)
        finally:
            try:
                if modified:
                    phone.stop()
                    phone.app(f"rm -rf {ROOT}")
                    phone.shell(f"rm -f {INBOX}")
                    result["device_cleanup"] = (phone.app(f"test ! -e {ROOT} && echo clean") == "clean"
                                                and phone.shell(f"test ! -e {INBOX} && echo clean") == "clean")
            finally:
                try:
                    if modified:
                        result["settings_restored"] = {
                            name: restore_setting(phone, namespace, name, value)
                            for (namespace, name), value in settings.items()
                        }
                finally:
                    if modified:
                        result["apk_restored"] = "Success" in (
                            phone.adb("install", "-r", str(previous), timeout=120)
                            if previous.exists() else phone.adb("uninstall", APP))
                    save_json(args.output, result)
                    print(f"设备清理 {result.get('device_cleanup')}，APK 恢复 {result.get('apk_restored')}",
                          flush=True)


def main():
    """Loads build and runtime-only input paths. / 读取构建路径及只在运行时使用的素材路径。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--output", type=Path, default=Path("../raster_cache_auto_drawcall_raw.json"))
    parser.add_argument("--legacy-svg", type=Path, required=True)
    for name in ("old-apk", "old-so", "new-apk", "new-so"):
        parser.add_argument(f"--{name}", type=Path, required=True)
    run(parser.parse_args())


if __name__ == "__main__":
    main()
