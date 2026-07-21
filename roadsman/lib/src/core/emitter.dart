/// Type-safe event emitter.
///
/// Pure Dart, no DOM dependency, no wildcards, no priorities, no async queue.
/// Ported from `src/core/emitter.ts`; the Dart version uses a single payload
/// type (instead of the TS multi-key event map), so multi-event scenarios
/// should have callers create one `Emitter<T>` instance per event — this fits
/// Dart's type inference better than forcing the TS
/// `Record<string, unknown>` event map pattern.
library;

/// Event listener (receives a payload, returns nothing).
typedef Listener<T> = void Function(T payload);

/// Type-safe emitter.
///
/// ```dart
/// final emitter = Emitter<int>();
/// final off = emitter.on((value) => print(value));
/// emitter.emit(42);
/// off();
/// ```
class Emitter<T> {
  final _listeners = <Listener<T>>{};

  /// Subscribes to events, returning an unsubscribe function (removes this listener when called).
  void Function() on(Listener<T> listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Emits an event, synchronously calling all listeners.
  void emit(T payload) {
    for (final listener in _listeners.toList()) {
      listener(payload);
    }
  }
}
