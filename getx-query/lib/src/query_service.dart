import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_query/flutter_query.dart';
import 'package:get/get.dart';

/// Singleton [QueryClient] registered as a [GetxService].
///
/// Automatically wires up [connectivity_plus] so [refetchOnReconnect]
/// works out of the box.
///
/// Register in [_AppBinding]:
/// ```dart
/// Get.put<QueryService>(QueryService(), permanent: true);
/// ```
///
/// Every option is an individually-overridable named parameter, merged
/// field-by-field with getx_query's own defaults (5-min stale, 10-min GC,
/// 3 exponential-backoff retries; everything else matches flutter_query's
/// own `DefaultQueryOptions` defaults). Unlike passing a whole
/// `DefaultQueryOptions` object, this lets you change just one field and
/// keep getx_query's defaults for the rest:
/// ```dart
/// Get.put<QueryService>(
///   QueryService(gcDuration: GcDuration(minutes: 30)), // staleDuration/retry stay getx_query's defaults
///   permanent: true,
/// );
/// ```
///
/// Pass [connectivityChanges] to swap the connectivity source (e.g. for
/// tests, or a non-`connectivity_plus` implementation) — it must emit the
/// current state on first listen, same requirement as [QueryClient] itself.
class QueryService extends GetxService {
  QueryService({
    bool? enabled,
    NetworkMode? networkMode,
    StaleDuration? staleDuration,
    GcDuration? gcDuration,
    Duration? refetchInterval,
    RefetchOnMount? refetchOnMount,
    RefetchOnResume? refetchOnResume,
    RefetchOnReconnect? refetchOnReconnect,
    RetryResolver? retry,
    bool? retryOnMount,
    Map<String, dynamic>? meta,
    Stream<bool>? connectivityChanges,
  })  : _enabled = enabled,
        _networkMode = networkMode,
        _staleDuration = staleDuration,
        _gcDuration = gcDuration,
        _refetchInterval = refetchInterval,
        _refetchOnMount = refetchOnMount,
        _refetchOnResume = refetchOnResume,
        _refetchOnReconnect = refetchOnReconnect,
        _retry = retry,
        _retryOnMount = retryOnMount,
        _meta = meta,
        _connectivityChanges = connectivityChanges;

  final bool? _enabled;
  final NetworkMode? _networkMode;
  final StaleDuration? _staleDuration;
  final GcDuration? _gcDuration;
  final Duration? _refetchInterval;
  final RefetchOnMount? _refetchOnMount;
  final RefetchOnResume? _refetchOnResume;
  final RefetchOnReconnect? _refetchOnReconnect;
  final RetryResolver? _retry;
  final bool? _retryOnMount;
  final Map<String, dynamic>? _meta;
  final Stream<bool>? _connectivityChanges;

  late final QueryClient client;

  @override
  void onInit() {
    super.onInit();
    client = QueryClient(
      // connectivity_plus emits the current state on first listen,
      // which is the behaviour QueryClient requires.
      connectivityChanges: _connectivityChanges ??
          Connectivity().onConnectivityChanged.map(
                (results) => !results.contains(ConnectivityResult.none),
              ),
      defaultQueryOptions: DefaultQueryOptions(
        enabled: _enabled ?? true,
        networkMode: _networkMode ?? NetworkMode.online,
        staleDuration: _staleDuration ?? StaleDuration(minutes: 5),
        gcDuration: _gcDuration ?? GcDuration(minutes: 10),
        refetchInterval: _refetchInterval,
        refetchOnMount: _refetchOnMount ?? RefetchOnMount.stale,
        refetchOnResume: _refetchOnResume ?? RefetchOnResume.stale,
        refetchOnReconnect: _refetchOnReconnect ?? RefetchOnReconnect.stale,
        retry: _retry ??
            (count, _) => count < 3
                ? Duration(seconds: 1 << count) // 1 s, 2 s, 4 s
                : null,
        retryOnMount: _retryOnMount ?? true,
        meta: _meta,
      ),
    );
  }

  @override
  void onClose() {
    client.clear();
    super.onClose();
  }
}
