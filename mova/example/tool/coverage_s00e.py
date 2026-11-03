"""S00e host collector. Import/parser tests never invoke device commands.

The explicit CLI is for a later authorized device run. This worktree only
uses synthetic parser tests. Raw dumps and per-command acknowledgements are
retained; an unsupported /proc or dumpsys format produces unknown, not zero.
"""
import argparse
import json
from pathlib import Path
import re
import time
import urllib.parse

PACKAGE = 'com.icodejoo.mova.mova_example.coverage'


def brightness(raw):
    value = raw.strip()
    return int(value) if re.fullmatch(r'\d+', value) else None


def window_brightness(raw):
    # Application brightness is a Window attribute, distinct from the global
    # screen_brightness setting. Never inspect a different application's window.
    sections = re.split(r'(?m)(?=^\s*Window #\d+ Window\{)', raw)
    values = []
    for section in sections:
        if PACKAGE not in section.split('\n', 1)[0]: continue
        values += re.findall(r'\bscreenBrightness=([0-9.]+)', section)
    return float(values[0]) if len(values) == 1 else None


def music_volume(raw):
    """Require an active output device and its STREAM_MUSIC Current entry."""
    section = re.search(r'(?ms)^\s*-?\s*STREAM_MUSIC:\s*\n(.*?)(?=^\s*-?\s*STREAM_[A-Z_]+:|\Z)', raw)
    if not section:
        return None
    devices = re.search(r'(?m)^\s*Devices:\s*(\S+)', section[1])
    current = re.search(r'(?m)^\s*Current:\s*(.+)', section[1])
    if not devices or not current:
        return None
    values = re.findall(r'([0-9a-fA-F]+)\s*\(([^)]+)\)\s*:\s*(\d+)', current[1])
    selected = [int(value) for key, name, value in values if devices[1] in (key, name)]
    return selected[0] if len(selected) == 1 else None


def process_values(status, stat, fds, meminfo):
    result = dict(rss=None, threads=None, handles=None, cpuTicks=None, pss=None)
    for key, pattern in [('rss', r'(?m)^VmRSS:\s+(\d+) kB$'), ('threads', r'(?m)^Threads:\s+(\d+)\s*$')]:
        match = re.search(pattern, status)
        if match:
            result[key] = int(match[1]) * (1024 if key == 'rss' else 1)
    # comm may contain spaces and parentheses. Remaining stat starts at field 3.
    tail = stat.rsplit(')', 1)[-1].split() if ')' in stat else []
    if len(tail) >= 13 and all(v.isdigit() for v in tail[11:13]):
        result['cpuTicks'] = sum(map(int, tail[11:13]))
    lines = fds.splitlines()
    if lines and all(re.fullmatch(r'\d+', value) for value in lines):
        result['handles'] = len(set(lines))
    match = re.search(r'(?m)^\s*TOTAL PSS:\s*(\d+)\b', meminfo)
    if not match:
        match = re.search(r'(?m)^\s*TOTAL\s+(\d+)\s+\d+', meminfo)
    if match:
        result['pss'] = int(match[1]) * 1024
    return result


def audio_session(raw, pid):
    """Keep only target playback configuration lines, require explicit state."""
    rows = [line.strip() for line in raw.splitlines()
            if re.search(r'(?:\bpid[:= ]+|\buid/pid:\d+/)' + re.escape(str(pid)) + r'\b', line)
            and 'state:' in line]
    states = [m[1].lower() for line in rows if (m := re.search(r'\bstate:\s*(started|paused|stopped|released)\b', line, re.I))]
    return dict(rows=rows, states=states or None)


def compare(ident, before, after, fields, *, changed=False):
    pairs = [(before.get(key), after.get(key)) for key in fields]
    passed = None if any(a is None or b is None for a, b in pairs) else all(
        b > a if changed else b == a for a, b in pairs)
    return dict(kind='CHECK', id=ident, origin='android-host-native',
                numbers=dict(before=before, after=after), **{'pass': passed})


