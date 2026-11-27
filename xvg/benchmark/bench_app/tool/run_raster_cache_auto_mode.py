"""Run the automatic-cache comparison with runtime-only SVG inputs."""

import argparse
import json
import time
from pathlib import Path

from raster_cache_auto_r2_plan import manifest_rows, save_json
from run_raster_cache_auto_r2 import APP, DEVICE, Phone, apk_hash, sha256

ROOT = f"/sdcard/Android/data/{APP}/files/xvg-auto-mode"
INBOX = "/data/local/tmp/bench-xvg-auto-mode-inbox"
PUBLIC_CASES = [("web-543", "48"), ("aurora", "200"), ("web-469", "48"),
                ("web-274", "48")]
LIST_CASES = ["web-274", "web-222", "web-400"]
PRIVATE_CASE = ("legacy-014", "full")


def stage(phone, local, relative):
    """Push the input using a fixed device-only name."""
    phone.adb("push", str(local), INBOX, timeout=120)
    try:
        phone.app(f"cp {INBOX} {ROOT}/{relative}")
    finally:
        phone.shell(f"rm -f {INBOX}")


def read(phone, name):
    """Read a measurement file when the Activity has written it."""
    path = f"{ROOT}/{name}"
    return phone.adb("exec-out", f"run-as {APP} sh -c 'if [ -f {path} ]; then cat {path}; fi'")


def run_round(phone, round_id, plan_file, plan):
    """Run one fresh app process, polling temperature throughout the round."""
    phone.stop()
    phone.app(f"rm -f {ROOT}/status.txt {ROOT}/status.tmp {ROOT}/frames.jsonl")
    save_json(plan_file, {**plan, "round": round_id})
    stage(phone, plan_file, "plan.json")
    thermal = phone.cool()
    phone.launch()
    deadline = time.monotonic() + 220
    last_status = None
    while time.monotonic() < deadline:
        thermal.append(phone.thermal())
        if thermal[-1][1]:
            phone.stop()
            return {"round": round_id, "status": "thermal_restart", "thermal": thermal}
        status = read(phone, "status.txt")
        if status != last_status:
            print(f"round {round_id}: {status or 'starting'}", flush=True)
            last_status = status
        if status == "done" or status.startswith("error"):
            rows = [json.loads(line) for line in read(phone, "frames.jsonl").splitlines()]
            return {"round": round_id, "status": status, "backend": phone.backend(phone.pid()),
                    "thermal": thermal, "measurements": rows}
        time.sleep(2)
    raise TimeoutError(f"Round {round_id} reached its deadline at {last_status}")


def main():
    """Verify the APK, copy the runtime inputs and always clean up the phone."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-svg", "-InputSvg", dest="input_svg", type=Path, required=True)
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--apk", type=Path, default=Path("build/app/outputs/flutter-apk/app-profile.apk"))
    parser.add_argument("--output", type=Path, default=Path("../raster_cache_auto_mode_raw.json"))
    parser.add_argument("--scratch", type=Path, default=Path(".dart_tool/raster_cache_auto_mode"))
    args = parser.parse_args()
    if not args.input_svg.is_file():
        parser.error("The runtime-only illustration input must be a local file")
    digest = apk_hash(args.apk)
    expected = sha256("../../rust/target/aarch64-linux-android/release/libxvg.so")
    if digest != expected:
        raise RuntimeError("APK so differs from the working tree release so")
    phone = Phone(DEVICE)
    args.scratch.mkdir(parents=True, exist_ok=True)
    manifest = {row["id"]: row["file"] for row in manifest_rows(args.corpus)}
    illustrations = [*PUBLIC_CASES[:3], PRIVATE_CASE, *PUBLIC_CASES[3:]]
    plan = {"illustrations": illustrations, "list_samples": LIST_CASES}
    record = {
        "device": DEVICE, "model": phone.shell("getprop ro.product.model"),
        "apk_so_sha256": digest, "apk_sha256": sha256(args.apk),
        "build_mode": "profile",
        "rounds": [], "plan": plan,
    }
    previous = phone.shell("settings get global stay_on_while_plugged_in")
    try:
        phone.adb("install", "-r", str(args.apk), timeout=160)
        phone.shell("settings put global stay_on_while_plugged_in 7")
        phone.shell("input keyevent KEYCODE_WAKEUP")
        phone.shell("wm dismiss-keyguard")
        phone.app(f"mkdir -p {ROOT}/input")
        for id in dict.fromkeys([*(id for id, _ in illustrations), *LIST_CASES]):
            if id == PRIVATE_CASE[0]:
                source = args.input_svg
            elif id == "aurora":
                source = Path("assets/raster_cache_aurora.svg")
            else:
                source = args.corpus / "files" / manifest[id]
            stage(phone, source, f"input/{id}.svg")
        for round_id in range(1, 4):
            for _ in range(3):
                result = run_round(phone, round_id, args.scratch / "plan.json", plan)
                record["rounds"].append(result)
                save_json(args.output, record)
                if result["status"] != "thermal_restart":
                    break
            if result["status"] != "done" or result["backend"] != "Impeller Vulkan":
                raise RuntimeError(f"Round {round_id} failed: {result['status']}")
    finally:
        phone.stop()
        phone.app(f"rm -rf {ROOT}")
        phone.shell(f"rm -f {INBOX}")
        if previous == "null":
            phone.shell("settings delete global stay_on_while_plugged_in")
        else:
            phone.shell(f"settings put global stay_on_while_plugged_in {previous}")
        clean = phone.app(f"test ! -e {ROOT} && test ! -e {INBOX} && echo clean")
        record["device_temporary_files_removed"] = clean == "clean"
        record["wake_setting_restored"] = (
            phone.shell("settings get global stay_on_while_plugged_in") == previous
        )
        save_json(args.output, record)


if __name__ == "__main__":
    main()
