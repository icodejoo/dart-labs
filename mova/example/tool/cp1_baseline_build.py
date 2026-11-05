"""Rebuild the documented CP0 revision with the current diagnostic-only page.

Archive under this worktree; never replace the live lib tree or switch branches.
Temporarily point the example dependency at that archive and restore exact bytes.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
from types import SimpleNamespace
import zipfile
from datetime import datetime

import run_matrix as matrix


def main():
    root = matrix.ROOT
    evidence = matrix.TOOL/'coverage_evidence'
    revision = 'a5c317f6afb55125611b64a964ce1222c63ae000'
    archive = evidence/'cp0-keepalive-source-a5c317f6.zip'
    destination = root/'.dart_tool/cp0-keepalive-a5c317f6'
    destination.mkdir(parents=True, exist_ok=True)
    subprocess.run(['git', 'archive', '--format=zip', '--output='+str(archive), revision,
                    'mova/lib', 'mova/android', 'mova/pubspec.yaml'], cwd=root.parent, check=True)
    with zipfile.ZipFile(archive) as source:
        if any(not (destination/n).resolve().is_relative_to(destination.resolve()) for n in source.namelist()):
            raise ValueError('archive path escapes workspace')
        source.extractall(destination)
    files = {p.relative_to(destination).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in destination.rglob('*') if p.is_file()}
    manifest = json.loads(matrix.MANIFEST.read_text(encoding='utf-8'))
    manifest['ports'] = [18080, 18082, 18083]
    manifest['build']['argv'] = ['{python}', '{tool}/coverage_build.py',
        'lib/main_cp0_keepalive_verify.dart', '--no-daemon', '--max-workers=4',
        '-Dorg.gradle.jvmargs=-Xms128m -Xmx2048m -XX:MaxMetaspaceSize=512m -XX:ReservedCodeCacheSize=128m -XX:ActiveProcessorCount=4',
        '-Pkotlin.compiler.execution.strategy=in-process']
    run_id = 'cp0-keepalive-build-'+datetime.now().strftime('%Y%m%d-%H%M%S')
    d = matrix.Driver(SimpleNamespace(run_id=run_id), manifest)
    pubspec = root/'example/pubspec.yaml'
    lock = root/'example/pubspec.lock'
    original = pubspec.read_bytes()
    original_lock = lock.read_bytes() if lock.exists() else None
    result = dict(run_id=run_id, sourceRevision=revision, sourceFiles=files,
                  productSource=str(destination/'mova'), status='BLOCKED')
    try:
        d.preflight()
        text = original.decode()
        old = '    path: ../'
        if text.count(old+'\n')+text.count(old+'\r\n') != 1:
            raise ValueError('ambiguous example mova dependency')
        pubspec.write_bytes(text.replace(old, '    path: ../.dart_tool/cp0-keepalive-a5c317f6/mova', 1).encode())
        subprocess.run(['cmd', '/c', 'flutter', 'pub', 'get', '--offline'], cwd=root/'example', check=True)
        config = json.loads((root/'example/.dart_tool/package_config.json').read_text())
        mova = next(p for p in config['packages'] if p['name'] == 'mova')
        if 'cp0-keepalive-a5c317f6' not in mova['rootUri']:
            raise ValueError('baseline dependency did not resolve to archive')
        result['resolvedMova'] = mova
        d.build()
        installed = d.out/(d.prefix+'installed.apk')
        original_apk = evidence/'matrix-cp1-build-20261103-153357/matrix-cp1-build-20261103-153357-installed-before.apk'
        if hashlib.sha256(original_apk.read_bytes()).hexdigest() != 'f9df792f6dcc0b68d908906f23026dd5beeacd56d0c2d566c1b85d6c35ba1586':
            raise ValueError('original CP0 APK provenance mismatch')
        with zipfile.ZipFile(installed) as current, zipfile.ZipFile(original_apk) as old:
            names = ['lib/arm64-v8a/libmpv.so', 'lib/arm64-v8a/libmediakitandroidhelper.so']
            result['nativeHashes'] = {n: dict(baseline=hashlib.sha256(old.read(n)).hexdigest(),
                                             rebuilt=hashlib.sha256(current.read(n)).hexdigest()) for n in names}
        if any(h['baseline'] != h['rebuilt'] for h in result['nativeHashes'].values()):
            raise ValueError('baseline native binaries changed')
        result.update(status='PASS', evidence=str(d.out),
            apk=str(installed),
            metadata=json.loads((d.out/(d.prefix+'build.json')).read_text()))
    except Exception as error:
        result['error'] = repr(error)
        raise
    finally:
        try:
            pubspec.write_bytes(original)
            if original_lock is not None:
                lock.write_bytes(original_lock)
            subprocess.run(['cmd', '/c', 'flutter', 'pub', 'get', '--offline'], cwd=root/'example', check=True)
            result['dependencyFilesRestored'] = pubspec.read_bytes() == original and (
                original_lock is None or lock.read_bytes() == original_lock)
            if not result['dependencyFilesRestored']:
                raise ValueError('example dependency files did not restore exactly')
        finally:
            d.cleanup()
            (evidence/'cp0-keepalive-build.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
