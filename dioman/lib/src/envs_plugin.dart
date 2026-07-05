import 'package:dio/dio.dart';
import 'dio_plugin.dart';

/// A single environment rule.
class EnvRule {
  const EnvRule({required this.rule, required this.config});

  /// Returns true when this rule matches the current environment.
  final bool Function() rule;

  /// [BaseOptions] fields to shallow-merge into `dio.options` when the rule
  /// matches. Only non-null fields are applied.
  final BaseOptions config;
}

/// Applies environment-specific [BaseOptions] to a [Dio] instance at install
/// time — zero runtime overhead after that.
///
/// Rules are evaluated in order; the **first matching rule wins** and the rest
/// are ignored. If no rule matches, the plugin is a no-op.
///
/// ```dart
/// dio.interceptors.add(EnvsPlugin([
///   EnvRule(
///     rule: () => const bool.fromEnvironment('dart.vm.product') == false,
///     config: BaseOptions(baseUrl: 'https://dev-api.example.com'),
///   ),
///   EnvRule(
///     rule: () => true, // fallback
///     config: BaseOptions(baseUrl: 'https://api.example.com'),
///   ),
/// ]));
/// ```
class EnvsPlugin extends DioPlugin {
  /// Pass [dio] to apply the matching rule immediately at construction
  /// (env config is install-time, one-shot). Omit it to apply later via
  /// [apply] yourself.
  EnvsPlugin(this.rules, {Dio? dio}) {
    if (dio != null) apply(dio);
  }

  final List<EnvRule> rules;

  @override
  String get name => 'envs';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Envs is install-time only — nothing to do at request time.
    handler.next(options);
  }

  /// Called by the plugin manager after the interceptor is added.
  /// Public so the manager (or the user) can trigger it explicitly.
  void apply(Dio dio) {
    for (final r in rules) {
      if (!r.rule()) continue;
      final c = r.config;
      if (c.baseUrl.isNotEmpty) dio.options.baseUrl = c.baseUrl;
      if (c.connectTimeout != null) dio.options.connectTimeout = c.connectTimeout;
      if (c.receiveTimeout != null) dio.options.receiveTimeout = c.receiveTimeout;
      if (c.sendTimeout != null) dio.options.sendTimeout = c.sendTimeout;
      if (c.headers.isNotEmpty) dio.options.headers.addAll(c.headers);
      // BaseOptions.responseType is non-nullable and defaults to json, so it
      // can't be null-checked like the fields above — only apply it when the
      // rule explicitly set something other than that default, otherwise a
      // rule that only configures e.g. baseUrl would silently reset a
      // user-configured bytes/stream responseType back to json.
      if (c.responseType != ResponseType.json) {
        dio.options.responseType = c.responseType;
      }
      return;
    }
  }
}
