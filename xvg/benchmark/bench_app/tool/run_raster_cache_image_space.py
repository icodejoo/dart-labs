"""Drive the image-space profile APK on one Android device."""
import argparse
import hashlib
import json
import math
import random
import re
import statistics
import subprocess
import time
import zipfile
from pathlib import Path

HEAVY = {'web-469': 'map__International-recognition-of-the-State-o.svg', 'web-543': 'pattern__Elementary-cellular-automaton-193.svg'}
MEDIUM = (
    ('web-161', 'clipart__programmers-working.svg', 101, 1089),
    ('web-327', 'flag__flag-icons-flags-1x1-fj.svg', 101, 3463),
    ('web-400', 'illustration__Cartoon-Woman-Dealing-With-Money-Excelle.svg', 104, 12715),
    ('web-372', 'game__kenney-Art-5190-files-Platformer-assets--3.svg', 430, 15660),
    ('web-274', 'effect__Window-function-and-frequency-response-C.svg', 105, 8480),
    ('web-124', 'clipart__honeycomb-3d-icon.svg', 106, 1611),
    ('web-326', 'flag__flag-icons-flags-1x1-do.svg', 106, 7041),
    ('web-329', 'flag__flag-icons-flags-1x1-gs.svg', 111, 3872),
    ('web-648', 'tech__Human-Neuroaxis-as.svg', 118, 16860),
    ('web-649', 'tech__Human-Neuroaxis-bn.svg', 118, 16860),
    ('web-163', 'clipart__red-anchor.svg', 151, 16942),
    ('web-597', 'pattern__vignette-3.svg', 1, 17168),
    ('web-222', 'clipart__work-clown.svg', 115, 11690),
    ('web-584', 'pattern__owl-perched-on-skull-and-book-vintage-en.svg', 1, 17257),
    ('web-332', 'flag__flag-icons-flags-1x1-me.svg', 116, 9284),
    ('web-393', 'humaaans__humaaans-Flat-Assets-Single-Pieces-Scene-2.svg', 117, 3575),
    ('web-419', 'illustration__Kern-County-California-Incorporated-and-.svg', 119, 8574),
    ('web-173', 'clipart__sicily-triskelion.svg', 123, 1876),
    ('web-200', 'clipart__tree70.svg', 368, 18598),
    ('web-228', 'diagram__Coradir-TITO-selection-flowchart-es.svg', 126, 694),
    ('web-426', 'illustration__Seagull-rising-with-fish.svg', 127, 1942),
    ('web-602', 'pattern__young-woman-with-flower-in-hair-holds-ma.svg', 1, 19288),
    ('web-322', 'flag__flag-icons-flags-1x1-ad.svg', 129, 4384),
    ('web-675', 'text__Romanian-Legacy-Keyboard.svg', 129, 4274),
    ('web-333', 'flag__flag-icons-flags-1x1-sh-hl.svg', 130, 4615),
    ('web-343', 'flag__flag-icons-flags-4x3-sh-hl.svg', 130, 4710),
    ('web-035', 'chart__Symmetric-group-4-Cayley-graph-1-5-21-Na.svg', 134, 3114),
    ('web-132', 'clipart__julie-de-graag-two-owls.svg', 2, 20131),
    ('web-116', 'clipart__green-winged-dragon-standing.svg', 4, 20335),
    ('web-398', 'illustration__BlankMap-USA-states-Canada-provinces-HI-.svg', 136, 11573),
    ('web-482', 'map__ND-Williams-County-Epping.svg', 67, 20559),
    ('web-330', 'flag__flag-icons-flags-1x1-gt.svg', 139, 4421),
    ('web-142', 'clipart__moon-viewing-scene.svg', 144, 3095),
    ('web-115', 'clipart__green-tree-ecology-symbol.svg', 146, 2868),
    ('web-663', 'text__HU-Keyboard-Layout-V2-EN-Legend.svg', 146, 2116),
    ('web-653', 'tech__Scheme-ant-worker-anatomy-ar.svg', 151, 4597),
)

