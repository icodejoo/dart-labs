"""Run RFV release acceptance on the single explicitly authorized device.

在唯一授权设备上执行 RFV release 验收，并在 finally 中回收资源。
"""
import array
import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import wave

EXAMPLE = Path(__file__).resolve().parents[1]
DEVICE = '7NQBB23606003715'
PACKAGE = 'com.icodejoo.mova.mova_example'
PORT = 18764
EVIDENCE = EXAMPLE.parent / 'doc' / 'plans' / '2026-11-06-review-fix-evidence'
ADB = [shutil.which('adb'), '-s', DEVICE]


def command(args, **kwargs):
    """Execute an explicit argument list and preserve failures / 执行参数列表并保留错误。"""
    result = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='replace', **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args}: {result.stdout}\n{result.stderr}')
    return result.stdout


def unlocked():
    """Stop on any reported keyguard / 发现锁屏立即停止。"""
    output = command(ADB + ['shell', 'dumpsys', 'window'])
    flags = [line.strip() for line in output.splitlines() if 'isKeyguardShowing=' in line]
    print('KEYGUARD ' + ' | '.join(flags), flush=True)
    if not flags or any('isKeyguardShowing=false' not in line for line in flags):
        raise RuntimeError('Device keyguard is showing or cannot be established')
    return flags


def fixture(path, rate, channels):
    """Generate exactly eight seconds with distinct channel frequencies / 生成八秒独立频率音轨。"""
    samples = array.array('h')
    for frame in range(rate * 8):
        for channel in range(channels):
            samples.append(round(12000 * math.sin(2 * math.pi * (440 if channel == 0 else 997) * frame / rate)))
    if sys.byteorder != 'little':
        samples.byteswap()
    with wave.open(str(path), 'wb') as output:
        output.setnchannels(channels)
        output.setsampwidth(2)
        output.setframerate(rate)
        output.writeframes(samples.tobytes())
    with wave.open(str(path), 'rb') as source:
        print(f'FIXTURE {path.name} channels={source.getnchannels()} sampleRate={source.getframerate()} bitsPerSample={source.getsampwidth()*8} frames={source.getnframes()} seconds={source.getnframes()/source.getframerate()}', flush=True)


def install_and_run(apk, cycle, phase):
    """Wait for a real RFV terminal event; timeouts never pass / 等待真实终止事件，超时不判通过。"""
    unlocked()
    command(ADB + ['shell', 'am', 'force-stop', PACKAGE])
    command(ADB + ['install', '-r', str(apk)], timeout=120)
    unlocked()
    command(ADB + ['shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity'])
    pid = command(ADB + ['shell', 'pidof', PACKAGE]).strip().split()[0]
    print(f'PROCESS cycle={cycle} phase={phase} pid={pid}', flush=True)
    seen = set()
    ordered = []
    terminal = 'READY_FORCE_STOP' if phase == 1 else 'DONE failures='
    deadline = time.monotonic() + (60 if phase == 1 else 240)
    raw = ''
    try:
        while time.monotonic() < deadline:
            raw = command(ADB + ['logcat', '-d', '-v', 'threadtime', '--pid=' + pid], timeout=15)
            for line in raw.splitlines():
                if 'RFV ' in line and line not in seen:
                    seen.add(line)
                    ordered.append(line)
                    print(line[line.index('RFV '):], flush=True)
            if any(terminal in line for line in seen):
                if phase == 1 and not any('PASS V1_PREPARE' in line for line in seen):
                    raise RuntimeError('Phase one did not prepare its durable state')
                return ordered
            time.sleep(0.75)
        raise TimeoutError(f'No {terminal} event; pid={pid}')
    finally:
        (EVIDENCE / f'cycle{cycle}-phase{phase}-logcat.txt').write_text(raw, encoding='utf-8')
        command(ADB + ['shell', 'am', 'force-stop', PACKAGE])
        probe = subprocess.run(ADB + ['shell', 'pidof', PACKAGE], capture_output=True, text=True)
        stopped = not probe.stdout.strip()
        print(f'EXTERNAL_FORCE_STOP cycle={cycle} phase={phase} previousPid={pid} noProcess={stopped}', flush=True)
        if not stopped:
            raise RuntimeError('App process remains after force-stop')


