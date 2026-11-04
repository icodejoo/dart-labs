import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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

/// 每次提交一个后端，计数绑定提交身份而非可复用的 id。
class _FakeBackend {
  /// 配置正常、延迟、永不结束或展示异常。
  _FakeBackend(this.mode);

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
    return PresentedOverlay<int>(
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

  /// overlap 优先于 replace，决定 I1 的串行分类。
  final bool overlap;

  /// 本次提交专属后端。
  final _FakeBackend backend;

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
  _Scenario(this.seed, this.tester) : random = Random(seed) {
    zoneEnabled = random.nextBool();
    manager = Layerman(
      now: () => clock,
      gap: random.nextBool() ? Duration.zero : const Duration(milliseconds: 50),
      dismissTimeout: _timeout,
      resolveTimeout: _timeout,
      cooldownStorage: MemoryCooldownStorage(),
      pauseOnRoutes: zoneEnabled ? const [_blocked] : const [],
      slots: random.nextBool()
          ? const {'b': OverlaySlotOptions(maxQueued: 2, gap: _slow)}
          : const {},
    );
    subscription = manager.events.listen(_event);
    addTearDown(manager.dispose);
    addTearDown(subscription.cancel);
  }

  /// 可复现的种子。
  final int seed;

  /// fake async 时钟驱动器。
  final WidgetTester tester;

  /// 唯一随机源。
  final Random random;

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
    final overlap = flags == 2 || flags == 3;
    final replace = flags == 1 || flags == 3;
    final affix = flags == 4;
    final priority = random.nextInt(4) - 1;
    final resolver = random.nextInt(7);
    final guard = random.nextInt(6);
    final condition = random.nextInt(5);
    final cooldown = random.nextInt(5);
    final backend =
        _FakeBackend(random.nextInt(12) == 0 ? 3 : random.nextInt(3));
    final delay = random.nextBool() ? null : _slow;
    final duration = random.nextBool() ? null : _slow;
    final exit = random.nextBool() ? null : _slow;
    final expiry = random.nextBool() ? null : _timeout;
    log.add('submit $id slot=$slot priority=$priority replace=$replace '
        'overlap=$overlap affix=$affix resolve=$resolver guard=$guard '
        'condition=$condition cooldown=$cooldown backend=${backend.mode} '
        'delay=$delay duration=$duration exit=$exit expireAfter=$expiry');
    final probe = _TicketProbe(id, overlap, backend);
    probes.add(probe);
    latest[id] = probe;
    probe.watch(manager.submit<int>(
      id: id,
      slot: slot,
      present: backend.present,
      data: const {'initial': true},
      priority: priority,
      replace: replace,
      overlap: overlap,
      affix: affix,
      delay: delay,
      duration: duration,
      exitDuration: exit,
      expireAfter: expiry,
      route: condition == 1 ? _home : null,
      requiresAuth: condition == 2 ? true : (condition == 3 ? false : null),
      when: condition == 4 ? (context) => context['auth'] == true : null,
      cooldown: switch (cooldown) {
        1 => const OverlayCooldown(session: 1),
        2 => const OverlayCooldown(minGap: _timeout),
        3 => const OverlayCooldown(day: 1),
        _ => null,
      },
      resolve: resolver < 2
          ? null
          : () async {
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
    final why = diagnostic;
    final records = manager.records;
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
          r.slot == slot && r.phase != 'pending' && !latest[r.id]!.overlap);
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
          p.backend.mode == 3 ? 0 : p.backend.presents,
          reason: 'I3 shown 与后端展示不一致\n$detail');
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
        replace: entry.replace,
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
    testWidgets('无条件串行排序不变量 seed=$seed', (tester) => _ordering(seed, tester));
  }
}
