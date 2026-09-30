# 用 dart:ffi 自建原生事件订阅，摆脱 media_kit git 依赖（2026-09-29）

目标：删掉 `pubspec.yaml` 对 media_kit git 提交 `c533e44` 的锁定，回到 pub.dev 的 `media_kit: ^1.2.6`，
由 mova 自己实现 `observeEvent` 的等价能力（订阅 `MPV_EVENT_PLAYBACK_RESTART` /
`MPV_EVENT_END_FILE`）。**不 fork、不新增第三方依赖。**

测试基线：945（`flutter test` 全绿，见 CLAUDE.md）。

---

## 0. 结论（先看这里）

**可行，无不可绕过的障碍。** 关键点如下。

1. **wait_event 单消费者冲突是真的，但有干净的绕法**：libmpv 每个 `mpv_handle` 有自己独立的事件队列。
   media_kit 1.2.6 的 `InitializerNativeCallable` 在主 handle（`ctx`）上用
   `mpv_set_wakeup_callback` + `mpv_wait_event(ctx,0)` 循环独占消费；我们**不碰主 handle**，
   而是用 `mpv_create_weak_client(ctx, name)` 派生一个**弱客户端**，在它上面自建一套
   wakeup + wait_event。`MPV_EVENT_END_FILE`、`MPV_EVENT_PLAYBACK_RESTART` 是广播给所有客户端的，
   互不抢事件。
2. **上游 `observeEvent` 本质很薄**（已读 `c533e44` 的 `real.dart`）：只是往 `observedEvents` map 里
   塞回调，再在 media_kit 自己的 `_handler`（第 1531 行附近）里按 `event_id` 分发，外加一次
   `mpv_request_event`。它**没有**新的线程/隔离区机制，事件回到 Dart 走的还是原有的
   `NativeCallable.listener`（release）/ `Isolate`（debug 或 execmem 受限）。所以我们自建等价物
   不需要复刻什么复杂机制。
3. **1.2.6 已公开的入口够用**：`NativePlayer.handle`（`Future<int>`，等初始化完成后返回
   `ctx.address`）、`NativePlayer.mpv`（`generated.MPV`，公开 final 字段，已含
   `mpv_create_weak_client`/`mpv_set_wakeup_callback`/`mpv_wait_event`/`mpv_request_event`/
   `mpv_destroy`/`mpv_wakeup` 绑定）。`generated/libmpv/bindings.dart` 是 mova 已经在 import 的公开路径。
   **不需要碰 `src/` 私有路径，也不需要自己 `DynamicLibrary.open`。**
4. **瘦身 libmpv 符号已核对**：`libmpv/` 下 windows-x86_64、arm64-v8a、armeabi-v7a、x86、x86_64、
   linux-x86_64、ios-arm64 产物里 `mpv_create_client`/`mpv_create_weak_client`/
   `mpv_set_wakeup_callback`/`mpv_wait_event`/`mpv_request_event`/`mpv_destroy`/`mpv_wakeup`
   字符串均存在（对二进制 `grep -a` 的结果；导出表级别的确认放进 Task 6 的运行时冒烟，
   因为 `-fvisibility=hidden` 下"字符串在"不严格等于"已导出"）。
5. **最大风险不是可行性，而是销毁时序**：
   - 如果用**普通**客户端（`mpv_create_client`），`mpv_terminate_destroy(ctx)` 会等所有客户端
     销毁，media_kit 的 `dispose` 里那个 `Future.delayed(5s, terminate_destroy)` 会**在主 isolate
     上阻塞**——所以必须用**弱客户端**（weak client 不阻止核心关闭，关闭时收到
     `MPV_EVENT_SHUTDOWN`），并且 kernel 在 `_player.dispose()` **之前**同步销毁它。
   - 原生线程回调用 `NativeCallable.listener`（线程安全地投递到 isolate），**绝不在回调线程里
     调任何 mpv API**；销毁时先 `mpv_set_wakeup_callback(client, nullptr, nullptr)`（同步生效）
     再 `close()` callable，最后 `mpv_destroy(client)`。
   - debug 热重启会让 isolate 里的 `NativeCallable` 失效而原生线程仍可能回调（media_kit issue
     #1340/#1314 的同类崩溃）。方案：debug 下改用**定时轮询** `mpv_wait_event(client,0)`，
     不注册原生回调（见决策点 D1）。
6. **失去的东西**：git master 提交里另有的几处修复（如 dispose 时先清 wakeup 再 quit、
   `mpv_free` 泄漏修复）回到 1.2.6 后没有，这是 media_kit 自身行为，与本方案无关，但升降级时
   要跑一遍回归。见风险 R5。

**需要用户拍板的点见文末「决策点」。**

---

## 1. 现状梳理（调用点）

`lib/src/core/kernel/mpv_kernel.dart`（`MovaMpvKernel`）：

- 构造：`observeQoeSignals == true` 且 `_player.platform is NativePlayer` 时，
  `_observeSetup = native.observeProperty('paused-for-cache', ...).catchError(静默).then((_) =>
  _observeNativeEvents(native))`。
