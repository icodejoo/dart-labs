"""Blocking repaired-APK campaign; commit immediately after every attempt."""
from collections import Counter
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'example/tool'
SUMMARY = ROOT / 'doc/plans/2026-11-05-cp3-results'
STAMP = datetime.now().strftime('%Y%m%d-%H%M%S')
OUT = TOOL / 'coverage_evidence' / ('cp3-r2-' + STAMP)
SERIAL = '7NQBB23606003715'
SUFFIX = '\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>'
PLAN = ['cp3-headers','cp3-feedplayer','cp3-cp1gap-bottom','cp3-r2-subtitles',
        'cp3-r2-pool','cp3-r2-s3s6','cp3-r2-stt','cp3-r2-receipt','cp2-qoe']
UNRESOLVED = [
    'TLS/C16：本轮未重跑；仍缺服务证书/CA哈希、有效期/SAN、设备CA读回、原生握手码及时间线。',
    'V14/F16/N10：本轮未重跑；仍缺广告/正片/影子引擎与世代归属、EOF/duration、OpenSLES及错误事件时间线；V13b缺非零speed样本。',
    'PiP/A15与V10/V10x方向：本轮未重跑；仍缺原生系统回调、请求归属及方向初态；fullscreen已通过不代替这些路径。',
    '剩余事件时序：接收时getter不等于发出时状态；仍需engine/open attempt/renderEpoch及width/height/quality发出顺序，不能把异步差异直接关闭。',
    '源退出根因：历史a child exited未定位子进程/退出码/stderr；本轮独立服务成功不关闭该问题。',
    '人工：听音/视觉、PiP系统交互、真实锁屏提示、GSM/路由切换、真实STT模型/WHEP/守卫专包仍需人工或专用环境。',
    '原全量67批及其14个BLOCKED、Windows待安静模式维持历史结论；本轮没有运行Windows验证。',
]


def call(argv, **kw):
    return subprocess.run(list(map(str, argv)), cwd=ROOT,
                          creationflags=subprocess.CREATE_NO_WINDOW, **kw)


def adb(*args):
    sys.path.insert(0, str(TOOL))
    from cp0_device_guard import wait_online
    wait_online(SERIAL)
    return subprocess.check_output(['adb','-s',SERIAL,*args],text=True,encoding='utf-8',errors='replace',timeout=120)


def snapshot():
    return dict(power=adb('shell','settings','get','global','stay_on_while_plugged_in').strip(),
                volume=re.search(r'volume is (\d+)',adb('shell','cmd','media_session','volume','--stream','3','--get'))[1],
                reverse=adb('reverse','--list'),forward=adb('forward','--list'))


