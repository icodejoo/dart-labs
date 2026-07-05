import 'package:dio/dio.dart';

/// Base class for all Dio plugins.
///
/// A plugin is a named [Interceptor] that handles request, response,
/// and error events. Override only what you need.
///
/// [dispose] is called when the plugin is ejected — use it to cancel
/// timers, close streams, or reset state.
abstract class DioPlugin extends Interceptor {
  const DioPlugin();

  /// Unique identifier. Used by the plugin manager for lookup and dedup.
  String get name;

  /// Called when the plugin is ejected from the Dio instance.
  void dispose() {}
}
