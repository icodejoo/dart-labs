"""S00c host observations. Importing this module never connects to a device.

Window/PiP decisions use native dumps, with unknown formats left BLOCKED.
Deadlines schedule polling only; no wall clock is a product predicate.
"""
import argparse
import json
from pathlib import Path
import re
import time
import urllib.parse
import xml.etree.ElementTree as ET

PACKAGE = 'com.icodejoo.mova.mova_example.coverage'


def window_values(window):
    """Read display rotation/dimensions and actual inset visibility."""
    result = {}
    frames = re.findall(r'(?:mDisplayFrames|DisplayFrames)[^\n]*?w=(\d+) h=(\d+)[^\n]*?r=(\d+)', window)
    if frames:
        width, height, rotation = map(int, frames[0])
        result.update(width=width, height=height, rotation=rotation)
    for key, name in [('status', 'statusBars'), ('navigation', 'navigationBars')]:
        values = re.findall(r'InsetsSource[^\n]*?type='+name+r'\b[^\n]*?visible=(true|false)', window)
        if values and len(set(values)) == 1:
            result[key] = values[0] == 'true'
    focus = re.search(r'mCurrentFocus=([^\n]+)', window)
    if focus:
        result['focused'] = PACKAGE in focus[1]
    return result


def pinned_value(activity):
    """Identify the target's task, never a different application's PiP."""
    # Android versions vary between Task and RootTask. Require both package
    # and a mode inside the same brace-delimited task description.
    tasks = re.findall(r'(?:RootTask|Task)\{([^}\n]+)\}', activity)
    target = [task for task in tasks if PACKAGE in task]
    modes = [re.search(r'(?:mode|windowingMode)=(\w+)', task) for task in target]
    values = [m[1] in ('pinned', '2') for m in modes if m]
    if values:
        return any(values)
    return None


