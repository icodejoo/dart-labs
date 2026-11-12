"""Quiet launcher for Windows benchmark/acceptance runs of bench_app / example.
Windows 真机基准/验收的"安静"启动器（bench_app / example 通用）。

Three hard rules (the user is working on this very machine) / 三条硬规矩（用户正在这台机器上工作）：
1. Small background window, never steal focus. The exe is started with
   SW_SHOWNOACTIVATE; the Flutter runner itself is quiet by default
   (640x360, bottom-right, bottom of z-order, WS_EX_TOOLWINDOW|WS_EX_NOACTIVATE
   -> no taskbar/Alt-Tab entry; XVG_WIN_INTERACTIVE=1 restores the normal
   window). This script never calls SetForegroundWindow / SetActiveWindow /
   BringWindowToTop / SendInput / keybd_event / mouse_event / os.startfile.
   小窗后台运行、绝不抢焦点：以 SW_SHOWNOACTIVATE 启动；runner 默认安静
   （640x360、右下角、压 z 序最底、不进任务栏/Alt-Tab）。本脚本不调用任何
   置前/激活/合成输入 API。
2. At most 3 samples per item: --runs is clamped to MAX_RUNS (3).
   每项最多采 3 次：--runs 钳到 3。
3. Foreground is only observed (once per second for the whole run). If the
   foreground window ever belongs to the tested process the run is marked
   BLOCKED in the log; the run is neither repeated nor is focus taken back.
   前台只观测（整个运行期间每秒一次）：前台变成被测进程就把该轮标 BLOCKED
   并写日志，不重跑、不抢回。

Usage / 用法（务必 `python -I`）:
    python -I win_quiet_launch.py --exe <path\\to\\app.exe> --log <dir\\name.log>
        [--timeout 900] [--runs 1] [--env KEY=VALUE ...]

Read-only CPU sampling: a thread reads the tested process's cumulative CPU time
(GetProcessTimes via a PROCESS_QUERY_LIMITED_INFORMATION handle; no attach, no
injection) every 0.5 s into <log>.cpu.csv (epoch_ms,cpu_100ns). 只读 CPU 采样：
每 0.5 秒读一次被测进程累计 CPU 时间，写 .cpu.csv（不 attach、不注入）。

Per run N it writes <log>(.runN).log (process stdout/stderr + launcher notes)
and sets XVG_MICRO_OUT=<log>(.runN).report.txt so the benchmark report is
captured even when GUI-process stdout is not. Exit code: 0 all runs ok,
2 any BLOCKED, 3 any timeout/non-zero exit, 4 bad arguments.
每轮写 <log>(.runN).log，并设 XVG_MICRO_OUT 指向 .report.txt，GUI 进程抓不到
stdout 时报告仍落盘。退出码：0 全部正常，2 有 BLOCKED，3 超时或进程非 0，4 参数错误。
"""
import argparse
import ctypes
import os
import subprocess
import sys
import threading
import time
from ctypes import wintypes

if sys.platform != 'win32':
    raise ImportError('win_quiet_launch only supports Windows')

MAX_RUNS = 3  # 每项采样次数上限 / per-item sample cap
CPU_SAMPLE_INTERVAL_S = 0.5  # CPU 采样间隔 / CPU sampling period
SAMPLE_INTERVAL_S = 1.0  # 前台采样间隔 / foreground sampling period
_SW_SHOWNOACTIVATE = 4
_STARTF_USESHOWWINDOW = 0x1
_GWL_EXSTYLE = -20
_WS_EX_TOOLWINDOW = 0x80
_WS_EX_NOACTIVATE = 0x08000000

_u32 = ctypes.WinDLL('user32', use_last_error=True)
_u32.GetForegroundWindow.restype = wintypes.HWND
_u32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
_u32.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
_u32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
_u32.IsWindowVisible.argtypes = [wintypes.HWND]
_u32.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
_u32.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
_PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
_k32 = ctypes.WinDLL('kernel32', use_last_error=True)
_k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
_k32.OpenProcess.restype = wintypes.HANDLE
_k32.CloseHandle.argtypes = [wintypes.HANDLE]
_k32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(wintypes.FILETIME)] * 4
_ENUM = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
_u32.EnumWindows.argtypes = [_ENUM, wintypes.LPARAM]


def clamp_runs(requested):
    """Clamp the requested sample count to MAX_RUNS. 把请求次数钳到 MAX_RUNS。"""
    return max(1, min(requested, MAX_RUNS))


def foreground_pid():
    """PID owning the current foreground window (0 if none). 前台窗口所属进程 id。"""
    pid = wintypes.DWORD()
    _u32.GetWindowThreadProcessId(_u32.GetForegroundWindow(), ctypes.byref(pid))
    return pid.value


def describe_windows(pid):
    """Observe-only snapshot of top-level windows owned by pid (visible, rect, ex-style).
    只读快照：该进程的顶层窗口（可见性、矩形、扩展样式）。"""
    found = []

    def visit(hwnd, _):
        owner = wintypes.DWORD()
        _u32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            rect = wintypes.RECT()
            _u32.GetWindowRect(hwnd, ctypes.byref(rect))
            ex = _u32.GetWindowLongPtrW(hwnd, _GWL_EXSTYLE)
            cls = ctypes.create_unicode_buffer(64)
            _u32.GetClassNameW(hwnd, cls, 64)
            found.append({
                'class': cls.value, 'visible': bool(_u32.IsWindowVisible(hwnd)),
                'rect': (rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top),
                'toolwindow': bool(ex & _WS_EX_TOOLWINDOW), 'noactivate': bool(ex & _WS_EX_NOACTIVATE),
            })
        return True

    _u32.EnumWindows(_ENUM(visit), 0)
    return found


