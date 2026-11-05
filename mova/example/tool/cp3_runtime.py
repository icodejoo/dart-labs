"""CP3 host resource guard; no GUI or device operations."""
import os
import subprocess
import time


def wait_memory():
    deadline = time.monotonic() + 2400
    while True:
        result = subprocess.run(
            ['powershell', '-NoProfile', '-NonInteractive', '-Command',
             '(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory'],
            capture_output=True, text=True, timeout=30,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        free_kb = int(result.stdout.strip())
        print('CP3 FreePhysicalMemory KiB:', free_kb, flush=True)
        if free_kb >= 3.5 * 1024 * 1024:
            return free_kb
        if time.monotonic() >= deadline:
            raise RuntimeError('FreePhysicalMemory below 3.5 GiB for 40 minutes')
        time.sleep(60)


def virtual_memory_error(text):
    return any(s in text.lower() for s in (
        'paging file is too small', 'insufficient memory', 'not enough memory',
        'could not reserve enough space', 'native memory allocation',
        'os::commit_memory', 'error=1455', 'error 1455', '虚拟内存', '页面文件太小'))