def close_bounds(xml):
    """Locate the real system PiP Close control, not a guessed coordinate."""
    try:
        root = ET.fromstring(xml)
    except ET.ParseError:
        return None
    for node in root.iter('node'):
        if node.get('package') != 'com.android.systemui': continue
        label = node.get('content-desc', '').strip().lower()
        if label not in ('close', '关闭', '关闭画中画', 'close picture-in-picture'): continue
        match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', node.get('bounds', ''))
        if match:
            left, top, right, bottom = map(int, match.groups())
            if right > left and bottom > top:
                return [(left + right) // 2, (top + bottom) // 2]
    return None


def observation(ident, numbers, predicates):
    """Unknown fields stay unknown; a boolean cannot manufacture a reading."""
    values = [None if key not in numbers or numbers[key] is None or value is None else numbers[key] == value
              for key, value in predicates.items()]
    passed = False if False in values else None if None in values else True
    return dict(kind='CHECK', id=ident, numbers=numbers, **{'pass': passed})


class Host:
    def __init__(self, name):
        # Lazy import makes parser tests fully independent of device tools.
        from coverage_device import adb, request, unlocked
        self.adb, self.request, self.unlocked = adb, request, unlocked
        self.out = Path(__file__).resolve().parent/'coverage_evidence'
        self.name, self.rows = name, []
        self.cursor = None

    def save(self):
        (self.out/(self.name+'.json')).write_text(json.dumps(
            dict(status='done', records=self.rows), ensure_ascii=False, indent=2), encoding='utf-8')

    def command(self, action='snapshot', **args):
        response = self.request('/run?'+urllib.parse.urlencode(dict(group='video', action=action, **args)))
        deadline = time.monotonic()+45
        while response['status'] == 'running':
            if time.monotonic() >= deadline: raise TimeoutError(action)
            time.sleep(.15)
            response = self.request('/')
        start = self.cursor if self.cursor is not None and self.cursor <= len(response['records']) else max(
            (i for i, r in enumerate(response['records']) if r.get('kind') == 'BEGIN'), default=0)
        current = response['records'][start:]
        self.cursor = len(response['records'])
        self.current = current
        if response['status'] != 'done': raise RuntimeError(current)
        self.rows += [r for r in current if r.get('kind') not in ('BEGIN', 'END')]
        return next((r['state'] for r in reversed(current) if r.get('kind') == 'VIDEO'), {})

    def native(self, phase):
        window = self.adb('shell', 'dumpsys', 'window')
        activity = self.adb('shell', 'dumpsys', 'activity', 'activities')
        for category, content in [('window', window), ('activity', activity)]:
            (self.out/(self.name+'.'+phase+'.'+category+'.txt')).write_text(content, encoding='utf-8')
        return dict(window_values(window), pinned=pinned_value(activity))

    def check(self, ident, numbers, expected):
        row = observation(ident, numbers, expected)
        self.rows.append(row)
        self.save()

    def windows(self):
        self.unlocked()
        self.command('dispose')
        self.command('snapshot')
        self.command('orient', value='portrait')
        baseline = self.native('baseline')
        for mode in ('landscape', 'portrait', 'auto'):
            if mode == 'auto': self.command('fullscreen', value='true')
            state = self.command('orient', value=mode)
            native = self.native('orient-'+mode)
            numbers = dict(native, stateOrient=state.get('orient'))
            if 'width' in native and 'height' in native:
                numbers['landscape'] = native['width'] > native['height']
            expected = dict(stateOrient=mode, focused=True)
            if mode != 'auto': expected['landscape'] = mode == 'landscape'
            else:
                # auto in fullscreen follows actual decoded video dimensions;
                # outside fullscreen the device's physical rotation is free.
                size = re.fullmatch(r'(\d+)x(\d+)', state.get('size', ''))
                expected['landscape'] = int(size[1]) >= int(size[2]) if size and int(size[1]) > 0 else None
                numbers['videoSize'] = state.get('size')
                numbers['videoLandscape'] = expected['landscape']
            self.check('A16.window.'+mode, numbers, expected)
        self.command('fullscreen', value='false')
        self.command('orient', value='portrait')
        baseline = self.native('before-fullscreen')
        for value in (True, False):
            state = self.command('fullscreen', value=str(value).lower())
            native = self.native('fullscreen-'+str(value).lower())
            numbers = dict(native, fullscreen=state.get('fullscreen'))
            numbers.update(baselineStatus=baseline.get('status'), baselineNavigation=baseline.get('navigation'),
                           baselineRotation=baseline.get('rotation'))
            expected = dict(fullscreen=value, focused=True)
            for bar in ('status', 'navigation'):
                expected[bar] = False if value else baseline.get(bar)
            if not value: expected['rotation'] = baseline.get('rotation')
            self.check('A14.window.'+('enter' if value else 'restore'), numbers, expected)

    def pip(self):
        self.unlocked()
        before_state = self.command('miniHost')
        self.command('miniInfo')
        mini_before = next((r for r in self.current if r.get('kind') == 'MINI_INFO'), {})
        before = self.native('before-pip')
        self.command('pip')
        returned = next((r.get('value') for r in self.current if r.get('kind') == 'PIP_RETURN'), None)
        entered = self.native('pip-entered')
        state = self.command()
        self.check('A18.pinned.enter', dict(entered, pip=state.get('pip'), mini=state.get('mini'), returned=returned),
                   dict(pinned=True, pip=True, mini=False, returned=True))
        self.command('miniInfo')
        mini_after = next((r for r in self.current if r.get('kind') == 'MINI_INFO'), {})
        self.check('A15.miniHostToPip', dict(showingBefore=mini_before.get('showing'),
                   mountBefore=mini_before.get('mount'), showingAfter=mini_after.get('showing'),
                   mini=state.get('mini'), pinned=entered.get('pinned'),
                   epochBefore=before_state.get('epoch'), epochAfter=state.get('epoch')),
                   dict(showingBefore=True, mountBefore='host', showingAfter=False, mini=False,
                        pinned=True, epochAfter=before_state.get('epoch')))
        self.adb('shell', 'am', 'start', '-n', PACKAGE+'/com.icodejoo.mova.mova_example.MainActivity')
        expanded = self.native('pip-expanded')
        state = self.command()
        self.check('A18.pinned.expand', dict(expanded, pip=state.get('pip')), dict(pinned=False, pip=False))
        self.command('miniInfo')
        mini_expanded = next((r for r in self.current if r.get('kind') == 'MINI_INFO'), {})
        self.check('A15.pipExpanded', dict(mini=state.get('mini'), pip=state.get('pip'),
                   showing=mini_expanded.get('showing'), pinned=expanded.get('pinned')),
                   dict(mini=False, pip=False, showing=False, pinned=False))
        self.command('pip')
        pinned = self.native('pip-second-entry')
        # Ask SystemUI for controls. No hardcoded screen coordinate is used.
        self.adb('shell', 'input', 'keyevent', 'KEYCODE_WINDOW')
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/s00c-pip.xml')
        xml = self.adb('shell', 'cat', '/sdcard/s00c-pip.xml')
        (self.out/(self.name+'.pip-controls.xml')).write_text(xml, encoding='utf-8')
        center = close_bounds(xml) if pinned.get('pinned') is True else None
        if center is not None:
            self.adb('shell', 'input', 'tap', *map(str, center))
        closed = self.native('pip-closed')
        state = self.command()
        if center is None:
            self.rows.append(dict(kind='CHECK', id='A18.pinned.close', **{'pass': None},
                numbers=dict(closed, enteredPinned=pinned.get('pinned')), reason='系统关闭控件未定位；未点击 X'))
            self.save()
            self.adb('shell', 'am', 'start', '-n', PACKAGE+'/com.icodejoo.mova.mova_example.MainActivity')
            return
        self.check('A18.pinned.close', dict(closed, pip=state.get('pip'), closeLocated=True,
                  enteredPinned=pinned.get('pinned'), baselinePinned=before.get('pinned')),
                  dict(pinned=False, pip=False, closeLocated=True, enteredPinned=True))
        transitions = [r.get('payload', {}).get('value') for r in self.rows if r.get('event') == 'MovaPipChange']
        self.check('N9.transitions', dict(values=transitions), dict(values=[True, False, True, False]))

    def keepalive_pip(self):
        self.command('dispose')
        self.command(url='http://127.0.0.1:18080/live.flv?gop=50&audio=1', live='true')
        held = self.command('keepAlive', value='true')
        mark = len(self.rows)
        self.command('pip')
        deadline = time.monotonic()+20
        state = self.command()
        while state.get('keepAlive') == 'resuming' and time.monotonic() < deadline:
            state = self.command()
        native = self.native('keepalive-pip')
        resumes = [r for r in self.rows[mark:] if r.get('event') == 'MovaKeepAliveResume']
        self.check('F5.pipWake', dict(phaseBefore=held.get('keepAlive'), phaseAfter=state.get('keepAlive'),
                   pinned=native.get('pinned'), pip=state.get('pip'), mini=state.get('mini'),
                   resumeEvents=len(resumes), hasResume=bool(resumes)),
                   dict(phaseBefore='holding', phaseAfter='off', pinned=True, pip=True, mini=False, hasResume=True))
        self.adb('shell', 'am', 'start', '-n', PACKAGE+'/com.icodejoo.mova.mova_example.MainActivity')
        self.command('dispose')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='s00c-native')
    parser.add_argument('--pip', action='store_true')
    args = parser.parse_args()
    host = Host(args.name)
    try:
        host.windows()
        if args.pip:
            host.pip()
            host.keepalive_pip()
    except Exception as error:
        host.rows.append(dict(kind='SCRIPT_ERROR', error=str(error)))
        raise
    finally:
        try:
            # Leave the API page in foreground for the next legacy API batch.
            host.adb('shell', 'am', 'start', '-n', PACKAGE+'/com.icodejoo.mova.mova_example.MainActivity')
            host.command('dispose')
        finally:
            host.save()


if __name__ == '__main__':
    main()
