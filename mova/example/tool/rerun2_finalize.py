"""Write the reviewed Android comparison and per-failure evidence index."""
from pathlib import Path
import json,hashlib
H=Path(__file__).resolve().parent;R=H.parents[1];O=H/'coverage_evidence';D=R/'doc/plans/2026-10-27-device-coverage-android-retest.md'
def load(name):return json.loads((O/name).read_text(encoding='utf-8'))
s=load('rerun2-hls-summary.json');fs=load('rerun2-hls-failures.json');manifest=load('rerun2-build-manifest.json');state=load('rerun2-final-state.json')
assert sum(x['validTotal'] for x in s.values())==177
assert sum(x['validFailed'] for x in s.values())==12
assert len(fs)==12
hashes=load('rerun2-source-hashes.json')
assert all(hashlib.sha256((R/p).read_bytes()).hexdigest()==v for p,v in hashes.items())
def link(name,label=None):return f'[{label or name}](../../example/tool/coverage_evidence/{name})'
def rows(name):
 d=load(name);i=max(i for i,x in enumerate(d['records']) if x.get('kind')=='BEGIN');return d['records'][i:]
a23=[x for x in rows('rerun2-a23.json') if x['kind']=='DISPOSE_RESULT'];assert len(a23)==4 and all(x['exception'] is None for x in a23)
zooms={v:next(x for x in rows('rerun2-a12-'+v+'.json') if x['kind']=='VIDEO')['state']['zoom'] for v in ['-1','0','NaN','100']}
assert zooms=={'-1':1.0,'0':1.0,'NaN':1.0,'100':100.0}
for phase in ['holding','expanded']:
 rr=rows('rerun2-mini-pip-repro-'+phase+'.json');m=next(x for x in rr if x['kind']=='MINI_INFO');v=next(x for x in rr if x['kind']=='VIDEO')
 assert m['apiNull'] and not m['showing'] and m['mount']=='none' and not v['state']['mini']
 assert v['state']['pip']==(phase=='holding')
t='''

## 最终结论与基线

本轮按五项列出 F3/A17、A15、F5、A23、A12；A15/F5 共用一次完整小窗/PiP流程，不重复计算样本。全部为设备 `7NQBB23606003715` 的 Android release 实测，自行执行。

- `flutter analyze lib test`：**0 issues，exit 0**。
- `flutter test`：**1516/1516 PASS，exit 0**。
- 基线完整日志：'''+link('rerun2-analyze.log')+'、'+link('rerun2-test.log')+'''。

| 项目 | 结论 | 本轮次数与观察 | 证据 |
|---|---|---|---|
| F3/A17 换档续播 | **FAIL** | 有效177次，165通过/12失败；cutover 112/117、普通播放26/30、普通暂停27/30 | '''+link('rerun2-hls-summary.json')+'、'+link('rerun2-hls-audit.json')+'、'+link('rerun2-hls-failures.json')+''' |
| A15 小窗随api收起 | **PASS** | 1条完整MiniHost→enterPip→展开；mini=false时controller api=null、showing=false、mount=none，界面无残留小窗 | '''+link('rerun2-mini-pip-repro-holding.json')+'、'+link('rerun2-mini-pip-repro-expanded.png')+''' |
| F5 小窗/PiP衔接 | **PASS** | 同一条流程；enterPip=true，原生pinned，展开pip=false，小窗仍收起 | '''+link('rerun2-mini-pip-repro-enter.activity.txt')+'、'+link('rerun2-mini-pip-repro-expanded.json')+''' |
| A23 重复dispose | **PASS** | 普通/cutover enabled代理各audioOnly打开40s源并连续dispose两次，4/4正常；两个第二次调用异常均0 | '''+link('rerun2-a23.json')+''' |
| A12 缩放下限 | **PASS** | 4/4：-1/0/NaN→1.0、100→100.0；真实挂树640×360；-1/0截图已目视确认不塌缩 | '''+link('rerun2-a12--1.png')+'、'+link('rerun2-a12-0.png')+'、'+link('rerun2-a12-NaN.json')+'、'+link('rerun2-a12-100.json')+''' |

## 新构建与设备安装一致性

- Gradle从当前工作区重新构建 `lib/main_coverage_api.dart`，`assembleRelease`成功（1m1s、777 tasks，33 executed）；日志 '''+link('rerun2-build.log')+'''。
- 隔离applicationId：`com.icodejoo.mova.mova_example.coverage`。未替换原示例包。
- 复用上一轮严格LFS哈希核对重打包代码；zipalign后以既有 `C:/Users/jelon/.android/debug.keystore` 重签，apksigner v2/v3校验通过；`adb install -r`成功。
- 证书SHA256：`c0f7b57aa2f5478d9a5977b2ae18fa15a3ec13a620004429a9f67ffc3638c2e3`。
- 安装前lastUpdateTime为`2026-10-27 19:12:43`，本轮为`2026-10-27 21:09:46`；运行页SERVER返回`build=rerun2-20261027`。
- 原始Gradle APK SHA256：`'''+manifest['gradleApkSha256']+'''`。
- 重签APK与设备安装后拉回的base.apk SHA256完全相同：`'''+manifest['signedApkSha256']+'''`。
- 运行时库来源engine.dart SHA256：`'''+manifest['engineSha256']+'''`；收尾一致，本轮未临时改动库文件。
- 清单与安装证据：'''+link('rerun2-build-manifest.json')+'、'+link('rerun2-install.log')+'、'+link('rerun2-certificate.txt')+'、'+link('rerun2-package-after.txt')+'、'+link('rerun2-start.json')+'''。

## F3/A17 计数、判据与复现

| 场景 | 原始尝试 | 不满足>=8s而剔除 | 有效次数 | 通过 | 失败 | 最低有效target |
|---|---:|---:|---:|---:|---:|---:|
'''
for mode,label in [('cutover','cutover长进程首批'),('cutover-extra','cutover补跑'),('normal','普通引擎播放'),('paused','普通引擎暂停')]:
 x=s[mode];t+=f'| {label} | {x["total"]} | {len(x["invalidTargets"])} | {x["validTotal"]} | {x["validPassed"]} | {x["validFailed"]} | {x["minValidTarget"]}ms |\n'
