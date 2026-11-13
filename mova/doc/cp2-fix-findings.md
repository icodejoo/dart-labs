# CP2 离线定性与修复

证据只读自 `E:\workspaces\wt-mova-cp2\mova`；修改仅在 cp2fix 的 mova。
不使用真机，单测不能代替设备复验。

## 1. cp2-rate：产品缺陷

`matrix-cp2-rate-resume-20261104-183441-cp2-rate.log` 的 V13b run5：
18:36:47.502 setRate(1.5) 返回时代理 state.rate=1.0，47.528 才观测到 1.5；
48.214 广告 started，48.248 广告 rate=1.0/epoch=1；52.323 正片仍为
1.0/epoch=2，55.253 的延后读数仍为 1.0。五轮一致。

丢失发生在 playAdNow 同步读取代理旧快照；无倒计时的 pending 立即进入
`_beginAd` 并设置 `_landing`，后来的正片进度也不能再更新快照。
广告计划的 1x、正片计划的显式恢复值、commit 的继承规则均按传入值执行，
A27 prepare+commit 并未自行把 1.5 改成 1.0，错误恢复值在进入广告前已保存。

修复代理 setRate 完成时发布当前生效播放器快照，并以播放器身份及 renderEpoch
隔离迟到写入。没有新增方向枚举，沿用 MovaWarmPlan.rate。
真实 Mova + FakeKernel 回归覆盖直接返回与影子提交返回，内核最后一次
setRate 参数和代理最终状态都为 1.5，广告时内核参数为 1.0。
仅撤去 lib 修复后两项均变红（期望 1.5，实际 1.0），恢复修复两项通过。

证据限制：该 rate 批次的 V13 夹具读取的是代理 rate；samples.txt 是进程采样，
没有原生 mpv speed 属性读回，不能将其写成独立原生 speed 证据。
回归在内核边界核对实际下发参数。既有断言未改写。

## 2. cp2-adpaths 中插偏差：产品缺陷，另有夹具误分类

原批次两条是 `CP2.adpaths.mp4.mid.0/.1`，尚未执行 HLS。
原生 entry/resumed：5200→4040ms（−1160ms）、5400→4320ms（−1080ms）；
续跑为 5040→4120ms（−920ms）、5200→4320ms（−880ms）。
夹具使用换指前最后一次正片原生读回，返回后要求 path 匹配且非广告，
因此没有把广告位置直接相减。异步采样有误差，但不足以解释代码中确定的冻结。
末条 entry 原生 5200ms、代理进度 4720ms，也说明采样存在额外进度滞后。

`_beginAd` 等广告就绪前设置 `_landing=true`，此时正片还在播放；
`_onProgress` 原先直接丢弃整个等待窗口的进度，`_contentResumeAt` 停在
触发 tick。后续正片计划和影子 start/seek 正确执行了这个过早目标。
修复只在 pending 且 renderEpoch 仍属于正片时跟踪进度；不重复预热，
换指后的广告进度、回正片期间旧广告进度仍不采纳。

新增 MP4/HLS × 正片影子提交/直接打开四项回归；模拟等待 1120ms，
修复前全部续播到 4000ms 而非 5120ms（偏差 −1120ms），修复后目标均精确
5120ms（替身内核边界误差 0ms）。四项在旧 lib 上均变红，既有断言未改写。
这不代表修复后真机误差已实测为零，原生采样和进度节流残差仍须设备复验。
广告 kind 覆盖 AD 记录类型造成的 ads=[] 是独立夹具缺陷，不纳入产品修复。

## 3. cp2-pod2 第二条 epoch 未增：仅夹具资源污染，未复现产品缺陷

续跑 `matrix-cp2-pod2-resume-20261104-182714-cp2-pod2.json` 前五轮均
epoch1=1、epoch2=2；第六轮第二条 path/首帧存在而 epoch2=1。
第六轮第一条首帧 43162443us、第二条 49688581us，其间多次 warming→idle；
49690267us 音频设备初始化失败，50156618us h264 decoder 初始化失败。
同批后续场景已无法起播，符合资源逐步耗尽，不能把未换指直接视作 pod 仲裁失效。

只读 `git show 996b324f:mova/example/lib/verify_auto/cp2_common.dart` 确认
实测版本注入 MovaMpvKernel 却缺少 ownsKernel:true；默认借用内核，销毁播放器
不会释放 Player。当前只读树的夹具已补该参数，不能拿其当前内容冒充实测版本。

当前 lib 的第二条 `_playAd` 在等待策略下走 prepareOwned+commitOwned。
只有影子失败/未就绪时才按既有 hardCut 契约在当前生效播放器 open；没有换渲染引擎，
renderEpoch 不增长是预期。正常路径未发现回落到主播放器 open 的问题。

新增两项诊断测试：一项连续二十轮干净 pod，每轮第二条均 1→2、独立影子提交，
第一条未收到第二条的 open，所有替身播放器均恰好释放一次；另一项注入第二条
影子初始化失败，确认释放失败影子、硬切第二条、epoch 保持 1。
两项均在既有 lib 上通过；没有可归因产品缺陷的变红回归（0 条），不改 lib，
不改既有断言，也没有新增行为需要记入 CHANGELOG。
这是离线隔离结论；不宣称单测证明了原生解码器在真机上的完整行为。

## 验证记录

开跑前执行 `Get-Process flutter_tester -ErrorAction SilentlyContinue | Stop-Process`。
`flutter analyze lib test`：0 issues。
新增 8 项（倍速 2、中插 4、pod 诊断 2），既有断言改写 0 项；
产品修复回退变红合计 6 项，pod 诊断不是产品缺陷回归。

第一次全量为 2397 通过、7 失败：全是 B09 setUp 对
`Directory('.dart_tool/b09').createTemp('cache_')` 的父目录缺失，
新 worktree 未继承运行目录。仅创建忽略目录 `.dart_tool/b09`，不改测试或断言，
再以 `flutter test --concurrency=3` 完整验证。
