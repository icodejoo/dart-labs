import 'package:flutter/widgets.dart';

import 'overlay_manager.dart';

/// 把应用前后台切换接入 [Layerman]：进入后台期间持有一个暂停凭证
/// （队列不再出场新条目、`duration` 倒计时冻结），回到前台自动释放。
///
/// 与手动 `pauseAll` 和 `pauseOnRoutes` 免打扰区按 OR 组合，互不覆盖。
///
/// ```dart
/// final lifecycle = LayermanLifecycle(manager)..attach();
/// // 不再需要时（例如 app 内重启换 manager 之前）：
/// lifecycle.detach();
/// ```
class LayermanLifecycle with WidgetsBindingObserver {
  /// 绑定 [manager]；[pauseOn] 是需要暂停的生命周期状态，
  /// 默认进入 `paused`（后台）或 `hidden` 时暂停。
  LayermanLifecycle(
    this.manager, {
    Set<AppLifecycleState> pauseOn = const <AppLifecycleState>{
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
    },
  }) : _pauseOn = pauseOn;

  /// 被控制的编排器。
  final Layerman manager;

  /// 命中即暂停的生命周期状态。
  final Set<AppLifecycleState> _pauseOn;

  /// 当前持有的暂停凭证；未暂停时为 null。
  OverlayHold? _hold;

  /// 是否已经注册为 [WidgetsBinding] 的观察者。
  bool _attached = false;

  /// 是否已经 [attach]。
  bool get isAttached => _attached;

  /// 开始监听生命周期，并立即按当前状态同步一次；重复调用无操作。
  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    _sync(WidgetsBinding.instance.lifecycleState);
  }

  /// 停止监听并释放暂停凭证；重复调用无操作。
  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
    _release();
  }

  /// 按新的应用生命周期状态同步独立暂停来源。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync(state);

  /// 按 [state] 持有或释放暂停凭证；编排器已销毁则自动解除监听。
  void _sync(AppLifecycleState? state) {
    if (manager.isDisposed) {
      detach();
      return;
    }
    if (state != null && _pauseOn.contains(state)) {
      _hold ??= manager.hold('app-lifecycle');
    } else {
      _release();
    }
  }

  /// 释放暂停凭证。
  void _release() {
    _hold?.release();
    _hold = null;
  }
}
