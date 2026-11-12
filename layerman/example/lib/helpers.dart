import 'dart:async';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'manager.dart';

/// 后端提示的默认展示时长。
const _toastDuration = Duration(seconds: 2);

/// GetX 消息条的进退场动画时长。
const _snackbarMotion = Duration(milliseconds: 300);

/// 合成路由名的统一前缀。
const _routePrefix = 'om://';

/// 只关闭捕获的路由，保持其他并行展示不受影响。
void _removeRoute(Route<Object?>? route) {
  final navigator = route?.navigator;
  if (route == null || navigator == null || !route.isActive) return;
  if (route.isCurrent && !route.willHandlePopInternally) {
    navigator.pop();
  } else {
    navigator.removeRoute(route);
  }
}

/// 保存本次展示的路由，并记录首帧前到达的关闭请求。
class RouteCapture<T> {
  /// 当前展示拥有的路由。
  Route<T>? route;

  /// 是否已在路由创建前收到关闭请求。
  bool _earlyDismiss = false;

  /// 从内容上下文捕获准确路由。
  void capture(BuildContext context) {
    route ??= ModalRoute.of(context) as Route<T>?;
    if (_earlyDismiss) {
      _earlyDismiss = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _removeRoute(route));
    }
  }

  /// 关闭本次路由，必要时推迟到路由被捕获之后。
  void dismiss() {
    if (route == null) {
      _earlyDismiss = true;
    } else {
      _removeRoute(route);
    }
  }

  /// 等弹出结果及路由动画完全结束后，再允许队列推进。
  Future<T?> waitForExit(Future<T?> popped) async {
    final result = await popped;
    final captured = route;
    if (captured is TransitionRoute<T>) await captured.completed;
    return result;
  }
}

/// 通过原生对话框展示内容；关闭回调绑定当前条目的守卫。
PresentedOverlay<T> presentCard<T>(
  PresentContext<T> ctx,
  Widget Function(BuildContext context, void Function([Object? result]) close)
  contentBuilder, {
  Color barrierColor = const Color(0x00000000),
  bool barrierDismissible = false,
}) {
  final visible = Completer<void>();
  final captured = RouteCapture<T>();
  final dismissed = showDialog<T>(
    context: Get.overlayContext!,
    barrierColor: barrierColor,
    barrierDismissible: barrierDismissible,
    routeSettings: RouteSettings(name: '$_routePrefix${ctx.id}'),
    builder: (context) {
      captured.capture(context);
      return OverlayVisibility(
        visible: visible,
        child: contentBuilder(context, ([result]) => ctx.close(result as T?)),
      );
    },
  );
  return PresentedOverlay<T>(
    visible: visible.future,
    dismissed: captured.waitForExit(dismissed),
    dismiss: ([result]) async => captured.dismiss(),
  );
}

/// 通过非模态 OverlayEntry 展示，保留 Positioned 的父数据契约。
PresentedOverlay<T> presentEntry<T>(
  Widget Function(void Function([Object? result]) close) contentBuilder,
) {
  final visible = Completer<void>();
  final dismissed = Completer<T?>();
  late final OverlayEntry entry;

  /// 精确移除本次 entry 并传回结果。
  void close([Object? result]) {
    if (dismissed.isCompleted) return;
    dismissed.complete(result as T?);
    entry.remove();
    entry.dispose();
  }

  entry = OverlayEntry(
    builder: (_) {
      final content = contentBuilder(close);
      if (content is Positioned) {
        return Positioned(
          left: content.left,
          top: content.top,
          right: content.right,
          bottom: content.bottom,
          width: content.width,
          height: content.height,
          child: OverlayVisibility(visible: visible, child: content.child),
        );
      }
      return OverlayVisibility(visible: visible, child: content);
    },
  );
  Get.key.currentState!.overlay!.insert(entry);
  return PresentedOverlay<T>(
    visible: visible.future,
    dismissed: dismissed.future,
    dismiss: ([result]) async => close(result),
  );
}

