"""在安静 Windows 进程中采样离屏纹理，合并有数据的轮次并计算 Fisher 双侧 p 值。"""

import argparse
from collections import Counter
import ctypes as ct
from ctypes import wintypes as win
import json
from math import comb
import os
from pathlib import Path
import re
import subprocess
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bench_app/tool"))
from win_quiet_launch import MAX_RUNS, foreground_pid

SAMPLES = 150
LOW = (122, 122, 120, 255)
CONTROLS = ("original", "legacy", "clean")
TREATMENTS = ("poison", "readback", "winding", "float32")
EXTRA_PAIRS = (("original", "legacy"), ("original", "clean"), ("clean", "poison"))
ALL_ARMS = set(CONTROLS) | set(TREATMENTS)
BACKEND = "Using the Impeller rendering backend (OpenGLESSDF)"
DESKTOP_CLASSES = {"Progman", "WorkerW", "SoPY_Status"}
WINDOW_CLASS = "FLUTTER_RUNNER_WIN32_WINDOW"
ROUND_ENV = "XVG_MSAA_ROUND"
ARCHIVE_ENV = "XVG_ARCHIVE"
REPORT_ENV = "XVG_MICRO_OUT"


def fisher_exact(a, b, c, d):
    """对固定边际的 2×2 表求双侧概率，同概率表一并计入。"""
    n, m, events = a + b, c + d, a + c
    observed = comb(n, a) * comb(m, c)
    weights = (comb(n, i) * comb(m, events - i)
               for i in range(max(0, events - m), min(n, events) + 1))
    return sum(weight for weight in weights if weight <= observed) / comb(n + m, events)


def summarize(rounds):
    """合并各轮逐样本记录，计算各档低值计数与成对 Fisher 双侧 p 值。"""
    totals = {arm: Counter() for arm in sorted(ALL_ARMS)}
    per_round = {}
    for actual in rounds:
        if set(actual.get("arms", {})) - ALL_ARMS:
            raise ValueError("Unexpected conditions")
        counts = {}
        for arm, rows in actual.get("arms", {}).items():
            if (len(rows) > SAMPLES
                    or [row["sample"] for row in rows] != list(range(1, len(rows) + 1))):
                raise ValueError(f"Invalid sample sequence in {arm}")
            if any(row["texel_xy"] != [160, 134] or len(row["texel"]) != 4 for row in rows):
                raise ValueError(f"Unexpected texel coordinates or channels in {arm}")
            totals[arm].update(Counter(tuple(row["texel"]) for row in rows))
            counts[arm] = [Counter(tuple(r["texel"]) for r in rows)[LOW], len(rows)]
        per_round[actual["round"]] = counts
    pairs = [(c, t) for t in TREATMENTS for c in CONTROLS] + list(EXTRA_PAIRS)
    tests = {}
    for control, treatment in pairs:
        a, c = totals[control][LOW], totals[treatment][LOW]
        n, m = totals[control].total(), totals[treatment].total()
        tests[f"{control}_vs_{treatment}"] = {
            "table": [[a, n - a], [c, m - c]],
            "fisher_two_sided": fisher_exact(a, n - a, c, m - c) if n and m else None,
        }
    return {
        "low_rgba": LOW,
        "per_round_low_and_n": per_round,
        "histograms": {arm: {",".join(map(str, rgba)): count for rgba, count in hist.items()}
                       for arm, hist in totals.items()},
        "tests": tests,
    }


def read_checkpoint(report):
    """恢复异常退出前已经完整写入的逐样本记录。"""
    arms, frames = {}, []
    for line in report.read_bytes().splitlines(keepends=True):
        if not line.endswith(b"\n"):
            break
        row = json.loads(line)
        if "arm" in row:
            arms.setdefault(row.pop("arm"), []).append(row)
        else:
            frames.append(row)
    return {"arms": arms, "order": list(arms), "host_frames": frames}


