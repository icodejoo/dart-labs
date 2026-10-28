# dioman B0 旧行为迁移总表

来源：`dart test test_legacy --reporter json` 的 testStart/testDone 事件（[原始事件](raw/legacy-tests.ndjson)），排除 loading、hidden、metadata.skip 与 testDone.skipped；每个参数化运行时标题单独一行。
归档前路径由 `test_legacy/` 一一还原成 `test/`；默认排除 real 标签，不把未运行的外部服务测试计入本地总数。旧 powerset 的 32767 个内部循环是一个运行时 test，不虚增用例。
总账源是未改动的 `test/accept/lib/matrix.json`，逐行以原 id 对账。预计位置按 `docs/guides/test-layers.md` 与 pipeline-test-plan §1 最低证明层安排；纯归一化进 unit，真实 IO 进 integration，多插件进 combo。
API id 是 B1–B5 的预定命名；删除能力的 new_api/location 是替代能力，绝非承诺恢复被删接口。`Options` 的机械换键仍可 keep；只有协议、判定或可观察行为变化才 change。
存疑为互斥分类上的附加标记，已计入 keep/change/drop，不能再加一次。B0 不替终审裁决。

## 计数

| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |
|---|---:|---:|---:|---:|---:|
| tests/unit | 91 | 36 | 9 | 46 | 0 |
| tests/rule | 238 | 118 | 87 | 33 | 21 |
| tests/boundary | 89 | 53 | 33 | 3 | 5 |
| tests/combo | 122 | 20 | 93 | 9 | 4 |
| tests/integration | 40 | 12 | 13 | 15 | 0 |
| tests/合计 | 580 | 239 | 235 | 106 | 30 |

`tests: 旧总数 580 = keep 239 + change 235 + drop 106`

| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |
|---|---:|---:|---:|---:|---:|
| matrix/unit | 107 | 7 | 40 | 60 | 7 |
| matrix/rule | 278 | 163 | 87 | 28 | 17 |
| matrix/boundary | 0 | 0 | 0 | 0 | 0 |
| matrix/combo | 19 | 4 | 13 | 2 | 0 |
| matrix/integration | 38 | 7 | 28 | 3 | 0 |
| matrix/合计 | 442 | 181 | 168 | 93 | 24 |

`matrix: 旧总数 442 = keep 181 + change 168 + drop 93`

## 终审裁决（2026-10-29）

54 条存疑按 [插件规格 §8.1](../../design/pipeline-plugin-spec.md) 裁决。其中请求级 `now` 覆盖、`cachePolicy.none`、`DiomanCacheOptions.maxEntries`、`DiomanSharePolicy.none` 相关的行改为 drop（新增行为变化编号 C13），其余维持 change；改标由 B1 用 `tool/pipeline_migration.py` 落地并重新核对公式。

## 存疑行（逐项交终审）

