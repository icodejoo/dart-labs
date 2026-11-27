"""测量预先划分的 SVG，逐批检查热状态和 APK 原生库指纹。"""

import argparse
import hashlib
import json
import math
import os
import re
import statistics
import subprocess
import tempfile
import time
import zipfile
from collections import Counter
from pathlib import Path

from raster_cache_auto_r2_plan import (
    LEGACY_SIZES, MINIMUM_TARGET, SCREEN_TARGET, SEED, WEB_SIZES,
    load_json, load_lines, make_plan, manifest_rows, reduce_plan, save_json,
)
from raster_cache_auto_r2_rules import aggregate, fit, needs_confirmation

APP = "com.example.bench_app"
DEVICE = "R5CY2359S7D"
DEVICE_ROOT = f"/sdcard/Android/data/{APP}/files/xvg-r2"
DEVICE_INBOX = "/data/local/tmp/bench-xvg-raster-r2-inbox"
LIB_HASH = "86463a7be4004ef0c6aed40a910663eb0355bb43d718080fd441f685d2fc41bd"
BATCH_SIZE = 14
POLL_S = 2
COOL_POLL_S = 12
MAX_HOURS = 4
BOT_TIMEOUT_S = 480
LEGACY_ID = "legacy-014"


def sha256(path):
    """按字节计算文件 SHA-256。"""
    with Path(path).open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def apk_hash(apk):
    """对 APK 里的 ARM64 so 本身取哈希，在任何安装之前校验。"""
    with zipfile.ZipFile(apk) as package:
        name = "lib/arm64-v8a/libxvg.so"
        assert package.namelist().count(name) == 1
        with package.open(name) as source:
            digest = hashlib.file_digest(source, "sha256").hexdigest()
    if digest != LIB_HASH:
        raise RuntimeError(f"Unexpected APK library SHA-256: {digest}")
    return digest


def append_json(path, row):
    """持久保存每次启动结果，异常退出后可以从已完成组合继续。"""
    with path.open("a", encoding="utf-8", newline="\n") as sink:
        sink.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
        sink.flush()
        os.fsync(sink.fileno())


