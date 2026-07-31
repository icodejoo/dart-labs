import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import 'scope.dart';

/// Capability mixin for stateful components that react to events with side
/// effects (not mere rebuilds — those stay stateless via `VmSelector`).
///
/// Grants exactly two, business-agnostic capabilities:
///
/// 1. [api] — a stable handle to the capability surface, for issuing
///    commands (`api.seek(...)`) and reading synchronous state (`api.state`).
/// 2. [bind] — subscribing to an event stream with lifecycle-safe teardown:
///    every subscription is cancelled automatically on [dispose].
///
/// It carries no business logic: *what* to listen to and *what* to do are the
/// component's own decisions. Because it is the single, pure capability mixin
/// (not one-per-feature), stacking it never risks member-name collisions.
///
/// Contract: only call [bind] from `initState`, never from `build` — a
/// subscription created per build would be re-created and dropped on every
/// rebuild. All writes must go through [api] (never around it to the kernel),
/// so host [VmInterceptor]s stay in the loop.
///
/// 为「事件副作用型」有状态组件提供能力的 mixin（副作用，非单纯重建——纯重建
/// 用 `VmSelector` 保持无状态即可）。
///
/// 只给两样与业务无关的能力：
///
/// 1. [api]——能力面的稳定句柄，用于发指令（`api.seek(...)`）与读同步状态
///    （`api.state`）。
/// 2. [bind]——订阅事件流并带生命周期安全回收：每个订阅都会在 [dispose] 时
///    自动取消。
///
/// 它不含任何业务：听什么、听到后干什么，是组件自己的决定。因为它是唯一的、
/// 纯粹的能力 mixin（而非每功能一个），叠加它绝不会有成员命名冲突之虞。
///
/// 契约：[bind] 只能在 `initState` 调用，禁在 `build`——每次 build 建订阅会随
/// 重建反复建/丢。所有写操作必须经 [api]（不得绕到内核），以让宿主
/// [VmInterceptor] 始终在环内。
mixin VmPlugin<T extends StatefulWidget> on State<T> {
  /// The capability surface, read as a stable handle (no rebuild dependency).
  ///
  /// 能力面，作为稳定句柄读取（不建立重建依赖）。
  VmApi get api => VmScope.readOf(context);

  /// Active subscriptions opened via [bind], cancelled in [dispose].
  ///
  /// 经 [bind] 打开的活跃订阅，在 [dispose] 中取消。
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Subscribes to [stream], routing each event to [onEvent], and registers
  /// the subscription for automatic cancellation on [dispose].
  ///
  /// Call from `initState`. Returns the [StreamSubscription] in case the
  /// caller wants to pause/resume it, though cancellation is handled for you.
  ///
  /// 订阅 [stream]，将每个事件交给 [onEvent]，并登记该订阅以在 [dispose] 时
  /// 自动取消。
  ///
  /// 在 `initState` 中调用。返回 [StreamSubscription] 以便调用方需要
  /// 暂停/恢复它，不过取消已替你处理。
  StreamSubscription<E> bind<E>(Stream<E> stream, void Function(E event) onEvent) {
    final sub = stream.listen(onEvent);
    _subs.add(sub);
    return sub;
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}
