"""R4 独立实例验收：验证来源、串行运行并只清理自己启动的进程。"""
from collections import Counter
import hashlib
import json
import os
import re
from pathlib import Path
import socket
import subprocess
import shutil
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
KIT = Path('E:/workspaces/api-ws-demo')
OUT = ROOT / 'docs/reports/round2-r4-evidence'
LOG = ROOT / 'coverage/accept'


def command(args, cwd=ROOT):
    """读取命令最终输出，失败立即退出。"""
    return subprocess.check_output(args, cwd=cwd, text=True, encoding='utf-8').strip()


def get(url):
    """读取独立实例的健康信息。"""
    with urllib.request.urlopen(url, timeout=3) as response:
        return json.load(response)


def main():
    """核对二进制和场景，完成后停止本进程拥有的实例。"""
    LOG.mkdir(parents=True, exist_ok=True)
    old = json.loads((ROOT / 'docs/reports/round2-r2a-evidence/acceptance.json').read_text(encoding='utf-8'))
    source_before = command(['git', 'status', '--porcelain'], KIT)
    revision = command(['git', 'rev-parse', 'HEAD'], KIT)
    assert not source_before, 'testkit 工作区已有改动，不能确认二进制来源'
    target = Path(old['testkit']['target'])
    binaries = {}
    reuse = revision == old['testkit']['commit']
    for name, expected in old['testkit']['binaries'].items():
        path = target / name
        actual = hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None
        reuse = reuse and actual == expected
        binaries[name] = actual
    if not reuse:
        target = ROOT / 'coverage/r4-testkit/release'
        with (LOG / 'r4-build.log').open('w', encoding='utf-8') as stream:
            subprocess.run(['cargo', 'build', '--locked', '--offline', '--release', '-j', '1',
                            '--manifest-path', str(KIT / 'Cargo.toml'),
                            '--target-dir', str(target.parent)], cwd=ROOT,
                           stdout=stream, stderr=subprocess.STDOUT, check=True)
        binaries = {name: hashlib.sha256((target / name).read_bytes()).hexdigest()
                    for name in old['testkit']['binaries']}
    with (LOG / 'r4-scenario-validation.log').open('w', encoding='utf-8') as stream:
        subprocess.run(['node', str(KIT / 'testkit/tools/validate.mjs'), '--check-index'],
                       cwd=KIT, stdout=stream, stderr=subprocess.STDOUT, check=True)
    scenarios = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in sorted((KIT / 'testkit/scenarios').glob('*.json'))}
    schema = json.loads((KIT / 'testkit/scenario.schema.json').read_text(encoding='utf-8'))
    capability = schema['$defs']['capability']
    common = (ROOT / 'test/accept/lib/common.dart').read_text(encoding='utf-8')
    literals = (ROOT / 'test/accept/lib/literals.dart').read_text(encoding='utf-8')
    constants = {name: value for name, quote, value in
                 re.findall(r'''const (tk\w+) = (['"])(.*?)\2;''', literals)}
    supported = []
    for name in ('capabilities', 'subCapabilities'):
        block = re.search(r'const '+name+r' = \{(.*?)\};', common, re.S).group(1)
        for token in block.split(','):
            token = token.strip()
            if token:
                supported.append(token.strip("'") if token.startswith("'") else constants[token])
    unsupported = sorted(set(capability['enum'])-set(supported))
    assert unsupported == ['raw-business-code', 'timeout-total']
    metadata = dict(commit=revision, source_clean=True, target=str(target),
                    binaries=binaries, reused_verified_r2a_binary=reuse,
                    scenarios_sha256=scenarios, capability=capability,
                    executor_supported_capabilities=sorted(supported),
                    executor_unsupported_capabilities=unsupported,
                    executor_registration_sha256=hashlib.sha256(common.encode('utf-8')).hexdigest(),
                    server='http://127.0.0.1:47280', netem='http://127.0.0.1:47290')
    (OUT / 'testkit.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    for port in (47280, 47290):
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            sock.bind(('0.0.0.0', port))
    processes = []
    streams = []
    try:
        env = dict(os.environ, TEST_MODE='1', PORT='47280')
        for name, args in [('api-ws-demo', []), ('netem', ['--control', '127.0.0.1:47290'])]:
            stream = (LOG / f'r4-{name}.log').open('w', encoding='utf-8')
            streams.append(stream)
            process = subprocess.Popen([str(target / f'{name}.exe'), *args], cwd=ROOT,
                                       env=env, stdout=stream, stderr=subprocess.STDOUT,
                                       creationflags=subprocess.CREATE_NO_WINDOW)
            processes.append(process)
        for attempt in range(40):
            try:
                ping = get(metadata['server'] + '/t/ping')
                presets = get(metadata['netem'] + '/presets')
                assert ping['code'] == 0 and presets
                break
            except Exception:
                assert all(p.poll() is None for p in processes), '独立实例提前退出'
                time.sleep(.5)
        else:
            raise RuntimeError('独立实例未就绪')
        listeners = json.loads(command(['powershell', '-NoProfile', '-Command',
            'Get-NetTCPConnection -LocalPort 47280,47290 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json']))
        assert {row['OwningProcess'] for row in listeners} == {process.pid for process in processes}
        (OUT / 'listeners.json').write_text(json.dumps(listeners, indent=2)+'\n', encoding='utf-8')
        with (LOG / 'r4-normal.log').open('w', encoding='utf-8') as stream:
            result = subprocess.run([shutil.which('dart'), 'run', 'test/accept/bin/cli.dart',
                                     '--networks=normal', '--styles=http,business', '--jobs=4',
                                     '--report=coverage/accept/r4-normal.json'], cwd=ROOT,
                                    env=dict(os.environ, TESTKIT_SERVER=metadata['server'],
                                             TESTKIT_NETEM=metadata['netem']),
                                    stdout=stream, stderr=subprocess.STDOUT)
        data = json.loads((LOG / 'r4-normal.json').read_text(encoding='utf-8'))
        (OUT / 'acceptance-structure.json').write_text(json.dumps(
            {key: (len(value) if isinstance(value, list) else value)
             for key, value in data.items()}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        results = data['results']
        counts = Counter(row['status'] for row in results)
        skips = {f"{row['scenario']}@{row['network']}@{row['style']}": row['reasons']
                 for row in results if row['status'] == '跳过'}
        old_skips = old['skips']
        differences = {key: dict(before=old_skips.get(key), after=skips.get(key))
                       for key in old_skips.keys() | skips.keys()
                       if old_skips.get(key) != skips.get(key)}
        summary = dict(planned=data['planned'], executed=data['executed'],
                       interrupted=data['interrupted'], remaining=data['remaining'],
                       counts=counts, by_style={style: Counter(row['status'] for row in results
                                                              if row['style'] == style)
                                                for style in ('http', 'business')},
                       skip_reasons=Counter(reason for reasons in skips.values() for reason in reasons),
                       r2a_skip_count=len(old_skips), skip_count=len(skips),
                       skip_differences=differences,
                       failures=[dict(scenario=row['scenario'], style=row['style'], reasons=row['reasons'])
                                 for row in results if row['status'] == '失败'])
        (OUT / 'acceptance.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
        assert result.returncode == 0, f'验收退出 {result.returncode}'
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=15)
        for stream in streams:
            stream.close()
        assert source_before == command(['git', 'status', '--porcelain'], KIT)
        cleanup = dict(processes=[dict(pid=p.pid, exit=p.returncode) for p in processes])
        cleanup['ports_free'] = {}
        for port in (47280, 47290):
            with socket.socket() as sock:
                cleanup['ports_free'][str(port)] = sock.connect_ex(('127.0.0.1', port)) != 0
        (OUT / 'process-cleanup.json').write_text(json.dumps(cleanup, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
