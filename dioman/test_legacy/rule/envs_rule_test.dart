// ignore_for_file: avoid_relative_lib_imports
// 规则层：envs
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkDiomanEnvs, () {
    test(
        '[DiomanEnvs.new(dio)][EnvRule.rule] the first matching rule wins and its BaseOptions fields are '
        'shallow-merged into dio.options; a later, also-matching rule is '
        'never even evaluated', () {
      final dio = Dio();
      var secondRuleEvaluated = false;
      DiomanEnvs([
        EnvRule(
          rule: () => true,
          config: BaseOptions(
            baseUrl: tkHttpsProdExampleCom,
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 6),
            sendTimeout: const Duration(seconds: 7),
            headers: {tkXEnv: tkProd},
          ),
        ),
        EnvRule(
          rule: () {
            secondRuleEvaluated = true;
            return true;
          },
          config: BaseOptions(baseUrl: 'https://staging.example.com'),
        ),
      ], dio: dio);

      expect(dio.options.baseUrl, tkHttpsProdExampleCom);
      expect(dio.options.connectTimeout, const Duration(seconds: 5));
      expect(dio.options.receiveTimeout, const Duration(seconds: 6));
      expect(dio.options.sendTimeout, const Duration(seconds: 7));
      expect(dio.options.headers[tkXEnv], tkProd);
      expect(secondRuleEvaluated, isFalse,
          reason: 'first match wins — later rules are never evaluated');
    });
    test(
        '[EnvRule.rule] no matching rule leaves dio.options completely untouched',
        () {
      final dio = Dio(BaseOptions(baseUrl: tkHttpsDefaultExampleCom));
      DiomanEnvs([
        EnvRule(rule: () => false, config: BaseOptions(baseUrl: tkHttpsX)),
      ], dio: dio);

      expect(dio.options.baseUrl, tkHttpsDefaultExampleCom);
    });
    test(
        '[EnvRule.config][EnvRule.rule] a rule that only sets responseType to something other than the '
        'json default applies it; one that never touches responseType '
        "never resets a caller's own bytes/stream setting back to json", () {
      final dio1 = Dio();
      DiomanEnvs([
        EnvRule(
          rule: () => true,
          config: BaseOptions(responseType: ResponseType.bytes),
        ),
      ], dio: dio1);
      expect(dio1.options.responseType, ResponseType.bytes);

      final dio2 = Dio(BaseOptions(responseType: ResponseType.stream));
      DiomanEnvs([
        EnvRule(rule: () => true, config: BaseOptions(baseUrl: tkHttpsX)),
      ], dio: dio2);
      expect(dio2.options.responseType, ResponseType.stream,
          reason: 'the rule never set responseType, so the pre-existing '
              'stream setting must survive — not get reset to the '
              "BaseOptions default of json");
    });
    test(
        '[DiomanEnvs.new(enabled)][EnvRule.rule][DiomanEnvs.apply] a constructor-level disabled DiomanEnvs makes apply() a permanent '
        'no-op even with a matching rule', () {
      final dio = Dio(BaseOptions(baseUrl: tkHttpsDefaultExampleCom));
      final envs = DiomanEnvs(
        [EnvRule(rule: () => true, config: BaseOptions(baseUrl: tkHttpsX))],
        enabled: false,
      );
      envs.apply(dio);
      expect(dio.options.baseUrl, tkHttpsDefaultExampleCom);
    });
    test('[DiomanEnvs.pluginName][DiomanEnvs.name] name identifies the plugin',
        () {
      expect(DiomanEnvs(const []).name, tkDiomanEnvs2);
    });
  });
}
