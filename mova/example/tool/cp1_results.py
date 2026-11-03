"""Render CP1 checkpoint ledger only from this session's original evidence."""
import json
import shutil
import argparse
from datetime import datetime
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
E = ROOT/'example/tool/coverage_evidence'
TARGET = ROOT/'doc/plans/2026-11-03-cp1-results'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def frame_summary(rows):
    result={}
    for key in ('buildUs','rasterUs','totalUs'):
        values=sorted(r[key] for r in rows if isinstance(r.get(key),(int,float)))
        if values:
            result[key]=dict(count=len(values),p50=values[int((len(values)-1)*.5)],
                p95=values[int((len(values)-1)*.95)],p99=values[int((len(values)-1)*.99)],maximum=values[-1])
    return result


def result_text(scene,variant,samples):
    numbers=[r.get('numbers',{}) for p,i,r in samples]
    if not numbers:return '无正式CHECK；见阻塞/宿主证据'
    if scene=='dispose120':
        gaps=[n['maxFrameIntervalUs'] for n in numbers if isinstance(n.get('maxFrameIntervalUs'),int)]
        return f"最大dispose区间帧间隔={max(gaps) if gaps else None}us；最大dispose={max(n.get('disposeUs',0) for n in numbers)}us"
    if scene=='manageauto':return '降档次数='+str([n.get('downShiftCount') for n in numbers])
    if scene=='probe':return '探测总数='+str([n.get('probeTotal') for n in numbers])+'；列表长度='+str([len(n.get('qualities',[])) for n in numbers])
    if scene=='pool' and variant=='feed':
        return '观测缓存上界='+str([max([n.get('maxCache',0)]+[s.get('cacheCount',0) for s in n.get('samples',[])]) for n in numbers])+'；PSS斜率KB/100条='+str([round(n['pssSlopeKbPer100Items'],2) if n.get('pssSlopeKbPer100Items') is not None else None for n in numbers])
    if scene=='danmaku':return json.dumps(frame_summary([f for n in numbers for f in n.get('frameTimings',[])]),ensure_ascii=False)
    if scene=='errclass' and variant=='fatal':
        return '独立END_FILE='+str(sum(bool(n.get('endFile')) for n in numbers))+'/'+str(len(numbers))+'；UI终结无转圈='+str(sum(n.get('overlay') is True and n.get('spinnerCount')==0 and not n.get('state',{}).get('buffering') for n in numbers))+'/'+str(len(numbers))
    if scene=='errclass' and variant=='poster':return '首帧信号='+str([n.get('frames',[{}])[0].get('signal') if n.get('frames') else None for n in numbers])
    if scene=='recovery':return '续播误差ms='+str([n.get('resumePositionDiffMs') for n in numbers])
    if scene=='bblock' and variant=='preview':return 'dispose耗时us='+str([n.get('disposeUs') for n in numbers])
    if scene=='bblock' and variant=='restore':return 'settings brightness前后='+str([(n.get('before',{}).get('brightness'),n.get('after',{}).get('brightness')) for n in numbers])
    if scene=='keepalive-s7s14':return '原生VERDICT='+str([n.get('nativeVerdicts') for n in numbers])+'；完整视觉判据未关闭'
    return 'CHECK结果及原生读回见JSON measurements与原始records'


