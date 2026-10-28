---
title: 库级行覆盖逐行复核（2026-10-27）
status: active
updated: 2026-10-28
summary: lcov 从 1683 到 1788/1793 的逐行处置，剩余 5 行兜底的理由。
---
# 库级覆盖逐行复核

历史1683/1793，缺110行；本轮1788/1793（99.7211%），缺5行。原110行处置：{'本轮已命中': 103, '保留兜底未命中': 5, '删除不可达分支': 1, '缺陷修复替换并覆盖': 1}。

分母恰好相同：key删除两个计数行，share修复新增两个计数行；行集合已经变化。当前五个兜底未命中行、理由及Dio契约摘录见results/coverage-review.json和results/coverage-invariants.json。

| 原文件:行 | 原代码 | 当前行 | 处置 | 说明 |
|---|---|---:|---|---|
| lib\src\cache_plugin.dart:550 | `return {for (final e in v.entries) e.key: _deepCopy(e.value)};` | 550 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:661 | `_clearFlags(bag);` | 661 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:663 | `DioException(requestOptions: opts, error: e, stackTrace: s);` | 663 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:664 | `if (!handler.isCompleted) {` | 664 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:665 | `_replay.handOffError(this, opts, failure, handler);` | 665 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:739 | `if (_isReplayAuthFailure(replayed.error?.response, o)) {` | 739 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:740 | `await _expire(response, o, staleToken: bag[_kTokenUsed] as String?);` | 740 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:741 | `_clearFlags(bag);` | 741 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:742 | `return _expiredError(replayed.error!.response!);` | 742 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:744 | `_clearFlags(bag);` | 744 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\auth_plugin.dart:777 | `error: DioException(requestOptions: opts, error: e, stackTrace: s),` | 777 | 保留兜底未命中 | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\extra_keys.dart:73 | `@override` | 73 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\extra_keys.dart:74 | `String toString() => 'DiomanExtraKey($key, $owner, ${kind.name})';` | 74 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\repath_plugin.dart:117 | `if (key == null) return m.group(0)!;` | 117 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\filter_plugin.dart:122 | `: {...ignoreValues, ...o!.ignoreValues!};` | 122 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\key_plugin.dart:254 | `return jsonEncode(v);` | 已删除 | 删除不可达分支 | 私有_encode仅被两个Map调用点调用；收窄参数并删除非Map返回支路。 |
| lib\src\key_plugin.dart:256 | `return v.toString();` | 253 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\offline_plugin.dart:56 | `@override` | 56 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\offline_plugin.dart:57 | `String toString() => 'DiomanOfflineException(${reason.name})';` | 57 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\offline_plugin.dart:69 | `const DiomanOfflineOptions({` | 69 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\offline_plugin.dart:338 | `if (!$enabled) return handler.next(options);` | 338 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:244 | `entry.complete(response);` | 244 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:248 | `_detach(entry);` | 248 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:460 | `lastError = token!.cancelError ?? lastError;` | 460 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:485 | `: DioException(requestOptions: opts, error: lastError);` | 485 | 保留兜底未命中 | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\share_plugin.dart:490 | `if (!handler.isCompleted) {` | 490 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:492 | `.next(DioException(requestOptions: opts, error: e, stackTrace: s));` | 494 | 缺陷修复替换并覆盖 | 原首发单独next被共享结算出口替换；修复前回归失败，修复后38项回归及真实双风格通过。 |
| lib\src\share_plugin.dart:524 | `_offer(entry, opts, response, error);` | 526 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:572 | `entry.completeError(DioException.requestCancelled(` | 574 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:591 | `.completeError(DioException(requestOptions: options, error: error));` | 593 | 保留兜底未命中 | 非 DioException 异常兜底：当前 ReplayClient.fetch 返回 Dio.fetch，Dio 将传输/转换异常包装为 DioException；标准传输路径不能进入该转换。保留防御分支，未删除。 |
| lib\src\share_plugin.dart:622 | `if (entry.isSettled) return _yieldToWinner(entry, opts);` | 624 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\share_plugin.dart:662 | `onError: (Object e) => handler.reject(copyError(e, own), true),` | 664 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\cancel_plugin.dart:177 | `void track(CancelToken token) {` | 177 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\cancel_plugin.dart:178 | `if (config.enabled) _tokens.add(token);` | 178 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\cancel_plugin.dart:187 | `void untrack(CancelToken token) => _tokens.remove(token);` | 187 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:223 | `_showTimer = Timer($delay, () {` | 223 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:224 | `_showTimer = null;` | 224 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:225 | `_shown = true;` | 225 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:226 | `$onChanged(true);` | 226 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:273 | `_clearShowTimer();` | 273 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:274 | `_cycleCallback = null;` | 274 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:280 | `_hideTimer = null;` | 280 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:281 | `_shown = false;` | 281 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:282 | `_cycleCallback = null;` | 282 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\loading_plugin.dart:283 | `$onChanged(false);` | 283 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:145 | `final _random = Random();` | 145 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:479 | `((_, __, ___, ____) => _defaultDelay);` | 479 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:490 | `Duration _resolveRetryAfterMax(RequestOptions config) =>` | 490 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:491 | `_overrideObject(config)?.retryAfterMax ?? retryAfterMax ?? _uncapped;` | 491 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:533 | `jittered = Duration(` | 533 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:534 | `microseconds: (raw.inMicroseconds * _random.nextDouble()).round(),` | 534 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:537 | `final r = jitter(raw);` | 537 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:538 | `jittered = r.isNegative ? raw : r;` | 538 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:543 | `static final _httpDate =` | 543 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:544 | `RegExp(r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$');` | 544 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:568 | `static DateTime? _parseHttpDate(String raw) {` | 568 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:569 | `final m = _httpDate.firstMatch(raw.trim());` | 569 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:571 | `final month = _months[m.group(2)];` | 571 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:573 | `return DateTime.utc(` | 573 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:574 | `int.parse(m.group(3)!),` | 574 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:576 | `int.parse(m.group(1)!),` | 576 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:577 | `int.parse(m.group(4)!),` | 577 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:578 | `int.parse(m.group(5)!),` | 578 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:579 | `int.parse(m.group(6)!),` | 579 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:583 | `Duration? _retryAfter(Response<dynamic>? response, Duration cap) {` | 583 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:584 | `final raw = response?.headers.value('retry-after');` | 584 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:586 | `final seconds = num.tryParse(raw);` | 586 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:588 | `return _capped(` | 588 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:589 | `Duration(milliseconds: (seconds * 1000).round()),` | 589 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:593 | `final date = _parseHttpDate(raw);` | 593 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:595 | `return _capped(date.difference(DateTime.now().toUtc()), cap);` | 595 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:616 | `? _retryAfter(response ?? err?.response, _resolveRetryAfterMax(config))` | 616 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:717 | `void _failCanceled(` | 717 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:719 | `final err = config.cancelToken!.cancelError ??` | 719 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:720 | `DioException.requestCancelled(` | 720 | 保留兜底未命中 | 取消错误兜底：唯一调用点先确认 token.isCancelled == true；Dio CancelToken 的该状态由非空 cancelError 定义，故 ?? 右支在此调用链不可达。 |
| lib\src\retry_plugin.dart:722 | `releaseClaim(config, this, error: err);` | 722 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:723 | `handler.reject(err, true);` | 723 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\retry_plugin.dart:777 | `: DioException(requestOptions: config, error: e);` | 777 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\breaker_plugin.dart:87 | `@override` | 87 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\breaker_plugin.dart:89 | `'DiomanBreakerOpenException(bucket: $bucketKey, retryableAt: $retryableAt)';` | 89 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\breaker_plugin.dart:654 | `return _reject(options, handler, key, b);` | 654 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\breaker_plugin.dart:770 | `_recordSuccess(key, config);` | 770 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\breaker_plugin.dart:779 | `void reset() => _buckets.clear();` | 779 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\log_plugin.dart:235 | `: '✗ ${err.type.name} ${err.requestOptions.method.toUpperCase()} ${err.requestOptions.uri}';` | 235 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:40 | `Dio? get host => _host;` | 40 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:80 | `if (!handler.isCompleted) {` | 80 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:81 | `handler.reject(_asDio(e, current.requestOptions, s), true);` | 81 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:86 | `throw DownstreamReject(_asDio(e, current.requestOptions, s),` | 86 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:102 | `: _asDio(data ?? e, current.requestOptions, StackTrace.current),` | 102 | 保留兜底未命中 | 非 DioException 的 handler 错误 data 兜底：Dio 的 ResponseInterceptorHandler.reject 参数类型为 DioException；同步/异步抛出已在此前转换。标准 handler 契约下不可达。 |
| lib\src\replay_support.dart:135 | `final err = _asDio(e, opts, StackTrace.current);` | 135 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:136 | `claims?.finish(error: err);` | 136 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:137 | `return handler.next(err);` | 137 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:168 | `_awaitWinner(wait, opts).then<void>(` | 168 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:169 | `handler.next,` | 169 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:170 | `onError: (Object e, StackTrace s) =>` | 170 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:171 | `handler.reject(_asDio(e, opts, s), true),` | 171 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:186 | `if (err.type == DioExceptionType.cancel) {` | 186 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:187 | `wait.ignore();` | 187 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:188 | `return handler.reject(err, true);` | 188 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:190 | `_awaitWinner(wait, opts).then<void>(` | 190 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:191 | `handler.next,` | 191 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:192 | `onError: (Object e, StackTrace s) =>` | 192 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:193 | `handler.reject(_asDio(e, opts, s), true),` | 193 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:210 | `wait.ignore();` | 210 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:211 | `return handler.next(err);` | 211 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:257 | `: DioException(requestOptions: opts, error: e, stackTrace: s);` | 257 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\replay_support.dart:268 | `} on StateError {` | 268 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\request_claims.dart:77 | `callback();` | 77 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\request_claims.dart:115 | `void releaseClaim(` | 115 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
| lib\src\request_claims.dart:121 | `claimsOf(opts)?.release(owner, response: response, error: error);` | 121 | 本轮已命中 | coverage/review-postfix的最终全量单测lcov记录命中。 |
