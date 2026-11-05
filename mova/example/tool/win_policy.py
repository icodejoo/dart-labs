"""Windows 真机测试的唯一启动入口与统一策略（脚本层硬约束，不靠智能体自觉）。

背景：测试驱动曾每秒检查前台窗口、不是测试进程就 SetForegroundWindow 抢回来，
并把"焦点被打断"的轮次作废重跑，反复劫持用户正在工作的桌面。这里把约束写进代码：

1. 启动：所有 Windows 测试进程只能经 `launch()`。默认 `window` 模式：SW_SHOWNOACTIVATE
   启动、640x360、压到 z 序最底、不进任务栏、全程不调用任何激活/置前 API；应用的 runner
   本身也默认安静创建（见 example/windows/runner，MOVA_WIN_INTERACTIVE=1 才恢复普通窗口）。
   `desktop` 模式把应用放进独立隐藏桌面（CreateDesktop），机制上不可能抢焦点，但实测
   **Flutter 在非输入桌面上不渲染任何帧**（HE V10 报 never rendered），只适合完全不依赖
   渲染的进程；需要渲染的测试不得用它。
2. 次数：`clamp_runs()` 把每项采样次数钳到 MAX_RUNS（3）；更多只能由用户在自己的
   shell 里显式设置环境变量，脚本里写它会被 win_focus_gate 拒绝。
3. 焦点：`QuietApp.sample_foreground()` 只观测、不干预；应用一旦成为前台就记录违规，
   调用方应中止该轮并标 BLOCKED，绝不"抢回来重跑"。

静态闸门见 win_focus_gate.py（run_matrix.py --check 会调用）。
"""
import ctypes
import msvcrt
import os
import subprocess
import sys
import threading
import time
from ctypes import wintypes

if sys.platform != 'win32':  # 只在 Windows 宿主上使用；其他平台导入即报错，避免误用
    raise ImportError('win_policy 只支持 Windows')

MAX_RUNS = 3
"""每个 Windows 测试项的采样次数上限。"""

WINDOW_SIZE = (640, 360)
"""window 模式下的测试窗口尺寸（宽, 高）。"""

ENV_ALLOW_MORE = 'MOVA_WIN_ALLOW_MORE_RUNS'
"""用户在自己 shell 里设为 1 才允许超过 MAX_RUNS；脚本不得设置它。"""

MODE_DESKTOP = 'desktop'
MODE_WINDOW = 'window'

_k32 = ctypes.WinDLL('kernel32', use_last_error=True)
_u32 = ctypes.WinDLL('user32', use_last_error=True)

_STARTF_USESHOWWINDOW = 0x1
_STARTF_USESTDHANDLES = 0x100
_SW_SHOWNOACTIVATE = 4
_CREATE_UNICODE_ENVIRONMENT = 0x400
_GENERIC_ALL = 0x10000000
_HANDLE_FLAG_INHERIT = 0x1
_GWL_EXSTYLE = -20
_WS_EX_TOOLWINDOW = 0x80
_WS_EX_NOACTIVATE = 0x08000000
_SWP_NOACTIVATE = 0x10
_SWP_FRAMECHANGED = 0x20
_HWND_BOTTOM = 1
_STILL_ACTIVE = 259
_WAIT_TIMEOUT = 0x102
_SM_XVIRTUALSCREEN, _SM_YVIRTUALSCREEN, _SM_CXVIRTUALSCREEN, _SM_CYVIRTUALSCREEN = 76, 77, 78, 79


class _STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ('cb', wintypes.DWORD), ('lpReserved', wintypes.LPWSTR), ('lpDesktop', wintypes.LPWSTR),
        ('lpTitle', wintypes.LPWSTR), ('dwX', wintypes.DWORD), ('dwY', wintypes.DWORD),
        ('dwXSize', wintypes.DWORD), ('dwYSize', wintypes.DWORD), ('dwXCountChars', wintypes.DWORD),
        ('dwYCountChars', wintypes.DWORD), ('dwFillAttribute', wintypes.DWORD), ('dwFlags', wintypes.DWORD),
        ('wShowWindow', wintypes.WORD), ('cbReserved2', wintypes.WORD),
        ('lpReserved2', ctypes.POINTER(ctypes.c_byte)), ('hStdInput', wintypes.HANDLE),
        ('hStdOutput', wintypes.HANDLE), ('hStdError', wintypes.HANDLE),
    ]


class _PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [
        ('hProcess', wintypes.HANDLE), ('hThread', wintypes.HANDLE),
        ('dwProcessId', wintypes.DWORD), ('dwThreadId', wintypes.DWORD),
    ]