t+='''| 合计 | 180 | 3 | **177** | **165** | **12** | >=8000ms |

- 首批cutover的run55/67/97在前次失败后的seek复位竞争中target读回0；页面原始pass=true被审计否决，三次仅保留原始证据，不计有效成功/失败，也不计要求次数。补跑20次全有效且全通过，cutover累计有效117次，满足至少100次；普通/暂停各30次满足要求。早期执行检查点中的148/160是原始计数，以本节有效数为准。
- 同一40s本地HLS VOD，18084提供`example/tool/rerun-sources/hls/master.m3u8`及high/low；交替360p/180p，真实MovaPlayer挂树。代理`MovaCutoverConfig(enabled:true)`；切档经代理switchQuality，未用cutoverTo代替。
- target使用切档前mpv `time-pos`，有效样本必须>=8s；原生位置>20s或失败后<8s时seek回9s，避开EOF。同步等待Player进度与原生读回相差<=100ms。三次入组竞争已明确剔除。
- 每次保存target、档位、path、全部原生RESTART序列、landed、continued、pause，以及EVENT/duration、Player原生progress、实际内核seek调用/返回。`RetestKernel`只在验证页继承并观测原实现，没有改动lib。
- landed取RESTART序列中首个target±500ms读数；播放态continued必须由mpv time-pos实际增加>=250ms且pause=no，暂停态须保持target±500ms且pause=yes。所有通过项另核对原生path为目标档位。原生落点等待/继续推进各6s截止只防挂死，未用墙钟推算播放进度。
- 全部原始尝试：'''+link('rerun2-hls-cutover.json')+'、'+link('rerun2-hls-normal.json')+'、'+link('rerun2-hls-paused.json')+'、'+link('rerun2-hls-cutover-extra.json')+'''；各自包含本进程累计历史，审计按最后BEGIN划分本组。
- 逐次审计：'''+link('rerun2-hls-audit.json')+'；12次失败完整EVENT时间线合集：'+link('rerun2-hls-failures.json')+'''。每次失败还独立保存下表链接中的完整未筛选时间线。

最小功能复现：启动本轮release页→`new case=hls cutover=true count=100`→等原生进度>=8s→交替360p/180p。首个失败为首批cutover run42（第43次），此前没有失败后的复位：target19783ms，duration已40000ms，真实seek调用19783ms后RESTART仍[23,23]，continued4423ms。普通引擎和暂停态也能复现，无需PiP、小窗或其他UI动作。完整驱动：`python example/tool/rerun2_run.py hls`（会依次跑100/30/30）；同入口可用`coverage_device.py new --arg case=hls --arg cutover=true --arg count=100`。

首个失败关键时间线（ms为该app进程单调事件时间）：

| 事件时间ms | 实际事件/原生读回 |
|---:|---|
| 95086 | switch→360p，target=19783，streamPosition=19783，pause=no |
| 95187 | MovaDurationChange(0) |
| 95200 | MovaQualityChange(360p) |
| 95551 | MovaDurationChange(40000) |
| 95693 | MovaSizeChange(640×360) |
| 95746 | KERNEL_SEEK_CALL(19783)；首个RESTART读回23ms |
| 96247 | KERNEL_SEEK_RETURN(19783) |
| 96349 | MovaDurationChange(40007) |
| 96764 | 第二个RESTART仍23ms |
| 101217 | landed=-1，continued=4423，pause=no，FAIL |

这证实修复后仍有“seek确实调用，但RESTART仍停23ms并从头推进”的残余路径。另有一次未观察到换档续播seek，一次先到目标又回到23ms。上述为事件观察，不能据此断言新的根因已经定位。normal run10处于前次失败后的复位竞争，原生最终path仍low而目标为high，且continued不足，明确计失败，不把早期9023ms的RESTART误记为通过。

### 所有失败与完整时间线索引

run为从0起的轮次；target/RESTART/landed/continued单位均ms；`landed=-1`表示没有目标附近RESTART。每个JSON包含该次从HLS_SWITCH到HLS_RESULT之间所有EVENT、duration、progress、seek调用/返回和RESTART；原始整组文件保留前后上下文。

| 场景/run | target | 全部RESTART | landed | continued / pause | 实际seek目标 | 完整时间线 |
|---|---:|---|---:|---|---|---|
'''
for f in fs:
 r=f['result'];seeks=[str(x['target']) for x in f['timeline'] if x.get('kind')=='KERNEL_SEEK_CALL'];name=f'rerun2-failure-{f["mode"]}-{f["run"]}.json'
 t+=f'| {f["mode"]}/{f["run"]} | {r["target"]} | {r["restarts"]} | {r["landed"]} | {r["continued"]} / {r["pause"]} | {", ".join(seeks) or "未观察到调用"} | {link(name,"全部事件")} |\n'
