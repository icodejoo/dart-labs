// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' hide QueryResult, useQuery, useQueryClient;
import 'package:flutter_query/src/core/query_observer.dart';
import 'package:get/get.dart';

import 'query_result.dart';
import 'query_service.dart';
import 'reactive.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rx helpers
// ─────────────────────────────────────────────────────────────────────────────

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
        resolveReactiveKey(queryKey),
        queryFn,
        enabled:            plainValue(enabled) as bool?,
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
///   queryKey: ['todos', filter],   // RxString in key — auto-rewires on change
///   queryFn: (ctx) => api.getTodos(filter.value),
///   enabled: loggedIn,             // RxBool — stops/starts fetch on change
///   staleDuration: StaleDuration(minutes: 5),
/// );
///
/// Obx(() => TodoList(items: todos.data ?? []));
/// todos.dispose();
/// ```
QueryResult<T> useQuery<T>({
  required List<Object?> queryKey,
  required QueryFn<T> queryFn,
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
      resolveReactiveKey(queryKey),
      queryFn,
      enabled:            plainValue(enabled) as bool?,
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

  // Wire every reactive value in [queryKey] and [enabled] to re-run the
  // options setter — equivalent to flutter_query calling observer.options =
  // opts on every HookWidget build.
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
  final rxSubs = bindReactive([...queryKey, enabled], update);
  final disposeResume = bindResume(observer.onResume);

  result.disposeCallback = () {
    unsubscribe();
    observer.onUnmount();
    disposeResume();
    for (final s in rxSubs) {
      s.cancel();
    }
  };

  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// useIsFetching / useIsMutating
// ─────────────────────────────────────────────────────────────────────────────

/// Returns a reactive [RxInt] tracking how many queries are currently
/// fetching, plus a [VoidCallback] to stop tracking. Mirrors flutter_query's
/// `useIsFetching` hook.
///
/// ```dart
/// final (fetchingCount, dispose) = useIsFetching();
/// Obx(() => fetchingCount.value > 0
///     ? const LinearProgressIndicator()
///     : const SizedBox());
/// dispose();
/// ```
(RxInt, VoidCallback) useIsFetching({
  QueryClient? client,
  List<Object?>? queryKey,
  bool exact = false,
}) {
  final c  = client ?? useQueryClient();
  final rx = RxInt(c.isFetching(queryKey: queryKey, exact: exact));
  final unsubscribe = c.cache.subscribe((_) {
    rx.value = c.isFetching(queryKey: queryKey, exact: exact);
  });
  return (rx, unsubscribe);
}

/// Returns a reactive [RxInt] tracking pending mutations, plus a
/// [VoidCallback] to stop tracking. Mirrors flutter_query's `useIsMutating`
/// hook.
(RxInt, VoidCallback) useIsMutating({
  QueryClient? client,
  List<Object?>? mutationKey,
  bool exact = false,
}) {
  final c  = client ?? useQueryClient();
  final rx = RxInt(c.isMutating(mutationKey: mutationKey, exact: exact));
  final unsubscribe = c.mutationCache.subscribe((_) {
    rx.value = c.isMutating(mutationKey: mutationKey, exact: exact);
  });
  return (rx, unsubscribe);
}

// ─────────────────────────────────────────────────────────────────────────────
// useQueries
// ─────────────────────────────────────────────────────────────────────────────

/// Subscribe to multiple queries at once.
/// Dispose all via the returned callback.
///
/// Pass [combine] to derive a single value from the whole result list —
/// mirrors TanStack Query's `useQueries({ combine })`. Unlike React, there's
/// no need for [combine] to memoize away re-renders: call the returned
/// `combined()` getter **inside** `Obx`, and GetX's own fine-grained
/// dependency tracking makes the widget rebuild only when the specific
/// fields [combine] actually reads (e.g. `.data`, `.isLoading`) change.
///
/// ```dart
/// final (results, combined, disposeAll) = useQueries(
///   [
///     QueryOptions(['users'],    (_) => api.getUsers()),
///     QueryOptions(['products'], (_) => api.getProducts()),
///   ],
///   combine: (rs) => rs.every((r) => r.isSuccess),
/// );
/// Obx(() => Text('all loaded: ${combined()}'));
/// disposeAll();
/// ```
(List<QueryResult>, TCombined Function(), VoidCallback) useQueries<TCombined>(
  List<QueryOptions> options, {
  QueryClient? client,
  TCombined Function(List<QueryResult> results)? combine,
}) {
  final results = options.map((opt) {
    return useQuery(
      queryKey:           opt.queryKey,
      queryFn:            opt.queryFn,
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

  TCombined combined() {
    if (combine == null) {
      throw StateError(
          'useQueries: combined() called but no `combine` callback was provided.');
    }
    return combine(results);
  }

  return (results, combined, () {
    for (final r in results) {
      r.dispose();
    }
  });
}
