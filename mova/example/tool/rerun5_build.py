"""Build an isolated release package without editing Android project files.

通过 Gradle 初始化脚本构建独立安装包，不修改 Android 工程文件。
"""
from pathlib import Path
import subprocess
import sys
import base64

example = Path(__file__).resolve().parents[1]
target = sys.argv[1] if len(sys.argv) > 1 else 'lib/main_coverage_api.dart'
profile = '--profile-build' in sys.argv[2:]
extra_args = [a for a in sys.argv[2:] if a != '--profile-build']
with (example / 'tool/coverage_evidence/rerun5-build.log').open('w', encoding='utf-8') as log:
    result = subprocess.run([
        str(example / 'android/gradlew.bat'), '-I', str(example / 'tool/coverage.init.gradle'),
        '-Ptarget-platform=android-arm64', f'-Ptarget={target}',
        '-Pdart-defines='+','.join(base64.b64encode(s.encode()).decode() for s in ['MEDIA=http://127.0.0.1:18080/vod.mp4','AUTOEXIT=false','GOPS=25,50,100','HOLDS=3','S3_SECONDS=15','S4_SECONDS=15','S5_SECONDS=20']),
        '-Pdart-obfuscation=false', '-Ptrack-widget-creation=true', '-Ptree-shake-icons=true',
        *extra_args, 'assembleProfile' if profile else 'assembleRelease',
    ], cwd=example / 'android', stdout=log, stderr=subprocess.STDOUT)
print('BUILD_EXIT', result.returncode)
sys.exit(result.returncode)
