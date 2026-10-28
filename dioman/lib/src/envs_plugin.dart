import 'package:dio/dio.dart';
import 'dioman_plugin.dart';

/// Construction-time options for [DiomanEnvs]. Envs has no per-request
/// behavior, so this only controls whether the plugin is enabled at all.
///
/// [DiomanEnvs]的构造期选项。envs没有单请求级行为，这里只控制插件整体是否生效。
class DiomanEnvsOptions {
  const DiomanEnvsOptions({this.enabled = true});

  /// `false` disables the plugin entirely — [DiomanEnvs.apply] becomes a no-op.
  ///
  /// `false`时插件整体失效——[DiomanEnvs.apply]变成空操作。
  final bool enabled;
}

/// A single environment rule.
///
/// 单条环境规则。
class EnvRule {
  const EnvRule({required this.rule, required this.config});

  /// Returns true when this rule matches the current environment.
  ///
  /// 当前环境匹配这条规则时返回true。
  final bool Function() rule;

  /// [BaseOptions] fields to shallow-merge into `dio.options` when the rule
  /// matches. Only non-null fields are applied.
  ///
  /// 规则匹配时，浅合并进`dio.options`的[BaseOptions]字段。只应用非空字段。
  final BaseOptions config;
}

/// Applies environment-specific [BaseOptions] to a [Dio] instance at install
/// time — zero runtime overhead after that.
///
/// 在安装时把环境相关的[BaseOptions]套用到某个[Dio]实例——之后零运行时开销。
///
/// Rules are evaluated in order; the **first matching rule wins** and the rest
/// are ignored. If no rule matches, the plugin is a no-op.
///
/// 规则按顺序求值；**第一条命中**的规则生效，其余忽略。若都不匹配，插件不做任何事。
///
/// Nothing is applied until [apply] runs. Either pass `dio:` to the
/// constructor (it applies right away), or call [apply] yourself — neither
/// `Dioman.install` nor `DiomanHandle` calls it for you.
///
/// 在[apply]执行之前不会套用任何配置。要么构造时传`dio:`（立即套用），要么自己调
/// [apply]——`Dioman.install`和`DiomanHandle`都不会替你调用。
///
/// ```dart
/// final rules = [
///   EnvRule(
///     rule: () => const bool.fromEnvironment('dart.vm.product') == false,
///     config: BaseOptions(baseUrl: 'https://dev-api.example.com'),
///   ),
///   EnvRule(
///     rule: () => true, // fallback
///     config: BaseOptions(baseUrl: 'https://api.example.com'),
///   ),
/// ];
/// // 方式一：构造时传 dio，立即套用
/// final envs = DiomanEnvs(rules, dio: dio);
/// // 方式二：先构造，稍后手动套用
/// // final envs = DiomanEnvs(rules)..apply(dio);
/// dio.interceptors.add(envs);
/// ```
class DiomanEnvs extends DiomanPlugin {
  /// Pass [dio] to apply the matching rule immediately at construction
  /// (env config is install-time, one-shot). Omit it to apply later via
  /// [apply] yourself.
  ///
  /// 传[dio]则在构造时立即套用匹配的规则（环境配置是安装期一次性的）。
  /// 省略则需稍后自行调用[apply]。
  DiomanEnvs(this.rules, {Dio? dio, bool enabled = true})
      : config = DiomanEnvsOptions(enabled: enabled) {
    if (dio != null) apply(dio);
  }

  /// The ordered list of environment rules to evaluate.
  ///
  /// 待求值的环境规则列表（有顺序）。
  final List<EnvRule> rules;

  /// This plugin's resolved construction-time options.
  ///
  /// 本插件解析后的构造期选项。
  final DiomanEnvsOptions config;

  /// Public plugin name / extra key for this plugin, accessible without an instance.
  ///
  /// 插件名 / extra键，无需实例即可访问。
  static const pluginName = 'dioman:envs';

  @override
  String get name => pluginName;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Envs is install-time only — nothing to do at request time.
    //
    // envs只在安装期生效——请求时无需做任何事。
    handler.next(options);
  }

  /// Applies the **first matching** rule's [BaseOptions] to [dio]`.options`
  /// (only non-null / non-default fields are written; `responseType` only when
  /// it is not [ResponseType.json]). A no-op when the plugin is disabled or no
  /// rule matches. Called automatically only by the constructor when `dio:` is
  /// passed — [Dioman.install] and [DiomanHandle] do NOT call it, so with an
  /// omitted `dio:` you must call it yourself. It is not tied to the
  /// interceptor chain, so it may run before or after adding the plugin.
  ///
  /// - [dio]: the instance whose `options` receive the matched rule's config.
  ///
  /// ```dart
  /// final envs = DiomanEnvs(rules);
  /// envs.apply(dio); // 手动套用一次
  /// ```
  ///
  /// 套用**第一条命中**规则的[BaseOptions]到[dio]`.options`（只写入非空/非默认
  /// 字段；`responseType`仅在不是[ResponseType.json]时才写）。插件被禁用或没有
  /// 规则命中时什么也不做。只有构造时传了`dio:`才会自动调用；[Dioman.install]和
  /// [DiomanHandle]都**不会**调用它，省略`dio:`时须自己调。它与拦截器链无关，
  /// 加入插件之前或之后调用都可以。
  ///
  /// - [dio]：接收命中规则配置的实例。
  void apply(Dio dio) {
    if (!config.enabled) return;
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
      //
      // BaseOptions.responseType非空且默认是json，不能像上面那些字段一样直接
      // 判空——只有规则显式设置了非默认值才应用，否则一条只配置了baseUrl的
      // 规则会悄悄把用户配置的bytes/stream responseType重置回json。
      if (c.responseType != ResponseType.json) {
        dio.options.responseType = c.responseType;
      }
      return;
    }
  }
}
