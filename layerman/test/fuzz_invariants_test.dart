import 'support/manual_now_clock.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:layerman/src/overlay_manager.dart';
import 'package:layerman/src/overlay_types.dart';

/// 回归：关闭请求发出后，remove / clear / dismiss 超时不得再次请求后端 dismiss。
/// 由本文件的随机序列在 10 个种子上发现（_doClose 没记录"已请求"，_remove 里的
/// _dismissBackendBestEffort 又请求一次），已用 Entry.dismissRequested 修复。
const _duplicateDismiss = 'I4：后端关闭未完成时，强制移除或超时不得重复 dismiss';

/// 随机序列长度。
const _steps = 72;

/// 模拟后端和异步用户回调的延迟。
const _slow = Duration(milliseconds: 180);

/// 引擎看门狗时限。
const _timeout = Duration(milliseconds: 300);

/// 迟到回调及退场的最终排空时间。
const _drain = Duration(seconds: 2);

/// 小集合制造同 id 重开，并包含默认槽位。
const _ids = <String>['i0', 'i1', 'i2', 'i3', 'i4', 'i5'];

/// 支持独立并行调度的槽位。
const _slots = <String>['', 'a', 'b'];

/// 上下文使用的普通路由。
const _home = '/home';

/// 上下文使用的免打扰路由。
const _blocked = '/blocked';

/// 不存在的 id，验证写操作边界。
const _missing = 'missing';

/// 只由本文件主动注入的异常消息。
const _fault = '随机测试注入异常';

/// 仅允许被消费的存储读取故障。
const _readFault = '随机冷却存储读取失败';

/// 自定义角色集合的上下文键。
const _rolesKey = 'roles';

/// 自定义开关的上下文键。
const _enabledKey = 'enabled';

/// 自定义租户的上下文键。
const _tenantKey = 'tenant';

/// 默认拥有的角色。
const _readerRole = 'reader';

/// 需要显式授予的角色。
const _adminRole = 'admin';

/// 延迟计时的最小边界。
const _tick = Duration(milliseconds: 1);

/// 最小持久化上限，供存储边界用例复用。
const _persistedOnce = OverlayCooldown(total: 1);

/// 最小组合上限，验证两种计数一起重置。
const _combinedOnce = OverlayCooldown(total: 1, session: 1);

/// 统计全部扩展随机族的实际执行覆盖次数。
final _extendedCoverage = <String, int>{};

/// 记录能力被实际调用的次数，最终输出以便复审。
void _cover(String operation) => _extendedCoverage
    .update(operation, (count) => count + 1, ifAbsent: () => 1);

/// 每次提交一个后端，计数绑定提交身份而非可复用的 id。
class _FakeBackend {
  /// 配置正常、延迟、永不结束或展示异常。
  _FakeBackend(this.mode, {this.visibleMode = 0});

  /// 可见确认行为：即时、延迟或放弃。
  final int visibleMode;

  /// 后端是否实际发出过成功确认。
  bool confirmed = false;

  /// 后端行为编号。
  final int mode;

  /// 后端自行关闭信号。
  final done = Completer<int?>();

  /// 展示调用次数。
  int presents = 0;

  /// 编排器关闭调用次数。
  int dismisses = 0;

  /// 展示一次，并提供可延迟或不完成的关闭适配器。
  PresentedOverlay<int> present(PresentContext context) {
    presents++;
    if (mode == 3) throw StateError(_fault);
    final visible = Completer<void>();
    if (visibleMode == 0) {
      confirmed = true;
      visible.complete();
    } else if (visibleMode == 1) {
      Timer(_slow, () {
        confirmed = true;
        visible.complete();
      });
    }
    _cover('visible$visibleMode');
    return PresentedOverlay<int>(
      visible: visible.future,
      dismissed: done.future,
      dismiss: ([value]) async {
        dismisses++;
        if (mode == 0) finish(value);
        if (mode == 1) Timer(_slow, () => finish(value));
      },
    );
  }

  /// 模拟用户关闭；重复或迟到的信号不重复完成 Future。
  void finish([int? value]) {
    if (!done.isCompleted) done.complete(value);
  }
}

/// 跟踪单张票的完成次数及事件，不依赖引擎内部状态。
class _TicketProbe {
  /// 保存提交身份及其串行属性。
  _TicketProbe(this.id, this.overlap, this.backend);

  /// 可被下一次提交复用的标识。
  final String id;

  /// 是否以 overlap 模式提交，决定 I1 的串行分类。
  final bool overlap;

  /// 本次提交专属后端。
  final _FakeBackend backend;

  /// overlap 最早完成 appear delay 的时刻，用于区分延迟容器与实际阻塞持有。
  DateTime? overlapDue;

  /// 独立保存 gate 最近一次返回值，检查激活没有越过等待或拒绝。
  OverlayVerdict? lastGateVerdict;

  /// 最近一次 gate 是否故意抛错，异常不得放行。
  bool gateThrew = false;

  /// 曾返回过未来截止时刻，用于统计等待后激活覆盖。
  bool gateWaited = false;

  /// 类型化票据。
  late final OverlayTicket<int> ticket;

  /// 收到的生命周期事件。
  final events = <OverlayEvent>[];

  /// result 回调次数。
  int results = 0;

  /// outcome 回调次数。
  int outcomes = 0;

  /// result 首次返回的值。
  int? value;

  /// outcome 首次返回的对象，结束后再次读取必须保持身份。
  OverlayOutcome<int>? outcome;

  /// 在任何异步结算前挂接两个完成监听器。
  void watch(OverlayTicket<int> submitted) {
    ticket = submitted;
    ticket.result.then((result) {
      results++;
      value = result;
    });
    ticket.outcome.then((result) {
      outcomes++;
      outcome ??= result;
    });
  }
}

/// 单个种子的最小模型、日志与不变量检查器。
class _Scenario {
  /// 根据种子配置间隔、槽位容量及路由暂停。
  _Scenario(this.seed, this.tester, {this.withGates = false})
      : random = Random(seed) {
    // 独立随机源保持原有操作序列的抽样次数不变。
    final config = Random(seed ^ 0x6a31).nextInt(4);
    blockers = switch (config) {
      1 => {
          'b': {'a'}
        },
      2 => {
          'b': {'a'},
          'a': {''}
        },
      3 => {
          'b': {'a'},
          'a': {'b'}
        },
      _ => {},
    };
    if (config != 0) {
      _cover(['无', 'blockedBy 单向', 'blockedBy 链', 'blockedBy 环'][config]);
    }
    zoneEnabled = random.nextBool();
    manager = Layerman(
      clock: ManualNowClock(() => clock),
      gap: random.nextBool() ? Duration.zero : const Duration(milliseconds: 50),
      dismissTimeout: _timeout,
      resolveTimeout: _timeout,
      cooldownStorage: MemoryCooldownStorage(),
      pauseOnRoutes:
          zoneEnabled ? const [RouteMatcher.exact(_blocked)] : const [],
      slots: slotOptions(random.nextBool()),
    );
    subscription = manager.events.listen(_event);
    addTearDown(manager.dispose);
    addTearDown(subscription.cancel);
  }

  /// 随机生成的跨槽位约束，与原容量配置合并。
  late final Map<String, Set<String>> blockers;

  /// 回调内仅记录激活安全违规。
  final violations = <String>[];

  /// 曾在阻塞期间排队的提交身份。
  final blockedProbes = <_TicketProbe>{};

  /// 到点后确实仍因 blocker 被持有的 overlap，不能把 appear delay 当作持有。
  final heldBlockedProbes = <_TicketProbe>{};

  /// 保留既有 b 槽位选项。
  Map<String, OverlaySlotOptions> slotOptions(bool limited) => {
        for (final name in {'a', 'b'})
          name: OverlaySlotOptions(
            blockedBy: blockers[name] ?? const {},
            maxQueued: name == 'b' && limited ? 2 : null,
            gap: name == 'b' && limited ? _slow : null,
          ),
      };

  /// 占用只来自 records 的 active，排除当前提交本身。
  bool blocked(String slot, String id) => manager.records.any((r) =>
      r.id != id && r.active && (blockers[slot]?.contains(r.slot) ?? false));

  /// resolver 或无解析的 present 调用时核对安全性。
  void activated(String slot, _TicketProbe probe) {
    final verdict = probe.lastGateVerdict;
    if (probe.gateThrew ||
        verdict?.reason != null ||
        (verdict?.retryAt?.isAfter(clock) ?? false)) {
      violations.add('G1 gate 未通过却激活 ${probe.id}@$slot');
    }
    if (probe.gateWaited) _cover('gate 等待后激活');
    if (blocked(slot, probe.id)) violations.add('跨槽位受阻仍激活 ${probe.id}@$slot');
    if (blockedProbes.remove(probe)) {
      _cover('被阻塞后解除并出场');
    }
    if (heldBlockedProbes.remove(probe)) {
      _cover('overlap 被阻塞持有后释放');
    }
  }

