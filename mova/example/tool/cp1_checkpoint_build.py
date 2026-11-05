"""CP1 stage 0: one shared release build, install and device provenance."""
import json
import os
from datetime import datetime
from types import SimpleNamespace
from pathlib import Path
import run_matrix as matrix

os.environ['ANDROID_SDK_ROOT'] = 'E:/sdk/android'
run_id = 'cp1-build-' + datetime.now().strftime('%Y%m%d-%H%M%S')
manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
manifest['ports'] = [18082, 18083, 18190, 18194]
manifest['build']['argv'] = ['{python}', '{tool}/coverage_build.py',
    'lib/main_coverage_suite.dart', '--no-daemon', '--max-workers=4',
    '-Dorg.gradle.jvmargs=-Xms128m -Xmx2048m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m -XX:ActiveProcessorCount=4',
    '-Pkotlin.compiler.execution.strategy=in-process']
d = matrix.Driver(SimpleNamespace(run_id=run_id), manifest)
result = dict(run_id=run_id, status='BLOCKED', evidence=str(d.out))
try:
    d.preflight()
    for name, args in {'battery': ('shell','dumpsys','battery'),
        'identity': ('shell','getprop'), 'disk': ('shell','df','-k','/data')}.items():
        (d.out/(name+'.txt')).write_text(d.adb(*args), encoding='utf-8')
    d.build()
    result.update(status='PASS', apk=str(d.out/(d.prefix+'installed.apk')),
        metadata=json.loads((d.out/(d.prefix+'build.json')).read_text()))
except Exception as error:
    result['error'] = repr(error)
    raise
finally:
    d.cleanup()
    result['cleanup'] = d.results
    (matrix.TOOL/'coverage_evidence/cp1-stage0.json').write_text(
        json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False),flush=True)
