---
title: 测试总账矩阵缺口报告
status: active
updated: 2026-10-28
summary: 总账五道闸门的当前缺口清单与按插件分布，是补测的基线。
---

G1 已检查 lcov。

| 闸门 | 缺口数 |
|---|---:|
| G0 | 0 |
| G1 | 0 |
| G2 | 0 |
| G3 | 199 |
| G4 | 20 |
| G5 | 28 |

## 按插件汇总

| 插件 | G2 | G3 | G0 |
|---|---:|---:|---:|
| auth | 0 | 24 | 0 |
| breaker | 0 | 22 | 0 |
| cache | 0 | 9 | 0 |
| cancel | 0 | 10 | 0 |
| combo | 0 | 2 | 0 |
| envs | 0 | 8 | 0 |
| extra | 0 | 7 | 0 |
| filter | 0 | 2 | 0 |
| install | 0 | 8 | 0 |
| key | 0 | 7 | 0 |
| loading | 0 | 9 | 0 |
| log | 0 | 19 | 0 |
| mock | 0 | 7 | 0 |
| normalize | 0 | 5 | 0 |
| notify | 0 | 7 | 0 |
| offline | 0 | 10 | 0 |
| repath | 0 | 2 | 0 |
| retry | 0 | 19 | 0 |
| share | 0 | 11 | 0 |
| timeout | 0 | 11 | 0 |

## 完整缺口

<details>
<summary>G0（0）</summary>


</details>

<details>
<summary>G1（0）</summary>


</details>

<details>
<summary>G2（0）</summary>


</details>

<details>
<summary>G3（199）</summary>