  /// 可复现的种子。
  final int seed;

  /// fake async 时钟驱动器。
  final WidgetTester tester;

  /// 唯一随机源。
  final Random random;

  /// 新随机族混入 gate，原有 300 个种子的参数和操作序列保持原样。
  final bool withGates;

  /// 注入的日历时钟，从日边界附近开始以覆盖 day rollover。
  DateTime clock = DateTime(2026, 1, 1, 23, 59, 59);

  /// 本种子的被测实例。
  late final Layerman manager;

  /// 是否配置路由暂停。
  late final bool zoneEnabled;

  /// 所有提交，包括已经结束的旧票。
  final probes = <_TicketProbe>[];

  /// 当前 id 对应的最新提交，仅用于串行分类。
  final latest = <String, _TicketProbe>{};

  /// 全部操作参数，失败时完整输出。
  final log = <String>[];

  /// 保留全部 hold，覆盖重复释放。
  final holds = <OverlayHold>[];

  /// 手动暂停模型。
  bool manualPaused = false;

  /// 路由暂停模型。
  bool routePaused = false;

  /// 异步广播订阅。
  late final StreamSubscription<OverlayEvent> subscription;

  /// 由三个独立来源计算暂停，避免借用被测实现。
  bool get paused =>
      manualPaused || routePaused || holds.any((h) => !h.isReleased);

  /// 所有提交的累计 present 调用数。
  int get presents => probes.fold(0, (sum, p) => sum + p.backend.presents);

  /// 每次失败附完整复现信息。
  String get diagnostic => 'seed=$seed\n${log.join('\n')}\nrecords='
      '${manager.records.map((r) => '${r.id}@${r.slot}:${r.phase}:${r.data}').toList()}';

  /// 用同 id 的 queued 边界关联事件；允许旧票 ended 早于退场完成。
  void _event(OverlayEvent event) {
    final candidates = probes.where((p) => p.id == event.id);
    final probe = event.type == OverlayEventType.queued
        ? candidates.firstWhere((p) => p.events.isEmpty)
        : candidates.firstWhere((p) =>
            p.events.isNotEmpty &&
            !p.events.any((e) => e.type == OverlayEventType.ended));
    probe.events.add(event);
  }

  /// 有界泵送同时推进注入时钟；只消费故意注入的错误和看门狗错误。
  Future<void> pump([Duration elapsed = Duration.zero]) async {
    clock = clock.add(elapsed);
    await tester.pump(elapsed);
    Object? error;
    while ((error = tester.takeException()) != null) {
      expect(error is TimeoutException || error.toString().contains(_fault),
          isTrue,
          reason: '$diagnostic\n非预期异常：$error');
    }
  }

  /// 随机提交完整参数，始终显式指定 cooldown 使用的 id。
  void submit(String id) {
    final slot = _slots[random.nextInt(_slots.length)];
    final flags = random.nextInt(8);
    // 保留既有种子的抽样次数和模式分布，旧组合分支映射到实际生效的 overlap。
    final mode = switch (flags) {
      1 => OverlayMode.replace,
      2 || 3 => OverlayMode.overlap,
      _ => OverlayMode.queue,
    };
    final overlap = mode == OverlayMode.overlap;
    final affix = flags == 4;
    final priority = random.nextInt(4) - 1;
    final resolver = random.nextInt(7);
    final guard = random.nextInt(6);
    final condition = random.nextInt(5);
    final cooldown = random.nextInt(5);
    final backend = _FakeBackend(
        random.nextInt(12) == 0 ? 3 : random.nextInt(3),
        visibleMode: random.nextInt(3));
    final delay = random.nextBool() ? null : _slow;
    final duration = random.nextBool() ? null : _slow;
    final exit = random.nextBool() ? null : _slow;
    final expiry = random.nextBool() ? null : _timeout;
    log.add('submit $id slot=$slot priority=$priority mode=$mode '
        'overlap=$overlap affix=$affix resolve=$resolver guard=$guard '
        'condition=$condition cooldown=$cooldown backend=${backend.mode} '
        'delay=$delay duration=$duration exit=$exit expireAfter=$expiry');
    final probe = _TicketProbe(id, overlap, backend);
    final gateKind = withGates
        ? Random(seed ^ (probes.length * 0x13f) ^ 0x6245).nextInt(6)
        : 0;
    final gateDeadline = clock.add(_slow + _timeout);
    log.add('gate=$gateKind deadline=$gateDeadline');
    if (overlap) probe.overlapDue = clock.add(delay ?? Duration.zero);
    probes.add(probe);
    latest[id] = probe;
    if (blocked(slot, id)) blockedProbes.add(probe);
    var submitGateCalls = 0;
    probe.watch(manager.submit<int>(
      id: id,
      slot: slot,
      present: (ctx) {
        if (resolver < 2) activated(slot, probe);
        return backend.present(ctx);
      },
      data: const {'initial': true},
      priority: priority,
      mode: mode,
      affix: affix,
      delay: delay,
      duration: duration,
      exitDuration: exit,
      expireAfter: expiry,
      route: condition == 1 ? const RouteMatcher.exact(_home) : null,
      auth: condition == 2
          ? (ctx) => ctx['auth'] == true
          : (condition == 3 ? (ctx) => ctx['auth'] != true : null),
      when: condition == 4 ? (context) => context['auth'] == true : null,
      gate: gateKind == 0 ? null : (ctx) {
        submitGateCalls++;
        probe.gateThrew = gateKind == 5;
        if (probe.gateThrew) {
          _cover('gate 异常');
          throw StateError(_fault);
        }
        final verdict = switch (gateKind) {
          1 => const OverlayVerdict.pass(),
          2 => OverlayVerdict.waitUntil(gateDeadline),
          3 => const OverlayVerdict.drop(),
          _ => ctx['auth'] == true
              ? const OverlayVerdict.pass()
              : ctx['route'] == _blocked
                  ? const OverlayVerdict.drop()
                  : OverlayVerdict.waitUntil(gateDeadline),
        };
        probe.lastGateVerdict = verdict;
        probe.gateWaited |= verdict.retryAt?.isAfter(clock) ?? false;
        _cover(verdict.reason != null ? 'gate drop'
            : verdict.retryAt != null ? 'gate wait' : 'gate pass');
        return verdict;
      },
      cooldown: switch (cooldown) {
        1 => const OverlayCooldown(session: 1),
        2 => const OverlayCooldown(minGap: _timeout),
        3 => const OverlayCooldown(day: 1),
        _ => null,
      },
      resolve: resolver < 2
          ? null
          : () async {
              activated(slot, probe);
              if (resolver == 2) return 7;
              if (resolver == 3) return null;
              if (resolver == 4) throw StateError(_fault);
              await Future<void>.delayed(resolver == 5 ? _slow : _drain);
              return 9;
            },
      beforeClose: () {
        if (guard == 0) return false;
        if (guard == 1) throw StateError(_fault);
        if (guard == 2 || guard == 3) {
          return Future<bool>.delayed(_slow, () => guard == 2);
        }
        return true;
      },
    ));
    expect(submitGateCalls, lessThanOrEqualTo(1),
        reason: 'G1 单次提交重复求值\n$diagnostic');
  }

