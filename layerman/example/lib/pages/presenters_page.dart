import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../demo_kit/demo_kit.dart';
import '../helpers.dart';
import '../demo_text.dart';

/// bot_toast 的品牌名称。
const _botToastName = 'bot_toast';

/// 可切换的已有 UI 后端，不引入额外依赖。
enum DemoBackend {
  /// 官方对话框。
  dialog('Material dialog', 'Material 对话框'),

  /// 官方底部弹层。
  sheet('Material sheet', 'Material 底部弹层'),

  /// GetX 路由对话框。
  getx('GetX dialog', 'GetX 对话框'),

  /// GetX 独立 snackbar。
  snackbar('GetX snackbar', 'GetX 消息条'),

  /// bot_toast 提示。
  botToast(_botToastName, _botToastName),

  /// shadcn 对话框。
  shadDialog('shadcn dialog', 'shadcn 对话框'),

  /// shadcn 可拖动底部弹层。
  shadSheet('shadcn sheet', 'shadcn 底部弹层'),

  /// shadcn 提示。
  shadToast('shadcn toast', 'shadcn 提示'),

  /// 跨 UI 库依次执行。
  mixed('Mixed sequence', '跨库串行');

  /// 保存后端双语名称。
  const DemoBackend(this.en, this.zh);

  /// 英文名称。
  final String en;

  /// 中文名称。
  final String zh;
}

/// 合并原外部后端与混合 UI 页面，保留所有后端类型。
class PresentersPage extends StatelessWidget {
  /// 创建真实 UI 后端页面。
  const PresentersPage({super.key});

  /// 构建响应式后端目录。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'UI backends', 'UI 后端'),
    description: tr(
      context,
      'Open real dialogs, sheets and toasts. Replay clears the card’s manager and starts a fresh presentation.',
      '打开真实对话框、底部弹层与提示。重放会清理当前卡片的 manager，并重新展示。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Choose a presenter', '选择展示后端'),
        code: '''final manager = Layerman();
final dialogs = DialogManager(navigatorKey);
final ticket = manager.submit<bool>(
  present: dialogs<bool>((context, close) => AlertDialog(
    title: const Text('Confirm'),
    actions: [TextButton(onPressed: () => close(true), child: const Text('OK'))],
  )),
);
final outcome = await ticket.outcome;
manager.dispose();''',
        child: DemoGrid(
          children: [
            for (final backend in DemoBackend.values)
              DemoGridItem(child: BackendDemo(backend: backend)),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'Adapters wait for first paint and target their own route or handle when dismissing. For custom backends, see helpers.dart and the tested README recipes.',
          '适配器等待首帧绘制；关闭只针对自己的路由或句柄。自定义后端可参考 helpers.dart 与已有测试的 README 配方。',
        ),
      ),
    ],
  );
}

/// 管理外部控制器的卡片，重放同时重置引擎及真实 UI。
class BackendDemo extends StatefulWidget {
  /// 创建后端卡片。
  const BackendDemo({super.key, required this.backend});

  /// 当前后端类型。
  final DemoBackend backend;

  /// 创建后端状态。
  @override
  State<BackendDemo> createState() => _BackendDemoState();
}

/// 保存后端 manager 与重复点击的清理状态。
class _BackendDemoState extends State<BackendDemo> {
  /// 当前卡片专用的编排器。
  Layerman _manager = Layerman();

  /// 最近的结束原因。
  OverlayEndReason? _reason;

  /// 当前是否正在重放。
  bool _restarting = false;

