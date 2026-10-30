"""Verify constructor assertions on the Android debug VM and archive raw logcat."""
from pathlib import Path
import subprocess,time,re,json
from coverage_device import adb,unlocked,shot
import coverage_record
from coverage_record import update
H=Path(__file__).resolve().parent;O=H/'coverage_evidence';P='com.icodejoo.mova.mova_example.coverage'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
update('开始N22真机debug断言',[],['- 隔离debug APK已由Gradle真实构建；安装到同一独立包，读取VM断言启用与两个非法构造捕获结果。其他矩阵结果仍只引用release。'])
unlocked()
with (O/'rerun-debug-install.txt').open('w',encoding='utf-8') as log:
    subprocess.run(['adb','-s','7NQBB23606003715','install','-r',str(H.parent/'build/app/outputs/apk/debug/app-debug.apk')],check=True,stdout=log,stderr=subprocess.STDOUT)
adb('shell','am','force-stop',P);adb('shell','am','start','-n',P+'/com.icodejoo.mova.mova_example.MainActivity')
end=time.monotonic()+40;found=None;raw=''
while time.monotonic()<end:
    try:
        pid=adb('shell','pidof',P).strip()
        raw=adb('logcat','-d','--pid='+pid,'-v','threadtime')
        found=re.search(r'RERUN_ASSERT enabled=(true|false) trackCount=(true|false) maxZoom=(true|false)',raw)
        if found:break
    except subprocess.CalledProcessError:pass
    time.sleep(.3)
(O/'rerun-debug-assert.logcat.txt').write_text(raw,encoding='utf-8')
(O/'rerun-debug-assert.window.txt').write_text(unlocked(),encoding='utf-8')
shot(O/'rerun-debug-assert.png',P)
result={'foundMarker':found is not None,'assertionsEnabled':bool(found and found[1]=='true'),'trackCountRejected':bool(found and found[2]=='true'),'maxZoomRejected':bool(found and found[3]=='true')}
(O/'rerun-debug-assert.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
adb('shell','am','force-stop',P)
update('结束N22真机debug断言',[],['- '+json.dumps(result)+'；证据rerun-debug-assert.json/logcat.txt/png。'])
print(result)
if not all(result.values()):raise SystemExit(1)
