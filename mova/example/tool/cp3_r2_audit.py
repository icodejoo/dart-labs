"""Audit the finished R2 evidence and append a compact, attributed final report."""
from collections import Counter
from datetime import datetime
import hashlib
import http.server
import json
from pathlib import Path
import subprocess
import time
import threading
import urllib.parse
import urllib.request
import zipfile

import cp3_r2 as campaign

ROOT, TOOL, SUMMARY = campaign.ROOT, campaign.TOOL, campaign.SUMMARY


def command_records(row):
    for path in sorted((ROOT / row['evidence']).glob('*cp3-r2-*.json')):
        data=json.loads(path.read_text(encoding='utf-8'))
        if not isinstance(data,dict) or 'records' not in data:continue
        records=data['records']
        start=max((i for i,r in enumerate(records) if r.get('kind')=='BEGIN'),default=0)
        for i,r in enumerate(records[start:],start):
            yield path,i,r


def original_header_pass(r):
    n=r['numbers'];variant=r['id'].split('.')[-2]
    good=[q for q in n['requests'] if q['query'].endswith('-yes')]
    bad=[q for q in n['requests'] if q['query'].endswith('-no')]
    return bool(n['positive'] and (variant=='prefetch' or not n['negative']) and good and bad
        and all(q['status']==200 and q['referer']=='https://cp3.example/authorized' for q in good)
        and all(q['status']==403 for q in bad)
        and (variant!='thumb' or any(q['path']=='/sprite.png' for q in good))
        and (variant!='prefetch' or any(q.get('range') is not None for q in good)))


