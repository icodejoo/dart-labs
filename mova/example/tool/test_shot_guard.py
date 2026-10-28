"""Offline tests for the screenshot foreground guard: no adb, no device.

截图前台守卫的离线单测：用伪造的 dumpsys 输出，不连设备。
"""
import re
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import coverage_device
import coverage_perf
import run_matrix as matrix
import shot_guard

OURS = matrix.PACKAGE
OTHER = 'com.tencent.mm'
LAUNCHER = 'com.huawei.android.launcher'


def activities(resumed, top=None, extra=''):
    """Fake `dumpsys activity activities` in the Android 12 format / 仿 Android 12 的 activities 输出。"""
    lines = [f'    mResumedActivity: ActivityRecord{{494ad9e u0 {resumed}/.Main t7}}',
             f'  ResumedActivity: ActivityRecord{{494ad9e u0 {resumed}/.Main t7}}']
    if top:
        lines.insert(0, f'  topResumedActivity=ActivityRecord{{1a2b3c u0 {top}/.Main t9}}')
    return '\n'.join(lines) + '\n' + extra


def window(focus):
    """Fake `dumpsys window` focus lines; focus may be a package, a label or None / 仿 window 的焦点行。"""
    if focus is None:
        return '  mCurrentFocus=null\n  mFocusedApp=null\n'
    if '.' in focus:
        return (f'  mCurrentFocus=Window{{2d39e35 u0 {focus}/{focus}.MainActivity}}\n'
                f'  mFocusedApp=ActivityRecord{{494ad9e u0 {focus}/.Main t7}}\n')
    return f'  mCurrentFocus=Window{{2d39e35 u0 {focus}}}\n'


PINNED_LINES = (f'  * Recent #1: Task{{da06a5c #1178 type=standard I={OURS}/com.icodejoo.mova.mova_example.MainActivity '
                'U=0 visible=true mode=pinned translucent=false sz=1}\n')


class ShotGuardTests(unittest.TestCase):
    """Pure decision function / 纯判定函数。"""

    def test_ours_in_foreground_allowed(self):
        """Foreground is the package under test: allow / 前台是被测包：允许。"""
        allowed, reason = matrix.shot_allowed(activities(OURS), window(OURS))
        self.assertTrue(allowed, reason)
        self.assertEqual(reason, 'foreground=' + OURS)

    def test_top_resumed_form_is_understood(self):
        """topResumedActivity alone is enough, and may refuse too / 只有 topResumedActivity 也能解析。"""
        text = f'  topResumedActivity=ActivityRecord{{1a2b3c u0 {OURS}/.Main t9}}\n'
        self.assertTrue(matrix.shot_allowed(text, window(None))[0])
        text = f'  topResumedActivity=ActivityRecord{{1a2b3c u0 {OTHER}/.Main t9}}\n'
        self.assertEqual(matrix.shot_allowed(text, window(None)), (False, 'foreground=' + OTHER))

    def test_third_party_foreground_refused(self):
        """A third-party app in front: refuse and name the package / 前台是第三方：拒绝并给出包名。"""
        allowed, reason = matrix.shot_allowed(activities(OTHER), window(OTHER))
        self.assertFalse(allowed)
        self.assertEqual(reason, 'foreground=' + OTHER)

    def test_focus_disagreeing_with_resumed_refused(self):
        """Resumed is ours but focus is foreign (dialog from another app): refuse / 焦点窗口是别家：拒绝。"""
        allowed, reason = matrix.shot_allowed(activities(OURS), window(OTHER))
        self.assertFalse(allowed)
        self.assertIn(OTHER, reason)

    def test_non_package_window_refused(self):
        """Notification shade / keyguard style windows have no package: refuse / 通知栏等无包名窗口：拒绝。"""
        allowed, reason = matrix.shot_allowed(activities(OURS), window('NotificationShade'))
        self.assertFalse(allowed)
        self.assertIn('NotificationShade', reason)

    def test_sibling_package_is_not_ours(self):
        """com.x.mova_example must not pass for com.x.mova_example.coverage / 相近包名不能冒充被测包。"""
        sibling = 'com.icodejoo.mova.mova_example'
        self.assertNotEqual(sibling, OURS)
        allowed, reason = matrix.shot_allowed(activities(sibling), window(sibling))
        self.assertFalse(allowed)
        self.assertEqual(reason, 'foreground=' + sibling)

    def test_pinned_refused_even_if_ours_resumed(self):
        """Our package in pinned (PiP) mode: refuse a full-screen shot / 被测包在画中画：拒绝。"""
        allowed, reason = matrix.shot_allowed(activities(OURS, extra=PINNED_LINES), window(OURS))
        self.assertFalse(allowed)
        self.assertIn('pinned', reason)

    def test_pinned_with_launcher_in_front_refused(self):
        """Real PiP shape: launcher resumed, ours pinned in the background: refuse / 真机 PiP 形态：前台是桌面。"""
        allowed, reason = matrix.shot_allowed(activities(LAUNCHER, extra=PINNED_LINES), window(LAUNCHER))
        self.assertFalse(allowed)
        self.assertEqual(reason, 'foreground=' + LAUNCHER)

    def test_pinned_flag_only_for_our_package(self):
        """Another app being pinned does not block our own shot / 别家的画中画不影响判定。"""
        other_pinned = PINNED_LINES.replace(OURS, OTHER)
        self.assertTrue(matrix.shot_allowed(activities(OURS, extra=other_pinned), window(OURS))[0])

    def test_unparseable_refused(self):
        """No marker at all: refuse (better no screenshot) / 解析不到：拒绝。"""
        for text in ('', 'Permission Denial: can\'t dump\n', '  mResumedActivity: null\n'):
            with self.subTest(text=text):
                self.assertEqual(matrix.shot_allowed(text, window(None)), (False, 'foreground=unknown'))

    def test_null_focus_is_ignored_when_resumed_is_ours(self):
        """mCurrentFocus=null appears next to real data and must not refuse / 空焦点行不应误拒。"""
        self.assertTrue(matrix.shot_allowed(activities(OURS), window(None))[0])


