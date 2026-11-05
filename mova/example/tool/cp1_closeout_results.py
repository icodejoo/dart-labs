"""Reconcile immutable CP1 native evidence without rewriting historic FAILs."""
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
E = ROOT/'example/tool/coverage_evidence'
TARGET = ROOT/'doc/plans/2026-11-03-cp1-results'


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def rel(path):
    return Path(path).resolve().relative_to(ROOT.resolve()).as_posix()


def combined(statuses):
    return 'FAIL' if 'FAIL' in statuses else 'PASS' if statuses and all(s == 'PASS' for s in statuses) else 'BLOCKED'


def numbers_summary(numbers):
    # Complete raw traces remain at the immutable recordIndex. Keep the ledger
    # compact, while retaining direct native before/after, events and counters.
    out={k:v for k,v in numbers.items() if k not in
         ('networkWindow','frameTimings','events','nativeSamples','resumeNativeSamples','fixture')}
    for key in ('nativeSamples','resumeNativeSamples'):
        if key in numbers: out[key+'Count']=len(numbers[key])
    for key in ('networkWindow','fixture'):
        value=numbers.get(key)
        if isinstance(value,dict):
            out[key+'Summary']={k:v for k,v in value.items() if k not in ('requests','responses','manifests')}
            out[key+'TraceCounts']={k:len(value[k]) for k in ('requests','responses','manifests') if k in value}
    return out


