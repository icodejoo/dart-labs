"""Build the assertion page without touching Android project files."""
from pathlib import Path
import subprocess,sys
H=Path(__file__).resolve().parent
with (H/'coverage_evidence/rerun-debug-build.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([str(H.parent/'android/gradlew.bat'),'-I',str(H/'coverage.init.gradle'),'-I',str(H/'rerun-debug.init.gradle'),
        '-Ptarget-platform=android-arm64','-Ptarget=lib/main_coverage_rerun_assert.dart',
        '-Pdart-obfuscation=false','-Ptrack-widget-creation=true','assembleDebug'],cwd=H.parent/'android',stdout=log,stderr=subprocess.STDOUT)
print('DEBUG_BUILD_EXIT',result.returncode)
sys.exit(result.returncode)
