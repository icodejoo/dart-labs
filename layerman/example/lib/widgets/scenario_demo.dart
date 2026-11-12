import 'dart:async';
import 'package:flutter/material.dart';
import 'package:layerman/layerman.dart';
import '../demo_kit/demo_kit.dart';
import '../scenarios.dart';
import '../demo_text.dart';

/// 所有示例共用的条目标识。
const _a = 'A', _b = 'B', _c = 'C';

/// 示例上下文和分组使用的稳定键。
const _route = 'route', _role = 'role', _ready = 'ready', _promo = 'promo';

/// 示例使用的路由和槽位。
const _home = '/home',
    _zone = '/zone',
    _promoRoute = '/promo',
    _toast = 'toast',
    _modal = 'modal';

/// 条件演示中使用的其他路由、角色和拒绝键。
const _other = '/other', _vip = 'vip', _declined = 'declined';

/// 实时计数数据键。
const _count = 'n';

/// 可观察的短等待时间。
const demoWait = Duration(seconds: 1);

/// 自动展示时间与冷却间隔。
const demoLifetime = Duration(seconds: 3);

/// 交互预览后端的退场时长。
const demoFade = Duration(milliseconds: 180);

/// 保留的最近事件数量。
const _logLimit = 3;

/// 重复提交按钮的双语文案。
const _retryEn = 'Try again', _retryZh = '再次提交';

/// 队列快照中的分隔符。
const _separator = ', ';

/// 一次后端展示持有的状态，生命周期不依赖同名条目。
class _Preview {
  /// 保存上下文与首帧、退场信号。
  _Preview(this.context);

  /// 绑定当前提交身份的上下文。
  final PresentContext<String> context;

  /// 首次绘制成功的确认。
  final visible = Completer<void>();

  /// 后端完全移除的确认。
  final dismissed = Completer<String?>();

  /// 是否正在播放退场。
  bool closing = false;
}

/// 卡片内的真实 present 后端及其独立编排器。
class ScenarioDemo extends StatefulWidget {
  /// 创建可重新挂载的场景。
  const ScenarioDemo({super.key, required this.scenario, this.clock});

  /// 要执行的公开 API 场景。
  final DemoScenario scenario;

  /// 可注入与测试计时一致的时钟；默认使用系统时钟。
  final OverlayClock? clock;

  /// 创建独立状态。
  @override
  State<ScenarioDemo> createState() => _ScenarioDemoState();
}

/// 统一管理场景所需队列、计时和后端清理。
class _ScenarioDemoState extends State<ScenarioDemo> {
  /// 当前卡片专属的编排器。
  late final Layerman _manager;

  /// 实际挂载的预览，以对象身份隔离同名重新提交。
  final List<_Preview> _views = [];

  /// 自有后端计时器，卸载时全部取消。
  final List<Timer> _timers = [];

  /// 最近的引擎事件记录。
  final List<OverlayEvent> _events = [];

  /// 事件订阅，防止重放后旧通知串入新场景。
  late final StreamSubscription<OverlayEvent> _subscription;

  /// 当前生命周期绑定。
  late final LayermanLifecycle _lifecycle;

  /// 独立暂停来源。
  final List<OverlayHold> _holds = [];

  /// 是否已经开始卸载。
  bool _disposing = false;

  /// 场景的交互阶段。
  int _step = 0;

  /// 关闭守卫是否已解锁。
  bool _unlocked = false;

  /// 当前实时计数。
  int _counter = 0;

  /// build 场景的单次提交标志。
  bool _built = false;

  /// 最近票据返回值。
  String? _result;