t+='''
## 与上一轮对比

| 项目 | 上一轮Android | 本轮Android | 对比结论 |
|---|---|---|---|
| F3/A17 | 39/40，1次FAIL；target10183→RESTART[23,23] | 165/177有效通过，12次FAIL；仍有[23,23]、无seek、到目标后回零等形态 | **仍未修复到可验收**；两轮样本量/组别与观测截止不同，不能把比例直接当性能退化结论 |
| A15 | mini=false但controller showing=true/persistent，展开残留 | 进入PiP即api=null/showing=false/none，展开保持 | FAIL→PASS |
| F5 | MiniHost/PiP互斥衔接失败 | enterPip返回true、原生pinned、展开复位，无App小窗残留 | FAIL→PASS |
| A23 | 两种引擎二次dispose抛[Player] has been disposed | 两种引擎二次均正常，4/4调用无异常 | FAIL→PASS |
| A12 | -1/0原值保留，画面可塌缩；100接受 | -1/0/NaN均1.0且正常显示；100保持100 | 下限保护FAIL→PASS，100行为保持 |

上一轮依据：`doc/plans/2026-10-27-device-coverage-rerun.md`及其rerun-*原始证据。Windows复测1516全绿、A23/A12 PASS与本轮一致；Windows无法复现F3竞态，本轮Android已实际复现，不能用Windows结果覆盖本轮FAIL。本轮不改库、不做forcePark=false对照构建。

## 最终设备状态与工作区范围

- 起测与收尾都确认`isKeyguardShowing=false`、`mScreenOnFully=true`；未解锁设备、未锁屏硬跑。
- 隔离测试包已`am force-stop`，`pidof`为空；USB常亮已恢复**7**，媒体音量speaker/streamVolume为**6/20**。
- 本次自启18080/18084两个HTTP源进程已结束，收尾检查这两个端口无监听；未停止原有adb转发及其他应用/进程。
- 完整最终设备状态：'''+link('rerun2-final-state.json')+'、'+link('rerun2-final-window.txt')+'、'+link('rerun2-final-audio.txt')+'、'+link('rerun2-final-power.txt')+'、'+link('rerun2-final-pid.txt')+'''。
- 修改仅为本报告、`example/lib/main_coverage_api.dart`、`example/lib/verify_auto/coverage_new.dart`及`example/tool/rerun2_*.py`验证脚本；证据均`example/tool/coverage_evidence/rerun2-*`。未执行git commit/stash/reset/checkout，未触碰../dioman。
- `engine.dart`、`test/core/engine_test.dart`、`mini.dart`的本轮观测哈希与收尾逐项一致，原工作区改动保留。''' +link('rerun2-source-hashes.json')+'''；本轮没有临时修改或换行转换库文件。

- 最终报告检查点：已从原始事件独立复算177个有效样本，12个失败各自完整时间线已保存；A15/F5、A23、A12逐值/逐阶段审计与截图检查完毕，设备收尾状态已确认。
'''
with D.open('a',encoding='utf-8') as f:f.write(t)
print('Report written',D)
