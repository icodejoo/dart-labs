// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' hide QueryResult, useQuery, useQueryClient;

import 'query_result.dart';
import 'use_query.dart';

// ─────────────────────────────────────────────────────────────────────────────
// watchQuery — explicit QueryClient, returns record
// ─────────────────────────────────────────────────────────────────────────────

/// Like [useQuery] but takes an explicit [QueryClient].
/// Returns `(result, dispose)` as a Dart-3 record.
///
/// ```dart
/// final (items, cancel) = watchQuery(
///   client, ['shop', 'items'], (_) => ShopApi.getItems(),
/// );
/// Obx(() => ItemList(items: items.data ?? []));
/// cancel();
/// ```
(QueryResult<T>, VoidCallback) watchQuery<T>(
  QueryClient client,
  List<Object?> key,
  QueryFn<T> fn, {
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
  final result = useQuery(
    key, fn,
    client:             client,
    enabled:            enabled,
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
  );
  return (result, result.dispose);
}

// ─────────────────────────────────────────────────────────────────────────────
// QueryScope — groups subscriptions for collective lifecycle management
// ─────────────────────────────────────────────────────────────────────────────

/// Collects multiple [useQuery] results and disposes them together.
///
/// ```dart
/// final scope = QueryScope();
///
/// final deposits = scope.watch(['deposit', 'list'], (_) => api.getList());
/// final balance  = scope.watch(['wallet', 'balance'], (_) => api.getBalance());
///
/// Obx(() => Text('${balance.data}'));
/// scope.dispose();
/// ```
class QueryScope {
  QueryScope({QueryClient? client}) : _client = client;

  final QueryClient? _client;
  final _results = <QueryResult>[];

  QueryResult<T> watch<T>(
    List<Object?> key,
    QueryFn<T> fn, {
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
    final result = useQuery(
      key, fn,
      client:             _client,
      enabled:            enabled,
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
    );
    _results.add(result);
    return result;
  }

  QueryClient get _resolvedClient => _client ?? useQueryClient();

  Future<void> invalidateQueries({
    List<Object?>? queryKey,
    bool exact = false,
    RefetchType refetchType = RefetchType.active,
  }) =>
      _resolvedClient.invalidateQueries(
          queryKey: queryKey, exact: exact, refetchType: refetchType);

  Future<void> prefetchQuery<T>(List<Object?> queryKey, QueryFn<T> fn) =>
      _resolvedClient.prefetchQuery(queryKey, fn);

  T? getQueryData<T>(List<Object?> queryKey) =>
      _resolvedClient.getQueryData<T>(queryKey);

  T? setQueryData<T>(
          List<Object?> queryKey, T? Function(T? prev) updater) =>
      _resolvedClient.setQueryData<T, dynamic>(queryKey, updater);

  /// Convenience: run [fn] and then invalidate [invalidates] keys.
  Future<R> mutate<R>(
    Future<R> Function() fn, {
    List<List<Object?>> invalidates = const [],
  }) async {
    final result = await fn();
    for (final key in invalidates) {
      _resolvedClient.invalidateQueries(queryKey: key);
    }
    return result;
  }

  void dispose() {
    for (final r in _results) {
      r.dispose();
    }
    _results.clear();
  }
}
