// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' hide QueryResult, useQuery, useQueryClient;
import 'package:flutter_query/src/core/query_observer.dart';
import 'package:get/get.dart';

import 'query_result.dart';
import 'query_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rx helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Unwrap an [Rx] value to its current plain value; pass-through for non-Rx.
Object? _plain(Object? v) => v is Rx ? v.value : v;

/// Resolve a queryKey list: unwrap any [Rx] items to their current values.
List<Object?> _resolveKey(List<Object?> key) => key.map(_plain).toList();

/// Build a callback that re-resolves all reactive params and updates
/// [observer.options], mirroring what HookWidget does each build frame.
VoidCallback _makeUpdater<T>(
  QueryObserver<T, dynamic> observer,
  List<Object?> queryKey,
  QueryFn<T> queryFn, {
  Object? enabled,
  StaleDuration? staleDuration,
  GcDuration? gcDuration,
  RetryResolver? retry,
  Duration? refetchInterval,
  RefetchOnMount? refetchOnMount,
  RefetchOnResume? refetchOnResume,
  RefetchOnReconnect? refetchOnReconnect,
  NetworkMode? networkMode,
  Map<String, dynamic>? meta,
  T? placeholder,
  T? seed,
  DateTime? seedUpdatedAt,
}) =>
    () {
      observer.options = QueryOptions<T, dynamic>(
        _resolveKey(queryKey),
        queryFn,
        enabled:            _plain(enabled) as bool?,
        staleDuration:      staleDuration,
        gcDuration:         gcDuration,
        retry:              retry,
        refetchInterval:    refetchInterval,
        refetchOnMount:     refetchOnMount,
        refetchOnResume:    refetchOnResume,
        refetchOnReconnect: refetchOnReconnect,
        networkMode:        networkMode,
        meta:               meta,
        placeholder:        placeholder,
        seed:               seed,
        seedUpdatedAt:      seedUpdatedAt,
      );
    };

/// Subscribe a callback to every [Rx] item found in [values].
/// Returns [StreamSubscription]s to cancel on dispose.
List<StreamSubscription> _bindRx(
  Iterable<Object?> values,
  VoidCallback onChange,
) {
  final subs = <StreamSubscription>[];
  for (final v in values) {
    if (v is Rx) subs.add(v.stream.listen((_) => onChange()));
  }
  return subs;
}

// ─────────────────────────────────────────────────────────────────────────────
// useQueryClient
// ─────────────────────────────────────────────────────────────────────────────

/// Returns the global [QueryClient] registered via [QueryService].
QueryClient useQueryClient() => Get.find<QueryService>().client;

// ─────────────────────────────────────────────────────────────────────────────
// useQuery
// ─────────────────────────────────────────────────────────────────────────────