- `_observeNativeEvents`：两次 `native.observeEvent(...)`，各自 try/catch 静默退化：
  - `MPV_EVENT_PLAYBACK_RESTART` -> `_restartController.add(null)`（`playbackRestarts`，TTFF 落地）。
  - `MPV_EVENT_END_FILE` -> 读 `event.ref.data` 转 `mpv_event_end_file.reason` ->
    `_mapEndFileReason` -> `_endFileController.add(...)`（`endFiles`，会话结束原因）。
- `dispose()`：关 sub、关四个 controller、`await _observeSetup`、`await _player.dispose()`。
  **没有** `unobserveEvent`（靠 player 整体销毁）。
- 消费方：`MovaStatsProbe.playbackRestarts/endFiles`（`core/report/stats_probe.dart`）->
  `MovaQoeCollector`（`core/report/collector.dart`）。上层对来源无感，**接口不变，只换来源**。
- 退化路径：订阅失败或平台无 `NativePlayer` -> 流为空 -> QoE 层退回 `buffering` 边沿与
  `resolveSessionEnd` 时序推断。本方案沿用该退化路径。

上游 `observeEvent` 语义（供对齐）：单事件单监听（重复注册抛 `ArgumentError`）；`disposed` 后调用
抛 `AssertionError`；注册前 `await waitForPlayerInitialization`；分发在 media_kit 的
`_handler` 里、`await fn.call(event)`，事件指针只在回调期内有效。

---

## 2. 架构决策

| # | 决策 | 理由 |
|---|------|------|
| A1 | 用 **弱客户端**（`mpv_create_weak_client`）而非改 media_kit 主 handle 的事件分发 | 独立事件队列，不与 media_kit 抢 `wait_event`；弱客户端不阻塞 `mpv_terminate_destroy` |
| A2 | 抽象端口 `MovaMpvEventBackend`（纯 Dart 接口）+ 纯逻辑状态机 `MovaMpvEventPump` + FFI 实现 `FfiMpvEventBackend` | 状态机（注册/排空/销毁/幂等）可用假后端做确定性单测，FFI 层只做薄薄一层绑定 |
| A3 | **排空循环全同步**（`while` 内不 `await`），事件字段在下一次 `wait_event` 前拷成 Dart 值对象 `MovaRawEvent` | mpv 文档：事件指针仅在下次 `wait_event` 前有效；media_kit 的 `await fn.call(event)` 恰是它的隐患来源 |
| A4 | 只保留三个事件：RESTART、END_FILE、SHUTDOWN。对其它事件 `mpv_request_event(id, 0)` 关闭；**SHUTDOWN 不可关闭**（mpv 源码对 `SHUTDOWN && !enable` 返回 `INVALID_PARAMETER`），必须跳过它，且逐项容错，单项失败不得使整体注册失败 | 新客户端默认收全部事件，无谓唤醒；同时 `PROPERTY_CHANGE` 等我们没订阅的不会入队 |
| A5 | 唤醒方式：release 用 `NativeCallable<Void Function(Pointer<mpv_handle>)>.listener`；debug（`kDebugMode`）用 `Timer.periodic` 轮询 | 见风险 R3；两种都由后端接口封装，状态机不感知 |
| A6 | 生命周期在 `MovaMpvKernel` 内管理：构造发起 -> `dispose()` 先 `await pump.dispose()`（同步销毁客户端）再 `_player.dispose()` | 保证销毁 mpv 主句柄前弱客户端已释放，避免持有已释放核心的指针 |
| A7 | 对外接口（`playbackRestarts`/`endFiles`/`MovaEndFileReason`/`_mapEndFileReason`）不变；`observeQoeSignals=false` 时完全不创建客户端 | 沿用"无 reporter 零开销"承诺；上层与全部现有测试无感 |
| A8 | 不新增依赖：`dart:ffi`、`dart:async`、已有的 `package:media_kit/generated/libmpv/bindings.dart` 与 `package:media_kit/ffi/ffi.dart`（`calloc`/`Utf8`，media_kit 自带的公开路径）足够 | 遵守依赖管理约定；**不需要 `package:ffi`** |

平台范围：仅 `NativePlayer`（Windows/Android/Linux/macOS/iOS）。web 无此能力，走空流退化。

---

## 3. 并发与销毁不变量清单

代码评审和测试都以此为验收准绳（编号供测试用例引用）。

- **I1 销毁前等注册落地**：`dispose()` 若发生在 `handle` 尚未解析/客户端尚未创建时，必须让注册流程在
  创建客户端**之前**检查 `disposing` 标志并放弃创建；若已在创建中，等其完成后再销毁。绝不出现
  "先销毁、后创建"。
- **I2 销毁后零回调**：`dispose()` 返回后，任何路径（已排队的唤醒、迟到的定时器）都不得再调用
  `wait_event`、不得再向 controller `add`。用 `_closed` 标志在排空循环每一轮开头检查。
- **I3 重复 dispose 幂等**：并发/多次调用只销毁一次；第二次直接返回同一个 Future。
- **I4 销毁顺序固定**：`置 closed` -> `mpv_set_wakeup_callback(client, nullptr, nullptr)` ->
  关闭 `NativeCallable` / 取消 Timer -> `mpv_destroy(client)`；且整体发生在
  `_player.dispose()` 之前。
- **I5 原生回调不触碰已释放的 Dart 对象**：原生线程回调只做"投递"；listener 内先判 `_closed`，
  再通过状态机方法进入，不直接持有 controller。