  /// 执行一个随机操作；暂停状态改变时以新模型判断后续 present。
  Future<void> step() async {
    final id =
        random.nextInt(7) == 0 ? _missing : _ids[random.nextInt(_ids.length)];
    final op = random.nextInt(22);
    final before = presents;
    var elapsed = Duration.zero;
    log.add('操作 $op id=$id');
    switch (op) {
      case 0 || 1 || 2 || 3 || 4 || 5 || 6:
        submit(id);
      case 7:
        manager.close(id, 42);
      case 8:
        manager.dismiss(id);
      case 9:
        manager.remove(id);
      case 10:
        manager.clear();
      case 11:
        final slot = _slots[random.nextInt(_slots.length)];
        log.add('clearWhere slot=$slot');
        manager.clearWhere((record) => record.slot == slot);
      case 12:
        final route = random.nextBool() ? _home : _blocked;
        final auth = random.nextBool();
        log.add('setContext route=$route auth=$auth');
        routePaused = zoneEnabled && route == _blocked;
        manager.setContext({'route': route, 'auth': auth});
      case 13:
        manualPaused = true;
        manager.pauseAll();
      case 14:
        manualPaused = false;
        manager.resumeAll();
      case 15:
        holds.add(manager.hold('fuzz'));
      case 16:
        if (holds.isNotEmpty) {
          final index = random.nextInt(holds.length);
          log.add('release hold=$index');
          holds[index].release();
        }
      case 17:
        manager.pause(id);
      case 18:
        manager.resume(id);
      case 19:
        final patch =
            random.nextBool() ? <String, Object?>{'step': log.length} : 5;
        log.add('update patch=$patch');
        manager.update(id, patch);
      case 20:
        final candidates =
            probes.where((p) => p.backend.presents == 1).toList();
        if (candidates.isNotEmpty) {
          final index = random.nextInt(candidates.length);
          log.add('backend.finish 提交序号=${probes.indexOf(candidates[index])}');
          candidates[index].backend.finish(11);
        }
      case 21:
        elapsed = Duration(milliseconds: random.nextInt(650) + 1);
        log.add('pump $elapsed');
    }
    await pump(elapsed);
    if (paused) {
      expect(presents, before, reason: 'I5 暂停期间新增展示\n$diagnostic');
    }
    await check();
  }

  /// 检查 I1–I4，同时比对独立暂停模型。
  Future<void> check({bool ended = false}) async {
    manager.debugCheckInvariants();
    final why = diagnostic;
    expect(violations, isEmpty, reason: why);
    final records = manager.records;
    for (final r in records) {
      final p = latest[r.id]!;
      if (p.overlap &&
          r.phase == OverlayPhase.pending &&
          !clock.isBefore(p.overlapDue!) &&
          !paused &&
          blocked(r.slot, r.id)) {
        heldBlockedProbes.add(p);
      }
    }
    final queued = manager.queuedIds.toSet();
    final active = manager.activeIds.toSet();
    final resolving = manager.resolvingIds.toSet();
    expect(
        manager.queuedIds.length +
            manager.activeIds.length +
            manager.resolvingIds.length,
        records.length,
        reason: 'I2 重复索引\n$why');
    expect(queued.intersection(active), isEmpty, reason: 'I2\n$why');
    expect(queued.intersection(resolving), isEmpty, reason: 'I2\n$why');
    expect(active.intersection(resolving), isEmpty, reason: 'I2\n$why');
    expect(
        {...queued, ...active, ...resolving}, records.map((r) => r.id).toSet(),
        reason: 'I2\n$why');
    expect(records.map((r) => r.id).toSet().length, records.length,
        reason: 'I2 记录重复\n$why');
    for (final slot in _slots) {
      final serial = records.where((r) =>
          r.slot == slot &&
          r.phase != OverlayPhase.pending &&
          !latest[r.id]!.overlap);
      expect(serial.length, lessThanOrEqualTo(1), reason: 'I1\n$why');
    }
    for (final id in {..._ids, _missing, ...records.map((r) => r.id)}) {
      expect(manager.isShowing(id), active.contains(id), reason: 'I2\n$why');
      final matching = records.where((r) => r.id == id).toList();
      final record = manager.recordOf(id);
      if (matching.isEmpty) {
        expect(record, isNull, reason: 'I2\n$why');
      } else {
        final r = matching.single;
        expect([
          record!.id,
          record.slot,
          record.phase,
          record.active,
          record.data
        ], [
          r.id,
          r.slot,
          r.phase,
          r.active,
          r.data
        ], reason: 'I2\n$why');
      }
    }
    for (final p in probes) {
      final detail = '$why\n提交序号=${probes.indexOf(p)} id=${p.id}';
      expect(p.results, inInclusiveRange(0, 1), reason: 'I3\n$detail');
      expect(p.outcomes, p.results, reason: 'I3\n$detail');
      final types = p.events.map((e) => e.type).toList();
      final allowed = <List<OverlayEventType>>[
        [OverlayEventType.queued],
        [OverlayEventType.queued, OverlayEventType.shown],
        [OverlayEventType.queued, OverlayEventType.ended],
        [
          OverlayEventType.queued,
          OverlayEventType.shown,
          OverlayEventType.ended
        ],
      ];
      expect(
          allowed.any((a) =>
              a.length == types.length &&
              List.generate(a.length, (i) => a[i] == types[i]).every((b) => b)),
          isTrue,
          reason: 'I3 事件顺序 $types\n$detail');
      expect(types.where((t) => t == OverlayEventType.ended).length, p.outcomes,
          reason: 'I3 ended 次数\n$detail');
      expect(types.where((t) => t == OverlayEventType.shown).length,
          inInclusiveRange(0, p.backend.confirmed ? 1 : 0),
          reason: 'I3 shown 与后端展示不一致\n$detail');
      if (p.outcomes == 0 && p.backend.confirmed) {
        expect(types.where((t) => t == OverlayEventType.shown), hasLength(1),
            reason: 'I3 活跃条目的成功可见确认必须产生 shown\n$detail');
      }
      if (p.outcome != null) {
        final again = await p.ticket.outcome;
        expect(identical(again, p.outcome), isTrue,
            reason: 'I3 首次原因改变\n$detail');
        expect(p.value, again.value, reason: 'I3 结果不一致\n$detail');
        expect(p.events.last.reason, again.reason, reason: 'I3\n$detail');
      }
      expect(p.backend.presents, lessThanOrEqualTo(1), reason: 'I4\n$detail');
      expect(p.backend.dismisses, lessThanOrEqualTo(p.backend.presents),
          reason: 'I4\n$detail');
      if (ended) expect(p.results, 1, reason: 'I6 未结算\n$detail');
    }
    if (!manager.isDisposed) {
      expect(manager.isPaused, paused, reason: 'I5\n$why');
    }
  }

  /// 清场后覆盖销毁写操作；open/submit 的 debug 断言遵守技能契约 21。
  Future<void> finish() async {
    log.add('clear + dispose + 排空');
    manager.clear();
    manager.dispose();
    final before = presents;
    for (final id in [..._ids, _missing]) {
      manager.close(id);
      manager.dismiss(id);
      manager.remove(id);
      manager.pause(id);
      manager.resume(id);
      manager.update(id, 0);
    }
    manager.clear();
    manager.clearWhere((_) => throw StateError('销毁后不应调用谓词'));
    manager.setContext(const {'route': _home, 'auth': true});
    manager.pauseAll();
    manager.resumeAll();
    final hold = manager.hold();
    expect(hold.isReleased, isTrue, reason: diagnostic);
    hold.release();
    for (final hold in holds) {
      expect(hold.isReleased, isTrue, reason: diagnostic);
      hold.release();
    }
    for (final p in probes) {
      p.ticket.close();
      p.ticket.remove();
      p.ticket.update(1);
    }
    expect(() => manager.open<int>(present: _FakeBackend(0).present),
        throwsAssertionError);
    expect(() => manager.submit<int>(present: _FakeBackend(0).present),
        throwsAssertionError);
    manager.dispose();
    await pump(_drain);
    await pump(_drain);
    expect(presents, before, reason: 'I7\n$diagnostic');
    expect(manager.records, isEmpty, reason: 'I6\n$diagnostic');
    await check(ended: true);
  }
}

/// 受限排序模型只存不可变排序键，不复制引擎的生命周期实现。
class _Candidate {
  /// 保存提交顺序、槽位与排序键。
  _Candidate(this.seq, this.slot, this.priority, this.replace, this.affix);

  /// 唯一提交顺序同时充当 FIFO 键。
  final int seq;

  /// 目标槽位。
  final String slot;

  /// 普通优先级。
  final int priority;

  /// 前排带标志。
  final bool replace;

  /// 是否阻止后来者抢占。
  final bool affix;

  /// 唯一 id，受限族不混入同 id 接管规则。
  String get id => '排序$seq';
}