/// 通过已有 Material 或 GetX 对话框确认首帧并精确关闭。
PresentedOverlay<T> presentRouteDialog<T>(
  PresentContext<T> ctx,
  Widget dialog, {
  bool useGetx = false,
}) {
  final visible = Completer<void>();
  final captured = RouteCapture<T>();
  final settings = RouteSettings(name: '$_routePrefix${ctx.id}');
  final wrapped = Builder(
    builder: (context) {
      captured.capture(context);
      return OverlayVisibility(visible: visible, child: dialog);
    },
  );
  final dismissed = useGetx
      ? Get.dialog<T>(wrapped, routeSettings: settings)
      : showDialog<T>(
          context: Get.overlayContext!,
          routeSettings: settings,
          builder: (_) => wrapped,
        );
  return PresentedOverlay<T>(
    visible: visible.future,
    dismissed: captured.waitForExit(dismissed),
    dismiss: ([result]) async => captured.dismiss(),
  );
}

/// 用 snackbar 自身的控制器关闭，避免误弹导航栈。
PresentedOverlay<void> presentGetxSnackbar(
  String title,
  String message, {
  Duration duration = _toastDuration,
}) {
  final visible = Completer<void>();
  final controller = Get.snackbar(
    title,
    message,
    messageText: OverlayVisibility(visible: visible, child: Text(message)),
    duration: duration,
    animationDuration: _snackbarMotion,
  );
  return PresentedOverlay<void>(
    visible: visible.future,
    dismissed: controller.future,
    dismiss: ([_]) => controller.close(),
  );
}

/// 等待 bot_toast 的 onClose 通知实际退场完成。
PresentedOverlay<void> presentBotToastText(
  String text, {
  Duration duration = _toastDuration,
}) {
  final visible = Completer<void>();
  final dismissed = Completer<void>();
  final cancel = BotToast.showCustomText(
    toastBuilder: (_) => OverlayVisibility(
      visible: visible,
      child: Card(
        child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
      ),
    ),
    duration: duration,
    onlyOne: false,
    onClose: () {
      if (!dismissed.isCompleted) dismissed.complete();
    },
  );
  return PresentedOverlay<void>(
    visible: visible.future,
    dismissed: dismissed.future,
    dismiss: ([_]) async => cancel(),
  );
}

/// 让 shadcn 对话框继承宿主亮暗主题并精确关闭。
PresentedOverlay<T> presentShadDialog<T>(PresentContext<T> ctx, Widget dialog) {
  final visible = Completer<void>();
  final captured = RouteCapture<T>();
  final dismissed = showShadDialog<T>(
    context: Get.overlayContext!,
    routeSettings: RouteSettings(name: '$_routePrefix${ctx.id}'),
    builder: (context) {
      captured.capture(context);
      return OverlayVisibility(visible: visible, child: dialog);
    },
  );
  return PresentedOverlay<T>(
    visible: visible.future,
    dismissed: captured.waitForExit(dismissed),
    dismiss: ([result]) async => captured.dismiss(),
  );
}

/// 自主管理 shadcn 提示的时长，等待 hide 的实际退场完成。
PresentedOverlay<void> presentShadToast(
  PresentContext<void> ctx, {
  Widget? title,
  required Widget description,
  ShadToastVariant variant = ShadToastVariant.primary,
  Duration duration = Duration.zero,
}) {
  final visible = Completer<void>();
  final dismissed = Completer<void>();
  final sonner = shadSonnerKey.currentState!;
  final id = sonner.show(
    ShadToast.raw(
      variant: variant,
      title: title,
      description: OverlayVisibility(visible: visible, child: description),
      duration: const Duration(days: 1),
    ),
  );
  Timer? timer;
  var closing = false;

  /// 合并超时和主动关闭，避免同一 toast 重复 hide。
  Future<void> finish() async {
    if (closing) return dismissed.future;
    closing = true;
    timer?.cancel();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      final afterFrame = Completer<void>();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => afterFrame.complete(),
      );
      await afterFrame.future;
    }
    if (sonner.mounted) await sonner.hide(id);
    if (!dismissed.isCompleted) dismissed.complete();
  }

  timer = Timer(duration == Duration.zero ? _toastDuration : duration, finish);
  return PresentedOverlay<void>(
    visible: visible.future,
    dismissed: dismissed.future,
    dismiss: ([_]) => finish(),
  );
}