def reconcile(windows_run):
    original = json.loads(subprocess.check_output(['git', 'show',
        'a0420953^:mova/doc/plans/2026-11-03-cp1-results.json'], cwd=ROOT))
    data = copy.deepcopy(original)
    rows = {r['id']: r for r in data['rows']}
    checks = []

    def change(rowid, **values):
        row = rows[rowid]
        if 'previous' not in row:
            previous = copy.deepcopy(row)
            row.clear(); row.update(id=rowid, previous=previous)
            for key in ('stage','planned','criterion','cp0'):
                row[key] = previous.get(key)
        row.update(values)
        row.setdefault('issues', [])
        return row

    def native(run, scene, variants, note):
        folder=E/('matrix-'+run)
        path=folder/f'matrix-{run}-cp1-{scene}.json'
        raw=read(path)
        assert raw['completed'] and not raw['harness'] and not raw['missing'], path
        meta=read(folder/f'matrix-{run}-build.json')
        assert meta['sha256']['signed']==meta['sha256']['device']
        for variant, expected in variants.items():
            samples=[(i,r) for i,r in enumerate(raw['records']) if r['kind']=='CHECK' and r['id'].startswith(f'CP1.{scene}.{variant}.')]
            assert len(samples)==expected, (path,variant,len(samples))
            counts=dict(Counter(r['status'] for _,r in samples))
            change(f'{scene}.{variant}', executed=len(samples), counts=counts,
                status=combined([r['status'] for _,r in samples]), result=f'{counts.get("PASS",0)}/{expected}，完整 CHECK 与原生数字见证据',
                difference=note, evidence=[rel(path)], apkSha256=meta['sha256']['signed'],
                buildEvidence=rel(folder/f'matrix-{run}-build.json'), harness=[],
                measurements=[dict(recordIndex=i,id=r['id'],values=numbers_summary(r.get('numbers',{}))) for i,r in samples])
        checks.append(dict(kind='native',evidence=rel(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),passed=True))

    native('cp1-close-wakeswap-1838','wakeswap',{'swap':10},'新源网络超时20s，闸门仍跨旧5s唤醒计时；10次真正新源首帧/原生地址通过。')
    native('cp1-close-edgepause-1843','edgepause',{'pause':10,'fallback':10},'完整 HTTP URI 夹具功能通过；旧相对 URI 协议错误另立归因阻塞，不能凭此判夹具根因。')
    native('cp1-close-errclass-1832','errclass',{'nonfatal':5,'fatal':5,'poster':5},'等独立100ms泵消费 END_FILE 再释放；fatal独立原始事件5/5、超时0/5；原 records[262] FAIL 保留。')
    native('cp1-close-recovery-r3-1853','recovery',{'resume':10,'manual720':10},'限速与预读上限构成真实卡死；以原生稳定落点判恢复，notify=false不应等待用户MovaSeeked；误差最大120/280ms。')
    native('cp1-close-probe-1858','probe',{'list':10,'manual':10,'once':10,'failover':5,'disabled':5},'真实滑动直播主源404触发备用源；每源一次；关闭组0探测。')

    control=E/'matrix-cp1-close-edgepause-relative-2023/matrix-cp1-close-edgepause-relative-2023-cp1-edgepause.json'
    raw=read(control)
    assert raw['completed'] and not raw['harness'] and not raw['missing']
    selected=[(i,r) for i,r in enumerate(raw['records']) if r['kind']=='CHECK']
    assert len(selected)==20 and all(r['status']=='PASS' for _,r in selected)
    for variant in ('pause','fallback'):
        rows['edgepause.'+variant]['controlEvidence']=dict(evidence=rel(control),uriStyle='root-relative',
            recordIndices=[i for i,r in selected if f'.{variant}.' in r['id']],counts={'PASS':10})
    protocol=dict(id='edgepause.protocolAttribution',stage=1,planned=0,executed=0,status='BLOCKED',counts={'BLOCKED':1},
        criterion='解释原第六次根相对URI协议错误：区分夹具服务与产品/原生',cp0='无此交错基线',
        result='绝对URI20/20、原始相对URI20/20，本轮均未复现旧错误；责任归因未闭合',
        difference='合法相对URI不能仅因没有协议前缀判为夹具错误；未证明夹具根因，不把功能通过当作历史缺陷已修。',
        evidence=[rel(control),'example/tool/coverage_evidence/matrix-cp1-edgepause-20261103-1542/matrix-cp1-edgepause-20261103-1542-cp1-edgepause.json'],
        recordIndices=[1256,1258,1281,1539,1540])
    data['rows'].append(protocol);rows[protocol['id']]=protocol

    hpath=E/'matrix-cp1-close-h28-r3-1818-cp0-h28/cp0-result.json';h=read(hpath)
    assert h['completed'] and not h['harness']
    for mode in ('playing','paused','cutover'):
        selected=[(i,v) for i,v in enumerate(h['verdicts']) if v['case']=='gap:H28.default.'+mode]
        assert len(selected)==30 and all(v['status']=='PASS' and abs(v['actual']['deltaMs'])<=500 and v['actual']['path']==v['expectedPath'] for _,v in selected)
        change('H28.default.'+mode,status='PASS',executed=30,counts={'PASS':30},evidence=[rel(hpath)],
            apkSha256='979e3d9ba3f8d45beb1425634636c77fe9b6d174de36819d2c573e658c989cf4',
            result='30/30，最大绝对落点误差'+str(max(abs(v['actual']['deltaMs']) for _,v in selected))+'ms',
            difference='原两个0秒读回均在既有恢复链落地前采样；下一次seek之前已自愈。改稳定窗测量，未改lib。',
            measurements=[dict(recordArray='verdicts',recordIndex=i,actual=v['actual']) for i,v in selected])
    checks.append(dict(kind='H28',evidence=rel(hpath),passed=True,count=90))

    skin=[]
    for suffix in ('','-1','-2'):
        p=E/f'matrix-cp1-close-skin-1825{suffix}-skin/cp0-result.json';s=read(p)
        for i in (6,8,56,61):
            assert s['verdicts'][i]['status']=='PASS'
            skin.append(dict(evidence=rel(p),recordArray='verdicts',recordIndex=i,values=s['verdicts'][i]))
    srow=dict(id='B.skin',stage=3,planned=12,executed=12,status='PASS',counts={'PASS':12},
        criterion='设计内lockToggle完整有序树与真实挂树/点击，不删除组件或放宽等式',cp0='旧期望未含已落地B14/C06锁定按钮',
        result='三轮各4条目标快照，12/12；Flutter皮肤测试24通过',difference='辅助快照通过不代表B03底栏专属刺激已覆盖',
        evidence=sorted({m['evidence'] for m in skin}),measurements=skin,
        apkSha256='9a9e047da9bcec323ad51ca88cd0b7097f5ec8fb54e86fc4caa70a52fe12e78c')
    data['rows'].append(srow);rows[srow['id']]=srow
    change('B.bottomPatch',status='BLOCKED',executed=0,counts={},
        result='辅助skin 12条已修；底栏专属刺激仍0/3，不能冒充通过',difference='缺底栏专属夹具；本次范围仅修旧快照。',
        evidence=srow['evidence'],measurements=[])

    core_path=E/'cp1-close-keepalive-core-comparison.json';core=read(core_path)
    for scene in ('S1','S13'):
        assert core['decisions'][scene]=='PASS'
        change('keepalive-core.'+scene,status='PASS',executed=5,counts={'PASS':5},
            result='两版各5轮；当前原生子样本'+str(core['cp1']['scenes'][scene]['counts']),
            difference='归档CP0产品revision独立重建同诊断入口；S1每轮25/50/100 GOP。grace不冒充解码首帧时延。',
            evidence=[rel(core_path),core['cp1']['evidence']],measurements=core['cp1']['scenes'][scene]['samples'],
            apkSha256='a7e4ccc9954a643a4843198ccd50247ff1f357d4b3de1dbd243aa2909875dd7d')
    visual_path=E/'cp1-close-keepalive-review/visual-review.json';visual=read(visual_path)
    assert visual['status']=='PASS'
    for scene in ('S7','S14'):
        change('keepalive-s7s14.'+scene,status=visual['decisions'][scene],executed=5,counts={'PASS':5},
            result='5/5；S7 100/100恢复运动对，S14 holding与CP0同为黑屏且恢复重新运动',
            difference='token保持真实阶段，精确ACK后继续；原始CHECK人工项不回写。CP0一轮采图缺测保持BLOCKED，显式补采只补缺测。',
            evidence=[rel(visual_path)],measurements=visual['selections'][scene],
            apkSha256='a7e4ccc9954a643a4843198ccd50247ff1f357d4b3de1dbd243aa2909875dd7d')

    wp=E/windows_run/'result.json';win=read(wp)
    for item in ('F3','dispose','HE V6','HE V10'):
        attempts=[r for r in win['attempts'] if r['item']==item]
        assert len(attempts)==3
        native_status=combined([a['status'] for a in attempts])
        status=native_status if item=='HE V10' or native_status!='PASS' else 'BLOCKED'
        change('Windows '+item,status=status,executed=3,counts=dict(Counter(a['status'] for a in attempts)),
            collectionStatus=native_status,result=f'3次实测：{dict(Counter(a["status"] for a in attempts))}',
            difference='V10按功能/零崩溃绝对线裁决' if item=='HE V10' else '当前功能实测齐备；CP0 Windows同口径基线仍PENDING，无法裁决不劣于CP0',
            evidence=[rel(wp),'doc/plans/2026-11-03-win-quiet-mode.md'],measurements=attempts)

    for r in data['rows']:
        r.setdefault('apkSha256',original['stage0']['metadata']['sha256']['signed'] if not r['id'].startswith('Windows') else None)
        if r['id'] in ('edgepause.protocolAttribution','B.bottomPatch'):r['apkSha256']=None
    for master in data['masterRows']:
        if master['id']=='终审7b / fallback':master['subrows'].append(protocol['id'])
        members=[rows[i] for i in master['subrows']]
        master.update(status=combined([r['status'] for r in members]),executed=sum(r['executed'] for r in members),
                      evidence=sorted({e for r in members for e in r['evidence']}))
    data['counts']=dict(Counter(r['status'] for r in data['rows']))
    data['masterCounts']=dict(Counter(r['status'] for r in data['masterRows']))
    data['sourceHead']=subprocess.check_output(['git','rev-parse','HEAD'],text=True,cwd=ROOT).strip()
    data['originalCheckpoint']=dict(sourceHead=original['sourceHead'],masterCounts=original['masterCounts'],counts=original['counts'],
        revision='a0420953^',failureCount=len(original['failures']),note='原始FAIL数组完全保留；更新行previous保留原数字和证据。未更新PASS沿用原APK，不冒充新批次。')
    assert data['failures']==original['failures']
    data['additionalRows']=[dict(id=r['id'],status=rows[r['id']]['status'],see='rows') for r in original['additionalRows']]
    data['originalVisualReview']=original['visualReview']
    data['visualReview']=dict(status=visual['status'],evidence=rel(visual_path),decisions=visual['decisions'])
    data['originalAudit']=original['audit']
    data['originalRestoration']=original['restoration']
    data['originalRestoration']['evidence']='example/tool/coverage_evidence/cp1-original-session-restored-before-closeout.json'
    restored=read(E/'cp1-session-restored.json')
    data['restoration']={k:v for k,v in restored.items() if k!='commands'}
    data['restoration']['evidence']='example/tool/coverage_evidence/cp1-session-restored.json'
    assert restored['status']=='VERIFIED'
    data['stages']['4']=dict(status='COMPLETE_WITH_BASELINE_GAPS',windowsAppsLaunched=len(win['launches'])+1,
        validWindowsAppsLaunched=len(win['launches']),startupFailuresBeforeCases=1,
        casesExecuted=12,plannedRunsPerItem=3,gateRecord='doc/plans/2026-11-03-win-quiet-mode.md',gateRecordExistsAtClose=True,evidence=rel(wp))
    data['closeoutCommits']=subprocess.check_output(['git','log','-5','--format=%H %s'],text=True,cwd=ROOT).splitlines()[::-1]
    data['closeoutChecks']=checks
    data['validations'] += [dict(stage='closeout',flutterTests=dict(full=2094,skin=24,endFilePump=24,recoveryProbe=23),
        redGreen=dict(sampler={'red':4,'green':4},fixtureUriShape={'red':2,'green':2},productFix=0),
        analyze='lib/test 0 issues; selected example diagnostic pages 0 issues',pythonCloseout=12,pythonMatrix=56,
        nativeHeaderAudit='example/tool/coverage_evidence/cp1-closeout-native-audit.json')]
    data['closeoutResolution']=[
        dict(id='CP1-P01',status='CLOSED_MEASUREMENT',evidence=rows['H28.default.paused']['evidence'],detail='过早读回，既有链在下一次seek前自愈；无lib修改；90/90复测'),
        dict(id='CP1-H10',status='CLOSED_SNAPSHOT',evidence=srow['evidence'],detail='设计内lockToggle旧快照，12/12'),
        dict(id='CP1-H01',status='CLOSED_MEASUREMENT',evidence=rows['errclass.fatal']['evidence'],detail='释放早于独立100ms泵采样，5/5复测'),
        dict(id='CP1-H02',status='CLOSED_FIXTURE',evidence=rows['wakeswap.swap']['evidence'],detail='新源超时大于延迟闸门，10/10'),
        dict(id='CP1-H04',status='CLOSED_FIXTURE',evidence=rows['recovery.resume']['evidence'],detail='限速/预读上限建立真实卡死，原生判恢复，20/20'),
        dict(id='CP1-H06',status='CLOSED_FIXTURE',evidence=rows['probe.failover']['evidence'],detail='直播类型与真实404，备用源/关闭组补齐，40/40'),
        dict(id='CP1-H08',status='CLOSED_MEASUREMENT',evidence=[rel(core_path),rel(visual_path)],detail='双版本五轮基线，阶段token和相邻帧视觉证据齐备')]
    resolutions={r['id']:r for r in data['closeoutResolution']}
    for defect in data['defects']:
        defect['originalClassification']=defect['classification']
        if defect['id'] in resolutions:
            resolution=resolutions[defect['id']]
            defect.update(status=resolution['status'],resolution=resolution,
                classification=resolution['detail']+'（已关闭；原现象/证据保留）')
        else: defect['status']='BLOCKED'
    data['originalComparisonSummary']=original['comparisonSummary']
    data['comparisonSummary']=[s for s in original['comparisonSummary'] if not s.startswith('404：')]+[
        'H28新三组各30/30、0失败；稳定窗测量，lib未改。',
        '404独立END_FILE新5/5，原4/5历史缺采保留。',
        'keepAlive四场景各5/5；CP0归档源码重建同诊断入口，原生/视觉基线齐备。',
        '7b/fallback两套URI各20/20；旧协议错误归因仍BLOCKED。',
        'Windows功能各3/3；V10 0崩溃；CP0比较基线仍缺。']
    data['remaining']=[dict(id=r['id'],reason=r.get('difference') or r.get('result'),evidence=r['evidence']) for r in data['rows'] if r['status']!='PASS']
    data['status']='COMPLETE_WITH_FAILURES_AND_BLOCKERS' if any(r['status']=='FAIL' for r in data['rows']) else 'COMPLETE_WITH_BLOCKERS' if data['remaining'] else 'PASS'
    data['stages']['closeout']=dict(status=data['status'],masterCounts=data['masterCounts'],
        counts=data['counts'],deviceRestore=restored['status'],report='doc/plans/2026-11-03-cp1-results.md')
    data['closeoutBuilds']=list({r.get('apkSha256'):dict(sha256=r.get('apkSha256'),
        evidence=r.get('buildEvidence',r['evidence'])) for r in data['rows'] if
        (r.get('previous') or r['id']=='B.skin') and r.get('apkSha256')}.values())
    data['closeoutBuilds'].append(dict(role='CP0 keepAlive diagnostic rebuild',
        evidence='example/tool/coverage_evidence/cp0-keepalive-build.json',
        sha256='e0d9f938c260b9fddb5f08b219c1cacc2cfb867e1b993c99acccb6ffa09904d2'))
    data['closeoutIncident']=dict(kind='external-build-install',status='NOT_RESTORABLE_WITHOUT_BACKUP',
        evidence='example/tool/coverage_evidence/win-cp1-close-2039/external-install-incident.json',
        detail='首次CMake失败配置留下Program Files默认安装前缀，后续构建误覆盖既有目录；未备份无法恢复。已固定本树前缀并加构建前后路径检查，未删除既有目录。')
    for r in data['rows']:
        for evidence in r['evidence']:assert (ROOT/evidence).is_file(),(r['id'],evidence)
    audit=dict(passed=True,rowCount=len(data['rows']),masterCount=len(data['masterRows']),originalFailuresRetained=len(data['failures']),
        evidenceFilesChecked=True,checks=checks)
    (E/'cp1-closeout-ledger-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2),encoding='utf-8')
    data['audit']=dict(passed=True,evidence='example/tool/coverage_evidence/cp1-closeout-ledger-audit.json',checkCount=len(data['rows']))
    return data


def render(data):
    lines=['# CP1 真机检查点收口结果','',
        f"状态：{data['status']}；总计划16行 {data['masterCounts']}，细分 {data['counts']}。存在未关闭项，CP1尚未整体通过。",'',
        '本人执行，未转派。6项按序各提交；未修改lib，新增测试与验证器/夹具修正。原始15条FAIL保留在JSON failures，更新行previous保存旧数字；本轮结论不会覆盖旧原始记录。','',
        '设备：'+data['device']+'。证据位于 `example/tool/coverage_evidence/`（gitignored）。数组/行下标均为零基。正式通过依据原生事件、属性和画面，不以静态“未上机”标签或DONE标记代替。','',
        '原CP1 APK `'+data['stage0']['metadata']['sha256']['signed']+'`；沿用的旧PASS保持原APK归属。新批次各行JSON apkSha256/buildEvidence记录实际构建；安装均拉回核验。最后APK `'+data['restoration']['apk']['actual']+'`。','',
        '|总计划行|记录/计划|新结论|证据|','|---|---:|---|---|']
    for r in data['masterRows']:lines.append(f"|{r['id']}|{r['executed']}/{r['planned']}|{r['status']}|"+'<br>'.join(r['evidence'])+'|')
    lines += ['', '## 逐项结论与证据','', '|项目|实测/计划|结论|说明|证据|','|---|---:|---|---|---|']
    for r in data['rows']:
        note=(r.get('result','')+'；'+r.get('difference','')).replace('|','/')
        refs=[]
        measurements=r.get('measurements')
        if isinstance(measurements,list):
            indices=[m.get('recordIndex') for m in measurements if isinstance(m,dict) and m.get('recordIndex') is not None]
            if indices:refs.append(('verdicts' if r['id'].startswith(('H28.','B.skin')) else 'records')+str(indices))
        lines.append(f"|{r['id']}|{r['executed']}/{r['planned']}|{r['status']} {r.get('counts',{})}|{note}|"+'<br>'.join(r['evidence']+refs)+'|')
    lines += ['', '## 归因与复测','',
        '- H28：原 verdicts[32,77] 的0秒读回均早于既有恢复链落地。原始时序证明下一次seek前已恢复；稳定窗4条红→绿、既有产品链2条回归通过，lib未改。新三组各30/30，最大误差463/23/463ms。',
        '- Skin：总计划B14及C06落地记录确认lockToggle属于设计；保留完整有序树与挂树/点击判据。旧12条FAIL对应的新三轮12/12通过；不冒充B03专属底栏刺激。',
        '- 404：核心fatal到CHECK仅33.242ms，独立泵周期100ms，随即释放导致缺采。等待真实独立END_FILE后再释放，新5/5，各1条，无超时。',
        '- 7a、恢复、探测：分别修正新源网络超时、预缓冲抵消刺激/错误事件等待、滑动直播源类型；新批次10/10、20/20、40/40通过。所有中间HARNESS与缺测保留，未当产品PASS。',
        '- 7b/fallback：绝对URI20/20、原始相对URI20/20。旧records[1256,1258,1281]协议错误未复现，服务/产品责任仍未知，独立标BLOCKED。URI形状测试2红→2绿只证明输出契约。',
        '- keepAlive：CP0按a5c317f6产品源码归档重建同诊断入口，原生库哈希与旧APK一致。两版各5轮S1/S13；S7/S14以token阶段保持、双帧、前台守卫、精确ACK及人工联系表裁决。当前20/20；CP0原一轮缺采保留BLOCKED，显式补采记录齐备。',
        '- Windows：F3三模式各1次，dispose/V6/V10各3次，完整次数见逐行表。只经win_policy、640×360、无焦点干预；CP0 Windows仍PENDING，因此功能PASS不能当不劣于CP0通过。','',
        '## 检查与提交','',
        'Flutter：全量2094 PASS（--concurrency=3）；皮肤24、事件泵24、恢复/探测23 PASS。全量与analyze未并行；lib/test analyze 0 issues。Python closeout 12、matrix 56 PASS。产品修复红绿0；测量4红→4绿，夹具URI输出2红→2绿。','',
        *['- '+s for s in data['closeoutCommits']],'',
        '详细过程：`doc/plans/2026-11-03-cp1-closeout.md`；独立身份头审计 `example/tool/coverage_evidence/cp1-closeout-native-audit.json`，保留原外层HARNESS日志。','',
        '## 原始失败（历史，不是本轮新FAIL）','']
    for f in data['failures']:lines.append(f"- {f['row']} / {f['id']}：`{f['evidence']}` {f.get('recordArray','records')}[{f['recordIndex']}]。")
    lines+=['','## 仍未关闭','']
    for r in data['remaining']:lines.append('- '+r['id']+'：'+str(r['reason'])+'；'+'；'.join(r['evidence']))
    lines+=['','额外POD2两行不计入总计划16行，公共FirstFrame契约缺测仍BLOCKED，原CP1-P02及证据下标保留于JSON。','',
        '## 恢复与执行偏差','',
        '设备恢复：'+data['restoration']['status']+'，原设置与恢复后逐值一致，APK拉回哈希一致；见 `example/tool/coverage_evidence/cp1-session-restored.json`。','',
        data['closeoutIncident']['detail']+'证据：`'+data['closeoutIncident']['evidence']+'`。此越界写入已向用户明确报告，不能声称本次所有文件写入均在worktree内。','']
    return '\n'.join(lines)


if __name__=='__main__':
    data=reconcile(sys.argv[1])
    Path(str(TARGET)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    Path(str(TARGET)+'.md').write_text(render(data),encoding='utf-8')
    print(data['masterCounts'],data['counts'])