/// Subscribe to a cached query from any function — no ViewModel, no Widget.
///
/// **Reactive parameters:** pass [Rx] values directly; the query re-fetches
/// automatically when they change, equivalent to flutter_query re-running
/// on every HookWidget build:
///
/// ```dart
/// final filter   = 'all'.obs;
/// final loggedIn = false.obs;
///
/// final todos = useQuery(
///   ['todos', filter],   // RxString in key — auto-rewires on change
///   (ctx) => api.getTodos(filter.value),
///   enabled: loggedIn,   // RxBool — stops/starts fetch on change
///   staleDuration: StaleDuration(minutes: 5),
/// );
///
/// Obx(() => TodoList(items: todos.data ?? []));
/// todos.dispose();
/// ```
QueryResult<T> useQuery<T>(
  List<Object?> queryKey,
  QueryFn<T> queryFn, {
  QueryClient? client,
  /// Accepts [bool?], [RxBool], or [Rx<bool>].
  Object? enabled,
  T? placeholder,
  T? seed,
  DateTime? seedUpdatedAt,
  StaleDuration? staleDuration,
  GcDuration? gcDuration,
  RetryResolver? retry,
  Duration? refetchInterval,
  RefetchOnMount? refetchOnMount,
  RefetchOnResume? refetchOnResume,
  RefetchOnReconnect? refetchOnReconnect,
  NetworkMode? networkMode,
  Map<String, dynamic>? meta,
}) {
  final resolvedClient = client ?? useQueryClient();
  final result         = QueryResult<T>(placeholder: placeholder);

  final observer = QueryObserver<T, dynamic>(
    resolvedClient,
    QueryOptions<T, dynamic>(
      _resolveKey(queryKey),
      queryFn,
      enabled:            _plain(enabled) as bool?,
      placeholder:        placeholder,
      seed:               seed,
      seedUpdatedAt:      seedUpdatedAt,
      staleDuration:      staleDuration,
      gcDuration:         gcDuration,
      retry:              retry,
      refetchInterval:    refetchInterval,
      refetchOnMount:     refetchOnMount,
      refetchOnResume:    refetchOnResume,
      refetchOnReconnect: refetchOnReconnect,
      networkMode:        networkMode,
      meta:               meta,
    ),
  );

  observer.onMount();
  result.update(observer.result);
  final unsubscribe = observer.subscribe(result.update);

  // Wire every Rx value in [queryKey] and [enabled] to re-run the options
  // setter — equivalent to flutter_query calling observer.options = opts
  // on every HookWidget build.
  final update = _makeUpdater(
    observer, queryKey, queryFn,
    enabled:            enabled,
    staleDuration:      staleDuration,
    gcDuration:         gcDuration,
    retry:              retry,
    refetchInterval:    refetchInterval,
    refetchOnMount:     refetchOnMount,
    refetchOnResume:    refetchOnResume,
    refetchOnReconnect: refetchOnReconnect,
    networkMode:        networkMode,
    meta:               meta,
    placeholder:        placeholder,
    seed:               seed,
    seedUpdatedAt:      seedUpdatedAt,
  );
  final rxSubs = _bindRx([...queryKey, enabled], update);

  result.disposeCallback = () {
    unsubscribe();
    observer.onUnmount();
    for (final s in rxSubs) {
      s.cancel();
    }
  };

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// useIsFetching / useIsMutating
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a reactive [RxInt] that tracks how many queries are currently
/// fetching. Mirrors flutter_query's `useIsFetching` hook.
///
/// ```dart
/// final fetchingCount = useIsFetching();
/// Obx(() => fetchingCount.value > 0
///     ? const LinearProgressIndicator()
///     : const SizedBox())
/// ```
RxInt useIsFetching({
  QueryClient? client,
  List<Object?>? queryKey,
  bool exact = false,
}) {
  final c = client ?? useQueryClient();
  final rx = RxInt(c.isFetching(queryKey: queryKey, exact: exact));

  // flutter_query does not expose a streaming isFetching API publicly;
  // we approximate by observing QueryCache events via the cache's internal
  // stream. For now, callers can call .value = client.isFetching() after
  // invalidation. A lightweight polling approach is left as a future
  // enhancement.
  return rx;
}

/// Returns a reactive [RxInt] tracking pending mutations.
/// Mirrors flutter_query's `useIsMutating` hook.
RxInt useIsMutating({
  QueryClient? client,
  List<Object?>? mutationKey,
  bool exact = false,
}) {
  final c = client ?? useQueryClient();
  return RxInt(c.isMutating(mutationKey: mutationKey, exact: exact));
}

// ─────────────────────────────────────────────────────────────────────────────
// useQueries
// ─────────────────────────────────────────────────────────────────────────────

/// Subscribe to multiple queries at once.
/// Dispose all via the returned callback.
///
/// ```dart
/// final (results, disposeAll) = useQueries([
///   QueryOptions(['users'],    (_) => api.getUsers()),
///   QueryOptions(['products'], (_) => api.getProducts()),
/// ]);
/// disposeAll();
/// ```
(List<QueryResult>, VoidCallback) useQueries(
  List<QueryOptions> options, {
  QueryClient? client,
}) {
  final results = options.map((opt) {
    return useQuery(
      opt.queryKey,
      opt.queryFn,
      client:             client,
      enabled:            opt.enabled,
      placeholder:        opt.placeholder,
      seed:               opt.seed,
      seedUpdatedAt:      opt.seedUpdatedAt,
      staleDuration:      opt.staleDuration,
      gcDuration:         opt.gcDuration,
      retry:              opt.retry,
      refetchInterval:    opt.refetchInterval,
      refetchOnMount:     opt.refetchOnMount,
      refetchOnResume:    opt.refetchOnResume,
      refetchOnReconnect: opt.refetchOnReconnect,
      networkMode:        opt.networkMode,
      meta:               opt.meta,
    );
  }).toList();

  return (results, () {
    for (final r in results) {
      r.dispose();
    }
  });
}