_k32.CreateProcessW.argtypes = [
    wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p, wintypes.BOOL,
    wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR,
    ctypes.POINTER(_STARTUPINFOW), ctypes.POINTER(_PROCESS_INFORMATION),
]
_k32.CreateProcessW.restype = wintypes.BOOL
_k32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
_k32.WaitForSingleObject.restype = wintypes.DWORD
_k32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
_k32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
_k32.CloseHandle.argtypes = [wintypes.HANDLE]
_k32.SetHandleInformation.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.DWORD]
_u32.CreateDesktopW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_void_p, wintypes.DWORD,
                                wintypes.DWORD, ctypes.c_void_p]
_u32.CreateDesktopW.restype = wintypes.HANDLE
_u32.CloseDesktop.argtypes = [wintypes.HANDLE]
_u32.GetForegroundWindow.restype = wintypes.HWND
_u32.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
_u32.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int, ctypes.c_int, ctypes.c_int,
                              ctypes.c_int, wintypes.UINT]
_u32.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
_u32.GetWindowLongPtrW.restype = ctypes.c_ssize_t
_u32.SetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int, ctypes.c_ssize_t]
_u32.SetWindowLongPtrW.restype = ctypes.c_ssize_t


def clamp_runs(requested):
    """把请求的采样次数钳到 MAX_RUNS。

    参数：requested 请求的次数。
    返回：实际应执行的次数；用户在自己 shell 里设置 ENV_ALLOW_MORE=1 时不钳。
    示例：`for i in range(win_policy.clamp_runs(20)):`（默认只跑 3 次）。
    """
    if os.environ.get(ENV_ALLOW_MORE) == '1':
        return requested
    return min(requested, MAX_RUNS)


def foreground_pid():
    """当前前台窗口所属进程 id；无前台窗口返回 0。"""
    pid = wintypes.DWORD()
    _u32.GetWindowThreadProcessId(_u32.GetForegroundWindow(), ctypes.byref(pid))
    return pid.value


def _env_block(env):
    """把环境变量字典编码成 CreateProcessW 要的 Unicode 环境块。"""
    return ctypes.create_unicode_buffer(''.join(f'{k}={v}\0' for k, v in env.items()) + '\0')


class QuietApp:
    """被策略托管的测试进程；只观测焦点，不干预。"""

    def __init__(self, pid, mode, process=None, popen=None, desktop=None, desktop_name=None):
        self.pid = pid
        self.mode = mode
        self.desktop_name = desktop_name
        self.foreground_violations = []
        self.exit_code = None
        self._process = process
        self._popen = popen
        self._desktop = desktop
        self._stop = threading.Event()

    def poll(self):
        """返回退出码；仍在运行返回 None。"""
        if self._popen is not None:
            return self._popen.poll()
        if self._process is None:
            return self.exit_code if self.exit_code is not None else 0
        code = wintypes.DWORD()
        _k32.GetExitCodeProcess(self._process, ctypes.byref(code))
        if code.value == _STILL_ACTIVE:
            return None
        self.exit_code = code.value
        return code.value

    def wait(self, timeout=None):
        """等待退出，超时抛 subprocess.TimeoutExpired；返回退出码。"""
        deadline = None if timeout is None else time.monotonic() + timeout
        while True:
            code = self.poll()
            if code is not None:
                self._close()
                return code
            if deadline is not None and time.monotonic() > deadline:
                raise subprocess.TimeoutExpired(str(self.pid), timeout)
            time.sleep(0.1)

    def terminate(self):
        """结束进程并释放桌面/句柄。"""
        if self.poll() is None:
            if self._popen is not None:
                self._popen.terminate()
            elif self._process is not None:
                _k32.TerminateProcess(self._process, 1)
        try:
            self.wait(20)
        except subprocess.TimeoutExpired:
            pass
        self._close()

    def sample_foreground(self):
        """观测一次前台窗口；应用成为前台则记录违规并返回 True。不会尝试改变焦点。"""
        if foreground_pid() == self.pid:
            self.foreground_violations.append(time.monotonic_ns())
            return True
        return False

    def _close(self):
        self._stop.set()
        if self._process is not None:
            self.poll()  # 关句柄前记下真实退出码
            _k32.CloseHandle(self._process)
            self._process = None
        if self._desktop is not None:
            _u32.CloseDesktop(self._desktop)
            self._desktop = None


