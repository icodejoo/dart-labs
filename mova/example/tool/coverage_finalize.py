"""Finalize the 135-row ledger and add reviewable reproductions and limits."""
import json,re
from collections import Counter,defaultdict
from pathlib import Path
from coverage_record import update,RESULT,EVIDENCE

c=[]
def put(ids,status,detail):c.extend((i,status,detail) for i in ids.split())
put('A26','PASS','batch16/22 show/showInPage/hide/close及A/B互斥、setRect读回30/90/180/110；batch25-mini-tap有MINI_TAPPED，close有MINI_CLOSED，位置继续/epoch0；isShowing与mount有日志。setRect是窗口回写矩形接口，未把它当强制移动UI的命令。')
put('C10 N16','PASS','batch22-controls.xml实际COVERAGE FIT文案；batch25-spinner-custom.png为60逻辑尺寸/8 stroke/#FFFF0000红圈，spinner-disabled.png消失；minimal无栏无手势，error-visible/error-disabled.png分别有/无原生404错误文字。默认外观见batch3及batch25 normal。')
put('U3','FAIL','batch25-route-player.png：TopBar有标题、PiP/fit/方向/全屏，无返回按钮；Android BACK能正常退路由（route-back），不是TopBar返回动作。矩阵要求的TopBar返回能力未提供；支持态PiP与真实方向切换已测，不支持平台隐藏分支没有自然设备样本。')
put('U4','PASS','batch19-live-controls.png为DVR/behind/backToLive形态；batch25 preview-during dragging=true/previewAt=13647；连续移动会防抖等待，batch26-preview-held.png在真实DOWN/MOVE后停留显示彩色VTT crop气泡/00:25。UP后正常seek、气泡消失；VOD与live栏均有真实截图。')
put('U5','FAIL','batch25-speed-button实际点击1→1.25x，为循环切档按钮，无倍速菜单；CenterPlay真实点击可播放、state及Play事件有记录，HUD亮度/音量/进度见batch16/18。FAIL限矩阵要求的菜单形态。')
put('U7','FAIL','实际通过：batch25-danmaku滚动文本；batch17四格式字幕；NextUp立即播放点击后title=Coverage vod.mp4/position40ms；广告countdown/跳过PNG且VISUAL_AD_EVENT started→clicked→skipped，语义定位SKIP_BUTTON=true；batch22 Feed双击like=true/count1。FAIL限C8中NextUp不含数字倒计时。')
put('C12 U8','PASS','batch22真实拖动吸左left12/top434.20；转屏PNG钳回。修正原甩动坐标：batch27-mini-real-fling从窗口内(200,1200)→(950,1200)90ms，仍showing=true、吸右left231.5294/top435.1814；无误关。batch25-mini-disabled-info：enabled=false时Host无小窗，isShowing仍true/mini=true是controller持有状态，符合“开关仅控制Host渲染”。')
put('N15','PASS','batch25 Feed连续帧1封面teal占92.12%，帧2首帧后0；video换源重盖占92.93%、恢复后0；audioOnly封面teal像素2079525常驻。batch28自定义posterFade=2s真实中间帧像素(500,600)：(0,150,136)→(0,99,90)→(0,37,34)→黑，证明渐隐，未用墙钟报精确时长。')
put('N22','BLOCKED','除assert外均已实测：hooks异步保护、重映射横向volume/左竖seek、STT失败回滚重试、crop零写。batch28延迟VTT BEGIN=1793072460.8985/END=2463.3994，换源在2461.4741；晚到非空thumb=0、previewCurrent=null。release两种入口及profile尝试--enable-asserts均在Flutter SDK defaultTargetPlatform/_environmentCache常量求值失败，见assert-aot-*-build-failed.log；断言设备分支不能记PASS，未改SDK/库来绕过。')
put('E1','FAIL','batch15-lifecycle.json真实序列：open清理Pause/Duration(0)/Size(0)→Play→SourceChange→Ready→Duration/Size→FirstFrame(restart)→…→Pause/Done。若按矩阵箭头Ready→Size→FirstFrame→Play严格判定则不符；Play表达请求意图、早于真实首帧，不等于播放器提前出画。生命周期F1仍无异常完成。')
put('A17 F3','FAIL','原生FFI最终版：batch23-hls-native普通首切8183→8143ms(-40)，第二切target8823但RESTART=23ms并从头走；普通5切1通过4失败。batch24-hls-native-cutover也1/5；paused第二切8263→23ms丢位置，之后目标已0附近的“通过”不算有效续播样本。ABR限速下调通过，不抵消重复手切缺陷。旧batch17/19/21的等待/瞬时读回判据作废，非库失败依据。')

