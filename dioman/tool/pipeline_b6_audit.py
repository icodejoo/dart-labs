import json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/reports/pipeline-b6-evidence'

def main():
 inventory=json.loads((ROOT/'test/accept/lib/api-inventory.json').read_text())
 public={x['api'] for x in inventory}
 roots={a.split('.')[0] for a in public}
 ren=json.loads((ROOT/'docs/reports/pipeline-b5b-evidence/api-renames.json').read_text())
 rem=json.loads((ROOT/'docs/reports/pipeline-b5b-evidence/api-removals.json').read_text())
 excluded=lambda a: 'DiomanMockAdapter' in a or 'x-dioman-mock' in a
 guide=(ROOT/'docs/guides/migrating-to-pipeline.md').read_text()
 old={x['api'] for x in rem}|set(ren)
 expected={a for a in old if not excluded(a)}
 listed=set(re.findall(r'^\| `([^`]+)` \|',guide,re.M))
 missing=sorted(expected-listed)
 targets={v for k,v in ren.items() if not excluded(k)}
 bad_targets=sorted(targets-public)
 files=['README.md','README.zh-CN.md','CHANGELOG.md','docs/guides/migrating-to-pipeline.md','docs/design/architecture.md','docs/status.md','docs/guides/test-layers.md','docs/guides/accept-runner.md','docs/reference/testkit-mapping.md','.claude/skills/dioman/SKILL.md','benchmark/README.md']
 found=set();unknown=[];historical=[]
 pattern=r'\b(?:Dioman[A-Za-z0-9_]*|StateKey|RequestPatch|Envelope|EnvRule|NetworkQuality)(?:\.[A-Za-z_]\w*)?'
 for f in files:
  text=(ROOT/f).read_text(encoding='utf-8-sig')
  if f == 'CHANGELOG.md':text=text.split('## 0.7.2')[0]
  # 迁移证据表逐行在上面核对；左列是明确的历史 API，不作当前 API 使用。
  if f.endswith('migrating-to-pipeline.md'):text=text.split('## 旧 API 逐项替代')[0]
  text=re.sub(r'<!-- docs:old -->\s*```dart[\s\S]*?```','',text)
  for n,line in enumerate(text.splitlines(),1):
   for a in re.findall(pattern,line):
    if a in public:found.add(a)
    elif a in old or a in {'Dioman.install','Dioman.sort','Dioman.validate','DiomanTokenManager.canRefresh'}:
     historical.append({'file':f,'line':n,'api':a})
    elif a.split('.')[0] in roots:
     # 泛型对象访问均由 Dart 分析器核对；文中伪代码写 Plugin.option 不在此词法范围。
     unknown.append({'file':f,'line':n,'api':a})
    else:unknown.append({'file':f,'line':n,'api':a})
 headings=lambda p:[(len(m[1]),m[2]) for m in re.finditer(r'^(#{2,3}) (.+)$',(ROOT/p).read_text(),re.M)]
 en=headings('README.md');zh=headings('README.zh-CN.md')
 structure=[a[0] for a in en]==[a[0] for a in zh]
 plugin_sections = [name for level,name in en if level == 3]
 assert len(plugin_sections) == 12
 assert plugin_sections == [name for level,name in zh if level == 3]
 rename_rows_missing = [a for a,b in ren.items() if not excluded(a) and f'| `{a}` | `{b}`' not in guide]
 result={'inventory':len(public),'checkedFiles':files,'currentNames':sorted(found),'currentNameCount':len(found),'unknownCurrent':unknown,'historicalMentions':historical,'renames':len(ren),'renamesCovered':sum(not excluded(a) for a in ren),'renameRowsMissing':rename_rows_missing,'removals':len(rem),'uniqueOld':len(old),'excludedUnreleased':sorted(a for a in old if excluded(a)),'coveredOld':len(expected&listed),'missingOld':missing,'badRenameTargets':bad_targets,'readmeStructureEqual':structure,'headingsEN':en,'headingsZH':zh}
 OUT.mkdir(parents=True,exist_ok=True)
 (OUT/'api-doc-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
 print(json.dumps({k:v for k,v in result.items() if k not in ('currentNames','historicalMentions','headingsEN','headingsZH','checkedFiles')},ensure_ascii=False,indent=2))
 assert not missing and not bad_targets and not rename_rows_missing and not unknown and structure
if __name__=='__main__':main()