class FakeDriver(matrix.Driver):
    """Driver with scripted dumpsys output and an in-memory log / 带脚本化 dumpsys 的 Driver。"""

    def __init__(self, states):
        """`states` is a list of (activities, window); the last one repeats / 状态序列，末项重复。"""
        self.states, self.lines, self.calls = list(states), [], []
        self.reads = 0

    def note(self, kind, detail, case='driver'):
        """Record lines instead of writing files / 只记内存。"""
        self.lines.append((kind, detail))

    def adb(self, *args, binary=False):
        """Serve fake dumps and a fake PNG / 返回伪造 dump 与伪 PNG。"""
        self.calls.append(args)
        if args[:3] == ('shell', 'dumpsys', 'activity'):
            pair = self.states[min(self.reads, len(self.states) - 1)]
            self.reads += 1
            return pair[0]
        if args[:2] == ('shell', 'dumpsys'):
            return self.states[min(self.reads - 1, len(self.states) - 1)][1]
        if args[:2] == ('exec-out', 'screencap'):
            return b'PNG'
        return ''


class DriverShotTests(unittest.TestCase):
    """The single Driver entry point and PiP recovery / Driver 的唯一截图入口与画中画恢复。"""

    def test_allowed_writes_png(self):
        """Allowed foreground: PNG saved, SHOT logged / 允许时落盘并记 SHOT。"""
        driver = FakeDriver([(activities(OURS), window(OURS))])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'a.png'
            self.assertTrue(driver.safe_screenshot(path))
            self.assertEqual(path.read_bytes(), b'PNG')
        self.assertEqual(driver.lines[-1][0], 'SHOT')

    def test_third_party_never_calls_screencap(self):
        """Refused foreground: screencap is never issued, SHOT says skipped / 拒绝时根本不发 screencap。"""
        driver = FakeDriver([(activities(OTHER), window(OTHER))])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'a.png'
            self.assertFalse(driver.safe_screenshot(path))
            self.assertFalse(path.exists())
        self.assertFalse(any(c[:2] == ('exec-out', 'screencap') for c in driver.calls))
        kind, detail = driver.lines[-1]
        self.assertEqual(kind, 'SHOT')
        self.assertIn('skipped: foreground=' + OTHER, detail)

    def test_foreground_change_during_capture_discards(self):
        """Foreground flips right after the first check: discard the PNG / 截的过程中前台被切走：丢弃。"""
        driver = FakeDriver([(activities(OURS), window(OURS)), (activities(OTHER), window(OTHER))])
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'a.png'
            self.assertFalse(driver.safe_screenshot(path))
            self.assertFalse(path.exists())
        self.assertIn('discarded', driver.lines[-1][1])

    def test_dumpsys_failure_refuses(self):
        """If dumpsys itself fails we cannot know: refuse / dumpsys 读不出来：拒绝。"""
        driver = FakeDriver([])
        driver.adb = lambda *a, **k: (_ for _ in ()).throw(RuntimeError('device offline'))
        allowed, reason = driver.foreground()
        self.assertFalse(allowed)
        self.assertIn('foreground=unknown', reason)

    def test_restore_foreground_confirms_package(self):
        """After PiP: am start, then wait until the package is in front / 拉回后确认前台已是被测包才返回。"""
        pinned = (activities(LAUNCHER, extra=PINNED_LINES), window(LAUNCHER))
        back = (activities(OURS), window(OURS))
        driver = FakeDriver([pinned, back])
        with patch('run_matrix.time.sleep'):
            self.assertTrue(driver.restore_foreground())
        self.assertIn(('shell', 'am', 'start', '-n', matrix.MAIN_ACTIVITY), driver.calls)

    def test_restore_foreground_failure_reported(self):
        """Never confirmed in time: return False so the caller blocks later cases / 始终未恢复：返回 False。"""
        driver = FakeDriver([(activities(LAUNCHER, extra=PINNED_LINES), window(LAUNCHER))])
        with patch('run_matrix.time.sleep'), patch('run_matrix.time.monotonic', side_effect=[0, 1, 99, 100]):
            self.assertFalse(driver.restore_foreground(seconds=5))
        self.assertTrue(any(k == 'ERROR' for k, _ in driver.lines))

    def test_capture_failure_uses_guard(self):
        """capture_failure routes its PNG through the guard / 失败取证的截图也走守卫。"""
        driver = FakeDriver([(activities(OTHER), window(OTHER))])
        with tempfile.TemporaryDirectory() as tmp:
            driver.out, driver.prefix = Path(tmp), 'p-'
            driver.capture_failure('case')
            self.assertFalse((Path(tmp) / 'p-case.failure.png').exists())
        self.assertTrue(any(k == 'SHOT' and 'skipped' in d for k, d in driver.lines))