CONFIG = {
    'wakeswap': [('swap',10,'新 URI MovaFirstFrame 10/10，原生 path 正确','CP0 无此交错基线')],
    'edgepause': [('pause',10,'网络重开窗口中 pause 后保持暂停','CP0 无此交错基线'),('fallback',10,'fallback 回边缘不补播','CP0 无此交错基线')],
    'errclass': [('nonfatal',5,'真实非终结 error 日志不遮罩且播放推进','CP0 无独立定量基线'),('fatal',5,'404 END_FILE(error) 终结，遮罩显示，转圈消失','CP0 无独立定量基线'),('poster',5,'首帧 restart，撤封面不早于首帧','CP0 无独立定量基线')],
    'probe': [(v,n,c,'CP0 无独立定量基线') for v,n,c in [('list',10,'列表非空'),('manual',10,'手选 720p 保持，原生地址正确'),('once',10,'每会话探测一次'),('failover',5,'换备用源重新探测且每地址一次'),('disabled',5,'关闭探测时请求为零')]],
    'manageauto': [(v,5,c,b) for v,c,b in [('managed','真实降档且降档后可手选 720p','CP0 限速五次均停最高档、不降档'),('default','默认关闭无降档','CP0 默认限速五次均不降档；夹具/观察窗不同'),('disabled','ABR 关闭无降档','CP0 无该对照'),('lease','手选档缓冲 true→false，租约不降档','CP0 无独立定量基线')]],
    'bblock': [('restore',5,'亮度播种/还原、竖屏、系统栏原生对账','CP0 无独立定量基线'),('preview',5,'404 挂起 body 时 dispose≤5s 且 NativePlayer 释放','CP0 无独立定量基线')],
    'pool': [('reject',5,'拒绝后隐藏旧素材、重试地址正确','CP0 无独立定量基线'),('throw',5,'抛错后隐藏旧素材、重试地址正确','CP0 无独立定量基线'),('feed',3,'每轮 1000 条，缓存≤7，十点 PSS 不单调上升','CP0 无独立定量基线')],
    'danmaku': [('jump',5,'5000 条弹幕四次跳转，保留帧耗时分布，不设硬线','CP0 无 5000 条定量基线')],
    'recovery': [('resume',10,'真实 stallTimeout 重试，续播误差≤500ms 且地址正确','CP0 无此定量基线'),('manual720',10,'重试保持 720p，续播误差≤500ms 且地址正确','CP0 无此定量基线')],
    'dispose120': [('round',120,'逐轮首帧/dispose 完成，dispose 帧间隔<100ms','CP0 无 120 轮联合基线')],
    'keepalive-s7s14': [('S7',5,'20 次 vid 循环，mediacodec-copy，黑屏/运动复核','CP0 无完整像素/时序复核基线'),('S14',5,'vid=no 窗口及恢复画面复核','CP0 无完整像素/时序复核基线')],
}


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--stage',choices=['0','1','2','3','4'])
    parser.add_argument('--state',default='COMPLETE')
    parser.add_argument('--final',action='store_true')
    args=parser.parse_args()
    # Per-batch 135-ID reports are raw tool output, not CP1 product verdicts.
    # Keep them with the run evidence; the checkpoint report is the tracked table.
    for generated in (ROOT/'doc/plans').glob('2026-11-03-matrix-run-cp1-*'):
        if generated.is_file() and generated.suffix in ('.json','.md'):
            shutil.move(str(generated),str(E/generated.name))
    prior = read(Path(str(TARGET)+'.json')) if Path(str(TARGET)+'.json').exists() else {}
    stage0 = read(E/'cp1-stage0.json') if (E/'cp1-stage0.json').exists() else {}
    data = dict(status=prior.get('status','RUNNING'), sourceHead='047b179c59676033b1392e5e7ccc8f8a39401b10',
        device='7NQBB23606003715 / STG-AL00 / Android 12 arm64 release', stage0=stage0,
        stages=prior.get('stages',{}), rows=[], failures=[], defects=prior.get('defects',[]),
        incidents=prior.get('incidents',[]),
        visualReview=prior.get('visualReview',[]),
        audit=prior.get('audit',{}),
        restoration=prior.get('restoration',{}), validations=prior.get('validations',[]))
    for scene, variants in CONFIG.items():
        files = sorted(E.glob('matrix-cp1-*/matrix-*-cp1-'+scene+'.json'))
        sources = [(p,read(p)) for p in files]
        for variant,planned,criterion,baseline in variants:
            prefix = 'CP1.'+scene+'.'+variant+'.'
            samples = [(p,i,r) for p,d in sources for i,r in enumerate(d.get('records',[]))
                if r.get('kind')=='CHECK' and r.get('id','').startswith(prefix)]
            counts = Counter(r.get('status','BLOCKED') for _,_,r in samples)
            status = 'FAIL' if counts['FAIL'] else 'PASS' if len(samples)==planned and counts['PASS']==planned else 'BLOCKED'
            summaries=[(p,i,r) for p,d in sources for i,r in enumerate(d.get('records',[]))
                if scene=='dispose120' and r.get('id')=='CP1.dispose120.summary.0']
            if scene=='dispose120':
                if any(r.get('status')=='FAIL' for p,i,r in summaries): status='FAIL'
                elif len(summaries)!=1 or summaries[0][2].get('status')!='PASS': status='BLOCKED'
            # The old page only passes collection. No approved bound/CP0 frame
            # distribution exists for the user's "no spike" performance claim.
            if scene=='danmaku' and status=='PASS':status='BLOCKED'
            issues = [dict(evidence=rel(p),recordIndex=i,id=r['id'],status=r.get('status'),
                reason=r.get('missing'),numbers=r.get('numbers')) for p,i,r in samples if r.get('status')!='PASS']
            issues.extend(dict(evidence=rel(p),recordIndex=i,id=r['id'],status=r.get('status'),
                reason=r.get('missing'),numbers={k:v for k,v in r.get('numbers',{}).items() if k!='rounds'})
                for p,i,r in summaries if r.get('status')!='PASS')
            row = dict(id=scene+'.'+variant,stage=1,planned=planned,executed=len(samples),
                counts=dict(counts),status=status,criterion=criterion,cp0=baseline,
                result=result_text(scene,variant,samples),
                collectionStatus='PASS' if scene=='danmaku' and len(samples)==planned and counts['PASS']==planned else None,
                adjudication='原始采样CHECK为5/5 PASS；853帧totalSpan最大159062us，缺CP0同口径分布/批准的尖峰判据，不宣称无尖峰' if scene=='danmaku' else None,
                difference='待本轮证据' if not samples else '本次开启5/5真实降档，CP0默认关不降档；参数不同，不作性能倍数比较' if scene=='manageauto' and variant=='managed' else '默认关闭均无降档，与CP0同方向；夹具/时长不同' if scene=='manageauto' and variant=='default' else 'CP0无同口径独立基线，不推断改善',
                evidence=[rel(p) for p,_ in sources],issues=issues,
                summary=[dict(evidence=rel(p),recordIndex=i,status=r.get('status'),
                    values={k:v for k,v in r.get('numbers',{}).items() if k!='rounds'}) for p,i,r in summaries],
                measurements=[dict(evidence=rel(p),recordIndex=i,id=r['id'],
                    frameDistribution=frame_summary(r.get('numbers',{}).get('frameTimings',[])),
                    pssSamples=r.get('numbers',{}).get('samples') if scene=='pool' and variant=='feed' else None,
                    values={k:v for k,v in r.get('numbers',{}).items() if k in (
                        'deltaUs','holdingPhase','renderEpoch','pendingAtPause','phase','opacity',
                        'probeCounts','probeTotal','sourceIndex','currentQuality','downShiftCount',
                        'autoTierAfter','manualAfter','beforeBuffering','quality','disposeUs',
                        'disposeCompleted','nativeReleased','hiddenOnReject','threw','ready',
                        'items','maxCache','cacheBound','pssSlopeKbPer100Items','strictlyIncreasing',
                        'frameCount','resumePositionDiffMs','retryCount','round','maxFrameIntervalUs',
                        'disposed','hwdec','nativeVerdicts','visualReview')}) for p,i,r in samples],
                harness=[dict(evidence=rel(p),errors=d.get('harness'),missing=d.get('missing')) for p,d in sources if d.get('harness') or d.get('missing')])
            blockReasons={
                'wakeswap':'新源响应被拦超过6s，但原生约5s先HTTP超时；未获7a有效CHECK，未补跑',
                'edgepause':'pause前5次通过，第6次根相对HLS分片地址协议错误、native读回缺失；余下pause/fallback未执行',
                'probe':'前三组各10次通过；首个failover无切源并自然Done，90s超时，剩余failover/disabled未执行',
                'recovery':'首个resume的segmentEntered始终false，预缓冲已读63请求；未建立卡死前提，后续未执行',
                'bblock':'OEM亮度/应用覆盖/display/InsetsSource字段未完整解析；已记录系统brightness漂移，未凭缺字段判通过',
                'danmaku':'5次采样CHECK完整，但totalSpan尾值159.062ms；无CP0同口径分布/批准硬线，性能结论未关闭',
                'keepalive-s7s14':'原生场景均通过；单张恢复截图缺运动证据，S14有跨场景采图滞后，CP0 Android完整视觉基线缺失',
            }
            if status=='BLOCKED':row['difference']=blockReasons.get(scene,'未形成完整本轮判据；详见原始缺失清单')
            data['rows'].append(row)
            data['failures'].extend(dict(row=row['id'],**issue) for issue in issues if issue['status']=='FAIL')
    from cp1_reduce_extra import rows as extra_rows
    from cp1_reduce_supplement import rows as supplement_rows
    data['additionalRows']=extra_rows()+supplement_rows()+prior.get('supplementRows',[])
    data['supplementRows']=prior.get('supplementRows',[])
    data['rows'].extend(data['additionalRows'])
    data['failures'].extend(dict(row=r['id'],**issue) for r in data['additionalRows'] for issue in r.get('issues',[]) if issue.get('status')=='FAIL')
    for name in ['F3','dispose','HE V6','HE V10']:
        data['rows'].append(dict(id='Windows '+name,stage=4,planned=3,executed=0,status='BLOCKED',
            criterion='经 win_policy，次数 clamp_runs=3；不劣于 CP0，V10 零崩溃',
            cp0='本树 CP0 Windows 基线仍 PENDING',difference='待安静模式验证',
            evidence=['doc/plans/2026-11-03-win-quiet-mode.md（开工时不存在）']))
    data['counts']=dict(Counter(r['status'] for r in data['rows']))
    groups=[('F3/A17 precise 三组',['F3/A17 precise.normal','F3/A17 precise.paused','F3/A17 precise.cutover']),
        ('H28 默认三组',['H28.default.playing','H28.default.paused','H28.default.cutover']),
        ('H20/H50 HLS',['H20.hlsSeek','H50.hlsSeek']),
        ('P0-2 三种触发',['p02.contentWarm','p02.midPending','p02.postLoad']),
        ('keepAlive S1/S7/S13/S14',['keepalive-core.S1','keepalive-s7s14.S7','keepalive-core.S13','keepalive-s7s14.S14']),
        ('终审7a',['wakeswap.swap']),('终审7b / fallback',['edgepause.pause','edgepause.fallback']),
        ('H35 / 手选720p重试',['recovery.resume','recovery.manual720']),
        ('错误分级',['errclass.nonfatal','errclass.fatal']),('A14 poster',['errclass.poster']),
        ('A12/N6 探测',['probe.list','probe.manual','probe.once','probe.failover','probe.disabled']),
        ('A16 / A11',['manageauto.managed','manageauto.default','manageauto.disabled','manageauto.lease']),
        ('B11/B12 池与feed',['pool.reject','pool.throw','pool.feed']),('A23/F13 dispose120',['dispose120.round']),
        ('B块亮度/全屏/预览/抽帧/底栏/弹幕',['bblock.restore','bblock.preview','B.extract','B.bottomPatch','danmaku.jump']),
        ('Windows',['Windows F3','Windows dispose','Windows HE V6','Windows HE V10'])]
    byid={r['id']:r for r in data['rows']}
    data['masterRows']=[]
    for title,ids in groups:
        members=[byid.get(i,dict(id=i,status='BLOCKED',planned=5,executed=0)) for i in ids]
        status='FAIL' if any(r['status']=='FAIL' for r in members) else 'PASS' if all(r['status']=='PASS' for r in members) else 'BLOCKED'
        data['masterRows'].append(dict(id=title,status=status,subrows=ids,
            planned=sum(r['planned'] for r in members),executed=sum(r['executed'] for r in members)))
    data['masterCounts']=dict(Counter(r['status'] for r in data['masterRows']))
    data['comparisonSummary']=[]
    for mode in ('normal','paused','cutover'):
        row=byid['F3/A17 precise.'+mode]
        data['comparisonSummary'].append(f"precise.{mode}：{row['executed']}/{row['planned']}；{row['difference']}")
    post=byid['p02.postLoad']
    pm=post.get('metrics',{})
    data['comparisonSummary'].append(f"P0-2 postLoad：CP0 0/10进入B、10/10停广告尾帧；CP1 {pm.get('passes',0)}/{post['executed']}进入B，播错集={sum(pm.get('wrongEpisode',[]))}，仍停广告={sum(pm.get('stillAd',[]))}，观察超限={sum(pm.get('observationLimit',[]))}。")
    data['comparisonSummary'].append('manageAuto：'+byid['manageauto.managed']['result']+'；默认关闭 '+byid['manageauto.default']['result']+'。CP0默认关时限速仍停最高档；本次夹具/观察窗不同。')
    data['comparisonSummary'].append('dispose120：'+byid['dispose120.round']['result'])
    data['comparisonSummary'].append('404：'+byid['errclass.fatal']['result']+'；保留独立采样缺口导致的原始FAIL，未把UI终结成功改写成完整CHECK成功。')
    if args.stage:
        data['stages'][args.stage]=dict(status=args.state,recordedAt=datetime.now().astimezone().isoformat(),
            detail='本阶段已收口；失败与缺测保留，不代表全部产品判据通过')
    if args.final:data['status']='COMPLETE_WITH_FAILURES_AND_BLOCKERS' if any(r['status']!='PASS' for r in data['rows']) else 'PASS'
    Path(str(TARGET)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    displayStatus='已收口（存在FAIL与BLOCKED，CP1未通过）' if data['status']=='COMPLETE_WITH_FAILURES_AND_BLOCKERS' else data['status']
    lines=['# CP1 真机检查点结果','',f"状态：{displayStatus}。本人执行，未转派；lib/test 未改。",
        '',f"设备：{data['device']}。",'',
        'APK SHA-256：`'+stage0.get('metadata',{}).get('sha256',{}).get('signed','待构建')+'`。构建一次，后续复用，安装后拉回逐值核验。',
        '', '证据目录：`example/tool/coverage_evidence/`（gitignored）；记录下标为 JSON records 的零基下标。',
        '', '工具汇总显式使用已提交的S00e矩阵台账（默认gitignored旧台账在本树缺失）；CP1产品比较只使用CP0基线定量数字。每批135项工具输出中的未运行BLOCKED不混入本表。',
        '', '页面原始CHECK的deviceStatus="未上机"是构建前遗留静态标签；本报告以本轮adb命令、安装拉回哈希、原生读回及真实事件为执行证据，不以该标签或AUTORUN DONE判通过。',
        '', '次数按各页CHECK/用例或独立宿主尝试计；BLOCKED记录数不代表通过。抽帧3次均为未获THUMB的尝试，底栏0/3指未具备底栏专属刺激；辅助skin三轮另行保留。',
        '',f"总计划16行：{data['masterCounts']}；细分行：{data['counts']}。RUNNING 时未执行行不代表产品失败。",'',
        '## 与CP0的关键差异','',*[('- '+s) for s in data['comparisonSummary']],'',
        '|总计划CP1行|记录/计划|结论|','|---|---:|---|',
        *[f"|{r['id']}|{r['executed']}/{r['planned']}|{r['status']}|" for r in data['masterRows']],
        '',
        '|项目|计划/记录|结论|通过标准|CP0 基线及差异|原始证据|','|---|---:|---|---|---|---|']
    for r in data['rows']:
        ev='；'.join(r.get('evidence',[]))
        lines.append(f"|{r['id']}|{r['planned']}/{r['executed']}|{r['status']} {r.get('counts',{})}；{r.get('result','')}；{r.get('adjudication') or ''}|{r['criterion']}|{r['cp0']}；{r['difference']}|{ev}|")
    lines += ['', '## 失败特征与证据','']
    for f in data['failures']:
        lines.append(f"- {f['row']} / {f['id']}：{f.get('reason') or 'CHECK 产品判据不满足'}；`{f['evidence']}` {f.get('recordArray','records')}[{f['recordIndex']}]；完整数字见 JSON。")
    if not data['failures']: lines.append('当前尚无已记录的产品 FAIL；缺证据仍为 BLOCKED。')
    lines += ['', '## 静态画面复核','',json.dumps(data['visualReview'],ensure_ascii=False,indent=2),
        '', '## 阶段、检查与恢复','', '```json',json.dumps({k:data[k] for k in ['stages','validations','restoration','incidents','audit']},ensure_ascii=False,indent=2),'```', '', '## 需要修复的缺陷与覆盖阻塞','']
    for defect in data['defects']:
        lines += ['### '+defect['id']+'：'+defect.get('classification',''),'',
            '现象：'+defect.get('phenomenon',''),'','复现条件：'+defect.get('reproduction',''),'',
            '证据：`'+defect.get('evidence','')+'`；记录下标：'+str(defect.get('recordIndices',[]))+'。','',
            '疑似位置：'+'、'.join('`'+s+'`' for s in defect.get('suspectedLocations',[]))+'。','',
            '建议：'+defect.get('suggestion',''),'']
    lines += ['', 'Windows：开工时安静模式验证记录不存在，四组均待安静模式验证，没有启动 Windows 应用。','']
    Path(str(TARGET)+'.md').write_text('\n'.join(lines),encoding='utf-8')
    print(data['counts'])


if __name__=='__main__': main()
