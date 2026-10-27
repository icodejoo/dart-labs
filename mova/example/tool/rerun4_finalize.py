"""Generate the final report from independently audited device evidence."""
from pathlib import Path
from collections import Counter
import json, hashlib, re, socket

H=Path(__file__).resolve().parent; R=H.parents[1]; O=H/'coverage_evidence'
D=R/'doc/plans/2026-10-27-device-coverage-android-retest3.md'
def load(n): return json.loads((O/n).read_text(encoding='utf-8'))
def link(n,label=None): return f'[{label or n}](../../example/tool/coverage_evidence/{n})'

s=load('rerun4-hls-summary.json'); audit=load('rerun4-hls-audit.json')
fs=load('rerun4-hls-failures.json'); m=load('rerun4-build-manifest.json')
state=load('rerun4-final-state.json')
valid=[x for x in audit if x['valid']]; failed=[x for x in valid if not x['pass']]
excluded=[x for x in audit if not x['valid']]; retries=[x for x in valid if x['retrySuccess']]
changed=[]
for n in ['rerun4-protected-tree-hashes.json','rerun4-source-hashes.json']:
    for p,h in load(n).items():
        if not (R/p).exists() or hashlib.sha256((R/p).read_bytes()).hexdigest()!=h: changed.append(p)
assert not changed,changed
assert m['signedApkSha256']==m['deviceApkSha256']
assert not state['pid']['text'].strip() and state['power']['text'].strip()=='7'
music=state['audio']['text'].split('- STREAM_MUSIC:')[1].split('- STREAM_ALARM:')[0]
assert 'Max: 20' in music and 'streamVolume:6' in music and '2 (speaker): 6' in music
ports={}
for port in [18080,18084]:
    with socket.socket() as sock: ports[str(port)]=sock.connect_ex(('127.0.0.1',port))==0
assert not any(ports.values())
review={'protectedFilesChanged':changed,'sourcePortsListening':ports,'valid':len(valid),
        'passed':len(valid)-len(failed),'failed':len(failed),'excluded':len(excluded),'retrySuccess':len(retries)}
(O/'rerun4-final-review.json').write_text(json.dumps(review,indent=2),encoding='utf-8')
labels={'cutover':'cutover 代理','normal':'普通播放','paused':'暂停态'}
t=f'''

## 基线与 F3/A17 结果

设备 `7NQBB23606003715`，隔离 Android release 包；由当前 Codex 自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；{link('rerun4-analyze.log')}。
- `flutter test`：**1517/1517 全绿**、exit 0；{link('rerun4-test.log')}。
- 有效 **{len(valid)}**，通过 **{len(valid)-len(failed)}**，失败 **{len(failed)}**；剔除 {len(excluded)}，不计成败。

| 场景 | 原始尝试 | 有效 | 通过 | 失败 | 剔除 | 其中harness-invalid |
|---|---:|---:|---:|---:|---:|---:|
'''
for base,label in labels.items():
    a=[x for x in audit if x['mode'].startswith(base)]; v=[x for x in a if x['valid']]
    assert len(v)>=(150 if base=='cutover' else 60)
    t+=f"| {label} | {len(a)} | {len(v)} | {sum(x['pass'] for x in v)} | {sum(not x['pass'] for x in v)} | {len(a)-len(v)} | {sum(x['earlyResult'] or x['harnessInvalid'] for x in a)} |\n"
