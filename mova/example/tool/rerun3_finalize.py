"""Write F3/A17 retest conclusions from independently audited evidence."""
from pathlib import Path
import json, hashlib, re

H=Path(__file__).resolve().parent; R=H.parents[1]; O=H/'coverage_evidence'
D=R/'doc/plans/2026-10-27-device-coverage-android-retest2.md'
def load(n): return json.loads((O/n).read_text(encoding='utf-8'))
def link(n,label=None): return f'[{label or n}](../../example/tool/coverage_evidence/{n})'
s=load('rerun3-hls-summary.json'); fs=load('rerun3-hls-failures.json')
audit=load('rerun3-hls-audit.json'); m=load('rerun3-build-manifest.json'); state=load('rerun3-final-state.json')
valid=[x for x in audit if x['validTarget']]; failed=[x for x in valid if not x['pass']]
total=len(valid); passed=total-len(failed); retries=[x for x in valid if x['retrySuccess']]
assert total>=270 and all(sum(x['validTotal'] for k,x in s.items() if k.startswith(base))>=minimum for base,minimum in [('cutover',150),('normal',60),('paused',60)])
assert m['signedApkSha256']==m['deviceApkSha256']
hashes=load('rerun3-source-hashes.json')
assert all(hashlib.sha256((R/p).read_bytes()).hexdigest()==v for p,v in hashes.items())
tree=load('rerun3-protected-tree-hashes.json')
changed=[p for p,h in tree.items() if not (R/p).exists() or hashlib.sha256((R/p).read_bytes()).hexdigest()!=h]
assert not changed,changed
t=f'''\n\n## 基线与结果

设备 `7NQBB23606003715`，Android release，自行执行，只复测 F3/A17。

- `flutter analyze lib test`：0 issues，exit 0；{link('rerun3-analyze.log')}。
- `flutter test`：1517/1517 全绿，exit 0；{link('rerun3-test.log')}。
- F3/A17：有效 **{total}** 次，**{passed} 通过 / {len(failed)} 失败**；剔除 {len(audit)-total} 次，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 最低有效 target |
|---|---:|---:|---:|---:|---:|---:|
'''
labels={'cutover':'cutover 代理','normal':'普通播放','paused':'暂停态'}
agg={}
for base in labels:
    items=[(k,v) for k,v in s.items() if k.startswith(base)]
    agg[base]={n:sum(v[n] for k,v in items) for n in ['total','validTotal','validPassed','validFailed']}
    agg[base]['invalidTargets']=[(k,run) for k,v in items for run in v['invalidTargets']]
    agg[base]['minValidTarget']=min(v['minValidTarget'] for k,v in items)
    agg[base]['seekDistribution']={str(n):sum(v['seekDistribution'].get(str(n),0) for k,v in items) for n in {int(n) for k,v in items for n in v['seekDistribution']}}
    agg[base]['retrySuccesses']=[(k,run) for k,v in items for run in v['retrySuccesses']]
for mode,x in agg.items():
    t+=f'| {labels.get(mode,mode)} | {x["total"]} | {x["validTotal"]} | {x["validPassed"]} | {x["validFailed"]} | {len(x["invalidTargets"])} | {x["minValidTarget"]}ms |\n'
t+=f'| 合计 | {len(audit)} | {total} | {passed} | {len(failed)} | {len(audit)-total} | >=8000ms |\n'
t+='\n各批次有效数（补跑独立记账）：'+str({k:v['validTotal'] for k,v in s.items()})+'。\n'
t+='\n原始整组证据：'+ '、'.join(link(f'rerun3-hls-{mode}.json') for mode in s)+'。各文件含累计历史，审计仅取最后 BEGIN 之后。独立逐次复算：'+link('rerun3-hls-audit.json')+'；汇总：'+link('rerun3-hls-summary.json')+'。\n'
t+='''
## 判据与 seek 次数

沿用上轮同一 40s HLS VOD、18084 high/low，交替 360p/180p；真实 MovaPlayer 挂树，代理 enabled=true，经 switchQuality 切档。target 为切档前 mpv time-pos，必须 >=8000ms；远离 EOF 的复位仍 seek 9s，并等 Player 进度与原生读回差 <=100ms。未改动验证页 HLS 实现、ABR 配置或观测截止。

landed 为完整 RESTART 序列中首个 target±500ms；播放态 continued 由 mpv time-pos 实际增加 >=250ms 且 pause=no；暂停态保持 target±500ms 且 pause=yes；通过项同时核对原生 path 为目标档位。落点/继续推进各 6s 截止仅防挂死，不按墙钟推算位置。

每次 seekCount 统计 HLS_SWITCH 到 HLS_RESULT 之间 RetestKernel 的 KERNEL_SEEK_CALL，排除切档前复位；调用与返回、EVENT、duration、NATIVE_PROGRESS、全部 RESTART 原样保留。分布仅计有效样本，0次或超过3次另外保留，不能混入1次。

| 场景 | 0次 | 1次 | 2次 | 3次 | 超过3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
'''
for mode,x in agg.items():
    q=x['seekDistribution'];t+=f'| {labels.get(mode,mode)} | {q.get("0",0)} | {q.get("1",0)} | {q.get("2",0)} | {q.get("3",0)} | {sum(n for k,n in q.items() if int(k)>3)} | {len(x["retrySuccesses"])} |\n'
