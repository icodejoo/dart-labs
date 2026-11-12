"""AB2：固定 APK/default auto，仅比较引擎后端，不在运行中轮询设备。"""

import datetime as dt
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess as sp
import time

ROOT = Path(__file__).resolve().parent
BENCH = ROOT.parents[2]
SPEC = importlib.util.spec_from_file_location('previous_ab', ROOT.parent / 'run_ab.py')
PREVIOUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREVIOUS)
APK = BENCH / 'results/perf_after/perf.apk'
LIMIT = 8
EXPECTED_SETTINGS = dict(mode='0', brightness='1', stayon='2')


def now():
    """返回 UTC 时间，供跨日志核对。"""
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write(path, data):
    """只写本批目录，使用 LF。"""
    path.resolve().relative_to(ROOT)
    path.write_text(data, encoding='utf-8', newline='\n')


def dump(path, data):
    """保存原始结构化证据。"""
    write(path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def source_hashes():
    """记录副本源码、配置和 APK 哈希，不改变文件。"""
    package = BENCH.parents[1]
    paths = sorted((package / 'lib').rglob('*.dart'))
    paths += [package / 'pubspec.yaml', package / 'analysis_options.yaml',
              BENCH / 'integration_test/perf_bench_test.dart', BENCH / 'lib/main.dart', APK]
    return {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}


def prepare_driver():
    """复用既有指标转换；只增加一次引擎状态读取和后端断言。"""
    source = (ROOT.parent / 'ab_driver.dart').read_text(encoding='utf-8')
    source = source.replace("import 'package:integration_test/integration_test_driver.dart';",
                            "import 'package:integration_test/common.dart';")
    source = source.replace('await integrationDriver(', 'await _verifiedIntegrationDriver(')
    source += '''
/// 读取引擎实际后端后接收原测试报告，后端不符则失败。
Future<void> _verifiedIntegrationDriver({
  required Duration timeout,
  required Future<void> Function(Map<String, dynamic>?) responseDataCallback,
}) async {
  final driver = await FlutterDriver.connect();
  if (driver is! VMServiceFlutterDriver) {
    await driver.close();
    throw StateError('AB2 需要安卓 VM 驱动');
  }
  try {
    final response = await driver.serviceClient.callServiceExtension(
      'ext.ui.window.impellerEnabled', isolateId: driver.appIsolate.id);
    final enabled = response.json?['enabled'];
    final requested = Platform.environment['BENCH_BACKEND'];
    final verified = enabled is bool &&
      (requested == 'skia' || requested == 'impeller') &&
      enabled == (requested == 'impeller');
    await File('backend.json').writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'requested': requested,
        'impeller_enabled': enabled,
        'verified': verified,
        'verified_by': 'ext.ui.window.impellerEnabled',
        'raw_response': response.json,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      })}\\n');
    if (!verified) throw StateError('请求后端与实际后端不一致');
    final result = Response.fromJson(await driver.requestData(null, timeout: timeout));
    if (!result.allTestsPassed) throw StateError(result.formattedFailureDetails);
    await responseDataCallback(result.data);
    stdout.writeln('All tests passed. Backend verified: $requested/$enabled');
  } finally {
    await driver.close();
  }
}
'''
    write(ROOT / 'compare_driver.dart', source)


def snapshot(directory, log_start):
    """驱动退出后立即先读 SF 前120行与 battery，随后获取其它事后证据。"""
    results = {}
    for name, args in [
        ('surfaceflinger', ['shell', 'dumpsys SurfaceFlinger | head -120']),
        ('battery_after', ['shell', 'dumpsys', 'battery']),
        ('window_after', ['shell', 'dumpsys', 'window']),
        ('display_after', ['shell', 'dumpsys', 'display']),
        ('logcat_after', ['logcat', '-d', '-b', 'all', '-v', 'epoch', '-T', log_start]),
    ]:
        result = PREVIOUS.adb(*args)
        results[name] = result
        write(directory / f'{name}.txt', result['stdout'] + result['stderr'])
    dump(directory / 'snapshot_commands.json', results)
    return results


def main():
    """固定六轮交错；无效轮仅允许补一次，整个实验最多八次启动。"""
    if (ROOT / 'runs.json').exists():
        raise RuntimeError('拒绝覆盖已运行实验')
    prepare_driver()
    initial_hashes = source_hashes()
    dump(ROOT / 'source_hashes_before.json', initial_hashes)
    manifest = dict(createdAt=now(), device=PREVIOUS.DEVICE, apk=str(APK),
                    apkBytes=APK.stat().st_size,
                    apkSha256=hashlib.sha256(APK.read_bytes()).hexdigest(),
                    scenario='wheel_steady', route='/wheel_default', cacheMode='auto',
                    order=['S1', 'I1', 'S2', 'I2', 'S3', 'I3'], launchLimit=LIMIT,
                    hostAdbPollingDuringRun=False,
                    mainSessionWatchdog='用户告知：每120秒仅查询锁屏，无法停止；本批未控制',
                    previousABNotReused='旧AB为perf_ablation APK + wheel_picture，配置及APK均不同')
    dump(ROOT / 'manifest.json', manifest)
    records = []
    try:
        for label in manifest['order']:
            condition = label[0]
            backend = 'skia' if condition == 'S' else 'impeller'
            for attempt in range(2):
                if len(records) >= LIMIT:
                    raise RuntimeError('已达8次启动上限')
                directory = ROOT / (label if attempt == 0 else f'{label}_retry{attempt}')
                directory.mkdir(exist_ok=False)
                actual = PREVIOUS.settings()
                if actual != EXPECTED_SETTINGS:
                    raise RuntimeError(f'设置变化；只读保持，不擅自修改: {actual}')
                PREVIOUS.checked('shell', 'am', 'force-stop', 'com.example.luckdraw_bench')
                rest_start = now()
                print(f'REST {label}: 60 seconds; settings={actual}', flush=True)
                time.sleep(60)
                rest_end = now()
                before = PREVIOUS.unlocked_window()
                write(directory / 'window_before.txt', before['stdout'])
                actual = PREVIOUS.settings()
                if actual != EXPECTED_SETTINGS:
                    raise RuntimeError(f'启动前设置变化: {actual}')
                battery = PREVIOUS.adb('shell', 'dumpsys', 'battery')
                write(directory / 'battery_before.txt', battery['stdout'])
                free = PREVIOUS.free_memory()
                log_start = PREVIOUS.checked('shell', "date '+%m-%d %H:%M:%S.000'")
                arguments = [PREVIOUS.FLUTTER, 'drive', '--profile', '--no-pub', '--no-dds',
                             '--verbose', '-d', PREVIOUS.DEVICE,
                             f'--driver={ROOT / "compare_driver.dart"}',
                             '--target=integration_test/perf_bench_test.dart',
                             '--dart-define=LUCKDRAW_TIMELINE=true', '--route=/wheel_default',
                             '--no-enable-impeller' if condition == 'S' else '--enable-impeller',
                             f'--use-application-binary={APK}']
                env = {**os.environ, 'BENCH_PERF_OUTPUT': str(directory),
                       'BENCH_DEVICE_SERIAL': PREVIOUS.DEVICE,
                       'BENCH_DEVICE_MODEL': 'vivo V2417', 'BENCH_BACKEND': backend}
                record = dict(label=label, condition=condition, backendRequested=backend,
                              attempt=attempt, launchNumber=len(records)+1,
                              restStartedAt=rest_start, restEndedAt=rest_end,
                              startedAt=now(), settingsBefore=actual, freeKB=free,
                              unlockedBefore=True, command=arguments,
                              directory=directory.name, valid=False)
                records.append(record)
                dump(ROOT / 'runs.json', records)
                print(f'START {label}: launch={len(records)} freeKB={free}', flush=True)
                start = time.monotonic()
                with (directory / 'stdout.log').open('wb') as out, (directory / 'stderr.log').open('wb') as err:
                    process = sp.Popen(arguments, cwd=BENCH, env=env, stdout=out, stderr=err,
                                       creationflags=sp.CREATE_NO_WINDOW)
                    record['hostPid'] = process.pid
                    try:
                        code = process.wait(timeout=300)
                        record['timedOut'] = False
                    except sp.TimeoutExpired:
                        # 只终止本轮创建的进程树，不按全局进程名清理。
                        PREVIOUS.command(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'])
                        code = -1
                        record['timedOut'] = True
                record.update(endedAt=now(), elapsedSeconds=time.monotonic()-start, exitCode=code)
                snaps = snapshot(directory, log_start)
                record['settingsAfter'] = PREVIOUS.settings()
                locked = 'isKeyguardShowing=true' in snaps['window_after']['stdout']
                lock_lines = [line for line in snaps['logcat_after']['stdout'].splitlines()
                              if re.search(r'isKeyguardShowing=true|keyguard_shown: \[1|screen_toggled: [012](?:\s|$)|mWakefulness=Asleep', line)]
                write(directory / 'lock_event_candidates.txt', '\n'.join(lock_lines) + '\n')
                record.update(lockedAfter=locked, lockEventCandidates=len(lock_lines))
                backend_path = directory / 'backend.json'
                if backend_path.exists():
                    record['backendEvidence'] = json.loads(backend_path.read_text(encoding='utf-8'))
                summaries = list(directory.glob('wheel_steady_[0-9]*.timeline_summary.json'))
                record['summaryFiles'] = [p.name for p in summaries]
                if len(summaries) == 1:
                    record['metrics'] = json.loads(summaries[0].read_text(encoding='utf-8'))
                    record['valid'] = (code == 0 and not locked and not lock_lines and
                                       record.get('backendEvidence', {}).get('verified') is True and
                                       all(s['exitCode'] == 0 for s in snaps.values()) and
                                       record['metrics']['actual_scene'] == 'wheel_steady' and
                                       record['metrics']['frame_count'] > 0 and
                                       record['metrics']['rss_cycles'] == 5)
                dump(ROOT / 'runs.json', records)
                print(f'END {label}: exit={code} valid={record["valid"]} '
                      f'raster={record.get("metrics", {}).get("average_frame_rasterizer_time_millis")}', flush=True)
                PREVIOUS.checked('shell', 'am', 'force-stop', 'com.example.luckdraw_bench')
                if record['settingsAfter'] != EXPECTED_SETTINGS:
                    raise RuntimeError('事后设置变化，停止并保留证据')
                if record['valid']:
                    break
                if not (locked or lock_lines):
                    raise RuntimeError('非锁屏失败；先检查，不盲目追加启动')
            else:
                raise RuntimeError('本条件两次均无效，停止')
    finally:
        final = PREVIOUS.settings()
        dump(ROOT / 'final_settings_confirmation.json', dict(verifiedAt=now(), settings=final,
              expected=EXPECTED_SETTINGS, unchanged=final == EXPECTED_SETTINGS))
        after = source_hashes()
        dump(ROOT / 'source_hashes_after.json', after)
        dump(ROOT / 'source_verification.json', dict(unchanged=initial_hashes == after,
              files=len(after), changed=[p for p in after if initial_hashes.get(p) != after[p]]))
        print(f'FINAL settings={final}; source/APK unchanged={initial_hashes == after}', flush=True)


if __name__ == '__main__':
    main()
