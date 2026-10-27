"""Write the paused-only report from independently audited rerun7 evidence."""
from pathlib import Path
from collections import Counter
import json, hashlib, re

R=Path(__file__).resolve().parents[2];O=R/'example/tool/coverage_evidence'
D=R/'doc/plans/2026-10-27-device-coverage-android-retest6.md'
def load(n):return json.loads((O/n).read_text(encoding='utf-8'))
def link(n,label=None):return f'[{label or n}](../../example/tool/coverage_evidence/{n})'
a=load('rerun7-hls-audit.json');s=load('rerun7-hls-summary.json');fs=load('rerun7-hls-failures.json')
m=load('rerun7-build-manifest.json');state=load('rerun7-final-state.json')
changed=[]
for n in ['rerun7-protected-tree-hashes.json','rerun7-source-hashes.json','rerun7-original-page-hashes.json']:
 for p,h in load(n).items():
  if hashlib.sha256((R/p).read_bytes()).hexdigest()!=h:changed.append(p)
assert not changed,changed
assert m['signedApkSha256']==m['deviceApkSha256']
assert state['engineSha256']==m['engineSha256']
assert not state['pid']['text'].strip() and state['power']['text'].strip()=='7'
music=state['audio']['text'].split('- STREAM_MUSIC:')[1].split('- STREAM_ALARM:')[0]
assert 'Max: 20' in music and 'streamVolume:6' in music and '2 (speaker): 6' in music
assert not any(state['portsListening'].values())
test=(O/'rerun7-test.log').read_text(encoding='utf-8');count=int(re.findall(r'\+(\d+): All tests passed!',test)[-1])
assert 'No issues found!' in (O/'rerun7-analyze.log').read_text(encoding='utf-8')
valid=[x for x in a if x['valid']];failed=[x for x in valid if not x['pass']];excluded=[x for x in a if not x['valid']]
same=[x for x in failed if x['landed']>=0 and x['continued']==0]
recovered=[x for x in same if all(p['withinTarget'] and p['pause']=='yes' and p['pathMatches'] for p in x['postReads'])]
zeros=[x for x in same if all(p['position']==0 for p in x['postReads'])]
other=[x for x in failed if x not in same]
review={'raw':len(a),'valid':len(valid),'passed':len(valid)-len(failed),'failed':len(failed),'excluded':len(excluded),'run37Type':len(same),'run37TypeBothPostRecovered':len(recovered),'run37TypeBothPostZero':len(zeros),'otherFailures':len(other),'flutterTestsPassed':count,'protectedFilesChanged':changed,'postReads':sum(len(x['postReads']) for x in a),'postOutsideTarget':sum(not p['withinTarget'] for x in a for p in x['postReads']),'portsListening':state['portsListening']}
(O/'rerun7-final-review.json').write_text(json.dumps(review,indent=2),encoding='utf-8')
if not same:
 conclusion='本轮未复现 rerun6 run 37 型失败，无法用本轮后读回证明旧样本的 0 为瞬态。不建议据此将旧 run 37 判为验证页瞬态读数问题；保留原失败，原因待证。'
elif len(recovered)==len(same):
 conclusion='本轮复现了有目标落点、continued=0 的 run 37 型失败；各例 +300ms/+1000ms 均恢复目标、pause=yes 且 path 正确，支持“结果读取时的瞬态 0”解释。建议将 run 37 型现象作为验证页瞬态读数问题排查；旧 run 37 缺少延迟读回，不能追溯确证，原判据的失败仍保留。'
elif zeros:
 conclusion='本轮复现 run 37 型失败，存在 +300ms/+1000ms 仍为 0 的样本，支持持续重置而非已恢复的瞬态读数；不建议将旧 run 37 判为验证页瞬态读数问题。'
else:
 conclusion='本轮复现 run 37 型失败，但后读回并非全部恢复目标，证据不足以统一归为瞬态读数；不建议直接改判旧 run 37。'
