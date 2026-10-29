part of 'probes.dart';

/// 自动生成的逐属性读取检查器，由 inventory.dart 更新。
void generatedInspect(ApiEvidence e, Map<String, Object> values) {
  if (values['Dioman'] is Dioman) {
    final v = values['Dioman'] as Dioman;
    final snapshot = <String, Object?>{
      'Dioman.dio': v.dio,
      'Dioman.response': v.response,
      'Dioman.key': v.key,
      'Dioman.reject': v.reject,
      'Dioman.clock': v.clock,
      'Dioman.pending': v.pending,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['StateKey'] is StateKey) {
    final v = values['StateKey'] as StateKey;
    final snapshot = <String, Object?>{
      'StateKey.description': v.description,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanContext'] is DiomanContext) {
    final v = values['DiomanContext'] as DiomanContext;
    final snapshot = <String, Object?>{
      'DiomanContext.id': v.id,
      'DiomanContext.client': v.client,
      'DiomanContext.request': v.request,
      'DiomanContext.factory': v.factory,
      'DiomanContext.keyService': v.keyService,
      'DiomanContext.clock': v.clock,
      'DiomanContext.log': v.log,
      'DiomanContext.cancelToken': v.cancelToken,
      'DiomanContext.isCancelled': v.isCancelled,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanKeyOptions'] is DiomanKeyOptions) {
    final v = values['DiomanKeyOptions'] as DiomanKeyOptions;
    final snapshot = <String, Object?>{
      'DiomanKeyOptions.fastMode': v.fastMode,
      'DiomanKeyOptions.ignores': v.ignores,
      'DiomanKeyOptions.builder': v.builder,
      'DiomanKeyOptions.namespace': v.namespace,
      'DiomanKeyOptions.key': v.key,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanKeyService.maxBodyBytes', DiomanKeyService.maxBodyBytes);
  if (values['DiomanKeyService'] is DiomanKeyService) {
    final v = values['DiomanKeyService'] as DiomanKeyService;
    final snapshot = <String, Object?>{
      'DiomanKeyService.options': v.options,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanOptionKey'] is DiomanOptionKey) {
    final v = values['DiomanOptionKey'] as DiomanOptionKey;
    final snapshot = <String, Object?>{
      'DiomanOptionKey.description': v.description,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanCall'] is DiomanCall) {
    final v = values['DiomanCall'] as DiomanCall;
    final snapshot = <String, Object?>{
      'DiomanCall.headers': v.headers,
      'DiomanCall.connectTimeout': v.connectTimeout,
      'DiomanCall.sendTimeout': v.sendTimeout,
      'DiomanCall.receiveTimeout': v.receiveTimeout,
      'DiomanCall.cancelToken': v.cancelToken,
      'DiomanCall.key': v.key,
      'DiomanCall.envelope': v.envelope,
      'DiomanCall.silent': v.silent,
      'DiomanCall.options': v.options,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanPlugin'] is DiomanPlugin) {
    final v = values['DiomanPlugin'] as DiomanPlugin;
    final snapshot = <String, Object?>{
      'DiomanPlugin.name': v.name,
      'DiomanPlugin.stage': v.stage,
      'DiomanPlugin.enforce': v.enforce,
      'DiomanPlugin.enabled': v.enabled,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanRequest'] is DiomanRequest) {
    final v = values['DiomanRequest'] as DiomanRequest;
    final snapshot = <String, Object?>{
      'DiomanRequest.data': v.data,
      'DiomanRequest.headers': v.headers,
      'DiomanRequest.query': v.query,
      'DiomanRequest.extra': v.extra,
      'DiomanRequest.call': v.call,
      'DiomanRequest.path': v.path,
      'DiomanRequest.method': v.method,
      'DiomanRequest.baseUrl': v.baseUrl,
      'DiomanRequest.uri': v.uri,
      'DiomanRequest.connectTimeout': v.connectTimeout,
      'DiomanRequest.sendTimeout': v.sendTimeout,
      'DiomanRequest.receiveTimeout': v.receiveTimeout,
      'DiomanRequest.cancelToken': v.cancelToken,
      'DiomanRequest.silent': v.silent,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['RequestPatch'] is RequestPatch) {
    final v = values['RequestPatch'] as RequestPatch;
    final snapshot = <String, Object?>{
      'RequestPatch.headers': v.headers,
      'RequestPatch.query': v.query,
      'RequestPatch.extra': v.extra,
      'RequestPatch.removeHeaders': v.removeHeaders,
      'RequestPatch.removeQuery': v.removeQuery,
      'RequestPatch.data': v.data,
      'RequestPatch.path': v.path,
      'RequestPatch.method': v.method,
      'RequestPatch.connectTimeout': v.connectTimeout,
      'RequestPatch.sendTimeout': v.sendTimeout,
      'RequestPatch.receiveTimeout': v.receiveTimeout,
      'RequestPatch.cancelToken': v.cancelToken,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['Envelope'] is Envelope) {
    final v = values['Envelope'] as Envelope;
    final snapshot = <String, Object?>{
      'Envelope.code': v.code,
      'Envelope.data': v.data,
      'Envelope.message': v.message,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanResponse'] is DiomanResponse) {
    final v = values['DiomanResponse'] as DiomanResponse;
    final snapshot = <String, Object?>{
      'DiomanResponse.ok': v.ok,
      'DiomanResponse.kind': v.kind,
      'DiomanResponse.status': v.status,
      'DiomanResponse.httpStatus': v.httpStatus,
      'DiomanResponse.code': v.code,
      'DiomanResponse.message': v.message,
      'DiomanResponse.data': v.data,
      'DiomanResponse.reason': v.reason,
      'DiomanResponse.request': v.request,
      'DiomanResponse.raw': v.raw,
      'DiomanResponse.error': v.error,
      'DiomanResponse.errorStack': v.errorStack,
      'DiomanResponse.callSite': v.callSite,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanFailure'] is DiomanFailure) {
    final v = values['DiomanFailure'] as DiomanFailure;
    final snapshot = <String, Object?>{
      'DiomanFailure.kind': v.kind,
      'DiomanFailure.status': v.status,
      'DiomanFailure.message': v.message,
      'DiomanFailure.reason': v.reason,
      'DiomanFailure.data': v.data,
      'DiomanFailure.error': v.error,
      'DiomanFailure.errorStack': v.errorStack,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanResponseFactory'] is DiomanResponseFactory) {
    final v = values['DiomanResponseFactory'] as DiomanResponseFactory;
    final snapshot = <String, Object?>{
      'DiomanResponseFactory.envelope': v.envelope,
      'DiomanResponseFactory.isEnvelope': v.isEnvelope,
      'DiomanResponseFactory.isSuccess': v.isSuccess,
      'DiomanResponseFactory.logicalStatus': v.logicalStatus,
      'DiomanResponseFactory.expectJson': v.expectJson,
      'DiomanResponseFactory.create': v.create,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanLoadingOptions'] is DiomanLoadingOptions) {
    final v = values['DiomanLoadingOptions'] as DiomanLoadingOptions;
    final snapshot = <String, Object?>{
      'DiomanLoadingOptions.enabled': v.enabled,
      'DiomanLoadingOptions.onChanged': v.onChanged,
      'DiomanLoadingOptions.delay': v.delay,
      'DiomanLoadingOptions.delayClose': v.delayClose,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanLoadingApi'] is DiomanLoadingApi) {
    final v = values['DiomanLoadingApi'] as DiomanLoadingApi;
    final snapshot = <String, Object?>{
      'DiomanLoadingApi.activeCount': v.activeCount,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanLoading.pluginName', DiomanLoading.pluginName);
  e.read('DiomanLoading.option', DiomanLoading.option);
  if (values['DiomanLoading'] is DiomanLoading) {
    final v = values['DiomanLoading'] as DiomanLoading;
    final snapshot = <String, Object?>{
      'DiomanLoading.onChanged': v.onChanged,
      'DiomanLoading.delay': v.delay,
      'DiomanLoading.delayClose': v.delayClose,
      'DiomanLoading.enabled': v.enabled,
      'DiomanLoading.name': v.name,
      'DiomanLoading.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanNotify.pluginName', DiomanNotify.pluginName);
  e.read('DiomanNotify.option', DiomanNotify.option);
  if (values['DiomanNotify'] is DiomanNotify) {
    final v = values['DiomanNotify'] as DiomanNotify;
    final snapshot = <String, Object?>{
      'DiomanNotify.notify': v.notify,
      'DiomanNotify.stringify': v.stringify,
      'DiomanNotify.enabled': v.enabled,
      'DiomanNotify.name': v.name,
      'DiomanNotify.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanRepathOptions'] is DiomanRepathOptions) {
    final v = values['DiomanRepathOptions'] as DiomanRepathOptions;
    final snapshot = <String, Object?>{
      'DiomanRepathOptions.enabled': v.enabled,
      'DiomanRepathOptions.pattern': v.pattern,
      'DiomanRepathOptions.removeKey': v.removeKey,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanRepath.pluginName', DiomanRepath.pluginName);
  e.read('DiomanRepath.option', DiomanRepath.option);
  e.read('DiomanRepath.defaultPattern', DiomanRepath.defaultPattern);
  if (values['DiomanRepath'] is DiomanRepath) {
    final v = values['DiomanRepath'] as DiomanRepath;
    final snapshot = <String, Object?>{
      'DiomanRepath.pattern': v.pattern,
      'DiomanRepath.removeKey': v.removeKey,
      'DiomanRepath.enabled': v.enabled,
      'DiomanRepath.name': v.name,
      'DiomanRepath.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanFilterOptions'] is DiomanFilterOptions) {
    final v = values['DiomanFilterOptions'] as DiomanFilterOptions;
    final snapshot = <String, Object?>{
      'DiomanFilterOptions.enabled': v.enabled,
      'DiomanFilterOptions.predicate': v.predicate,
      'DiomanFilterOptions.ignoreKeys': v.ignoreKeys,
      'DiomanFilterOptions.ignoreValues': v.ignoreValues,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanFilter.pluginName', DiomanFilter.pluginName);
  e.read('DiomanFilter.option', DiomanFilter.option);
  if (values['DiomanFilter'] is DiomanFilter) {
    final v = values['DiomanFilter'] as DiomanFilter;
    final snapshot = <String, Object?>{
      'DiomanFilter.predicate': v.predicate,
      'DiomanFilter.ignoreKeys': v.ignoreKeys,
      'DiomanFilter.ignoreValues': v.ignoreValues,
      'DiomanFilter.enabled': v.enabled,
      'DiomanFilter.name': v.name,
      'DiomanFilter.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanTimeouts'] is DiomanTimeouts) {
    final v = values['DiomanTimeouts'] as DiomanTimeouts;
    final snapshot = <String, Object?>{
      'DiomanTimeouts.connect': v.connect,
      'DiomanTimeouts.receive': v.receive,
      'DiomanTimeouts.send': v.send,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanTimeoutOptions'] is DiomanTimeoutOptions) {
    final v = values['DiomanTimeoutOptions'] as DiomanTimeoutOptions;
    final snapshot = <String, Object?>{
      'DiomanTimeoutOptions.enabled': v.enabled,
      'DiomanTimeoutOptions.timeouts': v.timeouts,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanTimeout.pluginName', DiomanTimeout.pluginName);
  e.read('DiomanTimeout.option', DiomanTimeout.option);
  e.read('DiomanTimeout.defaultConnect', DiomanTimeout.defaultConnect);
  e.read('DiomanTimeout.defaultTimeouts', DiomanTimeout.defaultTimeouts);
  if (values['DiomanTimeout'] is DiomanTimeout) {
    final v = values['DiomanTimeout'] as DiomanTimeout;
    final snapshot = <String, Object?>{
      'DiomanTimeout.probe': v.probe,
      'DiomanTimeout.timeouts': v.timeouts,
      'DiomanTimeout.enabled': v.enabled,
      'DiomanTimeout.name': v.name,
      'DiomanTimeout.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['EnvRule'] is EnvRule) {
    final v = values['EnvRule'] as EnvRule;
    final snapshot = <String, Object?>{
      'EnvRule.rule': v.rule,
      'EnvRule.config': v.config,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanEnvsOptions'] is DiomanEnvsOptions) {
    final v = values['DiomanEnvsOptions'] as DiomanEnvsOptions;
    final snapshot = <String, Object?>{
      'DiomanEnvsOptions.enabled': v.enabled,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanEnvs.pluginName', DiomanEnvs.pluginName);
  if (values['DiomanEnvs'] is DiomanEnvs) {
    final v = values['DiomanEnvs'] as DiomanEnvs;
    final snapshot = <String, Object?>{
      'DiomanEnvs.rules': v.rules,
      'DiomanEnvs.config': v.config,
      'DiomanEnvs.name': v.name,
      'DiomanEnvs.enabled': v.enabled,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanRetryOptions'] is DiomanRetryOptions) {
    final v = values['DiomanRetryOptions'] as DiomanRetryOptions;
    final snapshot = <String, Object?>{
      'DiomanRetryOptions.enabled': v.enabled,
      'DiomanRetryOptions.max': v.max,
      'DiomanRetryOptions.methods': v.methods,
      'DiomanRetryOptions.statusCodes': v.statusCodes,
      'DiomanRetryOptions.shouldRetry': v.shouldRetry,
      'DiomanRetryOptions.delay': v.delay,
      'DiomanRetryOptions.jitter': v.jitter,
      'DiomanRetryOptions.delayMax': v.delayMax,
      'DiomanRetryOptions.respectRetryAfter': v.respectRetryAfter,
      'DiomanRetryOptions.afterStatusCodes': v.afterStatusCodes,
      'DiomanRetryOptions.retryAfterMax': v.retryAfterMax,
      'DiomanRetryOptions.onRetry': v.onRetry,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanRetry.defaultMethods', DiomanRetry.defaultMethods);
  e.read('DiomanRetry.defaultStatusCodes', DiomanRetry.defaultStatusCodes);
  e.read('DiomanRetry.defaultAfterStatusCodes',
      DiomanRetry.defaultAfterStatusCodes);
  e.read('DiomanRetry.pluginName', DiomanRetry.pluginName);
  e.read('DiomanRetry.option', DiomanRetry.option);
  if (values['DiomanRetry'] is DiomanRetry) {
    final v = values['DiomanRetry'] as DiomanRetry;
    final snapshot = <String, Object?>{
      'DiomanRetry.enabled': v.enabled,
      'DiomanRetry.max': v.max,
      'DiomanRetry.methods': v.methods,
      'DiomanRetry.statusCodes': v.statusCodes,
      'DiomanRetry.shouldRetry': v.shouldRetry,
      'DiomanRetry.delay': v.delay,
      'DiomanRetry.jitter': v.jitter,
      'DiomanRetry.delayMax': v.delayMax,
      'DiomanRetry.respectRetryAfter': v.respectRetryAfter,
      'DiomanRetry.afterStatusCodes': v.afterStatusCodes,
      'DiomanRetry.retryAfterMax': v.retryAfterMax,
      'DiomanRetry.onRetry': v.onRetry,
      'DiomanRetry.name': v.name,
      'DiomanRetry.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanBreakerApi'] is DiomanBreakerApi) {
    final v = values['DiomanBreakerApi'] as DiomanBreakerApi;
    final snapshot = <String, Object?>{
      'DiomanBreakerApi.bucketCount': v.bucketCount,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanBreakerOptions'] is DiomanBreakerOptions) {
    final v = values['DiomanBreakerOptions'] as DiomanBreakerOptions;
    final snapshot = <String, Object?>{
      'DiomanBreakerOptions.enabled': v.enabled,
      'DiomanBreakerOptions.failureThreshold': v.failureThreshold,
      'DiomanBreakerOptions.resetDuration': v.resetDuration,
      'DiomanBreakerOptions.halfOpenMaxCalls': v.halfOpenMaxCalls,
      'DiomanBreakerOptions.shouldTrip': v.shouldTrip,
      'DiomanBreakerOptions.keyBuilder': v.keyBuilder,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanBreaker.defaultFailureThreshold',
      DiomanBreaker.defaultFailureThreshold);
  e.read(
      'DiomanBreaker.defaultResetDuration', DiomanBreaker.defaultResetDuration);
  e.read('DiomanBreaker.defaultHalfOpenMaxCalls',
      DiomanBreaker.defaultHalfOpenMaxCalls);
  e.read('DiomanBreaker.defaultIdleTtl', DiomanBreaker.defaultIdleTtl);
  e.read('DiomanBreaker.defaultMaxBuckets', DiomanBreaker.defaultMaxBuckets);
  e.read('DiomanBreaker.pluginName', DiomanBreaker.pluginName);
  e.read('DiomanBreaker.option', DiomanBreaker.option);
  if (values['DiomanBreaker'] is DiomanBreaker) {
    final v = values['DiomanBreaker'] as DiomanBreaker;
    final snapshot = <String, Object?>{
      'DiomanBreaker.enabled': v.enabled,
      'DiomanBreaker.failureThreshold': v.failureThreshold,
      'DiomanBreaker.resetDuration': v.resetDuration,
      'DiomanBreaker.halfOpenMaxCalls': v.halfOpenMaxCalls,
      'DiomanBreaker.shouldTrip': v.shouldTrip,
      'DiomanBreaker.keyBuilder': v.keyBuilder,
      'DiomanBreaker.idleTtl': v.idleTtl,
      'DiomanBreaker.maxBuckets': v.maxBuckets,
      'DiomanBreaker.clock': v.clock,
      'DiomanBreaker.onStateChange': v.onStateChange,
      'DiomanBreaker.name': v.name,
      'DiomanBreaker.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanAuthOptions'] is DiomanAuthOptions) {
    final v = values['DiomanAuthOptions'] as DiomanAuthOptions;
    final snapshot = <String, Object?>{
      'DiomanAuthOptions.enabled': v.enabled,
      'DiomanAuthOptions.onAccessDenied': v.onAccessDenied,
      'DiomanAuthOptions.onAccessExpired': v.onAccessExpired,
      'DiomanAuthOptions.onFailure': v.onFailure,
      'DiomanAuthOptions.isProtected': v.isProtected,
      'DiomanAuthOptions.ready': v.ready,
      'DiomanAuthOptions.expiresAt': v.expiresAt,
      'DiomanAuthOptions.refreshLeeway': v.refreshLeeway,
      'DiomanAuthOptions.refreshTimeout': v.refreshTimeout,
      'DiomanAuthOptions.headerKey': v.headerKey,
      'DiomanAuthOptions.buildHeader': v.buildHeader,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanAuth.readyStableAttempts', DiomanAuth.readyStableAttempts);
  e.read('DiomanAuth.pluginName', DiomanAuth.pluginName);
  e.read('DiomanAuth.option', DiomanAuth.option);
  e.read('DiomanAuth.injectedToken', DiomanAuth.injectedToken);
  if (values['DiomanAuth'] is DiomanAuth) {
    final v = values['DiomanAuth'] as DiomanAuth;
    final snapshot = <String, Object?>{
      'DiomanAuth.tokenManager': v.tokenManager,
      'DiomanAuth.onRefresh': v.onRefresh,
      'DiomanAuth.enabled': v.enabled,
      'DiomanAuth.onAccessDenied': v.onAccessDenied,
      'DiomanAuth.onAccessExpired': v.onAccessExpired,
      'DiomanAuth.onFailure': v.onFailure,
      'DiomanAuth.isProtected': v.isProtected,
      'DiomanAuth.ready': v.ready,
      'DiomanAuth.expiresAt': v.expiresAt,
      'DiomanAuth.refreshLeeway': v.refreshLeeway,
      'DiomanAuth.refreshTimeout': v.refreshTimeout,
      'DiomanAuth.headerKey': v.headerKey,
      'DiomanAuth.buildHeader': v.buildHeader,
      'DiomanAuth.name': v.name,
      'DiomanAuth.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanTokenManager'] is DiomanTokenManager) {
    final v = values['DiomanTokenManager'] as DiomanTokenManager;
    final snapshot = <String, Object?>{
      'DiomanTokenManager.accessToken': v.accessToken,
      'DiomanTokenManager.refreshToken': v.refreshToken,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanMockOptions'] is DiomanMockOptions) {
    final v = values['DiomanMockOptions'] as DiomanMockOptions;
    final snapshot = <String, Object?>{
      'DiomanMockOptions.enabled': v.enabled,
      'DiomanMockOptions.routes': v.routes,
      'DiomanMockOptions.mockUrl': v.mockUrl,
      'DiomanMockOptions.fallbackWhen': v.fallbackWhen,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanMock.pluginName', DiomanMock.pluginName);
  e.read('DiomanMock.option', DiomanMock.option);
  if (values['DiomanMock'] is DiomanMock) {
    final v = values['DiomanMock'] as DiomanMock;
    final snapshot = <String, Object?>{
      'DiomanMock.enabled': v.enabled,
      'DiomanMock.routes': v.routes,
      'DiomanMock.mockUrl': v.mockUrl,
      'DiomanMock.fallbackWhen': v.fallbackWhen,
      'DiomanMock.name': v.name,
      'DiomanMock.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanShareOptions'] is DiomanShareOptions) {
    final v = values['DiomanShareOptions'] as DiomanShareOptions;
    final snapshot = <String, Object?>{
      'DiomanShareOptions.enabled': v.enabled,
      'DiomanShareOptions.policy': v.policy,
      'DiomanShareOptions.retries': v.retries,
      'DiomanShareOptions.interval': v.interval,
      'DiomanShareOptions.methods': v.methods,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanShare.pluginName', DiomanShare.pluginName);
  e.read('DiomanShare.option', DiomanShare.option);
  if (values['DiomanShare'] is DiomanShare) {
    final v = values['DiomanShare'] as DiomanShare;
    final snapshot = <String, Object?>{
      'DiomanShare.policy': v.policy,
      'DiomanShare.retries': v.retries,
      'DiomanShare.interval': v.interval,
      'DiomanShare.methods': v.methods,
      'DiomanShare.enabled': v.enabled,
      'DiomanShare.name': v.name,
      'DiomanShare.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanCacheOptions'] is DiomanCacheOptions) {
    final v = values['DiomanCacheOptions'] as DiomanCacheOptions;
    final snapshot = <String, Object?>{
      'DiomanCacheOptions.enabled': v.enabled,
      'DiomanCacheOptions.expires': v.expires,
      'DiomanCacheOptions.clone': v.clone,
      'DiomanCacheOptions.shouldCache': v.shouldCache,
      'DiomanCacheOptions.shouldStore': v.shouldStore,
      'DiomanCacheOptions.cachePolicy': v.cachePolicy,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read('DiomanCache.pluginName', DiomanCache.pluginName);
  e.read('DiomanCache.option', DiomanCache.option);
  if (values['DiomanCache'] is DiomanCache) {
    final v = values['DiomanCache'] as DiomanCache;
    final snapshot = <String, Object?>{
      'DiomanCache.maxEntries': v.maxEntries,
      'DiomanCache.persist': v.persist,
      'DiomanCache.cachePolicy': v.cachePolicy,
      'DiomanCache.expires': v.expires,
      'DiomanCache.clone': v.clone,
      'DiomanCache.shouldCache': v.shouldCache,
      'DiomanCache.shouldStore': v.shouldStore,
      'DiomanCache.clock': v.clock,
      'DiomanCache.enabled': v.enabled,
      'DiomanCache.name': v.name,
      'DiomanCache.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanOfflineOptions'] is DiomanOfflineOptions) {
    final v = values['DiomanOfflineOptions'] as DiomanOfflineOptions;
    final snapshot = <String, Object?>{
      'DiomanOfflineOptions.enabled': v.enabled,
      'DiomanOfflineOptions.shouldQueue': v.shouldQueue,
      'DiomanOfflineOptions.maxQueueSize': v.maxQueueSize,
      'DiomanOfflineOptions.maxWait': v.maxWait,
    };
    e.mark(snapshot.keys, 'property read');
  }
  if (values['DiomanOfflineApi'] is DiomanOfflineApi) {
    final v = values['DiomanOfflineApi'] as DiomanOfflineApi;
    final snapshot = <String, Object?>{
      'DiomanOfflineApi.pending': v.pending,
    };
    e.mark(snapshot.keys, 'property read');
  }
  e.read(
      'DiomanOffline.defaultMaxQueueSize', DiomanOffline.defaultMaxQueueSize);
  e.read('DiomanOffline.pluginName', DiomanOffline.pluginName);
  e.read('DiomanOffline.option', DiomanOffline.option);
  if (values['DiomanOffline'] is DiomanOffline) {
    final v = values['DiomanOffline'] as DiomanOffline;
    final snapshot = <String, Object?>{
      'DiomanOffline.isOnline': v.isOnline,
      'DiomanOffline.onConnectivityChanged': v.onConnectivityChanged,
      'DiomanOffline.shouldQueue': v.shouldQueue,
      'DiomanOffline.maxQueueSize': v.maxQueueSize,
      'DiomanOffline.maxWait': v.maxWait,
      'DiomanOffline.enabled': v.enabled,
      'DiomanOffline.name': v.name,
      'DiomanOffline.stage': v.stage,
    };
    e.mark(snapshot.keys, 'property read');
  }
}
