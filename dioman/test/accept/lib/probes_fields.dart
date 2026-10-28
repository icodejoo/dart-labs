part of 'probes.dart';

/// generatedInspect 的测试辅助入口。
/// 自动生成的逐属性读取检查器，由 inventory.dart 更新。
void generatedInspect(ApiEvidence e, Map<String, Object> values) {
  if (values[tkDiomanPlugin] is DiomanPlugin) {
    final v = values[tkDiomanPlugin] as DiomanPlugin;
    final snapshot = <String, Object?>{
      tkDiomanPluginName: v.name,
      tkDiomanPluginOrdering: v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanHandle] is DiomanHandle) {
    final v = values[tkDiomanHandle] as DiomanHandle;
    final snapshot = <String, Object?>{
      tkDiomanHandlePlugins: v.plugins,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanExtraKey] is DiomanExtraKey) {
    final v = values[tkDiomanExtraKey] as DiomanExtraKey;
    final snapshot = <String, Object?>{
      'DiomanExtraKey.key': v.key,
      'DiomanExtraKey.owner': v.owner,
      'DiomanExtraKey.kind': v.kind,
      'DiomanExtraKey.valueType': v.valueType,
      'DiomanExtraKey.description': v.description,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanSharedStateKey] is DiomanSharedStateKey) {
    final v = values[tkDiomanSharedStateKey] as DiomanSharedStateKey;
    final snapshot = <String, Object?>{
      'DiomanSharedStateKey.key': v.key,
      'DiomanSharedStateKey.count': v.count,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read(tkDiomanExtraKeysBuiltIn, DiomanExtraKeys.builtIn);
  e.read(tkDiomanExtraKeysAll, DiomanExtraKeys.all);
  e.read('DiomanPluginOrder.none', DiomanPluginOrder.none);
  if (values[tkDiomanPluginOrder] is DiomanPluginOrder) {
    final v = values[tkDiomanPluginOrder] as DiomanPluginOrder;
    final snapshot = <String, Object?>{
      'DiomanPluginOrder.before': v.before,
      'DiomanPluginOrder.after': v.after,
      'DiomanPluginOrder.requires': v.requires,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanPluginOrderException] is DiomanPluginOrderException) {
    final v =
        values[tkDiomanPluginOrderException] as DiomanPluginOrderException;
    final snapshot = <String, Object?>{
      'DiomanPluginOrderException.issue': v.issue,
      'DiomanPluginOrderException.plugins': v.plugins,
      'DiomanPluginOrderException.message': v.message,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanEnvsOptions] is DiomanEnvsOptions) {
    final v = values[tkDiomanEnvsOptions] as DiomanEnvsOptions;
    final snapshot = <String, Object?>{
      'DiomanEnvsOptions.enabled': v.enabled,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkEnvRule] is EnvRule) {
    final v = values[tkEnvRule] as EnvRule;
    final snapshot = <String, Object?>{
      'EnvRule.rule': v.rule,
      'EnvRule.config': v.config,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanEnvs.pluginName', DiomanEnvs.pluginName);
  if (values[tkDiomanEnvs] is DiomanEnvs) {
    final v = values[tkDiomanEnvs] as DiomanEnvs;
    final snapshot = <String, Object?>{
      'DiomanEnvs.rules': v.rules,
      'DiomanEnvs.config': v.config,
      'DiomanEnvs.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanTimeouts] is DiomanTimeouts) {
    final v = values[tkDiomanTimeouts] as DiomanTimeouts;
    final snapshot = <String, Object?>{
      'DiomanTimeouts.connect': v.connect,
      'DiomanTimeouts.receive': v.receive,
      'DiomanTimeouts.send': v.send,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanTimeoutOptions] is DiomanTimeoutOptions) {
    final v = values[tkDiomanTimeoutOptions] as DiomanTimeoutOptions;
    final snapshot = <String, Object?>{
      'DiomanTimeoutOptions.enabled': v.enabled,
      'DiomanTimeoutOptions.timeouts': v.timeouts,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanTimeout.pluginName', DiomanTimeout.pluginName);
  if (values[tkDiomanTimeout] is DiomanTimeout) {
    final v = values[tkDiomanTimeout] as DiomanTimeout;
    final snapshot = <String, Object?>{
      'DiomanTimeout.timeouts': v.timeouts,
      'DiomanTimeout.enabled': v.enabled,
      'DiomanTimeout.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanRepathOptions] is DiomanRepathOptions) {
    final v = values[tkDiomanRepathOptions] as DiomanRepathOptions;
    final snapshot = <String, Object?>{
      'DiomanRepathOptions.enabled': v.enabled,
      'DiomanRepathOptions.removeKey': v.removeKey,
      'DiomanRepathOptions.pattern': v.pattern,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanRepath.pluginName', DiomanRepath.pluginName);
  if (values[tkDiomanRepath] is DiomanRepath) {
    final v = values[tkDiomanRepath] as DiomanRepath;
    final snapshot = <String, Object?>{
      'DiomanRepath.removeKey': v.removeKey,
      'DiomanRepath.enabled': v.enabled,
      'DiomanRepath.pattern': v.pattern,
      'DiomanRepath.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanFilterOptions] is DiomanFilterOptions) {
    final v = values[tkDiomanFilterOptions] as DiomanFilterOptions;
    final snapshot = <String, Object?>{
      'DiomanFilterOptions.enabled': v.enabled,
      'DiomanFilterOptions.ignoreKeys': v.ignoreKeys,
      'DiomanFilterOptions.ignoreValues': v.ignoreValues,
      'DiomanFilterOptions.predicate': v.predicate,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanFilter.pluginName', DiomanFilter.pluginName);
  if (values[tkDiomanFilter] is DiomanFilter) {
    final v = values[tkDiomanFilter] as DiomanFilter;
    final snapshot = <String, Object?>{
      'DiomanFilter.predicate': v.predicate,
      'DiomanFilter.ignoreKeys': v.ignoreKeys,
      'DiomanFilter.ignoreValues': v.ignoreValues,
      'DiomanFilter.enabled': v.enabled,
      'DiomanFilter.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanKeyOptions] is DiomanKeyOptions) {
    final v = values[tkDiomanKeyOptions] as DiomanKeyOptions;
    final snapshot = <String, Object?>{
      'DiomanKeyOptions.enabled': v.enabled,
      'DiomanKeyOptions.key': v.key,
      'DiomanKeyOptions.fastMode': v.fastMode,
      'DiomanKeyOptions.ignores': v.ignores,
      'DiomanKeyOptions.builder': v.builder,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanKey.pluginName', DiomanKey.pluginName);
  if (values[tkDiomanKey] is DiomanKey) {
    final v = values[tkDiomanKey] as DiomanKey;
    final snapshot = <String, Object?>{
      'DiomanKey.fastMode': v.fastMode,
      'DiomanKey.ignores': v.ignores,
      'DiomanKey.enabled': v.enabled,
      'DiomanKey.builder': v.builder,
      'DiomanKey.namespace': v.namespace,
      'DiomanKey.name': v.name,
      'DiomanKey.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanNormalizeOptions] is DiomanNormalizeOptions) {
    final v = values[tkDiomanNormalizeOptions] as DiomanNormalizeOptions;
    final snapshot = <String, Object?>{
      'DiomanNormalizeOptions.enabled': v.enabled,
      'DiomanNormalizeOptions.dataKey': v.dataKey,
      'DiomanNormalizeOptions.codeKey': v.codeKey,
      'DiomanNormalizeOptions.messageKey': v.messageKey,
      'DiomanNormalizeOptions.isSuccess': v.isSuccess,
      'DiomanNormalizeOptions.shouldNormalize': v.shouldNormalize,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanException] is DiomanException) {
    final v = values[tkDiomanException] as DiomanException;
    final snapshot = <String, Object?>{
      'DiomanException.code': v.code,
      'DiomanException.message': v.message,
      'DiomanException.data': v.data,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanNormalize.pluginName', DiomanNormalize.pluginName);
  if (values[tkDiomanNormalize] is DiomanNormalize) {
    final v = values[tkDiomanNormalize] as DiomanNormalize;
    final snapshot = <String, Object?>{
      'DiomanNormalize.dataKey': v.dataKey,
      'DiomanNormalize.codeKey': v.codeKey,
      'DiomanNormalize.messageKey': v.messageKey,
      'DiomanNormalize.enabled': v.enabled,
      'DiomanNormalize.isSuccess': v.isSuccess,
      'DiomanNormalize.shouldNormalize': v.shouldNormalize,
      'DiomanNormalize.name': v.name,
      'DiomanNormalize.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanCacheOptions] is DiomanCacheOptions) {
    final v = values[tkDiomanCacheOptions] as DiomanCacheOptions;
    final snapshot = <String, Object?>{
      'DiomanCacheOptions.enabled': v.enabled,
      'DiomanCacheOptions.expires': v.expires,
      'DiomanCacheOptions.clone': v.clone,
      'DiomanCacheOptions.maxEntries': v.maxEntries,
      'DiomanCacheOptions.shouldCache': v.shouldCache,
      'DiomanCacheOptions.now': v.now,
      'DiomanCacheOptions.cachePolicy': v.cachePolicy,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanCache.pluginName', DiomanCache.pluginName);
  if (values[tkDiomanCache] is DiomanCache) {
    final v = values[tkDiomanCache] as DiomanCache;
    final snapshot = <String, Object?>{
      'DiomanCache.persist': v.persist,
      'DiomanCache.cachePolicy': v.cachePolicy,
      'DiomanCache.enabled': v.enabled,
      'DiomanCache.expires': v.expires,
      'DiomanCache.clone': v.clone,
      'DiomanCache.maxEntries': v.maxEntries,
      'DiomanCache.name': v.name,
      'DiomanCache.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanOfflineException] is DiomanOfflineException) {
    final v = values[tkDiomanOfflineException] as DiomanOfflineException;
    final snapshot = <String, Object?>{
      'DiomanOfflineException.reason': v.reason,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanOfflineOptions] is DiomanOfflineOptions) {
    final v = values[tkDiomanOfflineOptions] as DiomanOfflineOptions;
    final snapshot = <String, Object?>{
      'DiomanOfflineOptions.enabled': v.enabled,
      'DiomanOfflineOptions.shouldQueue': v.shouldQueue,
      'DiomanOfflineOptions.maxQueueSize': v.maxQueueSize,
      'DiomanOfflineOptions.maxWait': v.maxWait,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanOffline.pluginName', DiomanOffline.pluginName);
  if (values[tkDiomanOffline] is DiomanOffline) {
    final v = values[tkDiomanOffline] as DiomanOffline;
    final snapshot = <String, Object?>{
      'DiomanOffline.maxQueueSize': v.maxQueueSize,
      'DiomanOffline.maxWait': v.maxWait,
      'DiomanOffline.enabled': v.enabled,
      'DiomanOffline.name': v.name,
      'DiomanOffline.ordering': v.ordering,
      tkDiomanOfflinePending: v.pending,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanShareOptions] is DiomanShareOptions) {
    final v = values[tkDiomanShareOptions] as DiomanShareOptions;
    final snapshot = <String, Object?>{
      'DiomanShareOptions.enabled': v.enabled,
      'DiomanShareOptions.policy': v.policy,
      'DiomanShareOptions.retries': v.retries,
      'DiomanShareOptions.interval': v.interval,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanShare.pluginName', DiomanShare.pluginName);
  if (values[tkDiomanShare] is DiomanShare) {
    final v = values[tkDiomanShare] as DiomanShare;
    final snapshot = <String, Object?>{
      'DiomanShare.enabled': v.enabled,
      'DiomanShare.policy': v.policy,
      'DiomanShare.retries': v.retries,
      'DiomanShare.interval': v.interval,
      tkDiomanShareHasMultipleDownstreamSettlers:
          v.hasMultipleDownstreamSettlers,
      'DiomanShare.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanMockOptions] is DiomanMockOptions) {
    final v = values[tkDiomanMockOptions] as DiomanMockOptions;
    final snapshot = <String, Object?>{
      'DiomanMockOptions.enabled': v.enabled,
      'DiomanMockOptions.mockUrl': v.mockUrl,
      'DiomanMockOptions.routes': v.routes,
      'DiomanMockOptions.fallbackWhen': v.fallbackWhen,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanMock.pluginName', DiomanMock.pluginName);
  if (values[tkDiomanMock] is DiomanMock) {
    final v = values[tkDiomanMock] as DiomanMock;
    final snapshot = <String, Object?>{
      'DiomanMock.enabled': v.enabled,
      'DiomanMock.mockUrl': v.mockUrl,
      'DiomanMock.fallbackWhen': v.fallbackWhen,
      'DiomanMock.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanCancelOptions] is DiomanCancelOptions) {
    final v = values[tkDiomanCancelOptions] as DiomanCancelOptions;
    final snapshot = <String, Object?>{
      'DiomanCancelOptions.enabled': v.enabled,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanCancel.pluginName', DiomanCancel.pluginName);
  if (values[tkDiomanCancel] is DiomanCancel) {
    final v = values[tkDiomanCancel] as DiomanCancel;
    final snapshot = <String, Object?>{
      'DiomanCancel.config': v.config,
      'DiomanCancel.name': v.name,
      'DiomanCancel.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanLoadingOptions] is DiomanLoadingOptions) {
    final v = values[tkDiomanLoadingOptions] as DiomanLoadingOptions;
    final snapshot = <String, Object?>{
      'DiomanLoadingOptions.enabled': v.enabled,
      'DiomanLoadingOptions.onChanged': v.onChanged,
      'DiomanLoadingOptions.delay': v.delay,
      'DiomanLoadingOptions.delayClose': v.delayClose,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanLoading.pluginName', DiomanLoading.pluginName);
  if (values[tkDiomanLoading] is DiomanLoading) {
    final v = values[tkDiomanLoading] as DiomanLoading;
    final snapshot = <String, Object?>{
      'DiomanLoading.enabled': v.enabled,
      'DiomanLoading.delay': v.delay,
      'DiomanLoading.delayClose': v.delayClose,
      tkDiomanLoadingActiveCount: v.activeCount,
      'DiomanLoading.name': v.name,
      'DiomanLoading.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanTokenManager] is DiomanTokenManager) {
    final v = values[tkDiomanTokenManager] as DiomanTokenManager;
    final snapshot = <String, Object?>{
      tkDiomanTokenManagerAccessToken: v.accessToken,
      tkDiomanTokenManagerRefreshToken: v.refreshToken,
      tkDiomanTokenManagerCanRefresh: v.canRefresh,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanAuthOptions] is DiomanAuthOptions) {
    final v = values[tkDiomanAuthOptions] as DiomanAuthOptions;
    final snapshot = <String, Object?>{
      'DiomanAuthOptions.enabled': v.enabled,
      'DiomanAuthOptions.onAccessDenied': v.onAccessDenied,
      'DiomanAuthOptions.onAccessExpired': v.onAccessExpired,
      'DiomanAuthOptions.onFailure': v.onFailure,
      'DiomanAuthOptions.ready': v.ready,
      'DiomanAuthOptions.isProtected': v.isProtected,
      'DiomanAuthOptions.expiresAt': v.expiresAt,
      'DiomanAuthOptions.refreshLeeway': v.refreshLeeway,
      'DiomanAuthOptions.now': v.now,
      'DiomanAuthOptions.headerKey': v.headerKey,
      'DiomanAuthOptions.buildHeader': v.buildHeader,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanAuth.pluginName', DiomanAuth.pluginName);
  if (values[tkDiomanAuth] is DiomanAuth) {
    final v = values[tkDiomanAuth] as DiomanAuth;
    final snapshot = <String, Object?>{
      'DiomanAuth.enabled': v.enabled,
      'DiomanAuth.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanRetryOptions] is DiomanRetryOptions) {
    final v = values[tkDiomanRetryOptions] as DiomanRetryOptions;
    final snapshot = <String, Object?>{
      'DiomanRetryOptions.enabled': v.enabled,
      'DiomanRetryOptions.max': v.max,
      'DiomanRetryOptions.methods': v.methods,
      'DiomanRetryOptions.shouldRetry': v.shouldRetry,
      'DiomanRetryOptions.statusCodes': v.statusCodes,
      'DiomanRetryOptions.delay': v.delay,
      'DiomanRetryOptions.jitter': v.jitter,
      'DiomanRetryOptions.delayMax': v.delayMax,
      'DiomanRetryOptions.respectRetryAfter': v.respectRetryAfter,
      'DiomanRetryOptions.afterStatusCodes': v.afterStatusCodes,
      'DiomanRetryOptions.retryAfterMax': v.retryAfterMax,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanRetry.pluginName', DiomanRetry.pluginName);
  if (values[tkDiomanRetry] is DiomanRetry) {
    final v = values[tkDiomanRetry] as DiomanRetry;
    final snapshot = <String, Object?>{
      'DiomanRetry.onRetry': v.onRetry,
      'DiomanRetry.enabled': v.enabled,
      'DiomanRetry.max': v.max,
      'DiomanRetry.methods': v.methods,
      'DiomanRetry.shouldRetry': v.shouldRetry,
      'DiomanRetry.statusCodes': v.statusCodes,
      'DiomanRetry.delay': v.delay,
      'DiomanRetry.jitter': v.jitter,
      'DiomanRetry.delayMax': v.delayMax,
      'DiomanRetry.respectRetryAfter': v.respectRetryAfter,
      'DiomanRetry.afterStatusCodes': v.afterStatusCodes,
      'DiomanRetry.retryAfterMax': v.retryAfterMax,
      'DiomanRetry.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanBreakerOpenException] is DiomanBreakerOpenException) {
    final v =
        values[tkDiomanBreakerOpenException] as DiomanBreakerOpenException;
    final snapshot = <String, Object?>{
      'DiomanBreakerOpenException.bucketKey': v.bucketKey,
      'DiomanBreakerOpenException.retryableAt': v.retryableAt,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanBreakerOptions] is DiomanBreakerOptions) {
    final v = values[tkDiomanBreakerOptions] as DiomanBreakerOptions;
    final snapshot = <String, Object?>{
      'DiomanBreakerOptions.enabled': v.enabled,
      'DiomanBreakerOptions.failureThreshold': v.failureThreshold,
      'DiomanBreakerOptions.resetDuration': v.resetDuration,
      'DiomanBreakerOptions.halfOpenMaxCalls': v.halfOpenMaxCalls,
      'DiomanBreakerOptions.shouldTrip': v.shouldTrip,
      'DiomanBreakerOptions.keyBuilder': v.keyBuilder,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanBreaker.defaultIdleTtl', DiomanBreaker.defaultIdleTtl);
  e.read('DiomanBreaker.defaultMaxBuckets', DiomanBreaker.defaultMaxBuckets);
  e.read('DiomanBreaker.pluginName', DiomanBreaker.pluginName);
  if (values[tkDiomanBreaker] is DiomanBreaker) {
    final v = values[tkDiomanBreaker] as DiomanBreaker;
    final snapshot = <String, Object?>{
      'DiomanBreaker.idleTtl': v.idleTtl,
      'DiomanBreaker.maxBuckets': v.maxBuckets,
      tkDiomanBreakerBucketCount: v.bucketCount,
      'DiomanBreaker.failureThreshold': v.failureThreshold,
      'DiomanBreaker.resetDuration': v.resetDuration,
      'DiomanBreaker.halfOpenMaxCalls': v.halfOpenMaxCalls,
      'DiomanBreaker.shouldTrip': v.shouldTrip,
      'DiomanBreaker.keyBuilder': v.keyBuilder,
      'DiomanBreaker.onStateChange': v.onStateChange,
      'DiomanBreaker.enabled': v.enabled,
      'DiomanBreaker.name': v.name,
      'DiomanBreaker.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  if (values[tkDiomanLogOptions] is DiomanLogOptions) {
    final v = values[tkDiomanLogOptions] as DiomanLogOptions;
    final snapshot = <String, Object?>{
      'DiomanLogOptions.enabled': v.enabled,
      'DiomanLogOptions.logRequest': v.logRequest,
      'DiomanLogOptions.logResponse': v.logResponse,
      'DiomanLogOptions.logError': v.logError,
      'DiomanLogOptions.logHeaders': v.logHeaders,
      'DiomanLogOptions.logBody': v.logBody,
      'DiomanLogOptions.maxBodyLength': v.maxBodyLength,
      'DiomanLogOptions.writer': v.writer,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanLog.pluginName', DiomanLog.pluginName);
  if (values[tkDiomanLog] is DiomanLog) {
    final v = values[tkDiomanLog] as DiomanLog;
    final snapshot = <String, Object?>{
      'DiomanLog.logRequest': v.logRequest,
      'DiomanLog.logResponse': v.logResponse,
      'DiomanLog.logError': v.logError,
      'DiomanLog.logHeaders': v.logHeaders,
      'DiomanLog.logBody': v.logBody,
      'DiomanLog.enabled': v.enabled,
      'DiomanLog.maxBodyLength': v.maxBodyLength,
      'DiomanLog.writer': v.writer,
      'DiomanLog.name': v.name,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
  e.read('DiomanNotify.pluginName', DiomanNotify.pluginName);
  if (values[tkDiomanNotify] is DiomanNotify) {
    final v = values[tkDiomanNotify] as DiomanNotify;
    final snapshot = <String, Object?>{
      'DiomanNotify.notify': v.notify,
      'DiomanNotify.stringify': v.stringify,
      'DiomanNotify.name': v.name,
      'DiomanNotify.ordering': v.ordering,
    };
    e.mark(snapshot.keys, tkPropertyRead);
  }
}
