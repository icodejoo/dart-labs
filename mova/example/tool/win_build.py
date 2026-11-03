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
entry=sys.argv[2] if len(sys.argv)>2 else 'lib/main_win_retest.dart'
# CMake 4 removed the old googletest dependency's <3.5 policy compatibility.
# Set only the generated build cache; package and dependency sources stay intact.
cache=B/'CMakeCache.txt'
if not cache.exists():
    B.mkdir(parents=True, exist_ok=True)
    cache.write_text('CMAKE_INSTALL_PREFIX:PATH='+(B/'runner/Release').as_posix()+'\n'
        'CMAKE_CXX_FLAGS:STRING=/DWIN32 /D_WINDOWS /W3 /GR /EHsc\n')
if cache.exists() and 'CMAKE_POLICY_VERSION_MINIMUM:' not in cache.read_text():
    with cache.open('a') as stream: stream.write('\nCMAKE_POLICY_VERSION_MINIMUM:STRING=3.5\n')
if cache.exists():
    # VS 2026's STL requires this acknowledgement for the existing audio
    # plugin's experimental coroutine header. Again, generated cache only.
    source=cache.read_text()
    flag='/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS'
    lines=source.splitlines()
    for i,line in enumerate(lines):
        if line.startswith('CMAKE_CXX_FLAGS:STRING=') and flag not in line:
            lines[i]=line+' '+flag
        if line.startswith('CMAKE_INSTALL_PREFIX:PATH='):
            lines[i]='CMAKE_INSTALL_PREFIX:PATH='+(B/'runner/Release').as_posix()
    cache.write_text('\n'.join(lines)+'\n')
prefix=next(line.split('=',1)[1] for line in cache.read_text().splitlines()
            if line.startswith('CMAKE_INSTALL_PREFIX:PATH='))
if not Path(prefix).resolve().is_relative_to(R.resolve()):
    raise RuntimeError('install prefix must stay inside this worktree')
log=(O/f'win-build-{build}-complete.log').open('w')
proc=subprocess.Popen(['cmd','/c','flutter','build','windows','--release','-t',entry,f'--dart-define=WIN_BUILD={build}', '--dart-define=AUTORUN=true', '--dart-define=AUTOEXIT=false'],cwd=R/'example',stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
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
for installed in (B/'install_manifest.txt').read_text().splitlines():
    if not Path(installed).resolve().is_relative_to(R.resolve()):
        raise RuntimeError('build installed outside this worktree: '+installed)
shutil.copyfile(artifacts['libmpv-2.dll'],B/'runner/Release/libmpv-2.dll')
print('release build complete; generated DLL/import library match LFS SHA256',flush=True)