def write(state):
    data=json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    data['secondRoundRevalidation']=state
    SUMMARY.with_suffix('.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    original=SUMMARY.with_suffix('.md').read_text(encoding='utf-8').split('\n## 第二轮复验（修复后）')[0]
    lines=['','## 第二轮复验（修复后）','',
        f"起点 `{state['head']}`；设备 STG-AL00 / {SERIAL}；同一 release APK SHA-256 `{state['apkSha256']}`。",
        f"开始 {state['started']}；完成={state.get('complete',False)}。原首轮报告与全量结论保留；不以本轮局部绿灯替代全量验收。",'',
        '|批次/尝试|第二轮|CHECK PASS/FAIL/BLOCKED|与首轮对比|证据|','|---|---|---|---|---|']
    for row in state['attempts']:
        c=row['counts']
        lines.append(f"|{row['batch']} / {row['attempt']}|{row['status']}|{c.get('PASS',0)}/{c.get('FAIL',0)}/{c.get('BLOCKED',0)}|{row['comparison']}|`{row['evidence']}`|")
    lines+=['','失败特征与定性（保留所有尝试，不用重试覆盖）：','']
    for row in state['attempts']:
        if row['status']!='PASS':
            lines.append(f"- {row['runId']}：{row['classification']}；{json.dumps(row['failures'],ensure_ascii=False)}；缺证据/运行异常={json.dumps(row['errors'],ensure_ascii=False)}。疑似位置：{row['suspectedLocations']}。")
    lines+=['','仍未解决/缺证据：','']+['- '+s for s in UNRESOLVED]
    lines+=['','偏差与范围：','']+['- '+s for s in state['deviations']]
    lines+=['','恢复原生读回：`'+json.dumps(state.get('restoration',{}),ensure_ascii=False)+'`。',
            '','逐批提交（本次提交自身hash由后续提交/最终汇报给出）：'+', '.join(state['commits'])+'。',
            '',f"未完成：{state.get('unfinished',PLAN)}；原因：{state.get('stopReason','执行中')}。"]
    SUMMARY.with_suffix('.md').write_text(original+'\n'.join(lines)+'\n',encoding='utf-8')


def commit(state,label):
    write(state)
    paths=['example/tool/cp3_r2.py','example/tool/cp3_r2_legacy.py','example/tool/coverage_cp3.py',
           'example/tool/matrix_manifest.json','example/lib/verify_auto/cp3_pages_auto.dart',
           'doc/plans/2026-11-05-cp3-results.md','doc/plans/2026-11-05-cp3-results.json']
    for argv in [['git','add','--',*paths],['git','diff','--cached','--check'],
                 ['git','-c','maintenance.auto=false','-c','gc.auto=0','commit','-m','test(mova): '+label+SUFFIX]]:
        call(argv,check=True)
    sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    state['commits'].append(sha)
    print('R2 COMMIT',sha,label,flush=True)


def summarize(batch,run_id,attempt,code,console):
    reports=list((ROOT/'doc/plans').glob('*-matrix-run-'+run_id+'.json'))
    report=json.loads(reports[0].read_text(encoding='utf-8')) if reports else {}
    result=report.get('batches',{}).get(batch,{})
    folder=TOOL/'coverage_evidence'/('matrix-'+run_id)
    checks=[];errors=[];files=[]
    if 'gap_result' in result:
        raw=result['gap_result'];checks=[r for r in raw.get('records',[]) if r.get('kind')=='CHECK']
        errors+=raw.get('harness',[])+raw.get('missing',[])
        if not raw.get('completed'):errors.append('missing completion')
    else:
        for path in sorted(folder.glob('matrix-'+run_id+'-cp3-r2-*.json')):
            try:data=json.loads(path.read_text(encoding='utf-8'))
            except ValueError:continue
            if 'records' not in data:continue
            records=data['records'];start=max((i for i,r in enumerate(records) if r.get('kind')=='BEGIN'),default=0)
            records=records[start:]
            checks += [dict(r,evidence=path.name+':records['+str(start+i)+']') for i,r in enumerate(records) if r.get('kind')=='CHECK']
            errors += [str(r) for r in records if r.get('kind') in ('ERROR','UNCAUGHT','SCRIPT_ERROR')]
            if not any(r.get('kind')=='END' and r.get('status')=='done' for r in records):errors.append(path.name+': missing successful END')
            files.append(path.name)
        if batch=='cp3-r2-s3s6':
            text='\n'.join(p.read_text(encoding='utf-8',errors='replace') for p in folder.glob('matrix-'+run_id+'-cp3-r2-s3s6.log'))
            checks=[dict(id=m[0],status=m[1],feature=m[2]) for m in re.findall(r'VERDICT (S3|S6) (PASS|FAIL|BLOCKED) ([^\r\n]*)',text)]
            for ident in ['S3','S6']:
                if sum(r['id']==ident for r in checks)!=3:errors.append(ident+': expected three verdicts')
    counts=Counter(r.get('status') or ('PASS' if r.get('pass') is True else 'FAIL' if r.get('pass') is False else 'BLOCKED') for r in checks)
    required={
        'cp3-r2-subtitles':['F11.srt','F11.ass','F11.vtt','F11.movtext'],
        'cp3-r2-stt':['N22.sttRollback','N22.sttRetry'],
        'cp3-r2-pool':['A29.final','A29.poolReclaimed','A29.dispose'],
    }.get(batch,[])
    for ident in required:
        if not any(r.get('id')==ident for r in checks):errors.append('missing required CHECK '+ident)
    if batch=='cp3-r2-receipt':
        for implementation in ['engine','cutover']:
            if not any(r.get('id')=='A2.'+implementation+'.receipt' for r in checks):
                errors.append('missing '+implementation+' receipt evidence')
    if batch=='cp3-r2-pool' and len(files)!=2:errors.append('expected feed and s00d-resources results')
    for name,r in report.get('batches',{}).items():
        if r.get('kind') not in ('OK','FAIL'):errors.append(name+': '+str(r.get('error') or r.get('kind')))
    if not checks:errors.append('no CHECK evidence')
    failures=[]
    for r in checks:
        if r.get('status')=='FAIL' or r.get('pass') is False:
            failures.append({k:r[k] for k in ('id','event','differences','feature','actual','expected','evidence') if k in r and k not in ('actual','expected')})
    status='FAIL' if counts['FAIL'] else 'BLOCKED' if errors or counts['BLOCKED'] else 'PASS'
    old='BLOCKED（9/10，缺manual720.4）' if batch=='cp2-qoe' else 'FAIL（修复前夹具或产品问题）'
    row=dict(batch=batch,runId=run_id,attempt=attempt,exit=code,kind=result.get('kind'),status=status,
             counts=dict(counts),comparison=old+' → '+status,evidence=str(folder.relative_to(ROOT)),
             rawReport=str(reports[0].relative_to(ROOT)) if reports else None,console=str(console.relative_to(ROOT)),
             errors=errors,failures=failures,rawFiles=files,
             classification='待定：保留原始载荷与运行异常，区分事件接收时快照/夹具前提和产品',
             suspectedLocations='lib/src/core/engine.dart; lib/src/core/cutover/cutover_engine.dart; example/lib/verify_auto/s00d_receipt.dart')
    if batch=='cp3-headers':
        row['nativePaths']={r['id']:{k:v.get('pass') for k,v in r.get('numbers',{}).get('nativePaths',{}).items()} for r in checks if '.quality.' in r.get('id','')}
        row['originalQualityChecks']={r['id']:bool(r['numbers'].get('positive') and not r['numbers'].get('negative') and
            any(q.get('query','').endswith('-yes') for q in r['numbers'].get('requests',[])) and
            all(q.get('status')==(200 if q.get('query','').endswith('-yes') else 403) for q in r['numbers'].get('requests',[])))
            for r in checks if '.quality.' in r.get('id','')}
    if batch=='cp2-qoe':
        row['manual720_4']=[dict(id=r['id'],status=r.get('status'),
            numbers={k:v for k,v in r.get('numbers',{}).items() if k in
                ('sessionStarts','sessionIds','retryCount','resumePositionDiffMs','currentQuality')})
            for r in checks if r.get('id')=='CP2.qoe.manual720.4']
    return row


def main():
    os.environ.update(MOVA_CP3_CAMPAIGN='1',MOVA_MATRIX_SERIAL=SERIAL,ANDROID_SERIAL=SERIAL,
                      ANDROID_SDK_ROOT='E:/sdk/android',ANDROID_HOME='E:/sdk/android',PYTHONDONTWRITEBYTECODE='1')
    OUT.mkdir(parents=True)
    apk=OUT/'cp3-r2-release.apk'
    shutil.copy2(ROOT/'example/build/app/outputs/flutter-apk/app-release.apk',apk)
    shutil.copy2(TOOL/'coverage_isolated_build.log',OUT/'build.log')
    with zipfile.ZipFile(apk) as z:
        native=z.read('lib/arm64-v8a/libmpv.so')
        if len(native)<1024 or native.startswith(b'version https://git-lfs'):raise RuntimeError('APK has LFS native pointer')
    state=dict(started=datetime.now().astimezone().isoformat(),head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
               apk=str(apk.relative_to(ROOT)),apkSha256=hashlib.sha256(apk.read_bytes()).hexdigest(),attempts=[],commits=[],complete=False,unfinished=PLAN[:],
               deviations=['首次PowerShell调用拆分-P参数导致构建任务名错误；日志本地保留，改用Python参数数组；不计作虚拟内存重试。',
               '缺失ignored stall.mp4按首轮同参数重新生成40s H264/AAC素材；媒体不提交。',
               '底栏旧驱动未提供18192；补齐自有真实滚动HLS、等待分片就绪及映射恢复，DVR/60次挂载断言不变。',
               'headers保持原15 CHECK和5次每变体，quality内新增每轮extract/pool独立正负对照回执；不改产品代码。',
               '字幕/pool/STT/回执使用新增窄批次选择器，保留原子命令次数；回执覆盖basic普通/代理及ABR，未重新覆盖所有历史触发路径。',
               'QoE无子项续跑入口：按CP2口径整批5次×resume/manual720；失败仅再整批重试一次。'])
    before=snapshot();state['initialSettings']=before
    (OUT/'initial-settings.json').write_text(json.dumps(before,indent=2),encoding='utf-8')
    try:
        for batch in PLAN:
            for attempt in (1,2):
                run_id='cp3-'+batch.removeprefix('cp3-')+'-r2-'+datetime.now().strftime('%Y%m%d-%H%M%S')
                console=OUT/(run_id+'.console.log')
                argv=[sys.executable,'-B',TOOL/'run_matrix.py','--only',batch,'--run-id',run_id,'--reuse-apk',apk,
                      '--baseline',ROOT/'doc/plans/2026-11-03-s00e-matrix-replay-r1030.json']
                print('R2 BEGIN',batch,attempt,run_id,flush=True)
                with console.open('w',encoding='utf-8') as log:
                    code=call(argv,stdout=log,stderr=subprocess.STDOUT).returncode
                row=summarize(batch,run_id,attempt,code,console)
                state['attempts'].append(row)
                print('R2 END',batch,row['status'],row['counts'],flush=True)
                commit(state,'CP3 repaired APK '+batch+' attempt '+str(attempt)+' evidence')
                if row['status']=='PASS':break
            state['unfinished'].remove(batch)
        state.update(complete=True,stopReason='全部限定批次已返回最终结果；所有失败/缺证据和重试均保留。')
    except BaseException as error:
        state['stopReason']=repr(error)
        raise
    finally:
        after=snapshot()
        state['restoration']=dict(before=before,after=after,matches=before==after)
        write(state)
        (OUT/'state.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        commit(state,'CP3 second round final results and device restoration')


if __name__=='__main__':main()
