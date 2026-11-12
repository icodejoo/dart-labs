import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';

// 以下保留 visible 版 README 英文配方正文，仅增加函数包装和 return，供分析器及 widget 测试执行。
// bottom sheet 按 README 指示只替换 route 构造；不借用其他演示的 presenter helper。

/// 配方出处：README 第「GetX dialog / bottom sheet」节；通过真实后端打开并交付结果。
Future<bool?> openReadmeGetxDialog(Layerman manager) {
  return manager.open<bool>(
    id: 'confirm',
    present: (ctx) {
      final navigator = Get.key.currentState!;
      final route = DialogRoute<bool>(
        context: navigator.context,
        settings: RouteSettings(name: 'om://${ctx.id}'),
        builder: (_) => const ConfirmDialog(),
      );
      // 出处：visible 版 README，路由首帧确认与定向关闭统一交给 presentRoute。
      return presentRoute(navigator, route);
    },
  );
}

/// 配方出处：README 第「GetX dialog / bottom sheet」节；通过真实后端打开并交付结果。
Future<bool?> openReadmeGetxBottomSheet(Layerman manager) {
  return manager.open<bool>(
    id: 'confirm',
    present: (ctx) {
      final navigator = Get.key.currentState!;
      final route = ModalBottomSheetRoute<bool>(
        settings: RouteSettings(name: 'om://${ctx.id}'),
        builder: (_) => const ConfirmDialog(),
        isScrollControlled: false,
      );
      // 出处：visible 版 README，路由首帧确认与定向关闭统一交给 presentRoute。
      return presentRoute(navigator, route);
    },
  );
}

/// 配方出处：README 第「GetX snackbar」节；通过真实后端打开并交付结果。
Future<void> openReadmeGetxSnackbar(Layerman manager) {
  return manager.open<void>(
    id: 'saved',
    slot:
        'snack', // a dedicated lane so a toast can coexist with a modal dialog
    present: (ctx) {
      final visible = Completer<void>();
      final c = Get.snackbar('Saved', 'Your changes are safe.',
        messageText: OverlayVisibility(visible: visible, child: const Text('Your changes are safe.')),
      );
      return PresentedOverlay<void>(
        visible: visible.future,
        dismissed: c.future,
        dismiss: ([_]) => c.close(),
      );
    },
  );
}

/// 配方出处：README 第「bot_toast」节；通过真实后端打开并交付结果。
Future<void> openReadmeBotToast(Layerman manager) {
  return manager.open<void>(
    id: 'tip',
    slot: 'toast',
    present: (ctx) {
      final visible = Completer<void>();
      final done = Completer<void>();
      final cancel = BotToast.showCustomText(
        toastBuilder: (_) => OverlayVisibility(visible: visible, child: Card(child: Text('Copied to clipboard'))),
        onlyOne: false, // replace decisions belong to the manager
        onClose: () => done.complete(), // fires after the exit animation
      );
      return PresentedOverlay<void>(
        visible: visible.future,
        dismissed: done.future,
        dismiss: ([_]) async => cancel(),
      );
    },
  );
}

/// README 中留给业务方实现的确认内容，供可编译配方使用。
class ConfirmDialog extends StatelessWidget {
  /// 创建静态确认内容。
  const ConfirmDialog({super.key});

  /// 在配方的路由中渲染确认内容。
  @override
  Widget build(BuildContext context) =>
      const AlertDialog(title: Text('Confirm'));
}