def _launch_desktop(exe, cwd, env, stdout):
    """在独立隐藏桌面启动：窗口不在用户桌面上，不可能抢焦点或遮挡。"""
    name = f'mova_win_{os.getpid()}_{time.monotonic_ns() % 10**9}'
    desktop = _u32.CreateDesktopW(name, None, None, 0, _GENERIC_ALL, None)
    if not desktop:
        raise OSError(f'CreateDesktop 失败: {ctypes.get_last_error()}')
    si = _STARTUPINFOW()
    si.cb = ctypes.sizeof(si)
    si.lpDesktop = f'winsta0\\{name}'
    inherit = False
    if stdout is not None:
        handle = msvcrt.get_osfhandle(stdout.fileno())
        _k32.SetHandleInformation(handle, _HANDLE_FLAG_INHERIT, _HANDLE_FLAG_INHERIT)
        si.dwFlags |= _STARTF_USESTDHANDLES
        si.hStdOutput = si.hStdError = handle
        inherit = True
    pi = _PROCESS_INFORMATION()
    ok = _k32.CreateProcessW(str(exe), None, None, None, inherit, _CREATE_UNICODE_ENVIRONMENT,
                             ctypes.cast(_env_block(env), ctypes.c_void_p), str(cwd),
                             ctypes.byref(si), ctypes.byref(pi))
    if not ok:
        err = ctypes.get_last_error()
        _u32.CloseDesktop(desktop)
        raise OSError(f'CreateProcess 失败: {err}')
    _k32.CloseHandle(pi.hThread)
    return QuietApp(pi.dwProcessId, MODE_DESKTOP, process=pi.hProcess, desktop=desktop, desktop_name=name)


def _virtual_corner(width, height):
    """虚拟屏幕（含副显示器）右下角，给 window 模式摆窗口。"""
    vx, vy = _u32.GetSystemMetrics(_SM_XVIRTUALSCREEN), _u32.GetSystemMetrics(_SM_YVIRTUALSCREEN)
    vw, vh = _u32.GetSystemMetrics(_SM_CXVIRTUALSCREEN), _u32.GetSystemMetrics(_SM_CYVIRTUALSCREEN)
    return vx + vw - width - 8, vy + vh - height - 48


def _quiet_windows_of(pid):
    """把该进程的顶层窗口缩小、压到最底、去掉激活与任务栏按钮；全程不调用任何置前/激活 API。"""
    width, height = WINDOW_SIZE
    x, y = _virtual_corner(width, height)
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def visit(hwnd, _param):
        owner = wintypes.DWORD()
        _u32.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
        if owner.value == pid:
            ex = _u32.GetWindowLongPtrW(hwnd, _GWL_EXSTYLE)
            _u32.SetWindowLongPtrW(hwnd, _GWL_EXSTYLE, ex | _WS_EX_TOOLWINDOW | _WS_EX_NOACTIVATE)
            _u32.SetWindowPos(hwnd, _HWND_BOTTOM, x, y, width, height, _SWP_NOACTIVATE | _SWP_FRAMECHANGED)
        return True

    _u32.EnumWindows(callback(visit), 0)


def _launch_window(exe, cwd, env, stdout):
    """降级模式：不激活地显示、缩小、压底。仅在隐藏桌面跑不起来时显式选用。"""
    si = subprocess.STARTUPINFO()
    si.dwFlags |= _STARTF_USESHOWWINDOW
    si.wShowWindow = _SW_SHOWNOACTIVATE
    popen = subprocess.Popen([str(exe)], cwd=str(cwd), env=env, stdout=stdout,
                             stderr=subprocess.STDOUT if stdout is not None else None, startupinfo=si)
    app = QuietApp(popen.pid, MODE_WINDOW, popen=popen)

    def keep_quiet():
        # 窗口创建较晚且可能被应用重设，前 60 秒持续压制；只做缩小/压底，不做任何激活
        end = time.monotonic() + 60
        while not app._stop.is_set() and time.monotonic() < end and app.poll() is None:
            _quiet_windows_of(app.pid)
            time.sleep(0.5)

    threading.Thread(target=keep_quiet, daemon=True).start()
    return app


def launch(exe, cwd, env=None, stdout=None, mode=MODE_WINDOW):
    """启动 Windows 测试应用的唯一入口。

    参数：exe 可执行文件；cwd 工作目录；env 环境变量字典（默认继承当前进程）；
    stdout 已打开的日志文件对象（stdout/stderr 合并写入）；mode 为 MODE_WINDOW（默认，
    不激活的小窗）或 MODE_DESKTOP（隐藏桌面，不渲染，慎用）。
    返回：QuietApp。
    示例：`app = win_policy.launch(EXE, EXE.parent, env, console)`。
    """
    env = dict(os.environ if env is None else env)
    env.pop('MOVA_WIN_INTERACTIVE', None)  # 测试进程永远不是"交互模式"
    if mode == MODE_DESKTOP:
        return _launch_desktop(exe, cwd, env, stdout)
    if mode == MODE_WINDOW:
        return _launch_window(exe, cwd, env, stdout)
    raise ValueError(f'未知模式: {mode}')
