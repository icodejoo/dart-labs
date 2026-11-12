"""Drive the release coverage page and retain real device evidence.

通过 adb forward 操作真机验证页；先检查已解锁，结果写入指定证据目录。
"""
import argparse
import json
from pathlib import Path
import subprocess
import time
import urllib.request
import urllib.parse
import os
import sys
from shot_guard import PACKAGE, guarded_screencap

SERIAL = "7NQBB23606003715"
HERE = Path(__file__).resolve().parent
_campaign_api_checked = False


def adb(*args, binary=False):
    """Run only against the explicitly authorized device / 仅操作指定真机。"""
    from cp0_device_guard import wait_online
    wait_online(SERIAL)
    return subprocess.check_output(["adb", "-s", SERIAL, *args], text=not binary, timeout=120)


def shot(path, package=PACKAGE):
    """Guarded screenshot: only when the foreground is `package`; returns True when written.

    经隐私守卫的截图：前台不是被测包（或在画中画、解析不到）就跳过并打印 SHOT skipped；返回是否落盘。
    """
    return guarded_screencap(adb, package, path)


def unlocked():
    """Reject locked-screen rendering evidence / 拒绝锁屏时执行渲染验证。"""
    window = adb("shell", "dumpsys", "window")
    if "isKeyguardShowing=true" in window:
        raise RuntimeError("BLOCKED: device remains locked (isKeyguardShowing=true)")
    if "mScreenOnFully=true" not in window:
        raise RuntimeError("BLOCKED: screen not fully on")
    return window


def request(path):
    global _campaign_api_checked
    if os.environ.get('MOVA_CP3_CAMPAIGN') == '1' and not _campaign_api_checked and path.startswith('/run?'):
        # Short-first ordering can leave a HE/gap page foreground. Establish
        # the API control prerequisite before sending the first test command;
        # never retry or replace a command that has already been sent.
        ready = False
        try:
            with urllib.request.urlopen('http://127.0.0.1:18083/', timeout=2) as response:
                current = json.load(response)
                ready = 'status' in current and isinstance(current.get('records'), list)
        except (OSError, ValueError):
            pass
        if not ready:
            print('CP3 API prerequisite: select api page before first command', flush=True)
            subprocess.run([sys.executable, HERE / 'coverage_suite_device.py', 'api',
                            '--name', 'cp3-api-prerequisite', '--timeout', '60'],
                           check=True, timeout=90,
                           creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        _campaign_api_checked = True
    with urllib.request.urlopen("http://127.0.0.1:18083" + path, timeout=10) as response:
        return json.load(response)


def capture(name):
    """Save screenshots, OS states and the app journal / 保存画面、系统状态和应用日志。"""
    out = HERE / "coverage_evidence"
    out.mkdir(exist_ok=True)
    shot(out / f"{name}.png")
    for category in ["window", "audio", "activity", "meminfo"]:
        args = ["shell", "dumpsys", category]
        if category == "meminfo":
            args.append("com.icodejoo.mova.mova_example.coverage")
        (out / f"{name}.{category}.txt").write_text(adb(*args), encoding="utf-8")
    (out / f"{name}.json").write_text(json.dumps(request("/"), ensure_ascii=False, indent=2), encoding="utf-8")
    # OEM log buffers may contain invalid UTF-8. Preserve original bytes so
    # successful commands do not fail during the final evidence capture.
    (out / f"{name}.logcat.txt").write_bytes(adb("logcat", "-d", "-v", "threadtime", binary=True))
    print(out / name, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("group", nargs="?", default="basic")
    parser.add_argument("--arg", action="append", default=[])
    parser.add_argument("--name")
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--capture-only", action="store_true")
    a = parser.parse_args()
    unlocked()
    adb("forward", "tcp:18083", "tcp:18083")
    if not a.capture_only:
        params = {"group": a.group}
        params.update(s.split("=", 1) for s in a.arg)
        response = request("/run?" + urllib.parse.urlencode(params))
        sampled=set()
        end = time.monotonic() + a.timeout
        while response["status"] == "running":
            if time.monotonic() > end:
                capture(a.name or a.group)
                raise TimeoutError("runner command did not finish")
            time.sleep(0.5)
            response = request("/")
            # Only act on markers emitted by this command. Earlier commands'
            # subtitle shots and memory rounds must not be recaptured here.
            # 只消费本条命令的标记，避免把历史字幕/内存采样错拍到本次文件名下。
            command_start = max((i for i, r in enumerate(response['records']) if r.get('kind') == 'BEGIN'), default=0)
            for row in response['records'][command_start:]:
                if row.get('kind') == 'RESOURCE_SAMPLE' and ('resource', row['ms']) not in sampled:
                    sampled.add(('resource', row['ms']))
                    # Host snapshots follow the marker; retain timestamps rather
                    # than claiming simultaneous native-instance measurements.
                    base = HERE/'coverage_evidence'/f"{a.name or a.group}.{row['phase']}"
                    captures = []
                    for category, tail in [('meminfo', [str(row['pid'])]),
                                           ('media.codec', []), ('SurfaceFlinger', [])]:
                        started = time.time()
                        argv = ['adb', '-s', SERIAL, 'shell', 'dumpsys', category, *tail]
                        try:
                            from cp0_device_guard import wait_online
                            wait_online(SERIAL)
                            result = subprocess.run(argv, capture_output=True, timeout=30)
                            Path(str(base)+'.'+category+'.txt').write_bytes(result.stdout)
                            Path(str(base)+'.'+category+'.stderr.txt').write_bytes(result.stderr)
                            captures.append(dict(argv=argv, exit=result.returncode,
                                                 started=started, ended=time.time()))
                        except Exception as error:
                            captures.append(dict(argv=argv, started=started,
                                                 ended=time.time(), error=repr(error)))
                    Path(str(base)+'.native.json').write_text(json.dumps(
                        dict(marker=row, captures=captures), ensure_ascii=False, indent=2), encoding='utf-8')
                if row.get('kind')=='MEM_SAMPLE' and row['round'] not in sampled:
                    sampled.add(row['round'])
                    (HERE/'coverage_evidence'/f"{a.name or a.group}.round{row['round']}.meminfo.txt").write_text(adb('shell','dumpsys','meminfo','com.icodejoo.mova.mova_example.coverage'),encoding='utf-8')
                if row.get('kind')=='SUBTITLE_SHOT' and row['ms'] not in sampled:
                    sampled.add(row['ms'])
                    shot(HERE/'coverage_evidence'/f"{a.name or a.group}.{row['format']}.png")
        print("status", response["status"], flush=True)
    capture(a.name or a.group)
    if a.group=='new' and 'case=preview' in a.arg:
        for sec in [4,8,12]:
            try:
                with urllib.request.urlopen(f'http://127.0.0.1:18083/artifact?name=coverage-thumb-{sec}.jpg',timeout=3) as response:
                    (HERE/'coverage_evidence'/f'{a.name or a.group}.thumb{sec}.jpg').write_bytes(response.read())
            except Exception:
                pass


if __name__ == "__main__":
    main()