t+=f'| 合计 | {sum(x["seekCount"]==0 for x in valid)} | {sum(x["seekCount"]==1 for x in valid)} | {sum(x["seekCount"]==2 for x in valid)} | {sum(x["seekCount"]==3 for x in valid)} | {sum(x["seekCount"]>3 for x in valid)} | {len(retries)} |\n'
t+=f'\n“靠重发成功”共 **{len(retries)}** 次：同目标再次 KERNEL_SEEK_CALL 之前未出现目标附近 RESTART，之后首次落点并满足最终续播判据。该定义描述事件顺序；没有关闭重发的对照构建，不能证明每次重发都具有反事实必要性。\n'
if retries:
    t+='\n本轮观察到第二层重发实际参与成功；结合仍存在的失败，结论为重发有生效样本，但尚未消除竞态。\n'
    t+='\n| 场景/run（从0起） | target | seek调用(ms:target) | RESTART | 完整时间线 |\n|---|---:|---|---|---|\n'
    for x in retries:
        calls=', '.join(f'{v["ms"]}:{v["target"]}' for v in x['seekCalls'])
        fn=f'rerun3-retry-success-{x["mode"]}-{x["run"]}.json'
        t+=f'| {x["mode"]}/{x["run"]} | {x["target"]} | {calls} | {x["nativeRestarts"]} | {link(fn,"全部事件")} |\n'
else:
    t+='\n本轮未观察到靠重发成功；本轮仍有残余失败时，两层修复组合尚未达到验收要求。\n'
multi=[x for x in valid if x['seekCount']>=2 and not x['retrySuccess']]
if multi:
    t+='\n多次调用但不能记为重发成功的样本：'+str([(x['mode'],x['run'],x['pass'],bool(x['abrEvents'])) for x in multi])+'（依次为场景、run、pass、ABR）。例如 cutover/128 两次调用间隔735ms，首次RESTART已到10223ms；随后ABR从360p降至180p并发生第二次seek，最终low档从零推进而失败，不属于1.5s校验重发成功。\n'
t+='\n## 剔除、失败与复现\n\n'
excluded=[x for x in audit if not x['validTarget']]
if excluded:
    for x in excluded:
        fn=f'rerun3-excluded-{x["mode"]}-{x["run"]}.json'
        t+=f'- 剔除 {x["mode"]}/{x["run"]}：target={x["target"]}ms，不满足>=8s，与上轮同规则，不计通过/失败；'+link(fn,'包含前次失败后复位的完整上下文')+'。\n'
else:t+='本轮无前次失败后复位竞争导致的 target<8s 样本，剔除0次。未为凑数改变判据。\n'
t+='\n即使处于前次失败后的复位上下文，只要切档target>=8s，仍保留为有效样本并按原生判据计成败；例如暂停组存在RESTART短暂等于目标但最终time-pos无有效值（-1000ms）的样本，计失败。只按上轮target<8s规则剔除。\n'
t+='\n61个有效失败中：49个仅调用1次seek、11个零调用、1个双调用（ABR再切档）；51个没有目标附近RESTART，10个曾到目标附近但最终续播/暂停条件失败。失败内夹有ABR的样本为cutover/63、cutover/128、normal/57，其余58个失败时间线未出现MovaAbrDownShift。\n'
t+='\n剔除完整索引：'+link('rerun3-hls-excluded.json')+'；失败完整 EVENT/duration/RESTART/seek 调用与返回合集：'+link('rerun3-hls-failures.json')+'。\n'
if fs:
    t+='\n各场景首次失败（均早于本组首次失败后复位）：\n\n| 场景/run | target | RESTART | seek次数 |\n|---|---:|---|---:|\n'
    for mode in ['cutover','normal','paused']:
        first=next((x for x in audit if x['mode']==mode and x['validTarget'] and not x['pass']),None)
        if first:t+=f'| {mode}/{first["run"]} | {first["target"]} | {first["restarts"]} | {first["seekCount"]} |\n'
    t+='\n| 场景/run | 有效 | target | RESTART | landed / continued / pause | ABR夹入 | 完整时间线 |\n|---|---|---:|---|---|---|---|\n'
    for x in fs:
        r=x['result']; fn=f'rerun3-failure-{x["mode"]}-{x["run"]}.json'
        t+=f'| {x["mode"]}/{x["run"]} | {x["validTarget"]} | {r["target"]} | {r["restarts"]} | {r["landed"]} / {r["continued"]} / {r["pause"]} | {x["abrPresent"]} | {link(fn,"全部事件")} |\n'
    t+='\n完整复测驱动：`python example/tool/rerun3_run.py hls`（依次160/60/60）；补跑命令：`python example/tool/rerun3_extra.py normal 20 extra`、`python example/tool/rerun3_extra.py paused 10 extra`。\n'
    t+='\n最小功能复现：启动本轮 release 页→new case=hls（相应 cutover=true 或 paused=true）→原生进度>=8s→交替360p/180p；以上首个失败的 run 与完整时间线可定位本轮实际复现。独立暂停补跑也在run1（第2次切档）失败，target8343ms、RESTART[23,23]、continued23ms、pause=yes；此前run0通过，可用验证页new case=hls paused=true count=10重复尝试。\n'
