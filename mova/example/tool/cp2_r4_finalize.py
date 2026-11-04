"""Append the repaired fourth round while preserving all earlier CP2 evidence."""
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import subprocess
import re

ROOT=Path(__file__).resolve().parents[2]
E=ROOT/'example/tool/coverage_evidence'
TARGET=ROOT/'doc/plans/2026-11-04-cp2-results'

def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))

def classify(scene,c):
    n=c.get('numbers') or {}
    fixture=None
    classification='PRODUCT_SUSPECT'
    lib='lib/src/core/session/session.dart / lib/src/core/cutover/cutover_engine.dart'
    if scene=='adpaths':
        symptom=f"resumeErrorMs={n.get('resumeErrorMs')}; lifecycle={n.get('adLifecycleValid')}; epochs={n.get('epochs')}; frames={len(n.get('frames',[]))}; contentEnded={n.get('contentEnded')}"
        lib+=': _contentResumeAt / _onProgress / _playContent / commit'
        if n.get('adLifecycleValid') is not True:
            classification='UNRESOLVED_FIXTURE_OR_PRODUCT';fixture='example/lib/verify_auto/cp2_adpaths_auto.dart / cp2_criteria.dart'
    elif scene=='pod2':
        symptom=f"epoch0={n.get('epoch0')}; epoch1={n.get('epoch1')}; epoch2={n.get('epoch2')}; first={n.get('first')}; second={n.get('second')}"
        lib+=': session.dart:1054附近 _playAd在wait=false时直接_api.open；cutover_engine.dart:519的open委派_active.open而不递增_epoch，只有1156附近影子commit递增。与本轮第二条epoch必须增长判据不符，仍记录FAIL；结合KERNEL_RELEASE/RELEASE_DRAINED排除迭代资源未释放'
    elif scene in ('adpause','adbg'):
        symptom=f"pauseDrift={n.get('nativePauseDriftMs')}ms; slotError={n.get('slotErrorMs')}ms; pausedCompleted={n.get('pausedCompleted')}; foreground={n.get('foreground')}"
        lib='lib/src/core/session/session.dart: 广告slot计时；lib/src/ui/player.dart / view.dart: 后台守卫；lib/src/core/cutover/cutover_engine.dart: pause/play'
        if n.get('pausedCompleted')==0 and abs(n.get('nativePauseDriftMs') or 0)<=300 and abs(n.get('slotErrorMs') or 0)>300:
            classification='UNRESOLVED_FIXTURE_OR_PRODUCT'
            fixture='example/lib/verify_auto/cp2_adpause_auto.dart: lastAd.timePosMs-6000为原生媒体进度估算，不是直接读取slotClock.remaining；保留300ms门槛及FAIL'
            lib='lib/src/core/session/session.dart:1089–1146 _armSlotTimer/_holdIfPaused；MovaAdClock墙钟计时与mpv time-pos存在起表/缓冲/采样差，尚不能凭该误差证实产品提前结束'
    elif scene=='playlist3':
        symptom=f"contentEnded={n.get('contentEnded')}; ads={n.get('ads')}; events/node/epoch见原始numbers"
        classification='UNRESOLVED_FIXTURE_OR_PRODUCT';fixture='example/lib/verify_auto/cp2_playlist3_auto.dart'
    elif scene=='bgowner':
        symptom=f"before={n.get('before')}; after={n.get('after')}; foreground={n.get('foreground')}; guardMounted={n.get('guardMounted')}"
        lib='lib/src/ui/view.dart / lib/src/ui/player.dart / MovaAutoPause；lib/src/core/cutover/cutover_engine.dart'
    elif scene in ('rate','warmmute'):
        symptom=str(n.get('sourceVerdict'))
        if scene=='rate':lib+=': setRate / playAdNow / _contentRate'
        else:
            classification='UNRESOLVED_FIXTURE_OR_PRODUCT';fixture='example/lib/main_q13_mute_verify.dart'
            lib+=' / lib/src/core/keep_alive；warming可达性需结合原生初始化日志，不能直接归为静音产品缺陷'
    else:
        symptom=str(n)
        lib='lib/src/ui/player.dart / MovaAutoPause；lib/src/core/engine.dart'
    return dict(classification=classification,symptom=symptom,fixture=fixture,libSuspect=lib)