class PerfShotTests(unittest.TestCase):
    """coverage_perf's Android sampler uses the same decision / perf 采样器用同一判定。"""

    def make(self, states):
        """Build an Android sampler without touching adb / 不连 adb 构造采样器。"""
        sampler = object.__new__(coverage_perf.Android)
        sampler.prefix, sampler.package = ['adb', '-s', 'x'], OURS
        sampler.states = list(states)
        sampler.reads = 0
        return sampler

    def run_fake(self, argv, **kwargs):
        """Stand-in for subprocess.run / 替身。"""
        sampler = self.current
        text = argv[-1]
        done = Mock(stdout='', returncode=0)
        if text == 'dumpsys activity activities':
            done.stdout = sampler.states[min(sampler.reads, len(sampler.states) - 1)][0]
            sampler.reads += 1
        elif text == 'dumpsys window':
            done.stdout = sampler.states[min(sampler.reads - 1, len(sampler.states) - 1)][1]
        else:
            self.screencaps = getattr(self, 'screencaps', 0) + 1
            done.stdout = b'PNG'
        return done

    def test_refuse_and_allow(self):
        """Third party refuses without screencap; ours writes the file / 第三方拒绝且不截；被测包落盘。"""
        with tempfile.TemporaryDirectory() as tmp:
            for states, expect in [([(activities(OTHER), window(OTHER))], False),
                                   ([(activities(OURS), window(OURS))], True)]:
                self.current = self.make(states)
                self.screencaps = 0
                path = Path(tmp) / f'{expect}.png'
                with patch('coverage_perf.subprocess.run', side_effect=self.run_fake):
                    written, reason = self.current.screenshot(path)
                self.assertEqual(written, expect, reason)
                self.assertEqual(path.exists(), expect)
                self.assertEqual(self.screencaps, 1 if expect else 0)


