import 'package:flutter/material.dart';

/// 可重放的当前公开 API 演示目录。
enum DemoScenario {
  /// 串行队列演示。
  queue(
    'Serial queue',
    '串行队列',
    'Close A to advance to B, then C.',
    '关闭 A 后依次轮到 B、C。',
    'for (final id in [\'A\', \'B\', \'C\']) { manager.open<String>(id: id, present: present); }',
  ),

  /// 优先级演示。
  priority(
    'Priority',
    '优先级',
    'Only waiting entries are reordered: B (10) precedes C (0).',
    '只重排等待项：B（10）在 C（0）前，当前 A 不被抢占。',
    'manager.open<String>(id: \'A\', present: present);\nmanager.open<String>(id: \'C\', present: present);\nmanager.open<String>(id: \'B\', priority: 10, present: present);',
  ),

  /// 抢占替换演示。
  replace(
    'Replace',
    '抢占替换',
    'Replace ends A permanently; it will not return.',
    '替换会结束 A，关闭 B 后 A 不会回来。',
    'manager.open<String>(id: \'A\', present: present);\nmanager.open<String>(id: \'B\', mode: OverlayMode.replace, present: present);',
  ),

  /// 固定保护演示。
  affix(
    'Affix',
    '固定保护',
    'A stays until closed; a replace request waits behind it.',
    'A 关闭前保持展示；替换请求在它后面等待。',
    'manager.open<String>(id: \'A\', affix: true, present: present);\nmanager.open<String>(id: \'B\', mode: OverlayMode.replace, present: present);',
  ),

  /// 并行叠加演示。
  overlap(
    'Overlap',
    '并行叠加',
    'A and B coexist; each close targets its own submission.',
    'A 与 B 同时展示，关闭操作各自绑定条目。',
    'manager.open<String>(id: \'A\', present: present);\nmanager.open<String>(id: \'B\', mode: OverlayMode.overlap, present: present);',
  ),

  /// 独立槽位演示。
  slots(
    'Independent slots',
    '独立槽位',
    'X and Y each run their own queue.',
    'X、Y 各自推进，互不阻塞。',
    'for (final slot in [\'X\', \'Y\']) { manager.open<String>(slot: slot, present: present); }',
  ),

  /// 跨槽位互斥演示。
  blocked(
    'Cross-slot blocking',
    '跨槽位互斥',
    'Toast waits for modal, including when it uses overlap.',
    'modal 关闭后才放行 toast，overlap 同样遵守。',
    '// Construct with slots: {\'toast\': OverlaySlotOptions(blockedBy: {\'modal\'})}.\nmanager.open<String>(id: \'A\', slot: \'modal\', present: present);\nmanager.open<String>(id: \'B\', slot: \'toast\', mode: OverlayMode.overlap, present: present);',
  ),

  /// 延迟出场演示。
  delay(
    'Delayed activation',
    '延迟出场',
    'Wait one second, then present A. Replay restarts the wait.',
    '等待 1 秒再展示 A；重放重新计时。',
    'manager.open<String>(delay: const Duration(seconds: 1), present: present);',
  ),

  /// 自动关闭演示。
  duration(
    'Auto close',
    '自动关闭',
    'A expires after three seconds; duration starts at activation.',
    'A 激活后 3 秒自动关闭，计时不等待 visible。',
    'manager.open<String>(duration: const Duration(seconds: 3), present: present);',
  ),

  /// 两阶段关闭演示。
  exit(
    'Two-phase close',
    '两阶段关闭',
    'A fades out; B waits for dismissed and 600 ms grace.',
    'A 淡出后，再等待 600ms 退场宽限才展示 B。',
    'manager.open<String>(id: \'A\', exitDuration: const Duration(milliseconds: 600), present: present);\nmanager.open<String>(id: \'B\', present: present);',
  ),

  /// 整体暂停演示。
  pauseAll(
    'Pause the queue',
    '整体暂停',
    'Pause freezes activation and duration, then resume.',
    '暂停冻结新激活与展示时长；继续恢复剩余时间。',
    'manager.pauseAll();\nmanager.resumeAll();',
  ),

  /// 单项暂停演示。
  pauseOne(
    'Pause one timer',
    '单项暂停',
    'Freeze only A’s five-second duration timer.',
    '仅冻结 A 的 5 秒展示计时。',
    'manager.pause(\'A\');\nmanager.resume(\'A\');',
  ),

  /// 路由免打扰演示。
  routePause(
    'Quiet route',
    '路由免打扰',
    'Entering /zone freezes the queue; leave to release it.',
    '进入 /zone 冻结队列，离开后解除路由暂停。',
    '// Construct with pauseOnRoutes: [RouteMatcher.exact(\'/zone\')].\nmanager.setContext({\'route\': \'/zone\'});\nmanager.setContext({\'route\': \'/home\'});',
  ),

