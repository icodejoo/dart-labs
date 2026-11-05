"""Build an isolated release package without editing Android project files.

通过 Gradle 初始化脚本构建独立安装包，不修改 Android 工程文件。
"""
from pathlib import Path
import subprocess
import sys
import base64
import shutil
import os
from cp3_runtime import wait_memory, virtual_memory_error

example = Path(__file__).resolve().parents[1]
target = sys.argv[1] if len(sys.argv) > 1 else 'lib/main_coverage_api.dart'
profile = '--profile-build' in sys.argv[2:]
extra_args = [a for a in sys.argv[2:] if a != '--profile-build']
campaign = os.environ.get('MOVA_CP3_CAMPAIGN') == '1'
if campaign:
    target = 'lib/main_coverage_suite.dart'
    extra_args = [a for a in extra_args if not a.startswith('--max-workers=')]
    extra_args += ['--no-daemon', '--max-workers=2']
# Detached worktrees do not contain ignored Gradle wrapper files or JNI copies.
# Bootstrap only inside this example, using the installed SDK and hydrated repo.
flutter=Path(shutil.which('flutter') or shutil.which('flutter.bat') or '')
wrapper=flutter.resolve().parents[1]/'bin/cache/artifacts/gradle_wrapper' if flutter.is_file() else None
for relative in ('gradlew','gradlew.bat','gradle/wrapper/gradle-wrapper.jar'):
    dest=example/'android'/relative
    if not dest.exists():
        if wrapper is None or not (wrapper/relative).is_file():
            raise RuntimeError('Missing Gradle wrapper; run flutter create --platforms=android in example or restore SDK artifacts')
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(wrapper/relative,dest)
native=example.parent/'packages/media_kit_libs_android_video_slim/android/src/main/jniLibs/arm64-v8a'
for source in native.glob('*.so'):
    if source.read_bytes().startswith(b'version https://git-lfs'):
        raise RuntimeError('LFS pointer: run python tool/libmpv_hydrate.py before building')
    dest=example/'tool/coverage_native/arm64-v8a'/source.name
    dest.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source,dest)
build_command = [
        str(example / 'android/gradlew.bat'), '-I', str(example / 'tool/coverage.init.gradle'),
        '-Ptarget-platform=android-arm64', f'-Ptarget={target}',
        '-Pdart-defines='+','.join(base64.b64encode(s.encode()).decode() for s in ['MEDIA=http://127.0.0.1:18080/vod.mp4','AUTOEXIT=false','GOPS=25,50,100','HOLDS=3','S3_SECONDS=15','S4_SECONDS=15','S5_SECONDS=20', *(['CP3_HEADERS_R4=true'] if os.environ.get('MOVA_CP3_HEADERS_R4') == '1' else [])]),
        '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true', '-Ptree-shake-icons=true',
        *extra_args, 'assembleProfile' if profile else 'assembleRelease',
    ]
for attempt in range(4 if campaign else 1):
    if campaign:
        wait_memory()
    with (example / 'tool/coverage_isolated_build.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(build_command, cwd=example / 'android', stdout=log, stderr=subprocess.STDOUT,
                                creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    if not campaign or result.returncode == 0:
        break
    text = (example / 'tool/coverage_isolated_build.log').read_text(encoding='utf-8', errors='replace')
    shutil.copy2(example / 'tool/coverage_isolated_build.log', example / f'tool/cp3-build-attempt-{attempt + 1}.log')
    if not virtual_memory_error(text):
        break
    print('CP3 virtual memory failure; retry', attempt + 1, 'of 3', flush=True)
print('BUILD_EXIT', result.returncode)
sys.exit(result.returncode)
