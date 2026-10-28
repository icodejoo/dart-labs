part of 'probes.dart';

/// 自动生成的逐属性读取检查器，由 inventory.dart 更新。
void generatedInspect(ApiEvidence e, Map<String,Object> values) {
  if (values['DiomanPlugin'] is DiomanPlugin) {
    final v = values['DiomanPlugin'] as DiomanPlugin;
    final snapshot = <String,Object?>{
      'DiomanPlugin.name':v.name,
      'DiomanPlugin.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanHandle'] is DiomanHandle) {
    final v = values['DiomanHandle'] as DiomanHandle;
    final snapshot = <String,Object?>{
      'DiomanHandle.plugins':v.plugins,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanExtraKey'] is DiomanExtraKey) {
    final v = values['DiomanExtraKey'] as DiomanExtraKey;
    final snapshot = <String,Object?>{
      'DiomanExtraKey.key':v.key,
      'DiomanExtraKey.owner':v.owner,
      'DiomanExtraKey.kind':v.kind,
      'DiomanExtraKey.valueType':v.valueType,
      'DiomanExtraKey.description':v.description,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanSharedStateKey'] is DiomanSharedStateKey) {
    final v = values['DiomanSharedStateKey'] as DiomanSharedStateKey;
    final snapshot = <String,Object?>{
      'DiomanSharedStateKey.key':v.key,
      'DiomanSharedStateKey.count':v.count,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanExtraKeys.mockAdapterOwner', DiomanExtraKeys.mockAdapterOwner);
  e.read('DiomanExtraKeys.builtIn', DiomanExtraKeys.builtIn);
  e.read('DiomanExtraKeys.all', DiomanExtraKeys.all);
  e.read('DiomanPluginOrder.none', DiomanPluginOrder.none);
  if (values['DiomanPluginOrder'] is DiomanPluginOrder) {
    final v = values['DiomanPluginOrder'] as DiomanPluginOrder;
    final snapshot = <String,Object?>{
      'DiomanPluginOrder.before':v.before,
      'DiomanPluginOrder.after':v.after,
      'DiomanPluginOrder.requires':v.requires,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanPluginOrderException'] is DiomanPluginOrderException) {
    final v = values['DiomanPluginOrderException'] as DiomanPluginOrderException;
    final snapshot = <String,Object?>{
      'DiomanPluginOrderException.issue':v.issue,
      'DiomanPluginOrderException.plugins':v.plugins,
      'DiomanPluginOrderException.message':v.message,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanEnvsOptions'] is DiomanEnvsOptions) {
    final v = values['DiomanEnvsOptions'] as DiomanEnvsOptions;
    final snapshot = <String,Object?>{
      'DiomanEnvsOptions.enabled':v.enabled,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['EnvRule'] is EnvRule) {
    final v = values['EnvRule'] as EnvRule;
    final snapshot = <String,Object?>{
      'EnvRule.rule':v.rule,
      'EnvRule.config':v.config,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanEnvs.pluginName', DiomanEnvs.pluginName);
  if (values['DiomanEnvs'] is DiomanEnvs) {
    final v = values['DiomanEnvs'] as DiomanEnvs;
    final snapshot = <String,Object?>{
      'DiomanEnvs.rules':v.rules,
      'DiomanEnvs.config':v.config,
      'DiomanEnvs.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanTimeouts'] is DiomanTimeouts) {
    final v = values['DiomanTimeouts'] as DiomanTimeouts;
    final snapshot = <String,Object?>{
      'DiomanTimeouts.connect':v.connect,
      'DiomanTimeouts.receive':v.receive,
      'DiomanTimeouts.send':v.send,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanTimeoutOptions'] is DiomanTimeoutOptions) {
    final v = values['DiomanTimeoutOptions'] as DiomanTimeoutOptions;
    final snapshot = <String,Object?>{
      'DiomanTimeoutOptions.enabled':v.enabled,
      'DiomanTimeoutOptions.timeouts':v.timeouts,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanTimeout.pluginName', DiomanTimeout.pluginName);
  if (values['DiomanTimeout'] is DiomanTimeout) {
    final v = values['DiomanTimeout'] as DiomanTimeout;
    final snapshot = <String,Object?>{
      'DiomanTimeout.timeouts':v.timeouts,
      'DiomanTimeout.enabled':v.enabled,
      'DiomanTimeout.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanRepathOptions'] is DiomanRepathOptions) {
    final v = values['DiomanRepathOptions'] as DiomanRepathOptions;
    final snapshot = <String,Object?>{
      'DiomanRepathOptions.enabled':v.enabled,
      'DiomanRepathOptions.removeKey':v.removeKey,
      'DiomanRepathOptions.pattern':v.pattern,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanRepath.pluginName', DiomanRepath.pluginName);
  if (values['DiomanRepath'] is DiomanRepath) {
    final v = values['DiomanRepath'] as DiomanRepath;
    final snapshot = <String,Object?>{
      'DiomanRepath.removeKey':v.removeKey,
      'DiomanRepath.enabled':v.enabled,
      'DiomanRepath.pattern':v.pattern,
      'DiomanRepath.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanFilterOptions'] is DiomanFilterOptions) {
    final v = values['DiomanFilterOptions'] as DiomanFilterOptions;
    final snapshot = <String,Object?>{
      'DiomanFilterOptions.enabled':v.enabled,
      'DiomanFilterOptions.ignoreKeys':v.ignoreKeys,
      'DiomanFilterOptions.ignoreValues':v.ignoreValues,
      'DiomanFilterOptions.predicate':v.predicate,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanFilter.pluginName', DiomanFilter.pluginName);
  if (values['DiomanFilter'] is DiomanFilter) {
    final v = values['DiomanFilter'] as DiomanFilter;
    final snapshot = <String,Object?>{
      'DiomanFilter.predicate':v.predicate,
      'DiomanFilter.ignoreKeys':v.ignoreKeys,
      'DiomanFilter.ignoreValues':v.ignoreValues,
      'DiomanFilter.enabled':v.enabled,
      'DiomanFilter.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanKeyOptions'] is DiomanKeyOptions) {
    final v = values['DiomanKeyOptions'] as DiomanKeyOptions;
    final snapshot = <String,Object?>{
      'DiomanKeyOptions.enabled':v.enabled,
      'DiomanKeyOptions.key':v.key,
      'DiomanKeyOptions.fastMode':v.fastMode,
      'DiomanKeyOptions.ignores':v.ignores,
      'DiomanKeyOptions.builder':v.builder,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanKey.pluginName', DiomanKey.pluginName);
  if (values['DiomanKey'] is DiomanKey) {
    final v = values['DiomanKey'] as DiomanKey;
    final snapshot = <String,Object?>{
      'DiomanKey.fastMode':v.fastMode,
      'DiomanKey.ignores':v.ignores,
      'DiomanKey.enabled':v.enabled,
      'DiomanKey.builder':v.builder,
      'DiomanKey.namespace':v.namespace,
      'DiomanKey.name':v.name,
      'DiomanKey.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanNormalizeOptions'] is DiomanNormalizeOptions) {
    final v = values['DiomanNormalizeOptions'] as DiomanNormalizeOptions;
    final snapshot = <String,Object?>{
      'DiomanNormalizeOptions.enabled':v.enabled,
      'DiomanNormalizeOptions.dataKey':v.dataKey,
      'DiomanNormalizeOptions.codeKey':v.codeKey,
      'DiomanNormalizeOptions.messageKey':v.messageKey,
      'DiomanNormalizeOptions.isSuccess':v.isSuccess,
      'DiomanNormalizeOptions.shouldNormalize':v.shouldNormalize,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanException'] is DiomanException) {
    final v = values['DiomanException'] as DiomanException;
    final snapshot = <String,Object?>{
      'DiomanException.code':v.code,
      'DiomanException.message':v.message,
      'DiomanException.data':v.data,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanNormalize.pluginName', DiomanNormalize.pluginName);
  if (values['DiomanNormalize'] is DiomanNormalize) {
    final v = values['DiomanNormalize'] as DiomanNormalize;
    final snapshot = <String,Object?>{
      'DiomanNormalize.dataKey':v.dataKey,
      'DiomanNormalize.codeKey':v.codeKey,
      'DiomanNormalize.messageKey':v.messageKey,
      'DiomanNormalize.enabled':v.enabled,
      'DiomanNormalize.isSuccess':v.isSuccess,
      'DiomanNormalize.shouldNormalize':v.shouldNormalize,
      'DiomanNormalize.name':v.name,
      'DiomanNormalize.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanCacheOptions'] is DiomanCacheOptions) {
    final v = values['DiomanCacheOptions'] as DiomanCacheOptions;
    final snapshot = <String,Object?>{
      'DiomanCacheOptions.enabled':v.enabled,
      'DiomanCacheOptions.expires':v.expires,
      'DiomanCacheOptions.clone':v.clone,
      'DiomanCacheOptions.maxEntries':v.maxEntries,
      'DiomanCacheOptions.shouldCache':v.shouldCache,
      'DiomanCacheOptions.shouldStore':v.shouldStore,
      'DiomanCacheOptions.now':v.now,
      'DiomanCacheOptions.cachePolicy':v.cachePolicy,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanCache.pluginName', DiomanCache.pluginName);
  if (values['DiomanCache'] is DiomanCache) {
    final v = values['DiomanCache'] as DiomanCache;
    final snapshot = <String,Object?>{
      'DiomanCache.persist':v.persist,
      'DiomanCache.cachePolicy':v.cachePolicy,
      'DiomanCache.enabled':v.enabled,
      'DiomanCache.expires':v.expires,
      'DiomanCache.clone':v.clone,
      'DiomanCache.maxEntries':v.maxEntries,
      'DiomanCache.name':v.name,
      'DiomanCache.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanOfflineException'] is DiomanOfflineException) {
    final v = values['DiomanOfflineException'] as DiomanOfflineException;
    final snapshot = <String,Object?>{
      'DiomanOfflineException.reason':v.reason,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanOfflineOptions'] is DiomanOfflineOptions) {
    final v = values['DiomanOfflineOptions'] as DiomanOfflineOptions;
    final snapshot = <String,Object?>{
      'DiomanOfflineOptions.enabled':v.enabled,
      'DiomanOfflineOptions.shouldQueue':v.shouldQueue,
      'DiomanOfflineOptions.maxQueueSize':v.maxQueueSize,
      'DiomanOfflineOptions.maxWait':v.maxWait,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanOffline.pluginName', DiomanOffline.pluginName);
  if (values['DiomanOffline'] is DiomanOffline) {
    final v = values['DiomanOffline'] as DiomanOffline;
    final snapshot = <String,Object?>{
      'DiomanOffline.maxQueueSize':v.maxQueueSize,
      'DiomanOffline.maxWait':v.maxWait,
      'DiomanOffline.enabled':v.enabled,
      'DiomanOffline.name':v.name,
      'DiomanOffline.ordering':v.ordering,
      'DiomanOffline.pending':v.pending,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanShareOptions'] is DiomanShareOptions) {
    final v = values['DiomanShareOptions'] as DiomanShareOptions;
    final snapshot = <String,Object?>{
      'DiomanShareOptions.enabled':v.enabled,
      'DiomanShareOptions.policy':v.policy,
      'DiomanShareOptions.retries':v.retries,
      'DiomanShareOptions.interval':v.interval,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanShare.pluginName', DiomanShare.pluginName);
  if (values['DiomanShare'] is DiomanShare) {
    final v = values['DiomanShare'] as DiomanShare;
    final snapshot = <String,Object?>{
      'DiomanShare.enabled':v.enabled,
      'DiomanShare.policy':v.policy,
      'DiomanShare.retries':v.retries,
      'DiomanShare.interval':v.interval,
      'DiomanShare.hasMultipleDownstreamSettlers':v.hasMultipleDownstreamSettlers,
      'DiomanShare.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanMockOptions'] is DiomanMockOptions) {
    final v = values['DiomanMockOptions'] as DiomanMockOptions;
    final snapshot = <String,Object?>{
      'DiomanMockOptions.enabled':v.enabled,
      'DiomanMockOptions.mockUrl':v.mockUrl,
      'DiomanMockOptions.routes':v.routes,
      'DiomanMockOptions.fallbackWhen':v.fallbackWhen,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanMockAdapter.extraKey', DiomanMockAdapter.extraKey);
  e.read('DiomanMockAdapter.markerHeader', DiomanMockAdapter.markerHeader);
  if (values['DiomanCancelOptions'] is DiomanCancelOptions) {
    final v = values['DiomanCancelOptions'] as DiomanCancelOptions;
    final snapshot = <String,Object?>{
      'DiomanCancelOptions.enabled':v.enabled,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanCancel.pluginName', DiomanCancel.pluginName);
  if (values['DiomanCancel'] is DiomanCancel) {
    final v = values['DiomanCancel'] as DiomanCancel;
    final snapshot = <String,Object?>{
      'DiomanCancel.config':v.config,
      'DiomanCancel.name':v.name,
      'DiomanCancel.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanLoadingOptions'] is DiomanLoadingOptions) {
    final v = values['DiomanLoadingOptions'] as DiomanLoadingOptions;
    final snapshot = <String,Object?>{
      'DiomanLoadingOptions.enabled':v.enabled,
      'DiomanLoadingOptions.onChanged':v.onChanged,
      'DiomanLoadingOptions.delay':v.delay,
      'DiomanLoadingOptions.delayClose':v.delayClose,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanLoading.pluginName', DiomanLoading.pluginName);
  if (values['DiomanLoading'] is DiomanLoading) {
    final v = values['DiomanLoading'] as DiomanLoading;
    final snapshot = <String,Object?>{
      'DiomanLoading.enabled':v.enabled,
      'DiomanLoading.delay':v.delay,
      'DiomanLoading.delayClose':v.delayClose,
      'DiomanLoading.activeCount':v.activeCount,
      'DiomanLoading.name':v.name,
      'DiomanLoading.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanTokenManager'] is DiomanTokenManager) {
    final v = values['DiomanTokenManager'] as DiomanTokenManager;
    final snapshot = <String,Object?>{
      'DiomanTokenManager.accessToken':v.accessToken,
      'DiomanTokenManager.refreshToken':v.refreshToken,
      'DiomanTokenManager.canRefresh':v.canRefresh,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanAuthOptions'] is DiomanAuthOptions) {
    final v = values['DiomanAuthOptions'] as DiomanAuthOptions;
    final snapshot = <String,Object?>{
      'DiomanAuthOptions.enabled':v.enabled,
      'DiomanAuthOptions.onAccessDenied':v.onAccessDenied,
      'DiomanAuthOptions.onAccessExpired':v.onAccessExpired,
      'DiomanAuthOptions.onFailure':v.onFailure,
      'DiomanAuthOptions.ready':v.ready,
      'DiomanAuthOptions.isProtected':v.isProtected,
      'DiomanAuthOptions.expiresAt':v.expiresAt,
      'DiomanAuthOptions.refreshLeeway':v.refreshLeeway,
      'DiomanAuthOptions.now':v.now,
      'DiomanAuthOptions.headerKey':v.headerKey,
      'DiomanAuthOptions.buildHeader':v.buildHeader,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanAuth.pluginName', DiomanAuth.pluginName);
  if (values['DiomanAuth'] is DiomanAuth) {
    final v = values['DiomanAuth'] as DiomanAuth;
    final snapshot = <String,Object?>{
      'DiomanAuth.enabled':v.enabled,
      'DiomanAuth.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanRetryOptions'] is DiomanRetryOptions) {
    final v = values['DiomanRetryOptions'] as DiomanRetryOptions;
    final snapshot = <String,Object?>{
      'DiomanRetryOptions.enabled':v.enabled,
      'DiomanRetryOptions.max':v.max,
      'DiomanRetryOptions.methods':v.methods,
      'DiomanRetryOptions.shouldRetry':v.shouldRetry,
      'DiomanRetryOptions.statusCodes':v.statusCodes,
      'DiomanRetryOptions.delay':v.delay,
      'DiomanRetryOptions.jitter':v.jitter,
      'DiomanRetryOptions.delayMax':v.delayMax,
      'DiomanRetryOptions.respectRetryAfter':v.respectRetryAfter,
      'DiomanRetryOptions.afterStatusCodes':v.afterStatusCodes,
      'DiomanRetryOptions.retryAfterMax':v.retryAfterMax,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanRetry.pluginName', DiomanRetry.pluginName);
  if (values['DiomanRetry'] is DiomanRetry) {
    final v = values['DiomanRetry'] as DiomanRetry;
    final snapshot = <String,Object?>{
      'DiomanRetry.breaker':v.breaker,
      'DiomanRetry.onRetry':v.onRetry,
      'DiomanRetry.enabled':v.enabled,
      'DiomanRetry.max':v.max,
      'DiomanRetry.methods':v.methods,
      'DiomanRetry.shouldRetry':v.shouldRetry,
      'DiomanRetry.statusCodes':v.statusCodes,
      'DiomanRetry.delay':v.delay,
      'DiomanRetry.jitter':v.jitter,
      'DiomanRetry.delayMax':v.delayMax,
      'DiomanRetry.respectRetryAfter':v.respectRetryAfter,
      'DiomanRetry.afterStatusCodes':v.afterStatusCodes,
      'DiomanRetry.retryAfterMax':v.retryAfterMax,
      'DiomanRetry.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanBreakerOpenException'] is DiomanBreakerOpenException) {
    final v = values['DiomanBreakerOpenException'] as DiomanBreakerOpenException;
    final snapshot = <String,Object?>{
      'DiomanBreakerOpenException.bucketKey':v.bucketKey,
      'DiomanBreakerOpenException.retryableAt':v.retryableAt,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanBreakerOptions'] is DiomanBreakerOptions) {
    final v = values['DiomanBreakerOptions'] as DiomanBreakerOptions;
    final snapshot = <String,Object?>{
      'DiomanBreakerOptions.enabled':v.enabled,
      'DiomanBreakerOptions.failureThreshold':v.failureThreshold,
      'DiomanBreakerOptions.resetDuration':v.resetDuration,
      'DiomanBreakerOptions.halfOpenMaxCalls':v.halfOpenMaxCalls,
      'DiomanBreakerOptions.shouldTrip':v.shouldTrip,
      'DiomanBreakerOptions.keyBuilder':v.keyBuilder,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanBreaker.defaultIdleTtl', DiomanBreaker.defaultIdleTtl);
  e.read('DiomanBreaker.defaultMaxBuckets', DiomanBreaker.defaultMaxBuckets);
  e.read('DiomanBreaker.pluginName', DiomanBreaker.pluginName);
  if (values['DiomanBreaker'] is DiomanBreaker) {
    final v = values['DiomanBreaker'] as DiomanBreaker;
    final snapshot = <String,Object?>{
      'DiomanBreaker.idleTtl':v.idleTtl,
      'DiomanBreaker.maxBuckets':v.maxBuckets,
      'DiomanBreaker.bucketCount':v.bucketCount,
      'DiomanBreaker.failureThreshold':v.failureThreshold,
      'DiomanBreaker.resetDuration':v.resetDuration,
      'DiomanBreaker.halfOpenMaxCalls':v.halfOpenMaxCalls,
      'DiomanBreaker.shouldTrip':v.shouldTrip,
      'DiomanBreaker.keyBuilder':v.keyBuilder,
      'DiomanBreaker.onStateChange':v.onStateChange,
      'DiomanBreaker.enabled':v.enabled,
      'DiomanBreaker.name':v.name,
      'DiomanBreaker.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
  if (values['DiomanLogOptions'] is DiomanLogOptions) {
    final v = values['DiomanLogOptions'] as DiomanLogOptions;
    final snapshot = <String,Object?>{
      'DiomanLogOptions.enabled':v.enabled,
      'DiomanLogOptions.logRequest':v.logRequest,
      'DiomanLogOptions.logResponse':v.logResponse,
      'DiomanLogOptions.logError':v.logError,
      'DiomanLogOptions.logHeaders':v.logHeaders,
      'DiomanLogOptions.logBody':v.logBody,
      'DiomanLogOptions.maxBodyLength':v.maxBodyLength,
      'DiomanLogOptions.writer':v.writer,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanLog.pluginName', DiomanLog.pluginName);
  if (values['DiomanLog'] is DiomanLog) {
    final v = values['DiomanLog'] as DiomanLog;
    final snapshot = <String,Object?>{
      'DiomanLog.logRequest':v.logRequest,
      'DiomanLog.logResponse':v.logResponse,
      'DiomanLog.logError':v.logError,
      'DiomanLog.logHeaders':v.logHeaders,
      'DiomanLog.logBody':v.logBody,
      'DiomanLog.enabled':v.enabled,
      'DiomanLog.maxBodyLength':v.maxBodyLength,
      'DiomanLog.writer':v.writer,
      'DiomanLog.name':v.name,
    };
    e.mark(snapshot.keys,'property read');
  }
  e.read('DiomanNotify.pluginName', DiomanNotify.pluginName);
  if (values['DiomanNotify'] is DiomanNotify) {
    final v = values['DiomanNotify'] as DiomanNotify;
    final snapshot = <String,Object?>{
      'DiomanNotify.notify':v.notify,
      'DiomanNotify.stringify':v.stringify,
      'DiomanNotify.name':v.name,
      'DiomanNotify.ordering':v.ordering,
    };
    e.mark(snapshot.keys,'property read');
  }
}
