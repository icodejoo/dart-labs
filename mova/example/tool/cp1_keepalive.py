"""CP1 S7/S14: five serial launches of the unchanged single scenarios. 未上机。

Uses coverage_suite_device.py and its guarded SHOT capture, never synthesizes a
pixel verdict from vid/resume alone. Visual review is deliberately BLOCKED.
No device or subprocess work occurs on import.
"""
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
PKG = 'com.icodejoo.mova.mova_example.coverage'


def validate_checks(runs, checks):
    missing = []
    for scene in ('S7', 'S14'):
        for i in range(runs):
            ident = f'CP1.keepalive-s7s14.{scene}.{i}'
            rows = [r for r in checks if r.get('id') == ident]
            if len(rows) != 1:
                missing.append(f'{ident}: CHECK count={len(rows)}')
                continue
            numbers = rows[0].get('numbers', {})
            if not {'run', 'log', 'shots', 'nativeVerdicts', 'hwdec', 'visualReview'} <= numbers.keys():
                missing.append(f'{ident}: incomplete numbers schema')
            if rows[0].get('status') not in ('PASS', 'FAIL'):
                missing.append(f'{ident}: {rows[0].get("missing", "visual evidence pending")}')
    return missing


def review_check(scene, i, text, shots, log):
    """Preserve native verdicts separately from the pending pixel judgment."""
    images = [s for s in shots if f'{scene} SHOT ' in s.get('marker', '') and 'SHOT_ACK ' not in s.get('marker', '')]
    verdicts = re.findall(r'VERDICT '+scene+r' (PASS|FAIL) ([^\r\n]*)', text)
    hwdec = re.findall(r'S7 hwdec=([^\s]+)', text)
    expected = 20 if scene == 'S7' else 4
    captured = len(images) == expected and all(s.get('captured') is True and s.get('phaseConfirmed') is True
        and Path(s['path']).is_file() and Path(s.get('motionPath', '')).is_file() for s in images)
    reasons = ['待相邻帧像素/运动与CP0同口径复核']
    if not captured:
        reasons.append(f'缺完整SHOT采图：期望{expected}，实得{len(images)}（含隐私守卫跳过检查）')
    if scene == 'S7' and hwdec != ['mediacodec-copy']:
        reasons.append('缺 mediacodec-copy 原生 hwdec 前提')
    if 'os=android' not in text:
        reasons.append('缺 Android 运行前提')
    if len(verdicts) != 1:
        reasons.append('缺唯一原页面 VERDICT')
    failed = any(v[0] == 'FAIL' for v in verdicts)
    return dict(kind='CHECK', id=f'CP1.keepalive-s7s14.{scene}.{i}',
        status='FAIL' if failed else 'BLOCKED', **{'pass': False if failed else None},
        missing='；'.join(reasons), deviceStatus='未上机', numbers=dict(run=i+1,
        log=str(log), shots=images, nativeVerdicts=verdicts, hwdec=hwdec,
        visualReview=dict(status='BLOCKED', missing=reasons)))