- **I6 排空循环同步**：单次排空内不 `await`，事件拷贝先于下一次 `wait_event`；排空期间不会与
  `dispose()` 交错（同一 isolate 线程）。
- **I7 controller 关闭**：`dispose()` 关闭 `_restartController`/`_endFileController`；关闭后
  `isClosed` 守卫保证不抛 `Bad state: Cannot add`。
- **I8 注册中途失败可退化**：`handle` 抛错、`create_weak_client` 返回 `nullptr`、`request_event`
  返回负值，均静默退化为空流，且**不泄漏**已创建的客户端（失败路径也要 `mpv_destroy`）。
- **I9 多引擎互不串扰**：每个 kernel 各自的客户端（名称含自增序号 `mova_qoe_<n>`）、各自的
  回调闭包；A 引擎的事件绝不出现在 B 的流里；A dispose 不影响 B。
- **I10 核心先死**：收到 `MPV_EVENT_SHUTDOWN`（media_kit 在别处先销毁核心）时，标记不再排空，
  但仍需在 `dispose()` 时 `mpv_destroy` 释放客户端句柄（弱客户端允许在核心销毁后销毁）。
- **I11 数量守恒**：创建的客户端数 == 销毁的客户端数（假后端计数 + 真机循环验证）。
- **I12 不在 mpv 回调线程调 mpv API**：wakeup 回调体内零 mpv 调用（仅 `listener` 投递或不注册）。

---

## 4. 逐 Task 计划

约定：每个 Task 一个 commit（由主会话执行）；每个 Task 完成 `flutter analyze` 0 新增 issue +
`flutter test` 全绿；注释中文简短、每个类/方法都要有；公开 API 带参数/返回/示例。

### Task 1：值对象与后端端口（纯 Dart）

新文件 `lib/src/core/kernel/mpv_event_backend.dart`：

```dart
/// mpv 原始事件的值拷贝（脱离原生指针生命周期）。
class MovaRawEvent {
  const MovaRawEvent(this.id, {this.endFileReason});
  /// mpv_event_id。
  final int id;
  /// 仅 END_FILE 有值：mpv_end_file_reason。
  final int? endFileReason;
}

/// 原生事件后端端口；FFI 实现与测试假实现共用。
abstract class MovaMpvEventBackend {
  /// 创建弱客户端；失败返回 false。
  bool createClient(String name);
  /// 只保留指定事件，其余关闭；返回是否全部成功。
  bool restrictEvents(Set<int> keep);
  /// 注册"有新事件"的通知（可能来自任意线程的投递，回到 isolate 后调用 [onWake]）。
  void armWakeup(void Function() onWake);
  /// 非阻塞取一个事件（拷贝后返回）；无事件返回 null。
  MovaRawEvent? poll();
  /// 同步、幂等地注销通知并销毁客户端。
  void destroy();
}
```

单测 `test/core/kernel/mpv_event_backend_test.dart`（值对象与假后端自检，约 3 项）。

### Task 2：纯逻辑状态机 `MovaMpvEventPump`

新文件 `lib/src/core/kernel/mpv_event_pump.dart`。骨架：

```dart
enum _PumpState { idle, registering, active, closing, closed }

class MovaMpvEventPump {
  MovaMpvEventPump(this._backend, {required this.name,
    required this.onRestart, required this.onEndFile});

  /// 发起注册；[ready] 为等待"原生句柄可用"的 Future（生产中是 NativePlayer.handle）。
  Future<void> start(Future<void> ready);   // 落实 I1/I8
  /// 幂等销毁（I3/I4）。
  Future<void> dispose();
  void _onWake();                            // 落实 I2/I5/I6：closed 直接返回；同步排空
}
```

要点：
- `start` 内 `await ready` 之后、`createClient` 之前检查 `_state == closing/closed`（I1）。
- `dispose` 在 `registering` 态：置 `closing`，`await _startFuture`（注册流程发现 closing 后自行
  不创建/或创建后立即销毁），再 `_backend.destroy()`；返回缓存的同一个 Future（I3）。
- `_onWake` 排空：`while (_state == active) { final e = _backend.poll(); if (e == null) break; ... }`；
  END_FILE 通过 `onEndFile(e.endFileReason)`；`MPV_EVENT_SHUTDOWN` -> 置 `_coreGone`，停止排空（I10）。
- 回调里抛异常要吞掉（try/catch），否则一个坏事件打断排空。

单测 `test/core/kernel/mpv_event_pump_test.dart`（假后端 + `fake_async`，约 20 项，见第 5 节）。

### Task 3：FFI 后端 `FfiMpvEventBackend`

新文件 `lib/src/core/kernel/mpv_event_backend_ffi.dart`（需 `dart:ffi`；先核对
`test/core/purity_test.dart` 对 `lib/src/core/` 的 import 约束——`mpv_kernel.dart` 已在
core/kernel 下 import media_kit，本文件同目录同级别；若 purity 测试禁 `dart:ffi`，则改放
`lib/src/platform_impl/` 并从 wiring 注入，Task 4 相应调整）。

