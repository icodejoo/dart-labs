"""Checkpoint completed edge, UI and native HLS findings before final visuals."""
from coverage_record import update
c=[]
def put(ids,status,detail):c.extend((i,status,detail) for i in ids.split())
put('A5','FAIL','batch20-edges BAD_OPEN_RESULT：recovery关闭、404返回accepted=true/threw=false，错误随后进入state/error事件；batch15-basic两实现OPEN_SYNC立即读仍旧duration40000/title，异步后归零。与矩阵同步清零/坏地址抛出预期不同；按当前异步API属契约预期差异，open true仅代表接受（N8通过）。')
put('A7','PASS','batch15-basic两实现5个精确seek误差0ms、负值落0，live0/2s组seek被拦；batch20-edges加载中寄存7s→6999ms，seekBy(+2s)→8998ms，超长1h→duration40000ms。最后一项仅测越界钳制，不作为EOF/性能判据。')
put('A9','FAIL','batch15-basic两实现越界state=-1/2未钳制；batch20-edges真实ScreenBrightness.application读回0/.25/.75/1与state逐项完全一致。FAIL限越界state契约，不是正常亮度失效。')
put('A27','PASS','batch15-ads前/中/后/手动、deferred、clicked、skip、waitsFor覆盖，batch11 pod真实换指；batch20-ad-failure：RetrySkip(maxRetries1)真实404两次failed后继续下一条，AbandonPod首次failed后直接正片。')
put('A30 F10','PASS','batch15 preview真实VTT/原生抽帧及cache两层命中、cancel/clear；batch23-preview-probe真实connectivity插件allowHeavy=true、wifiOnly获得7次thumb通知；offline把VTT源指向拒连127.0.0.1:9，抽帧兜底3次/磁盘命中1/内存命中4无崩。此处断网是缩略图源网络不可达，视频18080仍可达；未把never策略冒充断网。')
put('A17 F3','FAIL','batch23-hls-native.json：每引擎进度起点8s，监听真实FFI RESTART。首切档target8183→8143ms(-40)，后切到低档target8823而RESTART=23ms，后续15s从头推进，未续播；五切1通过4失败。ABR真实限速下降及紧接手切成功见batch15-abr，但不抵消多次手切缺陷。此前batch17/19超时及batch21瞬时读回产生假阳性，最终以该RESTART日志为准。')
put('C6','FAIL','矩阵要求“发送”，当前设计为仅展示固定host items，没有发送API/输入框（danmaku_config.dart明确Display-only）。batch16 custom配置8条定时弹幕，实际滚动截图在最终batch25补；不把设计不提供的能力称为已通过。')
put('C8','FAIL','batch22-nextup.png显示COVERAGE NEXT EPISODE和取消/立即播放，A28自然完成后连播已通过；卡片实现仅lead-time显隐，无可见数字倒计时，矩阵“NextUp倒计时”未实现。')
put('C12 U8','PASS','batch22-mini-drag：真实触屏从(800,2200)拖到(400,1200)，吸左边后rect.left=12/top434.20099/180x101.25；landscape/portrait截图显示钳回，90ms甩动后仍showing=true，无误关闭；batch16默认禁用/启用与A/B挂载、MiniClosed有记录。')
put('U1 U2','PASS','batch16 View复用/options/route/ticker/surface及卸载；batch22 Feed滚动真实视频/like回调；Default/Bilibili/Minimal/Mini与Douyin(Feed)均有PNG、components输出，patch显示PATCH VISIBLE。batch20启动日志Impeller Vulkan/OpenGLES；封面完整分支另列N15。')
put('N22','BLOCKED','已实测：hooks两实现异步失效保护；batch22 remap横滑volume50→74.12037且position5000不变，左竖滑seek5000→24000；STT失败回滚后可重试，crop零写入。缺assert开启的设备构建（本轮限定release/profile，assert关闭），不能把1503单测当真机assert通过；换源旧预览结果仍缺可控延迟服务证据。')
put('C2','BLOCKED','已在真实FLV/HLS测试durationStep、DVR窗口12s、seek退后/LiveEdgeReach/回边缘（batch15-live*、batch19-live*）；未提供可按behind URL取历史的服务，现有18081仅滑动live HLS、FLV忽略历史时间参数，不能证明urlBuilder时移语义；自定义windowResolver/autoBackToLiveOnStall完整联动仍缺此服务。')
update('批次20–23：边界、广告失败策略、真实网络探针、HLS原生结论',c,['- 每条引用的JSON含真实事件及state；HLS失败的原生path也记录，排除仅UI标签切换。','- 后续只补最终视觉与HLS swap/暂停态，当前已测数据先落盘。'])
