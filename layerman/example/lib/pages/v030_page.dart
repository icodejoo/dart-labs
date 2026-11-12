import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';

import '../helpers.dart';
import '../manager.dart';

/// 不绑定可被重启替换的 manager，展示时读取当前导航器。
final _dialogs = DialogManager(Get.key);

/// 与对话框共用根导航器的底部弹层工厂。
final _sheets = BottomSheetManager(Get.key);

/// 演示和回归测试共用的条目标识与文案。
const _dmA = 'dm-a', _dmB = 'dm-b', _outcome = 'outcome';

/// 路由后端的展示文案。
const _aText = 'DM-A', _bText = 'DM-B', _sheetText = 'BS-1';

/// 数据和超时演示标识。
const _live = 'live', _stuck = 'stuck', _after = 'AFTER';

/// 过期演示标识。
const _blocker = 'blocker', _exp = 'exp';

/// 冷却查询演示的标识和固定配置。
const _cdq = 'cdq', _cdqText = 'CDQ';

/// 每次重置后仅允许展示一次。
const _queryCooldown = OverlayCooldown(session: 1);

/// 标签演示共用的标签。
const _promoTag = 'promo';

/// build 期间提交的条目标识和文案。
const _buildOpen = 'build-open', _buildText = 'BUILD-OPEN';

/// 页面与弹窗共用的操作键。
const _closeAKey = 'btn-dm-close-a', _replaceKey = 'btn-outcome-replace';

/// 延迟、守卫关闭和角色权限演示的条目标识与文案。
const _ovd = 'OVD', _ctx = 'CTX', _vip = 'VIP-ONLY';

/// 角色判断与登录按钮共用的上下文键和角色名。
const _userKey = 'user', _rolesKey = 'roles', _vipRole = 'vip';

/// ticket 尚未结束时的页面文案。
const _ctxPendingOutcome = 'ctx: - -';

/// 抑制与跨槽位演示的条目标识，同时用作卡片文案。
const _sup = 'SUP', _blkModal = 'BLK-MODAL';

/// 串行与并行 toast 的标识和文案。
const _blkToast = 'BLK-TOAST', _blkOverlap = 'BLK-OVL';

/// 不限制次数，仅接受显式抑制。
const _suppressCooldown = OverlayCooldown();

/// 展示 0.3.0 的路由后端、结果、实时数据与队列保护。
class V030Page extends StatefulWidget {
  /// 创建演示页；所有操作使用当前全局 manager。
  const V030Page({super.key});

  @override
  State<V030Page> createState() => _V030PageState();
}

/// 保存演示结果并清理故意失联的后端视图。
class _V030PageState extends State<V030Page> {
  /// 最近一次抑制演示提交的结果。
  String _supOutcome = 'sup: - -';

  /// 最近查询的抑制状态。
  String _supStatus = 'sup: -';