class FakeAdb:
    """Scripted adb callable shared by the module-level tests / 模块级测试用的脚本化 adb。"""

    def __init__(self, states, fail_dumpsys=False):
        """`states` as in FakeDriver; the last pair repeats / 状态序列，末项重复。"""
        self.states, self.fail_dumpsys, self.calls, self.reads = list(states), fail_dumpsys, [], 0

    def __call__(self, *args, binary=False):
        """Serve fake dumps, a fake PNG, and empty text for anything else / 伪造 dump 与伪 PNG。"""
        self.calls.append(args)
        if args[:2] == ('shell', 'dumpsys') and len(args) > 2 and args[2] in ('activity', 'window'):
            if self.fail_dumpsys:
                raise RuntimeError('device offline')
            if args[2] == 'activity':
                pair = self.states[min(self.reads, len(self.states) - 1)]
                self.reads += 1
                return pair[0]
            return self.states[min(self.reads - 1, len(self.states) - 1)][1]
        if args[:2] == ('exec-out', 'screencap'):
            return b'PNG'
        return b'' if binary else ''

    def screencaps(self):
        """How many screencap calls were issued / 发出过几次 screencap。"""
        return sum(1 for c in self.calls if c[:2] == ('exec-out', 'screencap'))


class GuardedScreencapTests(unittest.TestCase):
    """shot_guard.guarded_screencap, used by every standalone script / 独立脚本共用的守卫截图。"""

    def run_shot(self, adb, package=OURS):
        """Capture to a temp path; returns (written, file exists, log lines) / 截到临时路径。"""
        logs = []
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'a.png'
            written = shot_guard.guarded_screencap(adb, package, path, logs.append)
            return written, path.exists(), logs

    def test_ours_written(self):
        """Foreground is ours: PNG written, path logged / 前台是被测包：落盘。"""
        adb = FakeAdb([(activities(OURS), window(OURS))])
        written, exists, logs = self.run_shot(adb)
        self.assertTrue(written and exists)
        self.assertEqual(adb.screencaps(), 1)
        self.assertTrue(logs[-1].endswith('a.png'))

    def test_third_party_refused_without_screencap(self):
        """Third-party foreground: no screencap at all, skipped is logged / 第三方前台：不发 screencap。"""
        adb = FakeAdb([(activities(OTHER), window(OTHER))])
        written, exists, logs = self.run_shot(adb)
        self.assertFalse(written or exists)
        self.assertEqual(adb.screencaps(), 0)
        self.assertIn('skipped: foreground=' + OTHER, logs[-1])

    def test_pinned_refused(self):
        """Our package in PiP: refuse / 被测包在画中画：拒绝。"""
        adb = FakeAdb([(activities(OURS, extra=PINNED_LINES), window(OURS))])
        written, exists, logs = self.run_shot(adb)
        self.assertFalse(written or exists)
        self.assertIn('pinned', logs[-1])

    def test_flip_after_capture_discards(self):
        """Foreground switches while capturing: PNG discarded / 截图过程中前台被切走：丢弃。"""
        adb = FakeAdb([(activities(OURS), window(OURS)), (activities(OTHER), window(OTHER))])
        written, exists, logs = self.run_shot(adb)
        self.assertFalse(written or exists)
        self.assertEqual(adb.screencaps(), 1)
        self.assertIn('discarded', logs[-1])

    def test_missing_package_refuses(self):
        """No package under test known: most conservative, refuse without even asking adb / 包名不明：保守拒绝。"""
        for package in (None, ''):
            adb = FakeAdb([(activities(OURS), window(OURS))])
            written, exists, logs = self.run_shot(adb, package)
            self.assertFalse(written or exists)
            self.assertEqual(adb.calls, [])
            self.assertIn('not specified', logs[-1])

    def test_dumpsys_failure_refuses(self):
        """dumpsys unreadable: refuse, never raise / dumpsys 读不出来：拒绝而不崩。"""
        adb = FakeAdb([], fail_dumpsys=True)
        written, exists, logs = self.run_shot(adb)
        self.assertFalse(written or exists)
        self.assertEqual(adb.screencaps(), 0)
        self.assertIn('foreground=unknown', logs[-1])

    def test_default_log_prints_shot(self):
        """Without a log callback the SHOT line goes to stdout / 缺省日志打印 SHOT。"""
        adb = FakeAdb([(activities(OTHER), window(OTHER))])
        with tempfile.TemporaryDirectory() as tmp, patch('builtins.print') as fake_print:
            shot_guard.guarded_screencap(adb, OURS, Path(tmp) / 'a.png')
        self.assertTrue(fake_print.call_args[0][0].startswith('SHOT skipped: foreground=' + OTHER))

    def test_run_matrix_reexports_same_objects(self):
        """run_matrix keeps the old names, bound to the shared module / 旧名仍可用且指向共享模块。"""
        self.assertIs(matrix.shot_allowed, shot_guard.shot_allowed)
        self.assertEqual(matrix.PACKAGE, shot_guard.PACKAGE)


