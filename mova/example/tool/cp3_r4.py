"""One authorized R4 headers batch, blocking execution and immediate commit."""
from datetime import datetime
from collections import Counter
import hashlib,json,os,shutil,subprocess,sys
import cp3_r2 as prev
from coverage_device import unlocked
ROOT,TOOL,SUMMARY=prev.ROOT,prev.TOOL,prev.SUMMARY
OUT=TOOL/'coverage_evidence'/('cp3-r4-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
PATHS=['example/tool/cp3_r4.py','example/tool/coverage_build.py','example/lib/verify_auto/cp3_pages_auto.dart','doc/plans/2026-11-05-cp3-results.md','doc/plans/2026-11-05-cp3-results.json']
def save(s):
    data=json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'));data['fourthRoundRevalidation']=s
    SUMMARY.with_suffix('.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    old=SUMMARY.with_suffix('.md').read_text(encoding='utf-8').split('\n## 第四轮复验')[0]
    lines=['','## 第四轮复验','',f"起点 `{s['head']}`；STG-AL00 / {prev.SERIAL}；APK SHA-256 `{s.get('apkSha256','构建中')}`。",f"run-id `{s['runId']}`；完成={s.get('complete',False)}；仅 headers 抽帧/池预热正负对照批次，无其他批次/Windows 验证。",'', '抽帧与池暂停截图：','', '```json',json.dumps({k:({a:b for a,b in v.items() if a not in ('samples','firstSuccess','elapsedMs')} if isinstance(v,dict) else v) for k,v in s.get('analysis',{}).items()},ensure_ascii=False,indent=2),'```','',f"结论：{s.get('conclusion','执行中')}。",'', '仍未解决：','', '- 隐藏抽帧播放器没有公开 seek 重试回执，精确重试命中次数未知；耗时阈值仅列候选，不能证明重试。','- 若池在 first-frame future 就绪后仍返回 null，暂停预热/原生截图仍待定；未通过 play/seek 改变测试条件。','- 前三轮其他未解决项保留，本轮未复跑。','', '偏差：','']+['- '+x for x in s['deviations']]
    lines+=['', '批次结果：`'+json.dumps(s.get('row',{}),ensure_ascii=False)+'`。','', '恢复读回：`'+json.dumps(s.get('restoration',{}),ensure_ascii=False)+'`。','', '提交（当前提交自身 hash 见最终汇报）：'+', '.join(s['commits'])+'。']
    SUMMARY.with_suffix('.md').write_text(old+'\n'.join(lines)+'\n',encoding='utf-8')
    (OUT/'state.json').write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def commit(s,label):
    save(s);prev.call(['git','add','--',*PATHS],check=True);prev.call(['git','diff','--cached','--check'],check=True)
    prev.call(['git','-c','maintenance.auto=false','-c','gc.auto=0','commit','-m','test(mova): CP3 fourth round '+label+prev.SUFFIX],check=True)
    s['commits'].append(subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip());print('R4 COMMIT',s['commits'][-1],flush=True)
def analyze(folder):
    p=folder/(folder.name+'-cp3-headers.json');data=json.loads(p.read_text(encoding='utf-8'))
    samples={'extract':[],'pool':[]}
    for r in data['records']:
        if r.get('kind')=='CHECK' and '.quality.' in r.get('id',''):
            for kind in samples:samples[kind]+=r['numbers']['nativePaths'][kind]['samples']
    e=[r['observations']['authorized'] for r in samples['extract']];p=[r['observations']['authorized'] for r in samples['pool']]
    phases={}
    for row in p:
        for shot in row.get('shots',[]):
            v=phases.setdefault(shot['phase'],dict(total=0,null=0,success=0,atMs=[],gateReady=0));v['total']+=1;v['null']+=shot['null'];v['success']+=bool(shot.get('bytes'));v['atMs'].append(shot['atMs']);v.setdefault('sinceBindReturnMs',[]).append(shot['atMs']-row['bindReturnedMs']);v['gateReady']+=shot.get('gateReady',False)
    for v in phases.values():v['atMsRange']=[min(v['atMs']),max(v['atMs'])];v['sinceBindReturnMsRange']=[min(v['sinceBindReturnMs']),max(v['sinceBindReturnMs'])];del v['atMs'];del v['sinceBindReturnMs']
    return dict(extract=dict(total=len(e),success=sum(x.get('outcome')=='frame' for x in e),null=sum(x.get('outcome')=='null' for x in e),errors=[x for x in e if 'error' in x],retryHits=None,retryReason='API has no public internal seek retry receipt',slowOver5s=[x for x in e if x.get('elapsedMs',0)>=5000],previous=dict(success=28,total=30,null=2),negativeRejected=sum(not x['negative'] for x in samples['extract']),elapsedMs=[x.get('elapsedMs') for x in e]),pool=dict(total=len(p),originalNull=sum(x.get('imageBytes') is None for x in p),phases=phases,negativeRejected=sum(not x['negative'] for x in samples['pool']),firstSuccess=[next((shot for shot in x.get('shots',[]) if shot.get('bytes')),None) for x in p],samples=p))
def main():
    os.environ.update(MOVA_CP3_CAMPAIGN='1',MOVA_CP3_HEADERS_R4='1',MOVA_MATRIX_SERIAL=prev.SERIAL,ANDROID_SERIAL=prev.SERIAL,ANDROID_SDK_ROOT='E:/sdk/android',ANDROID_HOME='E:/sdk/android',PYTHONDONTWRITEBYTECODE='1')
    OUT.mkdir(parents=True);(ROOT/'example/.dart_tool/b09').mkdir(parents=True,exist_ok=True)
    s=dict(started=datetime.now().astimezone().isoformat(),head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),runId='cp3-headers-r4-'+datetime.now().strftime('%Y%m%d-%H%M%S'),commits=[],deviations=['用户所述 d954901b 在本树对应 cherry-pick 6f57ca5c；起点 HEAD c20f4911。','保留原15 CHECK；每quality条目扩展12组抽帧/6组池正负对照，总60/30；不在夹具重试抽帧。','精确内部重试次数不可读，记 null/未知，不将耗时当命中证据。','暂停时钟起点为 bind(play:false) 调用前；bind返回和各截图调用/返回分别记录。'])
    before=prev.snapshot();s['initialSettings']=before;(OUT/'initial-settings.json').write_text(json.dumps(before),encoding='utf-8')
    try:
        unlocked()
        argv=[sys.executable,'-B',TOOL/'coverage_build.py','lib/main_coverage_suite.dart','--max-workers=2','-Dorg.gradle.jvmargs=-Xms128m -Xmx1024m -XX:MaxMetaspaceSize=384m -XX:ReservedCodeCacheSize=96m -XX:TieredStopAtLevel=1 -XX:ActiveProcessorCount=2 -XX:+UseSerialGC -XX:HeapBaseMinAddress=0x100000000','-Pkotlin.compiler.execution.strategy=in-process']
        with (OUT/'build-console.log').open('w',encoding='utf-8') as log:prev.call(argv,stdout=log,stderr=subprocess.STDOUT,check=True)
        shutil.copy2(TOOL/'coverage_isolated_build.log',OUT/'build.log')
        apk=OUT/'cp3-r4-release.apk';shutil.copy2(ROOT/'example/build/app/outputs/flutter-apk/app-release.apk',apk);s['apkSha256']=hashlib.sha256(apk.read_bytes()).hexdigest();s['apk']=str(apk.relative_to(ROOT));save(s)
        unlocked();console=OUT/'batch-console.log';print('R4 BEGIN',s['runId'],s['apkSha256'],flush=True)
        with console.open('w',encoding='utf-8') as log:code=prev.call([sys.executable,'-B',TOOL/'run_matrix.py','--only','cp3-headers','--run-id',s['runId'],'--reuse-apk',apk,'--baseline',ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json'],stdout=log,stderr=subprocess.STDOUT).returncode
        s['row']=prev.summarize('cp3-headers',s['runId'],1,code,console)
        try:s['analysis']=analyze(ROOT/s['row']['evidence'])
        except Exception as err:s['analysisError']=repr(err)
        a=s.get('analysis',{});e=a.get('extract',{});p=a.get('pool',{})
        if e.get('total')==60 and e.get('success')==60:
            s['conclusion']='抽帧本轮60/60成功，较上轮28/30改善，支持修复有效；但内部重试命中次数未知，因果归因仍待定'
        else:s['conclusion']='抽帧修复效果仍待定：失败及缺失样本按原样保留'
        s['conclusion']+='；池截图原始null '+str(p.get('originalNull'))+'/'+str(p.get('total'))+'，等待对照见逐阶段统计，暂停预热/截图问题仍未关闭'
        commit(s,'headers batch evidence')
        s['complete']=True
    except BaseException as err:s['stopReason']=repr(err);raise
    finally:
        try:
            prev.adb('shell','settings','put','global','stay_on_while_plugged_in',before['power'])
            prev.adb('shell','cmd','media_session','volume','--stream','3','--set',before['volume'])
            if prev.snapshot()['volume']!=before['volume']:prev.call([sys.executable,'-B',TOOL/'cp3_r3_restore_volume.py',OUT],check=True)
            after=prev.snapshot();s['restoration']=dict(before=before,after=after,matches=before==after)
        except Exception as err:s['restorationError']=repr(err)
        commit(s,'final results and device restoration')
if __name__=='__main__':main()
