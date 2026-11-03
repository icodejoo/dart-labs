"""Render CP1 checkpoint ledger only from this session's original evidence."""
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
E = ROOT/'example/tool/coverage_evidence'
TARGET = ROOT/'doc/plans/2026-11-03-cp1-results'


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


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
    prior = read(Path(str(TARGET)+'.json')) if Path(str(TARGET)+'.json').exists() else {}
    stage0 = read(E/'cp1-stage0.json') if (E/'cp1-stage0.json').exists() else {}
    data = dict(status=prior.get('status','RUNNING'), sourceHead='047b179c59676033b1392e5e7ccc8f8a39401b10',
        device='7NQBB23606003715 / STG-AL00 / Android 12 arm64 release', stage0=stage0,
        stages=prior.get('stages',{}), rows=[], failures=[], defects=prior.get('defects',[]),
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
            issues = [dict(evidence=rel(p),recordIndex=i,id=r['id'],status=r.get('status'),
                reason=r.get('missing'),numbers=r.get('numbers')) for p,i,r in samples if r.get('status')!='PASS']
            row = dict(id=scene+'.'+variant,stage=1,planned=planned,executed=len(samples),
                counts=dict(counts),status=status,criterion=criterion,cp0=baseline,
                difference='待本轮证据' if not samples else '见实测数字；CP0 无相同样本时不推断改善',
                evidence=[rel(p) for p,_ in sources],issues=issues,
                harness=[dict(evidence=rel(p),errors=d.get('harness'),missing=d.get('missing')) for p,d in sources if d.get('harness') or d.get('missing')])
            data['rows'].append(row)
            data['failures'].extend(dict(row=row['id'],**issue) for issue in issues if issue['status']=='FAIL')
    # Stage 2 and B supplemental evidence are filled by the same session's reducer.
    data['rows'].extend(prior.get('additionalRows',[]))
    data['additionalRows']=prior.get('additionalRows',[])
    for name in ['F3','dispose','HE V6','HE V10']:
        data['rows'].append(dict(id='Windows '+name,stage=4,planned=3,executed=0,status='BLOCKED',
            criterion='经 win_policy，次数 clamp_runs=3；不劣于 CP0，V10 零崩溃',
            cp0='本树 CP0 Windows 基线仍 PENDING',difference='待安静模式验证',
            evidence=['doc/plans/2026-11-03-win-quiet-mode.md（开工时不存在）']))
    data['counts']=dict(Counter(r['status'] for r in data['rows']))
    Path(str(TARGET)+'.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    lines=['# CP1 真机检查点结果','',f"状态：{data['status']}。本人执行，未转派；lib/test 未改。",
        '',f"设备：{data['device']}。",'',
        'APK SHA-256：`'+stage0.get('metadata',{}).get('sha256',{}).get('signed','待构建')+'`。构建一次，后续复用，安装后拉回逐值核验。',
        '', '证据目录：`example/tool/coverage_evidence/`（gitignored）；记录下标为 JSON records 的零基下标。',
        '',f"逐行计数：{data['counts']}。RUNNING 时未执行行不代表产品失败。",'',
        '|项目|计划/完成|结论|通过标准|CP0 基线及差异|原始证据|','|---|---:|---|---|---|---|']
    for r in data['rows']:
        ev='；'.join(r.get('evidence',[]))
        lines.append(f"|{r['id']}|{r['planned']}/{r['executed']}|{r['status']} {r.get('counts',{})}|{r['criterion']}|{r['cp0']}；{r['difference']}|{ev}|")
    lines += ['', '## 失败特征与证据','']
    for f in data['failures']:
        lines.append(f"- {f['row']} / {f['id']}：{f.get('reason') or 'CHECK 产品判据不满足'}；`{f['evidence']}` records[{f['recordIndex']}]；完整数字见 JSON。")
    if not data['failures']: lines.append('当前尚无已记录的产品 FAIL；缺证据仍为 BLOCKED。')
    lines += ['', '## 阶段、检查与恢复','', '```json',json.dumps({k:data[k] for k in ['stages','validations','restoration']},ensure_ascii=False,indent=2),'```', '', '## 需要修复的缺陷','']
    for defect in data['defects']:
        lines.append('- '+json.dumps(defect,ensure_ascii=False))
    lines += ['', 'Windows：开工时安静模式验证记录不存在，四组均待安静模式验证，没有启动 Windows 应用。','']
    Path(str(TARGET)+'.md').write_text('\n'.join(lines),encoding='utf-8')
    print(data['counts'])


if __name__=='__main__': main()