notes=r'''
### 最小复现与FAIL分类

下表是同类问题合并后的复现；**FAIL编号数不是独立bug数**。特别是“矩阵契约/能力差异”不能直接理解为有效输入下播放故障。所有命令仅操作独立包 `com.icodejoo.mova.mova_example.coverage`。

| 涉及编号 | 分类与最小复现 | 本轮证据 |
|---|---|---|
| A23 | 生命周期问题：`a=createMovaEngine(audioOnly:true)`，open后`await a.dispose(); await a.dispose();`；第二次抛`[Player] has been disposed`，普通/cutover均复现。120轮首次创建/销毁完成，不能替代幂等要求。 | batch15-basic/basic-cutover.json 的A23.doubleDispose=false；batch15-dispose120.json及round20..120.meminfo.txt |
| F8/N19 | 续播问题：本地stall.mp4播放到约2.52–2.68s，有限重试`MovaRetryThenFailover`；卡顿恢复后首采样40ms并从头增长，1.5s内未回原位置，5次0通过。 | batch6-he-recovery-guard.log，HE V6；不要用旧默认无限直播重连脚本的超时冒充本缺陷 |
| A17/F3 | 续播问题：打开18084/master.m3u8，原生位置>=8s，loadQualities，先360p再180p。首切恢复，第二次原生RESTART落23ms，从头播；普通和默认关闭的cutover代理均复现，暂停态也丢位置。 | batch23-hls-native.json、batch24-hls-native-cutover/paused.json，HLS_RESTART含原生path；三模式首个切档误差[-40,0,-40]ms，第二切均失败 |
| C16 | 原生TLS兼容问题：`tlsVerify:true,tlsCaFile:<ca.pem>`，打开https://127.0.0.1:18443/vod.mp4或low/index.m3u8；合法IP SAN证书被拒。改localhost:18447合法DNS证书能播放。未定位Dart/mpv/mbedtls具体责任层。 | batch15-tls40格35符合预期；batch17-tls-probe合法DNS 6/6通过、IP 6/6失败；CA/tls属性读回；openssl verify IP证书成功 |
| A1 | 矩阵流契约差异：直接读events/states/progress/uiStates.isBroadcast为[true,false,true,false]；两个订阅仍都收到，dispose后八订阅全关闭。 | batch15-basic/basic-cutover.json STREAM_FLAGS，不是已证实的订阅互相干扰 |
| A2/E.MovaBufferChange/E.MovaSizeChange | 异步交付快照差异：订阅event时同时读`a.state`，连续更新时载荷与“接收这一刻”的最新state可不同。不能由此推断解码状态错误。 | event-audit.json；batch1-basic-cutover BufferChange 7次中3次，batch15-abr SizeChange 7次中1次不符；原始ms/engine/state齐全 |
| A5/N12 | 矩阵同步/错误契约差异：已播放40s源时`f=a.open(other);`立刻读state仍为旧duration/rendered/title，随后异步清零；恢复关闭的404 `await open`为true且不抛，错误通过event/state报告。 | batch15-basic两实现OPEN_SYNC；batch20-edges BAD_OPEN_RESULT accepted=true/threw=false。与N8的true=接受语义一致 |
| A8/A9/A12 | 越界输入契约差异：setVolume(-10/110)、setBrightness(-1/2)、setZoom(-1/0/100)的state保留输入。合法范围音量/亮度原生写回正常；maxZoom是手势上限，直接setZoom不使用该上限。 | batch15-basic及batch3-zoom JSON；音量0/50/100/30→系统0/10/20/6(max20)；batch20亮度原生0/.25/.75/1逐项一致 |
| C3/U6 | 能力假设差异：真实播放时在视频上长按1800ms，rate仍1；当前GestureLayer没有长按倍速处理。双击实际是左右±10s seek，不是播放切换。 | batch18-longpress-during/after、doubletap-seek；batch22轴向改配通过 |
| C6 | 能力假设差异：弹幕只展示宿主固定items，故意不含发送API/输入框。滚动已实际截图。 | batch25-danmaku.png；MovaDanmakuConfig设计为Display-only |
| C8/U7 | 能力假设差异：NextUp在提前窗口显示卡片及取消/立即播放，未显示数字倒计时。立即播放点击有效，自动连播另已测。 | batch22-nextup.png、batch25-nextup-click.json（新title/position40ms）；广告自身倒计时/跳过正常 |
| U3 | 能力假设差异：TopBar未提供返回按钮；路由可用Android BACK退出。 | batch25-route-player/route-back.png，TopBar组件树只有title/PiP/quality/subtitle/fit/orientation/fullscreen |
| U5 | 能力假设差异：SpeedButton点击循环倍速，未弹菜单；实际1x→1.25x。 | batch25-speed-button.json/png；CenterPlay/HUD子项通过 |
| E1 | 顺序契约差异：实际Play意图事件早于Ready/FirstFrame，不符合矩阵示意箭头的严格顺序；不能将Play当首帧证据。 | batch15-lifecycle.json LIFECYCLE数组、逐条EVENT；naturalDone=1/errors=0，F1通过 |

复跑入口（先启动本地源与adb reverse，设备亮屏解锁）：`python example/tool/coverage_suite_device.py api --name repro-launch`，再`python example/tool/coverage_device.py new --arg case=hls --name repro-hls --timeout 180`；双dispose用`basic`及`basic --arg cutover=true`；V6用`coverage_suite_device.py he --only V6 --runs 5`。库代码不改。

### BLOCKED所缺条件

- A31/C7：缺真实STT识别引擎、模型与可用下载服务。disabled/noEngine及失败回滚重试已测，未把注入的Noop派生引擎当作真实转写；SRT导出/分块存储没有真机通过证据。
- C2：现有FLV/HLS源支持播放/本地DVR窗口，未提供按behind URL返回历史时刻、且可控卡顿的服务。urlBuilder历史语义、自定义windowResolver及autoBackToLiveOnStall完整联动未完成；需要该服务才能继续，不能用忽略参数的live源冒充历史回看。
- F15：WHEP 38889/test/whep不可达，缺publisher、信令及UDP38189/relay38190映射。WHEP选项读回不等于15s真实播放。
- N22：assert启用的AOT构建在当前Flutter 3.47 SDK编译失败；release及profile日志已保存。除assert子项外，异步钩子、轴向改配、STT回滚、crop、换源旧结果丢弃均有实际证据。不能用单测结果补真机PASS。

### 与CLAUDE.md/交接结论的对照

- 单测基线为1503通过，较文档1472多31；`flutter analyze lib test` 0问题。复启基线分别见coverage_baseline_test_restart.log/analyze_restart.log；不是本轮新增库测试。
- HE V6“续播就绪修复待Android复测”：本轮仍0/5，从40ms起播放，与期望修复行为不一致。
- PiP退出state不复位的历史段落已过期：本轮展开及X均收到false/state复位；X会暂停，展开继续播。
- 历史WarmPlan方向/广告短暂用户倍速窗口/pod第二条回落：本轮广告采样1x、内容恢复2x/1.5x、pod真换指，退役dispose不复位全局方向。每项3轮，未声称穷尽所有微任务时间窗口。
- Android 404约120ms、拒连约79ms即nativeEndError，非Windows约5s；默认黑洞约5.28s先由mpv network-timeout结束，65s是Dart兜底派生值。
- keepAlive功能迁移/mediacodec-copy唤醒20/20通过，但S1跨GOP15/15仍靠grace约5s，不能将KeepAliveResume.elapsed当实际出画耗时；实际属性恢复约百余ms。该兜底受配置允许，最终F6/N20记PASS并保留信号/延迟观察。
- S14 Android holding为黑屏、恢复正常，区别于Windows保留帧；S5只测20s，漂移137/681/410ms，均值409.3ms，不能据此宣称Windows 60s约2.5s漂移已修复。
- 首帧证据使用native restart与实际事件。qoe:false零QoE、弱客户端0；完整卡顿释放后stallCount1/stallMs5468；120次首次销毁完成。上述均不以截止时间、UI标签、临近EOF seek推断性能。

### 证据与环境边界

- 所有主功能设备测试为release；profile只尝试assert构建且未安装失败产物。独立APK身份保留原示例包的数据/签名，真机仍为7NQBB23606003715。
- 原packages Android libmpv是132bytes LFS指针。仅在example/tool/coverage_native中取匹配二进制；SHA256=798cde9e27e3761dd5f8f065693e4669b5499d5807618f81a74e0d3a88dc230b，6357872bytes。JNI重定向、appId、ABI与integration_test依赖均通过tool/coverage.init.gradle，不改Android工程/库源码。
- CPU为top采样、单核百分比；USB充电下没有给出电池能耗结论。120轮RSS从227037184到247193600bytes，后60/80/100/120轮为241020928/245993472/246718464/247193600；PSS原始文件在同目录。不声称绝对无泄漏。
- 系统没有screenrecord（inaccessible or not found），已用adb PNG连拍取代；posterFade=2s有中间颜色而非只拍前后两态。主观手感、真实人耳听感未作测量结论。
- 每个主台账编号只有一个结论；批次历史中旧锁屏/构建阻塞、验证器误判及中间计数均保留，**当前台账和本节优先**。旧HE V5默认无限重试、字幕asset缺失/挂载时dispose、HLS等待Seeked/跨引擎latest/瞬时读回均是验证器问题，未作为库bug。
'''.strip().splitlines()
update('最终批次：可视证据核对、FAIL复现与BLOCKED条件',c,notes)