class WindowAudit:
    """用只读 Win32 查询检查焦点、物理位置、样式及 z-order。"""

    def __init__(self):
        """固定句柄原型，按物理坐标读取窗口。"""
        self.user32 = ct.WinDLL("user32", use_last_error=True)
        self.callback = ct.WINFUNCTYPE(win.BOOL, win.HWND, win.LPARAM)
        self.enum = self.bind("EnumWindows", win.BOOL, self.callback, win.LPARAM)
        self.visible = self.bind("IsWindowVisible", win.BOOL, win.HWND)
        self.owner = self.bind("GetWindowThreadProcessId", win.DWORD, win.HWND,
                               ct.POINTER(win.DWORD))
        self.title_class = self.bind("GetClassNameW", ct.c_int, win.HWND, win.LPWSTR, ct.c_int)
        self.rect = self.bind("GetWindowRect", win.BOOL, win.HWND, ct.POINTER(win.RECT))
        self.style = self.bind("GetWindowLongPtrW", ct.c_ssize_t, win.HWND, ct.c_int)
        self.metric = self.bind("GetSystemMetrics", ct.c_int, ct.c_int)
        self.dpi = self.bind("GetDpiForWindow", win.UINT, win.HWND)
        set_dpi_context = self.bind("SetThreadDpiAwarenessContext", win.HANDLE, win.HANDLE)
        if not set_dpi_context(-4):
            raise ct.WinError(ct.get_last_error())

    def bind(self, name, result, *args):
        """给窗口查询设置 Win32 参数和返回类型。"""
        function = getattr(self.user32, name)
        function.restype, function.argtypes = result, args
        return function

    def window(self, pid):
        """返回被测可见窗口的初始状态，并检查所有安静启动约束。"""
        seen = []

        @self.callback
        def visit(hwnd, _):
            """按 z-order 记录可见窗口。"""
            if self.visible(hwnd):
                owner, name = win.DWORD(), ct.create_unicode_buffer(128)
                self.owner(hwnd, ct.byref(owner))
                self.title_class(hwnd, name, len(name))
                seen.append((hwnd, owner.value, name.value))
            return True

        if not self.enum(visit, 0):
            raise ct.WinError(ct.get_last_error())
        for i, (hwnd, owner, name) in enumerate(seen):
            if owner != pid or name != WINDOW_CLASS:
                continue
            rect = win.RECT()
            if not self.rect(hwnd, ct.byref(rect)):
                raise ct.WinError(ct.get_last_error())
            style = self.style(hwnd, -20)
            right, bottom = self.metric(76) + self.metric(78) - 8, self.metric(77) + self.metric(79) - 48
            expected = [right - 640, bottom - 360, right, bottom]
            actual = [rect.left, rect.top, rect.right, rect.bottom]
            below = [row[2] for row in seen[i + 1:]]
            info = {"rect": actual, "dpi": self.dpi(hwnd), "ex_style": hex(style),
                    "visible_classes_below": below}
            required, forbidden = 0x08000080, 0x00040008
            if (actual != expected or style & required != required or style & forbidden
                    or set(below) - DESKTOP_CLASSES):
                raise RuntimeError(f"Benchmark window violates quiet configuration: {info}")
            return info
        return None


def run_once(audit, exe, archive, out, number):
    """只启动一次，记录窗口审计、后端与每张纹理的原始读数。"""
    report, log = out / f"run-{number}.jsonl", out / f"run-{number}.log"
    options = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("FLUTTER_ENGINE_SWITCH")
        and key.upper() != "XVG_WIN_INTERACTIVE"
    }
    options.update({ROUND_ENV: str(number), ARCHIVE_ENV: str(archive), REPORT_ENV: str(report)})
    startup = subprocess.STARTUPINFO(dwFlags=subprocess.STARTF_USESHOWWINDOW, wShowWindow=4)
    state = {"round": number, "foreground_checks": 0, "foreground_violations": 0}
    start = time.monotonic()
    with log.open("xb") as sink:
        child = subprocess.Popen(
            [str(exe)], cwd=exe.parent, env=options, startupinfo=startup,
            stdin=subprocess.DEVNULL, stdout=sink, stderr=sink,
        )
        state["pid"] = child.pid
        try:
            while child.poll() is None:
                state["foreground_checks"] += 1
                if foreground_pid() == child.pid:
                    state["foreground_violations"] += 1
                    raise RuntimeError("Benchmark entered the foreground")
                if "window" not in state:
                    if info := audit.window(child.pid):
                        state["window"] = info
                if time.monotonic() - start > 300:
                    raise TimeoutError("Benchmark timed out")
                time.sleep(0.015)
            state["exit_code"] = child.returncode
            safe_log = [line for line in log.read_text(encoding="utf-8", errors="replace").splitlines()
                        if not re.search(r"KEY|TOKEN|SECRET|PASSWORD", line, re.I)]
            if not any(BACKEND in line for line in safe_log):
                raise RuntimeError(f"Backend check failed for round {number}")
            state["backend"] = BACKEND
            if child.returncode or "window" not in state or not report.is_file():
                state["incomplete"] = True
        finally:
            if child.poll() is None:
                child.terminate()
            child.wait(timeout=10)
            state["seconds"] = round(time.monotonic() - start, 3)
            if state.get("backend") == BACKEND and "window" in state and report.is_file():
                state.update(read_checkpoint(report))
            (out / f"audit-{number}.json").write_text(json.dumps(state, indent=2) + "\n",
                                                     encoding="utf-8")
    return state


def main():
    """验证输入，只跑指定的一轮，再合并 out 中所有已有轮次并保存结果。"""
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("exe", "archive", "out"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--round", type=int, choices=range(1, MAX_RUNS + 1), required=True)
    args = parser.parse_args()
    exe, archive, out = args.exe.resolve(), args.archive.resolve(), args.out.resolve()
    if not exe.is_file() or not all((archive / name).is_file()
                                   for name in ("C1-web-481.jsonl", "clips-481.json")):
        parser.error("The profile exe and local C1 corpus are required")
    out.mkdir(exist_ok=True)
    audit = WindowAudit()
    if (out / f"audit-{args.round}.json").is_file():
        parser.error("This round already has an audit file; refusing to rerun")
    state = run_once(audit, exe, archive, out, args.round)
    count = sum(len(rows) for rows in state.get("arms", {}).values())
    print(f"Round {args.round}: {count} texels, {state['seconds']}s, "
          f"{state['foreground_checks']} foreground checks, "
          f"{state['foreground_violations']} violations, exit {state.get('exit_code')}", flush=True)
    rounds = []
    for number in range(1, MAX_RUNS + 1):
        existing = out / f"audit-{number}.json"
        if existing.is_file():
            loaded = json.loads(existing.read_bytes())
            if loaded.get("arms"):
                rounds.append(loaded)
    summary = summarize(rounds)
    (out / "results.json").write_text(json.dumps({"rounds": rounds, "summary": summary}, indent=2)
                                      + "\n", encoding="utf-8")
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
