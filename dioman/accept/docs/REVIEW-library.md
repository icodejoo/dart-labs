# 上轮七文件 diff 自审（2026-10-27）

本轮逐个读取了七个文件相对当前 HEAD 的限定路径 `git diff`；保留原改动，没有 commit、stash 或整仓库回退。
顺序依据先读 `README.md:136`、`lib/src/plugin_order.dart`，再核对各插件 `ordering`。
这里的“有回归”指对应行为已有具体断言，不代表所有取值和竞态已经穷尽。

| 文件 | diff 中的行为改动与核对结论 | 对应可执行回归 |
|---|---|---|
| `auth_plugin.dart` | `_expiredNotified` 在有 access 的请求中重置，过期通知按会话去重；过期错误保留原响应。重试桥接恢复原始裸 token，并将 401 交回原 auth；重放仍为认证失败时结束会话。没有增加 extra 键；原 protected/tokenUsed/refreshed 状态由既有注册表管理。BOM 与换行调整不改变行为。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：重试遇到401、并发稳定过期、重新登录再次通知；`test/unit/（各插件回归）及 test/combo/cross_test.dart`：replay401/500、重放 header 回调抛异常 |
| `extra_keys.dart` | 只增加 `dioman:notify:sent`，归属 notify、类型 bool、种类 state，与 notify 的常量一致；未与配置键或协议键重复。 | `test/integration/extra_keys_integration_test.dart` 的源码/注册表双向检查、`test/unit/extra_keys_test.dart` 的唯一性与前缀检查；真实矩阵 `rules` 逐键登记 |
| `notify_plugin.dart` | 声明 notify 在 normalize 前；每次 onRequest 清除通知标记，同一逻辑请求发出非空通知后置位，响应转错误时不重复通知。无强制依赖，缺 normalize 时仍能单开。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：notify读取解包前业务错误且只通知一次；17插件全开 normal/weak/flap，http/business，notify次数=1；真实逆序拒绝规则 |
| `replay_support.dart` | 恢复响应先交给 self 前的 cache，再交给 self 后的响应阶段；cache 接收原信封，normalize 在后。未新增 extra 键。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：auth恢复写回上游缓存、只归一化一次；`test/unit/（各插件回归）及 test/combo/cross_test.dart`：同步/异步下游异常、三种仲裁出口、取消、胜出方失败 |
| `request_claims.dart` | 新增内部 `recoverAuth` 回调属性，仍使用已有 `dioman:claims`，没有新增跨插件字符串键；责任按请求登记。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：500→401→刷新；`test/unit/（各插件回归）及 test/combo/cross_test.dart`：release/whenDrained、仲裁交付及取消后已结束断言 |
| `retry_plugin.dart` | `_reissue` 恢复 auth；失败尝试逐次交给 breaker，重试前领取新 admission，等待后再查 open。终态不重复记账。原 README“只算最终失败”与此冲突，本轮已修正文档。格式化和月份字典展开不改变行为。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：3次失败达到阈值而不是重试6次；`test/unit/（各插件回归）及 test/combo/cross_test.dart`：Retry-After数字/日期/非法值、jitter、响应阶段取消；真实全开重试流程 |
| `share_plugin.dart` | start 策略登记 followers；首发取消后通过已有 ReplayClient 将传输交给存活跟随者；entry.promoting 阻止重复接手。新属性位于 entry 对象内，不引入 extra 键。BOM 与换行调整不改变行为。 | `test/combo/cross_test.dart、test/unit/auth_test.dart、test/unit/share_test.dart、test/unit/notify_test.dart`：首发取消后跟随者成功；`test/unit/（各插件回归）及 test/combo/cross_test.dart`：最后接手者也取消后新请求成功、显式settle、race/end胜出交付 |

真实顺序规则由 `accept/lib/plugin_rules.dart` 实现：对安装集合执行 `Dioman.validate`，将实际图的每条边反转后要求 misordered；重复名要求 duplicateName；extra 注册表检查唯一性/归属/前缀，正常安装不得有状态键冲突。
缺依赖、环、自指、动态插入/删除的专项断言仍在 `test/unit/plugin_order_test.dart`；这些是库级测试，不伪称独立服务端请求。

本轮另外核实 `key_plugin.dart` 私有 `_encode` 只有两处调用：过滤后的 body Map 与 query Map。将参数由 Object 收窄为 Map，删除无法到达的非 Map 编码分支；不可序列化 Map 的字符串回退仍保留并有新增回归。
本轮确认并修复一个新的库级行为缺陷：share 的内部重试准备（例如自定义 FormData.clone 抛 FormatException）进入兜底出口时只结束首发，没有调用 `_finishOrDefer`，使跟随者悬挂。回归在修复前明确失败（认领未结束），修复后要求首发和跟随者都失败且共享认领已结束；真实47080/netem的http/business复验各通过一次，服务端各只命中1次、inflight=0、loading成对。证据见`../results/share-prepare-real.json`与`share-prepare-baseline.log`。
本轮另外两次矩阵失败是 flap 中 offline 提前拒绝、尚未进入 notify 导致的场景预期错误，修正后双风格复验通过。README和breaker类注释中“只算最终失败”的旧描述已同步修正。

尚未穷尽每个插件的实现不变量；规则矩阵不得据此标为全规则完成。
