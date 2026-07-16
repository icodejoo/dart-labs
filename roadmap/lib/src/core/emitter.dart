/// 类型安全事件发射器。
///
/// 纯 Dart，无 DOM 依赖，无通配符，无优先级，无异步队列。移植自
/// `src/core/emitter.ts`；Dart 版本用单一载荷类型（不是 TS 的多键事件映射表），
/// 多事件场景由调用方各自建一个 `Emitter<T>` 实例，比强行照搬 TS 的
/// `Record<string, unknown>` 事件映射表更符合 Dart 的类型推断习惯。
library;

/// 事件监听器（接收载荷，无返回值）。
typedef Listener<T> = void Function(T payload);

/// 类型安全 Emitter。
///
/// ```dart
/// final emitter = Emitter<int>();
/// final off = emitter.on((value) => print(value));
/// emitter.emit(42);
/// off();
/// ```
class Emitter<T> {
  final _listeners = <Listener<T>>{};

  /// 订阅事件，返回取消订阅函数（调用后立即移除该监听器）。
  void Function() on(Listener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// 发射事件，同步调用所有监听器。
  void emit(T payload) {
    for (final listener in _listeners.toList()) {
      listener(payload);
    }
  }
}