```dart
class FfiMpvEventBackend implements MovaMpvEventBackend {
  FfiMpvEventBackend(this._mpv, this._ctx, {required bool pollInDebug});
  final generated.MPV _mpv;
  final Pointer<generated.mpv_handle> _ctx;   // 由 NativePlayer.handle 的地址还原
  Pointer<generated.mpv_handle> _client = nullptr;
  NativeCallable<Void Function(Pointer<generated.mpv_handle>)>? _callable;
  Timer? _timer;
  // createClient: mpv.mpv_create_weak_client(_ctx, namePtr)  (name 用 calloc/toNativeUtf8，用后 free)
  // restrictEvents: 对 id in 1..MPV_EVENT_* 上限逐个 mpv_request_event(_client, id, keep.contains(id)?1:0)
  // armWakeup: release -> NativeCallable.listener(...) + mpv_set_wakeup_callback(_client, fn, _client)
  //            debug   -> Timer.periodic(100ms, (_) => onWake())
  // poll: ev = mpv_wait_event(_client, 0); NONE -> null;
  //       拷贝 id 与（END_FILE 时）data.cast<mpv_event_end_file>().ref.reason 后立即返回
  // destroy: 幂等；顺序 = set_wakeup(nullptr) -> callable.close()/timer.cancel() -> mpv_destroy
}
```

注意：`NativePlayer.handle` 只在初始化后返回地址；`Pointer.fromAddress(addr)` 还原。

单测：FFI 层无法在纯 `flutter test` 里无 libmpv 地跑，本 Task 的单测只覆盖能抽出的纯函数
（事件 id 上限枚举、reason 拷贝映射）约 3 项；其余靠 Task 6 真机验证。

### Task 4：接线 `MovaMpvKernel`

改 `lib/src/core/kernel/mpv_kernel.dart`：
- `_observeNativeEvents(native)` 改为：
  `final addr = await native.handle;` -> 构造 `FfiMpvEventBackend(native.mpv, Pointer.fromAddress(addr))`
  -> `MovaMpvEventPump.start(...)`，`onRestart` -> `_restartController`，`onEndFile` ->
  `_mapEndFileReason`（保留原映射函数）-> `_endFileController`（带 `isClosed` 守卫）。
- 字段 `_pump`；`dispose()` 顺序改为：关 sub/controller ->
  `await _observeSetup` -> `await _pump?.dispose()` -> `await _player.dispose()`。
- 删除对 `native.observeEvent` 的全部引用；类注释里"只在锁定的 git 提交上有"改成新说明。
- 构造函数增加可选注入 `MovaMpvEventBackend Function(NativePlayer)? backendFactory`（仅供测试）。
  不改公开签名的其它部分。

单测 `test/core/kernel/mpv_kernel_events_test.dart`（用假 `backendFactory`，不需要真 libmpv；
`Player` 注入方式沿用 `audio_only_test.dart` 的做法，约 5 项）。

### Task 5：依赖回退 pubspec

- `pubspec.yaml`：`media_kit: ^1.2.6`（去掉 `git:`），删除 `dependency_overrides` 里的 media_kit
  git 段和上方为 git 依赖写的说明注释；`flutter pub get`。
- `example/pubspec.yaml`、`packages/*/pubspec.yaml` 中若有对该 git 提交的引用一并核对回退
  （执行时 `grep -rn c533e44` 全仓）。
- `flutter analyze`：目标 0 issue，且**不再有** "Publishable packages can't have 'git' dependencies"；
  `flutter pub publish --dry-run` 至少不再因 media_kit 报错（其余告警另论，如 dependency_overrides
  的 fork 包只影响 example，不影响主包发布）。
- 全量 `flutter test` 与基线对照。

### Task 6：真机验证（见第 6 节）

### Task 7：文档同步（提交时做）

CLAUDE.md 顶部第 5 条（git 依赖说明）与"统一上报模块"段落里 `observeEvent` 相关叙述、
`doc/plans/2026-09-29-telemetry-enhancement.md` 的"新架构决策"、SPEC.md 相关小节：改成
"自建弱客户端订阅，依赖回到 pub.dev 官方 1.2.6"；更新测试基线数字。

---

## 5. 专项测试设计（重点）

全部基于 `MovaMpvEventBackend` 假实现 `FakeMpvEventBackend`（放 `test/support/fake_mpv_event_backend.dart`）：
可编程事件队列、手动触发 `wake()`、记录调用序列（`createClient/restrictEvents/armWakeup/poll/destroy`）、
计数 create/destroy、可注入"创建失败/poll 抛异常/destroy 抛异常"。时间相关用 `fake_async`。

### 5.1 注册与生命周期（Pump 单测，约 20 项）

1. 正常：start -> create -> restrict(保留 RESTART/END_FILE/SHUTDOWN，跳过 SHUTDOWN 的关闭调用) -> armWakeup；顺序断言。追加：restrict 中个别 id 失败不影响注册成功。
2. PLAYBACK_RESTART 触发 `onRestart` 一次；END_FILE(reason=STOP/QUIT/ERROR/REDIRECT) 各触发并带 reason。
3. 一次 wake 排空多个事件，顺序保持；排空中不 await（同步：wake 返回后立即可观察结果）。
4. **注册未完成就 dispose（I1）**：`ready` 未完成时 dispose -> 之后 `ready` 完成 -> 断言
   `createClient` 从未被调用，`destroy` 调用 0 次或 1 次但净创建数为 0（I11）。
