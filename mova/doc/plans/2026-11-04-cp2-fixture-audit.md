# CP2 续跑夹具审计

以下修复仅位于 example，不修改 lib。原 APK（SHA-256 `492634c5f804abf3f989e2b204eb97d9f30d980b5a6228cb4393c8fe6290d53c`）不包含这些修改，复用原 APK 的结果仍按原夹具解释，不能声称修复已通过真机。

1. **bgowner view（已知问题）**：`MovaView(source:null)` 的 build 只返回占位，不创建 MovaPlayer/MovaAutoPause。原 view 5 条后台仍推进属于夹具缺陷。改为真实 source，并由 View 自己 open；plain 仍显式 open。设备验证必须使用新 APK。
2. **广告事件类别覆盖**：`cp2AdEvent` 的 values 包含 `kind: pre/mid/post`，`Cp2Harness.mark` 的 `...values` 覆盖外层 `kind: AD`。因此 records 中实际有 `event:MovaAdEvent`，但筛选 `kind==AD` 的 adpaths/adpause/adbg 找不到事件。改 payload 字段为 `adKind`。原广告 pre 的续播误差40ms、epoch `[0,1,2]` 仍因 ads=[] 失败，不能据此指认产品漏发 completed；adpause/adbg 等 completed 超时同理。
3. **playlist 广告归集**：回调读取 `list.currentIndex`，但下一集 pre.started 在 session.jumpTo 更新 index 前发出。原 series.0 的 contentEnded=[0,1,2]，下一集 pre.started 被归到上一集，导致各集计数失败。改为按唯一广告 source URI 找排期 item。原始回调与失败保留；此项不证明产品未播放下一集广告。
4. **注入内核未移交所有权**：`cp2Mova` 自建Player/MovaMpvKernel后注入createMova，却未传ownsKernel。`lib/src/platform_impl/wiring.dart:240` 与 `lib/src/core/mova.dart:894,3542` 明确默认借用注入内核，player.dispose不会销毁它。夹具清空nativePlayers映射也不等于释放Player。补 `ownsKernel:true`。pod2重试日志3333–3388行出现OpenSLES创建失败、file cache创建失败、H.264 decoder初始化失败；adpaths重试日志4764–4773行亦有解码/音频设备错误。该资源耗尽足以污染后段epoch/首帧结果，不能据此确认产品资源泄漏。原APK不含修复，必须新包验证。
5. **旧Q13页同类所有权问题**：`main_q13_mute_verify.dart:154` 也注入自建内核、未传ownsKernel，且_disposeRig不等待ads.dispose。原包Q13A五次后Q13B出现SL_RESULT_MEMORY_FAILURE与warming未就绪FAIL。补ownsKernel:true并等待广告编排对象（`MovaAds`）销毁。该原生资源错误与静音错误应分开，源码修复仍未进入原APK。

仍保留待隔离的产品疑点：adpaths mid 原生续播误差约 -1160ms（需核对接管前采样与 `_contentResumeAt` 的时点）；pod2 wait.ad2.5 两个 URI 及首帧都存在，但 epoch1=epoch2=1。pod2同时伴随夹具导致的资源耗尽，需先修夹具再判是否有独立产品缺陷。仅标记疑似位置，不修改 lib、不宣称定位完成。

续跑原 APK 的目的包括采集尚未运行的四批及重试不完整批次。已完成 V9/PiP 不重跑。驱动尚无按 CHECK ID 断点续跑能力，不完整批次以新 run-id 整批尝试，最终按正式 ID 去重并保留历史 FAIL。

18:14 前后 audioonly-bg 首次续跑取得21条PASS后中断，harness中有空异常文本和adb `protocol fault (couldn't read status): connection reset`。后续宿主异常改用repr与完整traceback记录，避免TimeoutError的str为空而无法区分类型。

18:22:09 原生 `adb devices -l` 显示 `7NQBB23606003715 unauthorized transport_id:2`。按用户指示执行 `adb kill-server`、`adb start-server`，随后设备读回为 `device ... transport_id:1`；恢复本批 reverse 18082/18190/18194 与 forward 18083。QoE应用随后读回completed=true、9条PASS加1条harness BLOCKED（manual720.4原生path/time-pos不可用）。这些时间相关事实不等于已证明硬件、宿主或产品的唯一根因。