def main():
    """Build two release artifacts, run three crash cycles, always clean up / 构建两阶段包并完成三轮验证及清理。"""
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase1-apk', type=Path, help='Reuse the already built PHASE=1 APK from this exact page revision')
    options = parser.parse_args()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    unlocked()
    temp = Path(tempfile.mkdtemp(prefix='mova-rfv-'))
    server = None
    server_log = None
    results = []
    try:
        fixture(temp / 'stereo44100.wav', 44100, 2)
        fixture(temp / 'mono48000.wav', 48000, 1)
        (temp / 'control.json').write_text(json.dumps({'cycle': 1}), encoding='utf-8')
        server_log = (EVIDENCE / 'http-server.txt').open('w', encoding='utf-8')
        server = subprocess.Popen([sys.executable, '-u', '-m', 'http.server', str(PORT), '--bind', '127.0.0.1', '--directory', str(temp)], stdout=server_log, stderr=server_log, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        print(f'HTTP pid={server.pid} temp={temp}', flush=True)
        command(ADB + ['reverse', f'tcp:{PORT}', f'tcp:{PORT}'])
        flutter = shutil.which('flutter')
        build_env = os.environ.copy()
        build_env['GRADLE_OPTS'] = build_env.get('GRADLE_OPTS', '') + ' -Xmx128m -XX:+UseSerialGC -XX:ActiveProcessorCount=2 -XX:TieredStopAtLevel=1 -Dorg.gradle.jvmargs="-Xmx1536m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=96m -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:TieredStopAtLevel=1" -Dorg.gradle.workers.max=1 -Dorg.gradle.daemon=false -Dorg.gradle.project.kotlin.compiler.execution.strategy=in-process'
        for phase in (1, 2):
            if phase == 1 and options.phase1_apk:
                shutil.copy2(options.phase1_apk, temp / 'phase1.apk')
                print(f'REUSE PHASE=1 {options.phase1_apk}', flush=True)
                continue
            args = [flutter, 'build', 'apk', '--release', '--target-platform', 'android-arm64', '-t', 'lib/main_review_fix_verify.dart', f'--dart-define=PHASE={phase}']
            print('BUILD ' + subprocess.list2cmdline(args), flush=True)
            build = command(args, cwd=EXAMPLE, env=build_env, timeout=1200)
            (EVIDENCE / f'build-phase{phase}.txt').write_text(build, encoding='utf-8')
            print(build, flush=True)
            shutil.copy2(EXAMPLE / 'build/app/outputs/flutter-apk/app-release.apk', temp / f'phase{phase}.apk')
            # Let the single-use Gradle daemon exit before the next build.
            # 下一次构建前等待本次单次 Gradle daemon 退出。
            time.sleep(5)
        for cycle in range(1, 4):
            (temp / 'control.json').write_text(json.dumps({'cycle': cycle}), encoding='utf-8')
            for phase in (1, 2):
                results.extend(install_and_run(temp / f'phase{phase}.apk', cycle, phase))
        (EVIDENCE / 'rfv-lines.txt').write_text('\n'.join(results) + '\n', encoding='utf-8')
        failures = [line for line in results if ' FAIL ' in line]
        print(f'RESULT pass={sum(" PASS " in line for line in results)} fail={len(failures)}', flush=True)
        if failures:
            raise SystemExit(1)
    finally:
        command(ADB + ['shell', 'am', 'force-stop', PACKAGE])
        command(ADB + ['reverse', '--remove-all'])
        if server:
            server.terminate()
            server.wait(timeout=15)
        if server_log:
            server_log.close()
        if temp.parent != Path(tempfile.gettempdir()) or not temp.name.startswith('mova-rfv-'):
            raise RuntimeError(f'Refusing cleanup outside named temporary directory: {temp}')
        shutil.rmtree(temp)
        print(f'CLEANUP appStopped=true httpStopped=true tempRemoved={not temp.exists()} reverse={command(ADB + ["reverse", "--list"]).strip()!r}', flush=True)


if __name__ == '__main__':
    main()
