"""Windows 作业对象：把一次驱动运行的所有后代进程绑在一起，作业关闭时全部杀掉。

背景：驱动被超时/强杀时 finally 清理不会执行，驱动起的 ffmpeg 等子进程成为孤儿；
`taskkill /T` 沿父子关系找后代，父进程先死就找不到。作业对象的成员关系由后代自动继承，
与父进程是否存活无关；`KILL_ON_JOB_CLOSE` 保证作业句柄关闭（含本进程崩溃）时全部终止。
非 Windows 上是空操作。
"""
import os
import sys

if os.name != 'nt':
    class KillOnCloseJob:
        """非 Windows：空实现。"""

        def __init__(self): pass
        def assign(self, pid): return False
        def close(self): pass
        def __enter__(self): return self
        def __exit__(self, *a): self.close()
else:
    import ctypes
    from ctypes import wintypes

    _k32 = ctypes.WinDLL('kernel32', use_last_error=True)
    _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION = 9
    _KILL_ON_JOB_CLOSE = 0x2000
    _PROCESS_SET_QUOTA_TERMINATE = 0x0100 | 0x0001

    class _BASIC(ctypes.Structure):
        _fields_ = [('PerProcessUserTimeLimit', ctypes.c_int64), ('PerJobUserTimeLimit', ctypes.c_int64),
                    ('LimitFlags', wintypes.DWORD), ('MinimumWorkingSetSize', ctypes.c_size_t),
                    ('MaximumWorkingSetSize', ctypes.c_size_t), ('ActiveProcessLimit', wintypes.DWORD),
                    ('Affinity', ctypes.c_size_t), ('PriorityClass', wintypes.DWORD),
                    ('SchedulingClass', wintypes.DWORD)]

    class _IO(ctypes.Structure):
        _fields_ = [(n, ctypes.c_uint64) for n in ('ReadOp', 'WriteOp', 'OtherOp', 'ReadBytes',
                                                   'WriteBytes', 'OtherBytes')]

    class _EXTENDED(ctypes.Structure):
        _fields_ = [('BasicLimitInformation', _BASIC), ('IoInfo', _IO), ('ProcessMemoryLimit', ctypes.c_size_t),
                    ('JobMemoryLimit', ctypes.c_size_t), ('PeakProcessMemoryUsed', ctypes.c_size_t),
                    ('PeakJobMemoryUsed', ctypes.c_size_t)]

    _k32.CreateJobObjectW.restype = wintypes.HANDLE
    _k32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    _k32.OpenProcess.restype = wintypes.HANDLE
    _k32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _k32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    _k32.CloseHandle.argtypes = [wintypes.HANDLE]

    class KillOnCloseJob:
        """一个带 KILL_ON_JOB_CLOSE 的作业；`assign(pid)` 加入进程，`close()`/退出 with 时杀光成员。"""

        def __init__(self):
            self._job = _k32.CreateJobObjectW(None, None)
            if not self._job:
                raise OSError(f'CreateJobObject 失败: {ctypes.get_last_error()}')
            info = _EXTENDED()
            info.BasicLimitInformation.LimitFlags = _KILL_ON_JOB_CLOSE
            if not _k32.SetInformationJobObject(self._job, _JOB_OBJECT_EXTENDED_LIMIT_INFORMATION,
                                                ctypes.byref(info), ctypes.sizeof(info)):
                err = ctypes.get_last_error()
                _k32.CloseHandle(self._job)
                self._job = None
                raise OSError(f'SetInformationJobObject 失败: {err}')

        def assign(self, pid):
            """把进程加入作业；成功返回 True。进程此后派生的后代自动属于作业。

            这是尽力而为的兜底：任何失败（pid 非法、权限、进程已退出）都返回 False，
            绝不抛出，不能因它中断一轮跑批。
            """
            if not self._job:
                return False
            try:
                handle = _k32.OpenProcess(_PROCESS_SET_QUOTA_TERMINATE, False, int(pid))
                if not handle:
                    return False
                try:
                    return bool(_k32.AssignProcessToJobObject(self._job, handle))
                finally:
                    _k32.CloseHandle(handle)
            except Exception:
                return False

        def close(self):
            """关闭作业句柄：所有成员（含孤儿后代）被终止。可重复调用。"""
            if self._job:
                _k32.CloseHandle(self._job)
                self._job = None

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            self.close()
