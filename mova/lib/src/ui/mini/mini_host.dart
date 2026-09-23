import 'package:flutter/widgets.dart';

import 'mini_ctl.dart';
import 'mini_window.dart';

/// A convenience wrapper that composites the mini window above the whole app.
///
/// Optional: it is exactly a [Stack] of your app content plus the window, and
/// hosts that prefer to own that [Stack] can skip this class entirely — see
/// the README for the equivalent hand-written snippet. Use it in
/// `MaterialApp.builder`, where [child] is the [Navigator] itself, so the
/// window is composited above every pushed route.
///
/// Renders nothing while [MovaMiniCtl.api] is `null`, while the api's
/// `MovaOpts.mini.enabled` is `false`, or while the window is mounted the
/// other way ([MovaMiniMount.page]) — the same api must never have two
/// rendering surfaces.
///
/// 把小窗合成到整个 App 之上的便利壳。
///
/// 可选：它就是"App 内容 + 小窗"两层 [Stack]，想自己掌控那个 [Stack] 的宿主
/// 完全可以不用它——README 里给了等价的手写代码。用在 `MaterialApp.builder`
/// 里，[child] 就是 [Navigator] 本身，因此小窗合成在所有已压入路由之上。
///
/// [MovaMiniCtl.api] 为 `null`、api 的 `MovaOpts.mini.enabled` 为 `false`、或小窗
/// 正以另一种方式挂载（[MovaMiniMount.page]）时，它什么都不渲染——同一个 api
/// 绝不允许有两个渲染面。
///
/// Example / 示例:
/// ```dart
/// MaterialApp(
///   builder: (context, child) => MovaMiniHost(ctl: miniCtl, child: child!),
///   home: const HomePage(),
/// )
/// ```
class MovaMiniHost extends StatefulWidget {
  /// Creates the host wrapper around [child].
  ///
  /// 创建包裹 [child] 的宿主壳。
  const MovaMiniHost({super.key, required this.ctl, required this.child});

  /// The route-independent mini-window state.
  ///
  /// 独立于路由的小窗状态。
  final MovaMiniCtl ctl;

  /// The app content (normally the [Navigator]).
  ///
  /// App 内容（通常是 [Navigator]）。
  final Widget child;

  @override
  State<MovaMiniHost> createState() => _MovaMiniHostState();
}

class _MovaMiniHostState extends State<MovaMiniHost> {
  @override
  void initState() {
    super.initState();
    widget.ctl.addListener(_onCtl);
  }

  @override
  void didUpdateWidget(covariant MovaMiniHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ctl != widget.ctl) {
      oldWidget.ctl.removeListener(_onCtl);
      widget.ctl.addListener(_onCtl);
    }
  }

  @override
  void dispose() {
    widget.ctl.removeListener(_onCtl);
    super.dispose();
  }

  void _onCtl() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final api = widget.ctl.api;
    final cfg = api?.options.mini;
    final shows = api != null &&
        cfg != null &&
        cfg.enabled &&
        widget.ctl.mount == MovaMiniMount.persistent;
    return Stack(
      children: [
        widget.child,
        if (shows)
          Positioned.fill(
            child: MovaMiniWindow(
              key: const ValueKey('movaMiniWindow'),
              ctl: widget.ctl,
              api: api,
              config: cfg,
            ),
          ),
      ],
    );
  }
}