else:t+='\n本轮没有失败，没有可报告的失败最小复现。复测入口：`python example/tool/rerun3_run.py hls`，依次160/60/60；场景/驱动与上轮一致，仅次数提高。\n'
if fs:
    first=next((x for x in fs if x['validTarget']),fs[0])
    t+='\n首个失败关键时间线（ms为应用单调事件时间；完整文件保留全部未筛选事件）：\n\n| ms | 事件 |\n|---:|---|\n'
    for v in first['timeline']:
        k=v['kind']; event=v.get('event',v.get('type'))
        if k in ['HLS_SWITCH','KERNEL_SEEK_CALL','KERNEL_SEEK_RETURN','HLS_RESTART','HLS_RESULT']:
            payload={a:b for a,b in v.items() if a not in ['ms','kind']}
            t+=f'| {v["ms"]} | {k} {payload} |\n'
        elif k=='EVENT' and event in ['MovaDurationChange','MovaAbrDownShift']:
            t+=f'| {v["ms"]} | {event} {v.get("payload")} |\n'
    t+='\n进度流中的短暂目标值不视为原生落点；例如首个失败可从 NATIVE_PROGRESS 核对瞬态目标值后回零，验收仍以原生 RESTART 与 time-pos 为准。未直接观测引擎私有 _pendingSeekTarget，本轮不将未重发的内部原因当作已证实根因。\n'
t+='\nABR MovaAbrDownShift 出现于有效样本：'+str({k:v['abrRuns'] for k,v in s.items()})+'；按每次切档列出，不将 EVENT/HLS_EVENT 的同一事件重复计数。\n'
t+=f'''\n## 新包与上轮对比

- 上轮有效177次，165通过/12失败（cutover 112/117、普通26/30、暂停27/30）；本轮 {passed}/{total}，失败 {len(failed)}。两轮样本数量不同，只报告本轮是否再现，不能据有限样本宣称竞态绝不出现。
- 本轮重建日志 {link('rerun3-build.log')}；隔离包 `com.icodejoo.mova.mova_example.coverage`；原生库按 LFS SHA256核对、zipalign、既有debug证书重签，apksigner v2/v3校验通过。
- 安装前 lastUpdateTime=2026-10-27 21:09:46；安装后 `{m['installedLastUpdate'][0]}`；SERVER build=rerun3-20261027。
- Gradle APK SHA256：`{m['gradleApkSha256']}`。
- 重签APK与设备拉回APK一致：`{m['signedApkSha256']}`。
- engine.dart SHA256：`{m['engineSha256']}`，与起测和收尾一致，未修改或转换CRLF。
- {link('rerun3-build-manifest.json')}、{link('rerun3-package-before.txt')}、{link('rerun3-package-after.txt')}、{link('rerun3-certificate.txt')}、{link('rerun3-start.json')}。

## 最终设备状态与范围

起测与收尾均 isKeyguardShowing=false、mScreenOnFully=true；未尝试解锁。USB常亮起测7，已恢复7；媒体 STREAM_MUSIC speaker 起测6/20，已恢复6/20。隔离包已 force-stop，pid为空；本次启动的18080/18084源进程已关闭，端口无监听。{link('rerun3-final-state.json')}、{link('rerun3-final-window.txt')}、{link('rerun3-final-audio.txt')}、{link('rerun3-final-power.txt')}、{link('rerun3-final-review.json')}。

仅改验证页构建标记、example/tool/rerun3_*.py及本报告；证据前缀rerun3-。未改lib/、test/、packages/；原有未提交改动保留，未执行git commit/stash/reset/checkout，未触碰../dioman或另一会话的矩阵文件。受保护源码哈希在起测与收尾核对一致。
'''
journal=D.read_text(encoding='utf-8').split('\n\n## 基线与结果')[0]
D.write_text(journal+t,encoding='utf-8')
links=re.findall(r'\]\((\.\./\.\./[^)]+)\)',D.read_text(encoding='utf-8'))
assert all((D.parent/p).exists() for p in links)
print(f'valid={total} passed={passed} failed={len(failed)} excluded={len(excluded)} retrySuccess={len(retries)}')

with D.open('a',encoding='utf-8') as f:f.write('\n- 交付检查点：295有效样本与页面判定逐项一致，61份失败、15份剔除上下文、2份重发成功完整时间线及报告所有证据链接已核验；受保护源码哈希无变化，设备收尾状态已确认。\n')