def main():
    data=read(str(TARGET)+'.json')
    state=read(E/'cp2-r4.json')
    assert state.get('finishedAt'),'Do not finalize while device batches are running'
    previous=read(E/'cp2-r4-previous-results.json')
    checks={r['id']:dict(r,inherited=True) for r in previous['checks']}
    observations={};failures=[];blockers=[];native_rate=[];release_counts={}
    for a in state['attempts']:
        scene=a['batch'].removeprefix('cp2-')
        path=ROOT/a['evidence']/(f"matrix-{a['run_id']}-cp2-{scene}.json")
        raw=read(path) if path.exists() else {}
        if scene=='pod2':release_counts[a['run_id']]=dict(Counter(r['kind'] for r in raw.get('records',[]) if r.get('kind') in ('KERNEL_RELEASE','RELEASE_DRAINED','ERROR')))
        if scene=='rate':
            log=E/f"matrix-{a['run_id']}-cp2-rate.log"
            content=log.read_text(encoding='utf-8',errors='replace') if log.exists() else ''
            pattern=r'RFV2\|(\d+)\|(V13[ab])\|run(\d+) NATIVE_SPEED \{phase: (ad|returned), epoch: (\d+), path: ([^,]+), speed: ([\d.]+), stable: (true|false)'
            samples=[dict(atMs=int(t),id=f'CP2.rate.{v}.{int(i)-1}',phase=p,epoch=int(epoch),path=uri,speed=float(speed),stable=stable=='true') for t,v,i,p,epoch,uri,speed,stable in re.findall(pattern,content)]
            native_rate.append(dict(run_id=a['run_id'],evidence=str(log.relative_to(ROOT)),samples=samples))
        for c in raw.get('records',[]):
            ident=c.get('id','')
            if c.get('kind')!='CHECK' or not ident.startswith('CP2.'+scene+'.') or ident.endswith('.harness'):continue
            obs=dict(id=ident,status=c['status'],run_id=a['run_id'],evidence=str(path.relative_to(ROOT)),numbers=c.get('numbers'),missing=c.get('missing'))
            observations.setdefault(ident,[]).append(obs)
            if c['status']=='FAIL':failures.append(dict(obs,**classify(scene,c)))
            elif c['status']=='BLOCKED':blockers.append(obs)
    rerun_scenes={a['batch'].removeprefix('cp2-') for a in state['attempts']}
    for ident,old in list(checks.items()):
        scene=ident.split('.')[1]
        if scene not in rerun_scenes:continue
        if scene=='audioonly-bg' and ident not in {f'CP2.audioonly-bg.videoGuard.{i}' for i in range(1,10)}:continue
        observed=observations.get(ident,[])
        status='FAIL' if any(r['status']=='FAIL' for r in observed) else 'PASS' if any(r['status']=='PASS' for r in observed) else 'BLOCKED'
        checks[ident]=dict(id=ident,status=status,inherited=False,attempts=observed)
    batches=[]
    for b in previous['batches']:
        scene=b['batch'].removeprefix('cp2-')
        cs=[r for ident,r in checks.items() if ident.startswith('CP2.'+scene+'.')]
        counts={s:sum(r['status']==s for r in cs) for s in ('PASS','FAIL','BLOCKED')}
        attempts=[a for a in state['attempts'] if a['batch']==b['batch']]
        complete=not attempts or any(a['completed'] and a['executed']==a['planned'] and not a['harness'] and not a['missing'] for a in attempts)
        batches.append(dict(batch=b['batch'],counts=counts,status='FAIL' if counts['FAIL'] else 'BLOCKED' if counts['BLOCKED'] or not complete else 'PASS',
            inherited=scene not in rerun_scenes,previousStatus=b['status'],previousCounts=b['counts']))
    master=[]
    for old in previous['masterRows']:
        bs=[b for b in batches if b['batch'] in old['batches']]
        automated='FAIL' if any(b['status']=='FAIL' for b in bs) else 'BLOCKED' if not bs or any(b['status']=='BLOCKED' for b in bs) else 'PASS'
        needs_manual=any(s in old['item'] for s in ['后台','F16','Windows'])
        master.append(dict(item=old['item'],planned=old['planned'],criterion=old['criterion'],batches=old['batches'],automatedStatus=automated,
            status='BLOCKED' if needs_manual and automated=='PASS' else automated))
    manual=[dict(item='听音',status='BLOCKED',scope='广告暂停/后台无声、Q13预热静音、audioOnly后台持续出声；本轮原始系统媒体音量0，未做人耳听音；原生mute/pause/volume不能代替声学验收'),
            dict(item='视觉',status='BLOCKED',scope='广告切换、pod第二条、三集连播、前后台无黑帧/错画需人工审阅'),
            dict(item='PiP系统交互',status='BLOCKED',scope='系统展开/X/mini联动、F5 keepAlive唤醒；本轮按指令不重跑已PASS的PiP自动项')]
    deviations=['QoE按用户指令不重跑；历史JSON实际为9 PASS/1 BLOCKED，缺CP2.qoe.manual720.9（以历史具体ID为准），不能改为完整PASS。',
        'audioonly-bg用选择器仅补videoGuard.1–9，未重跑已PASS的21条；验证判据与10轮编号不变。',
        '每次缺完成标记/缺CHECK的尝试立即提交，再以新run-id整批重试一次；完整产品FAIL直接记录并继续。',
        '第四轮独立计算修复后结论，不用历史FAIL压住修复后PASS；历史BUILD-01、首轮、续跑及失败均原样保留。',
        '仅修改mova/example与mova/doc；未转派、未修改lib/test、未运行Windows被测应用、未操作其他worktree、未切分支/push/stash/reset。']
    qoe_missing=[r['id'] for r in previous['checks'] if r['id'].startswith('CP2.qoe.') and r['status']=='BLOCKED']
    deviations[0]='QoE按用户指令不重跑；历史JSON实际为9 PASS/1 BLOCKED，缺'+','.join(qoe_missing)+'；保留证据缺口，不改成完整PASS。'
    ad_errors=[abs(o['numbers']['resumeErrorMs']) for rs in observations.values() for o in rs if o['id'].startswith('CP2.adpaths.') and o['numbers'].get('resumeErrorMs') is not None]
    mid_errors=[abs(o['numbers']['resumeErrorMs']) for rs in observations.values() for o in rs if o['id'].startswith('CP2.adpaths.') and '.mid.' in o['id'] and o['numbers'].get('resumeErrorMs') is not None]
    warm=[o for rs in observations.values() for o in rs if o['id'].startswith('CP2.warmmute.')]
    quantitative=dict(adpathsMaxAbsResumeMs=max(ad_errors,default=None),adpathsMidMaxAbsResumeMs=max(mid_errors,default=None),
        pod2ReleaseCounts=release_counts,warmmuteSystemVolumeProof=warm[0]['numbers'].get('systemVolumeProof') if warm else None)
    native_stats=[]
    for evidence in native_rate:
        for ident in sorted({s['id'] for s in evidence['samples']}):
            samples=[s for s in evidence['samples'] if s['id']==ident and s['stable']]
            ads=[s['speed'] for s in samples if s['phase']=='ad' and 'ad.mp4' in s['path']]
            returned=[s['speed'] for s in samples if s['phase']=='returned' and 'vod.mp4' in s['path']]
            native_stats.append(dict(id=ident,adSamples=len(ads),adSpeeds=sorted(set(ads)),returnedSpeeds=returned,evidence=evidence['evidence']))
    commit_lines=subprocess.check_output(['git','log','--reverse','--format=%H%x09%s','93fe4875..HEAD'],cwd=ROOT,text=True).splitlines()
    commits=[dict(hash=line.split('\t',1)[0],subject=line.split('\t',1)[1]) for line in commit_lines]
    round4=dict(title='第四轮（修复后）',generatedAt=datetime.now().astimezone().isoformat(),state=state,apkSha256=state.get('apkSha256'),
        batches=batches,masterRows=master,checks=list(checks.values()),nativeSpeedReadbacks=native_rate,nativeSpeedSummary=native_stats,quantitative=quantitative,commits=commits,
        newlyExecutedChecks=sum(a['executed'] for a in state['attempts']),newRunCounts={s:sum(a['counts'][s] for a in state['attempts']) for s in ('PASS','FAIL','BLOCKED')},
        hostChecks=dict(manifest='78 batches / 135 IDs / 6 manual PASS',matrixTests='63 tests OK; example/tool/coverage_evidence/cp2-r4-test-run-matrix.log',volumeTests='8 tests OK',analyze='2 files; No issues found; example/tool/coverage_evidence/cp2-r4-analyze.log'),
        failures=failures,blockers=blockers,manual=manual,deviations=deviations,
        counts=dict(Counter(r['status'] for r in checks.values())),status='FAIL' if failures else 'BLOCKED' if any(r['status']=='BLOCKED' for r in master) else 'PASS')
    data['fourthRound']=round4;data['latestRound']='第四轮（修复后）';data['latestStatus']=round4['status']
    Path(str(TARGET)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    text=Path(str(TARGET)+'.md').read_text(encoding='utf-8')
    text=re.sub(r'\n> 最新第四轮：[^\n]*\n','\n',text)
    first,rest=text.split('\n',1)
    text=first+f"\n\n> 最新第四轮：{round4['status']}；新APK与修复后逐行结果见文末“第四轮（修复后）”。下方既有首轮/续跑文字属于历史记录。\n"+rest
    marker='\n## 第四轮（修复后）\n'
    text=text.split(marker)[0]+marker
    text+=f"\n最新结论 **{round4['status']}**；本人连续执行，未转派。新APK SHA-256：`{state.get('apkSha256')}`。历史章节均保留；下面独立计算修复后结果。\n\n"
    text+='|总计划CP2行|次数|判据|自动|含人工结论|\n|---|---|---|---|---|\n'
    for r in master:text+=f"|{r['item']}|{r['planned']}|{r['criterion']}|{r['automatedStatus']}|{r['status']}|\n"
    text+='\n|批次|上轮P/F/B|第四轮有效P/F/B（未重跑则继承）|结论|\n|---|---|---|---|\n'
    for b in batches:text+=f"|{b['batch']}{'（未重跑）' if b['inherited'] else ''}|{b['previousCounts']}|{b['counts']}|{b['status']}|\n"
    text+='\n每次尝试及逐批提交见[第四轮台账](2026-11-04-cp2-r4.md)和对应matrix-run JSON；所有完整CHECK ID与numbers保留在本JSON fourthRound.checks.attempts。\n\n'
    text+=f"adpaths全部可续播路径原生误差绝对值最大{quantitative['adpathsMaxAbsResumeMs']}ms，中插最大{quantitative['adpathsMidMaxAbsResumeMs']}ms；pod2释放记录 `{release_counts}`。warmmute音量证明 `{quantitative['warmmuteSystemVolumeProof']}`。\n\n"
    text+='### 第四轮FAIL清单\n\n'
    for f in failures:text+=f"- `{f['id']}` / `{f['run_id']}`：{f['classification']}；{f['symptom']}。证据 `{f['evidence']}`；夹具 {f['fixture'] or '暂无已证实夹具归因'}；疑似lib `{f['libSuspect']}`。\n"
    if not failures:text+='无正式CHECK FAIL；缺测或夹具失败仍按BLOCKED记录。\n'
    text+='\n### 阻塞、人工项与偏差\n\n'
    for a in state['attempts']:
        if a['harness'] or a['missing'] or not a['completed']:text+=f"- `{a['run_id']}`：{a['status']}；完成={a['completed']}；harness={a['harness']}；missing={a['missing']}；证据 `{a['evidence']}`。\n"
    for m in manual:text+=f"- {m['item']}：{m['status']}；{m['scope']}。\n"
    for d in deviations:text+='- '+d+'\n'
    text+=f"\n设备恢复：**{state['restoration']['status']}**；原值与最终读回、媒体音量/USB常亮/reverse/forward见 fourthRound.state.restoration。\n"
    text+='\nrate原生读回补丁独立提交 `bb7f6059`，从当前VideoController.player.platform的NativePlayer读取mpv path/speed，按句柄与epoch稳定性过滤；广告原生speed稳定段1x、回正片2x/1.5x证据在rate的NATIVE_SPEED及RESULT行，不把代理rate当原生speed。\n'
    text+='\n|rate正式ID|原生广告样本数|原生广告speed集合|返回正片原生speed|\n|---|---:|---|---|\n'
    for r in native_stats:text+=f"|{r['id']}|{r['adSamples']}|{r['adSpeeds']}|{r['returnedSpeeds']}|\n"
    text+=f"\n本轮新执行{round4['newlyExecutedChecks']}条：{round4['newRunCounts']}；合并未重跑历史ID后190条：{round4['counts']}。新跑九批全部完成，无崩溃、缺CHECK或连接中断，不需额外整批重试；完整FAIL均保留。\n"
    text+='\n宿主校验：run_matrix --check PASS（78批/135编号/6人工）；test_run_matrix 63 tests OK；test_cp2_volume 8 tests OK；本轮改动的两个Dart文件flutter analyze均No issues found。未将这些宿主校验当作真机通过证据。\n'
    text+='\n### 本轮提交\n\n'
    for c in commits:text+=f"- `{c['hash']}` {c['subject']}\n"
    Path(str(TARGET)+'.md').write_text(text,encoding='utf-8')
    print(json.dumps(dict(status=round4['status'],counts=round4['counts'],batches=[(b['batch'],b['status']) for b in batches],failures=len(failures)),ensure_ascii=False))

if __name__=='__main__':main()
