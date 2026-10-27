"""Install the freshly built isolated APK and start only owned fixture services."""
from pathlib import Path
import subprocess,hashlib,json,sys,os,time
from coverage_device import adb,unlocked
H=Path(__file__).resolve().parent; R=H.parents[1]; O=H/'coverage_evidence'; D=R/'doc/plans/2026-10-27-device-coverage-android-retest5.md'
def unlocked():
    w=adb('shell','dumpsys','window')
    if 'isKeyguardShowing=false' not in w or 'isKeyguardShowing=true' in w or 'mScreenOnFully=true' not in w:
        raise RuntimeError('STOP: keyguard or screen precondition failed; do not unlock')
    return w

def note(s):
    with D.open('a',encoding='utf-8') as f:f.write('\n- '+s+'\n')
def run(cmd):
    p=subprocess.run(list(map(str,cmd)),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    with (O/'rerun6-install.log').open('a',encoding='utf-8') as f:f.write(p.stdout+'\n')
    if p.returncode:raise RuntimeError(p.stdout)
    return p.stdout
unlocked()
inputs=json.loads((O/'rerun6-source-hashes.json').read_text(encoding='utf-8'))
for name,digest in inputs.items():
    assert hashlib.sha256((R/name).read_bytes()).hexdigest()==digest,name
assert b'_abrHold' in (R/'lib/src/core/engine.dart').read_bytes()
assert b'(_pendingSeekTarget == null &&' in (R/'lib/src/core/engine.dart').read_bytes()

note('开始重打包与安装：从本轮 Gradle APK 提取并核对原生库，zipalign 后使用既有 debug.keystore 重签；安装前后记录证书、SHA256 与 lastUpdateTime。')
build=R/'example/build/app/outputs/flutter-apk/app-release.apk'
assert build.exists()
before=adb('shell','dumpsys','package','com.icodejoo.mova.mova_example.coverage');(O/'rerun6-package-before.txt').write_text(before,encoding='utf-8')
# Reuse the existing strict LFS replacement implementation with rerun6 outputs.
s=(H/'coverage_repack.py').read_text(encoding='utf-8').replace("'coverage-unsigned.apk'","'rerun6-unsigned.apk'")
exec(compile(s,str(H/'coverage_repack.py'),'exec'),{'__file__':str(H/'coverage_repack.py'),'__name__':'__main__'})
bt=Path('E:/sdk/android/build-tools/36.0.0'); apk=O/'rerun6-installed.apk'
run([bt/'zipalign.exe','-f','-p','4',O/'rerun6-unsigned.apk',O/'rerun6-aligned.apk'])
run([bt/'apksigner.bat','sign','--ks',Path.home()/'.android/debug.keystore','--ks-key-alias','androiddebugkey','--ks-pass','pass:android','--key-pass','pass:android','--out',apk,O/'rerun6-aligned.apk'])
cert=run([bt/'apksigner.bat','verify','--verbose','--print-certs',apk]);(O/'rerun6-certificate.txt').write_text(cert,encoding='utf-8')
unlocked();run(['adb','-s','7NQBB23606003715','install','-r',apk])
after=adb('shell','dumpsys','package','com.icodejoo.mova.mova_example.coverage');(O/'rerun6-package-after.txt').write_text(after,encoding='utf-8')
path=adb('shell','pm','path','com.icodejoo.mova.mova_example.coverage').strip().removeprefix('package:')
run(['adb','-s','7NQBB23606003715','pull',path,O/'rerun6-device-pulled.apk'])
hashof=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
manifest={'containsAbrHold':True,'buildInputHashes':inputs,'target':'lib/main_rerun6_coverage_api.dart','buildMarker':'rerun6-20261027','gradleApkSha256':hashof(build),'signedApkSha256':hashof(apk),'deviceApkSha256':hashof(O/'rerun6-device-pulled.apk'),'engineSha256':hashof(R/'lib/src/core/engine.dart'),'installedLastUpdate':[x.strip() for x in after.splitlines() if 'lastUpdateTime=' in x]}
assert manifest['signedApkSha256']==manifest['deviceApkSha256']
(O/'rerun6-build-manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
note('构建安装检查点：新 release 安装成功，设备拉回 APK SHA256 与重签包完全一致；lastUpdateTime/证书/源码哈希见 rerun6-build-manifest.json、rerun6-package-after.txt、rerun6-certificate.txt。')
note('开始本地源与页面启动：复用已存在同一 VOD/HLS 素材，18080 提供 rerun-sources，18084 提供其 hls/high、low；设置 adb reverse 并确认新页面构建标记。')
kids=[]
weaklog=(O/'rerun6-service-18085.log').open('w',encoding='utf-8')
weak=subprocess.Popen([sys.executable,'-u',str(H/'rerun6_media.py')],stdout=weaklog,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
kids.append(weak)
adb('reverse','tcp:18085','tcp:18085')
for port,folder in [(18080,H/'rerun-sources'),(18084,H/'rerun-sources/hls')]:
    log=(O/f'rerun6-service-{port}.log').open('w',encoding='utf-8')
    kids.append(subprocess.Popen([sys.executable,'-u','-m','http.server',str(port),'--bind','127.0.0.1','--directory',str(folder)],stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW))
    adb('reverse',f'tcp:{port}',f'tcp:{port}')
(O/'rerun6-services.json').write_text(json.dumps([p.pid for p in kids]),encoding='utf-8')
adb('forward','tcp:18083','tcp:18083');adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage');unlocked()
adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
from coverage_device import request
for _ in range(100):
    try:
        d=request('/');assert any(x.get('build')=='rerun6-20261027' for x in d['records']);break
    except Exception:time.sleep(.25)
else:raise RuntimeError('new build marker missing')
(O/'rerun6-start.json').write_text(json.dumps(d,indent=2),encoding='utf-8')
note('源/启动检查点：新页面 SERVER build=rerun6-20261027，双端口服务已启动并保存 owned PIDs；后续仅使用 rerun6 证据。')
print(json.dumps(manifest,indent=2),flush=True)
