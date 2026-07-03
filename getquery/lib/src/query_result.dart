import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' as fq;
import 'package:get/get.dart';

/// Reactive query result backed by GetX [Rx].
///
/// Use [Obx] anywhere — no controller or BuildContext required:
/// ```dart
/// final posts = useQuery(['posts'], (_) => api.getPosts());
/// Obx(() => PostList(items: posts.data ?? []));
/// posts.dispose();
/// ```
class QueryResult<T> {
  QueryResult({T? placeholder}) : _placeholder = placeholder;

  final T? _placeholder;
  final _rx = Rx<fq.QueryResult<T, dynamic>?>(null);

  // ── Data ──────────────────────────────────────────────────────────────────

  T? get data => _rx.value?.data ?? _placeholder;

  // ── Status ────────────────────────────────────────────────────────────────

  bool get isIdle              => _rx.value == null;
  bool get isLoading           => _rx.value == null || _rx.value!.isPending;
  bool get isFetching          => _rx.value?.isFetching          ?? false;
  bool get isSuccess           => _rx.value?.isSuccess           ?? false;
  bool get isError             => _rx.value?.isError             ?? false;
  bool get isStale             => _rx.value?.isStale             ?? true;
  bool get isFetchedAfterMount => _rx.value?.isFetchedAfterMount ?? false;

  // ── Error / meta ──────────────────────────────────────────────────────────

  Object?   get error     => _rx.value?.error;
  DateTime? get updatedAt => _rx.value?.dataUpdatedAt;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> refetch() async => _rx.value?.refetch();

  void dispose() => disposeCallback?.call();

  // ── Internal — @internal so they don't appear in user-facing API,
  //    but accessible from use_query.dart / base_view_model.dart which
  //    carry "// ignore_for_file: invalid_use_of_internal_member". ──────────

  /// Called by useQuery / _Core to push a new flutter_query snapshot.
  @internal
  void update(fq.QueryResult<T, dynamic> result) => _rx.value = result;

  /// Set by useQuery / _Core to wire up observer cleanup.
  @internal
  VoidCallback? disposeCallback;
}
