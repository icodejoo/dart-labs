"""Run the UI-stage benchmark on Android. / 在 Android 真机测量 UI 阶段。"""

import argparse
import hashlib
import json
import random
import re
import tempfile
import time
import zipfile
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows, save_json
from run_raster_cache_auto_r2 import APP, DEVICE, Phone, sha256

ROOT = f"/sdcard/Android/data/{APP}/files/xvg-ui-stage"
INBOX = "/data/local/tmp/xvg-ui-stage-inbox"
LIB_HASH = "3cc70a8dd6f23a80aa5af0811dc25c63979c95e0dc7936918da473a53869403f"
HEAVY = ("web-543", "web-544", "web-545", "web-150", "web-469", "web-078",
         "web-002", "web-123", "aurora", "legacy-014")
MEDIUM = ("web-103", "web-056", "web-075", "web-029")
ICONS = ("mdi-0", "mdi-749")
TRIALS = 5
ROUNDS = 3


def verify_apk(apk, source_so):
    """Verify the selected library and APK asset inventory. / 核对源 so、APK 内 so 及素材清单。"""
    with zipfile.ZipFile(apk) as package:
        name = "lib/arm64-v8a/libxvg.so"
        if package.namelist().count(name) != 1:
            raise RuntimeError("Missing or duplicate APK library")
        with package.open(name) as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
        assets = sorted(name for name in package.namelist() if name.startswith("assets/"))
    if digest != LIB_HASH or sha256(source_so) != digest:
        raise RuntimeError(f"Unexpected library SHA-256: {digest}")
    if any(name.lower().endswith((".svg", ".svgz")) for name in assets):
        raise RuntimeError("The APK contains SVG assets")
    return digest, assets


def stage(phone, path, name):
    """Transfer runtime data using a fixed inbox name. / 使用固定的中转名传入运行时数据。"""
    try:
        phone.adb("push", str(path), INBOX, timeout=120)
        phone.app(f"cp {INBOX} {ROOT}/{name}")
    finally:
        phone.shell(f"rm -f {INBOX}")


def thermal(phone):
    """Capture Android thermal status and live HAL temperatures. / 记录系统热状态及 HAL 当前温度。"""
    data = phone.shell("date +%s%3N; dumpsys thermalservice")
    status = re.search(r"(?m)^Thermal Status:\s*(\d+)\s*$", data)
    current = data.split("Current temperatures from HAL:", 1)[-1]
    sensors = re.findall(r"mValue=([\d.]+), mType=\d+, mName=(AP|SKIN|BAT),", current)
    if status is None:
        raise RuntimeError("Thermal status unavailable")
    return {"epoch_ms": int(data.splitlines()[0]), "status": int(status[1]),
            "celsius": {name: float(value) for value, name in sensors}}


def restore_setting(phone, namespace, name, previous):
    """Restore and verify one numeric Android setting. / 恢复并验证一项数字型 Android 设置。"""
    if previous == "null":
        phone.shell(f"settings delete {namespace} {name}")
    elif re.fullmatch(r"\d+(?:\.\d+)?", previous):
        phone.shell(f"settings put {namespace} {name} {previous}")
    else:
        raise RuntimeError(f"Invalid saved Android setting: {name}")
    return phone.shell(f"settings get {namespace} {name}") == previous


def validate_round(data, plan):
    """Check every stage, scenario and first-frame marker before accepting a round. / 只接收分段、场景及首帧完整的轮次。"""
    expected = {(sample, trial) for sample in plan["samples"]
                for trial in range(1, plan["trials"] + 1)}
    if data["round"] != plan["round"]:
        raise RuntimeError("Unexpected round number")
    phases = data["frame_phases"]
    frame_number = phases.index("frameNumber")
    reported = {frame[frame_number] for frame in data["frames"]}
    for key in ("stages", "scenarios"):
        rows = data[key]
        if len(rows) != len(expected) or {(row["id"], row["trial"]) for row in rows} != expected:
            raise RuntimeError(f"Missing or duplicate {key} trials")
        for row in rows:
            times = row["times_us"]
            order = [times[name] for name in ("call", "call_return", "decode",
                                              "decode_done", "record", "record_done")]
            expected_dispatch = "worker" if key == "stages" or row["units"] >= 16384 else "sync"
            if order != sorted(order) or row["bytes"] <= 0 or row["dispatch"] != expected_dispatch:
                raise RuntimeError(f"Invalid timing or wire data for {row['id']}")
            if key == "scenarios" and times["first_art_frame"] not in reported:
                raise RuntimeError(f"First artwork frame missing for {row['id']}")


def measure(phone, scratch, plan):
    """Capture one fresh app process and stop if thermal status rises. / 每轮从新进程采集，热状态上升即停测。"""
    phone.stop()
    phone.app(f"rm -f {ROOT}/status {ROOT}/result.json {ROOT}/error-stack")
    save_json(scratch / "plan.json", plan)
    stage(phone, scratch / "plan.json", "plan.json")
    readings = [thermal(phone)]
    deadline = time.monotonic() + 600
    while readings[-1]["status"]:
        if time.monotonic() >= deadline:
            raise RuntimeError("The phone did not cool within ten minutes")
        print(f"等待降温，thermal={readings[-1]['status']}", flush=True)
        time.sleep(12)
        readings.append(thermal(phone))
    launch_index = len(readings) - 1
    phone.launch()
    pid = phone.pid()
    deadline = time.monotonic() + 300
    started = time.monotonic()
    backend = None
    progress = ""
    try:
        while time.monotonic() < deadline:
            readings.append(thermal(phone))
            if readings[-1]["status"]:
                return {"round": plan["round"], "thermal": readings, "launch_index": launch_index}
            status = phone.adb("exec-out", f"run-as {APP} sh -c '"
                               f"if [ -f {ROOT}/status ]; then cat {ROOT}/status; fi'")
            if backend is None:
                backend = phone.backend(pid)
            if status == "done":
                if backend != "Impeller Vulkan":
                    raise RuntimeError("Impeller Vulkan was not detected")
                result = json.loads(phone.adb("exec-out", f"run-as {APP} cat {ROOT}/result.json"))
                return {**result, "thermal": readings, "launch_index": launch_index,
                        "backend": backend, "elapsed_s": time.monotonic() - started}
            if status.startswith("error"):
                stack = phone.app(f"cat {ROOT}/error-stack")
                raise RuntimeError(f"{status}\n{stack}")
            if pid is None or phone.pid() != pid:
                raise RuntimeError(f"App exited at {progress}: {phone.exit_reason(pid)}")
            if status and status != progress:
                progress = status
                print(f"第 {plan['round']} 轮 {progress}", flush=True)
            time.sleep(2)
        raise RuntimeError(f"Round timed out at {progress}")
    finally:
        phone.stop()


