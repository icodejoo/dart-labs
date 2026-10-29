import 'dart:io';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

/// 编译诊断和夹具共用的换行。
const _newline = '\n';

/// 夹具语句共用的分隔。
const _statementSeparator = '\n  ';

/// 锁定唯一入口的声明可达性；行为仍由各层规则测试验证。
void main() {
  test('[INV-context-lifecycle] 公共入口无法访问内部类型、扩展或白盒成员', () async {
    const hidden = [
      'DiomanContextState',
      'DiomanCancelLink',
      'DiomanShareApi',
      'DiomanContextInternal',
      'DiomanDiagnostics',
      'DiomanCacheDiagnostics',
      'DiomanShareDiagnostics',
      'DiomanResponseFactoryInternal',
      'DiomanRunner',
      'DiomanRegistration',
      'validateDiomanPlugins',
      'sortDiomanPipeline',
      'compileDiomanPipeline',
      'diomanSetupPlugins',
      'diomanBuiltinStages',
      'diomanTransport',
      'cancellationFailure',
    ];
    const getters = [
      'client.cancellationSubscriptions',
      'context.cancellationSubscriptions',
      'context.state',
      'context.replayable',
      'factory.withCallSite',
      'cache.pendingWrites',
      'cache.entryCount',
    ];
    final fixture = File('.dart_tool/public_surface_probe.dart');
    try {
      fixture.writeAsStringSync('''
import 'package:dioman/dioman.dart' as api;
void probe(api.Dioman client, api.DiomanContext context, api.DiomanCacheApi cache, api.DiomanResponseFactory factory) {
  ${hidden.map((name) => 'print(api.$name);').join(_statementSeparator)}
  ${getters.map((name) => 'print($name);').join(_statementSeparator)}
}
''');
      final result = await Process.run(Platform.resolvedExecutable,
          ['analyze', '--format', 'machine', fixture.path]);
      final errors = '${result.stdout}\n${result.stderr}'
          .split(_newline)
          .where((line) => line.startsWith('ERROR|'))
          .toList();
      expect(result.exitCode, isNonZero);
      expect(errors.where((line) => line.contains('|UNDEFINED_PREFIXED_NAME|')),
          hasLength(hidden.length),
          reason: errors.join(_newline));
      expect(errors.where((line) => line.contains('|UNDEFINED_GETTER|')),
          hasLength(getters.length),
          reason: errors.join(_newline));
      expect(errors, hasLength(hidden.length + getters.length));
    } finally {
      if (fixture.existsSync()) fixture.deleteSync();
    }
  });
  test('[Dioman][Dioman.new] 导出声明可解析', () {
    final Type declaration = Dioman;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanClock][DiomanClock.system] 导出声明可解析', () {
    final Type declaration = DiomanClock;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanLogger] 导出声明可解析', () {
    final Type declaration = DiomanLogger;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[StateKey][StateKey.new] 导出声明可解析', () {
    final Type declaration = StateKey;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanContext][DiomanContext.new] 导出声明可解析', () {
    final Type declaration = DiomanContext;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanKeyOptions][DiomanKeyOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanKeyOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanKeyService][DiomanKeyService.new] 导出声明可解析', () {
    final Type declaration = DiomanKeyService;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanOptionKey][DiomanOptionKey.new] 导出声明可解析', () {
    final Type declaration = DiomanOptionKey;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCall][DiomanCall.new] 导出声明可解析', () {
    final Type declaration = DiomanCall;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanNext] 导出声明可解析', () {
    final Type declaration = DiomanNext;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanPlugin][DiomanPlugin.new] 导出声明可解析', () {
    final Type declaration = DiomanPlugin;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanPluginInstance] 导出声明可解析', () {
    final Type declaration = DiomanPluginInstance;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRequest][DiomanRequest.new] 导出声明可解析', () {
    final Type declaration = DiomanRequest;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[RequestPatch][RequestPatch.new] 导出声明可解析', () {
    final Type declaration = RequestPatch;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanKind] 导出声明可解析', () {
    final Type declaration = DiomanKind;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[Envelope][Envelope.new] 导出声明可解析', () {
    final Type declaration = Envelope;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanResponse][DiomanResponse.new] 导出声明可解析', () {
    final Type declaration = DiomanResponse;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanFailure][DiomanFailure.new] 导出声明可解析', () {
    final Type declaration = DiomanFailure;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanResponseFactory][DiomanResponseFactory.new] 导出声明可解析', () {
    final Type declaration = DiomanResponseFactory;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanStage] 导出声明可解析', () {
    final Type declaration = DiomanStage;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanEnforce] 导出声明可解析', () {
    final Type declaration = DiomanEnforce;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanLoadingOptions][DiomanLoadingOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanLoadingOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanLoadingApi] 导出声明可解析', () {
    final Type declaration = DiomanLoadingApi;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanLoading][DiomanLoading.new] 导出声明可解析', () {
    final Type declaration = DiomanLoading;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanNotify][DiomanNotify.new] 导出声明可解析', () {
    final Type declaration = DiomanNotify;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRepathOptions][DiomanRepathOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanRepathOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRepath][DiomanRepath.new] 导出声明可解析', () {
    final Type declaration = DiomanRepath;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanFilterPredicate] 导出声明可解析', () {
    final Type declaration = DiomanFilterPredicate;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanFilterOptions][DiomanFilterOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanFilterOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanFilter][DiomanFilter.new] 导出声明可解析', () {
    final Type declaration = DiomanFilter;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[NetworkQuality] 导出声明可解析', () {
    final Type declaration = NetworkQuality;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanTimeouts][DiomanTimeouts.new] 导出声明可解析', () {
    final Type declaration = DiomanTimeouts;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanTimeoutOptions][DiomanTimeoutOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanTimeoutOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanTimeout][DiomanTimeout.new] 导出声明可解析', () {
    final Type declaration = DiomanTimeout;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[EnvRule][EnvRule.new] 导出声明可解析', () {
    final Type declaration = EnvRule;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanEnvsOptions][DiomanEnvsOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanEnvsOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanEnvs][DiomanEnvs.new] 导出声明可解析', () {
    final Type declaration = DiomanEnvs;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanShouldRetry] 导出声明可解析', () {
    final Type declaration = DiomanShouldRetry;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRetryDelay] 导出声明可解析', () {
    final Type declaration = DiomanRetryDelay;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanJitter] 导出声明可解析', () {
    final Type declaration = DiomanJitter;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRetryOptions][DiomanRetryOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanRetryOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanRetry][DiomanRetry.new] 导出声明可解析', () {
    final Type declaration = DiomanRetry;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanBreakerState] 导出声明可解析', () {
    final Type declaration = DiomanBreakerState;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanShouldTrip] 导出声明可解析', () {
    final Type declaration = DiomanShouldTrip;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanBreakerApi] 导出声明可解析', () {
    final Type declaration = DiomanBreakerApi;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanBreakerOptions][DiomanBreakerOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanBreakerOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanBreaker][DiomanBreaker.new] 导出声明可解析', () {
    final Type declaration = DiomanBreaker;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthFailureAction] 导出声明可解析', () {
    final Type declaration = DiomanAuthFailureAction;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthNotice] 导出声明可解析', () {
    final Type declaration = DiomanAuthNotice;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthRefresh] 导出声明可解析', () {
    final Type declaration = DiomanAuthRefresh;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthFailure] 导出声明可解析', () {
    final Type declaration = DiomanAuthFailure;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthReady] 导出声明可解析', () {
    final Type declaration = DiomanAuthReady;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuthOptions][DiomanAuthOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanAuthOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanAuth][DiomanAuth.new] 导出声明可解析', () {
    final Type declaration = DiomanAuth;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanTokenManager] 导出声明可解析', () {
    final Type declaration = DiomanTokenManager;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCachePersist] 导出声明可解析', () {
    final Type declaration = DiomanCachePersist;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanMockRoute] 导出声明可解析', () {
    final Type declaration = DiomanMockRoute;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanMockOptions][DiomanMockOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanMockOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanMock][DiomanMock.new] 导出声明可解析', () {
    final Type declaration = DiomanMock;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanSharePolicy] 导出声明可解析', () {
    final Type declaration = DiomanSharePolicy;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanShareOptions][DiomanShareOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanShareOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanShare][DiomanShare.new] 导出声明可解析', () {
    final Type declaration = DiomanShare;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanClonePolicy] 导出声明可解析', () {
    final Type declaration = DiomanClonePolicy;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCachePolicy] 导出声明可解析', () {
    final Type declaration = DiomanCachePolicy;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCacheOptions][DiomanCacheOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanCacheOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCacheApi] 导出声明可解析', () {
    final Type declaration = DiomanCacheApi;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanCache][DiomanCache.new] 导出声明可解析', () {
    final Type declaration = DiomanCache;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanOfflineOptions][DiomanOfflineOptions.new] 导出声明可解析', () {
    final Type declaration = DiomanOfflineOptions;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanOfflineApi] 导出声明可解析', () {
    final Type declaration = DiomanOfflineApi;
    expect(declaration.toString(), isNotEmpty);
  });
  test('[DiomanOffline][DiomanOffline.new] 导出声明可解析', () {
    final Type declaration = DiomanOffline;
    expect(declaration.toString(), isNotEmpty);
  });
}
