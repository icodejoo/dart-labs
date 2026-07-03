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
class QueryService extends GetxService {
  late final QueryClient client;

  @override
  void onInit() {
    super.onInit();
    client = QueryClient(
      // connectivity_plus emits the current state on first listen,
      // which is the behaviour QueryClient requires.
      connectivityChanges: Connectivity().onConnectivityChanged.map(
        (results) => !results.contains(ConnectivityResult.none),
      ),
      defaultQueryOptions: DefaultQueryOptions(
        staleDuration: StaleDuration(minutes: 5),
        gcDuration: GcDuration(minutes: 10),
        retry: (count, _) => count < 3
            ? Duration(seconds: 1 << count) // 1 s, 2 s, 4 s
            : null,
      ),
    );
  }

  @override
  void onClose() {
    client.clear();
    super.onClose();
  }
}
