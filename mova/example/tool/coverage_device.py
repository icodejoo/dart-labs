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

SERIAL = "7NQBB23606003715"
HERE = Path(__file__).resolve().parent


def adb(*args, binary=False):
    """Run only against the explicitly authorized device / 仅操作指定真机。"""
    return subprocess.check_output(["adb", "-s", SERIAL, *args], text=not binary)


def unlocked():
    """Reject locked-screen rendering evidence / 拒绝锁屏时执行渲染验证。"""
    window = adb("shell", "dumpsys", "window")
    if "isKeyguardShowing=true" in window:
        raise RuntimeError("BLOCKED: device remains locked (isKeyguardShowing=true)")
    if "mScreenOnFully=true" not in window:
        raise RuntimeError("BLOCKED: screen not fully on")
    return window


def request(path):
    with urllib.request.urlopen("http://127.0.0.1:18083" + path, timeout=10) as response:
        return json.load(response)


def capture(name):
    """Save screenshots, OS states and the app journal / 保存画面、系统状态和应用日志。"""
    out = HERE / "coverage_evidence"
    out.mkdir(exist_ok=True)
    (out / f"{name}.png").write_bytes(adb("exec-out", "screencap", "-p", binary=True))
    for category in ["window", "audio", "activity", "meminfo"]:
        args = ["shell", "dumpsys", category]
        if category == "meminfo":
            args.append("com.icodejoo.mova.mova_example.coverage")
        (out / f"{name}.{category}.txt").write_text(adb(*args), encoding="utf-8")
    (out / f"{name}.json").write_text(json.dumps(request("/"), ensure_ascii=False, indent=2), encoding="utf-8")
    (out / f"{name}.logcat.txt").write_text(adb("logcat", "-d", "-v", "threadtime"), encoding="utf-8")
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
            for row in response['records']:
                if row.get('kind')=='MEM_SAMPLE' and row['round'] not in sampled:
                    sampled.add(row['round'])
                    (HERE/'coverage_evidence'/f"{a.name or a.group}.round{row['round']}.meminfo.txt").write_text(adb('shell','dumpsys','meminfo','com.icodejoo.mova.mova_example.coverage'),encoding='utf-8')
                if row.get('kind')=='SUBTITLE_SHOT' and row['ms'] not in sampled:
                    sampled.add(row['ms'])
                    (HERE/'coverage_evidence'/f"{a.name or a.group}.{row['format']}.png").write_bytes(adb('exec-out','screencap','-p',binary=True))
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