class Phone:
    """把所有 adb 操作限定到指定的 Android 真机。"""

    def __init__(self, device):
        """保存设备编号，所有调用共享该选择。"""
        self.device = device

    def adb(self, *commands, timeout=30):
        """执行一个 adb 请求，返回 UTF-8 文本。"""
        result = subprocess.run(["adb", "-s", self.device, *commands],
                                capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError(f"adb {commands[0]} failed (exit {result.returncode})")
        return result.stdout.decode("utf-8", errors="replace").strip()

    def shell(self, commands, **kwargs):
        """在设备 shell 执行固定命令。"""
        return self.adb("shell", commands, **kwargs)

    def app(self, commands, **kwargs):
        """以 benchmark app 身份访问隔离的工作目录。"""
        return self.shell(f"run-as {APP} sh -c '{commands}'", **kwargs)

    def read(self, filename):
        """读回可能还没有生成的单个状态或逐帧文件。"""
        path = f"{DEVICE_ROOT}/{filename}"
        return self.adb("exec-out", f"run-as {APP} sh -c 'if [ -f {path} ]; then cat {path}; fi'")

    def stage(self, local, name):
        """通过固定的临时名字推送输入，不把主机路径写入设备或日志。"""
        self.adb("push", str(local), DEVICE_INBOX, timeout=120)
        try:
            self.app(f"cp {DEVICE_INBOX} {DEVICE_ROOT}/{name}")
        finally:
            self.shell(f"rm -f {DEVICE_INBOX}")

    def thermal(self):
        """同时取设备时钟和热状态，用于排除热切换附近的窗口。"""
        data = self.shell("date +%s%3N; dumpsys thermalservice")
        status = re.search(r"^Thermal Status:\s*(\d+)\s*$", data, re.MULTILINE)
        epoch = data.splitlines()[0]
        if not status or not epoch.isdecimal():
            raise RuntimeError("Thermal status or time missing")
        return [int(epoch), int(status[1])]

    def cool(self):
        """等待热状态归零，完整保留等待期间的观测。"""
        log = [self.thermal()]
        if log[-1][1]:
            print(f"thermal={log[-1][1]}，暂停降温", flush=True)
        while log[-1][1]:
            time.sleep(COOL_POLL_S)
            log.append(self.thermal())
        if len(log) > 1:
            print("thermal=0，继续", flush=True)
        return log

    def stop(self):
        """停止本次基准 app，停止 spinner 和 GPU 工作。"""
        self.shell(f"am force-stop {APP}")

    def launch(self):
        """启动 profile Activity 并确认系统报告成功。"""
        launch = self.shell(
            f"am start -W -n {APP}/.MainActivity --ez enable-impeller true",
            timeout=50)
        if "Status: ok" not in launch:
            raise RuntimeError("Benchmark Activity failed to start")

    def pid(self):
        """读取当前基准进程号，进程退出时返回空。"""
        value = self.shell(f"pidof {APP} || true")
        return value if value.isdecimal() else None

    def backend(self, pid):
        """在当前 app 进程日志中核对 Impeller Vulkan。"""
        if pid is None:
            return None
        log = self.adb("logcat", "-d", f"--pid={pid}", "-s", "flutter:I")
        return ("Impeller Vulkan" if
                "Using the Impeller rendering backend (Vulkan)" in log else None)

    def exit_reason(self, pid):
        """读取对应 PID 的 Android 退出原因，避免把主动停测误作崩溃。"""
        if pid is not None:
            log = self.shell(f"dumpsys activity exit-info {APP}")
            match = re.search(
                rf"(?m)^.*\bpid={pid}\b[^\n]*\n.*?reason=\d+ \(([^)]+)\)", log
            )
            if match:
                return match[1]
        return "UNKNOWN"


def chunks(items, size):
    """为每一轮计划切出独立的进程启动批次。"""
    for start in range(0, len(items), size):
        yield items[start:start + size]


class Run:
    """管理已经哈希校验的安装、分层计划、热恢复和逐批检查点。"""

    def __init__(self, args):
        """读取锁定的主机清单和第一轮样本标识。"""
        self.args = args
        self.scratch = args.scratch
        self.scratch.mkdir(parents=True, exist_ok=True)
        self.phone = Phone(args.device)
        self.journal = self.scratch / "batches.jsonl"
        self.plan = load_json(self.scratch / "plan.json")
        self.batches = load_lines(self.journal) if self.journal.exists() else []
        self.by_id = {row["id"]: row for row in self.plan["corpus"]}
        self.web = self.plan["web"]
        self.uploaded = set()

    def completed(self, round_id):
        """已得到冷态结果或明确跳过原因的组合。"""
        return {(row["sample"], row["size"])
                for batch in self.batches if batch["round"] == round_id
                for row in batch["accepted"] if row["type"] != "baseline"}

    def ensure_input(self, sample):
        """只将本轮选中的输入推送一遍，保证 APK 内无语料文件。"""
        if sample in self.uploaded:
            return
        if sample == LEGACY_ID:
            local = self.args.legacy_svg
        elif sample == "aurora":
            local = Path("assets/raster_cache_aurora.svg")
        else:
            local = self.args.corpus / "files" / self.by_id[sample]["file"]
        encoding = self.by_id.get(sample, {}).get("source_encoding")
        if encoding is None:
            self.phone.stage(local, f"input/{sample}.svg")
        else:
            # 保留 XML 字符，临时转码在仓库之外完成。
            with tempfile.TemporaryDirectory(prefix="xvg-r2-") as directory:
                transcoded = Path(directory) / "input.svg"
                transcoded.write_bytes(local.read_bytes().decode(encoding).encode("utf-8"))
                self.phone.stage(transcoded, f"input/{sample}.svg")
        self.uploaded.add(sample)

    def batch(self, phase, round_id, samples):
        """运行一次计划，热状态首次升高时停止并保留已确认的组合。"""
        phone = self.phone
        started = time.monotonic()
        if any(row["split"] == "legacy" for row in samples):
            self.ensure_input("aurora")
            self.ensure_input(LEGACY_ID)
        for row in samples:
            if row["split"] != "legacy":
                self.ensure_input(row["id"])
        phone.stop()
        phone.app(f"rm -f {DEVICE_ROOT}/status.txt {DEVICE_ROOT}/status.tmp {DEVICE_ROOT}/frames.jsonl")
        attempt = len(self.batches) + 1
        local_plan = self.scratch / "batch_plan.json"
        save_json(local_plan, {"round": round_id, "samples": samples,
                               "order_seed": SEED + attempt + round_id * 1000})
        phone.stage(local_plan, "plan.json")
        thermal = phone.cool()
        cool_s = (thermal[-1][0] - thermal[0][0]) / 1000
        status = ""
        backend = None
        cutoff = None
        phone.launch()
        pid = phone.pid()
        last_app_status = ""
        exit_reason = None
        deadline = time.monotonic() + BOT_TIMEOUT_S
        try:
            while time.monotonic() < deadline:
                last_app_status = phone.read("status.txt")
                reading = phone.thermal()
                if backend is None:
                    backend = phone.backend(pid)
                if reading[1]:
                    cutoff = thermal[-1][0]
                    thermal.append(reading)
                    phone.stop()
                    status = "thermal_pause"
                    print(f"批 {attempt} thermal={reading[1]}，停止当前窗口", flush=True)
                    break
                thermal.append(reading)
                if last_app_status == "done" or last_app_status.startswith("error"):
                    status = last_app_status
                    break
                if pid is None or phone.pid() != pid:
                    status = "process_exit"
                    exit_reason = phone.exit_reason(pid)
                    break
                time.sleep(POLL_S)
            else:
                phone.stop()
                status = "app_timeout"
            records = []
            for line in phone.read("frames.jsonl").splitlines():
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue  # force-stop can interrupt the last line
            accepted = [row for row in records if cutoff is None or row["end_ms"] <= cutoff]
            discarded = [row for row in records if cutoff is not None and row["end_ms"] > cutoff]
            if backend != "Impeller Vulkan" and accepted:
                raise RuntimeError("Measured rows lack Impeller Vulkan confirmation")
            row = {
                "id": attempt, "phase": phase, "round": round_id, "plan": samples,
                "status": status, "backend": backend, "thermal": thermal,
                "app_status": last_app_status, "exit_reason": exit_reason,
                "wall_s": round(time.monotonic() - started, 3), "cool_s": cool_s,
                "accepted": accepted,
                "discarded_after_last_cool": [
                    {key: r[key] for key in ("type", "sample", "size", "end_ms") if key in r}
                    for r in discarded
                ],
            }
            append_json(self.journal, row)
            self.batches.append(row)
            counts = Counter(r["type"] for r in accepted)
            print(f"批 {attempt} {phase}/{round_id} {status}，"
                  f"{counts['case']} 组合，{counts['skip']} 跳过，{row['wall_s']:.1f}s",
                  flush=True)
            return row
        finally:
            phone.stop()

    def phase(self, name, round_id, requests):
        """逐批执行剩余尺寸，遇热自动冷却并续跑。"""
        for group in chunks(requests, BATCH_SIZE):
            consecutive_errors = 0
            batch_limit = BATCH_SIZE
            exits = Counter()
            while True:
                done = self.completed(round_id)
                pending = [{**request, "sizes": [
                    size for size in request["sizes"] if (request["id"], size) not in done
                ]} for request in group]
                pending = [request for request in pending if request["sizes"]]
                if not pending:
                    break
                launched = pending[:batch_limit]
                batch = self.batch(name, round_id, launched)
                status = batch["status"]
                if status in {"done", "thermal_pause"}:
                    consecutive_errors = 0
                    if status == "done":
                        batch_limit = BATCH_SIZE
                    continue
                if status == "process_exit":
                    last = batch["app_status"].removeprefix("running ").split("/", 1)
                    exits[tuple(last)] += 1
                    batch_limit = 1
                    if len(launched) == 1 and last[0] == launched[0]["id"] and exits[tuple(last)] >= 2:
                        self.skip_after_exit(name, round_id, launched[0], last, batch)
                        consecutive_errors = 0
                        continue
                if len(self.completed(round_id)) > len(done):
                    consecutive_errors = 0
                    continue
                consecutive_errors += 1
                batch_limit = max(1, batch_limit // 2)
                if consecutive_errors >= 5:
                    raise RuntimeError(f"Device repeatedly failed at {pending[0]['id']}: {status}")

    def skip_after_exit(self, phase, round_id, sample, last, batch):
        """隔离重试仍退出时，记下该尺寸的 Android 退出原因。"""
        done = self.completed(round_id)
        sizes = [size for size in sample["sizes"]
                 if (sample["id"], size) not in done and (len(last) == 1 or size == last[1])]
        if not sizes:
            raise RuntimeError("Could not identify a remaining size after isolated exit")
        row = {
            "id": len(self.batches) + 1, "phase": phase, "round": round_id, "plan": [sample],
            "status": "isolated_exit_skip", "backend": None, "thermal": [],
            "wall_s": 0, "cool_s": 0, "discarded_after_last_cool": [],
            "source_batch": batch["id"],
            "accepted": [
                {"type": "skip", "sample": sample["id"], "size": size, "split": sample["split"],
                 "end_ms": batch["thermal"][-1][0],
                 "stage": "render", "reason": f"isolated_process_exit:{batch['exit_reason']}"}
                for size in sizes
            ],
        }
        append_json(self.journal, row)
        self.batches.append(row)
        print(f"{sample['id']} {','.join(sizes)}，隔离复跑仍退出：{batch['exit_reason']}",
              flush=True)

    def measure(self):
        """先试跑十张，随后筛选、补测，并完整重测第一轮样本。"""
        web_by_id = {row["id"]: row for row in self.web}
        requests = lambda rows: [
            {"id": row["id"], "split": row["split"], "sizes": list(WEB_SIZES)}
            for row in rows
        ]
        pilot_ids = self.plan["pilot"]
        decision_path = self.scratch / "time_budget.json"
        self.phase("pilot", 1, requests(web_by_id[sample] for sample in pilot_ids))
        if decision_path.exists():
            decision = load_json(decision_path)
        else:
            pilot_batches = [batch for batch in self.batches if batch["phase"] == "pilot"]
            pilot_seconds = sum(batch["wall_s"] for batch in pilot_batches)
            n = len(pilot_ids)
            # 以所有网上组合补三轮、旧样本四档全补三轮作为保守上界。
            seconds_per_web_sample = pilot_seconds / n
            legacy_seconds = len(self.plan["legacy"]) * 4 * seconds_per_web_sample
            limit = MAX_HOURS * 3600
            projected = legacy_seconds + SCREEN_TARGET * 3 * seconds_per_web_sample
            target = SCREEN_TARGET
            if projected > limit:
                target = max(MINIMUM_TARGET, min(SCREEN_TARGET,
                             math.floor((limit - legacy_seconds) / (3 * seconds_per_web_sample))))
            decision = {"pilot_samples": n, "pilot_wall_s": pilot_seconds,
                        "seconds_per_web_sample": seconds_per_web_sample,
                        "projected_200_upper_s": projected, "target": target,
                        "projected_target_upper_s": legacy_seconds + target * 3 * seconds_per_web_sample}
            save_json(decision_path, decision)
        print(f"十图试跑 {decision['pilot_wall_s']:.1f}s，"
              f"200 图保守估计 {decision['projected_200_upper_s'] / 3600:.2f}h，"
              f"抽样 {decision['target']} 图", flush=True)
        self.web = reduce_plan(self.web, pilot_ids, decision["target"])
        self.phase("screen", 1, requests(row for row in self.web if row["id"] not in pilot_ids))
        confirm_path = self.scratch / "confirmation.json"
        if not confirm_path.exists():
            cases = aggregate([batch for batch in self.batches if batch["round"] == 1])
            provisional = fit(cases, self.by_id)
            selected = {}
            for case in cases:
                if case["split"] == "legacy" or not needs_confirmation(case, provisional):
                    continue
                selected.setdefault(case["sample"], []).append(case["size"])
            save_json(confirm_path, {"rule": provisional, "sizes_by_sample": selected})
        confirm = load_json(confirm_path)["sizes_by_sample"]
        legacy = [{"id": sample, "split": "legacy", "sizes": list(LEGACY_SIZES)}
                  for sample in self.plan["legacy"]]
        self.phase("legacy", 1, legacy)
        for round_id in (2, 3):
            self.phase("confirm", round_id, [
                {"id": row["id"], "split": row["split"], "sizes": confirm[row["id"]]}
                for row in self.web if row["id"] in confirm
            ])
            self.phase("legacy", round_id, legacy)

    def run(self):
        """核对 APK 后安装并恢复设备设置，结束后检查临时文件。"""
        digest = apk_hash(self.args.apk)
        phone = self.phone
        assert phone.adb("get-state") == "device"
        print(f"APK arm64-v8a/libxvg.so SHA-256 {digest}", flush=True)
        phone.adb("install", "-r", str(self.args.apk), timeout=160)
        previous = phone.shell("settings get global stay_on_while_plugged_in")
        started = time.monotonic()
        cleanup = False
        try:
            phone.app(f"mkdir -p {DEVICE_ROOT}/input")
            phone.shell("input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard; svc power stayon true")
            self.measure()
        finally:
            try:
                phone.stop()
                phone.app(f"rm -rf {DEVICE_ROOT}")
                phone.shell(f"rm -f {DEVICE_INBOX}")
                phone.app(f"test ! -e {DEVICE_ROOT}")
                phone.shell(f"test ! -e {DEVICE_INBOX}")
                cleanup = True
            finally:
                if previous == "null":
                    phone.shell("settings delete global stay_on_while_plugged_in")
                else:
                    assert previous.isdecimal()
                    phone.shell(f"settings put global stay_on_while_plugged_in {previous}")
                append_json(self.scratch / "sessions.jsonl", {
                    "device": phone.device, "apk_so_sha256": digest, "cleanup": cleanup,
                    "elapsed_s": round(time.monotonic() - started, 3),
                    "stay_awake_restored": (
                        phone.shell("settings get global stay_on_while_plugged_in") == previous),
                })
                print(f"测量进程累计 {time.monotonic() - started:.1f}s，清理 {cleanup}", flush=True)


def main():
    """准备计划或启动已验证 APK 的设备测量。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("inputs", "plan", "measure", "verify-apk"))
    parser.add_argument("--corpus", type=Path, default=Path("E:/workspaces/svg-corpus"))
    parser.add_argument("--scratch", type=Path, default=Path(".dart_tool/raster_cache_auto_r2"))
    parser.add_argument("--first", type=Path, default=Path("../raster_cache_auto_raw.json"))
    parser.add_argument("--apk", type=Path, default=Path("build/app/outputs/flutter-apk/app-profile.apk"))
    parser.add_argument("--device", default=DEVICE)
    parser.add_argument("--legacy-svg", type=Path)
    args = parser.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=True)
    if args.action == "inputs":
        manifest = manifest_rows(args.corpus)
        save_json(args.scratch / "windows_inputs.json", [
            {"id": row["id"], "path": str((args.corpus / "files" / row["file"]).resolve())}
            for row in manifest])
    elif args.action == "plan":
        manifest = manifest_rows(args.corpus)
        native = load_lines(args.scratch / "windows_features.jsonl")
        plan_path = args.scratch / "plan.json"
        if (args.scratch / "batches.jsonl").exists():
            raise RuntimeError("Device timings already exist for this frozen plan")
        plan = make_plan(manifest, native, load_json(args.first)["runs"])
        save_json(plan_path, plan)
        print(Counter(row["status"] for row in plan["corpus"]))
        print(Counter(row["split"] for row in plan["web"]))
    elif args.action == "verify-apk":
        print(apk_hash(args.apk))
    else:
        if args.legacy_svg is None:
            parser.error("--legacy-svg is required for the runtime-only legacy input")
        if not args.legacy_svg.is_file():
            parser.error("Legacy runtime input is unavailable")
        Run(args).run()


if __name__ == "__main__":
    main()