class Host:
    def __init__(self, name):
        from coverage_device import adb, request, unlocked
        self.adb, self.request, self.unlocked = adb, request, unlocked
        self.out = Path(__file__).resolve().parent / 'coverage_evidence'
        self.out.mkdir(exist_ok=True)
        self.name, self.rows = name, []

    def raw(self, label, *args):
        try:
            value = self.adb(*args)
        except Exception as error:
            value = 'COLLECTOR_ERROR: ' + str(error)
        (self.out / (self.name + '.' + label + '.txt')).write_text(value, encoding='utf-8')
        return value

    def snapshot(self, label):
        bright = self.raw(label+'.brightness', 'shell', 'settings', 'get', 'system', 'screen_brightness')
        audio = self.raw(label+'.audio', 'shell', 'dumpsys', 'audio')
        pid = self.raw(label+'.pid', 'shell', 'pidof', PACKAGE).strip()
        window = self.raw(label+'.window', 'shell', 'dumpsys', 'window')
        activity = self.raw(label+'.activity', 'shell', 'dumpsys', 'activity', 'activities')
        from coverage_s00c import pinned_value
        result = dict(brightness=brightness(bright), appBrightness=window_brightness(window), volume=music_volume(audio), pid=None)
        result['pinned'] = pinned_value(activity)
        if re.fullmatch(r'\d+', pid):
            result['pid'] = int(pid)
            proc = {}
            for key, filename in [('status', 'status'), ('stat', 'stat')]:
                proc[key] = self.raw(label+'.'+key, 'shell', 'run-as', PACKAGE, 'cat', '/proc/'+pid+'/'+filename)
            proc['fds'] = self.raw(label+'.fd', 'shell', 'run-as', PACKAGE, 'ls', '-1', '/proc/'+pid+'/fd')
            proc['meminfo'] = self.raw(label+'.meminfo', 'shell', 'dumpsys', 'meminfo', PACKAGE)
            result.update(process_values(**proc))
            result['audioSession'] = audio_session(audio, pid)
        self.raw(label+'.battery', 'shell', 'dumpsys', 'batterystats', PACKAGE)
        self.rows.append(dict(kind='S00E_HOST_SAMPLE', label=label, numbers=result))
        return result

    def run(self):
        self.unlocked()
        self.adb('forward', 'tcp:18083', 'tcp:18083')
        response = self.request('/run?group=new&case=s00eNative')
        seen = set()
        deadline = time.monotonic() + 900
        while response['status'] == 'running':
            if time.monotonic() > deadline:
                raise TimeoutError('S00e native producer did not finish')
            start = max((i for i, row in enumerate(response['records']) if row.get('kind') == 'BEGIN'), default=0)
            for row in response['records'][start:]:
                token = row.get('token')
                if row.get('kind') == 'S00E_HOST_REQUEST' and token not in seen:
                    seen.add(token)
                    if row.get('phase', '').endswith('-background'):
                        self.adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
                    if row.get('phase', '').endswith('-foreground'):
                        self.adb('shell', 'am', 'start', '-n', PACKAGE+'/com.icodejoo.mova.mova_example.MainActivity')
                    sample = self.snapshot(token)
                    query = urllib.parse.urlencode(dict(token=token, sample=json.dumps(sample)))
                    self.request('/s00e-ack?' + query)
            time.sleep(.1)  # Poll scheduling only, never a product verdict.
            response = self.request('/')
        start = max((i for i, row in enumerate(response['records']) if row.get('kind') == 'BEGIN'), default=0)
        self.rows += response['records'][start:]
        return response['status']

    def save(self, status):
        (self.out / (self.name+'.json')).write_text(json.dumps(
            dict(status=status, records=self.rows), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[\w.-]+', args.name): parser.error('invalid evidence name')
    host, status = Host(args.name), 'error'
    try:
        status = host.run()
    finally:
        host.save(status)
    return 0 if status == 'done' else 1


if __name__ == '__main__':
    raise SystemExit(main())