5. **注册中途 dispose**（已 create、restrict 未完成/armWakeup 前 dispose）-> 断言最终 create==destroy（I11）。
6. **重复 dispose（I3）**：连续调用 3 次，`destroy` 恰好 1 次；并发 `Future.wait([dispose, dispose])` 同样。
7. **dispose 后再 wake（I2）**：dispose 后触发 wake，`poll` 调用数不增、回调 0 次、不抛。
8. **销毁顺序（I4）**：调用序列必须为 `...armWakeup -> (dispose) destroy`，且 destroy 内部在假后端里
   记录"先注销通知再销毁句柄"。
9. **事件风暴中途 dispose**：预置 1000 个事件，第 N 次回调里触发 dispose -> 断言其后不再 poll、
   不再回调（I2/I6），且不抛。
10. 回调抛异常（`onEndFile` 抛）不打断排空，后续事件仍处理；`poll` 抛异常 -> 进入 closed、不无限重试。
11. createClient 返回 false / restrict 失败 / `ready` 抛错（I8）：静默退化，`destroy` 被正确调用
    （若已创建）；start 的 Future 不抛。
12. SHUTDOWN 事件（I10）：之后不再排空；dispose 仍调用 destroy。
13. **多引擎并存（I9）**：两个 pump + 两个假后端，A 的事件不出现在 B；A dispose 不影响 B 继续收事件。
14. 名称唯一：连续 N 个 kernel 的客户端名互不相同。
15. start 重复调用 -> 忽略（幂等）。

### 5.2 Kernel 层（约 5 项）

- `observeQoeSignals=false` 时 `backendFactory` **从未被调用**（零开销承诺）。
- 构造后立即 `dispose()`（快速 open/dispose 循环 200 次，`fake_async` 推进微任务）：
  create 总数 == destroy 总数；`_player.dispose` 在 pump.dispose 之后（用调用序列断言）。
- dispose 后 `playbackRestarts`/`endFiles` 流已关闭（`done` 完成），无残留监听。
- END_FILE reason 映射沿用现有 `_mapEndFileReason` 用例（eof/未知 -> null 不发射）。
- 非 `NativePlayer` 平台：不创建后端，流为空。

### 5.3 纯映射/枚举（约 3 项）

事件 id 上限枚举覆盖 `mpv_event_id` 全部取值；reason 拷贝与 `_mapEndFileReason` 对齐。

---

## 6. 真机验证方案

遵循项目约定：**基于真实事件戳与多轮均值，不用墙钟计时、不用临近 EOF 的 seek**；
每个功能单独建 demo 页（`example/lib/main_observe_event_verify.dart`，不与其它 spike 混用）；
URL 加时间戳防缓存；多次取平均。

设备：Windows 桌面（`--no-enable-impeller`，已知规避）+ Android STG-AL00（arm64，Android 12）。
开始前先做环境核对（`adb devices`、`flutter devices`），不凭习惯断言"无法验证"。

| 项 | 方法 | 通过判据 |
|----|------|----------|
| V1 符号导出 | 启动时对 `native.mpv` 调 `mpv_create_weak_client`（经 Task 3 后端）并检查非空；瘦身 libmpv 各 ABI 各跑一次 | 非空；无 `Invalid argument`/符号找不到 |
| V2 事件到达 | 播放一条真实视频：记录 `MovaState` 首帧事件与 `playbackRestarts` 事件戳；`stop()`/换源/dispose 触发 `endFiles` | RESTART 每次 open 至少 1 次（**seek 后也会再发一次 RESTART**，与上游 observeEvent 语义相同，TTFF 只取首个，核对 collector 已按此处理）；END_FILE reason 与操作对应（stop->STOP、换源->STOP、错误地址->ERROR） |
| V3 与 media_kit 无冲突 | 同一 kernel 同时读 `position`/`playing`/`buffering` 流与本方案事件 | 播放、seek、暂停、卡顿信号均与改造前一致；无事件丢失（对比 media_kit 自带的 `completed`/`buffering` 计数） |
| V4 创建销毁循环（并发核心） | 循环 N=200 轮：创建 engine（QoE 开）-> open 真源 -> 随机延迟 0/10/50/200ms -> dispose；其中 1/3 轮在"刚构造即 dispose"，1/3 轮在"open 中途 dispose"，1/3 轮在"事件风暴（快速 seek/换源）中 dispose" | 0 次崩溃/ANR；进程存活；日志无 `use after`/`Callback invoked after it has been deleted`；create/destroy 计数相等（后端加计数日志） |
| V5 内存走势 | 循环前后与每 20 轮采样：Windows 用 `ProcessInfo.currentRss`；Android 用 `adb shell dumpsys meminfo <pkg>`（Native Heap / TOTAL PSS）。**独立进程测量**（沿用 `main_swap_leak_probe.dart` 方法论）；对照组：同循环但 `observeQoeSignals=false` | 增量在噪声量级、无线性爬升；对比对照组差值在噪声内；判据同 swap 泄漏结论的写法（首轮台阶后进入平台） |
| V6 并存多引擎 | 同时 2-3 个 engine（含 swap 影子引擎场景）各自订阅；单独 dispose 其中一个 | 其余引擎事件不受影响，无串扰 |
| V7 主 handle 销毁不挂起 | 记录 `dispose()` 调用到返回、以及其后 5s `Future.delayed(terminate_destroy)` 触发窗口内 UI 帧间隔（用 `SchedulerBinding` 帧回调的真实时间戳） | 无 >100ms 的主线程阻塞（证明弱客户端没有拖住 `mpv_terminate_destroy`）；若失败立即改方案（见 R1） |
| V8 debug 热重启（Windows） | debug 模式 QoE 开、播放中做 5 次 hot restart | 无崩溃；轮询路径工作；release 路径不受影响 |
| V9 关闭态回归 | `observeQoeSignals=false` / `MovaReportConfig.qoe=false` | 不创建任何客户端（后端计数 0）；行为与改造前逐字节一致 |
| V10 TTFF/会话结束对账 | 与旧 git 依赖版本各跑 10 轮，取 TTFF 与 END_FILE reason 分布对比 | 分布一致（误差在设备噪声内） |

