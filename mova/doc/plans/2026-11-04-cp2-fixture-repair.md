# CP2 夹具修复（6856df2c 起，无设备）

## 1. adpause / adbg

原始 `matrix-cp2-adpause-resume-20261104-182433/*cp2-adpause.json`：started us=1093754，completed us=17465550，超时 us=42857551；adbg 对应 `182539`：started us=87947，completed us=37782543，超时 us=63940385。二者 callback 的 kind 实为 pre。原生 path/time-pos 已可用，且完成暂停/后台窗口后才在等 completed 的循环超时；不是等待 started、源不可达或 pending 未退出。

HEAD 已将 cp2AdEvent payload 改为 adKind。本次进一步锁定 mark 的信封字段，避免再次被 payload 覆盖；暂停/后台统计与等待按 MovaAdEvent + 本轮唯一 URI + completed 精确匹配。保留暂停漂移、300ms slot 误差、暂停期间不得 completed 与守卫语义判据。

所有变更须新包真机复测；历史结果不改写。

## 2. bgowner.view

原始 `matrix-cp2-bgowner-20261104-172930/*cp2-bgowner.json` view 五条后台推进；`lib/src/ui/view.dart` 在 source=null 时直接返回占位，不构造 MovaPlayer/MovaAutoPause。HEAD 已传真实 source。本次在原生源已渲染且推进后遍历真实 surface Element 树，确认匹配同一 api 的 MovaAutoPause 已挂载才允许后台；CHECK 留存 guardMounted/source，并验证 plain 无守卫。仍须真机确认后台冻结及前台 intent/play 自动恢复。

## 3. playlist3

`matrix-cp2-playlist3-resume-20261104-182900/*cp2-playlist3.json` series.0/.1 中下一集 pre.started 被标为上一集 item，随后同一 URI 的 completed 才属下一集；contentEnded=[0,1,2]。`session._fire` 先发节点事件和广告 callback，jumpTo 完成后才更新 currentIndex。

HEAD 已按广告 URI 找排期。本次使用 session.events 携带的 node.item/kind/ordinal 与加载 epoch 归集 started/completed，contentEnded 同样由已完成的 content 节点归属。保留 URI callback 作为独立交叉验证，要求每集节点 epoch 与 contentEnded epoch 一致、每个 pre/mid 开始及完成各一次。没有使用当前集计数推断事件归属。

## 4. adpaths

`matrix-cp2-adpaths-resume-20261104-182245/*cp2-adpaths.json` 七条 CHECK 的 ads=[]，但原始 event=MovaAdEvent 实际有 pre started/completed（前五条），mid pending/started/completed（后两条）。不是产品遗漏 completed。`session._onProgress/_beginDelay/_fire` 及 pre/post/pod 直入 `_playAd` 的代码与此一致：等待就绪的 mid 必须 pending；pre/post 就绪等待本身不发 pending，pod 各条直入开始。

按 callback 身份取事件，每个排期唯一 URI 校验完整有序序列、adKind、一开始一完成，无 failed/skipped/重复/未知 URI；CHECK 显示 expectedAdEvents/adLifecycleValid。首帧、epoch、500ms 续播及 mid 原生目标的取样计算均未改变。mid 约 -1.1s 疑点仍会失败，不能由事件修复掩盖。

## 5. pod2 迭代释放

`matrix-cp2-pod2-resume-20261104-182714` 原始失败日志与 JSON 存在原生音频/解码初始化错误，后段 wait.ad2.5 epoch1=epoch2=1。旧包注入内核未移交 ownsKernel；HEAD 已补 true。本次核实 cutover.commit 仍以 unawaited(old.dispose()) 退休旧引擎，因此仅等待 cutover.dispose 不保证所有退休 native Player 释放完成。

夹具内核缓存唯一 dispose Future；h.release 在引擎销毁后等待本轮全部 active/warming/retired 内核的真实释放，完成前不清映射、不进入下一轮，记录 KERNEL_RELEASE/RELEASE_DRAINED。pod2 即使 ads.dispose 抛错仍走 release；view 同样先 await engine dispose，避免 widget 的 unawaited 清理越过迭代边界。资源释放失败/超时会阻止下一轮。pod2 epoch 与首帧/path 判据保持原样，需隔离重测才能判断产品疑点。

## 6. warmmute 系统音量采样

