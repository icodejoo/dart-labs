"""Windows 基准共享门控：逐秒扣除进程树占用，污染整对重跑。"""
import ctypes as c
from ctypes import wintypes as w
import json
import os
from pathlib import Path
import subprocess
import time
import shutil

ROOT = Path(__file__).resolve().parents[1]
RULES = json.loads((ROOT / 'docs/reports/round2-r4b-evidence/preregistered-harness.json').read_text())
KERNEL = c.WinDLL('kernel32', use_last_error=True)
KERNEL.CreateJobObjectW.restype = w.HANDLE
KERNEL.CreateJobObjectW.argtypes = [c.c_void_p, w.LPCWSTR]
KERNEL.OpenProcess.restype = w.HANDLE
KERNEL.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
KERNEL.CloseHandle.argtypes = [w.HANDLE]
KERNEL.AssignProcessToJobObject.argtypes = [w.HANDLE, w.HANDLE]
KERNEL.QueryInformationJobObject.argtypes = [w.HANDLE, c.c_int, c.c_void_p, w.DWORD, c.c_void_p]
KERNEL.SetInformationJobObject.argtypes = [w.HANDLE, c.c_int, c.c_void_p, w.DWORD]


def dart_executable():
    """Flutter 包装脚本改用同 SDK 的原生入口，保证启动优先级生效。"""
    command = Path(shutil.which('dart'))
    native = command.parent / 'cache/dart-sdk/bin/dart.exe'
    return str(native if native.exists() else command)


def benchmark_command(script, *arguments):
    """用与 dart run 相同参数直接启动计时 VM，优先级直接作用于它。"""
    cli = dart_executable()
    vm = Path(cli).with_name('dartvm.exe')
    if not vm.exists():
        raise RuntimeError('无法定位同 SDK 的 dartvm.exe')
    return [str(vm), f'--resolved_executable_name={cli}', f'--executable_name={cli}',
            script, *arguments]


class DiomanJobAccounting(c.Structure):
    """作业对象累计时间包含已经退出的所有子孙进程。"""
    _fields_ = [('user', c.c_longlong), ('kernel', c.c_longlong),
                ('periodUser', c.c_longlong), ('periodKernel', c.c_longlong),
                ('pageFaults', w.DWORD), ('totalProcesses', w.DWORD),
                ('activeProcesses', w.DWORD), ('terminatedProcesses', w.DWORD)]


class DiomanBenchJob:
    """独立 Windows 作业对象提供精确的进程树累计 CPU。"""

    def __init__(self, pid, high):
        """仅认领自己刚启动的子进程，累计全部后代的 CPU。"""
        self.handle = KERNEL.CreateJobObjectW(None, None)
        if not self.handle:
            raise c.WinError(c.get_last_error())
        process = KERNEL.OpenProcess(0x101, False, pid)
        try:
            if not KERNEL.AssignProcessToJobObject(self.handle, process):
                raise c.WinError(c.get_last_error())
        except BaseException:
            self.close()
            raise
        finally:
            if process:
                KERNEL.CloseHandle(process)

    def cpu(self):
        """返回整棵树的累计 CPU 时间，单位为一百纳秒。"""
        info = DiomanJobAccounting()
        if not KERNEL.QueryInformationJobObject(self.handle, 1, c.byref(info), c.sizeof(info), None):
            raise c.WinError(c.get_last_error())
        return info.user + info.kernel

    def close(self):
        """只释放采样句柄，不终止任何进程。"""
        if self.handle:
            KERNEL.CloseHandle(self.handle)
            self.handle = None


def snapshot(job=None):
    """读取系统与基准作业对象累计时间；起跑前没有基准树。"""
    idle, kernel, user = c.c_ulonglong(), c.c_ulonglong(), c.c_ulonglong()
    if not KERNEL.GetSystemTimes(c.byref(idle), c.byref(kernel), c.byref(user)):
        raise c.WinError(c.get_last_error())
    return {'time': time.time(), 'idle': idle.value, 'total': kernel.value + user.value,
            'processes': {'tree': (0, job.cpu())} if job else {}}


def point(before, after):
    """相同系统时间分母下计算总占用、自身占用和外部占用。"""
    total = after['total'] - before['total']
    busy = total - (after['idle'] - before['idle'])
    own = 0
    for pid, (created, cpu) in after['processes'].items():
        previous = before['processes'].get(pid)
        if previous and previous[0] == created:
            own += cpu - previous[1]
        elif created >= int((before['time'] + 11644473600) * 10000000):
            own += cpu
    if total <= 0:
        raise RuntimeError('系统采样时间未前进')
    return {'time': after['time'], 'seconds': after['time'] - before['time'],
            'totalPercent': busy / total * 100, 'ownPercent': own / total * 100,
            'externalPercent': max(0, busy - own) / total * 100}