  /// 独立暂停凭证演示。
  holds(
    'Independent holds',
    '独立暂停凭证',
    'Two owners pause; release both to resume.',
    '两个来源各自暂停，全部释放后才继续。',
    'final first = manager.hold();\nfinal second = manager.hold();\nfirst.release();\nsecond.release();',
  ),

  /// 应用前后台演示。
  lifecycle(
    'App lifecycle',
    '应用前后台',
    'Simulate background safely without stopping Flutter frames.',
    '安全模拟前后台，不关闭 Flutter 全局出帧。',
    'final binding = LayermanLifecycle(manager)..attach();\nbinding.didChangeAppLifecycleState(AppLifecycleState.paused);\nbinding.didChangeAppLifecycleState(AppLifecycleState.resumed);\nbinding.detach();',
  ),

  /// 精确路由演示。
  route(
    'Exact route',
    '精确路由',
    'A waits for /promo and closes when leaving.',
    'A 等待 /promo，离开后自动撤下。',
    'manager.open<String>(route: const RouteMatcher.exact(\'/promo\'), present: present);\nmanager.setContext({\'route\': \'/promo\'});',
  ),

  /// 多个路由演示。
  routeAny(
    'Any route',
    '多个路由',
    'A accepts either /home or /promo.',
    '/home、/promo 任意一个都满足。',
    'manager.open<String>(route: const RouteMatcher.anyOf([\'/home\', \'/promo\']), present: present);',
  ),

  /// 路由模式演示。
  routeRegex(
    'Route pattern',
    '路由模式',
    'Match /promo/42 with a regular expression.',
    '用正则匹配 /promo/42。',
    'manager.open<String>(route: RouteMatcher.regex(RegExp(r\'^/promo/\')), present: present);',
  ),

  /// 角色鉴权演示。
  auth(
    'Role-based auth',
    '角色鉴权',
    'Only the VIP role passes; logout dismisses A.',
    'VIP 角色才通过；退出后自动撤下 A。',
    'manager.open<String>(auth: (context) => context[\'role\'] == \'vip\', present: present);\nmanager.setContext({\'role\': \'vip\'});',
  ),

  /// 自定义条件演示。
  when(
    'Custom condition',
    '自定义条件',
    'when, route and auth combine with AND.',
    'when、route、auth 按 AND 组合。',
    'manager.open<String>(when: (context) => context[\'ready\'] == true, present: present);\nmanager.setContext({\'ready\': true});',
  ),

  /// 业务准入演示。
  gate(
    'Business gate',
    '业务准入',
    'Wait two seconds, pass early, or drop permanently.',
    '等待 2 秒自动重判，也可提前放行或永久拒绝。',
    'final retryAt = manager.clock.now().add(const Duration(seconds: 2));\nmanager.open<String>(gate: (_) => OverlayVerdict.waitUntil(retryAt), present: present);\n// Other verdicts: OverlayVerdict.pass(), OverlayVerdict.drop().',
  ),

  /// 条件失效仍保留演示。
  stay(
    'Keep when unmet',
    '条件失效仍保留',
    'After entering /promo, A stays when leaving.',
    '进入 /promo 激活后，离开时仍保留 A。',
    'manager.open<String>(route: const RouteMatcher.exact(\'/promo\'), dismissWhenUnmet: false, present: present);',
  ),

  /// 会话次数上限演示。
  session(
    'Session cap',
    '会话次数上限',
    'One visible show; further attempts end as capped.',
    '首帧可见计数一次；再次提交以 capped 结束。',
    'manager.open<String>(id: \'A\', cooldown: const OverlayCooldown(session: 1), present: present);',
  ),

  /// 累计次数上限演示。
  total(
    'Total cap',
    '累计次数上限',
    'Two shows in this in-memory store; restart clears it.',
    '本例内存存储允许 2 次展示；重启会清空。',
    'manager.open<String>(id: \'A\', cooldown: const OverlayCooldown(total: 2), present: present);',
  ),

  /// 日历时间窗口演示。
  calendar(
    'Calendar caps',
    '日历时间窗口',
    'Choose day, hour or minute; buckets use local calendar time.',
    '可选日、小时、分钟次数上限；按本地日历分桶。',
    'manager.open<String>(id: \'A\', cooldown: const OverlayCooldown(day: 1, hour: 1, minute: 1), present: present);',
  ),

  /// 最短间隔演示。
  minGap(
    'Minimum interval',
    '最短间隔',
    'Close then retry; the next show wakes after three seconds.',
    '关闭后再提交，满 3 秒时自动唤醒。',
    'manager.open<String>(id: \'A\', cooldown: const OverlayCooldown(minGap: Duration(seconds: 3)), present: present);',
  ),