/// 以候选集的最优者验证真实 present 顺序，包括 affix 阻挡 replace。
Future<void> _ordering(int seed, WidgetTester tester) async {
  final random = Random(seed);
  final manager = Layerman();
  addTearDown(manager.dispose);
  final waiting = <_Candidate>[];
  final current = <String, _Candidate>{};
  final expected = <String>[];
  final actual = <String>[];
  final log = <String>[];

  /// 槽位空出时，从独立候选集合选出前排带、最高优先级、最早提交者。
  void select(String slot) {
    if (current.containsKey(slot)) return;
    final options = waiting.where((e) => e.slot == slot).toList();
    if (options.isEmpty) return;
    final band = options.any((e) => e.replace);
    final front = options.where((e) => e.replace == band).toList();
    final priority = front.map((e) => e.priority).reduce(max);
    final winner = front.firstWhere((e) => e.priority == priority);
    waiting.remove(winner);
    current[slot] = winner;
    expected.add(winner.id);
  }

  for (var step = 0; step < _steps; step++) {
    final slot = _slots[random.nextInt(_slots.length)];
    if (random.nextInt(3) != 0) {
      final entry = _Candidate(step, slot, random.nextInt(4) - 1,
          random.nextBool(), random.nextBool());
      log.add('submit ${entry.id} slot=$slot priority=${entry.priority} '
          'replace=${entry.replace} affix=${entry.affix}');
      if (entry.replace && current[slot]?.affix == false) current.remove(slot);
      waiting.add(entry);
      select(slot);
      manager.submit<int>(
        id: entry.id,
        slot: slot,
        priority: entry.priority,
        mode: entry.replace ? OverlayMode.replace : OverlayMode.queue,
        affix: entry.affix,
        present: (context) {
          actual.add(context.id);
          return _FakeBackend(0).present(context);
        },
      );
    } else {
      final queued = waiting.where((e) => e.slot == slot).toList();
      final closeQueued = queued.isNotEmpty && random.nextBool();
      final target = closeQueued
          ? queued[random.nextInt(queued.length)]
          : current.remove(slot);
      // close 只作用于已展示条目；对排队项请求关闭必须保留候选。
      final id = target?.id ?? _missing;
      log.add('close $id slot=$slot');
      select(slot);
      manager.close(id);
    }
    await tester.pump();
    expect(actual, expected,
        reason: 'I8 seed=$seed\n${log.join('\n')}\n'
            'records=${manager.records.map((r) => '${r.id}:${r.phase}').toList()}');
  }
  // 逐个释放余下占位，保证最后入队的候选也经历排序断言。
  while (current.isNotEmpty) {
    final slot = current.keys.first;
    final entry = current.remove(slot)!;
    log.add('排空 close ${entry.id}');
    select(slot);
    manager.close(entry.id);
    await tester.pump();
    expect(actual, expected, reason: 'I8 seed=$seed\n${log.join('\n')}');
  }
  expect(waiting, isEmpty);
  manager.dispose();
}

/// 固定种子提供可复现的组合安全网，每个种子独立使用 fake async。
void main() {
  testWidgets('open 返回后端结果，销毁后遵守 debug 断言边界', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = _FakeBackend(0);
    final result = manager.open<int>(present: backend.present);
    backend.finish(11);
    await tester.pump();
    expect(await result, 11);
    expect(backend.dismisses, 0);
    manager.dispose();
    expect(() => manager.open<int>(present: backend.present),
        throwsAssertionError);
  });
  for (final delayed in [false, true]) {
    testWidgets('正常${delayed ? '延迟' : '立即'}关闭仅请求一次后端且保留首次结果', (tester) async {
      final manager = Layerman(dismissTimeout: _timeout);
      addTearDown(manager.dispose);
      final backend = _FakeBackend(delayed ? 1 : 0);
      final ticket = manager.submit<int>(present: backend.present);
      manager.close(ticket.id, 42);
      manager.dismiss(ticket.id);
      await tester.pump(_slow);
      manager.remove(ticket.id);
      expect(backend.presents, 1);
      expect(backend.dismisses, 1);
      expect(await ticket.result, 42);
      expect((await ticket.outcome).reason, OverlayEndReason.closed);
    });
  }
  for (final force in ['remove', 'timeout']) {
    testWidgets('回归：关闭未完成再 $force 仅 dismiss 一次', (tester) async {
      final manager = Layerman(dismissTimeout: _timeout);
      addTearDown(manager.dispose);
      final backend = _FakeBackend(2);
      final ticket = manager.submit<int>(present: backend.present);
      ticket.close();
      if (force == 'remove') {
        ticket.remove();
      } else {
        await tester.pump(_timeout);
        expect(tester.takeException(), isA<TimeoutException>());
      }
      expect(backend.dismisses, 1, reason: _duplicateDismiss);
    });
  }
  for (var seed = 0; seed < 300; seed++) {
    testWidgets('随机操作不变量 seed=$seed', (tester) async {
      final scenario = _Scenario(seed, tester);
      for (var step = 0; step < _steps; step++) {
        await scenario.step();
      }
      await scenario.finish();
    });
  }
  for (var seed = 0; seed < 60; seed++) {
    testWidgets('三态 gate 与阻塞随机不变量 seed=$seed', (tester) async {
      final scenario = _Scenario(seed, tester, withGates: true);
      for (var step = 0; step < _steps; step++) {
        await scenario.step();
      }
      await scenario.finish();
    });
  }
  for (var seed = 0; seed < 60; seed++) {
    testWidgets('无条件串行排序不变量 seed=$seed', (tester) => _ordering(seed, tester));
  }
  for (var seed = 0; seed < 120; seed++) {
    testWidgets('慢存储与 build 扩展不变量 seed=$seed', (tester) async {
      final scenario = _ExtendedScenario(seed, tester);
      try {
        for (var step = 0; step < _steps; step++) {
          await scenario.step(step);
        }
        await scenario.finish();
      } catch (error, stack) {
        fail('${scenario.diagnostic}\n$error\n$stack');
      }
    });
  }
  for (var seed = 0; seed < 40; seed++) {
    testWidgets('三态 gate 与慢存储 build 扩展不变量 seed=$seed', (tester) async {
      final scenario = _ExtendedScenario(seed, tester, withGates: true);
      try {
        for (var step = 0; step < _steps; step++) {
          await scenario.step(step);
        }
        await scenario.finish();
      } catch (error, stack) {
        fail('${scenario.diagnostic}\n$error\n$stack');
      }
    });
  }
  for (var seed = 0; seed < 24; seed++) {
    testWidgets('有界业务等待最终重判并激活或结束 seed=$seed', (tester) async {
      final random = Random(seed);
      var now = DateTime(2000);
      final manager = Layerman(
        clock: ManualNowClock(() => now),
        cooldownStorage: _FuzzStorage(1, _slow),
        slots: const {
          'target': OverlaySlotOptions(blockedBy: {'modal'}),
        },
      );
      addTearDown(manager.dispose);
      final blocker = manager.submit<int>(
          slot: 'modal', present: _FakeBackend(0).present);
      final deadline = now.add(_slow + _timeout);
      final backend = _FakeBackend(0);
      final reject = random.nextBool();
      var calls = 0;
      final ticket = manager.submit<int>(
        id: 'waiting',
        slot: 'target',
        mode: seed.isEven ? OverlayMode.queue : OverlayMode.overlap,
        cooldown: const OverlayCooldown(),
        present: backend.present,
        gate: (_) {
          calls++;
          if (now.isBefore(deadline)) return OverlayVerdict.waitUntil(deadline);
          return reject
              ? const OverlayVerdict.drop()
              : const OverlayVerdict.pass();
        },
      );
      expect(calls, 1);
      expect(manager.queuedIds, contains(ticket.id));
      manager.pauseAll();
      // 随机打乱 hydrate、业务到期、解除阻塞及恢复，最后不再施加外部等待。
      final actions = ['hydrate', 'deadline', 'unblock', 'resume']..shuffle(random);
      final why = 'seed=$seed reject=$reject actions=$actions';
      for (final action in actions) {
        switch (action) {
          case 'hydrate':
            now = now.add(_slow);
            await tester.pump(_slow);
          case 'deadline':
            now = now.add(_drain);
            await tester.pump(_drain);
          case 'unblock':
            blocker.remove();
          case 'resume':
            manager.resumeAll();
        }
        manager.debugCheckInvariants();
      }
      await tester.pump();
      expect(calls, greaterThan(1), reason: why);
      expect(manager.queuedIds, isEmpty, reason: why);
      expect(backend.presents, reject ? 0 : 1, reason: why);
      if (reject) {
        expect((await ticket.outcome).reason, OverlayEndReason.gated, reason: why);
        expect(manager.recordOf(ticket.id), isNull, reason: why);
      } else {
        expect(manager.recordOf(ticket.id)!.phase, OverlayPhase.open, reason: why);
      }
    });
  }
  test('扩展族的新增操作与正反边界实际执行次数均非零', () {
    for (final operation in [
      'gate pass',
      'gate wait',
      'gate drop',
      'gate 异常',
      'gate 等待后激活',
      '扩展 gate pass',
      '扩展 gate wait',
      '扩展 gate drop',
      'suppress 永久',
      'suppress 限时',
      '限时抑制到期后激活',
      'visible0',
      'visible1',
      'visible2',
      'blockedBy 单向',
      'blockedBy 链',
      'blockedBy 环',
      '被阻塞后解除并出场',
      'overlap 被阻塞持有后释放',
      'storage0',
      'storage1',
      'storage2',
      'storage3',
      '读取失败已取走',
      'ready 前提交',
      'build open',
      'build submit',
      'cooldownStatus',
      'resetCooldown',
      'clearCooldowns',
      'clearTag 命中',
      'clearTag 未命中',
      '带标签提交',
      'overlap delay',
      'AND 三条件',
      'ctx.close 允许',
      'ctx.close 拒绝',
    ]) {
      expect(_extendedCoverage[operation] ?? 0, greaterThan(0),
          reason: '$operation\n$_extendedCoverage');
    }
    debugPrint('C2 随机族实际执行次数：$_extendedCoverage');
  });
  _extendedBoundaries();
}

