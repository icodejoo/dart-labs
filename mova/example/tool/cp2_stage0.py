"""CP2: build the one shared release APK and retain device provenance."""
import json
import os
import subprocess
import time
from datetime import datetime
from types import SimpleNamespace

os.environ['ANDROID_SDK_ROOT'] = 'E:/sdk/android'
os.environ['MOVA_MATRIX_UNLOCK_WAIT'] = '600'
import run_matrix as matrix
session = 'cp2-retry2-' + datetime.now().strftime('%Y%m%d-%H%M%S')
ledger = matrix.TOOL/'coverage_evidence'/session
ledger.mkdir(parents=True)
history = matrix.ROOT/'doc/plans/2026-11-04-cp2-results.json'
(ledger/'previous-results.json').write_bytes(history.read_bytes())
attempts = []

def memory_gate():
    deadline = time.monotonic() + 2400
    while True:
        raw = subprocess.check_output(['powershell','-NoProfile','-Command',
            'Get-CimInstance Win32_OperatingSystem | Select-Object FreePhysicalMemory,FreeVirtualMemory | ConvertTo-Json'], text=True)
        values = json.loads(raw)
        values['at'] = datetime.now().astimezone().isoformat()
        with (ledger/'memory.jsonl').open('a', encoding='utf-8') as stream:
            stream.write(json.dumps(values)+'\n')
        print('MEMORY', json.dumps(values), flush=True)
        if min(values['FreePhysicalMemory'], values['FreeVirtualMemory']) >= 4*1024*1024:
            return values
        if time.monotonic() >= deadline:
            raise RuntimeError('MEMORY_GATE_40_MINUTES: physical/virtual free below 4 GiB')
        time.sleep(min(60, max(0, deadline-time.monotonic())))

manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
manifest['build']['argv'] = ['{python}', '{tool}/coverage_build.py',
    'lib/main_coverage_suite.dart', '--no-daemon', '--max-workers=2',
    '-Dorg.gradle.jvmargs=-Xms128m -Xmx2g -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m -XX:ActiveProcessorCount=2',
    '-Pkotlin.compiler.execution.strategy=in-process']
for attempt in range(1, 4):
    run_id = 'cp2-build-r2-' + datetime.now().strftime('%Y%m%d-%H%M%S')
    d = matrix.Driver(SimpleNamespace(run_id=run_id), manifest)
    result = dict(run_id=run_id, status='BLOCKED', evidence=str(d.out), attempt=attempt)
    retry = False
    try:
        result['memoryBefore'] = memory_gate()
        d.preflight()
        for name, args in {'battery': ('shell','dumpsys','battery'),
            'identity': ('shell','getprop'), 'disk': ('shell','df','-k','/data')}.items():
            (d.out/(name+'.txt')).write_text(d.adb(*args), encoding='utf-8')
        print('BUILD ATTEMPT', attempt, flush=True)
        d.build()
        result.update(status='PASS', apk=str(d.out/(d.prefix+'installed.apk')),
            metadata=json.loads((d.out/(d.prefix+'build.json')).read_text()))
    except Exception as error:
        result['error'] = repr(error)
        logs = list(d.out.glob('*build*.log'))
        result['memoryErrors'] = [dict(path=str(p), lines=[line for line in p.read_text(encoding='utf-8',errors='replace').splitlines()
            if 'Could not reserve virtual memory' in line]) for p in logs]
        retry = any(r['lines'] for r in result['memoryErrors'])
    finally:
        d.cleanup()
        result['cleanup'] = d.results
        attempts.append(dict(result))
        result['attempts'] = list(attempts)
        result['sessionEvidence'] = str(ledger)
        (ledger/'stage0.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False),flush=True)
    if result['status'] == 'PASS' or not retry:
        break
(matrix.TOOL/'coverage_evidence/cp2-stage0.json').write_text(
    json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
if result['status'] != 'PASS':
    raise SystemExit(1)
