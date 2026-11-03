"""Real desktop checks, opt in with MOVA_WIN_IT=1.

The bare-launch case intentionally uses subprocess to verify runner defaults,
independent of win_policy (the test_ gate exemption is required for this case).
Never runs the interactive control, and stops immediately on foreground violation.
"""
import ctypes
from ctypes import wintypes
import hashlib
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import unittest

TOOL = Path(__file__).resolve().parent
EXE = TOOL.parent/'build/windows/x64/runner/Release/mova_example.exe'
OUT = TOOL/'coverage_evidence/win-quiet-integration'
ENABLED = sys.platform == 'win32' and EXE.exists() and os.environ.get('MOVA_WIN_IT') == '1'
if sys.platform == 'win32':
    import win_policy
    U = ctypes.WinDLL('user32', use_last_error=True)
    U.GetWindowLongPtrW.argtypes = [wintypes.HWND, ctypes.c_int]
    U.GetWindowLongPtrW.restype = ctypes.c_ssize_t
    U.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    U.IsWindowVisible.argtypes = [wintypes.HWND]
    U.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    U.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    CALLBACK = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)


def windows(pid):
    rows = []
    def visit(hwnd, unused):
        if U.IsWindowVisible(hwnd):
            owner = wintypes.DWORD()
            U.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
            cls = ctypes.create_unicode_buffer(256)
            U.GetClassNameW(hwnd, cls, 256)
            rows.append(dict(hwnd=int(hwnd), pid=owner.value, windowClass=cls.value))
        return True
    U.EnumWindows(CALLBACK(visit), 0)  # top to bottom, including shell surfaces
    for index, row in enumerate(rows):
        if row['pid'] == pid and row['windowClass'] == 'FLUTTER_RUNNER_WIN32_WINDOW':
            rect = wintypes.RECT()
            U.GetWindowRect(row['hwnd'], ctypes.byref(rect))
            vx, vy, vw, vh = [U.GetSystemMetrics(i) for i in (76, 77, 78, 79)]
            return dict(rect=[rect.left, rect.top, rect.right, rect.bottom],
                        width=rect.right-rect.left, height=rect.bottom-rect.top,
                        virtualScreen=[vx, vy, vw, vh],
                        rightGap=vx+vw-rect.right, bottomGap=vy+vh-rect.bottom,
                        exStyle=hex(U.GetWindowLongPtrW(row['hwnd'], -20)),
                        zIndex=index, visibleCount=len(rows), below=rows[index+1:])
    return None


@unittest.skipUnless(ENABLED, 'requires existing Windows exe and MOVA_WIN_IT=1')
class QuietIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True, exist_ok=False)
        cls.stop_batch = False
        with socket.socket() as s:
            s.bind(('127.0.0.1', 18080))
        cls.source_console = (OUT/'source.console.log').open('wb')
        cls.source = subprocess.Popen([sys.executable, '-B', str(TOOL/'verify_sources/live_server.py'),
            '18080', str(OUT/'source.requests.log'), str(TOOL/'verify_sources/cp0-windows/stall.mp4')],
            stdout=cls.source_console, stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
        deadline = time.monotonic()+10
        while True:
            try:
                with socket.create_connection(('127.0.0.1', 18080), timeout=.2):
                    break
            except OSError:
                if time.monotonic()>deadline:
                    cls.source.terminate(); cls.source.wait(); cls.source_console.close()
                    raise RuntimeError('source not ready')
                time.sleep(.1)

    @classmethod
    def tearDownClass(cls):
        cls.source.terminate(); cls.source.wait(timeout=20); cls.source_console.close()

    def observe(self, bare=False):
        if self.stop_batch:
            self.fail('previous foreground violation: no more launches')
        stem = 'bare' if bare else 'policy-v10'
        log = OUT/(stem+'.he.log')
        env = dict(os.environ, MOVA_WIN_PAGE='' if bare else 'he', MOVA_ONLY='V10',
                   MOVA_RUNS=str(win_policy.clamp_runs(1)), MOVA_LOG=str(log))
        env.pop('MOVA_WIN_INTERACTIVE', None)
        evidence = dict(exeSha256=hashlib.sha256(EXE.read_bytes()).hexdigest(),
                        samples=[], windowSamples=[], foregroundViolations=[], bare=bare)
        with (OUT/(stem+'.console.log')).open('wb') as console:
            if bare:
                process = subprocess.Popen([str(EXE)], cwd=EXE.parent, env=env,
                                           stdout=console, stderr=subprocess.STDOUT)
                app = win_policy.QuietApp(process.pid, win_policy.MODE_WINDOW, popen=process)
            else:
                app = win_policy.launch(EXE, EXE.parent, env, console)
            evidence['pid'] = app.pid
            start = time.monotonic()
            try:
                while app.poll() is None and time.monotonic()-start < (9 if bare else 120):
                    violation = app.sample_foreground()
                    evidence['samples'].append(dict(atMonotonicNs=time.monotonic_ns(),
                        elapsed=time.monotonic()-start, violation=violation))
                    if violation:
                        app.terminate()
                        type(self).stop_batch = True
                        evidence['foregroundViolations'] = list(app.foreground_violations)
                        self.fail('focus-violation: immediately terminated; no retry')
                    snapshot = windows(app.pid)
                    if snapshot:
                        evidence['windowSamples'].append(snapshot)
                    (OUT/(stem+'.json')).write_text(json.dumps(evidence, indent=2), encoding='utf-8')
                    time.sleep(.2)
                evidence['elapsedSeconds'] = time.monotonic()-start
                evidence['exitCodeBeforeTermination'] = app.poll()
            finally:
                app.terminate()
                evidence['foregroundViolations'] = list(app.foreground_violations)
                (OUT/(stem+'.json')).write_text(json.dumps(evidence, indent=2), encoding='utf-8')
        self.assertTrue(evidence['windowSamples'], 'no visible runner window')
        # Ignore transient first creation before the policy sizing thread sees it.
        stable = evidence['windowSamples'][-1]
        self.assertLessEqual(stable['width'], 656)
        self.assertLessEqual(stable['height'], 399)
        self.assertGreater(stable['width'], 0)
        self.assertGreater(stable['height'], 0)
        self.assertLessEqual(abs(stable['rightGap']-8), 16)
        self.assertLessEqual(abs(stable['bottomGap']-48), 16)
        self.assertEqual(int(stable['exStyle'],16) & 0x08000080, 0x08000080)
        self.assertEqual(stable['below'], [], 'visible top-level windows below runner')
        if not bare:
            self.assertTrue(log.exists(), 'missing HE log')
            self.assertIn('VERDICT V10 PASS', log.read_text(encoding='utf-8', errors='replace'))

    def test_a_policy_v10(self):
        self.observe()

    def test_b_bare_runner(self):
        self.observe(bare=True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