/// 确定性正反边界验证随机族覆盖的契约。
void _extendedBoundaries() {
  testWidgets('回归 H1 seed=11：持久化条目在读取完成后出场', (tester) async {
    final storage = _FuzzStorage(1, _slow);
    final manager = Layerman(cooldownStorage: storage);
    addTearDown(manager.dispose);
    int? presentedAt;
    manager.submit<int>(
        id: _ids.first,
        cooldown: _persistedOnce,
        present: (ctx) {
          presentedAt = ++storage.eventOrder;
          return _FakeBackend(0).present(ctx);
        });
    await tester.pump();
    expect(presentedAt, isNull);
    expect(storage.readCompletedAt, isNull);
    await tester.pump(_slow);
    expect(presentedAt, greaterThan(storage.readCompletedAt!));
  });
  testWidgets('回归 B3 seed=0：build 内无资格 overlap 即时结束', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final backend = _FakeBackend(0);
    late OverlayTicket<int> ticket;
    await tester.pumpWidget(_BuildOpen(() {
      ticket = manager.submit<int>(
          id: _ids.first,
          mode: OverlayMode.overlap,
          when: (_) => false,
          present: backend.present);
      expect(manager.queuedIds, isNot(contains(_ids.first)));
      expect(manager.recordOf(_ids.first), isNull);
    }));
    expect(await ticket.result, isNull);
    expect((await ticket.outcome).reason, OverlayEndReason.dropped);
    expect(backend.presents, 0);
  });
  testWidgets('回归 T1 seed=61：永久受阻提交即结束，清标签保留无关条目', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    await tester.pump();
    const cd = OverlayCooldown(session: 1);
    manager.submit<int>(
        id: _ids.first, cooldown: cd, present: _FakeBackend(0).present);
    await tester.pump(); // 此回归的前提是旧项已可见并耗尽上限。
    manager.remove(_ids.first);
    manager.submit<int>(
        id: _ids.last,
        tags: {_ExtendedScenario.tags.first},
        present: _FakeBackend(0).present);
    final capped = manager.submit<int>(
        id: _ids.first, cooldown: cd, present: _FakeBackend(0).present);
    expect(manager.queuedIds, isNot(contains(_ids.first)));
    expect((await capped.outcome).reason, OverlayEndReason.capped);
    manager.submit<int>(id: _ids[1], present: _FakeBackend(0).present);
    final unrelated = manager.records
        .where((r) => !r.tags.contains(_ExtendedScenario.tags.first))
        .map((r) => r.id)
        .toSet();
    expect(unrelated, contains(_ids[1]));
    manager.clearTag(_ExtendedScenario.tags.first);
    expect(manager.records.map((r) => r.id), containsAll(unrelated));
    expect(manager.recordOf(_ids.last), isNull);
  });
  for (var mode = 0; mode < 4; mode++) {
    for (final latency in [Duration.zero, const Duration(milliseconds: 600)]) {
      testWidgets('存储模式=$mode 延迟=$latency：读取前冻结，读取后释放并排空写入', (tester) async {
        final manager = Layerman(cooldownStorage: _FuzzStorage(mode, latency));
        addTearDown(manager.dispose);
        manager.pauseAll();
        var ready = false;
        manager.ready().then((_) => ready = true);
        final backend = _FakeBackend(0);
        manager.submit<int>(
          id: _ids.first,
          cooldown: _persistedOnce,
          present: backend.present,
        );
        expect(ready, isFalse);
        expect(backend.presents, 0);
        expect(manager.cooldownStatus(_ids.first, _persistedOnce).wait, isNull);
        await tester.pump(latency);
        if (mode == 2) {
          final error = tester.takeException();
          expect(error, isA<StateError>());
          expect((error as StateError).message, _readFault);
        }
        expect(tester.takeException(), isNull);
        expect(ready, isTrue);
        expect(backend.presents, 0);
        manager.resumeAll();
        expect(backend.presents, 1);
        await tester.pump(); // 等 visible 确认再查询计数。
        expect(
            manager
                .cooldownStatus(_ids.first, _persistedOnce)
                .permanentlyBlocked,
            isTrue);
        manager.dispose();
        await tester.pump(_drain);
        await tester.pump(_drain);
      });
    }
  }
  for (var missing = 0; missing < 4; missing++) {
    testWidgets('AND 条件边界：缺失条件编号=$missing', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      manager.setContext({
        'route': missing == 1 ? _blocked : _home,
        _rolesKey: <String>{if (missing != 2) _adminRole},
        _enabledKey: missing != 3,
      });
      final backend = _FakeBackend(0);
      manager.submit<int>(
        id: _ids.first,
        mode: OverlayMode.overlap,
        route: const RouteMatcher.exact(_home),
        auth: (ctx) => (ctx[_rolesKey] as Set<String>).contains(_adminRole),
        when: (ctx) => ctx[_enabledKey] == true,
        present: backend.present,
      );
      await tester.pump();
      expect(backend.presents, missing == 0 ? 1 : 0);
    });
  }
  for (final guard in [false, true]) {
    testWidgets('后端上下文关闭：beforeClose=$guard 决定结果与关闭原因', (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      late PresentContext<int> context;
      final backend = _FakeBackend(0);
      final ticket = manager.submit<int>(
        beforeClose: () => guard,
        present: (ctx) {
          context = ctx;
          return backend.present(ctx);
        },
      );
      context.close(42);
      await tester.pump();
      if (guard) {
        final outcome = await ticket.outcome;
        expect(outcome.value, 42);
        expect(outcome.reason, OverlayEndReason.closed);
        expect(backend.dismisses, 1);
      } else {
        expect(ticket.isActive, isTrue);
        expect(backend.dismisses, 0);
        backend.finish(11);
        await tester.pump();
        expect((await ticket.outcome).value, 11);
      }
    });
  }
  for (final clearAll in [false, true]) {
    testWidgets('冷却上限与查询：${clearAll ? 'clear' : 'reset'} 重置 session 和 total',
        (tester) async {
      final manager = Layerman();
      addTearDown(manager.dispose);
      await tester.pump();
      await manager.ready();
      const cd = _combinedOnce;
      for (var epoch = 0; epoch < 2; epoch++) {
        final shown = _FakeBackend(0);
        manager.submit<int>(
            id: _ids.first, cooldown: cd, present: shown.present);
        expect(shown.presents, 1);
        await tester.pump(); // 即时后端的可见信号也由微任务交付。
        final status = manager.cooldownStatus(_ids.first, cd);
        expect(status.canShow, isFalse);
        expect(status.permanentlyBlocked, isTrue);
        expect(status.wait, isNull);
        manager.close(_ids.first);
        await tester.pump();
        final blocked = _FakeBackend(0);
        final capped = manager.submit<int>(
            id: _ids.first, cooldown: cd, present: blocked.present);
        await tester.pump(_drain);
        expect(blocked.presents, 0);
        expect((await capped.outcome).reason, OverlayEndReason.capped);
        if (clearAll) {
          manager.clearCooldowns();
        } else {
          manager.resetCooldown(_ids.first);
        }
        final reset = manager.cooldownStatus(_ids.first, cd);
        expect(reset.canShow, isTrue);
        expect(reset.permanentlyBlocked, isFalse);
        expect(reset.wait, Duration.zero);
      }
    });
  }
  testWidgets('标签批量清理保留无关项，也支持不存在的标签', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final labels = <String>{_ExtendedScenario.tags.first};
    manager.submit<int>(
        id: _ids.first, tags: labels, present: _FakeBackend(0).present);
    labels.clear();
    manager.submit<int>(id: _ids.last, present: _FakeBackend(0).present);
    manager.clearTag(_missing);
    expect(manager.records.length, 2);
    manager.clearTag(_ExtendedScenario.tags.first);
    expect(manager.records.map((r) => r.id), [_ids.last]);
    await tester.pump();
  });
  testWidgets('overlap 延迟前不展示，取消的延迟条目也不会迟到展示', (tester) async {
    final manager = Layerman();
    addTearDown(manager.dispose);
    final shown = _FakeBackend(0);
    final removed = _FakeBackend(0);
    manager.submit<int>(
        id: _ids.first,
        mode: OverlayMode.overlap,
        delay: _slow,
        present: shown.present);
    manager.submit<int>(
        id: _ids.last,
        mode: OverlayMode.overlap,
        delay: _slow,
        present: removed.present);
    await tester.pump(_slow - _tick);
    expect(shown.presents, 0);
    manager.remove(_ids.last);
    await tester.pump(_tick);
    expect(shown.presents, 1);
    expect(removed.presents, 0);
  });
}