原始 `matrix-cp2-warmmute-resume-20261104-183712-cp2-warmmute.volume.json` 是 before + Q13A 五轮各两个 MARK = 11 条。Q13B/C 的 `_enterAd` 失败路径直接 VERDICT，根本不发 MARK；旧采样只监听 MARK，所以“至少16条”的总数阈值与实际标记机制不一致，并不只是漏了四次 adb 调用。commands.log 还有 SL_RESULT_MEMORY_FAILURE，以及末尾 adb daemon 重新启动；logcat 主机记录中途丢失。`doc/plans/2026-11-04-cp2-warmmute-log-recovery.json` 中第12条是 18:45:25 恢复完成后的一次读数，不能证明缺失历史阶段。

- 启动前 baseline 完成后才 launch；独立 worker 在每个 Q13 VERDICT（包括提前失败）取样，另保留每个 MARK 阶段取样和结束读数。截图/音频 dumps 也移到 worker，避免阻塞日志读取与取样触发。
- 单次系统音量命令1s超时，最多3次，间隔100ms；从收到标记起超过3s即 BLOCKED，不用迟到读数补样。保存每次异常/不可解析输出、重试次数、耗时和状态。
- 正式门禁要求 before + 逐 variant/run 的15个唯一 verdict 样本 + after，共17个具名必需样本；MARK 为额外阶段证据，任一失败同样 BLOCKED。重复样本不能顶替缺失的某轮。完整且音量不同为 FAIL；系统证据完整时保留原页 PASS/FAIL，不会把 warming 未就绪改成通过。
- CHECK 的 systemVolumeProof 显式给出 expected/missing/invalid/reason。即便宿主命令失败，也归集已经落盘的日志与采样，生成缺样 BLOCKED；不执行事后补取。历史12/16及原报告保持不变。

## 校验与边界

中断续做已重新审阅原始记录、产品代码和未提交改动，并重新执行下列校验。已有五个修复提交（含 adpause/adbg 的 `966655b9`）保留；`3d8ad118` 与 `40134229` 分别补齐 bgowner/playlist3 的括号格式，不改变判据；剩余采样改动单独归入 warmmute 提交。

仅在本工作树修改 example/doc；未执行 adb、安装、Gradle、设备测试或构建 APK。没有改 mova/lib、mova/test；rate 判据、adpaths mid 目标/误差计算和500ms阈值、pod2 epoch 判据均未更动。generated_plugin* 初始脏文件保持未暂存、不进提交。

- example `flutter analyze --no-pub`：基线41 issues，最终41 issues；按级别/消息/文件/规则归一化（忽略行号）对比新增0。两次命令均因既有 warning 返回1，并非 No issues found。日志：`example/tool/coverage_evidence/cp2-fixture-{baseline,final}-analyze.log`。
- `python -B example/tool/run_matrix.py --check`：`CHECK PASS: 78 batches / 135 IDs / 6 manual; 无设备操作`。
- `test_run_matrix.py`：63 tests / OK；`test_win_policy.py`：11 / OK；`test_win_job.py`：3 / OK（既有 ResourceWarning: unclosed file，不影响退出0）。
- `test_cp2_volume.py`：8 / OK，覆盖超时/不可解析重试、失败和迟到阻塞、按轮缺样/重复样本、宿主失败后的显式BLOCKED、原页失败保留、worker落盘并等待结束。均为 fake read / mock subprocess，无设备操作。
- example 单文件 `flutter test --no-pub test/cp2_criteria_test.dart`：7 / All tests passed；覆盖广告回调来源隔离、事件完整顺序、重复/失败/错误种类拒绝及既有原生样本判据。
- Python校验日志/退出码：`example/tool/coverage_evidence/cp2-fixture-checks/`；Flutter日志：`example/tool/coverage_evidence/cp2-fixture-flutter-test.log`。这些本地日志不混入历史真机原始记录。

下一轮须使用包含本次Dart修复的新包复测：adpause/adbg能否产生完整CHECK且slot计时/静音正确，view真实守卫后台冻结/前台恢复，三集各节点/epoch归属，MP4/HLS各广告路径完整事件与续播，pod2退休内核全部释放后的第二条epoch，以及Q13各轮/阶段音量证据和warming可达性。mid约-1.1s、rate、pod2 epoch仍留给lib侧排查；本次不宣称产品通过。真实听音与画面连续性仍需真机人工确认。
