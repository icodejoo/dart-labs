import argparse,json
parser=argparse.ArgumentParser()
parser.add_argument("--set", type=int, default=1)
args=parser.parse_args()
prefix="bench" if args.set==1 else f"bench-set-{args.set}"
from pathlib import Path
D=Path('docs/reports/pipeline-b6-evidence')
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
 result[f'S{s+1}']=row
(D/(prefix+'-summary.json')).write_text(json.dumps(result,indent=2)+'\n')
for s,r in result.items():
 print(s,*(f"{k}: {v['median']['opsPerSecond']:.1f} ops/s, mean {v['median']['meanMicros']:.2f} us p99 {v['median']['p99Micros']:.2f} us range {v['spreadPercent']:.2f}%" for k,v in r.items()))
