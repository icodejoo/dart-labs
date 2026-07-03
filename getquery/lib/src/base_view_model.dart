// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:flutter_query/flutter_query.dart'
    hide QueryResult,
        MutationResult,
        useQuery,
        useQueryClient,
        QueryClientProvider,
        useMutation,
        useInfiniteQuery,
        useIsFetching,
        useIsMutating,
        useMutationState;
import 'package:flutter_query/src/core/mutation_observer.dart';
import 'package:flutter_query/src/core/query_observer.dart';
import 'package:get/get.dart';
import 'package:meta/meta.dart';

import 'mutation_result.dart';
import 'query_result.dart';
import 'query_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rx helpers
// ─────────────────────────────────────────────────────────────────────────────

Object? _plain(Object? v) => v is Rx ? v.value : v;

List<Object?> _resolveKey(List<Object?> key) => key.map(_plain).toList();

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

VoidCallback _makeObserverUpdater<T>(
  QueryObserver<T, dynamic> observer,
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
}) =>
    () {
      observer.options = QueryOptions<T, dynamic>(
        _resolveKey(key),
        fn,
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
      );
    };

// ─────────────────────────────────────────────────────────────────────────────
// _Core  — all observer + client logic, framework-agnostic
// ─────────────────────────────────────────────────────────────────────────────

class _Core with WidgetsBindingObserver {
  _Core(this._client);

  final QueryClient _client;
  final _results   = <QueryResult>[];
  final _mutations = <MutationResult>[];

  void init()    => WidgetsBinding.instance.addObserver(this);