  /// 组合上限演示。
  combined(
    'Combined caps',
    '组合上限',
    'session: 2 AND minGap: 3s must both pass.',
    'session: 2 与 minGap: 3 秒必须同时满足。',
    'manager.open<String>(id: \'A\', cooldown: const OverlayCooldown(session: 2, minGap: Duration(seconds: 3)), present: present);',
  ),

  /// 不再提示演示。
  suppress(
    'Don’t show again',
    '不再提示',
    'Suppress future cooldown submissions; reset restores eligibility.',
    '抑制后续带 cooldown 的提交；重置可恢复资格。',
    'manager.suppress(\'A\');\n// Temporary: manager.suppress(\'A\', duration: const Duration(seconds: 3));\nmanager.resetCooldown(\'A\');',
  ),

  /// 按需加载演示。
  resolve(
    'Resolve on demand',
    '按需加载',
    'Resolve takes one second after receiving the slot.',
    '拿到槽位后加载 1 秒，再把结果交给后端。',
    'manager.open<String>(resolve: () async => \'Ready\', present: present);',
  ),

  /// 跳过空结果演示。
  resolveNull(
    'Skip empty result',
    '跳过空结果',
    'resolve returning null ends as skipped; B can proceed.',
    'resolve 返回 null，以 skipped 结束并放行 B。',
    'manager.open<String>(resolve: () async => null, present: present);',
  ),

  /// 关闭守卫演示。
  guard(
    'Close guard',
    '关闭守卫',
    'Try close while locked, then unlock; remove bypasses the guard.',
    '锁定时关闭会被否决；解锁后可关闭；remove 可绕过守卫。',
    'manager.open<String>(id: \'A\', beforeClose: () => false, present: present);\nmanager.remove(\'A\');',
  ),

  /// 实时数据演示。
  live(
    'Live data',
    '实时数据',
    'Listen to dataListenable; update shallow-merges maps.',
    '监听 dataListenable；update 浅合并 Map。',
    'manager.open<String>(id: \'A\', data: const {\'n\': 0}, present: present);\nmanager.update(\'A\', {\'n\': 1});',
  ),

  /// 类型化结果演示。
  result(
    'Typed outcome',
    '类型化结果',
    'Close returns ok; the ticket reports the value and reason.',
    '关闭返回 ok；ticket 同时报告返回值与结束原因。',
    'final ticket = manager.submit<String>(present: present);\nticket.outcome.then((outcome) { debugPrint(\'\${outcome.reason}: \${outcome.value}\'); });',
  ),

  /// 按标签清理演示。
  tags(
    'Targeted cleanup',
    '按标签清理',
    'Remove promo entries while keeping the untagged one.',
    '清理 promo 标签条目，保留无标签条目。',
    'manager.open<String>(tags: const {\'promo\'}, present: present);\nmanager.clearTag(\'promo\');\nmanager.clearWhere((record) => record.tags.contains(\'promo\'));',
  ),

  /// 排队过期演示。
  expiry(
    'Queue expiry',
    '排队过期',
    'B waits behind A and expires after one second.',
    'B 被 A 阻塞，排队 1 秒后过期。',
    'manager.open<String>(id: \'A\', present: present);\nmanager.open<String>(id: \'B\', expireAfter: const Duration(seconds: 1), present: present);',
  ),

  /// 队列容量演示。
  capacity(
    'Bounded queue',
    '队列容量',
    'maxQueued: 2 excludes the active entry; the tail is evicted.',
    'maxQueued: 2 不含激活项；超额时挤出队尾。',
    '// Construct with slots: {\'\': OverlaySlotOptions(maxQueued: 2)}.\nfor (var i = 0; i < 5; i++) { manager.open<String>(present: present); }',
  ),

  /// 首帧可见确认演示。
  visible(
    'First painted frame',
    '首帧可见确认',
    'shown and cooldown count follow the actual painted frame.',
    'shown 与冷却计数等待真实首帧绘制确认。',
    '// In present: wrap the rendered child in OverlayVisibility(visible: completer, child: child).\n// Return PresentedOverlay(visible: completer.future, dismissed: dismissed, dismiss: dismiss).',
  ),

  /// build 期间提交演示。
  buildOpen(
    'Submit during build',
    'build 期间提交',
    'The engine defers presentation until after the frame.',
    '引擎将展示推迟到帧后，避免 build 中通知。',
    '// In a State.build guarded by a one-time boolean:\nmanager.open<String>(present: present);',
  ),

  /// 退场超时兜底演示。
  timeout(
    'Dismiss fallback',
    '退场超时兜底',
    'A deliberately unresponsive backend releases its slot after one second.',
    '故意让后端不响应关闭；1 秒超时后释放槽位。',
    '// Construct with dismissTimeout: Duration(seconds: 1).\n// Timeout releases orchestration; the backend owner must still clean up its view.\nmanager.close(\'A\');',
  ),