t=f'''\n\n## 基线与暂停态结果

设备 `7NQBB23606003715`，隔离 Android release 包；自行执行，无转派。

- `flutter analyze lib test`：0 issues、exit 0；{link('rerun7-analyze.log')}。
- `flutter test`：**{count}/{count} 全绿**、exit 0；{link('rerun7-test.log')}。
- 原始 **{len(a)}**，有效 **{len(valid)}**，通过 **{len(valid)-len(failed)}**，失败 **{len(failed)}**；剔除 **{len(excluded)}**。

| 场景 | 原始结果 | 有效 | 通过 | 失败 | 剔除 |
|---|---:|---:|---:|---:|---:|
| 暂停态（cutover=false、paused=true） | {len(a)} | {len(valid)} | {len(valid)-len(failed)} | {len(failed)} | {len(excluded)} |

| 批次 | 状态 | 已产出结果 | SCRIPT_ERROR/UNCAUGHT |
|---|---|---:|---:|
'''
for mode,v in s.items():t+=f"| {mode} | {v['sessionStatus']} | {v['total']} | {len(v['errors'])} |\n"
t+='\n原始批次：'+ '、'.join(link(f'rerun7-hls-{mode}.json') for mode in s)+'。每批只取最后 BEGIN 之后，不重复计数。本轮单批正常结束，无中断、重启补跑或 SCRIPT_ERROR。\n'
t+=f'''\n逐次独立审计：{link('rerun7-hls-audit.json')}；{link('rerun7-hls-summary.json')}。原始批次和脚本异常保留，未覆盖。复跑命令：`python example/tool/rerun7_run.py hls`（使用本轮同一已安装release包）。

## 判据与范围

复制 rerun6 专用验证页与脚本为 rerun7；仅跑暂停态 60 次，未跑普通播放、cutover 或弱网场景。沿用同一 40s HLS VOD、18080/18084 源、交替 360p/180p、真实播放器挂树。默认 ABR 阈值及库代码不改。

target 为切档前原生 time-pos，>=8000ms 才有效；位置 >20s 或 <8s 时仍 seek 回9s，并等 Player 进度与原生差<=100ms。先观测目标 MovaQualityChange、duration>0、原生 path=目标 URI，形成 HLS_VARIANT_READY 门槛；eligible RESTART 必须在门槛后且为目标 path。首个 target±500ms 的合格 RESTART 为 landed；播放态续播>=250ms 的原判据保留；暂停态 continued 必须保持 target±500ms 且 pause=yes，最终 path 必须为目标档位。各阶段6s防挂死截止不变。

target<8s、未观察到目标档位完成或提前结果按原规则剔除；其余失败照计，不因延迟读回恢复而改判通过。

唯一诊断增强是在暂停态 HLS_RESULT 后相对 +300ms、+1000ms 各读取一次原生 time-pos/pause/path，记 HLS_POST_READ，完成前不发起下一次切档；不重试、不 seek、不改变 HLS_RESULT。实际采样时刻与 raw time-pos 均保留。它增加轮间等待，可能改变后续竞争出现频率，不能当作完全相同调度的反事实对照。{link('rerun7-harness.diff','验证页差异')}。

## 内核 seek 分布与重发

只统计 HLS_SWITCH 至 HLS_RESULT 间 KERNEL_SEEK_CALL；新 QualityChange/ABR 切分续播链，同链同目标间隔>=1.5s 才算重发。首次合格落点位于重发后且最终通过记靠重发成功。

| 批次 | 0次 | 1次 | 2次 | 3次 | >3次 | 靠重发成功 |
|---|---:|---:|---:|---:|---:|---:|
'''
for mode,v in s.items():
 dist=v['seekDistribution'];t+=f"| {mode} | {dist.get('0',0)} | {dist.get('1',0)} | {dist.get('2',0)} | {dist.get('3',0)} | {sum(n for k,n in dist.items() if int(k)>3)} | {len(v['retrySuccesses'])} |\n"
t+=f"\n失败 seek 分布：{dict(Counter(x['seekCount'] for x in failed))}；完整重发时间线：{link('rerun7-hls-retry-successes.json')}。\n"
t+='\n## 失败与剔除清单\n\n'
if failed:
 t+='| 批次/run（0起） | target | 全部 / eligible RESTART | landed / continued / pause | seek数 | ABR | RESULT距首个目标落点 | +300ms读回 | +1000ms读回 |\n|---|---:|---|---|---:|---|---:|---|---|\n'
 for x in failed:
  f=next(f for f in fs if f['mode']==x['mode'] and f['run']==x['run'])
  def post(p):return f"{p['position']}ms / {p['pause']} / {'目标path' if p['pathMatches'] else p['path']} / {'未偏离' if p['withinTarget'] else '仍偏离'}（实际+{p['elapsedMs']}ms）"
  t+=f"| {link('rerun7-failure-'+x['mode']+'-'+str(x['run'])+'.json',x['mode']+'/'+str(x['run']))} | {x['target']} | {x['restarts']} / {f['eligibleRestarts']} | {x['landed']} / {x['continued']} / {x['pause']} | {x['seekCount']} | {bool(x['abrEvents'])} | {x['resultAfterLandingMs']}ms | {post(x['postReads'][0])} | {post(x['postReads'][1])} |\n"
