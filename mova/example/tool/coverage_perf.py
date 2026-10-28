"""Host performance runner; stdlib only. Never launches adb on import or --help.

Build/run main_coverage_perf.dart in release first. Android forwarding is explicit
and limited to this runner's control/media ports. Raw evidence is flushed JSONL.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import time
import urllib.request
from perf_judge import VERSION, LEAK_LIMITS, summarize, judge
from run_matrix import shot_allowed

TOOL = Path(__file__).resolve().parent
SCENES = {'vod-hw': 'PF1', 'vod-sw': 'PF2', 'live': 'PF3', 'cutover': 'PF4',
          'feed': 'PF5', 'soak-vod': 'PF6', 'soak-live': 'PF7', 'audio': 'PF11'}
DRIVER = None
RUN = 'setup'
CASE = 'perf:HARNESS'


def log(kind, data):
    line = (f'[MOVA-COV] {datetime.now(timezone.utc).isoformat(timespec="milliseconds")} '
            f'<run={RUN}> <case={CASE}> {kind} {json.dumps(data, ensure_ascii=False)}')
    if DRIVER:
        with DRIVER.open('a', encoding='utf-8', newline='\n') as stream:
            stream.write(line + '\n')


def command(argv):
    start = time.monotonic()
    log('CALL', {'argv': argv})
    try:
        result = subprocess.run(argv, capture_output=True, text=True, encoding='utf-8',
                                errors='replace', timeout=25, check=True)
        log('RET', {'argv': argv, 'code': result.returncode, 'stdout': result.stdout,
                    'stderr': result.stderr, 'elapsed_seconds': time.monotonic() - start})
        return result.stdout.strip()
    except subprocess.SubprocessError as error:
        log('RET', {'argv': argv, 'exception': repr(error),
                    'stdout': str(getattr(error, 'stdout', '')),
                    'stderr': str(getattr(error, 'stderr', '')),
                    'elapsed_seconds': time.monotonic() - start})
        raise


def control(endpoint, data=None):
    req = urllib.request.Request('http://127.0.0.1:18089/' + endpoint,
                                 data=json.dumps(data).encode() if data is not None else None,
                                 headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


class Android:
    def __init__(self, serial, package, thermal=False):
        if not re.fullmatch(r'[\w.]+', package):
            raise ValueError('invalid Android package')
        self.prefix = ['adb', '-s', serial]
        self.package, self.thermal = package, thermal
        self.last = None
        # /proc/uptime and CLK_TCK avoid top's vendor-specific CPU normalization.
        self.hz = float(self.shell('getconf CLK_TCK'))

    def shell(self, script):
        return command(self.prefix + ['shell', script])

    def optional(self, script):
        try:
            return self.shell(script)
        except subprocess.SubprocessError:
            return ''

    def proc(self, script):
        value = self.optional(script)
        return value or self.optional('run-as ' + self.package + ' sh -c ' + "'" + script + "'")

    def foreground_ok(self):
        """读取前台并判定能否截图，返回 (是否允许, 原因)；读取失败按未知拒绝。"""
        try:
            dumps = []
            for what in ('activity activities', 'window'):
                # 不走 command()：dumpsys 输出很大，不进 driver.log。
                done = subprocess.run(self.prefix + ['shell', 'dumpsys ' + what], capture_output=True,
                                      text=True, encoding='utf-8', errors='replace', timeout=25, check=True)
                dumps.append(done.stdout)
        except (OSError, subprocess.SubprocessError) as error:
            return False, 'foreground=unknown (dumpsys failed: ' + repr(error) + ')'
        return shot_allowed(dumps[0], dumps[1], self.package)

    def screenshot(self, path):
        """截图的唯一入口：截前截后各核对前台，不是被测包（或在画中画）就不落盘；返回 (是否写入, 原因)。"""
        allowed, reason = self.foreground_ok()
        if not allowed:
            return False, reason
        done = subprocess.run(self.prefix + ['exec-out', 'screencap', '-p'], capture_output=True,
                              timeout=25, check=False)
        allowed, reason = self.foreground_ok()
        if not allowed:
            return False, reason + ' (changed while capturing; discarded)'
        path.write_bytes(done.stdout)
        return True, reason

    def identity(self):
        return {'device': self.prefix[2], 'model': self.shell('getprop ro.product.model'),
                'os': self.shell('getprop ro.build.version.release'),
                'build': self.shell('getprop ro.build.fingerprint')}

    def reset(self):
        self.last = None
        self.shell('dumpsys gfxinfo ' + self.package + ' reset')

    def sample(self, expected_pid):
        pids = self.shell('pidof ' + self.package).split()
        if str(expected_pid) not in pids:
            raise RuntimeError('target process disappeared/restarted')
        pid = str(expected_pid)
        row = {}
        stat = self.proc('cat /proc/' + pid + '/stat')
        if stat:
            fields = stat[stat.rfind(')') + 2:].split()
            ticks = int(fields[11]) + int(fields[12])
            uptime = float(self.shell('cat /proc/uptime').split()[0])
            if self.last:
                dt = uptime - self.last[0]
                if dt > 0:
                    row['cpu'] = max(0, ticks - self.last[1]) / self.hz / dt * 100
            self.last = uptime, ticks
        status = self.proc('cat /proc/' + pid + '/status')
        match = re.search(r'^Threads:\s*(\d+)', status, re.M)
        row['threads'] = int(match[1]) if match else None
        # Do not pipe ls into wc: permission failures otherwise look like zero fds.
        fds = self.proc('ls /proc/' + pid + '/fd')
        row['fd'] = len(fds.split()) if fds else None
        mem = self.shell('dumpsys meminfo ' + self.package)
        for key, label in [('pss_kb', r'TOTAL PSS:'), ('native_kb', r'Native Heap'),
                           ('graphics_kb', r'Graphics:'), ('egl_kb', r'EGL mtrack')]:
            match = re.search(label + r'\s+(\d+)', mem)
            if key == 'pss_kb' and not match:
                match = re.search(r'^\s*TOTAL\s+(\d+)', mem, re.M)
            row[key] = int(match[1]) if match else None
        gfx = self.shell('dumpsys gfxinfo ' + self.package)
        # gfxinfo 只统计原生 HWUI；Flutter 帧由设备端 addTimingsCallback 提供 janky/gfx_frames，
        # 这里仅作辅助记录，不能覆盖同名字段。
        for key, label in [('gfxinfo_janky', 'Janky frames:'), ('gfxinfo_frames', 'Total frames rendered:')]:
            match = re.search(label + r'\s*(\d+)', gfx)
            row[key] = int(match[1]) if match else None
        if self.thermal:
            battery = self.optional('dumpsys battery')
            match = re.search(r'temperature:\s*(\d+)', battery)
            row['battery_temperature_tenths_c'] = int(match[1]) if match else None
            row['thermal'] = self.optional('dumpsys thermalservice')
        return row


class Windows:
    def __init__(self):
        self.last = None

    def identity(self):
        return {'device': 'windows-' + platform.node(), 'model': platform.machine(),
                'os': platform.platform()}

    def reset(self):
        self.last = None

    def sample(self, expected_pid):
        # Numeric PID only; Get-Process CPU is cumulative seconds across all cores.
        pid = int(expected_pid)
        value = json.loads(command(['powershell', '-NoProfile', '-NonInteractive', '-Command',
            f'$p=Get-Process -Id {pid} -ErrorAction Stop; '
            '[pscustomobject]@{cpu=$p.CPU; rss=$p.WorkingSet64; '
            'threads=$p.Threads.Count; handles=$p.HandleCount; '
            'start=$p.StartTime.ToUniversalTime().ToString("o")} | ConvertTo-Json -Compress']))
        now = time.monotonic()
        row = {'rss_kb': value['rss'] / 1024, 'threads': value['threads'],
               'handles': value['handles']}
        if self.last:
            if value['start'] != self.last[2]:
                raise RuntimeError('target process restarted')
            row['cpu'] = max(0, value['cpu'] - self.last[1]) / (now - self.last[0]) * 100
        self.last = now, value['cpu'], value['start']
        return row


def sources(args):
    if args.sources == 'local':
        return {'vod': args.vod_url, 'live': args.live_url, 'feed': args.feed_url}
    data = json.loads((TOOL / 'online_sources.json').read_text(encoding='utf-8'))
    if isinstance(data, dict):
        data = data.get('sources', [])
    playable = [r for r in data if r.get('verify', {}).get('libmpv_slim') == 'play']
    result = {}
    for row in playable:
        category = str(row.get('kind', '')) + ' ' + str(row.get('category', ''))
        key = 'live' if 'live' in category.lower() or '直播' in category else 'vod'
        result.setdefault(key, row['url'])
    if 'vod' in result:
        result.setdefault('feed', result['vod'])
    return result


def record_baseline(report, baseline, compatible, baseline_path):
    """按场景写基线：只有完整且无失败的场景才会写入/覆盖，其余场景保持原样。

    Record per scene: only complete, failure-free evidence becomes a reference;
    a failing scene never overwrites its old entry. Returns recorded scene names.
    """
    valid = {name: r for name, r in report['scenarios'].items()
             if not r['verdict']['failures'] and
             set(r['verdict']['blocked']) <= {'no-baseline', 'incompatible-baseline'}}
    if not valid:
        return []
    metadata = {k: v for k, v in report.items() if k != 'scenarios'}
    saved = baseline if compatible else dict(metadata, scenarios={})
    saved['commit'] = metadata['commit']
    saved['scenarios'].update(valid)
    baseline_path.parent.mkdir(parents=True, exist_ok=True)
    baseline_path.write_text(json.dumps(saved, indent=2), encoding='utf-8', newline='\n')
    return list(valid)


def main():
    global DRIVER, RUN, CASE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform', choices=['android', 'windows'], required=True)
    parser.add_argument('--serial')
    parser.add_argument('--package', default='com.icodejoo.mova.mova_example')
    parser.add_argument('--scenes', default='vod-hw,vod-sw,live,cutover,feed,soak-vod,soak-live')
    parser.add_argument('--seconds', type=float, default=600)
    parser.add_argument('--soak-seconds', type=float, default=480,
                        help='浸泡场景单场秒数（缩短版，原 3600）')
    parser.add_argument('--audio-seconds', type=float, default=180,
                        help='audio 场景秒数（缩短版，其余普通场景见 --seconds）')
    parser.add_argument('--audio-warmup', type=float, default=30,
                        help='audio 场景预热秒数；180s 减 60s 达不到 120s 稳态门槛，故单独设置')
    parser.add_argument('--interval', type=float, default=2)
    parser.add_argument('--warmup', type=float, default=60)
    parser.add_argument('--regression', type=float, default=.20)
    parser.add_argument('--record-baseline', action='store_true')
    parser.add_argument('--sources', choices=['local', 'online'], default='local')
    parser.add_argument('--vod-url', default='http://127.0.0.1:18085/perf-1080.mp4')
    parser.add_argument('--live-url', default='http://127.0.0.1:18085/live/index.m3u8')
    parser.add_argument('--feed-url', default='http://127.0.0.1:18085/perf-720.mp4',
                        help='feed 场景源；默认 720p，避免设备三路 1080p 硬解并发失败')
    parser.add_argument('--thermal', action='store_true')
    parser.add_argument('--forward', action='store_true', help='Android: adb forward control and reverse media')
    parser.add_argument('--leak-limits', type=Path, help='JSON metric: [units/hour, absolute delta] overrides')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if min(args.seconds, args.soak_seconds, args.audio_seconds, args.interval) <= 0 or min(args.warmup, args.audio_warmup) < 0 or args.regression < 0:
        parser.error('durations/interval must be positive; warmup/regression nonnegative')
    scenes = args.scenes.split(',')
    if any(s not in SCENES for s in scenes):
        parser.error('unknown scene')
    if args.platform == 'android' and not args.serial:
        parser.error('--serial required for Android')
    args.output.mkdir(parents=True, exist_ok=True)
    DRIVER, RUN = args.output / 'driver.log', args.output.name
    source_list = sources(args)
    sampler = Windows() if args.platform == 'windows' else Android(args.serial, args.package, args.thermal)
    if args.forward and args.platform == 'android':
        command(sampler.prefix + ['forward', 'tcp:18089', 'tcp:18089'])
        command(sampler.prefix + ['reverse', 'tcp:18085', 'tcp:18085'])
    identity = sampler.identity()
    device = re.sub(r'[^\w.-]', '_', identity['device'])
    baseline_path = TOOL / 'perf_baseline' / (device + '.json')
    baseline = json.loads(baseline_path.read_text(encoding='utf-8')) if baseline_path.exists() else None
    limits = dict(LEAK_LIMITS)
    if args.leak_limits:
        limits.update(json.loads(args.leak_limits.read_text(encoding='utf-8')))
    configuration = {'version': VERSION, 'sources_hash': hashlib.sha256(
        json.dumps(source_list, sort_keys=True).encode()).hexdigest(),
        'interval': args.interval, 'warmup': args.warmup, 'seconds': args.seconds,
        'soak_seconds': args.soak_seconds, 'audio_seconds': args.audio_seconds,
        'audio_warmup': args.audio_warmup, 'leak_limits': {k: list(v) for k, v in limits.items()},
        'platform': args.platform, 'thermal': args.thermal}
    metadata = dict(identity=identity, configuration=configuration, sources=source_list,
                    commit=command(['git', '-C', str(TOOL), 'rev-parse', 'HEAD']))
    compatible = baseline and baseline['identity'] == identity and baseline['configuration'] == configuration
    args.output.mkdir(parents=True, exist_ok=True)
    report = dict(metadata, scenarios={})
    for scene in scenes:
        CASE = 'perf:' + SCENES[scene] + '.' + scene
        rows = []
        started = False
        logcat = None
        logcat_stream = None
        seconds = (args.soak_seconds if scene.startswith('soak-') else
                   args.audio_seconds if scene == 'audio' else args.seconds)
        warmup = args.audio_warmup if scene == 'audio' else args.warmup
        url = source_list.get('live' if 'live' in scene else 'feed' if scene == 'feed' else 'vod')
        print(f'{SCENES[scene]} {scene}: {seconds}s', flush=True)
        try:
            if not url:
                raise RuntimeError('no verified source for scene')
            sampler.reset()
            initial = control('start', {'scene': scene, 'seconds': seconds, 'url': url,
                                        'run': args.output.name, 'interval': args.interval})
            pid = initial['pid']
            started = True
            if args.platform == 'android':
                logcat_stream = (args.output / (scene + '.logcat')).open('wb')
                logcat = subprocess.Popen(sampler.prefix + ['logcat', f'--pid={int(pid)}',
                    '-v', 'threadtime'], stdout=logcat_stream, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + seconds + 120
            with (args.output / (scene + '.jsonl')).open('w', encoding='utf-8', newline='\n') as stream:
                last_t = -1
                while True:
                    tick = time.monotonic()
                    state = control('status')
                    if state['pid'] != pid:
                        raise RuntimeError('control process restarted')
                    sample = state['sample']
                    if sample and sample['t'] > last_t:
                        # 宿主读不到的字段（如 release 包的 fd）为 None 时，保留设备端上报值。
                        host = {k: v for k, v in sampler.sample(pid).items() if v is not None}
                        row = dict(sample, **host)
                        rows.append(row)
                        stream.write(json.dumps(row, ensure_ascii=False) + '\n')
                        stream.flush()
                        log('STATE', row)
                        last_t = sample['t']
                    if not state['busy']:
                        if state['result'].get('status') != 'COLLECTED':
                            raise RuntimeError(str(state['result']))
                        break
                    if time.monotonic() > deadline:
                        raise TimeoutError('scene deadline exceeded')
                    time.sleep(max(0, args.interval - (time.monotonic() - tick)))
            summary = summarize(rows, warmup)
            old = baseline['scenarios'].get(scene, {}).get('summary') if compatible else None
            verdict = judge(summary, old, args.regression, args.platform, scene == 'audio', limits)
            if baseline and not compatible:
                verdict['blocked'].append('incompatible-baseline')
            report['scenarios'][scene] = {'summary': summary, 'verdict': verdict}
        except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
            log('ERROR', {'kind': 'HARNESS', 'exception': repr(error)})
            report['scenarios'][scene] = {'summary': summarize(rows, warmup),
                'verdict': {'status': 'BLOCKED', 'blocked': ['harness:' + str(error)], 'failures': []}}
        finally:
            if logcat:
                logcat.terminate()
                try:
                    logcat.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    logcat.kill()
                    logcat.wait()
            if logcat_stream:
                logcat_stream.close()
        verdict = report['scenarios'][scene]['verdict']
        log('EXPECT', {'regression': args.regression, 'leak_limits': limits,
                       'r2_min': .7, 'warmup_seconds': warmup})
        log('ACTUAL', report['scenarios'][scene]['summary'])
        log('VERDICT', verdict)
        try:
            if verdict['status'] == 'FAIL' and args.platform == 'android':
                for kind in ('window', 'audio'):
                    (args.output / (scene + '.' + kind + '.txt')).write_text(
                        sampler.optional('dumpsys ' + kind), encoding='utf-8', newline='\n')
                shot = args.output / (scene + '.png')
                written, reason = sampler.screenshot(shot)
                log('SHOT', {'path': str(shot)} if written else {'skipped': reason, 'path': str(shot)})
        except (OSError, subprocess.SubprocessError) as error:
            log('ERROR', {'kind': 'HARNESS', 'capture': repr(error)})
        finally:
            if started:
                try:
                    state = control('finish', {})
                    end = time.monotonic() + 50
                    while state.get('running') and time.monotonic() < end:
                        time.sleep(.2)
                        state = control('status')
                    if state.get('running'):
                        raise TimeoutError('dispose deadline exceeded')
                    if state.get('result', {}).get('status') == 'BLOCKED':
                        verdict['status'] = 'BLOCKED'
                        verdict['blocked'].append('harness:dispose')
                except (OSError, ValueError) as error:
                    verdict['status'] = 'BLOCKED'
                    verdict['blocked'].append('harness:finish:' + str(error))
        print(json.dumps(report['scenarios'][scene]['verdict']), flush=True)
        (args.output / 'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8', newline='\n')
    if args.record_baseline:
        recorded = record_baseline(report, baseline, compatible, baseline_path)
        print('baseline recorded: ' + str(baseline_path) + ' scenes=' + ','.join(recorded)
              if recorded else 'baseline NOT recorded: no valid scene')
        skipped = [k for k in report['scenarios'] if k not in recorded]
        if recorded and skipped:
            print('baseline skipped (failing/incomplete evidence): ' + ','.join(skipped))
    statuses = [r['verdict']['status'] for r in report['scenarios'].values()]
    return 1 if 'FAIL' in statuses else 2 if 'BLOCKED' in statuses else 0


if __name__ == '__main__':
    raise SystemExit(main())