/// 读写延迟均使用 widget 测试的 Timer 域，不依赖真实时间。
class _FuzzStorage implements OverlayCooldownStorage {
  /// 固定随机存储变体与延迟，便于复现。
  _FuzzStorage(this.mode, this.latency);

  /// 内存、慢读取、读取失败、慢写入四种模式。
  final int mode;

  /// 慢操作的延迟（含零毫秒边界）。
  final Duration latency;

  /// 快存储同时保存慢写完成后的快照。
  final memory = MemoryCooldownStorage();

  /// 读取与展示共用的单调事件序号。
  int eventOrder = 0;

  /// 读取开始顺序，供诊断异步边界使用。
  int? readStartedAt;

  /// 读取成功或失败的完成顺序；在返回 Future 结算前记录。
  int? readCompletedAt;

  /// 从同一 fake async 域中读取或注入指定的读取故障。
  @override
  Future<String?> read(String key) async {
    readStartedAt = ++eventOrder;
    try {
      if (mode == 1 || mode == 2) await Future<void>.delayed(latency);
      if (mode == 2) throw StateError(_readFault);
      return await memory.read(key);
    } finally {
      readCompletedAt = ++eventOrder;
    }
  }

  /// 慢写也使用 Timer，让测试覆盖引擎的串行补写。
  @override
  Future<void> write(String key, String value) async {
    if (mode == 3) await Future<void>.delayed(latency);
    await memory.write(key, value);
  }
}

/// 在真正的 persistentCallbacks/build 阶段执行一次提交。
class _BuildOpen extends StatelessWidget {
  /// 每次挂载的回调仅执行一次，由测试提供唯一 key。
  const _BuildOpen(this.invoke, {super.key});

  /// build 内的受测操作与即时断言。
  final VoidCallback invoke;

  /// 直接在 build 内执行回调，不能提前搬到 post-frame。
  @override
  Widget build(BuildContext context) {
    invoke();
    return const SizedBox.shrink();
  }
}

/// 扩展族每次提交的身份，不把复用 id 的旧票误认为新票。
class _ExtendedProbe {
  /// 固定本次提交的后端、模式及关闭守卫。
  _ExtendedProbe(
      this.id, this.overlap, this.guard, this.cooldown, int visibleMode)
      : backend = _FakeBackend(0, visibleMode: visibleMode);

  /// 本次提交用于计数断言的上限。
  final OverlayCooldown cooldown;

  /// 冷却模型使用的可复用 id。
  final String id;

  /// 串行占位统计需要排除 overlap。
  final bool overlap;

  /// 显式关闭是否被允许。
  final bool guard;

  /// 正常且立即确认关闭的后端。
  final _FakeBackend backend;

  /// 展示后保留真正的泛型上下文，供随机自关闭操作调用。
  PresentContext<int>? context;

  /// submit 的票据；open 分支只有结果 Future。
  OverlayTicket<int>? ticket;

  /// 异步生命周期事件。
  final events = <OverlayEvent>[];

  /// 完成结果，用于检查重复结算。
  final values = <int?>[];

  /// 完成原因，open 分支通过 ended 事件检查。
  OverlayOutcome<int>? outcome;

  /// build 返回时已从索引消失，必须验证即时结束且从未展示。
  bool endedOnSubmit = false;

  /// 提交时模型已知的结束原因，避免后续时间推进改变资格。
  OverlayEndReason? expectedSubmitReason;

  /// 永久抑制调用前仍在串行队列。
  bool suppressedInQueue = false;

  /// 成功的上下文关闭请求值。
  int? selfValue;

  /// 激活前最后一次业务资格快照，不能在未来截止或 drop 时出场。
  OverlayVerdict? lastGateVerdict;
}

/// 独立模型覆盖 hydrate、build、标签、冷却重置与条件 AND 组合。
class _ExtendedScenario {
  /// 每种存储都由 seed 的同一个随机源选择。
  _ExtendedScenario(this.seed, this.tester, {this.withGates = false})
      : random = Random(seed) {
    final mode = random.nextInt(4);
    _cover('storage$mode');
    final latency = Duration(milliseconds: random.nextInt(601));
    log.add('storage=$mode latency=$latency');
    manager = Layerman(
      cooldownStorage: storage = _FuzzStorage(mode, latency),
      clock: ManualNowClock(() => now),
    );
    manager.ready().then((_) {
      ready = true;
      log.add('ready 完成 time=$now');
    });
    subscription = manager.events.listen((event) {
      final candidates = probes.where((p) => p.id == event.id);
      final probe = event.type == OverlayEventType.queued
          ? candidates.firstWhere((p) => p.events.isEmpty)
          : candidates.firstWhere((p) =>
              p.events.isNotEmpty &&
              !p.events.any((e) => e.type == OverlayEventType.ended));
      probe.events.add(event);
      if (event.type == OverlayEventType.shown) {
        final cd = probe.cooldown;
        final count = counts.update(event.id, (n) => n + 1, ifAbsent: () => 1);
        if ((cd.total != null && count > cd.total!) ||
            (cd.session != null && count > cd.session!)) {
          violations.add(
              'H2 ${event.id} 可见次数=$count total=${cd.total} session=${cd.session}');
        }
      }
    });
    addTearDown(manager.dispose);
    addTearDown(subscription.cancel);
    manager.setContext(context);
  }

  /// 可复现的随机种子。
  final int seed;

  /// fake async 驱动器。
  final WidgetTester tester;

  /// 本族唯一随机源。
  final Random random;

  /// 新增 gate 随机族，原有慢存储与 build 种子保持原样。
  final bool withGates;

  /// 被测实例。
  late final Layerman manager;

  /// 存储读取与展示使用同一个事件时序。
  late final _FuzzStorage storage;

  /// 事件监听，销毁时释放。
  late final StreamSubscription<OverlayEvent> subscription;

  /// 使用远离桶边界的日历时间，H2 不受日 rollover 干扰。
  DateTime now = DateTime(2026, 1, 1);

  /// ready 的 then 已执行，而不是借用内部 hydrated 状态。
  bool ready = false;

  /// 暂停模型。
  bool paused = false;

  /// build 作用域，present 不允许在此期间发生。
  bool building = false;

  /// 最近一次自定义上下文，条件模型与引擎读同一快照。
  Map<String, Object?> context = {
    'route': _home,
    _rolesKey: <String>{_readerRole},
    _enabledKey: true,
    _tenantKey: 0,
  };

  /// 全操作日志包含随机参数及每次 present/ready 的时间。
  final log = <String>[];

  /// 回调内仅记录违规，避免断言被引擎的错误隔离吞掉。
  final violations = <String>[];

  /// 所有提交的独立身份。
  final probes = <_ExtendedProbe>[];

  /// 同 id 最新提交，用于当前 records 的串行分类。
  final latest = <String, _ExtendedProbe>{};

  /// 两次 reset/clear 之间的展示计数；每个 id 的配置保持固定。
  final counts = <String, int>{};

  /// 抑制到期时间模型；永久使用 DateTime 最大毫秒数。
  final suppressedUntil = <String, int>{};

  /// 小型固定上限集合，提高 total/day/minGap 出现频率。
  static const cooldowns = <OverlayCooldown>[
    OverlayCooldown(total: 2),
    OverlayCooldown(session: 2),
    OverlayCooldown(day: 2),
    OverlayCooldown(minGap: _slow),
    _combinedOnce,
    OverlayCooldown(session: 1),
  ];

  /// 固定标签集合，便于制造交集和无关条目。
  static const tags = <String>['红', '蓝', '绿'];

  /// 包含 seed、完整日志的失败信息。
  String get diagnostic => '扩展 seed=$seed\n${log.join('\n')}\n'
      'records=${manager.records.map((r) => '${r.id}:${r.phase}:${r.tags}').toList()}';

  /// 累计真实展示次数。
  int get presents => probes.fold(0, (sum, p) => sum + p.backend.presents);