def run(args):
    """Install the verified APK and restore the device after all rounds. / 安装已核验 APK，完成各轮后恢复设备。"""
    digest, assets = verify_apk(args.apk, args.so)
    print(f"APK arm64-v8a/libxvg.so SHA-256 {digest}，SVG 素材数 0", flush=True)
    corpus = {row["id"]: row for row in manifest_rows(args.corpus)}
    selected = HEAVY + MEDIUM + ICONS
    paths = {sample: args.corpus / "files" / corpus[sample]["file"]
             for sample in selected if sample.startswith("web-")}
    paths.update({"aurora": Path("assets/raster_cache_aurora.svg"), "legacy-014": args.legacy_svg})
    if any(not path.is_file() for path in paths.values()):
        raise RuntimeError("At least one runtime input is unavailable")
    phone = Phone(args.device)
    settings = {key: phone.shell(f"settings get {key[0]} {key[1]}") for key in (
        ("global", "stay_on_while_plugged_in"), ("system", "min_refresh_rate"),
        ("system", "peak_refresh_rate"))}
    result = {
        "device": args.device, "model": phone.shell("getprop ro.product.model"),
        "android": phone.shell("getprop ro.build.version.release"), "apk_so_sha256": digest,
        "apk_assets": assets, "rounds": [], "thermal_retries": [],
        "groups": {"specified": HEAVY, "medium": MEDIUM, "mdi": ICONS},
    }
    with tempfile.TemporaryDirectory(prefix="xvg-ui-stage-") as directory:
        scratch = Path(directory)
        previous = scratch / "previous.apk"
        installed = phone.shell(f"pm path {APP}").splitlines()
        if installed:
            if len(installed) != 1 or not installed[0].startswith("package:"):
                raise RuntimeError("Existing benchmark APK cannot be backed up as one file")
            phone.adb("pull", installed[0].removeprefix("package:"), str(previous), timeout=120)
        modified = False
        try:
            if "Success" not in phone.adb("install", "-r", str(args.apk), timeout=120):
                raise RuntimeError("APK installation failed")
            modified = True
            phone.shell("settings put system peak_refresh_rate 120.0; "
                        "settings put system min_refresh_rate 120.0; "
                        "input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard; svc power stayon true")
            phone.app(f"mkdir -p {ROOT}")
            for sample, path in paths.items():
                stage(phone, path, f"{sample}.svg")
            for number in range(1, ROUNDS + 1):
                order = list(selected)
                random.Random(20261127 + number).shuffle(order)
                plan = {"round": number, "trials": TRIALS, "samples": order}
                for _ in range(3):
                    measured = measure(phone, scratch, plan)
                    if "stages" in measured:
                        try:
                            validate_round(measured, plan)
                        except Exception:
                            result["validation_failure"] = measured
                            raise
                        result["rounds"].append(measured)
                        save_json(args.output, result)
                        print(f"第 {number} 轮完成，{measured['elapsed_s']:.1f}s", flush=True)
                        break
                    result["thermal_retries"].append(measured)
                else:
                    raise RuntimeError(f"Round {number} repeatedly exceeded thermal status 0")
        finally:
            try:
                if modified:
                    phone.stop()
                    phone.app(f"rm -rf {ROOT}")
                    phone.shell(f"rm -f {INBOX}")
                    result["device_cleanup"] = (
                        phone.app(f"test ! -e {ROOT} && echo clean") == "clean"
                        and phone.shell(f"test ! -e {INBOX} && echo clean") == "clean")
            finally:
                try:
                    if modified:
                        result["settings_restored"] = {
                            name: restore_setting(phone, namespace, name, value)
                            for (namespace, name), value in settings.items()}
                finally:
                    if modified:
                        result["apk_restored"] = "Success" in (
                            phone.adb("install", "-r", str(previous), timeout=120)
                            if previous.exists() else phone.adb("uninstall", APP))
                    save_json(args.output, result)
                    print(f"设备清理 {result.get('device_cleanup')}，APK 恢复 {result.get('apk_restored')}",
                          flush=True)


def main():
    """Load host paths without embedding illustration content or identity. / 读取主机路径，无需嵌入插画内容或身份。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--apk", type=Path, default=Path(".dart_tool/xvg-ui-stage-profile.apk"))
    parser.add_argument("--so", type=Path,
                        default=Path("../../rust/target/aarch64-linux-android/release/libxvg.so"))
    parser.add_argument("--output", type=Path, default=Path("../raster_cache_auto_ui_stage_raw.json"))
    parser.add_argument("--legacy-svg", type=Path, required=True, help="Runtime-only local input")
    run(parser.parse_args())


if __name__ == "__main__":
    main()