  /// 初始化独立引擎并在首帧后启动演示。
  @override
  void initState() {
    super.initState();
    _manager = Layerman(
      clock: widget.clock ?? OverlayClock.system,
      gap: const Duration(milliseconds: 120),
      dismissTimeout: demoWait,
      pauseOnRoutes: const [RouteMatcher.exact(_zone)],
      slots: {
        _toast: const OverlaySlotOptions(blockedBy: {_modal}),
        if (widget.scenario == DemoScenario.capacity)
          '': const OverlaySlotOptions(maxQueued: 2),
      },
    )..setContext({_route: _home});
    _lifecycle = LayermanLifecycle(_manager)..attach();
    _subscription = _manager.events.listen(_record);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run();
    });
  }

  /// 记录真实引擎事件，保留固定长度避免压测日志无限增长。
  void _record(OverlayEvent event) {
    if (_disposing) return;
    setState(() {
      _events.add(event);
      if (_events.length > _logLimit) _events.removeAt(0);
    });
  }

  /// 将实际绘制的预览及其精确关闭句柄交给引擎。
  PresentedOverlay<String> _present(PresentContext<String> context) {
    final view = _Preview(context);
    setState(() => _views.add(view));
    return PresentedOverlay<String>(
      visible: view.visible.future,
      dismissed: view.dismissed.future,
      dismiss: ([result]) async {
        if (widget.scenario == DemoScenario.timeout && context.id == _a) return;
        _dismiss(view, result);
        await view.dismissed.future;
      },
    );
  }

  /// 播放当前预览的淡出并在实际移除后完成 dismissed。
  void _dismiss(_Preview view, [String? result]) {
    if (view.dismissed.isCompleted || view.closing) return;
    if (_disposing) {
      view.dismissed.complete(result);
      return;
    }
    setState(() => view.closing = true);
    final reduced = MediaQuery.disableAnimationsOf(context);
    _timers.add(
      Timer(reduced ? Duration.zero : demoFade, () {
        if (!mounted || _disposing) return;
        setState(() => _views.remove(view));
        if (!view.dismissed.isCompleted) view.dismissed.complete(result);
      }),
    );
  }

  /// 提交场景条目并通过 ticket 观察返回值。
  OverlayTicket<String> _submit(
    String? id, {
    String slot = '',
    int priority = 0,
    OverlayMode mode = OverlayMode.queue,
    bool affix = false,
    Duration? delay,
    Duration? duration,
    Duration? exitDuration,
    Duration? expireAfter,
    OverlayPredicate? when,
    OverlayPredicate? auth,
    RouteMatcher? route,
    OverlayGate? gate,
    bool dismissWhenUnmet = true,
    OverlayCooldown? cooldown,
    Object? data,
    Set<String>? tags,
    Future<String?> Function()? resolve,
    FutureOr<bool> Function()? beforeClose,
  }) {
    final ticket = _manager.submit<String>(
      id: id,
      slot: slot,
      priority: priority,
      mode: mode,
      affix: affix,
      delay: delay,
      duration: duration,
      exitDuration: exitDuration,
      expireAfter: expireAfter,
      when: when,
      auth: auth,
      route: route,
      gate: gate,
      dismissWhenUnmet: dismissWhenUnmet,
      cooldown: cooldown,
      data: data,
      tags: tags,
      resolve: resolve,
      beforeClose: beforeClose,
      present: _present,
    );
    ticket.outcome.then((outcome) {
      if (mounted && !_disposing) setState(() => _result = outcome.value);
    });
    return ticket;
  }

  /// 选择当前场景使用的冷却策略。
  OverlayCooldown get _cooldown => switch (widget.scenario) {
    DemoScenario.session ||
    DemoScenario.visible => const OverlayCooldown(session: 1),
    DemoScenario.total => const OverlayCooldown(total: 2),
    DemoScenario.calendar => const OverlayCooldown(day: 1, hour: 1, minute: 1),
    DemoScenario.minGap => const OverlayCooldown(minGap: demoLifetime),
    DemoScenario.combined => const OverlayCooldown(
      session: 2,
      minGap: demoLifetime,
    ),
    _ => const OverlayCooldown(),
  };

  /// 当前场景是否需要展示冷却资格查询。
  bool get _hasCooldown => const {
    DemoScenario.session,
    DemoScenario.total,
    DemoScenario.calendar,
    DemoScenario.minGap,
    DemoScenario.combined,
    DemoScenario.suppress,
    DemoScenario.visible,
  }.contains(widget.scenario);

  /// 通过可取消计时器提供异步加载数据。
  Future<String?> _resolve() {
    final done = Completer<String?>();
    _timers.add(Timer(demoWait, () => done.complete('42')));
    return done.future;
  }

  /// 为容量诊断和突发队列生成稳定标识。
  String _queueId(int index) => 'Q$index';

  /// 启动真实场景，静态页面不调用此方法。
  void _run() {
    switch (widget.scenario) {
      case DemoScenario.queue:
        for (final id in [_a, _b, _c]) {
          _submit(id);
        }
      case DemoScenario.priority:
        _submit(_a);
        _submit(_c);
        _submit(_b, priority: 10);
      case DemoScenario.replace:
        _submit(_a);
      case DemoScenario.affix:
        _submit(_a, affix: true);
        _submit(_b, mode: OverlayMode.replace);
      case DemoScenario.overlap:
        _submit(_a);
        _submit(_b, mode: OverlayMode.overlap);
      case DemoScenario.slots:
        for (final slot in ['X', 'Y']) {
          _submit('$slot-1', slot: slot);
          _submit('$slot-2', slot: slot);
        }
      case DemoScenario.blocked:
        _submit(_a, slot: _modal);
        _submit(_b, slot: _toast, mode: OverlayMode.overlap);
      case DemoScenario.delay:
        _submit(_a, delay: demoWait);
      case DemoScenario.duration:
        _submit(_a, duration: demoLifetime);
      case DemoScenario.exit:
        _submit(_a, exitDuration: const Duration(milliseconds: 600));
        _submit(_b);
      case DemoScenario.pauseAll:
        _submit(_a, duration: demoLifetime);
        _submit(_b);
      case DemoScenario.pauseOne:
        _submit(_a, duration: const Duration(seconds: 5));
      case DemoScenario.routePause:
        _manager.setContext({_route: _zone});
        _submit(_a);
      case DemoScenario.holds:
        _holds.addAll([_manager.hold(), _manager.hold()]);
        _submit(_a);
      case DemoScenario.lifecycle:
        _lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
        _submit(_a);
      case DemoScenario.route:
        _submit(_a, route: const RouteMatcher.exact(_promoRoute));
      case DemoScenario.routeAny:
        _manager.setContext({_route: _other});
        _submit(_a, route: const RouteMatcher.anyOf([_home, _promoRoute]));
      case DemoScenario.routeRegex:
        _submit(_a, route: RouteMatcher.regex(RegExp(r'^/promo/')));
      case DemoScenario.auth:
        _submit(_a, auth: (ctx) => ctx[_role] == _vip);
      case DemoScenario.when:
        _submit(_a, when: (ctx) => ctx[_ready] == true);
      case DemoScenario.gate:
        final retryAt = _manager.clock.now().add(const Duration(seconds: 2));
        _submit(
          _a,
          gate: (ctx) => ctx[_declined] == true
              ? const OverlayVerdict.drop()
              : ctx[_ready] == true
              ? const OverlayVerdict.pass()
              : OverlayVerdict.waitUntil(retryAt),
        );
      case DemoScenario.stay:
        _submit(
          _a,
          route: const RouteMatcher.exact(_promoRoute),
          dismissWhenUnmet: false,
        );
      case DemoScenario.session ||
          DemoScenario.total ||
          DemoScenario.calendar ||
          DemoScenario.minGap ||
          DemoScenario.combined ||
          DemoScenario.suppress:
        _submit(_a, cooldown: _cooldown);
      case DemoScenario.resolve:
        _submit(_a, resolve: _resolve);
      case DemoScenario.resolveNull:
        _submit(_a, resolve: () async => null);
        _submit(_b);
      case DemoScenario.guard:
        _submit(_a, beforeClose: () => _unlocked);
      case DemoScenario.live:
        _submit(_a, data: const {_count: 0});
      case DemoScenario.result:
        _submit(null);
      case DemoScenario.tags:
        _submit(_a, tags: {_promo});
        _submit(_b, mode: OverlayMode.overlap, tags: {_promo});
        _submit(_c, mode: OverlayMode.overlap);
      case DemoScenario.expiry:
        _submit(_a);
        _submit(_b, expireAfter: demoWait);
      case DemoScenario.capacity:
        for (var i = 0; i < 5; i++) {
          _submit(_queueId(i));
        }
      case DemoScenario.visible:
        _submit(_a, cooldown: const OverlayCooldown(session: 1));
      case DemoScenario.buildOpen:
        break;
      case DemoScenario.timeout:
        _submit(_a);
        _submit(_b);
      case DemoScenario.stress:
        for (var i = 0; i < 100; i++) {
          _submit(_queueId(i), duration: const Duration(milliseconds: 30));
        }
    }
  }

  /// 构建紧凑的双语操作按钮。
  Widget _button(String en, String zh, VoidCallback action, {String? key}) =>
      FilledButton.tonal(
        key: key == null ? null : ValueKey(key),
        onPressed: action,
        child: Text(tr(context, en, zh)),
      );

  /// 根据场景提供少量与当前状态相关的控制。
  List<Widget> _actions() => switch (widget.scenario) {
    DemoScenario.replace => [
      _button(
        'Replace with B',
        '替换为 B',
        () => _submit(_b, mode: OverlayMode.replace),
      ),
    ],
    DemoScenario.pauseAll => [
      _button(
        _step.isEven ? 'Pause' : 'Resume',
        _step.isEven ? '暂停' : '继续',
        () {
          if (_step.isEven) {
            _manager.pauseAll();
          } else {
            _manager.resumeAll();
          }
          setState(() => _step++);
        },
      ),
    ],
    DemoScenario.pauseOne => [
      _button(
        _step.isEven ? 'Pause A' : 'Resume A',
        _step.isEven ? '暂停 A' : '继续 A',
        () {
          if (_step.isEven) {
            _manager.pause(_a);
          } else {
            _manager.resume(_a);
          }
          setState(() => _step++);
        },
      ),
    ],
    DemoScenario.routePause => [
      _button(
        'Leave /zone',
        '离开 /zone',
        () => _manager.setContext({_route: _home}),
      ),
    ],
    DemoScenario.holds => [
      _button('Release one hold', '释放一个凭证', () {
        if (_holds.isNotEmpty) _holds.removeAt(0).release();
      }),
    ],
    DemoScenario.lifecycle => [
      _button(
        'Return to foreground',
        '回到前台',
        () => _lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed),
      ),
    ],
    DemoScenario.route ||
    DemoScenario.routeAny ||
    DemoScenario.routeRegex ||
    DemoScenario.stay => [
      _button(
        'Enter promo',
        '进入活动页',
        () => _manager.setContext({
          _route: widget.scenario == DemoScenario.routeRegex
              ? '/promo/42'
              : _promoRoute,
        }),
      ),
      _button('Leave', '离开', () => _manager.setContext({_route: _other})),
    ],
    DemoScenario.auth => [
      _button(
        _step.isEven ? 'Sign in as VIP' : 'Sign out',
        _step.isEven ? 'VIP 登录' : '退出登录',
        () {
          _manager.setContext({_role: _step.isEven ? _vip : null});
          setState(() => _step++);
        },
      ),
    ],
    DemoScenario.when => [
      _button('Allow', '允许', () => _manager.setContext({_ready: true})),
    ],
    DemoScenario.gate => [
      _button('Allow now', '立即放行', () => _manager.setContext({_ready: true})),
      _button('Drop', '拒绝', () => _manager.setContext({_declined: true})),
    ],
    DemoScenario.session ||
    DemoScenario.total ||
    DemoScenario.calendar ||
    DemoScenario.minGap ||
    DemoScenario.combined => [
      _button(_retryEn, _retryZh, () => _submit(_a, cooldown: _cooldown)),
    ],
    DemoScenario.suppress => [
      _button('Never again', '不再提示', () {
        _manager.suppress(_a);
        _manager.close(_a);
      }),
      _button(_retryEn, _retryZh, () => _submit(_a, cooldown: _cooldown)),
      _button('Snooze 3s', '稍后 3 秒', () {
        _manager.suppress(_a, duration: demoLifetime);
        _manager.close(_a);
      }),
    ],
    DemoScenario.guard => [
      _button('Unlock', '解锁', () => setState(() => _unlocked = true)),
    ],
    DemoScenario.live => [
      _button(
        'Update +1',
        '更新 +1',
        () => _manager.update(_a, {_count: ++_counter}),
      ),
    ],
    DemoScenario.tags => [
      _button('Clear promo', '清理活动标签', () => _manager.clearTag(_promo)),
    ],
    DemoScenario.timeout => [
      _button('Clean up view', '清理失联视图', () {
        for (final view in _views.toList()) {
          if (view.context.id == _a) _dismiss(view);
        }
      }),
    ],
    DemoScenario.stress => [_button('Stop', '停止', _manager.clear)],
    _ => [],
  };

  /// 用真实上下文数据渲染一个可关闭的预览。
  Widget _preview(_Preview view) => OverlayVisibility(
    visible: view.visible,
    child: AnimatedOpacity(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : demoFade,
      opacity: view.closing ? 0 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: DemoTokens.tinyGap),
        padding: const EdgeInsets.only(left: DemoTokens.smallGap),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(DemoTokens.smallGap),
        ),
        child: Row(
          children: [
            Expanded(
              child: ValueListenableBuilder<Object?>(
                valueListenable: view.context.dataListenable,
                builder: (context, data, _) => Text(
                  '${view.context.id}${data == null ? '' : ' · $data'}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
            TextButton(
              onPressed: view.closing ? null : () => view.context.close('ok'),
              child: Text(tr(context, 'Close', '关闭')),
            ),
          ],
        ),
      ),
    ),
  );

  /// 卸载时先解绑观察器，再取消计时并结束自有后端。
  @override
  void dispose() {
    _disposing = true;
    _subscription.cancel();
    _lifecycle.detach();
    _manager.dispose();
    for (final timer in _timers) {
      timer.cancel();
    }
    for (final view in _views) {
      if (!view.dismissed.isCompleted) view.dismissed.complete();
    }
    super.dispose();
  }

  /// 构建始终可操作的预览和实时队列快照。
  @override
  Widget build(BuildContext context) {
    if (widget.scenario == DemoScenario.buildOpen && !_built) {
      _built = true;
      _submit(_a);
    }
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_views.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DemoTokens.gap),
              child: Text(tr(context, 'No visible preview', '暂无可见预览')),
            ),
          for (final view in _views) _preview(view),
          ListenableBuilder(
            listenable: _manager,
            builder: (context, _) => Text(
              '${tr(context, 'Active', '激活')} ${_manager.activeIds.join(_separator)} · '
              '${tr(context, 'Queued', '排队')} ${_manager.queuedIds.length} · '
              '${tr(context, 'Resolving', '解析')} ${_manager.resolvingIds.length}'
              '${_manager.isPaused ? tr(context, ' · Paused', ' · 已暂停') : ''}'
              '${_hasCooldown ? '\n${tr(context, 'Eligible', '可展示')}: ${_manager.cooldownStatus(_a, _cooldown).canShow ? tr(context, 'Yes', '是') : tr(context, 'No', '否')}' : ''}',
              key: const ValueKey('snapshot'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (widget.scenario == DemoScenario.guard)
            Text(
              _unlocked
                  ? tr(context, 'Unlocked', '已解锁')
                  : tr(context, 'Locked', '已锁定'),
            ),
          if (widget.scenario == DemoScenario.result && _result != null)
            Text('${tr(context, 'Returned', '返回值')}: $_result'),
          const SizedBox(height: DemoTokens.smallGap),
          Wrap(
            spacing: DemoTokens.smallGap,
            runSpacing: DemoTokens.smallGap,
            children: _actions(),
          ),
          if (_events.isNotEmpty) ...[
            const SizedBox(height: DemoTokens.smallGap),
            Text(
              '${tr(context, 'Events', '事件')} · ${_events.map((event) => demoEventLabel(context, event)).join(' → ')}',
              key: const ValueKey('events'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