class HistoricalScriptShotTests(unittest.TestCase):
    """coverage_device is the base of the historical scripts; they all capture through it / 历史脚本的截图基座。"""

    def capture_with(self, adb):
        """Run capture('case') on a temp dir; returns the evidence file names and PNG bytes / 跑一次 capture。"""
        with tempfile.TemporaryDirectory() as tmp, patch.object(coverage_device, 'adb', adb), \
                patch.object(coverage_device, 'request', return_value={}), \
                patch.object(coverage_device, 'HERE', Path(tmp)):
            coverage_device.capture('case')
            folder = Path(tmp) / 'coverage_evidence'
            png = folder / 'case.png'
            return {p.name for p in folder.iterdir()}, (png.read_bytes() if png.exists() else None)

    def test_capture_skips_png_for_third_party(self):
        """capture(): third-party foreground leaves no PNG, other evidence still written, no crash / 拒绝时无 PNG 且不崩。"""
        adb = FakeAdb([(activities(OTHER), window(OTHER))])
        files, png = self.capture_with(adb)
        self.assertIsNone(png)
        self.assertIn('case.json', files)
        self.assertEqual(adb.screencaps(), 0)

    def test_capture_writes_png_for_ours(self):
        """capture(): our foreground writes the PNG / 前台是被测包时写 PNG。"""
        files, png = self.capture_with(FakeAdb([(activities(OURS), window(OURS))]))
        self.assertEqual(png, b'PNG')
        self.assertIn('case.json', files)

    def test_shot_defaults_to_coverage_package_and_honours_override(self):
        """shot(): default package is the coverage build; an explicit package is checked instead / 默认包与显式包名。"""
        sibling = 'com.icodejoo.mova.mova_example'
        adb = FakeAdb([(activities(sibling), window(sibling))])
        with tempfile.TemporaryDirectory() as tmp, patch.object(coverage_device, 'adb', adb):
            self.assertFalse(coverage_device.shot(Path(tmp) / 'a.png'))
            self.assertTrue(coverage_device.shot(Path(tmp) / 'b.png', sibling))

    def test_no_bare_screencap_outside_guard(self):
        """Static guard: only shot_guard (and perf's own guarded sampler) may issue screencap / 静态回归：裸 screencap 只许在守卫里。"""
        allowed = {'shot_guard.py', 'coverage_perf.py'}
        tool = Path(__file__).resolve().parent
        for path in tool.glob('*'):
            if path.suffix not in ('.py', '.ps1', '.sh') or path.name in allowed or path.name.startswith('test_'):
                continue
            text = path.read_text(encoding='utf-8', errors='replace')
            hits = [ln for ln in text.splitlines() if re.search(r'''['"]screencap['"]''', ln)]
            self.assertEqual(hits, [], path.name)


if __name__ == '__main__':
    unittest.main()