  /// 对齐两个时钟，并且只消费已知的存储读取失败。
  Future<void> pump([Duration elapsed = Duration.zero]) async {
    now = now.add(elapsed);
    await tester.pump(elapsed);
    Object? error;
    while ((error = tester.takeException()) != null) {
      expect(error, isA<StateError>(), reason: '$diagnostic\nB2 $error');
      expect((error as StateError).message, _readFault,
          reason: 'B2 非存储读取故障\n$diagnostic');
      _cover('读取失败已取走');
    }
    check();
  }

  /// 随机参数提交；build 模式还检查返回时同步可见性。
  void submit(String id, {bool fromBuild = false}) {
    final index = _ids.indexOf(id);
    final cd = cooldowns[index];
    final mode = OverlayMode.values[random.nextInt(OverlayMode.values.length)];
    final slot = _slots[random.nextInt(_slots.length)];
    final delay = random.nextBool() ? _slow : Duration.zero;
    final guard = random.nextBool();
    final useOpen = random.nextBool();
    final labels = {
      for (final tag in tags)
        if (random.nextBool()) tag
    };
    final requireRoute = random.nextBool();
    final requireRole = random.nextBool();
    final requireWhen = random.nextBool();
    final role = random.nextBool() ? _readerRole : _adminRole;
    final tenant = random.nextInt(2);
    final priority = random.nextInt(3);
    if (!ready) _cover('ready 前提交');
    if (fromBuild) _cover(useOpen ? 'build open' : 'build submit');
    if (labels.isNotEmpty) _cover('带标签提交');
    if (mode == OverlayMode.overlap && delay > Duration.zero) {
      _cover('overlap delay');
    }
    if (requireRoute && requireRole && requireWhen) _cover('AND 三条件');
    log.add('提交 $id build=$fromBuild open=$useOpen mode=$mode slot=$slot '
        'delay=$delay guard=$guard tags=$labels route=$requireRoute '
        'auth=$requireRole role=$role when=$requireWhen tenant=$tenant '
        'priority=$priority cd=$index ready=$ready');
    final probe = _ExtendedProbe(
        id, mode == OverlayMode.overlap, guard, cd, random.nextInt(3));
    final gateKind = withGates
        ? Random(seed ^ (probes.length * 0x13f) ^ 0x781).nextInt(4)
        : 0;
    final gateDeadline = now.add(_slow);
    log.add('gate=$gateKind deadline=$gateDeadline');

    /// 模型和回调各自使用同一业务规则，不询问引擎内部资格。
    OverlayVerdict businessVerdict(Map<String, Object?> ctx) => switch (gateKind) {
      1 => const OverlayVerdict.pass(),
      2 => OverlayVerdict.waitUntil(gateDeadline),
      _ => ctx[_tenantKey] == 0
          ? const OverlayVerdict.drop()
          : ctx[_enabledKey] == true
              ? const OverlayVerdict.pass()
              : OverlayVerdict.waitUntil(gateDeadline),
    };

    /// 保存实际返回值，允许后端独立核对 gate 安全性。
    OverlayVerdict gate(Map<String, Object?> ctx) {
      final verdict = businessVerdict(ctx);
      probe.lastGateVerdict = verdict;
      _cover(verdict.reason != null ? '扩展 gate drop'
          : verdict.retryAt != null ? '扩展 gate wait' : '扩展 gate pass');
      return verdict;
    }
    probes.add(probe);
    latest[id] = probe;

    /// 模型独立计算所有提供的条件，而不询问引擎资格。
    bool conditions() =>
        (!requireRoute || context['route'] == _home) &&
        (!requireRole || (context[_rolesKey] as Set<String>).contains(role)) &&
        (!requireWhen ||
            (context[_enabledKey] == true && context[_tenantKey] == tenant));

    /// 后端先记录不变量，再返回普通关闭适配器。
    PresentedOverlay<int> present(PresentContext<int> ctx) {
      log.add('present $id time=$now ready=$ready context=$context');
      if (building) violations.add('B1 build 内 present $id');
      if ((suppressedUntil[id] ?? 0) > now.millisecondsSinceEpoch) {
        violations.add('S1 抑制期间激活 $id');
      } else if (suppressedUntil.containsKey(id)) {
        _cover('限时抑制到期后激活');
      }
      if (!conditions()) violations.add('A1 条件未满足却 present $id');
      final verdict = probe.lastGateVerdict;
      if (verdict?.reason != null ||
          (verdict?.retryAt?.isAfter(now) ?? false)) {
        violations.add('G1 gate 未通过却 present $id');
      }
      final presentOrder = ++storage.eventOrder;
      if (storage.readCompletedAt == null ||
          presentOrder <= storage.readCompletedAt!) {
        violations.add('H1 存储读取完成前 present $id order=$presentOrder');
      }
      if (paused) violations.add('I5 暂停期间 present $id');
      probe.context = ctx;
      return probe.backend.present(ctx);
    }

    final before = presents;
    if (useOpen) {
      manager
          .open<int>(
            id: id,
            slot: slot,
            present: present,
            mode: mode,
            delay: delay,
            priority: priority,
            cooldown: cd,
            tags: labels,
            route: requireRoute ? const RouteMatcher.exact(_home) : null,
            auth: requireRole
                ? (ctx) => (ctx[_rolesKey] as Set<String>).contains(role)
                : null,
            when: requireWhen
                ? (ctx) => ctx[_enabledKey] == true && ctx[_tenantKey] == tenant
                : null,
            gate: gateKind == 0 ? null : gate,
            beforeClose: () => guard,
          )
          .then(probe.values.add);
    } else {
      final ticket = manager.submit<int>(
        id: id,
        slot: slot,
        present: present,
        mode: mode,
        delay: delay,
        priority: priority,
        cooldown: cd,
        tags: labels,
        route: requireRoute ? const RouteMatcher.exact(_home) : null,
        auth: requireRole
            ? (ctx) => (ctx[_rolesKey] as Set<String>).contains(role)
            : null,
        when: requireWhen
            ? (ctx) => ctx[_enabledKey] == true && ctx[_tenantKey] == tenant
            : null,
        gate: gateKind == 0 ? null : gate,
        beforeClose: () => guard,
      );
      probe.ticket = ticket;
      ticket.result.then(probe.values.add);
      ticket.outcome.then((outcome) => probe.outcome = outcome);
    }
    if (fromBuild) {
      expect(presents, before, reason: 'B1\n$diagnostic');
      final queued = manager.queuedIds.contains(id);
      final recorded = manager.records.any((r) => r.id == id);
      expect(queued, recorded, reason: 'B3\n$diagnostic');
      probe.endedOnSubmit = !recorded;
      if (!recorded) {
        final suppressed =
            (suppressedUntil[id] ?? 0) > now.millisecondsSinceEpoch;
        final count = counts[id] ?? 0;
        final capped = (cd.total != null && count >= cd.total!) ||
            (cd.session != null && count >= cd.session!);
        final permanentSuppression = suppressedUntil[id] == 8640000000000000;
        final businessDrop = gateKind != 0 && conditions() &&
            businessVerdict(context).reason != null;
        probe.expectedSubmitReason =
            mode == OverlayMode.overlap && !conditions()
                ? OverlayEndReason.dropped
                : suppressed && (permanentSuppression || capped || !businessDrop)
                    ? OverlayEndReason.suppressed
                    : capped
                        ? OverlayEndReason.capped
                        : businessDrop
                            ? OverlayEndReason.gated
                        : OverlayEndReason.dropped;
      }
    }
  }

  /// clearTag 的影响在同一同步调用边界检查，避免后续调度干扰。
  void clearTag(String tag) {
    log.add('clearTag $tag');
    _cover(manager.records.any((r) => r.tags.contains(tag))
        ? 'clearTag 命中'
        : 'clearTag 未命中');
    final unrelated = manager.records
        .where((r) => !r.tags.contains(tag))
        .map((r) => r.id)
        .toSet();
    manager.clearTag(tag);
    expect(manager.records.any((r) => r.tags.contains(tag)), isFalse,
        reason: 'T1\n$diagnostic');
    expect(manager.records.map((r) => r.id).toSet(), containsAll(unrelated),
        reason: 'T1 无关条目被移除\n$diagnostic');
  }

  /// 模型先重置，允许同步重调度产生新的 present。
  void reset([String? id]) {
    log.add('reset $id');
    if (id == null) {
      _cover('clearCooldowns');
      counts.clear();
      suppressedUntil.clear();
      manager.clearCooldowns();
    } else {
      _cover('resetCooldown');
      counts.remove(id);
      suppressedUntil.remove(id);
      manager.resetCooldown(id);
    }
  }