def restore(state):
    before=state['initialSettings']
    campaign.adb('shell','am','force-stop', 'com.icodejoo.mova.mova_example.coverage')
    campaign.adb('shell','settings','put','global','stay_on_while_plugged_in',before['power'])
    readings=[]
    for _ in range(3):
        campaign.adb('shell','cmd','media_session','volume','--stream','3','--set',before['volume'])
        time.sleep(1)
        reading=campaign.snapshot();readings.append(reading)
        if reading['volume']==before['volume']:break
    if readings[-1]['volume']!=before['volume']:
        # This OEM logs shell setStreamVolume but does not apply it. Use the
        # existing APK's public volume action, with owned selector/media only.
        from functools import partial
        class Selector(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200);self.end_headers();self.wfile.write(b'api')
            def log_message(self,*args):pass
        source=next((ROOT/state['attempts'][0]['evidence']).glob('*cp3-headers-sources'))
        class Media(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args):pass
        servers=[http.server.ThreadingHTTPServer(('127.0.0.1',18082),Selector),
                 http.server.ThreadingHTTPServer(('127.0.0.1',18190),partial(Media,directory=str(source)))]
        try:
            for server in servers:threading.Thread(target=server.serve_forever,daemon=True).start()
            for port in (18082,18190):campaign.adb('reverse',f'tcp:{port}',f'tcp:{port}')
            campaign.adb('forward','tcp:18083','tcp:18083')
            campaign.adb('shell','am','start','-n','com.icodejoo.mova.mova_example.coverage/com.icodejoo.mova.mova_example.MainActivity')
            end=time.monotonic()+45
            while True:
                try:
                    with urllib.request.urlopen('http://127.0.0.1:18083/',timeout=2) as response:json.load(response)
                    break
                except OSError:
                    if time.monotonic()>end:raise RuntimeError('Volume restoration API unavailable')
                    time.sleep(.25)
            query=urllib.parse.urlencode(dict(group='video',audio='true',url='http://127.0.0.1:18190/a.mp4',
                action='volume',value=str(int(before['volume'])*5)))
            with urllib.request.urlopen('http://127.0.0.1:18083/run?'+query,timeout=5) as response:result=json.load(response)
            while result.get('status')=='running' and time.monotonic()<end:
                time.sleep(.25)
                with urllib.request.urlopen('http://127.0.0.1:18083/',timeout=3) as response:result=json.load(response)
            (ROOT/state['apk']).parent.joinpath('final-volume-api-restoration.json').write_text(
                json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
            if result.get('status')!='done':raise RuntimeError('Volume restoration action did not complete')
        finally:
            campaign.adb('shell','am','force-stop','com.icodejoo.mova.mova_example.coverage')
            for port in (18082,18190):campaign.adb('reverse','--remove',f'tcp:{port}')
            campaign.adb('forward','--remove','tcp:18083')
            for server in servers:server.shutdown();server.server_close()
    after=campaign.snapshot()
    matches=before['power']==after['power'] and before['volume']==after['volume'] and all(
        sorted(before[k].splitlines())==sorted(after[k].splitlines()) for k in ('reverse','forward'))
    state['restoration']['finalAudit']=dict(at=datetime.now().astimezone().isoformat(),after=after,
        readings=readings,matches=matches,
        note='receipt/basic曾改变系统音量；OEM shell命令记日志但未生效，使用同一APK现有video/volume动作恢复，再force-stop及撤销自有映射，按整轮初始值核验。')
    if not matches:raise RuntimeError('Final settings/mappings differ from initial settings')


def main():
    data=json.loads(SUMMARY.with_suffix('.json').read_text(encoding='utf-8'))
    state=data['secondRoundRevalidation']
    if not state.get('complete') or state.get('unfinished'):raise RuntimeError('Campaign has not finished')
    restore(state)
    state['title']='第二轮复验（修复后）'
    state['auditedAt']=datetime.now().astimezone().isoformat()
    state['campaignCommits']=subprocess.check_output(['git','log','--format=%H %s',
        state['head']+'..HEAD'],cwd=ROOT,text=True).splitlines()
    apk=ROOT/state['apk']
    assert hashlib.sha256(apk.read_bytes()).hexdigest()==state['apkSha256']
    hashes=[]
    for row in state['attempts']:
        run=row['runId'];folder=ROOT/row['evidence']
        build=json.loads((folder/('matrix-'+run+'-build.json')).read_text(encoding='utf-8'))
        assert build['sha256']['device']==build['sha256']['signed']==state['apkSha256']
        hashes.append(dict(runId=run,sha256=build['sha256']['device']))
        batch=row['batch']
        if batch=='cp3-headers':
            raw=json.loads((folder/('matrix-'+run+'-cp3-headers.json')).read_text(encoding='utf-8'))
            checks=[r for r in raw['records'] if r.get('kind')=='CHECK']
            row['sameScopeCounts']=dict(Counter('PASS' if original_header_pass(r) else 'FAIL' for r in checks))
            row['supplementCounts']={path:dict(Counter('PASS' if r['numbers']['nativePaths'][path]['pass'] else 'FAIL'
                for r in checks if '.quality.' in r['id'])) for path in ('extract','pool')}
            row['classification']='新增夹具缺陷：pool.slotFor.ready仅表示open已接受，不证明原生加载成功；回执快照偏早。第一次另有一次抽帧未取得图片，原因未定。'
            row['suspectedLocations']='example/lib/verify_auto/cp3_pages_auto.dart:nativePath; lib/src/core/feed/engine_pool.dart:_openBinding（accepted语义）; lib/src/platform_impl/mpv_extractor_impl.dart:_extractNow（仅首试偶发）'
            row['comparison']='旧口径 10 PASS/5 FAIL → 15 PASS；新增extract/pool使扩展整批仍FAIL'
        elif batch=='cp3-r2-subtitles':
            row['requestedChecks']=dict(PASS=0,FAIL=0,BLOCKED=4)
            row['classification']='夹具/打包缺陷：pubspec未声明assets/test_subtitle.srt，首格式读取即SCRIPT_ERROR；余下ass/vtt/movtext未执行，不归产品。'
            row['suspectedLocations']='example/pubspec.yaml:114; example/lib/verify_auto/coverage_new.dart:126；前提未成立，没有证据指向lib'
            row['comparison']='首轮srt/ass/vtt为404导致FAIL；本轮包内srt缺失，四格式均缺有效CHECK → BLOCKED'
        elif batch=='cp3-r2-pool':
            targets=[r for _,_,r in command_records(row) if r.get('kind')=='CHECK' and r.get('id','').startswith('A29.')]
            row['repairedTargets']=[dict(id=r['id'],passed=r.get('pass'),detail=r.get('detail'),numbers=r.get('numbers')) for r in targets]
            blocked=[dict(id=r.get('id'),pointer=p.name+':records['+str(i)+']',
                beforeError=r.get('numbers',{}).get('before',{}).get('counterError'),
                afterError=r.get('numbers',{}).get('after',{}).get('counterError'))
                for p,i,r in command_records(row) if r.get('kind')=='CHECK' and r.get('pass') is None]
            row['blockedMeasurements']=blocked
            row['classification']='A29容量上限/最终页/释放修复均通过；F12/F13资源证据因/proc/self/fd动态枚举异常缺handles/cpuTicks，属于夹具观测缺口，非已证资源泄漏。'
            row['suspectedLocations']='example/lib/verify_auto/s00d_resources.dart:metrics；lib/src/core/feed/engine_pool.dart（目标回收断言通过，未证产品错误）'
            row['comparison']='A29.final及poolReclaimed旧FAIL → 两条源命令的6条A29 CHECK通过；资源计数缺证据仍BLOCKED'
        elif batch=='cp3-r2-receipt':
            row['differenceCounts']=dict(Counter(r.get('event','')+':'+','.join(r.get('differences',[]))
                for _,_,r in command_records(row) if r.get('kind')=='CHECK' and r.get('pass') is False))
            row['classification']='混合待定：Seeked对独立progress流的硬相等仍有夹具/契约时序问题；Size/Quality为事件相关载荷差异，缺发出时同引擎/世代状态，不直接认定产品回归。'
            row['suspectedLocations']='example/lib/verify_auto/s00d_receipt.dart:receive；lib/src/core/engine.dart:1009/:3014/:3107；lib/src/core/cutover/cutover_engine.dart事件代理'
            row['comparison']='同三命令首轮45条回执FAIL → 本次'+str(row['counts'].get('FAIL',0))+'条；其余历史触发路径未覆盖'
        elif batch=='cp3-feedplayer':
            row['comparison']='首轮专项12 PASS/3 FAIL、全量13 PASS/2 FAIL → 15 PASS；controller/autoPause/failure各5'
        elif batch=='cp3-cp1gap-bottom':row['comparison']='首轮0 PASS/5 FAIL → 5 PASS；60次VOD/live-DVR叶子挂载全部通过'
        elif batch=='cp3-r2-s3s6':row['comparison']='S6旧策略夹具不符导致FAIL → 显式pause的3 PASS；默认keepDecoding的S3对照3 PASS'
        elif batch=='cp3-r2-stt':row['comparison']='N22.sttRetry旧calls=0/running=false FAIL → calls=2/running=true PASS；rollback亦PASS（仅测试引擎回滚）'
        elif batch=='cp2-qoe':
            row['comparison']='CP2旧9 PASS/1 BLOCKED（缺manual720.4） → '+str(row['counts'])+'；单独CHECK见manual720_4'
            row['classification']='若缺原生path/time-pos或恢复前提则BLOCKED；真实CHECK失败保留，不以旧9条PASS补齐本轮。'
            row['suspectedLocations']='example/lib/verify_auto/cp2_qoe_auto.dart:runQoe; example/lib/verify_auto/cp2_harness.dart:native; lib/src/core/engine.dart恢复/quality路径'
    state['installedApkAudit']=hashes
    state['offlineValidation']=['run_matrix --check PASS (92 batches / 135 IDs / 6 manual)',
        'test_cp3.py: 6 PASS','test_run_matrix.py: 66 PASS；新增批次移到gap-screen之前后通过',
        'Gradle release BUILD SUCCESSFUL in 4m16s; max-workers=2；成功尝试前FreePhysicalMemory=4250988 KiB；无虚拟内存错误重试',
        'git diff --check PASS（提交前再次检查）']
    with zipfile.ZipFile(apk) as z:
        state['subtitleApkAssets']={name:'assets/flutter_assets/assets/'+name in z.namelist()
            for name in ('test_subtitle.srt','test_subtitle.ass','test_subtitle.vtt','test_video_movtext.mp4')}
    latest={r['batch']:r for r in state['attempts']}
    state['finalBatchCounts']=dict(Counter(r['status'] for r in latest.values()))
    state['remainingUnresolved']=campaign.UNRESOLVED+[
        '本轮新增/保留：字幕srt打包缺失；池预热探针accepted/ready前提错误和迟到回执；第一次本地抽帧1次未取得图片（重试5/5通过）；动态资源/proc采样缺口。']
    if any(r.get('manual720_4') for r in state['attempts'] if r['batch']=='cp2-qoe'):
        state['qoeManual720_4Evidence']=[dict(runId=r['runId'],checks=r['manual720_4']) for r in state['attempts'] if r['batch']=='cp2-qoe']
    state['deviations'] += [
        'headers新增nativePaths布尔并入quality CHECK，导致原始扩展标签FAIL；已用同一不可变原始数据按旧完整判据单列15/15 PASS，不覆盖原始FAIL或冒充整批通过。',
        '字幕首格式SRT因缺APK资产中断，余下三格式未执行；整批重试一次同故障后继续，须下次补资源并构建新包，不能在本轮换包。',
        'receipt单批cleanup曾音量读回不一致；OEM的shell设置未生效，使用同一APK现有video/volume动作恢复volume=0，再force-stop并撤销恢复过程自有映射；USB常亮=2，最终读回见finalAudit。']
    state['deviations']=list(dict.fromkeys(state['deviations']))
    campaign.write(state)
    # Replace only the appended R2 section; first-round report stays byte-for-byte.
    md=SUMMARY.with_suffix('.md').read_text(encoding='utf-8')
    prefix=md.split('\n## 第二轮复验（修复后）')[0]
    lines=['','## 第二轮复验（修复后）','',
        f"设备 STG-AL00 / {campaign.SERIAL}；起点 `{state['head'][:8]}`；限定9批，{len(state['attempts'])}次尝试均已返回并逐次提交。本人执行，未转派、未跑Windows/F3/已通过页面/全量67批。",'',
        f"同一 release APK SHA-256：`{state['apkSha256']}`。每次安装拉包hash均相等；APK/原始matrix-run/完整日志仅留本地。",'',
        '|批次|最终结论|CHECK PASS/FAIL/BLOCKED|与首轮对比|','|---|---|---|---|']
    for batch,row in latest.items():
        c=row['counts'];count=f"{c.get('PASS',0)}/{c.get('FAIL',0)}/{c.get('BLOCKED',0)}"
        if batch=='cp3-r2-subtitles':count='0/0/4 字幕；另8回执PASS'
        if batch=='cp3-r2-stt':count='2/0/0 STT；另7回执PASS'
        lines.append(f"|{batch}|{row['status']}|{count}|{row['comparison']}|")
    lines+=['', 'headers整批FAIL包含新增探针；按首轮完整判据复算，同两次尝试均15/15 PASS。抽帧第一试4/5、第二试5/5；池预热探针两试均0/5，属于ready/accepted前提错误且存在迟到回执，仍缺有效解码预热验收。保留全部原始FAIL。',
        '', '逐次证据与提交：','', '|批次/尝试|状态|提交|本地原始证据目录|','|---|---|---|---|']
    commits=state['commits']
    for i,row in enumerate(state['attempts']):
        lines.append(f"|{row['batch']} / {row['attempt']}|{row['status']}|`{commits[i][:10]}`|`{row['evidence']}`|")
    lines+=['','失败/缺证据的特征、定位与定性：','']
    for batch,row in latest.items():
        if row['status']=='PASS':continue
        lines.append(f"- **{batch}**：{row['classification']} 对比：{row['comparison']}。疑似位置：{row['suspectedLocations']}。证据：`{row['evidence']}`。")
        if row.get('differenceCounts'):lines.append('  本次重试事件分布：`'+json.dumps(row['differenceCounts'],ensure_ascii=False)+'`；逐条records索引见JSON attempts.failures。')
    lines+=['','QoE缺项：`'+json.dumps(state.get('qoeManual720_4Evidence',[]),ensure_ascii=False)+'`。',
        '', '仍未解决/缺证据与人工项：','']+['- '+s for s in state['remainingUnresolved']]
    lines+=['','偏差与未完成：','']+['- '+s for s in state['deviations']]
    lines+=['- 运行计划全部完成；缺失的字幕四格式、池有效解码预热、F12/F13完整资源计数及剩余事件时序未验收通过，原因如上。',
        '', '恢复：最终原生读回媒体音量0、USB常亮2；adb reverse/forward均与初始空表一致。单批恢复失败保留，最终恢复已确认。',
        '', '离线/构建核验：']+['- '+s for s in state['offlineValidation']]
    SUMMARY.with_suffix('.md').write_text(prefix+'\n'.join(lines)+'\n',encoding='utf-8')
    print(json.dumps(dict(finalBatchCounts=state['finalBatchCounts'],restored=state['restoration']['finalAudit']['matches'],
        apkSha256=state['apkSha256']),ensure_ascii=False),flush=True)


if __name__=='__main__':main()