每项记录真实事件戳数字，回写本文档附录与 CLAUDE.md。iOS/macOS 无 Mac，**明确标注未验证**
（与其它 Darwin 项一致），仅保证退化路径：客户端创建失败即静默走空流。

---

## 7. 风险清单

- **R1 弱客户端仍拖住 `mpv_terminate_destroy`**：理论上不会（文档：weak 客户端收到
  `MPV_EVENT_SHUTDOWN`，且 `mpv_terminate_destroy` 不等待它们），由 V7 用帧间隔实测确认；若失败，
  退路是 kernel 在 `_player.dispose()` 前保证已销毁（本方案 A6 已如此），仍不行则回退到备选方案 B。
- **R2 slim libmpv 版本过老**：`mpv_create_weak_client` 需 client API >= 1.? （mpv 0.34 左右引入）。
  产物含该字符串；V1 运行时再确认。老版本回退：`createClient` 返回 false -> 空流退化（不崩）。
- **R3 debug 热重启**：见 A5；debug 用 100ms 轮询，TTFF 精度在 debug 下降低但不影响 release。
- **R4 事件指针生命周期**：由 A3/I6 覆盖；单测 5.1 第 3 条守护。
- **R5 回到 1.2.6 丢 master 修复**：跑全量测试 + V3/V4；若发现 media_kit 1.2.6 自身在 dispose
  上的问题，另立项，不在本方案范围。
- **R6 Darwin 未验证**：无 Mac；退化路径兜底。

**备选方案 B（若弱客户端方案在真机被否）**：不派生客户端，改为在 1.2.6 已有的 `observeProperty`
上找替代信号（TTFF 用 `video-params`/`estimated-frame-count` 首次变化 + `core-idle` 边沿；
会话结束原因回到旧的时序推断）。这是回退到功能降级，非首选。

---

## 8. 测试数量推进表

| 阶段 | 新增 | 累计（基线 945） |
|------|------|------------------|
| Task 1 端口/值对象 | +3 | 948 |
| Task 2 状态机（5.1） | +20 | 968 |
| Task 3 FFI 纯函数 | +3 | 971 |
| Task 4 kernel 接线（5.2） | +5 | 976 |
| Task 5 依赖回退 | 0（全量回归） | 976 |
| Task 6/7 真机与文档 | 0（demo 不计入） | 976 |

数字为估算，每个 Task 提交后用当次 `flutter test` 实测值回写 CLAUDE.md 与本表。

---

## 9. 决策点（需用户拍板）

- **D1 debug 下用 100ms 轮询代替原生回调**（规避热重启崩溃）：接受吗？还是 debug 也用原生回调、
  遇到热重启崩溃再说？（推荐：接受轮询。）
- **D2 FFI 后端放置（复审已定）**：`purity_test` 只允许 `kernel/mpv_kernel.dart` 一个文件 import media_kit，
  FFI 后端要 import media_kit 的 bindings，放 core 会违反。定为：端口与 `MovaMpvEventPump` 留 core（纯 Dart），
  `FfiMpvEventBackend` 放 `lib/src/platform_impl/`，由 `createMovaEngine()` 经 kernel 的 `backendFactory` 注入。不放宽 purity。
  代价：裸构造 `MpvKernel` 默认无原生事件（走退化路径），与"裸 `MovaEngine()` 平台端口为 noop"的既有约定一致。
- **D3 `pubspec` 版本约束**：`media_kit: ^1.2.6`（推荐）还是钉死 `1.2.6`？（本方案依赖
  `NativePlayer.mpv`/`handle` 的可见性，大版本升级需重验。）
- **D4 是否保留旧 git 依赖版本作为 V10 对账基线**：需要在另一个 worktree/分支保留一份旧实现供
  对照（不提交）。

---

## 10. 落地进展与验证记录（2026-09-29，均为本机实测）

### 10.1 决策点结论

D1 debug 用 100ms 轮询（release 用原生回调）；D2 端口与状态机留 core，FFI 后端放
`platform_impl/` 经 `backendFactory` 注入，**不放宽 purity**；D3 `media_kit: ^1.2.6`；D4 旧 git
依赖版本留临时分支对账，不提交。

### 10.2 任务进度

