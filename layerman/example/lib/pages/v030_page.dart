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

/// 页面与弹窗共用的操作键。
const _closeAKey = 'btn-dm-close-a', _replaceKey = 'btn-outcome-replace';

/// 展示 0.3.0 的路由后端、结果、实时数据与队列保护。
class V030Page extends StatefulWidget {
  /// 创建演示页；所有操作使用当前全局 manager。
  const V030Page({super.key});

  @override
  State<V030Page> createState() => _V030PageState();
}

/// 保存演示结果并清理故意失联的后端视图。
class _V030PageState extends State<V030Page> {
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
      route: gated ? '/home' : null,
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
        overlap: true,
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
      openCard('outcome-next', text: 'NEXT', replace: true);

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

  /// 模拟 dismissed 永不完成、dismiss 空实现的失联后端。
  void _openStuck() {
    _clearStuckView();
    om.open<void>(
      id: _stuck,
      present: (_) {
        final never = Completer<void>();
        final entry = OverlayEntry(
          builder: (_) => const Positioned(
            right: 16,
            top: 100,
            child: Card(
              child: Padding(padding: EdgeInsets.all(12), child: Text('STUCK')),
            ),
          ),
        );
        _stuckEntry = entry;
        Get.key.currentState!.overlay!.insert(entry);
        return PresentedOverlay<void>(
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
        pageHeader(context, 'v0.3 Features', '官方路由后端、可观测结果和队列保护。'),
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