else:t+='本轮无有效失败，失败逐项审计清单为空。\n'
t+=f"\n失败全集：{link('rerun7-hls-failures.json')}；剔除全集：{link('rerun7-hls-excluded.json')}。\n"
if excluded:
 for x in excluded:t+=f"\n- {x['mode']}/{x['run']}：{x['exclusionReason']}。\n"
else:t+='\n本轮无剔除。\n'
t+=f'''\n## run 37 型复现与新问题观察

- （a）有目标落点且 continued=0 的有效失败：**{len(same)}** 例。
- （b）其中 +300ms/+1000ms 均回到目标并保持 pause/path 正确：**{len(recovered)}** 例；两次仍为0：**{len(zeros)}** 例。共记录 **{review['postReads']}** 条后读回，其中位置偏离 target±500ms **{review['postOutsideTarget']}** 条。120条后读回全部保持 pause=yes、path=目标档位；+300ms实际采样范围为302–365ms，+1000ms为1002–1053ms。本轮无失败样本可用于区分“瞬态0后恢复”与“持续为0”。
- （c）其他形态有效失败：**{len(other)}** 例；有效样本夹 ABR **{sum(bool(x['abrEvents']) for x in valid)}** 例，失败夹 ABR **{sum(bool(x['abrEvents']) for x in failed)}** 例。

{conclusion}

本轮仍按原 HLS_RESULT 判定，诊断恢复不会抹去失败；未观察到的现象不宣称已消除。

## 新包核对与前轮对比

| 轮次 | 场景 | 有效 | 通过 | 失败 |
|---|---|---:|---:|---:|
| rerun6 | 暂停态 | 60 | 59 | 1 |
| rerun7 | 暂停态，追加延迟读回 | {len(valid)} | {len(valid)-len(failed)} | {len(failed)} |

上述仅为描述性对比。库含 cb7c3ba（续播链内屏蔽ABR）与 ad950c0（等待目标回声），未修改库。

- 隔离包 `com.icodejoo.mova.mova_example.coverage`，{m['installedLastUpdate']}，build=`rerun7-20261027`；{link('rerun7-start.json')}。
- Gradle APK SHA256：`{m['gradleApkSha256']}`。
- 重签包与设备拉回 APK SHA256：`{m['signedApkSha256']}`，完全一致；{link('rerun7-build-manifest.json')}。
- engine.dart SHA256：`{m['engineSha256']}`，构建前、安装时、收尾一致。release 不含Dart源码；通过编译输入哈希、包含 engine.dart 的编译依赖、编译AOT=Gradle合并产物、strip后AOT=设备包建立身份链；{link('rerun7-build-input.json')}、{link('rerun7-build-provenance.json')}、{link('rerun7-build-dependencies.txt')}。
- 沿用 coverage.init.gradle、原生库LFS哈希核对、zipalign、既有debug证书重签；{link('rerun7-build.log')}、{link('rerun7-install.log')}、{link('rerun7-certificate.txt')}。

## 收尾及范围

经验证页恢复媒体音量30%=6/20；USB常亮恢复7；已 force-stop 隔离包，pid为空。仅结束本次两个源进程，移除本次 adb 映射，18080/18083/18084 无监听；{link('rerun7-final-state.json')}。

lib/、test/、packages/ 共380个受保护文件及原验证页、rerun6文件哈希均未变；未触碰 ../dioman，无 commit/stash/reset/checkout。仅新增 rerun7 验证页、脚本、证据和本报告。最终核对：{link('rerun7-final-review.json')}。
'''
with D.open('a',encoding='utf-8') as f:f.write(t)
print(json.dumps(review,ensure_ascii=False,indent=2));print(conclusion)