APP = "com.example.bench_app"
ROOT = f"/sdcard/Android/data/{APP}/files/xvg-image-space"
SCENARIOS = ("route", "dialog", "hero", "list48", "list200", "zoom", "icons")
MODES = ("off", "final")
STATIONARY_ROOT = f"/sdcard/Android/data/{APP}/files/xvg-auto-mode"
STATIONARY_CASES = [("web-543", "48"), ("aurora", "200"), ("web-469", "48"),
                    ("web-274", "48"), ("legacy-014", "full")]
EXPECTED_SO = "86463a7be4004ef0c6aed40a910663eb0355bb43d718080fd441f685d2fc41bd"
BENCH = Path(__file__).resolve().parents[2]


class Device:
    """Keep every adb command on the nominated device."""

    def __init__(self, serial):
        self.serial = serial

    def adb(self, *args, binary=False, timeout=60):
        result = subprocess.run(["adb", "-s", self.serial, *map(str, args)],
                                capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(f"adb {args}: {result.stderr.decode(errors='replace')}")
        return result.stdout if binary else result.stdout.decode(errors="replace").strip()

    def shell(self, command):
        return self.adb("shell", command)

    def app(self, command):
        return self.shell(f"run-as {APP} sh -c '{command}'")

    def read(self, name, binary=False, root=ROOT):
        return self.adb("exec-out", f"run-as {APP} sh -c 'cat {root}/{name} 2>/dev/null || true'",
                        binary=binary)

    def stage(self, source, name, root=ROOT):
        inbox = "/data/local/tmp/xvg-image-space-inbox"
        try:
            self.adb("push", source, inbox)
            self.app(f"cp {inbox} {root}/{name}")
        finally:
            self.shell(f"rm -f {inbox}")

    def thermal(self):
        output = self.shell("date +%s%3N; dumpsys thermalservice")
        status = re.search(r"^Thermal Status:\s*(\d+)\s*$", output, re.MULTILINE)
        if status is None:
            raise RuntimeError("System thermal status missing")
        return [int(output.splitlines()[0]), int(status[1])]

    def stop(self):
        self.shell(f"am force-stop {APP}")


def digest(data):
    """Return a hex SHA-256. / 计算十六进制 SHA-256。"""
    return hashlib.sha256(data).hexdigest()


def plan(round_id):
    """Spread each mode across positions with a fixed rotation per round."""
    cases = []
    for index, scenario in enumerate(SCENARIOS):
        offset = (index + round_id - 1) % len(MODES)
        for mode in MODES[offset:] + MODES[:offset]:
            cases.append({"round": round_id, "scenario": scenario, "mode": mode})
    random.Random(20261127 + round_id).shuffle(cases)
    return cases


class RasterTrace:
    """Collect a narrow set of native engine snapshot events."""

    def __init__(self, device, pid, output):
        self.device = device
        self.output = output
        self.ready = output.with_suffix(output.suffix + ".ready")
        self.stop = output.with_suffix(output.suffix + ".stop")
        for path in (output, self.ready, self.stop):
            path.unlink(missing_ok=True)
        log = device.adb("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
        uri = re.search(r"VM service is listening on http://127\.0\.0\.1:(\d+)/(\S+/)", log)
        if uri is None:
            raise RuntimeError("VM service address missing from the profile process")
        self.port = device.adb("forward", "tcp:0", f"tcp:{uri[1]}")
        app_dir = BENCH / "bench_app"
        self.proc = subprocess.Popen(
            ["dart.bat", "--packages=.dart_tool/package_config.json",
             "tool/capture_raster_snapshots.dart", str(output)],
            cwd=app_dir, stdin=subprocess.PIPE, text=True, shell=True,
        )
        self.proc.stdin.write(f"http://127.0.0.1:{self.port}/{uri[2]}\n")
        self.proc.stdin.close()

    def poll_ready(self):
        if self.proc.poll() is not None:
            raise RuntimeError("VM trace collector exited before the cases finished")
        return self.ready.exists()

    def close(self):
        try:
            self.stop.touch()
            self.proc.wait(timeout=12)
        finally:
            self.device.adb("forward", "--remove", f"tcp:{self.port}")


def measure(device, scratch, cases, capture):
    """Start a fresh app process, sampling thermal state through completion."""
    device.stop()
    device.app(f"rm -f {ROOT}/status.txt {ROOT}/frames.jsonl {ROOT}/trace.ready")
    ids = set()
    workloads = {case["scenario"] for case in cases}
    if "route" in workloads:
        ids.update(HEAVY)
    if workloads & {"route", "dialog"}:
        ids.add("aurora")
    if capture or workloads & {"hero", "zoom"}:
        ids.add("web-469")
    if workloads & {"list48", "list200"}:
        ids.update(row[0] for row in MEDIUM)
    local = scratch / "plan.json"
    local.write_text(json.dumps({"ids": sorted(ids), "medium": [a[0] for a in MEDIUM],
                                 "cases": cases, "capture": capture, "trace": True}),
                     encoding="utf8")
    device.stage(local, "plan.json")
    thermal = [device.thermal()]
    while thermal[-1][1]:
        print(f"cooling from thermal={thermal[-1][1]}", flush=True)
        time.sleep(10)
        thermal.append(device.thermal())
    launch_status = device.shell(f"am start -W -n {APP}/.MainActivity")
    if "Status: ok" not in launch_status:
        raise RuntimeError(launch_status)
    pid = device.shell(f"pidof {APP}")
    last = None
    trace = None
    trace_started = False
    trace_file = scratch / f"native-{cases[0]['round']}.jsonl"
    deadline = time.monotonic() + 230
    try:
        while time.monotonic() < deadline:
            status = device.read("status.txt")
            thermal.append(device.thermal())
            if status and status != last:
                print(status, flush=True)
                last = status
            if status == "ready":
                if trace is None:
                    trace = RasterTrace(device, pid, trace_file)
                if not trace_started and trace.poll_ready():
                    device.app(f"touch {ROOT}/trace.ready")
                    trace_started = True
            if status == "done":
                break
            if status.startswith("error") or not device.shell(f"pidof {APP} || true"):
                raise RuntimeError(
                    f"App failed at {last}: {device.shell(f'dumpsys activity exit-info {APP}')[:1500]}"
                )
            time.sleep(1)
        else:
            raise RuntimeError(f"Timed out at {last}")
    finally:
        if trace is not None:
            trace.close()
    native_log = device.adb("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
    if "Using the Impeller rendering backend (Vulkan)" not in native_log:
        raise RuntimeError("Expected Impeller Vulkan is missing")
    rows = [json.loads(line) for line in device.read("frames.jsonl").splitlines()]
    if len(rows) != len(cases) + 1:
        raise RuntimeError(f"Expected {len(cases)} complete rows, got {len(rows) - 1}")
    slices = [json.loads(line) for line in trace_file.read_text().splitlines()]
    if not slices and any(row["requests"] for row in rows[1:]):
        raise RuntimeError("Native snapshot trace contained no Impeller snapshot slices")
    snapshots = []
    if capture:
        for mode in MODES:
            for zoom in (1, 4):
                name = f"{mode}-{zoom}.png"
                data = device.read(name, binary=True)
                if not data.startswith(b"\x89PNG"):
                    raise RuntimeError(f"Missing capture {name}")
                (scratch / name).write_bytes(data)
                snapshots.append(name)
    return {"device_view": rows[0], "rows": rows[1:], "thermal": thermal,
            "native_snapshots": slices, "snapshots": snapshots,
            "clarity": json.loads(device.read("clarity.json")) if capture else {}}


def percentile(values, fraction):
    """Read a non-interpolated nearest-rank percentile."""
    return sorted(values)[max(0, math.ceil(len(values) * fraction) - 1)]


def summarize(row, hz, snapshots):
    """Pair requests with submitting frames and summarize native raster intervals."""
    frames = row["frames"]
    if not frames:
        raise RuntimeError(f"No measured frames in {row['scenario']}/{row['mode']}")
    raster = [f[3] - f[2] for f in frames]
    frame_period = 1_000_000 / hz
    submitted = [max((f for f in frames if f[1] <= r[2]),
                     key=lambda f: f[1], default=None) for r in row["requests"]]
    in_window = [s for s in snapshots if row["start"] <= s[0] < row["end"]]
    overlaps = [f for f in frames if any(f[2] <= s[0] < f[3] for s in in_window)]
    intervals = [b[0] - a[0] for a, b in zip(frames, frames[1:])]
    return {
        "p50_us": percentile(raster, .50),
        "p90_us": percentile(raster, .90),
        "p99_us": percentile(raster, .99),
        "dropped_vsync": sum(max(0, round(interval / frame_period) - 1) for interval in intervals),
        "over_budget_frames": sum(f[3] - f[0] > frame_period for f in frames),
        "generation_count": len(row["requests"]),
        "generation_frame_peak_us": max((f[3] - f[2] for f in overlaps), default=None),
        "request_frame_peak_us": max((f[3] - f[2] for f in submitted if f), default=None),
        "native_snapshot_count": len(in_window),
        "native_snapshot_peak_us": max((s[1] - s[0] for s in in_window), default=None),
        "generation_wall_peak_us": max((r[4] - r[2] for r in row["requests"]), default=None),
        "max_bytes": max((v[1] for v in row["memory"]), default=0),
        "end_bytes": row["resident"],
        "frame_count": len(frames),
    }


def measure_stationary(device, scratch, round_id):
    """Run the original single-image spinner harness on the final implementation."""
    device.stop()
    device.app(f"rm -f {STATIONARY_ROOT}/status.txt {STATIONARY_ROOT}/frames.jsonl")
    local = scratch / "stationary-plan.json"
    local.write_text(json.dumps({"round": round_id, "illustrations": STATIONARY_CASES,
                                 "list_samples": [], "scroll_icons": False,
                                 "overflow_recheck": True}), encoding="utf8")
    device.stage(local, "plan.json", root=STATIONARY_ROOT)
    thermal = [device.thermal()]
    while thermal[-1][1]:
        print(f"cooling from thermal={thermal[-1][1]}", flush=True)
        time.sleep(10)
        thermal.append(device.thermal())
    launch_status = device.shell(f"am start -W -n {APP}/.MainActivity")
    if "Status: ok" not in launch_status:
        raise RuntimeError(launch_status)
    pid = device.shell(f"pidof {APP}")
    last = None
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        status = device.read("status.txt", root=STATIONARY_ROOT)
        thermal.append(device.thermal())
        if status and status != last:
            print(f"stationary {round_id}: {status}", flush=True)
            last = status
        if status == "done":
            break
        if status.startswith("error") or not device.shell(f"pidof {APP} || true"):
            raise RuntimeError(f"Stationary app stopped at {last}")
        time.sleep(1)
    else:
        raise RuntimeError(f"Stationary run timed out at {last}")
    log = device.adb("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
    if "Using the Impeller rendering backend (Vulkan)" not in log:
        raise RuntimeError("Expected Impeller Vulkan is missing")
    rows = [json.loads(line) for line in
            device.read("frames.jsonl", root=STATIONARY_ROOT).splitlines()]
    if len(rows) != 2 * len(STATIONARY_CASES):
        raise RuntimeError(f"Unexpected stationary case count: {len(rows)}")
    return {"round": round_id, "status": last, "thermal": thermal, "rows": rows}


def save_result(raw, output):
    """Save the compact raw observations under the repository size convention."""
    encoded = json.dumps(raw, ensure_ascii=False, separators=(",", ":")).encode()
    output.write_bytes(encoded + b"\n")
    print(f"raw {output} ({len(encoded)} B)", flush=True)


def print_report(path):
    """Recompute the three comparison tables directly from the raw frames."""
    data = json.loads(path.read_text(encoding="utf8"))
    print("| Scenario | Mode | p50 / p90 / p99 ms | Dropped | Requests | Native peak ms | MiB |")
    print("| --- | --- | ---: | ---: | ---: | ---: | ---: |")
    for scenario in SCENARIOS:
        for mode in MODES:
            rows = [summarize(row, batch["device_view"]["hz"], batch["native_snapshots"])
                    for batch in data["batches"] for row in batch["rows"]
                    if row["scenario"] == scenario and row["mode"] == mode]
            if not rows:
                continue
            def median(key):
                values = [row[key] for row in rows if row[key] is not None]
                return statistics.median(values) if values else 0
            timing = "/".join(f"{median(key) / 1000:.2f}"
                              for key in ("p50_us", "p90_us", "p99_us"))
            peak = median("native_snapshot_peak_us")
            peak_text = f"{peak / 1000:.2f}" if peak else "—"
            print(f"| {scenario} | {mode} | {timing} | {median('dropped_vsync'):g} | "
                  f"{median('generation_count'):g} | {peak_text} | {median('max_bytes') / 2**20:.2f} |")
    print()
    for batch in data["batches"]:
        if batch["clarity"]:
            print(json.dumps(batch["clarity"], indent=2))
    zoom = [row for batch in data["batches"] for row in batch["rows"]
            if row["scenario"] == "zoom" and row["mode"] == "final"]
    if zoom:
        def delay(row):
            hold = row["phases"]["hold4"]
            return (next(r[2] for r in row["requests"] if r[2] >= hold) - hold) / 1000
        print("Zoom regeneration delay ms:", statistics.median(delay(row) for row in zoom))
        print("Zoom endpoint MiB:", *(statistics.median(row["phases"][f"hold{s}_bytes"]
                                                         for row in zoom) / 2**20
                                     for s in (4, 1)))
    print("\n| Sample | Vector p50 ms | Final p50 ms | Paired savings ms | Textures / MiB | Ready ms |")
    print("| --- | ---: | ---: | ---: | ---: | ---: |")
    for sample, _ in STATIONARY_CASES:
        vector, final = [], []
        for batch in data["stationary"]:
            vector.append(next(row for row in batch["rows"]
                               if row["sample"] == sample and row["mode"] == "vector"))
            final.append(next(row for row in batch["rows"]
                              if row["sample"] == sample and row["mode"] == "automatic"))
        if not final:
            continue
        vectors = [percentile(row["raster_us"], .5) for row in vector]
        finals = [percentile(row["raster_us"], .5) for row in final]
        gain = statistics.median(v - a for v, a in zip(vectors, finals))
        tiles = statistics.median(row["tiles"] for row in final)
        mib = statistics.median(row["bytes"] for row in final) / 2**20
        ready = statistics.median(row["generation_us"] for row in final) / 1000
        label = "233KB 插画" if sample == "legacy-014" else sample
        print(f"| {label} | {statistics.median(vectors)/1000:.3f} | "
              f"{statistics.median(finals)/1000:.3f} | {gain/1000:.3f} | "
              f"{tiles:g} / {mib:.2f} | {ready:.1f} |")


def main():
    """Verify the APK, stage inputs, run requested rounds, and clean up."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", type=Path, help="Recompute tables from raw JSON without a device")
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--so", type=Path)
    parser.add_argument("--corpus", type=Path, help="Directory containing SVG files")
    parser.add_argument("--scratch", type=Path)
    parser.add_argument("--device", default="R5CY2359S7D")
    parser.add_argument("--output", type=Path, default=BENCH / "raster_cache_auto_image_space_raw.json")
    parser.add_argument("--input-svg", type=Path, help="Runtime-only 233KB illustration")
    parser.add_argument("--pilot", action="store_true")
    args = parser.parse_args()
    if args.report is not None:
        print_report(args.report)
        return
    if not all((args.apk, args.so, args.corpus, args.scratch)):
        parser.error("--apk, --so, --corpus and --scratch are required to measure")
    if not args.pilot and (args.input_svg is None or not args.input_svg.is_file()):
        parser.error("--input-svg must point to the local 233KB illustration")
    args.scratch.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.apk) as archive:
        native = digest(archive.read("lib/arm64-v8a/libxvg.so"))
        bundled_svg = [name for name in archive.namelist() if name.lower().endswith(".svg")]
    if native != EXPECTED_SO or native != digest(args.so.read_bytes()) or bundled_svg:
        raise RuntimeError(f"APK JNI mismatch or unexpected SVG assets: {bundled_svg}")
    print(f"APK so SHA-256 {native}", flush=True)
    raw = {"device": args.device, "apk_so_sha256": native, "backend": "Impeller Vulkan",
           "corpus": HEAVY, "medium": MEDIUM, "batches": [], "stationary": []}
    device = Device(args.device)
    raw["model"] = device.shell("getprop ro.product.model")
    raw["android"] = device.shell("getprop ro.build.version.release")
    stay_awake = device.shell("settings get global stay_on_while_plugged_in")
    previous_apk = args.scratch / "previous.apk"
    installed = device.shell(f"pm path {APP}")
    if installed.startswith("package:"):
        paths = installed.splitlines()
        if len(paths) != 1:
            raise RuntimeError("The existing benchmark APK is split and cannot be safely replaced")
        device.adb("pull", paths[0].removeprefix("package:"), previous_apk)
    modified = False
    try:
        install = device.adb("install", "-r", args.apk)
        if "Success" not in install:
            raise RuntimeError(install)
        modified = True
        device.shell("svc power stayon true")
        device.shell("input keyevent KEYCODE_WAKEUP")
        device.shell("wm dismiss-keyguard")
        device.app(f"mkdir -p {ROOT}")
        device.app(f"rm -f {STATIONARY_ROOT}/plan.json")
        sources = {sample: args.corpus / filename for sample, filename in HEAVY.items()}
        sources.update({sample: args.corpus / filename for sample, filename, _, _ in MEDIUM})
        sources["aurora"] = BENCH / "bench_app/assets/raster_cache_aurora.svg"
        for sample, path in sources.items():
            device.stage(path, f"{sample}.svg")
        for round_id in range(1, 4 if not args.pilot else 2):
            cases = plan(round_id)
            if args.pilot:
                cases = [case for case in cases if case["scenario"] == "zoom"]
            batch = measure(device, args.scratch, cases, capture=round_id == (1 if args.pilot else 3))
            if any(reading[1] for reading in batch["thermal"]):
                raise RuntimeError(f"Round {round_id} had a nonzero thermal state")
            raw["batches"].append(batch)
            for row in batch["rows"]:
                row["summary"] = summarize(row, batch["device_view"]["hz"],
                                           batch["native_snapshots"])
                print(f"{row['round']} {row['scenario']} {row['mode']} {row['summary']}", flush=True)
            save_result(raw, args.output)
        if not args.pilot:
            device.app(f"mkdir -p {STATIONARY_ROOT}/input")
            for sample, _ in STATIONARY_CASES:
                source = args.input_svg if sample == "legacy-014" else sources[sample]
                device.stage(source, f"input/{sample}.svg", root=STATIONARY_ROOT)
            for round_id in range(1, 4):
                for attempt in range(3):
                    batch = measure_stationary(device, args.scratch, round_id)
                    if not any(reading[1] for reading in batch["thermal"]):
                        break
                    print(f"Retrying stationary round {round_id} after thermal activity", flush=True)
                else:
                    raise RuntimeError(f"Stationary round {round_id} overheated")
                raw["stationary"].append(batch)
                save_result(raw, args.output)
    finally:
        if modified:
            device.stop()
            # The path is a constant rooted in the benchmark app's external files.
            device.app(f"rm -rf {ROOT} {STATIONARY_ROOT}")
            device.shell("rm -f /data/local/tmp/xvg-image-space-inbox")
            raw["device_cleanup"] = (device.app(
                f"test ! -e {ROOT} && test ! -e {STATIONARY_ROOT} && echo clean"
            ) == "clean" and device.shell(
                "test ! -e /data/local/tmp/xvg-image-space-inbox && echo clean"
            ) == "clean")
            if stay_awake == "null":
                device.shell("settings delete global stay_on_while_plugged_in")
            else:
                device.shell(f"settings put global stay_on_while_plugged_in {stay_awake}")
            raw["stay_awake_restored"] = (device.shell("settings get global stay_on_while_plugged_in")
                                          == stay_awake)
            if previous_apk.exists():
                raw["previous_apk_restored"] = "Success" in device.adb("install", "-r", previous_apk)
            else:
                raw["temporary_apk_uninstalled"] = "Success" in device.adb("uninstall", APP)
        if raw["batches"]:
            save_result(raw, args.output)


if __name__ == "__main__":
    main()