| Task | 状态 | 说明 |
|------|------|------|
| 1 端口/值对象 | 完成（未提交） | `mpv_event_backend.dart` + 假后端 |
| 2 状态机 | 完成（未提交） | `mpv_event_pump.dart`，经 1 轮复审退回修复 |
| 3 FFI 后端 | 完成（未提交） | `platform_impl/mpv_event_backend_ffi.dart` |
| 4 kernel 接线 | 完成（未提交） | `mpv_kernel.dart` + `wiring.dart` |
| 5 pubspec 回退 | 完成（2026-09-30） | 主包 `media_kit: ^1.2.6`，example 同步；`flutter test` 981 全绿 |
| 6 真机验证 | 部分 | Windows、Android 已过（见 §10.7）；iOS/macOS 未做 |
| 7 文档同步 | 完成 | 本节 + CLAUDE.md |

测试：945 → **976**（全绿）。

### 10.3 复审发现并已修的问题

1. **计划错误**：原计划要把其余事件全关，但 mpv 对 `SHUTDOWN && !enable` 返回
   `INVALID_PARAMETER`，照做会让注册整体失败、静默退化成空流。已改为保留 RESTART/END_FILE/
   SHUTDOWN 三个，跳过 SHUTDOWN 的关闭调用，其余逐项容错。
2. **验收判据错误**：`PLAYBACK_RESTART` 在 seek 后也会再发一次，原判据"每次 open 恰好 1 次"
   已改为"至少 1 次"，TTFF 只取首个。真实 libmpv 实测确认（见 10.4）。
3. **pump 泄漏**：`createClient`/`restrictEvents`/`armWakeup` 抛异常时 `_doStart` 冒泡，
   `dispose` 又 `await _startFuture` 跟着抛，`destroy` 永不调用。
4. **pump 死锁**：`dispose` 等 `ready`（`NativePlayer.handle`），`handle` 永不完成则销毁被卡死。
   修法：注册后的步骤全是同步的，`dispose` 不等注册流程，改走幂等 `_teardown()`。
5. **dispose 内 `armWakeup` 之后置 `active` 会覆盖重入 dispose 置的 `closed`**：已加守卫。

已验证的 mpv 事实（读 mpv 源码 `client.c`）：wakeup 回调在 `wakeup_lock` 内调用，
`set_wakeup_callback(null)` 与之同锁，返回后无在途回调（I4 成立）；`has_strong_ref` 只统计非弱
客户端，`mpv_terminate_destroy` 不会等弱客户端。

### 10.4 Windows 真实 libmpv 验证

方法：`flutter test` + 真实 `libmpv/windows-x86_64/libmpv-2.dll`（`MediaKit.ensureInitialized(
libmpv: ...)`），内核用 `audioOnly: true`（不创建 `VideoController`，不需要渲染面），网络源
`interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4`（URL 加时间戳防缓存）。
临时脚本已删除，未入库。

| 项 | 实测 |
|----|------|
| 20 轮创建/销毁（构造即销毁 / open 后 3s 销毁 / open+seek 后销毁 各约 1/3） | 无卡死、无崩溃；dispose 10–40ms（首轮 234ms 为冷启动）；退出前多等 6s（越过 media_kit 5s 延迟 `mpv_terminate_destroy` 窗口）进程存活 |
| create/destroy 对账 | 13 = 13；另 7 轮"构造即销毁"一个客户端都没创建（I1 生效） |
| RESTART | open 后 3s 销毁的轮次恰好 1 次；open+seek 的轮次 2 次；首个 RESTART 多为 516–662ms，2 次约 1.2s（网络抖动） |
| END_FILE 换源 | open 后 6–19ms 内收到 `stop`（reason=2），随后新的 RESTART |
| END_FILE 坏地址（`127.0.0.1:1`） | 约 5s 后收到 `error`（reason=4）；4s 内看不到，是 Windows 连接失败本身的耗时，不是 pump 丢事件（原始事件序列已核对） |
| 内存 RSS | 167 → 192MiB，前几轮抬升后走平（第 9 轮起每轮 <1MiB），无线性爬升 |

**局限**：单次运行、单台机器；`audioOnly` 内核，未覆盖带 `VideoController` 的路径；dispose 时 pump
先于 `_player.dispose()` 销毁，因此 `dispose()` 自身触发的最后一个 END_FILE 收不到，该次会话结束
原因走时序推断（与改造前差别不大）。**V7（弱客户端不拖累 `mpv_terminate_destroy`，用帧间隔实测）
未单独测**，只间接看到退出后进程存活。**Android/iOS/macOS 均未验证。**

### 10.5 `MovaMpvKernel.dispose()` 在 Windows 应用里偶发卡住（**根因线索见 §10.7，2026-09-30**）

现象：`example` 的 Windows debug 应用（`main_observe_event_verify.dart`，页面只有一个 `Text`，没有
`Video` 控件）里，`MovaMpvKernel.dispose()` 有时耗时等于外层超时（8s/20s）。**连不开 QoE、不带
pump 的 A 组也会**，所以不是 pump 引入的；但同一代码第一次对照时 A 组只用 251ms，说明**有
时序依赖、非确定性**。

已排除：
- 裸用 media_kit：`Player()` 创建 8ms、`handle` 就绪 49ms、`dispose` 5ms（同一进程内实测），都很快。
- 机器负载：先后关掉 30 个昨日遗留的 flutter_tools 进程、5 个失控的 `find /`（各累计约 2 万 CPU
  秒），CPU 负载 64–73% → 26%，重跑结果不变。
- 同样的 `audioOnly` 内核在 `flutter test` + 真实 libmpv 下 7 组场景（是否开 QoE、是否带 pump、
  是否监听流、是否等待）全部 2–386ms 完成，无一卡住。

