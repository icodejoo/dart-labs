"""VM 采样仅用于热点线索，不参与 A/B 计时结论。"""
import collections,gzip,json,re,shutil,subprocess,time,urllib.request,urllib.parse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/reports/pipeline-b6-evidence'
def main():
 log=OUT/'profile-process.txt'
 with log.open('w',encoding='utf-8') as stream:
  process=subprocess.Popen([shutil.which('dart'),'--enable-vm-service=0','--disable-service-auth-codes','--profiler','--pause-isolates-on-exit','benchmark/pipeline.dart'],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
  try:
   deadline=time.monotonic()+100
   uri=None
   while time.monotonic()<deadline:
    content=log.read_text(encoding='utf-8')
    match=re.search(r'http://127\.0\.0\.1:\d+/',content)
    if match:uri=match[0]
    if uri and '"measurementMillis"' in content:break
    if process.poll() is not None:raise RuntimeError(content)
    time.sleep(.2)
   if not uri:raise RuntimeError('VM service not found')
   def rpc(method,**parameters):
    url=uri+method+'?'+urllib.parse.urlencode(parameters)
    with urllib.request.urlopen(url,timeout=20) as response:return json.load(response)
   vm=rpc('getVM')['result']
   isolate=next(i for i in vm['isolates'] if i['name']=='main')['id']
   samples=rpc('getCpuSamples',isolateId=isolate,timeOriginMicros=0,timeExtentMicros=1000000000)['result']
   with gzip.open(OUT/'profile-samples.json.gz','wt',encoding='utf-8') as f:json.dump(samples,f)
   inclusive=collections.Counter();exclusive=collections.Counter()
   for sample in samples['samples']:
    stack=sample.get('stack',[])
    if stack:exclusive[stack[0]]+=1
    inclusive.update(set(stack))
   functions=samples['functions']
   def rows(counts):
    return [{'samples':n,'function':functions[i].get('function',functions[i])} for i,n in counts.most_common(30)]
   summary={'sampleCount':samples['sampleCount'],'samplePeriod':samples['samplePeriod'],'inclusive':rows(inclusive),'exclusive':rows(exclusive)}
   (OUT/'profile-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
   print('profile samples:',samples['sampleCount'])
   print(json.dumps(summary['exclusive'][:8],ensure_ascii=False))
  finally:
   if process.poll() is None:process.terminate()
   process.wait(timeout=20)
if __name__=='__main__':main()
