"""Run the one-line negative control and restore the exact original bytes."""
from pathlib import Path
import hashlib,json,subprocess,sys
from win_host import note,OUT,ROOT

engine=ROOT/'lib/src/core/engine.dart'
original=engine.read_bytes()
needle=b'await _seekOrPark(pos, forcePark: !_variantLanded);'
replacement=b'await _seekOrPark(pos, forcePark: false);'
assert original.count(needle)==1
sha=hashlib.sha256(original).hexdigest()
note(f'开始F3未修复对照：先归档原始SHA256={sha}及git diff，唯一临时改动为forcePark: !_variantLanded→false；结束后finally原字节还原并核对哈希。')
(OUT/'win-engine-fixed.bytes').write_bytes(original)
diff=subprocess.run(['git','diff','--','lib/src/core/engine.dart'],cwd=ROOT,capture_output=True,check=True)
(OUT/'win-f3-fix.patch').write_bytes(diff.stdout)
(OUT/'win-f3-diff-stderr.log').write_bytes(diff.stderr)
record={'before':sha,'patch':'win-f3-fix.patch','changedLine':'forcePark: !_variantLanded -> forcePark: false'}
(OUT/'win-engine-hashes.json').write_text(json.dumps(record,indent=2))
try:
    subprocess.run([sys.executable,str(Path(__file__).with_name('win_host.py')),'stop-app'],check=True)
    engine.write_bytes(original.replace(needle,replacement))
    record['negativeControl']=hashlib.sha256(engine.read_bytes()).hexdigest()
    (OUT/'win-engine-hashes.json').write_text(json.dumps(record,indent=2))
    note(f'临时改动检查点：只替换唯一一行、保留原文件所有其他字节；未修复SHA256={record["negativeControl"]}。开始同页同素材同次数release重构建。')
    subprocess.run([sys.executable,str(Path(__file__).with_name('win_build.py')),'unfixed'],check=True)
    note('未修复release构建检查点：exit 0；开始与修复版相同normal/cutover/paused各34次。')
    subprocess.run([sys.executable,str(Path(__file__).with_name('win_host.py')),'start','unfixed'],check=True)
    subprocess.run([sys.executable,str(Path(__file__).with_name('win_host.py')),'hls','unfixed'],check=True)
finally:
    current=engine.read_bytes()
    assert current in (original,original.replace(needle,replacement)), 'Unexpected concurrent engine modification; inspect before restore'
    engine.write_bytes(original)
    record['restored']=hashlib.sha256(engine.read_bytes()).hexdigest()
    record['restoredMatches']=record['restored']==sha
    (OUT/'win-engine-hashes.json').write_text(json.dumps(record,indent=2))
    note(f'还原检查点：engine.dart 已恢复原字节，SHA256={record["restored"]}，与开始一致={record["restoredMatches"]}。')
    assert record['restoredMatches']