def run(args):
    # The outer CP1 suite is already installed by run_matrix; --build here is
    # intentionally rejected so no second build can silently change the target.
    if args.build:
        raise ValueError('run cp1-keepalive-s7s14 through run_matrix; standalone --build unsupported')
    out = TOOL / 'coverage_evidence' / ('matrix-' + args.run_id)
    out.mkdir(parents=True, exist_ok=True)
    stem = 'matrix-' + args.run_id + '-cp1-keepalive-s7s14'
    serial = os.environ.get('MOVA_MATRIX_SERIAL', '7NQBB23606003715')
    records, harness, originals = [], [], {}
    children = []
    command_log = (out/(stem+'.commands.log')).open('w', encoding='utf-8')
    completed = False

    def command(argv, timeout=120):
        command_log.write('CALL '+json.dumps(list(map(str, argv)))+'\n'); command_log.flush()
        result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=timeout)
        text = result.stdout.decode('utf-8', errors='replace')
        command_log.write(f'RET {result.returncode}\n{text}\n'+result.stderr.decode('utf-8', errors='replace')); command_log.flush()
        if result.returncode:
            raise RuntimeError(f'command failed: {argv}, exit={result.returncode}')
        return text

    def adb(*argv):
        return command(['adb', '-s', serial, *argv])

    def stop(child):
        if child.poll() is None:
            if os.name == 'nt':
                command(['taskkill', '/PID', str(child.pid), '/T', '/F'])
            else:
                child.terminate()
            child.wait(timeout=15)

    try:
        # Refuse occupied ports; never use or kill another runner's service.
        for port in (18080, 18082, 18087):
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', port))
        for direction in ('reverse', 'forward'):
            originals[direction] = adb(direction, '--list')
        source_dir = out/(stem+'-sources'); source_dir.mkdir(exist_ok=True)
        shutil.copyfile(TOOL/'coverage_sources/stall.mp4', source_dir/'stall.mp4')
        source_log = (out/(stem+'.source-driver.log')).open('w')
        source = subprocess.Popen([sys.executable, '-B', str(TOOL/'verify_sources/live_server.py'),
            '18080', str(out/(stem+'.source.log')), str(source_dir/'stall.mp4')],
            cwd=ROOT, stdout=source_log, stderr=subprocess.STDOUT,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        children.append((source, source_log))
        deadline = time.monotonic()+30
        while True:
            if source.poll() is not None:
                raise RuntimeError('owned FLV fixture exited')
            try:
                with socket.create_connection(('127.0.0.1', 18080), timeout=.2):
                    break
            except OSError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('owned FLV fixture not ready')
                time.sleep(.2)
        adb('reverse', 'tcp:18080', 'tcp:18080')
        for i in range(args.runs):
            # S7/S14 are single:true; five launches are required, not --runs 5.
            name = out/(stem+f'.round{i+1}')
            argv = [sys.executable, '-B', str(TOOL/'coverage_suite_device.py'), 'keepAlive',
                '--only', 'S7,S14', '--runs', '1', '--timeout', '600', '--name', name.name, '--shot-index']
            # Keep the legacy driver's namespace/serial adaptation and own its
            # complete process tree if it times out.
            argv = [sys.executable, '-B', str(TOOL/'matrix_compat.py'), str(out),
                'matrix-'+args.run_id+'-', 'cp1-keepalive-s7s14', *argv[2:]]
            stream = (out/(stem+f'.round{i+1}.driver.log')).open('w',encoding='utf-8')
            command_log.write('CALL '+json.dumps(argv)+'\n'); command_log.flush()
            child = subprocess.Popen(argv,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT,
                creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
            children.append((child,stream))
            code=child.wait(timeout=660)
            command_log.write(f'RET {code}\n'); command_log.flush()
            if code: raise RuntimeError(f'round {i+1}: driver exit={code}')
            meta = json.loads(Path(str(name)+'.run.json').read_text(encoding='utf-8'))
            if not meta.get('completed'):
                raise RuntimeError(f'round {i+1}: missing AUTORUN DONE')
            log = Path(str(name)+'.log')
            text = log.read_text(encoding='utf-8')
            index = Path(str(name)+'.shots.jsonl')
            shots = [json.loads(line) for line in index.read_text(encoding='utf-8').splitlines()] if index.exists() else []
            for scene in ('S7', 'S14'):
                row = review_check(scene, i, text, shots, log)
                records.append(row)
                print('[MOVA-CP1] '+json.dumps(row, ensure_ascii=False), flush=True)
        completed = True
    except Exception as error:
        harness.append(str(error))
    finally:
        for child, stream in reversed(children):
            try:
                stop(child)
            except Exception as error:
                harness.append('cleanup: '+str(error))
            stream.close()
        if originals:
            try:
                adb('shell', 'am', 'force-stop', PKG)
                for direction, ports in [('reverse', (18080,18082)), ('forward', (18083,18087))]:
                    for port in ports:
                        key = f'tcp:{port}'
                        old = next((line.split()[-1] for line in originals.get(direction,'').splitlines() if key in line.split()[:2]), None)
                        adb(direction, key, old) if old else adb(direction, '--remove', key)
            except Exception as error:
                harness.append('mapping cleanup: '+str(error))
        missing = validate_checks(args.runs, records)
        result = dict(run_id=args.run_id, group='keepalive-s7s14', completed=completed,
            harness=harness, missing=missing, records=records,
            verdicts=[dict(case=r['id'],status=r['status'],numbers=r['numbers'],reason=r['missing']) for r in records])
        (out/(stem+'.json')).write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        command_log.close()
    return 2 if harness else 1 if missing else 0