- `G3:Dioman.installPlugins`
- `G3:DiomanAuth.dio`
- `G3:DiomanAuth.dio#transport-reuse`
- `G3:DiomanAuth.dispose`
- `G3:DiomanAuth.name`
- `G3:DiomanAuth.new(refreshLeeway)`
- `G3:DiomanAuth.new(tokenManager)`
- `G3:DiomanAuth.onError`
- `G3:DiomanAuth.onError#body-replay`
- `G3:DiomanAuth.onError#multipart-replay`
- `G3:DiomanAuth.onResponse`
- `G3:DiomanAuth.pluginName`
- `G3:DiomanAuthFailureAction.others`
- `G3:DiomanAuthOptions.buildHeader`
- `G3:DiomanAuthOptions.expiresAt`
- `G3:DiomanAuthOptions.headerKey`
- `G3:DiomanAuthOptions.now`
- `G3:DiomanAuthOptions.onAccessDenied`
- `G3:DiomanAuthOptions.onAccessExpired`
- `G3:DiomanAuthOptions.refreshLeeway`
- `G3:DiomanBreaker.bucketCount`
- `G3:DiomanBreaker.defaultIdleTtl`
- `G3:DiomanBreaker.defaultMaxBuckets`
- `G3:DiomanBreaker.dispose`
- `G3:DiomanBreaker.isOpen`
- `G3:DiomanBreaker.keyBuilder`
- `G3:DiomanBreaker.name`
- `G3:DiomanBreaker.new(clock)`
- `G3:DiomanBreaker.onError`
- `G3:DiomanBreaker.onError#cancel-probe`
- `G3:DiomanBreaker.onError#network-classification`
- `G3:DiomanBreaker.onResponse`
- `G3:DiomanBreaker.onStateChange`
- `G3:DiomanBreaker.ordering`
- `G3:DiomanBreaker.pluginName`
- `G3:DiomanBreaker.stateOf`
- `G3:DiomanBreakerOpenException.bucketKey`
- `G3:DiomanBreakerOpenException.retryableAt`
- `G3:DiomanBreakerOptions.failureThreshold`
- `G3:DiomanBreakerOptions.halfOpenMaxCalls`
- `G3:DiomanBreakerOptions.keyBuilder`
- `G3:DiomanBreakerOptions.resetDuration`
- `G3:DiomanCache.dispose`
- `G3:DiomanCache.name`
- `G3:DiomanCache.new(now)`
- `G3:DiomanCache.ordering`
- `G3:DiomanCache.pluginName`
- `G3:DiomanCacheOptions.expires`
- `G3:DiomanCacheOptions.now`
- `G3:DiomanCachePersist.erase`
- `G3:DiomanCachePersist.remove`
- `G3:DiomanCancel.config`
- `G3:DiomanCancel.dispose`
- `G3:DiomanCancel.dispose#inflight`
- `G3:DiomanCancel.name`
- `G3:DiomanCancel.new(enabled)`
- `G3:DiomanCancel.onResponse`
- `G3:DiomanCancel.ordering`
- `G3:DiomanCancel.pluginName`
- `G3:DiomanCancelOptions.enabled`
- `G3:DiomanEnvs.config`
- `G3:DiomanEnvs.new(dio)`
- `G3:DiomanEnvs.new(enabled)`
- `G3:DiomanEnvs.onRequest`
- `G3:DiomanEnvs.pluginName`
- `G3:DiomanEnvs.rules`
- `G3:DiomanEnvsOptions.enabled`
- `G3:DiomanExtraKey.config(name)`
- `G3:DiomanExtraKey.description`
- `G3:DiomanExtraKey.kind`
- `G3:DiomanExtraKey.owner`
- `G3:DiomanExtraKey.valueType`
- `G3:DiomanFilter.name`
- `G3:DiomanFilter.pluginName`
- `G3:DiomanKey.name`
- `G3:DiomanKey.ordering`
- `G3:DiomanKey.pluginName`
- `G3:DiomanKeyOptions.enabled`
- `G3:DiomanKeyOptions.fastMode`
- `G3:DiomanKeyOptions.ignores`
- `G3:DiomanLoading.activeCount`
- `G3:DiomanLoading.dispose`
- `G3:DiomanLoading.name`
- `G3:DiomanLoading.onError`
- `G3:DiomanLoading.onResponse`
- `G3:DiomanLoading.ordering`
- `G3:DiomanLoading.pluginName`
- `G3:DiomanLoadingOptions.delay`
- `G3:DiomanLoadingOptions.delayClose`
- `G3:DiomanLog.enabled`
- `G3:DiomanLog.logBody`
- `G3:DiomanLog.logError`
- `G3:DiomanLog.logHeaders`
- `G3:DiomanLog.logRequest`
- `G3:DiomanLog.logResponse`
- `G3:DiomanLog.maxBodyLength`
- `G3:DiomanLog.name`
- `G3:DiomanLog.onError`
- `G3:DiomanLog.onRequest`
- `G3:DiomanLog.onResponse`
- `G3:DiomanLog.pluginName`
- `G3:DiomanLogOptions.enabled`
- `G3:DiomanLogOptions.logBody`
- `G3:DiomanLogOptions.logError`
- `G3:DiomanLogOptions.logHeaders`
- `G3:DiomanLogOptions.logRequest`
- `G3:DiomanLogOptions.logResponse`
- `G3:DiomanLogOptions.maxBodyLength`
- `G3:DiomanMock.add`
- `G3:DiomanMock.dispose`
- `G3:DiomanMock.mockUrl`
- `G3:DiomanMock.name`
- `G3:DiomanMock.pluginName`
- `G3:DiomanMockOptions.mockUrl`
- `G3:DiomanNormalize.messageKey`
- `G3:DiomanNormalize.name`
- `G3:DiomanNormalize.pluginName`
- `G3:DiomanNormalizeOptions.dataKey`
- `G3:DiomanNormalizeOptions.messageKey`
- `G3:DiomanNotify.name`
- `G3:DiomanNotify.notify`
- `G3:DiomanNotify.onError`
- `G3:DiomanNotify.onRequest`
- `G3:DiomanNotify.onResponse`
- `G3:DiomanNotify.pluginName`
- `G3:DiomanNotify.stringify`
- `G3:DiomanOffline.dispose`
- `G3:DiomanOffline.name`
- `G3:DiomanOffline.onRequest`
- `G3:DiomanOffline.ordering`
- `G3:DiomanOffline.pluginName`
- `G3:DiomanOfflineException.reason`
- `G3:DiomanOfflineOptions.enabled`
- `G3:DiomanOfflineOptions.maxQueueSize`
- `G3:DiomanOfflineReason.disposed`
- `G3:DiomanOfflineReason.timeout`
- `G3:DiomanPlugin.dispose`
- `G3:DiomanPlugin.name`
- `G3:DiomanPluginOrder.none`
- `G3:DiomanPluginOrderException.issue`
- `G3:DiomanPluginOrderException.message`
- `G3:DiomanPluginOrderException.plugins`
- `G3:DiomanPluginOrderException.toString`
- `G3:DiomanRepath.name`
- `G3:DiomanRepath.pluginName`
- `G3:DiomanRetry.afterStatusCodes`
- `G3:DiomanRetry.delayMax`
- `G3:DiomanRetry.dio`
- `G3:DiomanRetry.dispose`
- `G3:DiomanRetry.name`
- `G3:DiomanRetry.onError`
- `G3:DiomanRetry.pluginName`
- `G3:DiomanRetry.respectRetryAfter`
- `G3:DiomanRetry.respectRetryAfter#real-header`
- `G3:DiomanRetry.retryAfterMax`
- `G3:DiomanRetry.statusCodes`
- `G3:DiomanRetry.statusCodes#network-type`
- `G3:DiomanRetryOptions.afterStatusCodes`
- `G3:DiomanRetryOptions.delay`
- `G3:DiomanRetryOptions.delayMax`
- `G3:DiomanRetryOptions.max`
- `G3:DiomanRetryOptions.respectRetryAfter`
- `G3:DiomanRetryOptions.retryAfterMax`
- `G3:DiomanRetryOptions.statusCodes`
- `G3:DiomanShare.dio`
- `G3:DiomanShare.dispose`
- `G3:DiomanShare.hasMultipleDownstreamSettlers`
- `G3:DiomanShare.interval`
- `G3:DiomanShare.name`
- `G3:DiomanShare.onResponse`
- `G3:DiomanShare.pluginName`
- `G3:DiomanShareOptions.interval`
- `G3:DiomanShareOptions.retries`
- `G3:DiomanSharePolicy.none`
- `G3:DiomanSharePolicy.start`
- `G3:DiomanSharedStateKey.key`
- `G3:DiomanSharedStateKey.toString`
- `G3:DiomanTimeout.name`
- `G3:DiomanTimeout.pluginName`
- `G3:DiomanTimeoutOptions.enabled`
- `G3:DiomanTimeouts.connect`
- `G3:DiomanTimeouts.connect#effective`
- `G3:DiomanTimeouts.send`
- `G3:DiomanTimeouts.send#effective`
- `G3:DiomanTokenManager.accessToken`
- `G3:DiomanTokenManager.canRefresh`
- `G3:DiomanTokenManager.clear`
- `G3:DiomanTokenManager.refreshToken`
- `G3:EnvRule.config`
- `G3:INV-18`
- `G3:INV-20`
- `G3:NetworkQuality.excellent`
- `G3:NetworkQuality.good`
- `G3:NetworkQuality.none`
- `G3:NetworkQuality.poor`
- `G3:cancelAll`
- `G3:defaultAuthFailure`
- `G3:defaultFallback`
- `G3:kKey`