  /// 突发队列演示。
  stress(
    'Burst queue',
    '突发队列',
    'Submit 100 entries and drain automatically; no historic FPS claims.',
    '提交 100 项并自动出场关闭，不展示历史性能数据。',
    'for (var i = 0; i < 100; i++) { manager.open<String>(duration: const Duration(milliseconds: 30), present: present); }',
  );

  /// 创建双语说明与可复制调用片段。
  const DemoScenario(
    this.en,
    this.zh,
    this.descriptionEn,
    this.descriptionZh,
    this.code,
  );

  /// 英文名称。
  final String en;

  /// 中文名称。
  final String zh;

  /// 英文行为说明。
  final String descriptionEn;

  /// 中文行为说明。
  final String descriptionZh;

  /// 使用当前 API 的调用片段。
  final String code;
}

/// 导航主题及其演示清单。
class DemoGroup {
  /// 创建双语主题。
  const DemoGroup(
    this.id,
    this.en,
    this.zh,
    this.descriptionEn,
    this.descriptionZh,
    this.icon,
    this.scenarios,
  );

  /// URL 中稳定的主题标识。
  final String id;

  /// 英文标题。
  final String en;

  /// 中文标题。
  final String zh;

  /// 英文简介。
  final String descriptionEn;

  /// 中文简介。
  final String descriptionZh;

  /// 导航图标。
  final IconData icon;

  /// 主题内的演示。
  final List<DemoScenario> scenarios;
}

/// 线上按行为组织的演示页面。
const demoGroups = [
  DemoGroup(
    'queue',
    'Queue & modes',
    '队列与模式',
    'Close the inline previews to advance real, independent queues.',
    '关闭卡片内的预览，观察独立真实队列的推进。',
    Icons.layers_outlined,
    [
      DemoScenario.queue,
      DemoScenario.priority,
      DemoScenario.replace,
      DemoScenario.affix,
      DemoScenario.overlap,
      DemoScenario.slots,
      DemoScenario.blocked,
    ],
  ),
  DemoGroup(
    'timing',
    'Timing & pause',
    '计时与暂停',
    'Replay a timer, freeze it, or compose independent pause sources.',
    '重放计时、冻结倒计时，或组合独立暂停来源。',
    Icons.timer_outlined,
    [
      DemoScenario.delay,
      DemoScenario.duration,
      DemoScenario.exit,
      DemoScenario.pauseAll,
      DemoScenario.pauseOne,
      DemoScenario.routePause,
      DemoScenario.holds,
      DemoScenario.lifecycle,
    ],
  ),
  DemoGroup(
    'conditions',
    'Conditions & gates',
    '条件与准入',
    'Change the context to grant eligibility. Each preview owns its route context.',
    '改变上下文以满足条件；各预览独立维护模拟路由上下文。',
    Icons.filter_alt_outlined,
    [
      DemoScenario.route,
      DemoScenario.routeAny,
      DemoScenario.routeRegex,
      DemoScenario.auth,
      DemoScenario.when,
      DemoScenario.gate,
      DemoScenario.stay,
    ],
  ),
  DemoGroup(
    'cooldown',
    'Cooldown & suppress',
    '冷却与抑制',
    'Counts wait for first paint. This demo uses in-memory storage; all cooldown submissions await hydration automatically.',
    '次数等待首帧确认；本例使用内存存储；所有带 cooldown 的提交均自动等待存储读取。',
    Icons.hourglass_empty_rounded,
    [
      DemoScenario.session,
      DemoScenario.total,
      DemoScenario.calendar,
      DemoScenario.minGap,
      DemoScenario.combined,
      DemoScenario.suppress,
    ],
  ),
  DemoGroup(
    'data',
    'Data & outcomes',
    '数据与结果',
    'Inspect live payloads, guarded close and typed ticket outcomes.',
    '观察实时数据、关闭守卫与类型化票据结果。',
    Icons.data_object_rounded,
    [
      DemoScenario.resolve,
      DemoScenario.resolveNull,
      DemoScenario.guard,
      DemoScenario.live,
      DemoScenario.result,
      DemoScenario.tags,
      DemoScenario.visible,
      DemoScenario.buildOpen,
    ],
  ),
];

/// 保留开发诊断与新增轻量压测，兼容 web 构建。
const diagnosticsGroup = DemoGroup(
  'diagnostics',
  'Queue diagnostics',
  '队列诊断',
  'Live engine diagnostics, not device performance measurements. Dismiss timeout deliberately exercises the fallback.',
  '实时引擎诊断，不代表设备性能；退场超时示例会主动触发兜底。',
  Icons.monitor_heart_outlined,
  [
    DemoScenario.expiry,
    DemoScenario.capacity,
    DemoScenario.timeout,
    DemoScenario.stress,
  ],
);
