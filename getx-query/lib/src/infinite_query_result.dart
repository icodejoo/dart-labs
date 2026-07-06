import 'package:flutter/foundation.dart';
import 'package:flutter_query/flutter_query.dart' as fq;
import 'package:get/get.dart';

/// Reactive paginated query result backed by GetX [Rx].
///
/// Use [Obx] anywhere — no controller or BuildContext required:
/// ```dart
/// final feed = useInfiniteQuery(
///   queryKey: ['feed'],
///   queryFn: (ctx) => api.getFeed(page: ctx.pageParam),
///   initialPageParam: 0,
///   nextPageParamBuilder: (data) => data.pages.last.isEmpty ? null : data.pages.length,
/// );
/// Obx(() => ListView(children: [
///   for (final page in feed.pages) ...page.map((e) => Text(e)),
///   if (feed.hasNextPage) TextButton(onPressed: feed.fetchNextPage, child: const Text('more')),
/// ]));
/// feed.dispose();
/// ```
class InfiniteQueryResult<TData, TPageParam> {
  InfiniteQueryResult({fq.InfiniteData<TData, TPageParam>? placeholder})
      : _placeholder = placeholder;

  final fq.InfiniteData<TData, TPageParam>? _placeholder;
  final _rx = Rx<fq.InfiniteQueryResult<TData, dynamic, TPageParam>?>(null);
  bool _disposed = false;

  // ── Data ──────────────────────────────────────────────────────────────────

  /// All fetched pages and their page params, or `null` before the first
  /// snapshot (falls back to the ctor-supplied `placeholder`).
  fq.InfiniteData<TData, TPageParam>? get data =>
      _rx.value?.data ?? _placeholder;

  /// Shorthand for `data.pages`, `const []` before the first snapshot.
  List<TData> get pages => data?.pages ?? const [];

  /// Shorthand for `data.pageParams`, `const []` before the first snapshot.
  List<TPageParam> get pageParams => data?.pageParams ?? const [];

  // ── Status ────────────────────────────────────────────────────────────────

  bool get isIdle              => _rx.value == null;
  bool get isLoading           => _rx.value == null || _rx.value!.isPending;
  bool get isFetching          => _rx.value?.isFetching          ?? false;
  bool get isSuccess           => _rx.value?.isSuccess           ?? false;
  bool get isError             => _rx.value?.isError             ?? false;
  bool get isStale             => _rx.value?.isStale             ?? true;
  bool get isFetchedAfterMount => _rx.value?.isFetchedAfterMount ?? false;

  // ── Pagination ────────────────────────────────────────────────────────────

  bool get hasNextPage              => _rx.value?.hasNextPage              ?? false;
  bool get hasPreviousPage          => _rx.value?.hasPreviousPage          ?? false;
  bool get isFetchingNextPage       => _rx.value?.isFetchingNextPage       ?? false;
  bool get isFetchingPreviousPage   => _rx.value?.isFetchingPreviousPage   ?? false;
  bool get isFetchNextPageError     => _rx.value?.isFetchNextPageError     ?? false;
  bool get isFetchPreviousPageError => _rx.value?.isFetchPreviousPageError ?? false;

  // ── Error / meta ──────────────────────────────────────────────────────────

  Object?   get error     => _rx.value?.error;
  DateTime? get updatedAt => _rx.value?.dataUpdatedAt;

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Refetches all pages. No-op if the query is already disposed.
  Future<void> refetch() async {
    if (_disposed) return;
    await _rx.value?.refetch();
  }

  /// Fetches the next page. Does nothing if [hasNextPage] is false.
  /// No-op if the query is already disposed.
  Future<void> fetchNextPage() async {
    if (_disposed) return;
    await _rx.value?.fetchNextPage();
  }

  /// Fetches the previous page. Does nothing if [hasPreviousPage] is false.
  /// No-op if the query is already disposed.
  Future<void> fetchPreviousPage() async {
    if (_disposed) return;
    await _rx.value?.fetchPreviousPage();
  }

  /// Idempotent — safe to call more than once, and safe to call after any
  /// other action method.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    disposeCallback?.call();
  }

  // ── Internal — @internal so they don't appear in user-facing API,
  //    but accessible from use_infinite_query.dart which carries
  //    "// ignore_for_file: invalid_use_of_internal_member". ────────────────

  /// Called by useInfiniteQuery to push a new flutter_query snapshot.
  @internal
  void update(fq.InfiniteQueryResult<TData, dynamic, TPageParam> result) =>
      _rx.value = result;

  /// Set by useInfiniteQuery to wire up observer cleanup.
  @internal
  VoidCallback? disposeCallback;
}
