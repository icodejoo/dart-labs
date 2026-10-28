"""Build the release probe without altering LFS pointers or package sources."""
from pathlib import Path
import hashlib, subprocess, sys, time, shutil, json

H = Path(__file__).resolve().parent
R = H.parents[1]
O = H/'coverage_evidence'
B = R/'example/build/windows/x64'
artifacts = {}
for name in ['libmpv.dll.a','libmpv-2.dll']:
    pointer = R/'libmpv/windows-x64'/name
    out = O/('win-libmpv-'+name)
    if not pointer.read_bytes().startswith(b'version https://git-lfs'):
        # 已水合的真实文件：直接用，不再走 smudge。
        artifacts[name] = pointer
        continue
    fields = dict(line.split(' ',1) for line in pointer.read_text().splitlines())
    expected = fields['oid'].split(':')[1]
    if not out.exists():
        result = subprocess.run(['git','-c','lfs.url=https://github.com/icodejoo/dart-labs.git/info/lfs','lfs','smudge'],input=pointer.read_bytes(),stdout=subprocess.PIPE,stderr=subprocess.PIPE,cwd=R)
        (O/('win-lfs-'+name+'.log')).write_bytes(result.stderr)
        if result.returncode: raise RuntimeError(result.stderr.decode(errors='replace'))
        assert hashlib.sha256(result.stdout).hexdigest()==expected
        out.write_bytes(result.stdout)
    assert hashlib.sha256(out.read_bytes()).hexdigest()==expected
    artifacts[name]=out
(O/'win-libmpv-hashes.json').write_text(json.dumps({k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in artifacts.items()},indent=2))
build=sys.argv[1]
log=(O/f'win-build-{build}-complete.log').open('w')
proc=subprocess.Popen(['cmd','/c','flutter','build','windows','--release','-t','lib/main_win_retest.dart',f'--dart-define=WIN_BUILD={build}'],cwd=R/'example',stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
while proc.poll() is None:
    # CMake copies the source pointer each configure; fix only its generated copy.
    # CMake配置复制源指针；仅补齐生成目录内副本。
    target=B/'libmpv/libmpv.dll.a'
    if target.exists() and target.stat().st_size<200:
        try: shutil.copyfile(artifacts['libmpv.dll.a'],target)
        except PermissionError: pass
    time.sleep(.05)
log.close()
if proc.returncode: raise SystemExit(proc.returncode)
shutil.copyfile(artifacts['libmpv-2.dll'],B/'runner/Release/libmpv-2.dll')
print('release build complete; generated DLL/import library match LFS SHA256',flush=True)
