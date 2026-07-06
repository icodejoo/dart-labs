// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter_query/flutter_query.dart'
    hide InfiniteQueryResult, useInfiniteQuery, useQueryClient;
import 'package:flutter_query/src/core/query_observer.dart';

import 'infinite_query_result.dart';
import 'reactive.dart';
import 'use_query.dart' show useQueryClient;

/// Subscribe to a paginated ("infinite") query from any function — no
/// ViewModel, no Widget.
///
/// Extends [useQuery] with page accumulation: [queryFn] fetches one page at
/// a time, [nextPageParamBuilder] (and optionally [prevPageParamBuilder])
/// derive the next/previous page param from the pages fetched so far.
///
/// **Reactive parameters:** pass reactive values directly in [queryKey] or
/// [enabled] — same rules as [useQuery].
///
/// ```dart
/// final feed = useInfiniteQuery(
///   queryKey: ['feed'],
///   queryFn: (ctx) => api.getFeed(page: ctx.pageParam),
///   initialPageParam: 0,
///   nextPageParamBuilder: (data) =>
///       data.pages.last.isEmpty ? null : data.pages.length,
/// );
///
/// Obx(() => ListView(
///   children: [
///     for (final page in feed.pages) ...page.map((e) => Text(e)),
///     if (feed.hasNextPage)
///       TextButton(onPressed: feed.fetchNextPage, child: const Text('more')),
///   ],
/// ));
/// feed.dispose();
/// ```
InfiniteQueryResult<TData, TPageParam> useInfiniteQuery<TData, TPageParam>({
  required List<Object?> queryKey,
  required InfiniteQueryFn<TData, TPageParam> queryFn,
  required TPageParam initialPageParam,
  required NextPageParamBuilder<TData, TPageParam> nextPageParamBuilder,
  PrevPageParamBuilder<TData, TPageParam>? prevPageParamBuilder,
  QueryClient? client,
  /// Accepts [bool?], [RxBool], or [Rx<bool>].
  Object? enabled,
  int? maxPages,
  NetworkMode? networkMode,
  StaleDuration? staleDuration,
  GcDuration? gcDuration,
  InfiniteData<TData, TPageParam>? placeholder,
  RefetchOnMount? refetchOnMount,
  RefetchOnResume? refetchOnResume,
  RefetchOnReconnect? refetchOnReconnect,
  Duration? refetchInterval,
  RetryResolver? retry,
  bool? retryOnMount,
  InfiniteData<TData, TPageParam>? seed,
  DateTime? seedUpdatedAt,
  Map<String, dynamic>? meta,
}) {
  final resolvedClient = client ?? useQueryClient();
  final result = InfiniteQueryResult<TData, TPageParam>(placeholder: placeholder);

  InfiniteQueryOptions<TData, dynamic, TPageParam> buildOptions() =>
      InfiniteQueryOptions<TData, dynamic, TPageParam>(
        resolveReactiveKey(queryKey),
        queryFn,
        initialPageParam:     initialPageParam,
        nextPageParamBuilder: nextPageParamBuilder,
        prevPageParamBuilder: prevPageParamBuilder,
        maxPages:             maxPages,
        enabled:              plainValue(enabled) as bool?,
        networkMode:          networkMode,
        staleDuration:        staleDuration,
        gcDuration:           gcDuration,
        placeholder:          placeholder,
        refetchOnMount:       refetchOnMount,
        refetchOnResume:      refetchOnResume,
        refetchOnReconnect:   refetchOnReconnect,
        refetchInterval:      refetchInterval,
        retry:                retry,
        retryOnMount:         retryOnMount,
        seed:                 seed,
        seedUpdatedAt:        seedUpdatedAt,
        meta:                 meta,
      );

  final observer = InfiniteQueryObserver<TData, dynamic, TPageParam>(
    resolvedClient,
    buildOptions(),
  );

  observer.onMount();
  result.update(observer.result);
  final unsubscribe = observer.subscribe(result.update);

  void update() => observer.options = buildOptions();
  final rxSubs = bindReactive([...queryKey, enabled], update);

  result.disposeCallback = () {
    unsubscribe();
    observer.onUnmount();
    for (final s in rxSubs) {
      s.cancel();
    }
  };

  return result;
}