def _cpu_100ns(handle):
    """Cumulative kernel+user CPU time of the process in 100 ns units.
    进程累计内核+用户 CPU 时间（100ns 单位）。"""
    t = [wintypes.FILETIME() for _ in range(4)]
    if not _k32.GetProcessTimes(handle, *[ctypes.byref(x) for x in t]):
        return None
    ft = lambda f: (f.dwHighDateTime << 32) | f.dwLowDateTime
    return ft(t[2]) + ft(t[3])


def _sample_cpu(pid, csv_path, stop):
    """Thread body: every CPU_SAMPLE_INTERVAL_S append `epoch_ms,cpu_100ns` until stop is set.
    采样线程：每 0.5 秒追加一行，直到 stop。"""
    handle = _k32.OpenProcess(_PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    with open(csv_path, 'w', encoding='utf-8') as f:
        f.write(f'# logical_cores={os.cpu_count()}' + chr(10) + 'epoch_ms,cpu_100ns' + chr(10))
        while handle and not stop.is_set():
            cpu = _cpu_100ns(handle)
            if cpu is None:
                break
            f.write(f'{int(time.time() * 1000)},{cpu}' + chr(10))
            f.flush()
            stop.wait(CPU_SAMPLE_INTERVAL_S)
    if handle:
        _k32.CloseHandle(handle)


def run_once(exe, log_path, timeout_s, env_extra):
    """Run the exe once, observe only. Returns (status, exit_code, violations, secs).
    status in OK / BLOCKED / TIMEOUT / FAILED. 启动一次并只观测。"""
    env = dict(os.environ)
    env.pop('XVG_WIN_INTERACTIVE', None)  # 测试进程永远不是交互模式 / never interactive
    env.update(env_extra)
    report = os.path.splitext(log_path)[0] + '.report.txt'
    env['XVG_MICRO_OUT'] = report
    if os.path.exists(report):
        os.remove(report)
    si = subprocess.STARTUPINFO()
    si.dwFlags |= _STARTF_USESHOWWINDOW
    si.wShowWindow = _SW_SHOWNOACTIVATE
    start = time.monotonic()
    violations, win_seen, status = 0, None, 'OK'
    with open(log_path, 'w', encoding='utf-8', errors='replace') as log:
        proc = subprocess.Popen([exe], cwd=os.path.dirname(os.path.abspath(exe)), env=env,
                                stdout=log, stderr=subprocess.STDOUT, startupinfo=si)

        def note(msg):
            log.write(f'\n[launcher +{time.monotonic() - start:6.1f}s] {msg}\n')
            log.flush()

        note(f'started pid={proc.pid} exe={exe} report={report}')
        stop_cpu = threading.Event()
        cpu_thread = threading.Thread(
            target=_sample_cpu, args=(proc.pid, os.path.splitext(log_path)[0] + '.cpu.csv', stop_cpu), daemon=True)
        cpu_thread.start()
        while proc.poll() is None:
            if foreground_pid() == proc.pid:  # 只观测，不抢回 / observe only
                violations += 1
                status = 'BLOCKED'
                note(f'FOREGROUND VIOLATION #{violations}: tested process became foreground')
            if win_seen is None:
                snap = describe_windows(proc.pid)
                if any(w['visible'] for w in snap):
                    win_seen = snap
                    note(f'windows: {snap}')
            if time.monotonic() - start > timeout_s:
                note(f'TIMEOUT after {timeout_s}s, terminating')
                proc.terminate()
                try:
                    proc.wait(20)
                except subprocess.TimeoutExpired:
                    proc.kill()
                status = 'TIMEOUT' if status == 'OK' else status
                break
            time.sleep(SAMPLE_INTERVAL_S)
        code = proc.wait()
        stop_cpu.set()
        cpu_thread.join(5)
        secs = time.monotonic() - start
        if status == 'OK' and code != 0:
            status = 'FAILED'
        note(f'exit_code={code} status={status} violations={violations} seconds={secs:.1f}')
    return status, code, violations, secs


def main(argv=None):
    """CLI entry. 命令行入口。"""
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--exe', required=True)
    ap.add_argument('--log', required=True)
    ap.add_argument('--timeout', type=float, default=900)
    ap.add_argument('--runs', type=int, default=1)
    ap.add_argument('--env', action='append', default=[], metavar='KEY=VALUE')
    args = ap.parse_args(argv)
    if not os.path.isfile(args.exe):
        print(f'exe not found: {args.exe}', file=sys.stderr)
        return 4
    env_extra = dict(kv.split('=', 1) for kv in args.env)
    runs = clamp_runs(args.runs)
    if runs != args.runs:
        print(f'--runs {args.runs} clamped to {runs}')
    os.makedirs(os.path.dirname(os.path.abspath(args.log)), exist_ok=True)
    worst = 0
    for i in range(1, runs + 1):
        log = args.log if runs == 1 else f'{os.path.splitext(args.log)[0]}.run{i}.log'
        status, code, viol, secs = run_once(args.exe, log, args.timeout, env_extra)
        print(f'run {i}/{runs}: {status} exit={code} violations={viol} {secs:.1f}s log={log}')
        worst = max(worst, {'OK': 0, 'BLOCKED': 2, 'TIMEOUT': 3, 'FAILED': 3}[status])
    return worst


if __name__ == '__main__':
    sys.exit(main())
