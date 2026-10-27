"""Run the final instrumented package after the main serial plan has completed."""
from pathlib import Path
import subprocess,sys,json,zipfile,hashlib
import coverage_record
from coverage_record import update
H=Path(__file__).resolve().parent;O=H/'coverage_evidence'
coverage_record.RESULT=H.parents[1]/'doc/plans/2026-10-27-device-coverage-rerun.md'
apk=H.parent/'build/app/outputs/apk/release/app-release.apk'
payload=zipfile.ZipFile(apk).read('lib/arm64-v8a/libmpv.so')
(O/'rerun-final-build-manifest.json').write_text(json.dumps({'apkSha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'mpvBytes':len(payload),'mpvSha256':hashlib.sha256(payload).hexdigest(),'target':'lib/main_coverage_suite.dart','mode':'release'},indent=2),encoding='utf-8')
update('开始最终补测包',[],['- 安装最终隔离release：新增实时戳TLS、亮度越界原生读回、可见宽高同步快照、质量字段、V6连续缓冲区间取证。此前证据保留；不改库。'])
with (O/'rerun-final-install.log').open('w',encoding='utf-8') as log:
    subprocess.run(['adb','-s','7NQBB23606003715','install','-r',str(apk)],check=True,stdout=log,stderr=subprocess.STDOUT)
jobs=[('final-api',['coverage_suite_device.py','api','--name','rerun-final-api','--timeout','60']),
 ('final-tls',['coverage_device.py','new','--arg','case=tls','--name','rerun-final-tls','--timeout','180']),
 ('final-tls-probe',['coverage_device.py','new','--arg','case=tlsProbe','--name','rerun-final-tls-probe','--timeout','180']),
 ('final-hls',['coverage_device.py','new','--arg','case=hls','--arg','cutover=true','--name','rerun-final-hls-cutover','--timeout','180']),
 ('final-abr',['coverage_device.py','new','--arg','case=abr','--name','rerun-final-abr','--timeout','180']),
 ('extras',['rerun_extra.py']),('live-inputs',['rerun_live_inputs.py']),('native-inputs',['rerun_native_inputs.py']),
 ('he-v6-final',['coverage_suite_device.py','he','--only','V6','--runs','5','--timeout','300','--name','rerun-he-v6-final']),
 ('manual-ready',['coverage_suite_device.py','api','--name','rerun-manual-ready','--timeout','60'])]
for name,args in jobs:
    update('开始 '+name,[],['- 命令：`python example/tool/'+' '.join(args)+'`。补齐编号剩余子项；按真实状态/事件判断。'])
    print('BEGIN',name,flush=True)
    with (O/('rerun-post-'+name+'.log')).open('w',encoding='utf-8') as log:
        p=subprocess.run([sys.executable,str(H/args[0]),*args[1:]],cwd=H.parents[1],stdout=log,stderr=subprocess.STDOUT)
    update('结束 '+name,[],[f'- exit={p.returncode}；驱动输出 rerun-post-{name}.log；编号判定在最终台账中汇总。'])
    print('END',name,p.returncode,flush=True)
openssl='C:/Program Files/Git/mingw64/bin/openssl.exe'
with (O/'rerun-openssl-verify.txt').open('w',encoding='utf-8') as log:
    for name,flag,host in [('good','-verify_ip','127.0.0.1'),('good_dns','-verify_hostname','localhost')]:
        subprocess.run([openssl,'verify','-CAfile',str(H/'coverage_tls/ca.pem'),flag,host,str(H/f'coverage_tls/{name}.pem')],stdout=log,stderr=subprocess.STDOUT)
print('RERUN_POST_DONE',flush=True)
