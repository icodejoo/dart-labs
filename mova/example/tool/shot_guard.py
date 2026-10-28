"""Screenshot privacy guard shared by every device script; stdlib only, never touches adb on import.

真机脚本共用的截图隐私守卫：只在前台确实是被测包（且非画中画）时才截图。
"""
from pathlib import Path
import re

PACKAGE = 'com.icodejoo.mova.mova_example.coverage'
# 前台判定：dumpsys activity 的 (top)ResumedActivity，以及 dumpsys window 的 mCurrentFocus。
# Foreground markers: (top)ResumedActivity from `dumpsys activity`, mCurrentFocus from `dumpsys window`.
RESUMED_RE = re.compile(r'(?:topResumedActivity|mResumedActivity|ResumedActivity)\s*[:=]\s*'
                        r'ActivityRecord\{[^}\s]+ u\d+ ([\w.]+)/')
FOCUS_RE = re.compile(r'mCurrentFocus=(\S.*)')
FOCUS_PKG_RE = re.compile(r'Window\{[^}\s]+ u\d+ ([\w.]+)/')
FOCUS_LABEL_RE = re.compile(r'Window\{[^}\s]+ u\d+ ([^}\s/]+)')
PINNED_RE = re.compile(r'\b(?:mWindowingMode|windowingMode|mode)=pinned\b')


def foreground_apps(activities, window):
    """Collect foreground package names from both dumps / 从两份 dump 收集前台包名。

    Resumed activities give package names; a focused window without a package
    (shade, keyguard, popup) is recorded by its label, so it counts as foreign.
    `mCurrentFocus=null` is a transition/other-display artifact and is ignored.
    """
    found = set(RESUMED_RE.findall(activities) + RESUMED_RE.findall(window))
    for match in FOCUS_RE.finditer(activities + '\n' + window):
        value = match.group(1).strip()
        if value == 'null':
            continue
        named = FOCUS_PKG_RE.search(value) or FOCUS_LABEL_RE.search(value)
        found.add(named.group(1) if named else 'unknown-window')
    return found


def is_pinned(activities, window, package):
    """Whether the package's activity/task is in system PiP (pinned) / 被测包是否处于系统画中画。"""
    needle = re.compile(r'(?<![\w.])' + re.escape(package) + r'/')
    for line in (activities + '\n' + window).splitlines():
        if needle.search(line) and PINNED_RE.search(line):
            return True
    return False


def shot_allowed(activities, window, package=PACKAGE):
    """Decide whether a screencap is safe; returns (allowed, reason).

    Rules: foreground must be only the package under test, not pinned, and
    parseable. Anything else refuses (better no screenshot than a private one).
    判定截图是否安全：前台只能是被测包、非画中画、且能解析；否则一律拒绝。
    """
    apps = foreground_apps(activities, window)
    if not apps:
        return False, 'foreground=unknown'
    foreign = sorted(apps - {package})
    if foreign:
        return False, 'foreground=' + ','.join(foreign)
    if is_pinned(activities, window, package):
        return False, f'foreground={package} (pinned PiP)'
    return True, 'foreground=' + package


def read_foreground(adb, package):
    """Read dumpsys through `adb` and decide; returns (allowed, reason) / 读前台并判定。

    `adb(*args, binary=False)` is the caller's own adb wrapper. A package that is not
    given, or any read failure, counts as unknown and refuses.
    adb 为调用方自己的封装；包名缺失或读取失败按未知处理，即拒绝。
    """
    if not package:
        return False, 'foreground=unknown (package under test not specified)'
    try:
        activities = adb('shell', 'dumpsys', 'activity', 'activities')
        window = adb('shell', 'dumpsys', 'window')
    except Exception as error:
        return False, f'foreground=unknown (dumpsys failed: {error})'
    return shot_allowed(activities, window, package)


def guarded_screencap(adb, package, path, log=None):
    """The one place that issues `screencap`: check foreground before and after.

    截图的唯一出口：截前、截后各核对一次前台，任何一次不是被测包就不落盘。
    Returns True only when the PNG was written. `log(detail)` receives the SHOT detail
    (a path when written, `skipped: ...` when refused); default prints to stdout.
    仅在 PNG 落盘时返回 True；log 收到 SHOT 明细，缺省打印到标准输出。
    """
    log = log or (lambda detail: print('SHOT ' + detail, flush=True))
    allowed, reason = read_foreground(adb, package)
    if not allowed:
        log(f'skipped: {reason} path={path}')
        return False
    payload = adb('exec-out', 'screencap', '-p', binary=True)
    allowed, reason = read_foreground(adb, package)
    if not allowed:
        log(f'skipped: {reason} (changed while capturing; discarded) path={path}')
        return False
    Path(path).write_bytes(payload)
    log(str(path))
    return True
