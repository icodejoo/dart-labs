from pathlib import Path
import subprocess,hashlib,json,sys
R=Path(__file__).resolve().parents[2];O=R/'example/tool/coverage_evidence';D=R/'doc/plans/2026-10-27-device-coverage-android-retest3.md'
def note(s):
 with D.open('a',encoding='utf-8') as f:f.write('\n- '+s+'\n')
hashes={str(p.relative_to(R)):hashlib.sha256(p.read_bytes()).hexdigest() for base in ['lib','test','packages'] for p in (R/base).rglob('*') if p.is_file() and not any(x in p.parts for x in ['build','.dart_tool','.git'])}
(O/'rerun4-protected-tree-hashes.json').write_text(json.dumps(hashes,indent=2),encoding='utf-8')
for name,args in [('analyze',['analyze','lib','test']),('test',['test'])]:
 note('开始基线 '+name+'：执行 flutter '+ ' '.join(args)+'，记录实际数字与完整输出。')
 with (O/f'rerun4-{name}.log').open('w',encoding='utf-8') as f:
  p=subprocess.run(['flutter.bat',*args],cwd=R,stdout=f,stderr=subprocess.STDOUT)
 note(f'{name} 检查点：exit={p.returncode}；完整日志 rerun4-{name}.log。')
 print(name,p.returncode,flush=True)
 if p.returncode:sys.exit(p.returncode)
