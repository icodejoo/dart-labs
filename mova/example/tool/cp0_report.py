"""Reduce this CP0 run only; missing results remain missing, never zero failures."""
from pathlib import Path
import json
import statistics
import sys
import re

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'example/tool/coverage_evidence'
P=ROOT/'doc/plans/2026-11-03-cp0-baseline'

def rel(p):return Path(p).relative_to(ROOT).as_posix()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def nums(values):
    v=[x for x in values if isinstance(x,(int,float))]
    return dict(min=min(v),median=statistics.median(v),max=max(v)) if v else None

def main():
    ledger=read(str(P)+'.json')
    ledger['status']='RUNNING';ledger['completed']=False
    ledger['run']='CP0 formal 2026-11-03; baseline a5c317f6; lib/test unchanged'
    ledger['excluded']={'cp0-pod2':'用户明确跳过：旧页默认不等待就绪，epoch 0→0 不能证明回落','audioFocus':'manual BLOCKED','full49':'本轮不在范围'}
    apk=E/'matrix-cp0-autotier-formal-20261103-01/matrix-cp0-autotier-formal-20261103-01-build.json'
    sha=read(apk).get('sha256',{}).get('device') if apk.exists() else None
    ledger['androidApkSha256']=sha
    ledger['previousAttempt']='a5c317f6: 设备离线，正式样本0；历史夹具/构建数字不计入本轮'
    ledger['apk']=dict(sourceEvidence=rel(apk),deviceSha256=sha,signedSha256=sha,installed=sha is not None)
    ledger['preflight']=dict(ready=True,evidence='example/tool/coverage_evidence/cp0-session-original.json')
    ledger['fixturePreflight']=dict(evidence='example/tool/coverage_evidence/matrix-cp0-autotier-formal-20261103-01/matrix-cp0-autotier-formal-20261103-01-cp0-autotier.fixtures.json')
    ledger['validation']=dict(dartAnalyze='统一Android入口及coverage_gap: No issues found',matrixCheck='49 batches / 135 IDs / 6 manual',releaseBuild='BUILD SUCCESSFUL in 2m54s; worker=1, Xmx1024m; installed/pulled SHA256 identical')
    ledger['restoration']=dict(originalMediaVolume=0,originalUsbStayAwake=7,originalMappingsEvidence='example/tool/coverage_evidence/cp0-session-original.json',status='verified' if (E/'cp0-session-restored.json').exists() else '每批finally恢复；整轮结束后再次核验')
    for stage in ledger['stages']:
        for item in stage['items']:
            if item['item']=='pod2':
                item.update(status='SKIPPED',reason=ledger['excluded']['cp0-pod2'],executed=0,failures=None);continue
            if item.get('executed',0)==0:
                item.update(status='PENDING',reason='本轮待执行',evidence=None)
    def put(name,executed,metrics,evidence,failures=None,complete=True,reason=None):
        item=next(i for s in ledger['stages'] for i in s['items'] if i['item']==name)
        item.update(executed=executed,metrics=metrics,evidence=evidence,failures=failures,
                    status='MEASURED' if complete else 'PARTIAL',reason=reason,
                    deviceApkSha256=sha if not name.startswith('Windows') else None)
    stage1=E/'matrix-cp0-autotier-formal-20261103-01/matrix-cp0-autotier-formal-20261103-01-cp0-autotier.json'
    if stage1.exists():
        d=read(stage1)
        for mode,name in [('limited','P1-3 限速 auto'),('unlimited','P1-3 不限速对照')]:
            summary=[r for r in d.get('summary',[]) if '.'+mode+'.' in r['case']]
            checks=[r for r in d['records'] if r.get('kind')=='CHECK' and '.'+mode+'.' in r.get('id','')]
            for r in summary:
                c=next(c for c in checks if c['id']==r['case'])
                samples=c['numbers']['samples']
                r['nativeHlsBitrates']=sorted(set(str(s['properties'].get('hls-bitrate')) for s in samples))
                r['sampleCount']=len(samples)
                r['timePosSeconds']=[dict(second=s['scheduledSeconds'],value=s['properties'].get('time-pos'),pausedForCache=s['properties'].get('paused-for-cache')) for s in samples]
                edges=r.get('bufferEvents',[]);start=None;intervals=[]
                for edge in edges:
                    if edge.get('payload',{}).get('buffering'):
                        if start is None:start=edge['us']
                    elif start is not None:
                        intervals.append(dict(startUs=start,endUs=edge['us'],durationUs=edge['us']-start,rightCensored=False));start=None
                if start is not None and samples:
                    intervals.append(dict(startUs=start,endUs=samples[-1]['us'] if 'us' in samples[-1] else c['us'],durationUs=(samples[-1].get('us',c['us'])-start),rightCensored=True))
                r['bufferEventIntervals']=intervals
                r['maxBufferEventIntervalSeconds']=max((x['durationUs']/1e6 for x in intervals),default=0)
                first_frame=next((e['us'] for e in c['numbers'].get('events',[]) if e.get('event')=='MovaFirstFrame'),None)
                rebuffers=[x for x in intervals if first_frame is not None and x['startUs']>first_frame]
                r['maxRebufferSeconds']=max((x['durationUs']/1e6 for x in rebuffers),default=0)
                r['totalRebufferSeconds']=sum(x['durationUs']/1e6 for x in rebuffers)
                r['rebufferCount']=len(rebuffers)
                r['finalNativeTimePos']=samples[-1]['properties'].get('time-pos') if samples else None
            metrics=dict(runs=summary,harness=d['harness'],missing=d['missing'])
            put(name,len(summary),metrics,rel(stage1),sum(len(r['failures']) for r in summary),len(summary)==(5 if mode=='limited' else 1))
    stage2=list(E.glob('matrix-cp0-formal-*/matrix-*-cp0-*.json'))
    for p in stage2:
        d=read(p);scene=d.get('group')
        if scene not in ('p02','bgpause','pauseload','timeshift','pageview'):continue
        for variant in {'p02':['contentWarm','midPending','postLoad'],'bgpause':['true','false'],'pauseload':['loading','ready','firstFrame'],'timeshift':['dvr','timeshift'],'pageview':['horizontal','vertical']}[scene]:
            prefix='CP0.'+scene+'.'+('video.' if scene=='bgpause' else '')+variant+'.'
            checks=[r for r in d['records'] if r.get('kind')=='CHECK' and r.get('id','').startswith(prefix)]
            numbers=[r.get('numbers',{}) for r in checks]
            metrics=dict(samples=numbers,harness=d['harness'],missing=d['missing'])
            for key in ['wrongEpisode','stillAd','matchesB','observationLimit','manualResume','playingAfterLoad','seekEvents','pageEvents']:
                if any(key in n for n in numbers):metrics[key+'Total']=sum(n.get(key,0) for n in numbers)
            for key in ['playToFirstFrameUs','renderEpoch','behindStateMs','pageIndex']:
                if any(key in n for n in numbers):metrics[key]=nums([n.get(key) for n in numbers])
            anomalies=sum(bool(n.get('wrongEpisode') or n.get('stillAd') or n.get('observationLimit')) for n in numbers)
            metrics['failureCountDefinition']='p02原生错源/仍广告/观测超时样本；其余只计显式异常，不设新产品通过线'
            put(scene+'.'+variant,len(checks),metrics,rel(p),anomalies, bool(checks) and d['completed'], 'CP0仅测量，不设产品通过线；见原始数字和异常')
    for p in E.glob('matrix-cp0-android-formal-*/*cp0-result.json'):
        d=read(p);g=d['group']
        if g.startswith('precise-'):
            mode=g.removeprefix('precise-')
            put('F3/A17 precise.'+mode,d.get('executed',0),d,rel(p),d.get('executed',0)-d.get('passes',0) if d.get('executed') else None,d['completed'])
        else:
            verdicts=d['verdicts']
            names=['H28 default.playing','H28 default.paused','H28 default.cutover'] if g=='cp0-h28' else ['H20.hlsSeek','H50.hlsSeek'] if g=='cp0-parked' else [i['item'] for s in ledger['stages'] if s['stage']==3 for i in s['items'] if not i['item'].startswith(('F3/','H28 ','H20','H50'))]
            for name in names:
                prefix='gap:'+name.replace('H28 default.','H28.default.')
                vs=[v for v in verdicts if v['case']==prefix or v['case'].startswith(prefix+'.')]
                if not vs:continue
                executed=len(set(v['case'] for v in vs)) if g=='cp0-parked' else len(vs)
                failures=sum(v['status']=='FAIL' for v in vs)
                put(name,executed,dict(verdicts=vs,harness=d['harness']),rel(p),failures,d['completed'])
    win=E/'cp0-windows-formal'
    if (win/'results.json').exists():
        wr=read(win/'results.json')
        for item,prefix,planned in [('Windows F3','F3-',30),('Windows A23/F13 dispose','dispose-',20),('Windows HE V6','V6-',5),('Windows HE V10','V10-',20)]:
            runs=[r for r in wr if r['item'].startswith(prefix)]
            metrics=dict(runs=runs,crashes=sum(r['crashed'] for r in runs),focusMismatchCount=sum(r.get('focusMismatchCount',0) for r in runs))
            if prefix=='F3-':
                rs=[]
                for run in runs:
                    jp=win/(run['item']+'.json')
                    if jp.exists():rs += [r for r in read(jp)['rows'] if r['kind']=='HLS_RESULT']
                metrics['results']=rs;metrics['below200']=sum(r.get('landed',-1)>=0 and abs(r['landed']-r['target'])<200 and r.get('path')==r.get('expectedPath') for r in rs)
                failures=sum(not (r.get('landed',-1)>=0 and abs(r['landed']-r['target'])<=500 and r.get('path')==r.get('expectedPath')) for r in rs)
                executed=len(rs)
            elif prefix=='dispose-':
                calls=[]
                for run in runs:
                    jp=win/(run['item']+'.json')
                    if jp.exists():calls += [r for r in read(jp)['rows'] if r['kind']=='DISPOSE_RETURN']
                metrics['disposeCallCount']=len(calls);metrics['exceptions']=[r for r in calls if r.get('exception')]
                executed=len(runs);failures=len(metrics['exceptions'])+metrics['crashes']
            else:
                vs=[];logs=[]
                for run in runs:
                    lp=win/(run['item']+'.he.log')
                    if lp.exists():
                        text=lp.read_text(encoding='utf-8',errors='replace');logs.append(rel(lp))
                        vs += re.findall(r'VERDICT (V\d+) (PASS|FAIL) ([^\n]*)',text)
                metrics.update(verdicts=vs,logs=logs,verdictCount=len(vs))
                executed=len(runs);failures=sum(v[1]=='FAIL' for v in vs)+metrics['crashes']
            put(item,executed,metrics,rel(win/'results.json'),failures,executed==planned and all(r['completed'] or r['crashed'] for r in runs))
    ledger['restorationEvidence']='example/tool/coverage_evidence/cp0-session-restored.json' if (E/'cp0-session-restored.json').exists() else None
    if 'final' in sys.argv:
        ledger['status']='COMPLETE_WITH_GAPS' if any(i['status'] in ('PENDING','PARTIAL') for s in ledger['stages'] for i in s['items']) else 'COMPLETE'
        ledger['completed']=ledger['status']=='COMPLETE'
    Path(str(P)+'.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# CP0 真机基线（2026-11-03）','',f'状态：**{ledger["status"]}**。CP0 不设产品通过线；测得故障原样保留。',
           '',f'Android release APK SHA-256：`{sha}`。阶段1构建一次，后续复用；安装拉回哈希一致。',
           '', '基线 detached a5c317f6；只在本树 mova/example、mova/doc 修改，lib/test 不改。',
           '', 'cp0-pod2 按用户指示跳过：旧页默认不等待就绪，不用 epoch 0→0 推断 cutover 回落。音频焦点 manual BLOCKED；全量49批不在本轮。',
           '', '## 实测台账','', '|阶段|项目|计划|已执行|失败|状态/关键数字|证据|','|---|---|---:|---:|---:|---|---|']
    for s in ledger['stages']:
        for i in s['items']:
            m=i.get('metrics') or {};brief={k:v for k,v in m.items() if k.endswith('Total') or k in ('passes','below200','executed','harness','missing')}
            if 'runs' in m:brief['runs']=[{k:v for k,v in r.items() if k in ('case','firstObservedTier','observedSwitchCount','switchIntervals','maxRebufferSeconds','totalRebufferSeconds','rebufferCount','finalNativeTimePos','nativeHlsBitrates','sampleCount')} for r in m['runs']]
            if 'verdicts' in m:brief['verdictCounts']={status:sum(v['status']==status for v in m['verdicts']) for status in ('PASS','FAIL','BLOCKED')}
            lines.append(f'|{s["stage"]}|{i["item"]}|{i["planned"]}|{i["executed"]}|{i.get("failures")}|{i["status"]} '+json.dumps(brief,ensure_ascii=False).replace('|','/')+'|'+str(i.get('evidence'))+'|')
    lines+=['','## 口径与证据边界','', 'P1-3：默认 createMovaEngine、auto、不手选；三档120秒HLS，共享900kbit/s限速。每秒原生读回档位、hls-bitrate、视频轨、缓存；切换时刻报告相邻采样区间，次数为观测下界。事件戳来自单调事件记录；卡顿结合原生 time-pos/paused-for-cache 与 MovaBufferChange，不以墙钟估算。完整逐轮数字在同名 JSON。',
            '', 'precise 沿用 rerun6 合格 RESTART/目标档位门槛，另算 CP0：目标与原生 time-pos 误差≤500ms 且 path 正确；<200ms 占比以已执行次数为分母。保留原续播/暂停判据与 harnessInvalid，不将缺样本算作成功。H28 默认配置不开泵。H20 使用 open 后立即seek(15s)，H50使用 cutoverTo(hls,at:12s)。',
            '', 'run_matrix.py 最小改动：增加 --reuse-apk，安装后拉回核对SHA256，避免阶段间重建；adb 增加断线15分钟/30秒重检。coverage1规则未改。',
            '', '恢复项以 cp0-session-original.json / cp0-session-restored.json 逐值核验；原值媒体音量0、USB常亮7，gnirehtet reverse 映射保留。原始证据均位于 gitignored example/tool/coverage_evidence/。',
            '', '本轮前的设备离线0样本仅为历史准备，不能代替本轮实测。上轮报告与台账可从 a5c317f6 复核。']
    Path(str(P)+'.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('CP0 report updated',ledger['status'],'apk',sha)

if __name__=='__main__':main()