  void dispose() {
    for (final r in _results) {
      r.dispose();
    }
    for (final m in _mutations) {
      m.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
  }

  // ── useQuery ──────────────────────────────────────────────────────────────

  QueryResult<T> useQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
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
    Object? enabled,   // bool? | RxBool
    Map<String, dynamic>? meta,
  }) {
    final result   = QueryResult<T>(placeholder: placeholder);
    final observer = QueryObserver<T, dynamic>(
      _client,
      QueryOptions<T, dynamic>(
        _resolveKey(queryKey), queryFn,
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
        enabled:            _plain(enabled) as bool?,
        meta:               meta,
      ),
    );

    observer.onMount();
    result.update(observer.result);
    final rxSubs = _bindRx(
      [...queryKey, enabled],
      _makeObserverUpdater(
        observer, queryKey, queryFn,
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
      ),
    );
    final unsubscribe = observer.subscribe(result.update);

    result.disposeCallback = () {
      unsubscribe();
      observer.onUnmount();
      for (final s in rxSubs) {
        s.cancel();
      }
    };

    _results.add(result);
    return result;
  }

  // ── useMutation ───────────────────────────────────────────────────────────

  MutationResult<TData, TVariables> useMutation<TData, TVariables>(
    MutateFn<TData, TVariables> mutationFn, {
    MutationOnMutate<TVariables, dynamic>? onMutate,
    MutationOnSuccess<TData, TVariables, dynamic>? onSuccess,
    MutationOnError<dynamic, TVariables, dynamic>? onError,
    MutationOnSettled<TData, dynamic, TVariables, dynamic>? onSettled,
    List<Object?>? mutationKey,
    GcDuration? gcDuration,
    RetryResolver? retry,
    NetworkMode? networkMode,
    Map<String, dynamic>? meta,
  }) {
    final observer = MutationObserver<TData, dynamic, TVariables, dynamic>(
      _client,
      MutationOptions(
        mutationFn:  mutationFn,
        onMutate:    onMutate,
        onSuccess:   onSuccess,
        onError:     onError,
        onSettled:   onSettled,
        mutationKey: mutationKey,
        gcDuration:  gcDuration,
        retry:       retry,
        networkMode: networkMode,
        meta:        meta,
      ),
    );
    observer.onMount();

    final result = MutationResult<TData, TVariables>();
    result.update(observer.result);
    result.mutate      = observer.mutate;
    result.mutateAsync = observer.mutateAsync;
    result.reset       = observer.reset;

    final unsubscribe = observer.subscribe(result.update);
    result.disposeCallback = () {
      unsubscribe();
      observer.onUnmount();
    };

    _mutations.add(result);
    return result;
  }

  // ── QueryClient — fetch / prefetch / ensure ───────────────────────────────

  Future<T> fetchQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
  }) =>
      _client.fetchQuery<T, dynamic>(
        queryKey, queryFn,
        staleDuration:  staleDuration,
        retry:          retry,
        gcDuration:     gcDuration,
        seed:           seed,
        seedUpdatedAt:  seedUpdatedAt,
        meta:           meta,
      );

  Future<void> prefetchQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
  }) =>
      _client.prefetchQuery<T, dynamic>(
        queryKey, queryFn,
        staleDuration:  staleDuration,
        retry:          retry,
        gcDuration:     gcDuration,
        seed:           seed,
        seedUpdatedAt:  seedUpdatedAt,
        meta:           meta,
      );

  Future<T> ensureQueryData<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
    bool revalidateIfStale = false,
  }) =>
      _client.ensureQueryData<T, dynamic>(
        queryKey, queryFn,
        staleDuration:      staleDuration,
        retry:              retry,
        gcDuration:         gcDuration,
        seed:               seed,
        seedUpdatedAt:      seedUpdatedAt,
        meta:               meta,
        revalidateIfStale:  revalidateIfStale,
      );

  // ── QueryClient — cache read / write ─────────────────────────────────────

  T? getQueryData<T>(List<Object?> queryKey) =>
      _client.getQueryData<T>(queryKey);

  QueryState<T, dynamic>? getQueryState<T>(List<Object?> queryKey) =>
      _client.getQueryState<T, dynamic>(queryKey);

  T? setQueryData<T>(
    List<Object?> queryKey,
    T? Function(T? previousData) updater, {
    DateTime? updatedAt,
  }) =>
      _client.setQueryData<T, dynamic>(queryKey, updater, updatedAt: updatedAt);

  // ── QueryClient — invalidation / cancellation / reset / removal ──────────

  Future<void> invalidateQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
    RefetchType refetchType = RefetchType.active,
  }) =>
      _client.invalidateQueries(
        queryKey:    queryKey,
        exact:       exact,
        predicate:   predicate,
        refetchType: refetchType,
      );

  Future<void> refetchQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _client.refetchQueries(
        queryKey:  queryKey,
        exact:     exact,
        predicate: predicate,
      );

  Future<void> cancelQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
    bool revert = true,
    bool silent = false,
  }) =>
      _client.cancelQueries(
        queryKey:  queryKey,
        exact:     exact,
        predicate: predicate,
        revert:    revert,
        silent:    silent,
      );

  Future<void> resetQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _client.resetQueries(
        queryKey:  queryKey,
        exact:     exact,
        predicate: predicate,
      );

  void removeQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _client.removeQueries(
        queryKey:  queryKey,
        exact:     exact,
        predicate: predicate,
      );

  // ── QueryClient — status counts ───────────────────────────────────────────

  int isFetching({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _client.isFetching(queryKey: queryKey, exact: exact, predicate: predicate);

  int isMutating({
    List<Object?>? mutationKey,
    bool exact = false,
    bool Function(List<Object?>? key, MutationState state)? predicate,
  }) =>
      _client.isMutating(
          mutationKey: mutationKey, exact: exact, predicate: predicate);

  // ── QueryClient — global ──────────────────────────────────────────────────

  /// Convenience: run [fn] imperatively and invalidate related keys on success.
  /// For reactive mutations with loading/error state use [useMutation] instead.
  Future<R> mutate<R>(
    Future<R> Function() fn, {
    List<List<Object?>> invalidates = const [],
  }) async {
    final result = await fn();
    for (final key in invalidates) {
      _client.invalidateQueries(queryKey: key);
    }
    return result;
  }

  void clear() => _client.clear();

  // ── WidgetsBindingObserver ────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.invalidateQueries();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _QueryDelegate  — shared public API delegated to _Core
// ─────────────────────────────────────────────────────────────────────────────

mixin _QueryDelegate {
  _Core get _core;

  // ── useQuery ──────────────────────────────────────────────────────────────

  /// Subscribe to a cached query (same API as flutter_query's `useQuery`).
  /// [queryKey] items and [enabled] accept [Rx<T>] for reactive re-fetching.
  ///
  /// ```dart
  /// class DepositViewModel extends GetBaseViewModel {
  ///   final userId = ''.obs;
  ///
  ///   late final deposits = this.useQuery(
  ///     ['deposit', userId],          // Rx item — refetches when userId changes
  ///     (_) => DepositApi.getList(),
  ///     staleDuration: StaleDuration(minutes: 5),
  ///   );
  /// }
  /// ```
  QueryResult<T> useQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
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
    Object? enabled,
    Map<String, dynamic>? meta,
  }) =>
      _core.useQuery(
        queryKey, queryFn,
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
        enabled:            enabled,
        meta:               meta,
      );

  // ── useMutation ───────────────────────────────────────────────────────────

  /// Perform create / update / delete operations with reactive state.
  ///
  /// ```dart
  /// late final createDeposit = this.useMutation<Deposit, DepositRequest>(
  ///   (req, _) => DepositApi.create(req),
  ///   onSuccess: (_, __, ___) =>
  ///       invalidateQueries(queryKey: ['deposit', 'list']),
  /// );
  ///
  /// // fire-and-forget:
  /// createDeposit.mutate(DepositRequest(...));
  ///
  /// // await:
  /// final deposit = await createDeposit.mutateAsync(DepositRequest(...));
  /// ```
  MutationResult<TData, TVariables> useMutation<TData, TVariables>(
    MutateFn<TData, TVariables> mutationFn, {
    MutationOnMutate<TVariables, dynamic>? onMutate,
    MutationOnSuccess<TData, TVariables, dynamic>? onSuccess,
    MutationOnError<dynamic, TVariables, dynamic>? onError,
    MutationOnSettled<TData, dynamic, TVariables, dynamic>? onSettled,
    List<Object?>? mutationKey,
    GcDuration? gcDuration,
    RetryResolver? retry,
    NetworkMode? networkMode,
    Map<String, dynamic>? meta,
  }) =>
      _core.useMutation(
        mutationFn,
        onMutate:    onMutate,
        onSuccess:   onSuccess,
        onError:     onError,
        onSettled:   onSettled,
        mutationKey: mutationKey,
        gcDuration:  gcDuration,
        retry:       retry,
        networkMode: networkMode,
        meta:        meta,
      );

  // ── Fetch / Prefetch / Ensure ─────────────────────────────────────────────

  Future<T> fetchQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
  }) =>
      _core.fetchQuery(
        queryKey, queryFn,
        staleDuration: staleDuration,
        retry:         retry,
        gcDuration:    gcDuration,
        seed:          seed,
        seedUpdatedAt: seedUpdatedAt,
        meta:          meta,
      );

  Future<void> prefetchQuery<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
  }) =>
      _core.prefetchQuery(
        queryKey, queryFn,
        staleDuration: staleDuration,
        retry:         retry,
        gcDuration:    gcDuration,
        seed:          seed,
        seedUpdatedAt: seedUpdatedAt,
        meta:          meta,
      );

  Future<T> ensureQueryData<T>(
    List<Object?> queryKey,
    QueryFn<T> queryFn, {
    StaleDuration? staleDuration,
    RetryResolver? retry,
    GcDuration? gcDuration,
    T? seed,
    DateTime? seedUpdatedAt,
    Map<String, dynamic>? meta,
    bool revalidateIfStale = false,
  }) =>
      _core.ensureQueryData(
        queryKey, queryFn,
        staleDuration:     staleDuration,
        retry:             retry,
        gcDuration:        gcDuration,
        seed:              seed,
        seedUpdatedAt:     seedUpdatedAt,
        meta:              meta,
        revalidateIfStale: revalidateIfStale,
      );

  // ── Cache read / write ────────────────────────────────────────────────────

  T? getQueryData<T>(List<Object?> queryKey) =>
      _core.getQueryData<T>(queryKey);

  QueryState<T, dynamic>? getQueryState<T>(List<Object?> queryKey) =>
      _core.getQueryState<T>(queryKey);

  T? setQueryData<T>(
    List<Object?> queryKey,
    T? Function(T? previousData) updater, {
    DateTime? updatedAt,
  }) =>
      _core.setQueryData<T>(queryKey, updater, updatedAt: updatedAt);

  // ── Invalidation / Cancellation / Reset / Removal ────────────────────────

  Future<void> invalidateQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
    RefetchType refetchType = RefetchType.active,
  }) =>
      _core.invalidateQueries(
        queryKey:    queryKey,
        exact:       exact,
        predicate:   predicate,
        refetchType: refetchType,
      );

  Future<void> refetchQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _core.refetchQueries(queryKey: queryKey, exact: exact, predicate: predicate);

  Future<void> cancelQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
    bool revert = true,
    bool silent = false,
  }) =>
      _core.cancelQueries(
        queryKey:  queryKey,
        exact:     exact,
        predicate: predicate,
        revert:    revert,
        silent:    silent,
      );

  Future<void> resetQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _core.resetQueries(queryKey: queryKey, exact: exact, predicate: predicate);

  void removeQueries({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _core.removeQueries(queryKey: queryKey, exact: exact, predicate: predicate);

  // ── Status counts ─────────────────────────────────────────────────────────

  int isFetching({
    List<Object?>? queryKey,
    bool exact = false,
    bool Function(List<Object?> key, QueryState state)? predicate,
  }) =>
      _core.isFetching(queryKey: queryKey, exact: exact, predicate: predicate);

  int isMutating({
    List<Object?>? mutationKey,
    bool exact = false,
    bool Function(List<Object?>? key, MutationState state)? predicate,
  }) =>
      _core.isMutating(
          mutationKey: mutationKey, exact: exact, predicate: predicate);

  // ── Global ────────────────────────────────────────────────────────────────

  /// Convenience: run [fn] imperatively and invalidate related keys on success.
  Future<R> mutate<R>(
    Future<R> Function() fn, {
    List<List<Object?>> invalidates = const [],
  }) =>
      _core.mutate(fn, invalidates: invalidates);

  void clear() => _core.clear();
}

// ─────────────────────────────────────────────────────────────────────────────
// BaseViewModel  — standalone, constructor-injected QueryClient
// ─────────────────────────────────────────────────────────────────────────────

abstract class BaseViewModel with _QueryDelegate {
  BaseViewModel(QueryClient client) : _core = _Core(client);

  @override
  final _Core _core;

  @mustCallSuper
  void init() => _core.init();

  @mustCallSuper
  void dispose() => _core.dispose();
}

// ─────────────────────────────────────────────────────────────────────────────
// GetBaseViewModel  — GetxController + GetxService, auto lifecycle
// ─────────────────────────────────────────────────────────────────────────────

abstract class GetBaseViewModel extends GetxController with _QueryDelegate {
  GetBaseViewModel({QueryClient? client})
      : _core = _Core(client ?? Get.find<QueryService>().client);

  @override
  final _Core _core;

  @override
  void onInit() {
    super.onInit();
    _core.init();
  }

  @override
  void onClose() {
    _core.dispose();
    super.onClose();
  }
}
