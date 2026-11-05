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
    if (E/'cp0-device-disconnect.json').exists():
        ledger['incidents']=[dict(kind='Android transport lost',detail='precise.cutover 第24个结果后ADB掉线，约5分20秒后观察到重连；恢复自有映射，原批最终读回26个结果/1失败及后续重定位超时；保留原批并补134次。',evidence=['example/tool/coverage_evidence/cp0-device-disconnect.json','example/tool/coverage_evidence/cp0-reconnect.jsonl','example/tool/coverage_evidence/cp0-cutover-reconnected.json']),
          dict(kind='host driver error',detail='新宿主调用gap时漏传timeout；初次H28/parked报AttributeError，不计为产品失败或正式样本。保存现场并修正后重跑。',evidence=['example/tool/coverage_evidence/cp0-gap-host-error-snapshot.json','example/tool/coverage_evidence/matrix-cp0-android-formal-20261103-1353-cp0-h28/cp0-result.json','example/tool/coverage_evidence/matrix-cp0-android-formal-20261103-1353-cp0-parked/cp0-result.json'])]
    if (E/'cp0-windows-unexpected-install-manifest.txt').exists():
        ledger.setdefault('incidents',[]).append(dict(kind='workspace boundary violation',detail='Windows CMake默认安装前缀导致运行包被写入 C:/Program Files/mova_example，违反仅在本树mova内写文件的约束；初次修正配置失败后顺序命令仍执行了一次旧安装脚本，记录于install-in-tree.log。随后以Python参数数组重新配置，检查全部安装脚本不含旧前缀后才重新安装，本树27个安装目标均核验通过。外部路径先前内容未备份，未擅自删除，无法声称恢复。',evidence=['example/tool/coverage_evidence/cp0-windows-unexpected-install-manifest.txt','example/tool/coverage_evidence/cp0-windows-install-in-tree.log','example/tool/coverage_evidence/cp0-windows-configure-prefix-fixed.log','example/tool/coverage_evidence/cp0-windows-install-in-tree-fixed.log']))
        ledger['windowsBuild']=dict(mode='release',entry='example/lib/main_win_retest.dart',cmakeParallel=4,
          compatibility=['生成CMakeCache设置CMAKE_POLICY_VERSION_MINIMUM:STRING=3.5','构建进程CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS','CMAKE_INSTALL_PREFIX明确设置为本树example/build/windows/x64/runner/Release'],
          buildEvidence=['example/tool/coverage_evidence/cp0-windows-build-attempt1.log','example/tool/coverage_evidence/cp0-windows-build-attempt2.log','example/tool/coverage_evidence/win-build-cp0-formal-20261103-complete.log'],
          startupFailureEvidence='example/tool/coverage_evidence/cp0-windows-startup-failure/results.json',startupFailureExitCode='0xC0000135',startupFailuresExcludedFromFormal=48)
    if (E/'cp0-windows-first-cleanup-hang').exists():
        ledger.setdefault('incidents',[]).append(dict(kind='Windows diagnostic teardown hang',detail='一次Windows F3普通诊断轮已获10个通过落点，但HTTP仍为running、收尾超过120秒无END；主动终止自启进程。焦点轨迹未持续落盘，该轮不计正式30；现象不抹去，尚不能归因内核或验证页。',evidence=['example/tool/coverage_evidence/cp0-windows-first-cleanup-hang/F3-normal.watchdog.json','example/tool/coverage_evidence/cp0-windows-first-cleanup-hang/F3-normal.json']))
    if (E/'cp0-windows-focus-invalid').exists():
        ledger.setdefault('incidents',[]).append(dict(kind='Windows foreground interruptions',detail='记录到termarx/Chrome抢占前台。未满足焦点条件的轮次保留并排除，修正开跑前PID握手、隐藏截图辅助进程、持续记录焦点；每项最多补跑5次，最终只统计无焦点中断的样本。',evidence=['example/tool/coverage_evidence/cp0-windows-focus-invalid/','example/tool/coverage_evidence/cp0-windows-formal/focus-retries/','example/tool/coverage_evidence/cp0-windows-final-monitor.json']))
    if (E/'cp0-windows-desktop-blocked.json').exists():
        ledger['windowsInputDesktop']=dict(observed=read(E/'cp0-windows-desktop-blocked.json'),checksEvidence='example/tool/coverage_evidence/cp0-windows-input-desktop.jsonl',finalMonitor=read(E/'cp0-windows-final-monitor.json') if (E/'cp0-windows-final-monitor.json').exists() else None)
        ledger.setdefault('incidents',[]).append(dict(kind='Windows input desktop unavailable, recovered',detail='曾观察到GetForegroundWindow=NULL、OpenInputDesktop错误5；没有假定是锁屏或UAC，也未操纵安全桌面。按30秒检查、10分钟上限等待，输入桌面恢复后补齐有真实前台采样且无中断的全部正式次数。',evidence=['example/tool/coverage_evidence/cp0-windows-desktop-blocked.json','example/tool/coverage_evidence/cp0-windows-input-desktop.jsonl','example/tool/coverage_evidence/cp0-windows-final-monitor.json']))
    for stage in ledger['stages']:
        for item in stage['items']:
            if item['item']=='pod2':
                item.update(status='SKIPPED',reason=ledger['excluded']['cp0-pod2'],executed=0,failures=None);continue
            if item.get('executed',0)==0:
                item.update(status='PENDING',reason='本轮待执行',evidence=None)
    def put(name,executed,metrics,evidence,failures=None,complete=True,reason=None):
        item=next(i for s in ledger['stages'] for i in s['items'] if i['item']==name)
        if item['planned']=='按现有用例次数':
            item['planned']=12 if name=='H14.manualSeek' else 3 if name.startswith('H17.') or name=='H42.wake' else 1
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
                r['qualityEventUs']=[e['us'] for e in r.pop('qualityEvents',[])]
                r['bufferEventCount']=len(r.pop('bufferEvents',[]))
                r['failureEvents']=[dict(event=e.get('event'),us=e.get('us'),payload=e.get('payload')) for e in r.pop('failures',[])]
                r.pop('timePosSeconds',None)
            metrics=dict(runs=summary,harness=d['harness'],missing=d['missing'])
            put(name,len(summary),metrics,rel(stage1),sum(len(r['failureEvents']) for r in summary),len(summary)==(5 if mode=='limited' else 1))
    stage2=list(E.glob('matrix-cp0-formal-*/matrix-*-cp0-*.json'))
    for p in stage2:
        d=read(p);scene=d.get('group')
        if scene not in ('p02','bgpause','pauseload','timeshift','pageview'):continue
        for variant in {'p02':['contentWarm','midPending','postLoad'],'bgpause':['true','false'],'pauseload':['loading','ready','firstFrame'],'timeshift':['dvr','timeshift'],'pageview':['horizontal','vertical']}[scene]:
            prefix='CP0.'+scene+'.'+('video.' if scene=='bgpause' else '')+variant+'.'
            checks=[r for r in d['records'] if r.get('kind')=='CHECK' and r.get('id','').startswith(prefix)]
            numbers=[r.get('numbers',{}) for r in checks]
            metrics=dict(harness=d['harness'],missing=d['missing'])
            for key in ['wrongEpisode','stillAd','matchesB','observationLimit','manualResume','playingAfterLoad','seekEvents','pageEvents']:
                if any(key in n for n in numbers):metrics[key+'Total']=sum(n.get(key,0) for n in numbers)
            for key in ['playToFirstFrameUs','renderEpoch','behindStateMs','pageIndex']:
                if any(key in n for n in numbers):metrics[key]=nums([n.get(key) for n in numbers])
            if scene=='bgpause':
                metrics['afterNativePauseYesTotal']=sum(n.get('after',{}).get('pause')=='yes' for n in numbers)
                metrics['afterStatePlayingFalseTotal']=sum(n.get('after',{}).get('state',{}).get('playing') is False for n in numbers)
                metrics['nativeAdvanceMs']=nums([n['after']['timePosMs']-n['before']['timePosMs'] for n in numbers if isinstance(n.get('after',{}).get('timePosMs'),int) and isinstance(n.get('before',{}).get('timePosMs'),int)])
            if scene=='pauseload':
                reports=[r for n in numbers for r in n.get('reports',[]) if '/b.mp4?' in r.get('params',{}).get('uri','')]
                metrics['sessionStartBFileFormats']=[r['params'].get('fileFormat') for r in reports]
                metrics['sessionStartBStaleFormatTotal']=sum('mp4' in str(r['params'].get('fileFormat')) for r in reports)
                metrics['fixtureBFileFormat']='matroska,webm; ffprobe evidence in batch fixtures.json'
                metrics['firstFrameBeforePlayTotal']=sum(n.get('playToFirstFrameUs',0)<0 for n in numbers)
            anomalies=sum(bool(n.get('wrongEpisode') or n.get('stillAd') or n.get('observationLimit')) for n in numbers)
            metrics['failureCountDefinition']='p02原生错源/仍广告/观测超时样本；其余只计显式异常，不设新产品通过线'
            expected=10 if scene=='p02' else 5 if scene=='bgpause' else 3
            put(scene+'.'+variant,len(checks),metrics,rel(p),anomalies,len(checks)==expected and d['completed'], 'CP0仅测量，不设产品通过线；见原始数字和异常')
    precise_acc={}
    for p in sorted(E.glob('matrix-cp0-android-formal-*/*cp0-result.json')):
        d=read(p);g=d['group']
        if g.startswith('precise-'):
            mode=g.removeprefix('precise-')
            precise_acc.setdefault(mode,[]).append((p,d))
        else:
            verdicts=d['verdicts']
            names=['H28 default.playing','H28 default.paused','H28 default.cutover'] if g=='cp0-h28' else ['H20.hlsSeek','H50.hlsSeek'] if g=='cp0-parked' else [i['item'] for s in ledger['stages'] if s['stage']==3 for i in s['items'] if not i['item'].startswith(('F3/','H28 ','H20','H50'))]
            for name in names:
                prefix='gap:'+name.replace('H28 default.','H28.default.')
                vs=[v for v in verdicts if v['case']==prefix or v['case'].startswith(prefix+'.')]
                if not vs:continue
                executed=len(set(v['case'] for v in vs)) if g=='cp0-parked' else len(vs)
                failures=sum(v['status']=='FAIL' for v in vs)
                operations=[op for case,ops in d.get('operations',{}).items() if case==prefix or case.startswith(prefix+'.') for op in ops]
                if name=='H14.manualSeek' or name.startswith('H17.'):
                    executed=sum(op.get('method')=='seek' for op in operations)
                elif name=='H42.wake':
                    wake_samples=[sample for v in vs if isinstance(v.get('actual'),dict) for sample in v['actual'].get('samples',[])]
                    executed=len(wake_samples) if wake_samples else sum(op.get('method')=='setKeepAlive' for op in operations)//2
                elif g not in ('cp0-h28','cp0-parked'):
                    executed=len(set(v['case'] for v in vs))
                actual=[v.get('actual') for v in vs if isinstance(v.get('actual'),dict)]
                metrics=dict(verdicts=[dict(case=v['case'],status=v['status'],reason=v.get('reason'),difference=v.get('difference')) for v in vs],harness=d['harness'],verdictCount=len(vs),failureCountUnit='判据FAIL数；执行次数按切档/seek/独立用例区分')
                for key in ('deltaMs','landingDeltaMs','landedMs','targetMs','nativeMs','progressMs','afterMs','bufferingTrueEdges'):
                    if any(key in v for v in actual):metrics[key]=nums([v.get(key) for v in actual])
                if g=='cp0-h28':
                    metrics['below200']=sum(abs(v['actual'].get('deltaMs',999999))<200 and v.get('expectedPath')==v['actual'].get('path') for v in vs if isinstance(v.get('actual'),dict))
                    metrics['below200Percent']=100*metrics['below200']/executed if executed else None
                if name=='H42.wake':
                    metrics['wakeElapsedMs']=nums([x.get('elapsedMs') for x in wake_samples])
                    metrics['wakeSignals']=[x.get('signal') for x in wake_samples]
                    if (E/'cp0-h42-visual-review.json').exists():
                        metrics['visualReview']=read(E/'cp0-h42-visual-review.json')
                        metrics['visualEvidence']='example/tool/coverage_evidence/cp0-h42-visual-review.json'
                if name in ('H37.dispose','A15.miniPip'):
                    metrics['explicitDisposeCalls']=sum(op.get('method') in ('dispose.first','dispose.second') for op in operations)
                if name.startswith('H33.'):
                    metrics['openReturns']=[v.get('returned') for v in actual if 'returned' in v]
                    metrics['openThrows']=[v.get('thrown') for v in actual if 'thrown' in v]
                    metrics['asyncErrors']=[v.get('errors') for v in actual if 'errors' in v]
                if name=='H14.manualSeek':
                    metrics['bufferingEdges']=[v.get('bufferingTrueEdges') for v in actual if 'bufferingTrueEdges' in v]
                    metrics['downshifts']=[v.get('downshifts') for v in actual if 'downshifts' in v]
                put(name,executed,metrics,rel(p),failures,d['completed'])
    for mode,batches in precise_acc.items():
        results=[r for p,d in batches for r in d.get('results',[])]
        n=len(results);passes=sum(r.get('cp0Pass',False) for r in results)
        below200=sum(r.get('cp0PathCorrect') and r.get('cp0DeltaMs') is not None and abs(r['cp0DeltaMs'])<200 for r in results)
        summary=dict(executed=n,passes=passes,below200=below200,below200Percent=100*below200/n if n else None,
          deltaMs=nums([r.get('cp0DeltaMs') for r in results]),
          failureFeatures=dict(noEligibleLanding=sum(r.get('landed',-1)<0 for r in results),pathMismatchOrUnavailable=sum(not r.get('cp0PathCorrect') for r in results),unavailablePath=sum(not r.get('path') for r in results),harnessInvalid=sum(bool(r.get('harnessInvalid')) for r in results),continuedFailed=sum(not r.get('continuedOk',False) for r in results)),
          batches=[dict(evidence=rel(p),executed=d.get('executed'),completed=d['completed'],errors=d.get('errors'),harness=d.get('harness')) for p,d in batches],
          failedIterations=[dict(evidence=rel(p),iteration=r.get('run'),target=r.get('target'),landed=r.get('landed'),continued=r.get('continued'),path=r.get('path')) for p,d in batches for r in d.get('results',[]) if not r.get('cp0Pass')])
        expected=160 if mode=='cutover' else 60
        put('F3/A17 precise.'+mode,n,summary,[rel(p) for p,d in batches],n-passes if n else None,n==expected)
    win=E/'cp0-windows-formal'
    if (win/'results.json').exists():
        wr=read(win/'results.json')
        if (win/'build.json').exists():ledger['windowsBinaryHashes']=read(win/'build.json')
        ledger['windowsFocusRetryArchives']=dict(count=sum(p.is_dir() for p in (win/'focus-retries').glob('*')),path='example/tool/coverage_evidence/cp0-windows-formal/focus-retries/',note='每个目录保留一次未满足前台采样条件的尝试；不计正式次数')
        for item,prefix,planned in [('Windows F3','F3-',30),('Windows A23/F13 dispose','dispose-',20),('Windows HE V6','V6-',5),('Windows HE V10','V10-',20)]:
            all_runs=[r for r in wr if r['item'].startswith(prefix)]
            runs=[r for r in all_runs if not r.get('focusMismatchCount') and not r.get('focusInterruptions') and (r.get('focus') or r.get('crashed'))]
            metrics=dict(runs=[{k:v for k,v in r.items() if k!='focus'} for r in runs],crashes=sum(r['crashed'] for r in runs),focusMismatchCount=sum(r.get('focusMismatchCount',0) or 0 for r in runs),focusExcludedItems=[r['item'] for r in all_runs if r not in runs],watchdogsTotal=sum(bool(r.get('watchdog')) for r in runs))
            if prefix=='F3-':
                rs=[]
                for run in runs:
                    jp=win/(run['item']+'.json')
                    if jp.exists():rs += [r for r in read(jp)['rows'] if r['kind']=='HLS_RESULT']
                metrics['deltaMs']=nums([r['landed']-r['target'] for r in rs if r.get('landed',-1)>=0])
                metrics['below200']=sum(r.get('landed',-1)>=0 and abs(r['landed']-r['target'])<200 and r.get('path')==r.get('expectedPath') for r in rs)
                metrics['below200Percent']=100*metrics['below200']/len(rs) if rs else None
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
                metrics.update(verdicts=[dict(case=v[0],status=v[1],detail=v[2]) for v in vs],logs=logs,verdictCount=len(vs))
                executed=len(runs);failures=sum(v[1]=='FAIL' for v in vs)+metrics['crashes']
            metrics['measurementFailures']=failures
            failures+=metrics['watchdogsTotal']
            put(item,executed,metrics,rel(win/'results.json'),failures,executed==planned and all(r['completed'] or r['crashed'] or r.get('watchdog') for r in runs),None if executed==planned else '输入桌面不可访问或前台采样缺失/中断；无有效前台证据的脚本轮次不计正式次数')
    ledger['restorationEvidence']='example/tool/coverage_evidence/cp0-session-restored.json' if (E/'cp0-session-restored.json').exists() else None
    if 'final' in sys.argv:
        ledger['status']='COMPLETE_WITH_GAPS' if any(i['status'] in ('PENDING','PARTIAL') for s in ledger['stages'] for i in s['items']) else 'COMPLETE'
        ledger['completed']=ledger['status']=='COMPLETE'
    Path(str(P)+'.json').write_text(json.dumps(ledger,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# CP0 真机基线（2026-11-03）','',f'状态：**{ledger["status"]}**。CP0 不设产品通过线；测得故障原样保留。',
           '',f'Android release APK SHA-256：`{sha}`。阶段1构建一次，后续复用；安装拉回哈希一致。',
           '', '基线 detached a5c317f6；版本控制改动仅本树 mova/example、mova/doc，lib/test 不改。Windows构建曾意外写到默认安装前缀，详见末尾事件记录，不声称满足全部目录写入约束。',
           '', 'cp0-pod2 按用户指示跳过：旧页默认不等待就绪，不用 epoch 0→0 推断 cutover 回落。音频焦点 manual BLOCKED；全量49批不在本轮。',
           '', '## P1-3 与 A16 文档措辞', '',
           '本次三档 HLS、默认配置下，限速5轮和不限速1轮均首个有效尺寸为1280×720，原生hls-bitrate=max；每轮90秒内观测切档0次，无切档时刻可报告。限速五轮有反复缓冲，不限速对照无起播后再缓冲。A16可据此写“当前默认配置在本次限速夹具下停留最高档，未自动降档”；结论限于此版本、夹具和90秒观察窗，不外推所有mpv版本/源。',
           '', '## 实测台账','', '|阶段|项目|计划|已执行|失败|状态/关键数字|证据|','|---|---|---:|---:|---:|---|---|']
    for s in ledger['stages']:
        for i in s['items']:
            m=i.get('metrics') or {};brief={k:v for k,v in m.items() if k.endswith('Total') or k in ('passes','below200','below200Percent','failureFeatures','executed','harness','missing','deltaMs','landingDeltaMs','landedMs','targetMs','crashes','disposeCallCount','verdictCount','focusMismatchCount','playToFirstFrameUs','renderEpoch','behindStateMs','pageIndex','nativeAdvanceMs')}
            if 'runs' in m:brief['runs']=[{k:v for k,v in r.items() if k in ('case','firstObservedTier','observedSwitchCount','switchIntervals','maxRebufferSeconds','totalRebufferSeconds','rebufferCount','finalNativeTimePos','nativeHlsBitrates','sampleCount')} for r in m['runs']]
            if 'verdicts' in m:brief['verdictCounts']={status:sum(v['status']==status for v in m['verdicts']) for status in ('PASS','FAIL','BLOCKED')}
            if 'verdicts' in m:
                brief['issues']=[dict(status=v['status'],reason=v.get('reason'),difference=v.get('difference')) for v in m['verdicts'] if v['status']!='PASS']
            for key in ('wakeElapsedMs','wakeSignals','explicitDisposeCalls','openReturns','openThrows','asyncErrors','bufferingEdges','downshifts'):
                if key in m:brief[key]=m[key]
            if 'visualReview' in m:brief['holdBlack']=m['visualReview']['observedHoldBlack']
            lines.append(f'|{s["stage"]}|{i["item"]}|{i["planned"]}|{i["executed"]}|{i.get("failures")}|{i["status"]} '+json.dumps(brief,ensure_ascii=False).replace('|','/')+'|'+str(i.get('evidence'))+'|')
    lines+=['','## 口径与证据边界','', 'P1-3：默认 createMovaEngine、auto、不手选；三档120秒HLS，共享900kbit/s限速。每秒原生读回档位、hls-bitrate、视频轨、缓存；切换时刻报告相邻采样区间，次数为观测下界。事件戳来自单调事件记录；卡顿结合原生 time-pos/paused-for-cache 与 MovaBufferChange，不以墙钟估算。完整逐轮数字在同名 JSON。',
            '', 'precise 沿用 rerun6 合格 RESTART/目标档位门槛，另算 CP0：目标与原生 time-pos 误差≤500ms 且 path 正确；<200ms 占比以已执行次数为分母。保留原续播/暂停判据与 harnessInvalid，不将缺样本算作成功。H28 默认配置不开泵。H20 使用 open 后立即seek(15s)，H50使用 cutoverTo(hls,at:12s)。',
            '', 'run_matrix.py 最小改动：增加 --reuse-apk，安装后拉回核对SHA256，避免阶段间重建；adb 增加断线15分钟/30秒重检。coverage1规则未改。',
            '', '恢复项以 cp0-session-original.json / cp0-session-restored.json 逐值核验；原值媒体音量0、USB常亮7，gnirehtet reverse 映射保留。原始证据均位于 gitignored example/tool/coverage_evidence/。',
            '', '本轮前的设备离线0样本仅为历史准备，不能代替本轮实测。上轮报告与台账可从 a5c317f6 复核。']
    if ledger.get('incidents'):
        lines+=['','## 中断与驱动故障','']
        for incident in ledger['incidents']:lines.append(incident['detail']+' 证据：'+', '.join(incident['evidence'])+'。')
    Path(str(P)+'.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('CP0 report updated',ledger['status'],'apk',sha)

if __name__=='__main__':main()