  /// 根据本次返回值抑制后续提交，关闭始终经身份绑定的 ctx.close。
  Future<void> _openSuppress() async {
    final manager = om;
    final ticket = manager.submit<String>(
      id: _sup,
      cooldown: _suppressCooldown,
      present: (ctx) => presentEntry<String>(
        (_) => Positioned(
          right: 16,
          bottom: 80,
          child: SizedBox(
            width: 260,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(_sup),
                    for (final (key, value, label) in const [
                      ('sup-close', 'close', '关闭'),
                      ('sup-later', 'later', '稍后提示（5 秒）'),
                      ('sup-never', 'never', '不再提示'),
                    ])
                      TextButton(
                        key: Key(key),
                        onPressed: () => ctx.close(value),
                        child: Text(label),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final outcome = await ticket.outcome;
    if (!mounted || !identical(manager, om)) return;
    if (outcome.value == 'never') manager.suppress(_sup);
    if (outcome.value == 'later') {
      // 演示仅等待 5 秒；真实应用一般用天作为稍后提示的间隔。
      manager.suppress(_sup, duration: const Duration(seconds: 5));
    }
    setState(() {
      _supOutcome = 'sup: ${outcome.reason.name} ${outcome.value}';
    });
  }

  /// 查询抑制资格快照，不改变当前提交。
  void _querySuppressStatus() {
    final status = om.cooldownStatus(_sup, _suppressCooldown);
    setState(() {
      _supStatus =
          'sup: canShow=${status.canShow} '
          'suppressed=${status.suppressed} '
          'permanent=${status.permanentlyBlocked}';
    });
  }

  /// toast 在 modal 占位期间等待；overlap 同样由 blockedBy 持有。
  void _openBlockedToast({bool overlap = false}) {
    final text = overlap ? _blkOverlap : _blkToast;
    om.submit<void>(
      id: text,
      slot: toastSlot,
      mode: overlap ? OverlayMode.overlap : OverlayMode.queue,
      present: (_) => presentEntry<void>(
        (close) => Positioned(
          right: 16,
          top: 24,
          child: SizedBox(
            width: 260,
            height: 160,
            child: buildCard(text, close),
          ),
        ),
      ),
    );
  }

  /// 使用官方对话框占用 modal 槽位，关闭后自动放行 toast。
  void _openBlockingModal() => om.open<void>(
    id: _blkModal,
    slot: modalSlot,
    present: _dialogs<void>(
      (ctx, close) => AlertDialog(
        title: const Text(_blkModal),
        actions: [
          demoButton('blk-toast', '排队 toast', () => _openBlockedToast()),
          demoButton(
            'blk-toast-overlap',
            'overlap toast',
            () => _openBlockedToast(overlap: true),
          ),
          demoButton('blk-modal-close', '关闭', () => close()),
        ],
      ),
    ),
  );

  /// 非路由卡片的关闭锁；每次打开重置为锁定。
  bool _ctxLocked = true;

  /// 最近一次非路由卡片的票据结果。
  String _ctxOutcome = _ctxPendingOutcome;

  /// 延迟一秒展示非模态 overlap，等待期间可从页面移除。
  void _openOverlapDelay() => om.open<void>(
    id: _ovd,
    mode: OverlayMode.overlap,
    delay: const Duration(seconds: 1),
    present: (_) => presentEntry<void>((close) => _floatingCard(_ovd, close)),
  );

  /// 以当前锁状态守卫 ctx.close，并展示 ticket 的结束原因和返回值。
  Future<void> _openContextClose() async {
    setState(() {
      _ctxLocked = true;
      _ctxOutcome = _ctxPendingOutcome;
    });
    final ticket = om.submit<String>(
      id: _ctx,
      beforeClose: () => !_ctxLocked,
      present: (ctx) => presentEntry<String>(
        (_) => Positioned(
          right: 16,
          top: 100,
          child: SizedBox(
            width: 240,
            height: 160,
            child: Card(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(_ctx),
                  TextButton(
                    key: const Key('ctx-close'),
                    onPressed: () => ctx.close('ok'),
                    child: const Text('关闭并返回 ok'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final outcome = await ticket.outcome;
    if (mounted) {
      setState(
        () => _ctxOutcome = 'ctx: ${outcome.reason.name} ${outcome.value}',
      );
    }
  }

  /// 非 VIP 排队等待；获得角色后展示，退出后自动撤下。
  void _openVip() => om.open<void>(
    id: _vip,
    auth: (ctx) => (ctx[_rolesKey] as Set?)?.contains(_vipRole) ?? false,
    dismissWhenUnmet: true,
    present: (_) => presentEntry<void>((close) => _floatingCard(_vip, close)),
  );

  /// 点击后挂载在 build 中提交条目的小组件。
  bool _showBuildOpen = false;

  /// 最近查询得到的冷却状态文案。
  String _cooldownLabel = 'cdq: -';

  /// 最近一次 ticket 的结束原因。
  String _reason = '-';

  /// 实时更新计数器。
  int _counter = 0;

  /// 故意不响应 dismiss 的视图由页面负责最终清理。
  OverlayEntry? _stuckEntry;

  /// 打开官方对话框，可选择路由条件或并行覆盖。
  void _openDialog({bool gated = false, bool buried = false}) {
    om.open<void>(
      id: _dmA,
      route: gated ? const RouteMatcher.exact('/home') : null,
      present: _dialogs<void>(
        (ctx, close) => AlertDialog(
          title: const Text(_aText),
          actions: [
            TextButton(
              key: const Key('dm-a-close'),
              onPressed: () => close(),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    if (buried) {
      om.open<void>(
        id: _dmB,
        mode: OverlayMode.overlap,
        present: _dialogs<void>(
          (ctx, close) => AlertDialog(
            title: const Text(_bText),
            actions: [
              demoButton(_closeAKey, '关闭下层 A', () => om.close(_dmA)),
              TextButton(
                key: const Key('dm-b-close'),
                onPressed: () => close(),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// 用 replace 结束当前 ticket；弹窗内同样可触发。
  void _replaceOutcome() =>
      openCard('outcome-next', text: 'NEXT', mode: OverlayMode.replace);

  /// 直接提交 ticket，显式 close 以得到 closed 原因。
  Future<void> _openOutcome() async {
    final ticket = om.submit<void>(
      id: _outcome,
      present: (ctx) => presentCard<void>(
        ctx,
        (context, close) => buildCard(
          'OUTCOME',
          ([Object? result]) => om.close(_outcome),
          actions: [demoButton(_replaceKey, '替换', _replaceOutcome)],
        ),
      ),
    );
    final outcome = await ticket.outcome;
    if (mounted) setState(() => _reason = outcome.reason.name);
  }

  /// 将非模态卡片约束在右上角，窄屏也可完整展示。
  Widget _floatingCard(String text, void Function([Object?]) close) =>
      Positioned(
        right: 16,
        top: 100,
        child: SizedBox(width: 240, height: 160, child: buildCard(text, close)),
      );

  /// 展示无需本地 notifier 镜像的实时数据卡片。
  void _openLive() {
    _counter = 0;
    om.open<void>(
      id: _live,
      data: const {'n': 0},
      present: (ctx) => presentEntry<void>(
        (close) => ValueListenableBuilder<Object?>(
          valueListenable: ctx.dataListenable,
          builder: (context, data, _) =>
              _floatingCard('live n=${(data as Map)['n']}', close),
        ),
      ),
    );
  }

  /// 查询当前冷却资格，并将快照显示在页面上。
  void _queryCooldownStatus() {
    final status = om.cooldownStatus(_cdq, _queryCooldown);
    setState(() {
      _cooldownLabel =
          'cdq: canShow=${status.canShow} '
          'permanent=${status.permanentlyBlocked}';
    });
  }

  /// 同时展示两张促销卡和一张无标签卡，竖向排布避免相互遮挡。
  void _openTagged() {
    const texts = ['TAG-P1', 'TAG-P2', 'TAG-N'];
    for (var i = 0; i < texts.length; i++) {
      final index = i;
      om.open<void>(
        id: texts[index],
        mode: OverlayMode.overlap,
        tags: index < 2 ? const {_promoTag} : null,
        present: (_) => presentEntry<void>(
          (close) => Positioned(
            right: 16,
            top: 80 + index * 170.0,
            child: SizedBox(
              width: 240,
              height: 160,
              child: buildCard(texts[index], close),
            ),
          ),
        ),
      );
    }
  }

  /// 模拟 dismissed 永不完成、dismiss 空实现的失联后端。
  void _openStuck() {
    _clearStuckView();
    om.open<void>(
      id: _stuck,
      present: (_) {
        final visible = Completer<void>();
        final never = Completer<void>();
        final entry = OverlayEntry(
          builder: (_) => Positioned(
            right: 16,
            top: 100,
            child: OverlayVisibility(
              visible: visible,
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('STUCK'),
                ),
              ),
            ),
          ),
        );
        _stuckEntry = entry;
        Get.key.currentState!.overlay!.insert(entry);
        return PresentedOverlay<void>(
          visible: visible.future,
          dismissed: never.future,
          dismiss: ([_]) async {},
        );
      },
    );
  }

  /// 超时仅释放引擎槽位，失联视图仍由后端持有者清理。
  void _clearStuckView() {
    _stuckEntry?.remove();
    _stuckEntry?.dispose();
    _stuckEntry = null;
  }

  /// 模拟进入后台：直接驱动生命周期监听器（持有暂停凭证），不动全局出帧开关。
  void _simulatePause() =>
      appLifecycle?.didChangeAppLifecycleState(AppLifecycleState.paused);

  /// 模拟回到前台：释放暂停凭证。
  void _simulateResume() =>
      appLifecycle?.didChangeAppLifecycleState(AppLifecycleState.resumed);

  /// 先占槽，再提交一秒内未获准展示即过期的条目。
  void _openExpire() {
    om.open<void>(
      id: _blocker,
      present: (_) =>
          presentEntry<void>((close) => _floatingCard('BLOCKER', close)),
    );
    om.open<void>(
      id: _exp,
      expireAfter: const Duration(seconds: 1),
      present: (ctx) =>
          presentCard<void>(ctx, (context, close) => buildCard('EXP', close)),
    );
  }

  @override
  void dispose() {
    _clearStuckView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeader(
          context,
          'v0.3 Features',
          '官方路由后端、可观测结果和队列保护。1.0 新增抑制与跨槽位互斥。',
        ),
        pageSection(context, '不再提示（suppress）', [
          demoButton('btn-sup-open', '打开 SUP', _openSuppress),
          demoButton('btn-sup-status', '查询抑制状态', _querySuppressStatus),
          demoButton('btn-sup-reset', '重置抑制', () => om.resetCooldown(_sup)),
          Text(_supOutcome, key: const Key('sup-label')),
          Text(_supStatus, key: const Key('sup-status')),
        ]),
        pageSection(context, '跨槽位互斥（blockedBy）', [
          demoButton('btn-blk-modal', '打开 modal', _openBlockingModal),
          demoButton('btn-blk-toast', '直接 toast', () => _openBlockedToast()),
          ListenableBuilder(
            listenable: om,
            builder: (context, _) {
              final shown =
                  om.activeIds.contains(_blkToast) ||
                  om.activeIds.contains(_blkOverlap);
              final queued =
                  om.queuedIds.contains(_blkToast) ||
                  om.queuedIds.contains(_blkOverlap);
              return Text(
                'blk: modal=${om.activeIds.contains(_blkModal)} '
                'toast=${shown
                    ? 'shown'
                    : queued
                    ? 'queued'
                    : '-'}',
                key: const Key('blk-label'),
              );
            },
          ),
        ]),
        pageSection(context, 'overlap 延迟出场', [
          demoButton('btn-ovd-open', '延迟打开 OVD', _openOverlapDelay),
          demoButton('btn-ovd-remove', '移除 OVD', () => om.remove(_ovd)),
        ]),
        pageSection(context, '非路由后端经守卫关闭', [
          demoButton('btn-ctx-open', '打开 CTX', _openContextClose),
          demoButton('btn-ctx-lock', '切换关闭锁', () {
            setState(() => _ctxLocked = !_ctxLocked);
          }),
          Text(
            'ctx-lock: ${_ctxLocked ? 'on' : 'off'}',
            key: const Key('ctx-lock-label'),
          ),
          Text(_ctxOutcome, key: const Key('ctx-outcome')),
        ]),
        pageSection(context, '按角色判断 auth', [
          demoButton('btn-login-user', '普通用户登录', () {
            om.setContext({_userKey: 'u1', _rolesKey: <String>{}});
          }),
          demoButton('btn-login-vip', 'VIP 登录', () {
            om.setContext({
              _userKey: 'u2',
              _rolesKey: {_vipRole},
            });
          }),
          demoButton('btn-logout', '退出登录', () {
            om.setContext({_userKey: null, _rolesKey: <String>{}});
          }),
          demoButton('btn-vip-open', '打开 VIP 卡片', _openVip),
        ]),
        pageSection(context, 'DialogManager / BottomSheetManager', [
          demoButton('btn-dm-open', '对话框', () => _openDialog()),
          demoButton(
            'btn-dm-route',
            '限定 /home',
            () => _openDialog(gated: true),
          ),
          demoButton(
            'btn-dm-buried',
            '叠放 A / B',
            () => _openDialog(buried: true),
          ),
          demoButton(_closeAKey, '关闭下层 A', () => om.close(_dmA)),
          demoButton(
            'btn-bs-open',
            '底部弹层',
            () => om.open<void>(
              id: 'bs',
              present: _sheets<void>(
                (ctx, close) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(_sheetText),
                      TextButton(
                        key: const Key('bs-close'),
                        onPressed: () => close(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]),
        pageSection(context, '结束原因', [
          demoButton('btn-outcome-open', '提交 ticket', _openOutcome),
          demoButton(_replaceKey, '替换', _replaceOutcome),
          Text('outcome: $_reason', key: const Key('outcome-label')),
        ]),
        pageSection(context, '实时数据', [
          demoButton('btn-live-open', '打开计数卡', _openLive),
          demoButton(
            'btn-live-update',
            'n + 1',
            () => om.update(_live, {'n': ++_counter}),
          ),
        ]),
        pageSection(context, '超时兜底', [
          demoButton('btn-stuck-open', '失联后端', _openStuck),
          demoButton('btn-stuck-close', '请求关闭', () => om.close(_stuck)),
          demoButton(
            'btn-after-stuck-open',
            '排队 AFTER',
            () => openCard('after-stuck', text: _after),
          ),
          demoButton('btn-stuck-clear', '清理失联视图', _clearStuckView),
        ]),
        pageSection(context, '后台暂停', [
          // 模拟前后台切换，仅用于演示；真实应用由系统发送生命周期事件。
          demoButton('btn-lifecycle-pause', '模拟后台', _simulatePause),
          demoButton('btn-lifecycle-resume', '模拟前台', _simulateResume),
          ListenableBuilder(
            listenable: om,
            builder: (context, _) =>
                Text('paused: ${om.isPaused}', key: const Key('paused-label')),
          ),
        ]),
        pageSection(context, 'build 期间打开', [
          demoButton('btn-build-open', '挂载 build 调用组件', () {
            setState(() => _showBuildOpen = true);
          }),
          if (_showBuildOpen) const _BuildOpenDemo(),
        ]),
        pageSection(context, '冷却查询与重置', [
          demoButton('btn-cdq-open', '打开 CDQ', () {
            om.open<void>(
              id: _cdq,
              cooldown: _queryCooldown,
              present: (_) =>
                  presentEntry<void>((close) => _floatingCard(_cdqText, close)),
            );
          }),
          demoButton('btn-cdq-status', '查询冷却', _queryCooldownStatus),
          demoButton('btn-cdq-reset', '重置冷却', () => om.resetCooldown(_cdq)),
          Text(_cooldownLabel, key: const Key('cdq-label')),
        ]),
        pageSection(context, '标签批量清理', [
          demoButton('btn-tag-open', '打开三张标签卡', _openTagged),
          demoButton('btn-tag-clear', '清理 promo', () => om.clearTag(_promoTag)),
        ]),
        pageSection(context, '队列保护', [
          demoButton('btn-expire-open', '排队并过期', _openExpire),
          demoButton('btn-expire-clear', '清理', () {
            om.remove(_exp);
            om.remove(_blocker);
          }),
        ]),
      ],
    ),
  );
}

/// 直接在 build 内提交一次，交由引擎推迟到帧后展示。
class _BuildOpenDemo extends StatefulWidget {
  /// 创建可反复重建但不重复提交的演示组件。
  const _BuildOpenDemo();

  @override
  State<_BuildOpenDemo> createState() => _BuildOpenDemoState();
}

/// 保存单次提交标志，不在页面重建时重复打开。
class _BuildOpenDemoState extends State<_BuildOpenDemo> {
  /// 当前组件是否已经提交过条目。
  bool _opened = false;

  @override
  Widget build(BuildContext context) {
    if (!_opened) {
      _opened = true;
      om.open<void>(
        id: _buildOpen,
        present: (_) => presentEntry<void>(
          (close) => Positioned(
            right: 16,
            top: 100,
            child: SizedBox(
              width: 240,
              height: 160,
              child: buildCard(_buildText, close),
            ),
          ),
        ),
      );
    }
    return const Text('已在 build 中提交');
  }
}
