import 'package:dio/dio.dart';
import '../client.dart';
import '../config.dart';
import '../plugin.dart';
import '../response.dart';

/// 安装时求值的环境规则；首个命中者生效。
class EnvRule {
  /// [rule] 返回是否命中，[config] 提供配置模板，例如 `BaseOptions(baseUrl: '/api')`。
  const EnvRule({required this.rule, required this.config});

  /// 当前环境是否匹配；异常原样中断 setup。
  final bool Function() rule;

  /// 非默认字段和容器的配置模板，写入前深拷贝容器。
  final BaseOptions config;
}

/// envs 安装期开关，没有请求级选项。
class DiomanEnvsOptions {
  /// [enabled] 为 false 时内核跳过 setup。
  const DiomanEnvsOptions({this.enabled = true});

  /// 是否应用环境规则。
  final bool enabled;
}

/// 仅在 setup 合并首个命中的环境配置，不进入请求链。
class DiomanEnvs<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// [rules] 按顺序短路匹配，例如 `DiomanEnvs([EnvRule(rule: () => true, config: BaseOptions())])`。
  const DiomanEnvs(this.rules, {bool enabled = true})
      : config = enabled
            ? const DiomanEnvsOptions()
            : const DiomanEnvsOptions(enabled: false);

  /// 规则列表，仅 setup 时读取。
  final List<EnvRule> rules;

  /// 安装配置。
  final DiomanEnvsOptions config;

  /// 稳定插件名称。
  static const pluginName = 'dioman:envs';

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 返回安装期开关。
  @override
  bool get enabled => config.enabled;

  /// 克隆后合并配置；返回 null 表示不进入链，卸载不还原配置。
  @override
  DiomanPluginInstance<R>? setup(Dioman<R> client) {
    for (final entry in rules) {
      if (!entry.rule()) continue;
      client.dio.options = cloneDiomanOptions(client.dio.options);
      mergeDiomanOptions(client.dio.options, entry.config);
      break;
    }
    return null;
  }
}