  /// 独立合并抑制时间，永久时同步验证队列身份消失及首次结束原因。
  void suppress(String id) {
    final permanent = random.nextBool();
    final duration = permanent ? null : _slow * (1 + random.nextInt(5));
    _cover(permanent ? 'suppress 永久' : 'suppress 限时');
    final until = duration == null
        ? 8640000000000000
        : now.add(duration).millisecondsSinceEpoch;
    suppressedUntil.update(id, (old) => max(old, until), ifAbsent: () => until);
    final p = latest[id];
    final queuedSerial =
        p != null && !p.overlap && manager.queuedIds.contains(id);
    log.add('suppress $id duration=$duration until=${suppressedUntil[id]}');
    manager.suppress(id, duration: duration);
    if (queuedSerial && suppressedUntil[id] == 8640000000000000) {
      expect(manager.recordOf(id), isNull, reason: 'S2\n$diagnostic');
      if (p.ticket != null) {
        p.ticket!.outcome.then((outcome) {
          if (outcome.reason != OverlayEndReason.suppressed) {
            violations.add('S2 永久抑制队列原因错误 $id ${outcome.reason}');
          }
        });
      }
      p.suppressedInQueue = true;
    }
  }

  /// 每步检查 C1 和 I1–I7，I8 继续由原来的 60 个排序种子守住。
  void check({bool ended = false}) {
    manager.debugCheckInvariants();
    final why = diagnostic;
    expect(violations, isEmpty, reason: why);
    final records = manager.records;
    final queued = manager.queuedIds.toSet();
    final active = manager.activeIds.toSet();
    final resolving = manager.resolvingIds.toSet();
    expect(queued.intersection(active), isEmpty, reason: 'I2\n$why');
    expect(queued.intersection(resolving), isEmpty, reason: 'I2\n$why');
    expect(active.intersection(resolving), isEmpty, reason: 'I2\n$why');
    expect(
        [...manager.queuedIds, ...manager.activeIds, ...manager.resolvingIds]
            .length,
        records.length,
        reason: 'I2\n$why');
    expect(
        {...queued, ...active, ...resolving}, records.map((r) => r.id).toSet(),
        reason: 'I2\n$why');
    expect(records.map((r) => r.id).toSet().length, records.length,
        reason: 'I2\n$why');
    for (final slot in _slots) {
      expect(
          records
              .where((r) =>
                  r.slot == slot &&
                  r.phase != OverlayPhase.pending &&
                  !latest[r.id]!.overlap)
              .length,
          lessThanOrEqualTo(1),
          reason: 'I1\n$why');
    }
    for (var i = 0; i < _ids.length; i++) {
      final id = _ids[i];
      final status = manager.cooldownStatus(id, cooldowns[i]);
      _cover('cooldownStatus');
      expect(status.suppressed,
          (suppressedUntil[id] ?? 0) > now.millisecondsSinceEpoch,
          reason: 'S1 抑制状态模型不一致\n$why');
      expect(manager.isShowing(id), active.contains(id), reason: 'I2\n$why');
      expect(
          manager.recordOf(id)?.id, records.any((r) => r.id == id) ? id : null,
          reason: 'I2\n$why');
      if (status.canShow) {
        expect(status.permanentlyBlocked, isFalse, reason: 'C1\n$why');
        expect(status.wait, Duration.zero, reason: 'C1\n$why');
      }
      if (status.permanentlyBlocked) {
        expect(status.canShow, isFalse, reason: 'C1\n$why');
        expect(status.wait, isNull, reason: 'C1\n$why');
      }
    }
    for (final p in probes) {
      final events = p.events.map((e) => e.type).toList();
      expect(p.values.length, lessThanOrEqualTo(1), reason: 'I3\n$why');
      expect(events.first, OverlayEventType.queued, reason: 'I3\n$why');
      expect(events.where((e) => e == OverlayEventType.shown).length,
          inInclusiveRange(0, p.backend.confirmed ? 1 : 0),
          reason: 'I3\n$why');
      if (p.values.isEmpty && p.backend.confirmed) {
        expect(events.where((e) => e == OverlayEventType.shown), hasLength(1),
            reason: 'I3 活跃条目的成功可见确认必须产生 shown\n$why');
      }
      expect(events.where((e) => e == OverlayEventType.ended).length,
          p.values.length,
          reason: 'I3\n$why');
      expect(p.backend.presents, lessThanOrEqualTo(1), reason: 'I4\n$why');
      expect(p.backend.dismisses, lessThanOrEqualTo(p.backend.presents),
          reason: 'I4\n$why');
      if (p.suppressedInQueue) {
        expect(p.events.last.reason, OverlayEndReason.suppressed,
            reason: 'S2\n$why');
      }
      if (p.endedOnSubmit) {
        expect(p.backend.presents, 0, reason: 'B3\n$why');
        expect(p.values, [null], reason: 'B3\n$why');
        final reason =
            p.ticket != null ? p.outcome?.reason : p.events.last.reason;
        expect(reason, p.expectedSubmitReason, reason: 'B3\n$why');
      }
      if (p.selfValue != null) {
        expect(p.values, [p.selfValue], reason: 'X1\n$why');
        expect(p.events.last.reason, OverlayEndReason.closed,
            reason: 'X1\n$why');
        if (p.ticket != null) {
          expect(p.outcome?.value, p.selfValue, reason: 'X1\n$why');
          expect(p.outcome?.reason, OverlayEndReason.closed,
              reason: 'X1\n$why');
        }
      }
      if (ended) expect(p.values.length, 1, reason: 'I6\n$why');
    }
  }

  /// 混入所有新操作及普通关闭、同 id 接管、暂停和延迟释放。
  Future<void> step(int step) async {
    final id = _ids[random.nextInt(_ids.length)];
    final op = random.nextInt(16);
    log.add('步骤=$step op=$op id=$id');
    switch (op) {
      case 0 || 1 || 2 || 3:
        submit(id);
      case 4:
        await tester.pumpWidget(Column(children: [
          AnimatedBuilder(
            animation: manager,
            builder: (context, child) => const SizedBox.shrink(),
          ),
          _BuildOpen(() {
            building = true;
            try {
              submit(id, fromBuild: true);
            } finally {
              building = false;
            }
          }, key: ValueKey('$seed:$step')),
        ]));
      case 5:
        reset(id);
      case 6:
        reset();
      case 7:
        clearTag(tags[random.nextInt(tags.length)]);
      case 8:
        context = {
          'route': random.nextBool() ? _home : _blocked,
          _rolesKey: {
            if (random.nextBool()) _readerRole,
            if (random.nextBool()) _adminRole
          },
          _enabledKey: random.nextBool(),
          _tenantKey: random.nextInt(2),
        };
        log.add('context=$context');
        manager.setContext(context);
      case 9:
        final p = latest[id];
        if (p?.context != null && manager.isShowing(id) && p!.values.isEmpty) {
          log.add('ctx.close $id guard=${p.guard}');
          final record = manager.recordOf(id);
          p.context!.close(42);
          if (p.guard) {
            _cover('ctx.close 允许');
            p.selfValue = 42;
          } else {
            _cover('ctx.close 拒绝');
            expect(identical(manager.recordOf(id)?.data, record?.data), isTrue,
                reason: 'X1\n$diagnostic');
            expect(manager.isShowing(id), isTrue, reason: 'X1\n$diagnostic');
            expect(p.backend.dismisses, 0, reason: 'X1\n$diagnostic');
          }
        }
      case 10:
        manager.close(id, 11);
      case 11:
        latest[id]?.backend.finish(7);
      case 12:
        paused = !paused;
        if (paused) {
          manager.pauseAll();
        } else {
          manager.resumeAll();
        }
      case 13:
        manager.remove(id);
      case 15:
        suppress(id);
      case 14:
        final status = manager.cooldownStatus(id, cooldowns[_ids.indexOf(id)]);
        log.add(
            'status canShow=${status.canShow} permanent=${status.permanentlyBlocked} wait=${status.wait}');
    }
    final elapsed = Duration(milliseconds: random.nextInt(250));
    log.add('pump $elapsed');
    await pump(elapsed);
  }

  /// 两轮排空足够完成慢写串行补写，并验证销毁后没有迟到展示。
  Future<void> finish() async {
    log.add('clear + dispose');
    manager.clear();
    manager.dispose();
    final before = presents;
    await pump(_drain);
    await pump(_drain);
    expect(presents, before, reason: 'I7\n$diagnostic');
    expect(manager.records, isEmpty, reason: 'I6\n$diagnostic');
    check(ended: true);
  }
}
