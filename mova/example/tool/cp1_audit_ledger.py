"""Independent evidence-reference, APK provenance and edit-scope audit."""
from collections import Counter
import json
from pathlib import Path
import subprocess

root=Path(__file__).resolve().parents[2]
target=root/'doc/plans/2026-11-03-cp1-results.json'
data=json.loads(target.read_text(encoding='utf-8'))
checks=[]
def check(name,condition):
    checks.append(dict(name=name,passed=bool(condition)))
    if not condition:print('AUDIT FAIL',name,flush=True)
check('16 master rows / 47 distinct subrows',len(data['masterRows'])==16 and len(data['rows'])==47 and len({r['id'] for r in data['rows']})==47)
check('status counts match rows',dict(Counter(r['status'] for r in data['rows']))==data['counts'])
check('master counts match rows',dict(Counter(r['status'] for r in data['masterRows']))==data['masterCounts'])
seen=set()
for issue in data['failures']:
    source=root/issue['evidence'];array=issue.get('recordArray','records');index=issue['recordIndex']
    signature=(str(source),array,index)
    check('unique failure '+str(signature),signature not in seen);seen.add(signature)
    if array=='logLines1Based':
        check('failed log reference',source.is_file() and 'FAIL' in source.read_text(encoding='utf-8').splitlines()[index-1])
    else:
        raw=json.loads(source.read_text(encoding='utf-8'))
        row=raw[index] if array=='root' else raw[array][index]
        check('raw FAIL retained '+str(signature),row.get('status')=='FAIL')
check('all 15 observed original failures retained',len(data['failures'])==15)
byid={r['id']:r for r in data['rows']}
for mode,count in [('normal',60),('paused',60),('cutover',160)]:
    r=byid['F3/A17 precise.'+mode]
    check('precise '+mode,r['executed']==count and r['metrics']['passes']==count and r['metrics']['below200Percent']==100 and r['status']=='PASS')
for variant in ('contentWarm','midPending','postLoad'):
    r=byid['p02.'+variant];m=r['metrics']
    check('native episode B '+variant,r['executed']==10 and m['passes']==10 and all(n==1 for n in m['matchesB']) and sum(m['wrongEpisode'])==sum(m['stillAd'])==sum(m['observationLimit'])==0)
check('dispose120 complete and below100ms',byid['dispose120.round']['counts']=={'PASS':120} and max(m['values']['maxFrameIntervalUs'] for m in byid['dispose120.round']['measurements'])<100000)
check('danmaku collection not mistaken for performance pass',byid['danmaku.jump']['collectionStatus']=='PASS' and byid['danmaku.jump']['status']=='BLOCKED')
check('keepalive five scenario rounds each',byid['keepalive-core.S1']['executed']==5 and byid['keepalive-core.S13']['executed']==5)
check('restoration independently read back',data['restoration']['status']=='VERIFIED' and data['restoration']['original']==data['restoration']['after'])
check('APK unchanged through final pull',data['restoration']['apk']['actual']==data['stage0']['metadata']['sha256']['signed']==data['stage0']['metadata']['sha256']['device'])
committed=subprocess.check_output(['git','diff','--name-only','047b179c','HEAD'],cwd=root,text=True).splitlines()
working=subprocess.check_output(['git','diff','--name-only','047b179c'],cwd=root,text=True).splitlines()
untracked=subprocess.check_output(['git','ls-files','--others','--exclude-standard'],cwd=root,text=True).splitlines()
check('only authorized source paths changed',all(p.startswith(('mova/example/','mova/doc/','example/','doc/')) for p in committed+working+untracked))
check('generated Windows plugin files excluded from commits',not any('example/windows/flutter/generated_plugin' in p for p in committed))
result=dict(passed=all(c['passed'] for c in checks),checks=checks,counts=data['counts'],masterCounts=data['masterCounts'],failedSamples=len(data['failures']),committedPaths=committed)
path=root/'example/tool/coverage_evidence/cp1-ledger-audit.json';path.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
data['audit']=dict(passed=result['passed'],evidence=path.relative_to(root).as_posix(),checkCount=len(checks))
target.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
print('AUDIT',result['passed'],'checks',len(checks),'failed samples',len(data['failures']),flush=True)
if not result['passed']:raise SystemExit(1)
