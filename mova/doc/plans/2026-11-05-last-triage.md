# CP3 最后两项离线定性（2026-11-05）

范围：仅当前 detached worktree；起点 d9059ebb；只读第三轮证据、读代码和运行桌面单测。未调用真机、adb、Gradle，未改证据及第三轮结果。

## 1. headers 池暂停截图：14/30 空图

结论：未挂渲染面的 lazyVideo 引擎 screenshot 返回 null 是设计；但不能用该设计解释本轮 14 次失败，也不能据此改成 PASS。现有证据更指向挂载后的暂停截图就绪时机或原生截图路径，离线无法进一步排除其中任一原因。

代码依据：wiring.dart 默认 lazyVideo=true；mpv_kernel.dart 的 screenshot 在 audioOnly 或 _controller==null 时直接返回 null。engine_pool.bind 负责 open/暂停预热，不保证独立的像素截图能力；ready/首帧事件也不等于可取得编码图像。

关键反证：example/lib/verify_auto/cp3_pages_auto.dart 的 nativePath(pool) 已先 await h.mount(engine, raw:true)，再 pool.bind；h.mount 等待两个 endOfFrame。截图还直接调用 (engine.renderHandle as VideoController).player.screenshot，绕过了 kernel 的 _controller==null 返回分支。因此本轮不是简单的“无控制器导致 kernel 返回 null”。

第三轮六个目录的 *cp3-headers.json（numbers.nativePaths.pool.observations.authorized）共 30 组：16 次 81259 字节、14 次 null；空图同样有 restart、rendered=true、duration=120000、640x360、playing=false、error=null。restart 与元数据不能证明原生 screenshot 在该时刻必有图。

夹具判据应明确为：**需挂渲染面后再截图**，并等待当前媒体的画面就绪；accepted、restart、size、duration 仅作为独立状态证据。现有夹具已经满足挂载前提，故本次不重复修改夹具或把空图豁免。未能在假内核重现真实原生截图偶发空图，不修改池产品路径。后续复验应保留首次截图及耗时，另采挂载/控制器就绪和延后截图结果，不能用重试成功覆盖首次空图。

## 2. 授权抽帧：2/30 空帧

原始位置：matrix-cp3-headers-r3-20261105-095110 的 quality.1 为 5123ms；matrix-cp3-extract-extra1-r3-20261105-095612 的 quality.4 为 5112ms。相应 requests 为授权 Referer、HTTP 200。其余 28 次取得帧。以上统计来自 coverage_evidence 下六个第三轮 headers/extract-extra 目录，与 cp3-results.md「第三轮复验」交叉核对。

core/preview/extractor.dart 只负责端口与缩略图适配，null 是抽取失败契约。platform_impl/mpv_extractor_impl.dart 的 movaWaitForPreviewFrame 默认 timeout=5s、pollInterval=30ms；新源先等 duration>0，再 seek 并等待 seeking=no 且 time-pos 距目标小于 0.3s，之后 settleDelay=60ms 才截图。duration 和落点分别有 5 秒期限，5123/5112ms 与一次 5 秒等待加初始化开销吻合；证据没有阶段标记，不能断言就是 seek 超时，更不能从 HTTP 200 推导完成解码。

超时返回 null 合理：未确认落点时截图可能把旧帧写入缓存。改动仅对首次 seek 落地等待失败重发一次 seek，再完整验证落点；仍失败返回 null。duration 超时、截图失败及异常均不自动重试。释放后不重发。每次确认仍使用原来的 5 秒期限，最坏落点等待由 5 秒增至 10 秒（不含 open/seek 本身），串行队列可能相应增加等待。

回归使用生产轮询与截图管线、假落点属性及 seek 动作，覆盖首次超时后恢复、持续超时和释放拒绝重发；这验证恢复策略，不声称复现 Android 原生根因。临时仅回退 helper 的重试分支：2 条失败、1 条通过；恢复修复后定向 3 条通过。行为变化已写 CHANGELOG。

## 验证与复验

产品修复提交：`d954901b`（fix(mova): retry preview seek once after landing timeout），包含 lib、回归测试和 CHANGELOG，附指定 Co-Authored-By。

- `flutter analyze lib test`：0 issues（35.2s）。
- `flutter test --concurrency=3`：仅运行一次全量，2418 条全绿（3m28s），基线 2415 + 新增 3。
- 定向测试：3 绿；临时回退重试分支：2 红、1 绿，修复已恢复。
- `git diff --check`：通过。
- 日志位于本机临时目录 mova-last-triage-{analyze,full,red}.log；未加入仓库。
- 提交仅显式 add 本次文件；未操作其他 worktree、未 push/切分支/stash/reset、未改 CLAUDE.md。

需要新 APK 复验：是。抽帧重发是产品行为变化，需验证 2/30 是否消失并观察最坏耗时；池截图仍需真实渲染/原生截图阶段证据。离线通过不能替代这两项真机结论。