t+=f"| 合计 | {len(audit)} | {len(valid)} | {len(valid)-len(failed)} | {len(failed)} | {len(excluded)} | {sum(x['earlyResult'] or x['harnessInvalid'] for x in audit)} |\n"
t+='\n| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR |\n|---|---|---:|---:|\n'
for mode,v in s.items():t+=f"| {mode} | {v['sessionStatus']} | {v['total']} | {len(v['errors'])} |\n"
t+='\n首批cutover/75目标流打开失败、无切档门槛，归harness-invalid；下一轮尚未发生HLS_SWITCH的9秒复位等待20秒后超时，仅记会话中断，不虚造一次切档样本。其余批次正常结束；此前已完成样本全部保留。\n'
t+='\n中断完整上下文：'+link('rerun4-interrupted-session.json')+'；原生打开失败是保留的异常事实，按未过门槛规则剔除不代表认定其由harness造成。\n'
t+='\n原始批次：'+'、'.join(link(f'rerun4-hls-{mode}.json') for mode in s)+'。每份取最后BEGIN之后，累计历史不重复计数。逐次表 '+link('rerun4-hls-audit.json')+'；分批汇总 '+link('rerun4-hls-summary.json')+'。\n'
t+='''
## 判据及验证页修正

沿用同一40s HLS VOD与18084 high/low，交替360p/180p，真实播放器挂树；cutover enabled=true，经switchQuality切档。target为切档前mpv time-pos，>=8000ms才有效；原生位置>20s或<8s时仍seek回9s，并等Player进度与原生差<=100ms。ABR配置未改。

播放与暂停统一先观测目标MovaQualityChange、duration>0且原生path等于目标URI，记录HLS_VARIANT_READY；随后开始观测。原始RESTART全部保留，eligible标记已过门槛且path为目标的读回。landed取这些RESTART中首个target±500ms；播放态mpv time-pos实际比landed增加>=250ms且pause=no；暂停态保持target±500ms且pause=yes；最终path还须为目标档位。门槛、落点和续播各保留6s防挂死截止，没有放宽500ms/250ms判据，也不按墙钟推算位置。

任何未观察到目标档位完成、或结果早于该时刻的样本均harness-invalid单列；target<8s沿用上轮复位竞争规则剔除。其余失败即使处在复位上下文或夹有ABR仍计失败，不为凑数改判据。
'''
old=load('rerun3-hls-audit.json')
oldzero=[x for x in old if x['validTarget'] and x['mode'].startswith('paused') and x['seekCount']==0 and not x['pass']]
expected=lambda x:'/high/index.m3u8' if x['run']%2==0 else '/low/index.m3u8'
priorHarness=load('rerun4-prior-harness-review.json')
oldkind=[x for x in priorHarness if x['wrongPathRestart']]
newkind=[x for x in valid if x['paused'] and x['seekCount']==0 and not x['pass'] and x['suppressedOldPathCandidates']]
t+=f"\n修验证页前后分开记账：rerun3有{len(oldzero)}个有效暂停失败为0次seek，其中{len(oldkind)}个曾将旧档位RESTART当成目标落点，符合上轮复盘的提前采样类型；本轮有效样本中同类型{len(newkind)}个，结果早于切档完成/无门槛的harness-invalid共{sum(x['earlyResult'] or x['harnessInvalid'] for x in audit)}个（已排除）。本轮抑制了{sum(bool(x['suppressedOldPathCandidates']) for x in audit)}个样本中的旧path目标附近RESTART候选。两轮同时更改了库与验证页，不把全部改善归因于验证页，也未重跑旧验证页构建。\n"
t+='\n旧9例逐次延迟、错误RESTART path与duration复核：'+link('rerun4-prior-harness-review.json')+'。\n'
t+='\n| 类型 | rerun3有效失败 | rerun4有效失败 |\n|---|---:|---:|\n'
for label,predicate in [('仅1次seek且无目标落点',lambda x:x['seekCount']==1 and x['landed']<0),('0次seek',lambda x:x['seekCount']==0),('曾有目标落点但最终失败',lambda x:x['landed']>=0)]:
    t+=f"| {label} | {sum(predicate(x) for x in old if x['validTarget'] and not x['pass'])} | {sum(predicate(x) for x in failed)} |\n"
t+='''
## 内核 seek 分布与重发

每次统计HLS_SWITCH至HLS_RESULT间RetestKernel的KERNEL_SEEK_CALL，排除切档前复位；0次及>3次单列。靠重发成功：同一QualityChange/ABR分段内、同目标、调用间隔>=1.5s，首次合格落点发生在重发之后且最终通过。新QualityChange或ABR分割续播链，避免把ABR切档seek误当重发；该定义为事件顺序证据，没有关闭重发的反事实对照。

| 场景 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
'''
for base,label in list(labels.items())+[('', '合计')]:
    v=[x for x in valid if x['mode'].startswith(base)]; q=Counter(x['seekCount'] for x in v)
    t+=f"| {label} | {q[0]} | {q[1]} | {q[2]} | {q[3]} | {sum(n for k,n in q.items() if k>3)} | {sum(x['retrySuccess'] for x in v)} |\n"
