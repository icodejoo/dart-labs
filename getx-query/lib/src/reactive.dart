import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:get/get.dart';

/// Unwrap a reactive value to its current plain value; pass-through for non-Rx.
///
/// Checks [RxObjectMixin] rather than [Rx] so GetX's collection types
/// ([RxList]/[RxMap]/[RxSet]) are recognized too — they mix in [RxObjectMixin]
/// for `.value`/`.stream` but do NOT extend [Rx].
///
/// [RxList]/[RxMap]/[RxSet] mutate their backing collection **in place**, so
/// returning the live object would hand flutter_query the exact same
/// reference on every rebuild — key-diffing would see "no change" even after
/// a mutation, since there is no frozen old copy to compare against. Copying
/// into a plain collection here gives each rebuild a distinct, frozen value.
Object? plainValue(Object? v) {
  if (v is RxList) return List.of(v);
  if (v is RxSet) return Set.of(v);
  if (v is RxMap) return Map.of(v);
  if (v is RxObjectMixin) return v.value;
  return v;
}

/// Resolve a queryKey list: unwrap any reactive items to their current values.
List<Object?> resolveReactiveKey(List<Object?> key) => key.map(plainValue).toList();

/// Subscribe a callback to every reactive item found in [values].
/// Returns [StreamSubscription]s to cancel on dispose.
List<StreamSubscription> bindReactive(
  Iterable<Object?> values,
  VoidCallback onChange,
) {
  final subs = <StreamSubscription>[];
  for (final v in values) {
    if (v is RxObjectMixin) subs.add(v.stream.listen((_) => onChange()));
  }
  return subs;
}

/// Subscribe [onResume] to app-foreground-resume events, mirroring what
/// flutter_query's own hooks do per query (`AppLifecycleListener(onResume:
/// observer.onResume)`) — so each query's own `refetchOnResume` policy is
/// honored individually instead of a blanket, client-wide invalidation.
/// Returns a callback to cancel the subscription.
VoidCallback bindResume(VoidCallback onResume) {
  final listener = AppLifecycleListener(onResume: onResume);
  return listener.dispose;
}