</details>

<details>
<summary>G4（20）</summary>

- `G4:DiomanAuth.dio#transport-reuse:no-real`
- `G4:DiomanAuth.dio#transport-reuse:no-result`
- `G4:DiomanAuth.onError#multipart-replay:no-real`
- `G4:DiomanAuth.onError#multipart-replay:no-result`
- `G4:DiomanBreaker.onError#cancel-probe:no-real`
- `G4:DiomanBreaker.onError#cancel-probe:no-result`
- `G4:DiomanBreaker.onError#network-classification:no-real`
- `G4:DiomanBreaker.onError#network-classification:no-result`
- `G4:DiomanCancel.dispose#inflight:no-real`
- `G4:DiomanCancel.dispose#inflight:no-result`
- `G4:DiomanRetry.statusCodes#network-type:no-real`
- `G4:DiomanRetry.statusCodes#network-type:no-result`
- `G4:DiomanSharePolicy.retry:no-real`
- `G4:DiomanSharePolicy.retry:no-result`
- `G4:DiomanTimeouts.connect#effective:no-real`
- `G4:DiomanTimeouts.connect#effective:no-result`
- `G4:DiomanTimeouts.send#effective:no-real`
- `G4:DiomanTimeouts.send#effective:no-result`
- `G4:INV-18:no-real`
- `G4:INV-18:no-result`

</details>

<details>
<summary>G5（28）</summary>

- `G5:real-orphan:auth.refresh-window-blocked-expired`
- `G5:real-orphan:cache.single-clear-cache`
- `G5:real-orphan:cache.single-explicit-key-expires`
- `G5:real-orphan:combo.auth-envs-refresh-replay`
- `G5:real-orphan:combo.auth-logger-refresh-deny-revoked`
- `G5:real-orphan:combo.cache-envs-hit-and-ttl`
- `G5:real-orphan:combo.cache-mock-fallback-cached-once`
- `G5:real-orphan:combo.cache-mock-no-key-collision`
- `G5:real-orphan:combo.cancel-logger-cleanup`
- `G5:real-orphan:combo.envs-mock-routing`
- `G5:real-orphan:combo.envs-retry-recovers-and-exhausts`
- `G5:real-orphan:combo.filter-repath-path-var-first`
- `G5:real-orphan:combo.filter-retry-recovers-and-exhausts`
- `G5:real-orphan:combo.loading-mock-fallback-single-pair`
- `G5:real-orphan:combo.logger-retry-recovers-and-exhausts`
- `G5:real-orphan:combo.mock-share-fallback-single-flight`
- `G5:real-orphan:combo.repath-retry-path-stable`
- `G5:real-orphan:mock.single-fallback-disabled`
- `G5:real-orphan:notify.single-silent-and-stringify`
- `G5:real-orphan:retry.single-plugin-methods`
- `G5:real-orphan:retry.single-req-max-delay`
- `G5:real-orphan:retry.single-req-methods`
- `G5:real-orphan:retry.single-req-retry-after-override`
- `G5:real-orphan:retry.single-retry-after-honored`
- `G5:real-orphan:retry.single-retry-after-ignored`
- `G5:real-orphan:share.single-all-timeout-aborts-server`
- `G5:real-orphan:share.single-req-policy-race`
- `G5:real-orphan:share.single-start-explicit-key`

</details>