t+='\n本轮36个成功样本在重发之前没有合格RESTART，重发之后才落点并通过；不能把这些成功全部归于第一层。暂停态旧档位提前采样的9例类型未再现。全部38个有效失败均夹有ABR并最终path偏离请求档位；未再现无ABR的单次seek后一直停在23ms失败形态。整体仍未达到全通过验收，不能把ABR夹入失败忽略。\n'
t+='\n仍失败样本seek次数分布：'+str(dict(sorted(Counter(x['seekCount'] for x in failed).items())))+'。\n'
t+='\n| 仍失败场景 | 0次 | 1次 | 2次 | 3次 | >3次 |\n|---|---:|---:|---:|---:|---:|\n'
for base,label in labels.items():
    q=Counter(x['seekCount'] for x in failed if x['mode'].startswith(base))
    t+=f'| {label} | {q[0]} | {q[1]} | {q[2]} | {q[3]} | {sum(n for k,n in q.items() if k>3)} |\n'
three=[x for x in failed if x['threeAttemptChains']]
t+=f"\n有效失败中，共{sum(x['seekCount']>=3 for x in failed)}个样本切档窗口含>=3次调用；其中确认同一续播链共尝试3次（首发+2次重发）仍失败为{len(three)}个："+str([(x['mode'],x['run']) for x in three])+'。总调用数可能含ABR二次切档，不能直接等同校验链3次。\n'
t+=f"\n靠重发成功 **{len(retries)}** 次，逐次完整时间线索引 "+link('rerun4-hls-retry-successes.json')+'；具体文件：'+'、'.join(link(f"rerun4-retry-success-{x['mode']}-{x['run']}.json",f"{x['mode']}/{x['run']}") for x in retries)+'。\n'
t+='\n## 剔除、失败与完整时间线\n\n'
if excluded:
    for x in excluded:
        t+=f"- {x['mode']}/{x['run']}，target={x['target']}ms："+'；'.join(x['exclusionReason'])+'；'+link(f"rerun4-excluded-{x['mode']}-{x['run']}.json",'完整上下文')+'。\n'
else: t+='本轮无剔除样本。\n'
t+='\n剔除全集 '+link('rerun4-hls-excluded.json')+'；失败EVENT、duration、全部RESTART、原生progress及seek调用/返回全集 '+link('rerun4-hls-failures.json')+'。\n'
if fs:
    t+='\n| 场景/run(0起) | target | 全部RESTART | landed/continued/pause | seek数 | ABR夹入 | 完整时间线 |\n|---|---:|---|---|---:|---|---|\n'
    for x in fs:
        r=x['result'];t+=f"| {x['mode']}/{x['run']} | {r['target']} | {r['restarts']} | {r['landed']}/{r['continued']}/{r['pause']} | {r['seekCount']} | {x['abrPresent']} | "+link(f"rerun4-failure-{x['mode']}-{x['run']}.json",'全部事件')+' |\n'
    first=fs[0];r=first['result']
    t+=f"\n本轮最小已观察复现：启动本轮release页，new case=hls，按场景设置cutover=true或paused=true；等原生位置>=8s，交替360p/180p。首个有效失败为{first['mode']}/{first['run']}（第{first['run']+1}次），target={r['target']}ms，RESTART={r['restarts']}，最终path={r['path']}；ABR夹入={first['abrPresent']}。这是本轮观察到的最短失败前缀，不保证每次固定轮次触发。\n"
    t+='\n首个失败关键时间线（完整文件保留全部EVENT/duration/progress）：\n\n| ms | 事件 |\n|---:|---|\n'
    for v in first['timeline']:
        if v['kind'] in ['HLS_SWITCH','HLS_VARIANT_READY','HLS_RESTART','KERNEL_SEEK_CALL','KERNEL_SEEK_RETURN','HLS_RESULT'] or v['kind']=='HLS_EVENT' and v.get('type') in ['MovaQualityChange','MovaDurationChange','MovaAbrDownShift']:
            t+=f"| {v['ms']} | {v['kind']} "+str({k:a for k,a in v.items() if k not in ['ms','kind']})+' |\n'