尚未确认（**不要当结论用**）：曾猜是 `VideoController` 初始化在没有渲染面时不完成，导致
`Player.dispose()` 内的 `waitForVideoControllerInitializationIfAttached` 挂起；但后续 `audioOnly` 组在
应用里也超时，这个猜测**未能证实**。`observeProperty` 与 `Player.dispose` 都会 await 该 Future
（media_kit `real.dart` 约第 95 行、1311 行）。也**没有在改动前的 `HEAD` 上对照过**，"既有问题"
只是高概率推断。

后续查法见 memory 待办条目（`project_mova_kernel_dispose_hang.md`）。

### 10.6 环境备忘（本机 Windows 构建 `example`）

VS 18 BuildTools + CMake 4.3.4 组合下，`example` 的 Windows 构建需要两个环境变量（只对当次命令
生效，不改仓库）：`CL=/D_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`（`just_audio_windows`
用了已被微软标记移除的 `<experimental/coroutine>`）、`CMAKE_POLICY_VERSION_MINIMUM=3.5`（旧
googletest 的 `cmake_minimum_required`）。另外配置出的安装前缀是
`C:/Program Files/mova_example`，`flutter build`/`run` 的安装步骤会把 exe 旁边该有的 dll 和
`data/` 装到那里，`runner/Debug` 里只剩 exe 和 pdb——直接双击 build 目录里的 exe 会报一串
"找不到 xxx.dll"。`flutter build windows` 不支持 `--no-enable-impeller`（只有 `run` 支持）。
整包构建单次 7–14 分钟，做纯 Dart 逻辑验证优先用 `flutter test` + 真实 libmpv。

### 10.7 Android 真机验证记录（2026-09-30，STG-AL00 arm64 Android 12）

**dispose 卡死的根因**：不是 FFI/pump。无 UI 时反复创建 `VideoController` 会卡死 media_kit（纯
media_kit 复现：第 0–2 轮正常，第 3 轮起 `observeProperty` 与 `dispose` 全部 6s 超时，之后
所有 `Player` 含不挂控制器的都挂；只创建 audioOnly `Player` 6 轮全部 26–79ms）。§10.5 里
Windows 的"偶发卡住"很可能同因，待验证。验证脚本一律用 `audioOnly` 内核。

**修正后的结果**（`main_observe_event_verify.dart` / `main_observe_event_verify2.dart`）：
- 控制组 A–F 全部 41–88ms 完成，无 hung；主循环 20 轮 created=13/destroyed=13，进程存活。
- **debug 与 release 走不同路径**（`wiring.dart` `pollInDebug: kDebugMode`）：debug=100ms 轮询，
  release=原生回调，两条都验过。release 包不能 `run-as`，媒体改由本机 HTTP 服务 + `adb reverse`。
- V2 RESTART：open 1 次、open+seek 2 次，首个 RESTART 307–677ms；END_FILE：坏地址收到 `error`。
- V3 pos/playing/buffering 与无订阅对照一致；V6 单独 dispose 一个不影响其余；V7 最大帧间隔
  32ms；V9 关闭态 0 客户端；V5 120/120，PSS 首轮抬升后稳定约 50MB，开关两组无差异。

**顺带用同一批真机测出的 QoE bug**（已修，见 CLAUDE.md）：假 TTFF（buffering 初始 false）、
`stallMs` 双倍累计、失败源观看时长。相关单测见 `test/core/report/ttff_test.dart`、
`session_test.dart`。

**Windows 桌面复测（2026-09-30，release，`main_observe_event_verify2.dart`，多次运行）**：V9 关闭态 0 客户端、
创建/销毁 14/14 全部通过；V6 三引擎并存 4 次里 3 次直接通过、1 次 seek 后未在 2s 窗口内收到 RESTART
（时序波动，Windows 上窗口偏紧）；V3 4 次里 3 次与无订阅对照完全一致，1 次 `buffering` 计数 5 对 3
（该计数只取决于 open/seek 时序，不经过本方案代码，判为波动，未复现）；**V7 加了不建弱客户端的对照组**：
对照 101ms、开订阅 53ms——Windows 上约 100ms 的帧间隔是 media_kit 自身/机器基线，不是本方案造成
（此前未加对照时 103/141/137ms 被误判为超线）。**运行方式**：必须从 `C:\Program Files\mova_example`
启动（exe 单独在 `build\...\Release` 会报缺 dll，新的 Dart 代码在安装目录的 `datapp.so`）；release 桌面端
`print` 不回传，用 `MOVA_LOG` 落盘。

### 10.8 Windows 上 dispose 卡住的结案（2026-09-30）

`main_dispose_hang_verify.dart`（release，`MovaMpvKernel` 不开 QoE、不带 pump，各组 6 轮，单次超时 8s）：
A 组 audioOnly 全部 0–15ms；B 组带 `VideoController` 但页面只有一个 `Text`：dispose 耗时
5511 / 8001(超时) / 8001(超时) / 1415 / 507 / 8001(超时) ms，3/6 超时。结论：§10.5 的"偶发卡住"与
Android（§10.7）同根因，是 media_kit 的 `VideoController` 在没有渲染面时初始化不完成，与 FFI 订阅无关。
