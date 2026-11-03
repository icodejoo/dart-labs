"""R4 快照回归的定向变异，逐项核对断言失败并按 SHA256 恢复。"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'coverage/r4-mutations'
TEST = 'test/unit/request_snapshot_test.dart'


def main():
    """只运行一个测试进程；编译失败、空跑和超时不计击中。"""
    OUT.mkdir(parents=True, exist_ok=True)
    request = (ROOT / 'lib/src/request.dart').read_text(encoding='utf-8')
    response = (ROOT / 'lib/src/response.dart').read_text(encoding='utf-8')
    entry = ('options.copyWith(), call: call' if 'this._owned(' in request
             else '_options = options.copyWith()')
    entry_bad = ('options, call: call' if 'this._owned(' in request
                 else '_options = options')
    patch = ('return DiomanRequest._owned(o, call: call);' if 'this._owned(' in request
             else 'return DiomanRequest(o, call: call);')
    strict = ('diomanRequestResponseType(request)' if 'diomanRequestResponseType(request)' in response
              else 'request.toRequestOptions().responseType')
    cases = [('entry-alias', 'lib/src/request.dart', entry, entry_bad),
             ('patch-ignored', 'lib/src/request.dart', patch, 'return this;'),
             ('strict-reads-wire', 'lib/src/response.dart', strict, 'response.requestOptions.responseType')]
    results = []
    for name, relative, before, after in cases:
        path = ROOT / relative
        original = path.read_bytes()
        digest = hashlib.sha256(original).hexdigest()
        source = original.decode('utf-8').replace('\r\n', '\n')
        assert source.count(before) == 1, (name, before)
        started = time.perf_counter()
        try:
            path.write_text(source.replace(before, after), encoding='utf-8')
            proc = subprocess.run([shutil.which('dart'), 'test', '--concurrency=1', TEST,
                                   '--reporter=json', '--timeout=10s'], cwd=ROOT,
                                  capture_output=True, text=True, encoding='utf-8',
                                  errors='replace', timeout=120)
            output = proc.stdout + proc.stderr
            (OUT / f'{name}.jsonl').write_text(output, encoding='utf-8')
            events = [json.loads(line) for line in proc.stdout.splitlines() if line.startswith('{')]
            failures = [event for event in events if event.get('type') == 'testDone'
                        and event.get('result') in ('failure', 'error')]
            assert proc.returncode != 0 and failures, name
            assert not any(value in output for value in ('Failed to load', 'Compilation failed', 'Test timed out')), name
        finally:
            path.write_bytes(original)
            assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
        results.append(dict(mutation=name, test=TEST, failures=len(failures),
                            before_sha256=digest, restored_sha256=digest,
                            seconds=round(time.perf_counter()-started, 3)))
        (OUT / 'mutations.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')
        print(f'{name}: assertion failure; SHA256 restored', flush=True)


if __name__ == '__main__':
    main()
