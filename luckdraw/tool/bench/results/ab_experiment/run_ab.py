"""受控手机设置实验；运行期间不执行任何额外 adb 采样。"""

import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess as sp
import time

ROOT = Path(__file__).resolve().parent
BENCH = ROOT.parents[1]
DEVICE = '10AE9K17UE0011S'
ADB = r'E:\sdk\android\platform-tools\adb.exe'
FLUTTER = r'E:\sdk\flutter\bin\flutter.bat'
APK = BENCH / 'results/perf_ablation/perf.apk'
UTF8 = 'utf-8'
LIMIT = 15


def now():
    """返回带时区的采集时间。"""
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write(path, data):
    """只在实验目录落盘，统一使用 LF。"""
    path.resolve().relative_to(ROOT)
    path.write_text(data, encoding=UTF8, newline='\n')


def dump(path, data):
    """保存可复核 JSON。"""
    write(path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def command(args, timeout=30):
    """有界运行单条命令并记录状态，不使用 shell 插值。"""
    started = now()
    try:
        p = sp.run(args, capture_output=True, timeout=timeout)
        return dict(startedAt=started, endedAt=now(), command=args,
                    exitCode=p.returncode,
                    stdout=p.stdout.decode(UTF8, errors='replace'),
                    stderr=p.stderr.decode(UTF8, errors='replace'))
    except sp.TimeoutExpired as error:
        return dict(startedAt=started, endedAt=now(), command=args,
                    exitCode=-1, stdout=(error.stdout or b'').decode(UTF8, errors='replace'),
                    stderr='COMMAND TIMEOUT')


def adb(*args):
    """调用唯一授权设备。"""
    return command([ADB, '-s', DEVICE, *args])


def checked(*args):
    """设备设置失败时终止，不默默继续。"""
    result = adb(*args)
    if result['exitCode']:
        raise RuntimeError(result)
    return result['stdout'].strip()


def settings():
    """在窗口外核实三个设置。"""
    return dict(mode=checked('shell', 'settings', 'get', 'system', 'screen_brightness_mode'),
                brightness=checked('shell', 'settings', 'get', 'system', 'screen_brightness'),
                stayon=checked('shell', 'settings', 'get', 'global', 'stay_on_while_plugged_in'))


def configure(condition):
    """应用条件设置；USB 常亮为所有条件共有。"""
    mode, brightness = ('0', '1') if condition == 'B' else ('1', '12')
    checked('shell', 'settings', 'put', 'system', 'screen_brightness_mode', mode)
    checked('shell', 'settings', 'put', 'system', 'screen_brightness', brightness)
    checked('shell', 'svc', 'power', 'stayon', 'usb')
    actual = settings()
    if actual['mode'] != mode or actual['stayon'] != '2' or (condition == 'B' and actual['brightness'] != brightness):
        raise RuntimeError(f'SETTING MISMATCH {actual}')
    if condition != 'B' and actual['brightness'] != brightness:
        print(f'AUTO_BRIGHTNESS_UPDATED commanded={brightness} observed={actual["brightness"]}', flush=True)
    return actual


def snapshot(directory, log_start):
    """驱动结束后立即串行读取，保留命令时间及原始输出。"""
    queries = [
        ('battery_after', ['dumpsys', 'battery']),
        ('window_after', ['dumpsys', 'window']),
        ('display', ['dumpsys', 'display']),
        ('surfaceflinger', ['dumpsys SurfaceFlinger | head -200']),
        ('getprop', ['getprop']),
        ('thermal', ['for z in /sys/class/thermal/thermal_zone*; do echo "$z"; cat "$z/type" "$z/temp"; done']),
    ]
    results = {}
    for name, args in queries:
        result = adb('shell', *args)
        results[name] = result
        write(directory / f'{name}.txt', result['stdout'] + result['stderr'])
    # 只在结束后读日志，用于检查窗口内锁屏/灭屏事件；不清空共享日志。
    result = adb('logcat', '-d', '-b', 'all', '-v', 'epoch', '-T', log_start)
    results['logcat_after'] = result
    write(directory / 'logcat_after.txt', result['stdout'] + result['stderr'])
    dump(directory / 'snapshot_commands.json', results)
    return results


def unlocked_window():
    """每次启动前等待明确解锁，最多十五分钟。"""
    deadline = time.monotonic() + 900
    while True:
        result = adb('shell', 'dumpsys', 'window')
        match = re.search(r'isKeyguardShowing=(true|false)', result['stdout'])
        if result['exitCode'] or not match:
            raise RuntimeError('Cannot verify isKeyguardShowing')
        if match[1] == 'false':
            return result
        if time.monotonic() >= deadline:
            raise RuntimeError('LOCK_TIMEOUT 15 minutes')
        print('LOCK_WAIT', flush=True)
        time.sleep(15)


def free_memory():
    """只读主机空闲物理内存，不向手机发送命令。"""
    p = command(['powershell.exe', '-NoProfile', '-Command',
                 '(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory'])
    free = int(p['stdout'].strip())
    if free < 2097152:
        raise RuntimeError(f'FreePhysicalMemory < 2 GiB: {free} KiB')
    return free


def main():
    """以固定交错顺序采齐九轮，有效组不追加筛选。"""
    records = json.loads((ROOT / 'runs.json').read_text(encoding=UTF8)) if (ROOT / 'runs.json').exists() else []
    manifest = dict(createdAt=now(), device=DEVICE,
         apk=str(APK), apkBytes=APK.stat().st_size,
         apkSha256=hashlib.sha256(APK.read_bytes()).hexdigest(),
         route='/wheel_picture', scenario='wheel_steady',
         order=['A1', 'B1', 'C1', 'A2', 'B2', 'C2', 'A3', 'B3', 'C3'],
         hostPollingDuringRun=False, mainSessionWatchdogStillRunning=True,
         driverChanges='Only metrics import URI and host output/current directory; APK unchanged')
    if (ROOT / 'manifest.json').exists():
        prior = json.loads((ROOT / 'manifest.json').read_text(encoding=UTF8))
        if prior['apkSha256'] != manifest['apkSha256'] or prior['route'] != manifest['route']:
            raise RuntimeError('Resume requires identical APK and route')
        if any('endedAt' not in r for r in records):
            raise RuntimeError('Do not resume while a previous launch is unfinished')
    else:
        dump(ROOT / 'manifest.json', manifest)
    try:
        for round_number in range(1, 4):
            for condition in ('A', 'B', 'C'):
                label = f'{condition}{round_number}'
                prior_slot = [r for r in records if r['label'] == label]
                if any(r['valid'] for r in prior_slot):
                    continue
                for retry in range(LIMIT):
                    if retry < len(prior_slot):
                        continue
                    if len(records) >= LIMIT:
                        raise RuntimeError('15-start limit reached')
                    directory = ROOT / (label if retry == 0 else f'{label}_retry{retry}')
                    if directory.exists() and any(directory.iterdir()):
                        raise RuntimeError(f'Refuse overwrite of existing run output: {directory}')
                    directory.mkdir(exist_ok=True)
                    actual = configure(condition)
                    checked('shell', 'am', 'force-stop', 'com.example.luckdraw_bench')
                    rest_start = now()
                    print(f'REST {label} 60s settings={actual}', flush=True)
                    # 无设备查询，先让每个条件/轮次静置完整六十秒。
                    time.sleep(60)
                    rest_end = now()
                    before = unlocked_window()
                    write(directory / 'window_before.txt', before['stdout'])
                    battery = adb('shell', 'dumpsys', 'battery')
                    write(directory / 'battery_before.txt', battery['stdout'])
                    free = free_memory()
                    log_start = checked('shell', "date '+%m-%d %H:%M:%S.000'")
                    arguments = [FLUTTER, 'drive', '--profile', '--no-pub', '--no-dds',
                                 '-d', DEVICE, f'--driver={ROOT / "ab_driver.dart"}',
                                 '--target=integration_test/perf_bench_test.dart',
                                 '--dart-define=LUCKDRAW_TIMELINE=true', '--route=/wheel_picture',
                                 f'--use-application-binary={APK}']
                    env = {**os.environ, 'BENCH_PERF_OUTPUT': str(directory),
                           'BENCH_DEVICE_SERIAL': DEVICE, 'BENCH_DEVICE_MODEL': 'vivo V2417'}
                    record = dict(label=label, condition=condition, retry=retry,
                                  launchNumber=len(records)+1, restStartedAt=rest_start,
                                  restEndedAt=rest_end, startedAt=now(), settingsBefore=actual,
                                  freeKB=free, unlockedBefore=True, command=arguments,
                                  directory=directory.name, valid=False)
                    records.append(record)
                    dump(ROOT / 'runs.json', records)
                    print(f'START {label} launch={len(records)} freeKB={free}', flush=True)
                    start = time.monotonic()
                    with (directory / 'stdout.log').open('wb') as stdout, (directory / 'stderr.log').open('wb') as stderr:
                        p = sp.Popen(arguments, cwd=BENCH, env=env, stdout=stdout, stderr=stderr,
                                     creationflags=sp.CREATE_NO_WINDOW)
                        record['hostPid'] = p.pid
                        try:
                            # 运行期间只等待驱动结束；没有额外 adb/dumpsys/日志采样。
                            code = p.wait(timeout=300)
                            record['timedOut'] = False
                        except sp.TimeoutExpired:
                            command(['taskkill.exe', '/PID', str(p.pid), '/T', '/F'])
                            code = -1
                            record['timedOut'] = True
                    record.update(endedAt=now(), elapsedSeconds=time.monotonic()-start, exitCode=code)
                    snaps = snapshot(directory, log_start)
                    record['settingsAfter'] = settings()
                    window = snaps['window_after']['stdout']
                    post_locked = 'isKeyguardShowing=true' in window
                    log = snaps['logcat_after']['stdout']
                    lock_lines = [line for line in log.splitlines() if re.search(
                        r'isKeyguardShowing=true|keyguard_shown: \[1|screen_toggled: [012](?:\s|$)|mWakefulness=Asleep', line)]
                    write(directory / 'lock_event_candidates.txt', '\n'.join(lock_lines) + '\n')
                    record.update(lockedAfter=post_locked, lockEventCandidates=len(lock_lines))
                    summaries = list(directory.glob('wheel_steady_[0-9]*.timeline_summary.json'))
                    record['summaryFiles'] = [p.name for p in summaries]
                    if len(summaries) == 1:
                        metrics = json.loads(summaries[0].read_text(encoding=UTF8))
                        record['metrics'] = {k: v for k, v in metrics.items()
                                             if not isinstance(v, (dict, list))}
                        record['valid'] = code == 0 and not post_locked and not lock_lines and metrics['frame_count'] > 0 and metrics['rss_cycles'] == 5
                    dump(ROOT / 'runs.json', records)
                    raster = record.get('metrics', {}).get('average_frame_rasterizer_time_millis')
                    print(f'END {label} code={code} valid={record["valid"]} raster={raster}', flush=True)
                    checked('shell', 'am', 'force-stop', 'com.example.luckdraw_bench')
                    if record['valid']:
                        break
                    if code != 0 or not (post_locked or lock_lines):
                        raise RuntimeError(f'Non-lock failure: {label}; inspect before any retry')
    finally:
        restored = configure('B')
        dump(ROOT / 'restored_settings.json', dict(verifiedAt=now(), settings=restored))
        print(f'RESTORED {restored}', flush=True)


if __name__ == '__main__':
    main()
