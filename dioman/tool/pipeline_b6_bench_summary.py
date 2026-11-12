import argparse,json,statistics
parser=argparse.ArgumentParser()
parser.add_argument("--set", type=int, default=1)
parser.add_argument("--out", default='docs/reports/pipeline-b6-evidence')
args=parser.parse_args()
prefix="bench" if args.set==1 else f"bench-set-{args.set}"
from pathlib import Path
D=Path(args.out)
audit=D/(prefix+'-load-audit.json')
if audit.exists():
 accepted=[row for row in json.loads(audit.read_text(encoding='utf-8')) if row['accepted']]
 assert len(accepted)==3 and [row['round'] for row in accepted]==[1,2,3]
 assert all(len(row['members'])==2 and all(v['clean'] for v in row['members']) for row in accepted)
data={k:[json.loads((D/f'{prefix}-{i}-{k}.json').read_text()) for i in range(1,4)] for k in ['legacy','pipeline']}
for rounds in data.values():
 for run in rounds:
  assert run['warmupMillis'] >= 500 and run['measurementMillis'] >= 2000
  for row in run['results']:
   assert row['elapsedSeconds'] >= 2
   assert row['sends'] == (0 if row['scenario'] == 'S4' else row['operations'])
result={}
for s in range(6):
 row={}
 for k,rounds in data.items():
  samples=[r['results'][s] for r in rounds]
  median=sorted(samples,key=lambda x:x['opsPerSecond'])[1]
  spread=(max(x['opsPerSecond'] for x in samples)/min(x['opsPerSecond'] for x in samples)-1)*100
  row[k]={'median':median,'spreadPercent':spread,'stable':spread<10,'ops':[x['opsPerSecond'] for x in samples]}
  row[k]['selectedRound']=samples.index(median)+1
  if s in (1,2):
   ratios=[run['results'][s]['meanMicros']/run['results'][0]['meanMicros']-1 for run in rounds]
   row[k]['overheadRatios']=ratios
   row[k]['medianOverheadRatio']=statistics.median(ratios)
 result[f'S{s+1}']=row
(D/(prefix+'-summary.json')).write_text(json.dumps(result,indent=2)+'\n')
for s,r in result.items():
 print(s,*(f"{k}: {v['median']['opsPerSecond']:.1f} ops/s, mean {v['median']['meanMicros']:.2f} us p99 {v['median']['p99Micros']:.2f} us range {v['spreadPercent']:.2f}%" for k,v in r.items()))
group_stable=all(value['stable'] for row in result.values() for value in row.values())
gates={}
for scenario in ('S2','S3','S4','S5','S6'):
 row=result[scenario]
 dependencies=('S1',scenario) if scenario in ('S2','S3') else (scenario,)
 eligible=all(value['stable'] for dependency in dependencies for value in result[dependency].values())
 if scenario in ('S2','S3'):
  a=row['legacy']['medianOverheadRatio']
  b=row['pipeline']['medianOverheadRatio']
  passed=b <= (a if scenario=='S2' else a*.8)
  gates[scenario]={'eligible':eligible,'legacyOverhead':a,'pipelineOverhead':b,'passed':passed if eligible else None}
 else:
  a=row['legacy']['median']['opsPerSecond']
  b=row['pipeline']['median']['opsPerSecond']
  gates[scenario]={'eligible':eligible,'throughputChangePercent':(b/a-1)*100,'passed':b>=a if eligible else None}
 gates[scenario]['groupStable']=group_stable
 gates[scenario]['dependencies']=dependencies
(D/(prefix+'-gates.json')).write_text(json.dumps(gates,indent=2)+'\n')