| 来源 / 身份 | 旧位置或能力 | 暂定 | 理由 |
|---|---|---|---|
| tests/T0058 | test/boundary/key_boundary_test.dart :: key namespace [DiomanKey.builder][DiomanKey.fastMode] absent null and empty namespaces preserve exact legacy keys | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0066 | test/boundary/offline_boundary_test.dart :: DiomanOffline [DiomanOfflineReason.disposed][DiomanOfflineException.reason][DiomanOffline.pending][DiomanOffline.new(isOnline)] dispose rejects every pending request (no perma-hang) | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0067 | test/boundary/offline_boundary_test.dart :: DiomanOffline [DiomanOfflineReason.queueFull][DiomanOffline.maxQueueSize] queue full evicts the oldest with a queueFull rejection | change | 新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。 |
| tests/T0068 | test/boundary/offline_boundary_test.dart :: [DiomanOffline.flush][DiomanOffline.new(isOnline)] offline flush checks cancellation before cancellation listener runs | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0079 | test/boundary/retry_boundary_test.dart :: retry 回调异常（#13） [DiomanRetry.onRetry] onRetry 抛异常：转成 DioException | change | 架构通知类枚举未列 onRetry；暂按 bug 原样抛出，是否属于通知隔离需终审。 |
| tests/T0157 | test/combo/cache_normalize_combo_test.dart :: 装了 normalize：HTTP 200 + 业务失败不入缓存 [DiomanCache.new(shouldStore) × DiomanNormalize.shouldNormalize] shouldNormalize 返回 false：照常缓存 | change | 新工厂要求 code+data，旧识别允许 code+message；迁客户端 envelope/create 后需终审确认自定义识别能力的替代范围。 |
| tests/T0158 | test/combo/cache_normalize_combo_test.dart :: 装了 normalize：HTTP 200 + 业务失败不入缓存 [DiomanCache.new(shouldStore) × DiomanNormalize.shouldNormalize] 非 Map 响应透传：照常缓存 | change | 新工厂要求 code+data，旧识别允许 code+message；迁客户端 envelope/create 后需终审确认自定义识别能力的替代范围。 |
| tests/T0162 | test/combo/cache_normalize_combo_test.dart :: 装了 normalize：HTTP 200 + 业务失败不入缓存 [DiomanCache.new(shouldStore) × DiomanNormalizeOptions.shouldNormalize] 请求级 shouldNormalize 返回 false：照常缓存 | change | 新工厂要求 code+data，旧识别允许 code+message；迁客户端 envelope/create 后需终审确认自定义识别能力的替代范围。 |
| tests/T0212 | test/combo/retry_share_arbitration_combo_test.dart :: share end/race 窄组合（已知限制 #1 #2 #3） [DiomanRetry.onRetry × DiomanSharePolicy.race] race：A 的 onRetry 抛异常、B 随后失败，A 收到 B 的失败而不是回调异常，且无未处理异步错误 | change | 架构通知类枚举未列 onRetry；暂按 bug 原样抛出，是否属于通知隔离需终审。 |
| tests/T0275 | test/rule/auth_overrides_rule_test.dart :: [DiomanAuthOptions.expiresAt][DiomanAuthOptions.now][DiomanAuthOptions.refreshLeeway][DiomanAuth.new(refreshLeeway)] constructor 覆盖、空值继承与到期等号边界 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0276 | test/rule/auth_overrides_rule_test.dart :: [DiomanAuthOptions.expiresAt][DiomanAuthOptions.now][DiomanAuthOptions.refreshLeeway][DiomanAuth.new(refreshLeeway)] expiresAt 覆盖、空值继承与到期等号边界 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0277 | test/rule/auth_overrides_rule_test.dart :: [DiomanAuthOptions.expiresAt][DiomanAuthOptions.now][DiomanAuthOptions.refreshLeeway][DiomanAuth.new(refreshLeeway)] now 覆盖、空值继承与到期等号边界 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0278 | test/rule/auth_overrides_rule_test.dart :: [DiomanAuthOptions.expiresAt][DiomanAuthOptions.now][DiomanAuthOptions.refreshLeeway][DiomanAuth.new(refreshLeeway)] refreshLeeway 覆盖、空值继承与到期等号边界 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0286 | test/rule/breaker_options_rule_test.dart :: [DiomanBreaker.defaultIdleTtl][DiomanBreaker.bucketCount][DiomanBreaker.dispose] 默认一小时惰性回收，查询不回收，dispose 清全部桶 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0287 | test/rule/breaker_options_rule_test.dart :: [DiomanBreaker.defaultMaxBuckets] 默认一千桶软上限用于实际淘汰 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0288 | test/rule/breaker_options_rule_test.dart :: [DiomanBreaker.isOpen][DiomanBreaker.stateOf][DiomanBreaker.new(clock)] 未知桶只读、注入时钟冷却到点后仅查询不迁移 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0308 | test/rule/cache_options_rule_test.dart :: [DiomanCacheOptions.expires][DiomanCacheOptions.now] 请求级 TTL=-1 不钳制，时钟同时用于写入和到期读取，空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| tests/T0309 | test/rule/cache_options_rule_test.dart :: [DiomanCacheOptions.expires][DiomanCacheOptions.now] 请求级 TTL=0 不钳制，时钟同时用于写入和到期读取，空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| tests/T0310 | test/rule/cache_options_rule_test.dart :: [DiomanCacheOptions.expires][DiomanCacheOptions.now] 请求级 TTL=1000 不钳制，时钟同时用于写入和到期读取，空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0317 | test/rule/cache_policy_rule_test.dart :: DiomanCache cachePolicy [DiomanCachePolicy.none][DiomanClonePolicy.none] none (default): never caches at all, neither layer touched | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| tests/T0318 | test/rule/cache_policy_rule_test.dart :: [DiomanCachePolicy.none][DiomanClonePolicy.none] none cache skips decisions and bookkeeping | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| tests/T0321 | test/rule/cache_store_rule_test.dart :: DiomanCache [DiomanCache.maxEntries][DiomanCacheOptions.maxEntries] maxEntries bounds the store via LRU eviction instead of growing without limit | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| tests/T0337 | test/rule/envs_rule_test.dart :: DiomanEnvs [DiomanEnvs.new(dio)][EnvRule.rule] the first matching rule wins and its BaseOptions fields are shallow-merged into dio.options; a later, also-matching rule is never even evaluated | change | 新 envs 要求克隆容器，旧版按支持字段浅合并；空地址/default json 的合并优先级新文未展开，交终审。 |
| tests/T0350 | test/rule/key_options_rule_test.dart :: [DiomanKeyOptions.enabled][DiomanKeyOptions.fastMode] 空值继承而显式值覆盖构键模式 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0351 | test/rule/key_options_rule_test.dart :: [DiomanKeyOptions.ignores] 请求忽略项与全局取并集且空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0353 | test/rule/key_rule_test.dart :: Newly wired Options fields (full constructor↔Options parity) [DiomanKey.builder][DiomanKeyOptions.builder] DiomanKeyOptions.builder overrides the computed key for a single call | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0358 | test/rule/key_rule_test.dart :: [DiomanKeyOptions.builder][DiomanKeyOptions.key][DiomanKey.builder][DiomanKey.namespace] key sources follow precedence with namespace | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| tests/T0366 | test/rule/loading_rule_test.dart :: DiomanLoadingOptions.onChanged (edge-triggered, not additive) [DiomanLoading.activeCount][DiomanLoading.new(onChanged)][DiomanLoadingOptions.onChanged] a request's own onChanged does not fire if it doesn't land on the batch edge (another request is already keeping the counter above zero) — counting is still accurate either way | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| tests/T0430 | test/rule/offline_rule_test.dart :: DiomanOffline [DiomanOffline.new(shouldQueue)][DiomanOfflineOptions.shouldQueue] shouldQueue: only writes are queued, reads pass through | change | 新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。 |
| tests/T0478 | test/rule/share_rule_test.dart :: DiomanShare: none policy, own-failure settlement, dispose, hasMultipleDownstreamSettlers [DiomanShare.policy][DiomanShare.onError][DiomanSharePolicy.none] policy: none passes every request through independently — never shared, and errors reach onError with no entry attached | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| matrix/DiomanAuthOptions.now |  :: 单请求覆盖主动到期判断时钟 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanBreaker.bucketCount |  :: 返回当前保留的桶数，不主动触发回收 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanBreaker.defaultIdleTtl |  :: 默认桶空闲回收时长为一小时 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanBreaker.defaultMaxBuckets |  :: 默认桶数量软上限为一千 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanBreaker.isOpen |  :: 只读判断当前是否会拒绝，不改变桶状态 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanBreaker.stateOf |  :: 只读查询状态，未知桶返回 closed | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanCache.cachePolicy |  :: 默认 none，可按请求选择内存或持久层 | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| matrix/DiomanCache.maxEntries |  :: 内存默认五百项，非正数不设上限 | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| matrix/DiomanCacheOptions.maxEntries |  :: 弃用占位字段，单请求设置不被读取 | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| matrix/DiomanCacheOptions.now |  :: 单请求覆盖到期时钟，空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanCachePolicy.none |  :: 跳过缓存读取和写入 | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |
| matrix/DiomanKey.builder |  :: 请求级 builder 与 key 都没给时，用插件级构键器 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanKey.fastMode |  :: 默认深模式，快速模式只编码方法来源路径 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanKeyOptions.builder |  :: 单请求替换构键器，优先级低于显式非空键 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanKeyOptions.fastMode |  :: 单请求覆盖快速或深模式，空值继承 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanKeyOptions.ignores |  :: 单请求忽略字段与全局配置取并集 | change | 新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。 |
| matrix/DiomanLoading.activeCount |  :: 当前在途请求数；opt-out 的请求不计入 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanNormalize.shouldNormalize |  :: 是否拆包的判定，默认 Map 且含 code 及 data/message | change | 新工厂要求 code+data，旧识别允许 code+message；迁客户端 envelope/create 后需终审确认自定义识别能力的替代范围。 |
| matrix/DiomanOffline.flush |  :: 重放全部排队请求；已取消的以取消错误结束 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanOffline.maxQueueSize |  :: 队列上限，满则挤出最早的；0 表示不限，默认 50 | change | 新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。 |
| matrix/DiomanOffline.pending |  :: 当前挂起的请求数，只读 | change | 新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。 |
| matrix/DiomanOfflineOptions.maxQueueSize |  :: 单请求覆盖队列上限，入队时求值 | change | 新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。 |
| matrix/DiomanOfflineReason.queueFull |  :: 队列满，最早的请求被挤出 | change | 新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。 |
| matrix/DiomanSharePolicy.none |  :: 不共享，请求各自独立发出 | change | 新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。 |

## 可复算

```powershell
python tool/pipeline_migration.py generate
python tool/pipeline_migration.py verify
```

verify 同时核对事件身份全集、matrix id 全集、唯一性、互斥分类、change 的 C1–C12、drop 理由、新位置与 Markdown 行数，输出见报告。
