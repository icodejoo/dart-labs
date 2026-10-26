import 'package:dio/dio.dart';

import 'plugin_order.dart';

/// Base class for all Dio plugins.
///
/// A plugin is a named [Interceptor] that handles request, response,
/// and error events. Override only what you need.
///
/// [dispose] is called when the plugin is ejected — use it to cancel
/// timers, close streams, or reset state.
abstract class DiomanPlugin extends Interceptor {
  const DiomanPlugin();

  /// Unique identifier. Used by the plugin manager for lookup and dedup.
  String get name;

  /// 本插件的顺序声明（before/after 约束与必需依赖），默认无约束。
  ///
  /// 覆写它即可让 `Dioman.sort`/`Dioman.installPlugins` 自动排序，并在安装与
  /// 动态插入时校验。详见 [DiomanPluginOrder]。
  DiomanPluginOrder get ordering => DiomanPluginOrder.none;

  /// Called when the plugin is ejected from the Dio instance.
  void dispose() {}
}