  /// 使用已有后端提供真实弹层；所有关闭都经过 ctx.close。
  PresentedOverlay<void> _present(
    DemoBackend backend,
    PresentContext<void> ctx,
  ) {
    final title = tr(context, backend.en, backend.zh);
    final closeLabel = tr(context, 'Close', '关闭');
    final dialog = AlertDialog(
      title: Text(title),
      content: Text(
        tr(
          context,
          'This UI is sequenced by layerman.',
          '此弹层的展示顺序由 layerman 编排。',
        ),
      ),
      actions: [TextButton(onPressed: ctx.close, child: Text(closeLabel))],
    );
    switch (backend) {
      case DemoBackend.dialog:
        return DialogManager(Get.key)<void>((_, close) => dialog)(ctx);
      case DemoBackend.sheet:
        return BottomSheetManager(Get.key)<void>(
          (_, close) => Padding(
            padding: const EdgeInsets.all(DemoTokens.sectionGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                TextButton(onPressed: close, child: Text(closeLabel)),
              ],
            ),
          ),
        )(ctx);
      case DemoBackend.getx:
        return presentRouteDialog<void>(ctx, dialog, useGetx: true);
      case DemoBackend.snackbar:
        return presentGetxSnackbar(
          title,
          tr(context, 'Saved successfully', '保存成功'),
        );
      case DemoBackend.botToast:
        return presentBotToastText(
          tr(context, 'Copied to clipboard', '已复制到剪贴板'),
        );
      case DemoBackend.shadDialog:
        return presentShadDialog<void>(
          ctx,
          ShadDialog(
            title: Text(title),
            actions: [
              ShadButton(onPressed: ctx.close, child: Text(closeLabel)),
            ],
          ),
        );
      case DemoBackend.shadSheet:
        final visible = Completer<void>();
        final captured = RouteCapture<void>();
        final dismissed = showShadSheet<void>(
          context: Get.overlayContext!,
          side: ShadSheetSide.bottom,
          builder: (sheetContext) {
            captured.capture(sheetContext);
            return OverlayVisibility(
              visible: visible,
              child: ShadSheet(
                title: Text(title),
                draggable: true,
                expandable: true,
                actions: [
                  ShadButton(onPressed: ctx.close, child: Text(closeLabel)),
                ],
              ),
            );
          },
        );
        return PresentedOverlay<void>(
          visible: visible.future,
          dismissed: captured.waitForExit(dismissed),
          dismiss: ([_]) async => captured.dismiss(),
        );
      case DemoBackend.shadToast:
        return presentShadToast(
          ctx,
          title: Text(title),
          description: Text(tr(context, 'One queue, any UI', '一个队列，多种 UI')),
        );
      case DemoBackend.mixed:
        throw StateError('Mixed sequences submit individual backends.');
    }
  }

  /// 清理当前展示后重新创建 manager，再开始所选后端序列。
  Future<void> _replay() async {
    if (_restarting) return;
    setState(() => _restarting = true);
    _manager.dispose();
    // 等旧路由退场，避免新旧 GetX 和 shadcn 动画重叠。
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    final manager = _manager = Layerman();
    setState(() {
      _reason = null;
      _restarting = false;
    });
    final backends = widget.backend == DemoBackend.mixed
        ? [
            DemoBackend.dialog,
            DemoBackend.getx,
            DemoBackend.botToast,
            DemoBackend.shadToast,
          ]
        : [widget.backend];
    for (final backend in backends) {
      final ticket = manager.submit<void>(
        id: backend.name,
        present: (ctx) => _present(backend, ctx),
      );
      ticket.outcome.then((outcome) {
        if (mounted && identical(manager, _manager)) {
          setState(() => _reason = outcome.reason);
        }
      });
    }
  }

  /// 卸载页面时清理本卡片全部后端。
  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  /// 显式连接外部控制器的重放，并显示实时队列状态。
  @override
  Widget build(BuildContext context) => DemoCard(
    title: tr(context, widget.backend.en, widget.backend.zh),
    description: tr(
      context,
      'First paint → visible; exit complete → next.',
      '首帧确认可见，退场完成后放行下一项。',
    ),
    onReplay: _replay,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          onPressed: _restarting ? null : _replay,
          child: Text(tr(context, 'Open demo', '打开演示')),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        ListenableBuilder(
          listenable: _manager,
          builder: (context, _) => Text(
            '${tr(context, 'Active', '激活')} ${_manager.activeIds.length} · '
            '${tr(context, 'Queued', '排队')} ${_manager.queuedIds.length}',
          ),
        ),
        if (_reason != null)
          Text(
            '${tr(context, 'Outcome', '结束原因')}: ${demoEndReason(context, _reason!)}',
          ),
      ],
    ),
  );
}
