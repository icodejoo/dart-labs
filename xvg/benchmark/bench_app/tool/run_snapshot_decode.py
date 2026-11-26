"""在 Android 真机上生成和重放磁盘位图快照。"""

import argparse
import base64
import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

from PIL import Image, __version__ as pillow_version, features


APP = "com.example.bench_app"
REMOTE = "files/xvg-snapshot"
ACTIVITY = f"{APP}/.MainActivity"
BENCH = Path(__file__).resolve().parents[1]
REPO = next((parent for parent in BENCH.parents if (parent / ".git").exists()), BENCH.parents[1])
DEFAULT_DEVICE = "R5CY2359S7D"


class Phone:
    """通过 adb 和应用 UID 访问一个独立的测量目录。"""

    def __init__(self, serial):
        """固定本次测量的 adb 序列号。"""
        self.adb = ["adb", "-s", serial]

    def run(self, *args, data=None):
        """以字节流调用 adb，保留 PNG 等二进制格式。"""
        return subprocess.run(
            [*self.adb, *args], input=data, capture_output=True, check=True, timeout=35
        ).stdout

    def app_shell(self, command):
        """使用应用 UID 执行由固定常量组成的设备命令。"""
        return self.run("shell", f"run-as {APP} sh -c '{command}'")

    def put(self, name, data):
        """将字节直接写入 Android 应用私有目录。"""
        # Windows adb shell 的 stdin 可能把二进制 0x1A 识别为 EOF。
        self.run(
            "shell", "-T", f"run-as {APP} sh -c 'base64 -d > {REMOTE}/{name}'",
            data=base64.b64encode(data),
        )
        size = int(self.app_shell(f"wc -c < {REMOTE}/{name}"))
        if size != len(data):
            raise RuntimeError(f"ADB byte count for {name}: {size} of {len(data)}")

    def get(self, name):
        """直接读取 Android 应用私有目录中的文件。"""
        return self.run("exec-out", "run-as", APP, "cat", f"{REMOTE}/{name}")

    def trial(self, job):
        """冷起一个进程，验证身份、后端和本轮返回的指标。"""
        self.run("shell", "am", "force-stop", APP)
        self.app_shell(
            f"rm -f {REMOTE}/result.json {REMOTE}/result.tmp {REMOTE}/capture.png"
        )
        self.put("job.json", json.dumps(job, ensure_ascii=True).encode())
        thermal = self.run("shell", "dumpsys", "thermalservice")
        launch = self.run("shell", "am", "start", "-W", "-n", ACTIVITY)
        if b"Status: ok" not in launch:
            raise RuntimeError(f"Launch failed for {job['id']}: {launch!r}")
        deadline = time.monotonic() + 18
        while time.monotonic() < deadline:
            raw = self.app_shell(
                f"if [ -f {REMOTE}/result.json ]; then cat {REMOTE}/result.json; fi"
            )
            if raw:
                break
            time.sleep(0.2)
        else:
            raise RuntimeError(f"No report received for {job['id']}")
        result = json.loads(raw)
        if result["id"] != job["id"] or result.get("error"):
            raise RuntimeError(f"Invalid report for {job['id']}: {result.get('error')}")

        pid = self.run("shell", "pidof", APP).decode().strip()
        log = self.run("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
        if b"Using the Impeller rendering backend (Vulkan)" not in log:
            raise RuntimeError(f"Impeller Vulkan was not confirmed for {job['id']}")
        result["pid"] = int(pid)
        thermal_status = re.search(rb"Thermal Status:\s*(\d+)", thermal)
        result["thermal_status"] = int(thermal_status[1]) if thermal_status else None

        if job["mode"] == "capture":
            print(f"{job['id']} PNG {result['size']}, encode {result['encode_us']} µs", flush=True)
        elif result.get("decode_error") and job["mode"] == "avif":
            print(f"{job['id']} {result['decode_error']}", flush=True)
        elif not result.get("request_to_raster_us") or len(result["frames"]) < 20:
            raise RuntimeError(f"Missing first image frame for {job['id']}")
        else:
            print(f"{job['id']} first raster {result['request_to_raster_us']} µs", flush=True)
        return result


def transcode(path):
    """保留原始 PNG，离线编码其它格式并记录真实透明度。"""
    with Image.open(path) as source:
        rgba = source.convert("RGBA")
    alpha = rgba.getchannel("A")
    histogram = alpha.histogram()
    meta = {
        "size": list(rgba.size),
        "alpha_nonopaque": sum(histogram[:255]),
        "alpha_partial": sum(histogram[1:255]),
        "alpha_range": list(alpha.getextrema()),
        "missing_encoders": [],
    }
    paths = {"png": path}
    if features.check("webp"):
        for mode, options in (
            ("webp_lossless", {"lossless": True, "quality": 90, "exact": True}),
            ("webp_q90", {"quality": 90, "alpha_quality": 100}),
        ):
            paths[mode] = path.with_suffix(f".{mode}")
            rgba.save(paths[mode], format="WEBP", method=6, **options)
    else:
        meta["missing_encoders"].append("WebP")

    paths["jpeg"] = path.with_suffix(".jpg")
    background = Image.new("RGB", rgba.size, "white")
    background.paste(rgba, mask=alpha)
    background.save(paths["jpeg"], format="JPEG", quality=90, subsampling=2)
    if features.check("avif"):
        paths["avif"] = path.with_suffix(".avif")
        rgba.save(paths["avif"], format="AVIF", quality=90, subsampling="4:2:0")
    else:
        meta["missing_encoders"].append("AVIF")

    meta["format_bytes"] = {mode: file.stat().st_size for mode, file in paths.items()}
    return paths, meta


def measure_group(phone, temp, sample, size, view, normalize, repetitions):
    """逐轮生成 PNG，并轮换测量矩阵的起点和方向。"""
    group = f"{sample}-{'view' if view else 'full'}"
    job = dict(sample=sample, width=size[0], height=size[1], view=view, normalize=normalize)
    captures = []
    png_path = temp / f"{group}.png"
    for round_index in range(repetitions):
        capture = phone.trial(dict(job, mode="capture", id=f"{group}-capture-{round_index + 1}"))
        captures.append(capture)
        if round_index == 0:
            png = phone.get("capture.png")
            if len(png) != capture["bytes"]:
                raise RuntimeError(f"PNG transfer size mismatch in {group}")
            png_path.write_bytes(png)

    paths, meta = transcode(png_path)
    for mode, path in paths.items():
        phone.put(f"input.{mode}", path.read_bytes())
    avif_probe = None
    if "avif" in paths:
        avif_probe = phone.trial(dict(job, mode="avif", id=f"{group}-avif-probe"))

    modes = [
        "vector",
        *(mode for mode in paths if mode != "avif" or not avif_probe.get("decode_error")),
    ]
    results = {mode: [] for mode in modes}
    for round_index in range(repetitions):
        for offset in range(len(modes)):
            step = offset if round_index % 2 == 0 else -offset
            mode = modes[(round_index + step) % len(modes)]
            run_id = f"{group}-{mode}-{round_index + 1}"
            measurement = phone.trial(dict(job, mode=mode, id=run_id))
            if mode == "vector":
                if not measurement["picture_bytes"] or measurement["parse_record_us"] is None:
                    raise RuntimeError(f"No cold xvg recording in {run_id}")
            elif measurement.get("bytes") != meta["format_bytes"][mode]:
                raise RuntimeError(f"Wrong snapshot loaded in {run_id}")
            results[mode].append(measurement)
    return group, dict(meta, captures=captures, trials=results, avif_probe=avif_probe)


def main():
    """读取运行时参数，采集纯数字结果并清理本轮私有文件。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", default=DEFAULT_DEVICE)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--external-svg", type=Path)
    parser.add_argument("--external-size", type=int, nargs=2, metavar=("WIDTH", "HEIGHT"))
    parser.add_argument("--normalize-external", action="store_true")
    parser.add_argument("--samples", nargs="+", choices=("external", "aurora", "icon"))
    parser.add_argument("--variants", nargs="+", choices=("view", "full"), default=["view", "full"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    samples = args.samples or (["external"] if args.external_svg else []) + ["aurora", "icon"]
    if "external" in samples and (
        not args.external_svg or not args.external_size or min(args.external_size) <= 0
    ):
        parser.error("The external sample requires --external-svg and a positive --external-size")
    if args.repetitions < 1:
        parser.error("--repetitions must be positive")
    if Path(tempfile.gettempdir()).resolve().is_relative_to(REPO):
        parser.error("The host temporary directory must be outside the repository")

    phone = Phone(args.device)
    report = {
        "device": phone.run("shell", "getprop", "ro.product.model").decode().strip(),
        "android": phone.run("shell", "getprop", "ro.build.version.release").decode().strip(),
        "pillow": pillow_version,
        "encoders": {name: features.version(name) for name in ("webp", "avif", "libjpeg_turbo")},
        "repetitions": args.repetitions,
        "groups": {},
    }
    settings = ("shell", "settings")
    key = "stay_on_while_plugged_in"
    original = phone.run(*settings, "get", "global", key).decode().strip()
    phone.app_shell(f"mkdir -p files && mkdir {REMOTE}")
    try:
        phone.run("shell", "input", "keyevent", "KEYCODE_WAKEUP")
        phone.run("shell", "wm", "dismiss-keyguard")
        phone.run("shell", "svc", "power", "stayon", "true")
        with tempfile.TemporaryDirectory(prefix="xvg-snapshot-") as scratch:
            for sample in samples:
                if sample == "external":
                    phone.put("input.svg", args.external_svg.read_bytes())
                    size = args.external_size
                    normalize = args.normalize_external
                elif sample == "aurora":
                    phone.put("input.svg", (BENCH / "assets/raster_cache_aurora.svg").read_bytes())
                    size = (375, 1500)
                    normalize = False
                else:
                    size = (24, 24)
                    normalize = False
                for variant in args.variants if sample != "icon" else ["full"]:
                    group, result = measure_group(
                        phone, Path(scratch), sample, size, variant == "view", normalize, args.repetitions
                    )
                    report["groups"][group] = result
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    args.output.write_text(json.dumps(report, separators=(",", ":")), encoding="utf-8")
            print(f"Metrics written to {args.output}", flush=True)
    finally:
        try:
            phone.run("shell", "am", "force-stop", APP)
            phone.app_shell(f"rm -f {REMOTE}/* && rmdir {REMOTE} && test ! -e {REMOTE}")
        finally:
            if original == "null":
                phone.run(*settings, "delete", "global", key)
            else:
                phone.run(*settings, "put", "global", key, original)


if __name__ == "__main__":
    main()