text=RESULT.read_text(encoding='utf-8')
text=re.sub(r'\n{3,}','\n\n',text)
text=text.replace('**执行中说明**：下方批次 0 的锁屏台账为当时快照，后续批次优先。设备后来已解锁（两处 `isKeyguardShowing=false`）。release 构建仍在处理原生依赖，真机用例即将开始，最终计数待更新。','**最终口径**：下方主台账已按135个编号完成判定。设备解锁后完成release测试，历史锁屏/构建记录仅为过程快照；详细FAIL最小复现、BLOCKED条件和CLAUDE对照见文末“最终批次”。')
rows=re.findall(r'^\| ((?:[ACUFN]\d+|E\.[A-Za-z]+|E[12])) \| (PASS|FAIL|BLOCKED) \| (.*?) \|$',text,re.M)
assert len(rows)==135 and len({r[0] for r in rows})==135,len(rows)
assert not any('等待对应真机批次' in r[2] or '尚未归档' in r[2] for r in rows)
counts=defaultdict(Counter)
for ident,status,_ in rows:counts[ident[0]][status]+=1
summary=['## 最终汇总','', '| 组 | 总数 | PASS | FAIL | BLOCKED |','|---|---:|---:|---:|---:|']
for group in ['A','C','E','U','F','N']:
    n=counts[group];summary.append(f"| {group} | {sum(n.values())} | {n['PASS']} | {n['FAIL']} | {n['BLOCKED']} |")
summary+=['','FAIL编号：'+', '.join(i for i,s,_ in rows if s=='FAIL')+'。','', 'BLOCKED编号：'+', '.join(i for i,s,_ in rows if s=='BLOCKED')+'。','', 'FAIL含真实播放/生命周期问题及矩阵契约/能力差异，文末分开列最小复现；不代表同样数量的独立bug。全部原始证据在 `example/tool/coverage_evidence/`，每批均已追加检查点。','']
first=text.find('\n\n',text.find('> 当前有效总计'))
text=text[:first]+'\n\n'+'\n'.join(summary)+text[first:]
RESULT.write_text(text,encoding='utf-8')
(EVIDENCE/'final-ledger.json').write_text(json.dumps({'rows':[{'id':i,'status':s,'evidence':d} for i,s,d in rows],'groups':counts},ensure_ascii=False,indent=2),encoding='utf-8')
print('FINAL_COUNTS',dict(Counter(s for _,s,_ in rows)))