else: t+='\n本轮无失败，无法提供本轮失败最小复现。\n'
t+='\n失败中夹有MovaAbrDownShift：'+str([(x['mode'],x['run']) for x in fs if x['abrPresent']])+'；其余失败未观察到该事件。仅以HLS_EVENT计数，同一事件的EVENT副本不重复计数。\n'
t+=f"\n有效失败中夹ABR {sum(bool(x['abrEvents']) for x in failed)}例、无ABR {sum(not x['abrEvents'] for x in failed)}例；最终path不等于目标 {sum(not x['path'].endswith(expected(x)) for x in failed)}例。仍以本轮实际事件描述残余形态，不将总seek数直接解释成同一重发链。\n"
t+='\n复测命令：`python example/tool/rerun4_run.py hls`（160/60/60），补跑使用`python example/tool/rerun4_extra.py <cutover|normal|paused> <count> extra`，每批独立记录。本轮首批中断后实际使用`python example/tool/rerun4_continue.py`，重启同一包后依次独立补跑cutover90、normal60、paused60。\n'
before=(O/'rerun4-package-before.txt').read_text(encoding='utf-8')
beforetime=next(x.strip() for x in before.splitlines() if 'lastUpdateTime=' in x)
t+=f'''
## 新包核对与前两轮对比

- rerun2：165/177通过、12/177失败（6.78%）；rerun3：234/295通过、61/295失败（20.68%）；本轮：{len(valid)-len(failed)}/{len(valid)}通过、{len(failed)}/{len(valid)}失败（{len(failed)/len(valid)*100:.2f}%）。场景数、验证页和库版本不同，比例是描述性对比，不能作为单独因果推断。
- 构建沿用Gradle初始化脚本、LFS原生库SHA256核对、zipalign与既有debug证书重签；{link('rerun4-build.log')}、{link('rerun4-certificate.txt')}。
- 独立包 `com.icodejoo.mova.mova_example.coverage`；安装前`{beforetime}`，安装后`{m['installedLastUpdate'][0]}`；SERVER build=`{m['buildMarker']}`，{link('rerun4-start.json')}。
- Gradle APK SHA256：`{m['gradleApkSha256']}`。
- 重签APK及设备拉回APK SHA256相同：`{m['signedApkSha256']}`；{link('rerun4-build-manifest.json')}。
- engine.dart SHA256：`{m['engineSha256']}`，起测/安装/收尾一致。受保护lib/test/packages文件与起测哈希逐项一致，未改库代码、未转换engine.dart的CRLF。

## 收尾及范围

起测：isKeyguardShowing=false、mScreenOnFully=true；USB常亮7；STREAM_MUSIC speaker=6/20。收尾：隔离包force-stop、pid为空；USB常亮恢复7、媒体音量恢复6/20；屏幕仍完全亮起且无锁屏。没有尝试解锁。本次启动的18080/18084本地源已结束，端口无监听。{link('rerun4-final-state.json')}、{link('rerun4-final-window.txt')}、{link('rerun4-final-audio.txt')}、{link('rerun4-final-review.json')}。

本轮仅修改example/lib验证页、example/tool的rerun4脚本与证据及本新文档；不触碰另一会话的四个矩阵文件和../dioman，未执行git commit/stash/reset/checkout。证据前缀rerun4-。
'''
t+='\n结论：'+(f'本轮仍有{len(failed)}/{len(valid)}有效失败，重发有成功证据但尚未消除F3/A17换档续播失败。' if failed else f'本轮{len(valid)}个有效样本全通过，未再现此前失败；有限样本不证明竞态永不发生。')+'\n'
journal=D.read_text(encoding='utf-8').split('\n\n## 基线与 F3/A17 结果')[0]
D.write_text(journal+t,encoding='utf-8')
links=re.findall(r'\]\((\.\./\.\./[^)]+)\)',D.read_text(encoding='utf-8'))
assert all((D.parent/p).exists() for p in links)
with D.open('a',encoding='utf-8') as f:f.write('\n- 交付检查点：有效样本最低数、逐次判据、全部失败/剔除/重发证据、报告链接及受保护源码哈希已核验；设备与源已收尾。\n')
print(json.dumps(review,ensure_ascii=False,indent=2))
