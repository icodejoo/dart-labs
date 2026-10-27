"""Replace only LFS pointer entries with hash-identical installed APK artifacts.

仅在 example/tool 目录重打包验证 APK；每个二进制严格核对仓库 LFS SHA-256。
"""
import hashlib
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'example/tool/coverage_evidence'
native = ROOT / 'packages/media_kit_libs_android_video_slim_v041/android/src/main/jniLibs'
replacement = {}
with zipfile.ZipFile(OUT / 'installed-before.apk') as installed:
    for pointer in native.rglob('*.so'):
        data = pointer.read_bytes()
        if not data.startswith(b'version https://git-lfs.github.com/spec/v1'):
            continue
        name = 'lib/' + pointer.relative_to(native).as_posix()
        if name not in installed.namelist():
            continue
        payload = installed.read(name)
        expected = re.search(rb'oid sha256:(\w+)', data)[1].decode()
        actual = hashlib.sha256(payload).hexdigest()
        if actual != expected:
            raise RuntimeError(f'hash mismatch: {name} {actual} != {expected}')
        replacement[name] = payload
        print(name, len(payload), actual)

with zipfile.ZipFile(ROOT / 'example/build/app/outputs/flutter-apk/app-release.apk') as source:
    with zipfile.ZipFile(OUT / 'coverage-unsigned.apk', 'w', zipfile.ZIP_DEFLATED) as dest:
        for info in source.infolist():
            if info.filename.startswith('META-INF/') and info.filename.endswith(('.RSA', '.SF', '.MF')):
                continue
            dest.writestr(info, replacement.get(info.filename, source.read(info.filename)))
print('Repack complete. zipalign + apksigner are required before installation.')