def classify(points):
    """按事前规则判断完整进程是否污染。"""
    reasons = []
    if len(points) < 3 or any(p['seconds'] > 2 for p in points):
        reasons.append('采样缺失或间隔超过两秒')
    mean = sum(p['externalPercent'] * p['seconds'] for p in points) / sum(p['seconds'] for p in points) if points else 100
    if mean > RULES['external_mean_max_percent']:
        reasons.append('外部均值超过20%')
    for i in range(len(points) - 2):
        if all(p['externalPercent'] > RULES['external_consecutive_max_percent'] for p in points[i:i+3]):
            reasons.append('连续三秒外部占用超过35%')
            break
    return {'clean': not reasons, 'meanExternalPercent': mean, 'reasons': reasons}


class DiomanBenchGate:
    """共享三十分钟预算，所有子进程串行且整对重试。"""

    def __init__(self, raw, high=False):
        """保存原始记录目录、优先级和本次任务期限。"""
        self.raw = Path(raw)
        self.raw.mkdir(parents=True, exist_ok=True)
        if any(self.raw.iterdir()):
            raise FileExistsError(f'原始目录已有记录，请使用新的任务目录：{self.raw}')
        self.high = high
        self.deadline = time.monotonic() + RULES['campaign_budget_seconds']
        self.records = []

    def check_time(self):
        """超过预算立即停止，不降低门控。"""
        if time.monotonic() >= self.deadline:
            raise TimeoutError('三十分钟预算耗尽')

    def wait_quiet(self, stem):
        """起跑前持续等待三个低负载采样点。"""
        samples = []
        before = snapshot()
        while True:
            self.check_time()
            time.sleep(1)
            after = snapshot()
            samples.append(point(before, after))
            before = after
            (self.raw / f'{stem}-waiting.json').write_text(json.dumps(samples), encoding='utf-8')
            recent = samples[-3:]
            if (len(recent) == RULES['external_consecutive_seconds']
                    and sum(p['totalPercent'] for p in recent) / len(recent) <= RULES['before_start_three_sample_mean_max_percent']
                    and max(p['totalPercent'] for p in recent) <= RULES['before_start_sample_max_percent']):
                return

    def run(self, command, stem, cwd=ROOT):
        """运行一个进程并逐秒监测，原始输出与曲线只写 coverage。"""
        self.wait_quiet(stem)
        output = self.raw / f'{stem}.json'
        error = self.raw / f'{stem}.stderr.txt'
        points = []
        with output.open('w', encoding='utf-8') as out, error.open('w', encoding='utf-8') as err:
            proc = subprocess.Popen(command, cwd=cwd, stdout=out, stderr=err,
                                    creationflags=subprocess.HIGH_PRIORITY_CLASS if self.high else 0,
                                    env={**os.environ, 'DIOMAN_BENCH_HIGH_PRIORITY': '1' if self.high else '0'})
            job = DiomanBenchJob(proc.pid, self.high)
            before = snapshot(job)
            while True:
                try:
                    proc.wait(timeout=1)
                    break
                except subprocess.TimeoutExpired:
                    after = snapshot(job)
                    points.append(point(before, after))
                    before = after
                    # 等待中的进程必须自行正常收尾，避免遗留临时工作树。
            after = snapshot(job)
            if after['time'] - before['time'] > .01:
                points.append(point(before, after))
        job.close()
        verdict = classify(points)
        verdict.update({'stem': stem, 'returncode': proc.returncode, 'highPriority': self.high})
        (self.raw / f'{stem}-load.json').write_text(json.dumps({'verdict': verdict, 'points': points}), encoding='utf-8')
        if proc.returncode:
            raise RuntimeError(f'{stem}: {error.read_text(encoding="utf-8")}')
        return json.loads(output.read_text(encoding='utf-8')), verdict

    def pairs(self, name, variants, prepare=None):
        """三轮完整交错；任一成员污染即废弃整对。"""
        accepted = {label: [] for label in variants}
        try:
            for round_id in range(1, 4):
                for attempt in range(1, RULES['pair_max_attempts'] + 1):
                    self.check_time()
                    pair = {}
                    verdicts = []
                    record = {'name': name, 'round': round_id, 'attempt': attempt,
                              'accepted': False, 'members': verdicts, 'complete': False}
                    self.records.append(record)
                    for label, command in variants.items():
                        if prepare:
                            prepare(label)
                        data, verdict = self.run(command, f'{name}-{round_id}-try-{attempt}-{label}')
                        pair[label] = data
                        verdicts.append(verdict)
                    clean = all(v['clean'] for v in verdicts)
                    record.update({'accepted': clean, 'complete': True})
                    if clean:
                        for label in variants:
                            accepted[label].append(pair[label])
                        break
                else:
                    raise TimeoutError('本轮五次尝试均未取得干净配对')
            return accepted
        finally:
            (self.raw / 'attempts.json').write_text(json.dumps(self.records, indent=2), encoding='utf-8')
