"""Persist evidence-backed CP1 harness findings without changing raw verdicts."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[2]
target=root/'doc/plans/2026-11-03-cp1-results.json'
d=json.loads(target.read_text(encoding='utf-8'))
base='example/tool/coverage_evidence/'
def evidence(scene,stamp):
    stem=f'matrix-cp1-{scene}-20261103-{stamp}'
    return base+stem+'/'+stem+'-cp1-'+scene+'.json'
known=[
 dict(id='CP1-H01',classification='验证器缺陷；保留原始FAIL',phenomenon='404第3轮独立END_FILE数组为空；fatal事件、错误遮罩均已出现，buffering=false、spinnerCount=0',
    reproduction='快速404；核心终结后约35ms即CHECK并dispose，而独立FFI泵按100ms轮询',evidence=evidence('errclass','1544'),recordIndices=[255,259,262,263,264],
    suspectedLocations=['example/lib/verify_auto/cp1_errclass_auto.dart:45','lib/src/platform_impl/mpv_event_backend_ffi.dart:172'],
    suggestion='先等待独立END_FILE(reason=4)或明确采样超时再判定/释放；不得用核心fatal事件伪造原生证据；本轮不改判或补跑'),
 dict(id='CP1-H02',classification='夹具刺激冲突；BLOCKED',phenomenon='wakeswap新源HTTP约5s超时，无法获得新首帧',
    reproduction='有意延迟新源响应超过6s，超过当前原生网络超时',evidence=evidence('wakeswap','1540'),recordIndices=[65,66,74,75],
    suspectedLocations=['example/lib/verify_auto/cp1_wakeswap_auto.dart:34','example/tool/cp1_sources.py:71'],
    suggestion='新源单独设置明确大于刺激窗的网络超时，同时保留旧恢复5s竞争窗口；先证明新源实际可加载再验证7a'),
 dict(id='CP1-H03',classification='夹具/FFmpeg地址解析异常；BLOCKED，产品归因未定',phenomenon='edgepause前5次通过，第6次出现No protocol handler found to open URL /720/index20.ts及后续分片，随后path/time-pos不可读',
    reproduction='同一滑动HLS服务串行第6次重开暂停',evidence=evidence('edgepause','1542'),recordIndices=[1256,1258,1281,1539,1540],
    suspectedLocations=['example/tool/cp1_sources.py:99','example/lib/verify_auto/cp1_edgepause_auto.dart:42'],
    suggestion='夹具输出完整http://host:port分片URI并保留实际响应正文；排除根相对URI上下文丢失后再调查lib重开路径；不凭本轮断言暂停意图回归'),
 dict(id='CP1-H04',classification='恢复刺激未成立；BLOCKED',phenomenon='recovery等待120s后仍segmentEntered=false，已有63条媒体请求，无续播CHECK',
    reproduction='本地120s HLS可被快速预缓冲；播放2秒后才arm分片挂起',evidence=evidence('recovery','1610'),recordIndices=[993,994],
    suspectedLocations=['example/lib/verify_auto/cp1_recovery_auto.dart:39','example/tool/cp1_sources.py:74'],
    suggestion='在预缓冲完成前布置可确认的后续分片闸门，限制媒体预读；必须先证实segmentEntered及真实buffering，再等待stallTimeout/retry'),
 dict(id='CP1-H05',classification='原生系统字段覆盖缺口；BLOCKED',phenomenon='STG-AL00的seedBrightness/application override/displayBrightness/InsetsSource解析不完整；首轮settings brightness 27→62，归因未定',
    reproduction='系统竖屏、视频左侧亮度手势、进出全屏再释放',evidence=evidence('bblock','1559'),recordIndices=[],
    suspectedLocations=['example/tool/cp1_sources.py:133','lib/src/platform_impl/brightness_impl.dart:43'],
    suggestion='适配真实OEM字段并同时记录自动亮度模式/系统值漂移；区分应用覆盖还原和系统自动亮度，不在缺字段时宣称B04通过或盲改lib'),
 dict(id='CP1-H06',classification='备用源刺激/恢复链未证实；BLOCKED',phenomenon='primary失效刺激后出现MovaDone，sourceIndex仍0，90s内未切备用源，disabled组随页面中止未执行',
    reproduction='先成功播放/探测primary，再fail-primary',evidence=evidence('probe','1546'),recordIndices=[1560,1564,1568,1569],
    suspectedLocations=['example/lib/verify_auto/cp1_probe_auto.dart:39','example/tool/cp1_sources.py:87','lib/src/core/engine.dart:882'],
    suggestion='增加HTTP响应状态/分片失败证据，确认真实终结失败而非自然结束；分别验证错误到恢复、恢复到重探测两段，不能把未切源直接归为探测bug'),
 dict(id='CP1-H07',classification='B03页面映射覆盖缺口；BLOCKED',phenomenon='现有gap-skin patchCase仅修改顶栏，example/lib中无bottomBar/子路径或bottom子节点insertAfter刺激',
    reproduction='静态核对CP1页映射与实际已构建页面；本轮仍执行既有skin页留辅助证据',evidence='example/lib/verify_auto/coverage_gap_skin.dart',recordIndices=[],
    suspectedLocations=['example/lib/verify_auto/coverage_gap_skin.dart:1128','example/lib/verify_auto/coverage_gap_skin.dart:1145','doc/plans/2026-11-03-cp1-pages.md'],
    suggestion='增加底栏每个子节点remove/insertAfter及直播布局的真实组件树与点击检查，各3–5次；当前受构建一次约束，不补建APK，不把顶栏patch冒充B03'),
 dict(id='CP1-H08',classification='画面采样时序缺口；BLOCKED',phenomenon='S14 holding2/restored标记对应截图已落到下一S7场景；S7每循环只有单张恢复截图，不能证明持续运动',
    reproduction='日志读取线程同步执行多条adb取证，后续SHOT积压，采图晚于原标记',evidence=base+'matrix-cp1-keepalive-s7s14-formal-20261103-1620/',recordIndices=[],
    suspectedLocations=['example/tool/coverage_suite_device.py:62','example/tool/cp1_keepalive.py:44'],
    suggestion='分离快速读日志与有界采图队列，保存标记/截图时序并拒绝过期标记；恢复后采相邻帧或受前台守卫保护的短视频；本轮原生PASS仍不改成视觉PASS'),
 dict(id='CP1-H09',classification='抽帧旧页配置无效；BLOCKED',phenomenon='三次既有preview/extract页均MovaPreviewBlock(reason=platform)，无THUMB，25s等待超时；导出JPEG返回404',
    reproduction='旧页createMovaEngine(audioOnly:true)，触发预览服务audioOnly拒绝分支；不是已证明的Android抽帧器失败',
    evidence=base+'matrix-cp1-b-extract-20261103-1640/extract-results.json',recordIndices=[0,1,2],
    suspectedLocations=['example/lib/verify_auto/rerun6_coverage_new.dart:387','lib/src/core/preview/service.dart:308'],
    suggestion='改用真实挂树视频引擎，导出临时抽帧内核的原生seek结束落点与JPEG；本轮APK只构建一次，不重建/补跑到通过'),
 dict(id='CP1-H10',classification='旧skin页树快照未同步B14；保留原始FAIL',phenomenon='default/bilibili完整树与patch树均比旧期望多lockToggle@overlay；这是B14已落地的新组件',
    reproduction='既有skin组，default/bilibili各3轮；点击与挂树结果分开保留',
    evidence=base+'matrix-cp1-b-skin-20261103-1643-0-skin/cp0-result.json',recordIndices=[6,8,56,61],
    suspectedLocations=['example/lib/verify_auto/coverage_gap_skin.dart:426','example/lib/verify_auto/coverage_gap_skin.dart:1152','lib/src/ui/skins/default_skin.dart:365'],
    suggestion='更新CP1验证页的目标组件树，避免用固定sublist下标构造patch预期；保留B14的lockToggle行为，不删除产品组件来迎合旧快照；补B03专属刺激后下一构建验证'),
]
other=[f for f in d.get('defects',[]) if f.get('id') not in {f['id'] for f in known}]
d['defects']=known+other
visualStem=base+'matrix-cp1-keepalive-s7s14-formal-20261103-1620/matrix-cp1-keepalive-s7s14-formal-20261103-1620-cp1-keepalive-s7s14.round2-'
d['visualReview']=[dict(scene='S14 round2',status='BLOCKED',
    normal=dict(path=visualStem+'1793694301079520700.png',observation='彩条画面，烧入时间00:00:04.520，屏幕日志处于S14 normal'),
    holding1=dict(path=visualStem+'1793694304715023300.png',observation='视频区域黑块；屏幕日志明确holding1 entered=true vid=no'),
    holding2=dict(path=visualStem+'1793694310481265500.png',observation='实际截图已进入S7，新源POSTER与转圈；不能作为S14 holding2画面'),
    restored=dict(path=visualStem+'1793694319679949600.png',observation='实际截图已进入S7且烧入时间00:00:02.160；不能作为S14恢复后持续运动证据'),
    conclusion='黑块是本机观测事实，S14原设计为记录黑/末帧；CP0 Android无完整对应画面基线。SHOT读取/采图存在滞后，S7/S14完整视觉与运动判据未关闭。')]
d.setdefault('incidents',[])
entry=dict(kind='keepalive fixture preflight',detail='首个S7/S14 run在启动页面前因本树gitignored stall.mp4缺失退出，正式样本为0；使用原live_server.ensure_media补齐后以新run-id首次正式执行，原前置错误和清理错误均保留',
    evidence=evidence('keepalive-s7s14','1618'),fixtureEvidence=base+'cp1-legacy-fixtures.json')
if not any(i.get('kind')==entry['kind'] for i in d['incidents']):d['incidents'].append(entry)
target.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
