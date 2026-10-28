| 原来源行 | ID | 原分类 | 新用例 | 说明 |
|---|---|---|---|---|
| boundary.md:46 | T0041 | keep | `test/boundary/cache_persist_boundary_test.dart:176` — [DiomanCache.clone] 写入快照隔离来源和返回值，扩展工厂保留标记 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:47 | T0042 | keep | `test/boundary/source_boundary_test.dart:184` — [DiomanCache.maxEntries] 新结果淘汰后旧在途不得回写，LRU 命中提升和不限容量 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:48 | T0043 | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:49 | T0044 | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:50 | T0045 | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:51 | T0046 | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:52 | T0047 | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:53 | T0048 | keep | `test/boundary/cache_persist_boundary_test.dart:96` — [DiomanCachePersist.read] 旧过期慢读取不得删除较新写入，持久命中按容量提升 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:54 | T0049 | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:70 | T0066 | change | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:71 | T0067 | change | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:72 | T0068 | change | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| boundary.md:73 | T0069 | keep | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:74 | T0070 | keep | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:75 | T0071 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| boundary.md:76 | T0072 | keep | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:87 | T0083 | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:88 | T0084 | keep | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:89 | T0085 | change | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:90 | T0086 | keep | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:92 | T0088 | change | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:93 | T0089 | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:94 | T0090 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| boundary.md:95 | T0091 | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| boundary.md:96 | T0092 | change | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| boundary.md:97 | T0093 | change | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:10 | T0102 | keep | `test/combo/b4_auth_migration_combo_test.dart:7` — [DiomanAuth.onRefresh × DiomanCache.option] 刷新后缓存只保存最终成功并供后续调用命中 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:11 | T0103 | change | `test/combo/b4_auth_migration_combo_test.dart:11` — [DiomanAuth.onRefresh × DiomanCache.option] 清除凭据后缓存命中也必须通过鉴权 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:20 | T0112 | keep | `test/combo/b4_auth_migration_combo_test.dart:13` — [DiomanAuth.onRefresh × DiomanShare.option] 传输失败后刷新期间首发取消不影响跟随者 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:21 | T0113 | change | `test/combo/b4_auth_migration_combo_test.dart:15` — [DiomanAuth.onRefresh × DiomanShare.option] 业务失败后刷新期间首发取消不影响跟随者 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:22 | T0114 | change | `test/combo/b4_auth_migration_combo_test.dart:17` — [DiomanAuth.onRefresh × DiomanShare.option] 刷新后传输失败仍重试并携带新凭据 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:25 | T0118 | change | `test/combo/b4_auth_migration_combo_test.dart:19` — [DiomanAuth.onRefresh × DiomanShare.option] 就绪回调异常使所有共享调用保留原错误落定 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:26 | T0119 | change | `test/combo/b4_auth_migration_combo_test.dart:21` — [DiomanAuth.onRefresh × DiomanShare.option] 到期回调异常使所有共享调用保留原错误落定 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:27 | T0120 | change | `test/combo/b4_auth_migration_combo_test.dart:23` — [DiomanAuth.onRefresh × DiomanShare.option] 保护判定异常使所有共享调用保留原错误落定 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:28 | T0121 | change | `test/combo/b4_auth_migration_combo_test.dart:25` — [DiomanAuth.onRefresh × DiomanShare.option] 主动刷新时钟异常使所有共享调用保留原错误落定 | 请求级 now 删除；改用客户端时钟，回调 bug 原样落定与 source 状态清理仍验证。 |
| combo.md:29 | T0122 | keep | `test/combo/b4_auth_migration_combo_test.dart:27` — [DiomanAuth.onRefresh × DiomanShare.option] 并发鉴权失败只刷新一次并共享重放成功 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:30 | T0123 | keep | `test/combo/b4_auth_migration_combo_test.dart:29` — [DiomanAuth.onRefresh × DiomanShare.option] 单调用刷新重放后共享活动表与逻辑状态归零 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:31 | T0124 | change | `test/combo/b4_auth_migration_combo_test.dart:33` — [DiomanAuth.onRefresh × DiomanShare.option] 失败回调异常使竞速调用保留原错误落定 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:32 | T0125 | keep | `test/combo/b4_auth_migration_combo_test.dart:37` — [DiomanAuth.onRefresh × DiomanShare.option] 公开请求没有凭据仍可共享一次传输 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:33 | T0126 | change | `test/combo/b4_auth_migration_combo_test.dart:39` — [DiomanAuth.onRefresh × DiomanShare.option] 内联模拟在共享之前为每个逻辑调用执行 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:34 | T0127 | change | `test/combo/b4_auth_migration_combo_test.dart:41` — [DiomanAuth.onRefresh × DiomanShare.option] 内部重试与鉴权组合保持逻辑状态完整 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:35 | T0128 | keep | `test/combo/b4_auth_migration_combo_test.dart:43` — [DiomanAuth.onRefresh × DiomanShare.option] 重装共享插件后刷新重放仍正确结算 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:36 | T0129 | change | `test/combo/b4_auth_migration_combo_test.dart:50` — [DiomanAuth.onRefresh × DiomanShare.option] 刷新期间全局取消使所有共享调用结束并清理 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:37 | T0130 | keep | `test/combo/b4_auth_migration_combo_test.dart:52` — [DiomanAuth.onRefresh × DiomanShare.option] 最新成功覆盖旧鉴权失败且不提前刷新 | 删除认领登记簿，验证外层逻辑请求与共享活动表归零。 |
| combo.md:41 | T0134 | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:42 | T0135 | change | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:43 | T0136 | change | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:44 | T0137 | change | `test/combo/source_migration_combo_test.dart:111` — [DiomanKeyOptions.namespace × DiomanCache.option × DiomanShare.option] 账号隔离和 prepare 后请求体区分 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:45 | T0138 | change | `test/combo/source_migration_combo_test.dart:111` — [DiomanKeyOptions.namespace × DiomanCache.option × DiomanShare.option] 账号隔离和 prepare 后请求体区分 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:46 | T0139 | keep | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:47 | T0140 | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:48 | T0141 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:49 | T0142 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:50 | T0143 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:51 | T0144 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:52 | T0145 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:53 | T0146 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:54 | T0147 | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:59 | T0152 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:60 | T0153 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:61 | T0154 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:62 | T0155 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:63 | T0156 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:64 | T0157 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:65 | T0158 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:66 | T0159 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:67 | T0160 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:68 | T0161 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:69 | T0162 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:70 | T0163 | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:71 | T0164 | change | `test/combo/b4_retry_migration_combo_test.dart:7` — [DiomanRetry.max × DiomanShare.option] 业务失败外层重试后缓存只保存成功响应 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:72 | T0165 | change | `test/combo/b4_retry_migration_combo_test.dart:9` — [DiomanRetry.max × DiomanShare.option] 共享重试成功后再次调用命中缓存且不重复发送 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:73 | T0166 | keep | `test/combo/source_combo_test.dart:61` — [DiomanShare.option × DiomanCache.option] 并发一次发送缓存一次，下一轮零触网 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| combo.md:74 | T0167 | change | `test/combo/source_combo_test.dart:61` — [DiomanShare.option × DiomanCache.option] 并发一次发送缓存一次，下一轮零触网 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| combo.md:78 | T0171 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:79 | T0172 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:80 | T0173 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:81 | T0174 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:82 | T0175 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:83 | T0176 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:84 | T0177 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:85 | T0178 | change | `test/combo/b4_retry_migration_combo_test.dart:11` — [DiomanAuth.onRefresh × DiomanShare.option] 刷新前取消首发后跟随者仍完成刷新 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:86 | T0179 | change | `test/combo/source_migration_combo_test.dart:197` — [DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:87 | T0180 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:88 | T0181 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:89 | T0182 | change | `test/combo/b4_retry_migration_combo_test.dart:13` — [DiomanRetry.max × DiomanShare.option] 失败响应前取消首发后跟随者仍外层重试成功 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:91 | T0184 | change | `test/combo/b4_retry_migration_combo_test.dart:17` — [DiomanRetry.max × DiomanShare.option] 鉴权与缓存共享组合在外层重试后正确结算 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:92 | T0185 | change | `test/combo/source_migration_combo_test.dart:111` — [DiomanKeyOptions.namespace × DiomanCache.option × DiomanShare.option] 账号隔离和 prepare 后请求体区分 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:94 | T0187 | keep | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:95 | T0188 | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:96 | T0189 | keep | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:97 | T0190 | keep | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:98 | T0191 | change | `test/combo/source_combo_test.dart:14` — [DiomanMock.mockUrl × DiomanCache.option × DiomanShare.option] 探测不缓存不共享，回落恢复两者 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:99 | T0192 | change | `test/combo/source_combo_test.dart:46` — [DiomanMock.routes × DiomanShare.option] 内联优先于 share 每个逻辑调用均处理，不触网 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:100 | T0193 | change | `test/combo/source_combo_test.dart:14` — [DiomanMock.mockUrl × DiomanCache.option × DiomanShare.option] 探测不缓存不共享，回落恢复两者 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:101 | T0194 | change | `test/combo/b4_retry_migration_combo_test.dart:19` — [DiomanMock.routes × DiomanRetry.max] 模拟探测回落在每次外层重试重新执行 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:102 | T0195 | change | `test/combo/b4_retry_migration_combo_test.dart:21` — [DiomanMock.routes × DiomanRetry.max] 内联模拟传输失败由外层重试恢复成功 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:103 | T0196 | change | `test/combo/b4_retry_migration_combo_test.dart:23` — [DiomanMock.routes × DiomanRetry.max] 内联模拟业务失败由自定义重试判定恢复 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:104 | T0197 | change | `test/combo/b4_retry_migration_combo_test.dart:25` — [DiomanMock.routes × DiomanRetry.max] 共享下模拟探测回落仍逐次重试执行 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:105 | T0198 | change | `test/combo/b4_retry_migration_combo_test.dart:27` — [DiomanMock.routes × DiomanRetry.max] 共享下内联模拟传输失败仍由外层重试恢复 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:106 | T0199 | change | `test/combo/b4_retry_migration_combo_test.dart:29` — [DiomanMock.routes × DiomanRetry.max] 共享下内联模拟业务失败仍由自定义判定恢复 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| combo.md:110 | T0203 | change | `test/combo/source_migration_combo_test.dart:197` — [DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:111 | T0204 | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| combo.md:112 | T0205 | change | `test/combo/source_migration_combo_test.dart:197` — [DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:113 | T0206 | change | `test/combo/source_migration_combo_test.dart:197` — [DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:114 | T0207 | change | `test/combo/source_migration_combo_test.dart:197` — [DiomanSharePolicy.start] FormData 首发取消跟随者沿用传输，嵌套信封只拆一层 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:117 | T0210 | keep | `test/combo/b4_retry_migration_combo_test.dart:31` — [DiomanRetry.max × DiomanShare.option] 外层重试中最新成功覆盖较早成功并统一结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:118 | T0211 | keep | `test/combo/b4_retry_migration_combo_test.dart:33` — [DiomanRetry.max × DiomanShare.option] 外层重试中竞速等待在途成功且不被旧失败提前结算 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:119 | T0212 | change | `test/combo/b4_retry_migration_combo_test.dart:35` — [DiomanRetry.max × DiomanShare.option] 竞速重试通知异常被隔离且各调用均正确落定 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:120 | T0213 | change | `test/combo/b4_retry_migration_combo_test.dart:37` — [DiomanRetry.max × DiomanShare.option] 最新策略重试判定异常保留原错误并清理 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:121 | T0214 | change | `test/combo/b4_retry_migration_combo_test.dart:41` — [DiomanRetry.max × DiomanShare.option] 竞速策略重试判定异常保留原错误并清理 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:122 | T0215 | change | `test/combo/b4_retry_migration_combo_test.dart:45` — [DiomanRetry.max × DiomanShare.option] 新调用加入外层重试当前尝试且不增加传输 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:123 | T0216 | change | `test/combo/b4_retry_migration_combo_test.dart:47` — [DiomanRetry.max × DiomanShare.option] 内部重试策略的外层通知按逻辑调用触发 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:124 | T0217 | keep | `test/combo/b4_retry_migration_combo_test.dart:49` — [DiomanRetry.max × DiomanShare.option] 内部重试耗尽后外层重试仍重新进入共享表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:125 | T0218 | change | `test/combo/b4_retry_migration_combo_test.dart:51` — [DiomanRetry.max × DiomanShare.option] 内部重试策略允许后到调用共享当前重放结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:126 | T0219 | change | `test/combo/b4_retry_migration_combo_test.dart:53` — [DiomanRetry.max × DiomanShare.option] 首发共享重试判定异常保留原错误并清理 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:146 | INV-15 | change | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:147 | INV-16 | change | `test/combo/source_migration_combo_test.dart:57` — [DiomanResponseFactory.envelope × DiomanCache.option] 信封开关自定义成功和单层解包 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| combo.md:151 | INV-20 | change | `test/combo/source_combo_test.dart:79` — [DiomanCache.option × DiomanOffline.maxWait] 离线缓存命中照常返回，未命中恢复后写缓存 | C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。 |
| integration.md:84 | INV-03 | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:60 | T0303 | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:61 | T0304 | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:62 | T0305 | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:63 | T0306 | keep | `test/boundary/cache_persist_boundary_test.dart:176` — [DiomanCache.clone] 写入快照隔离来源和返回值，扩展工厂保留标记 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:64 | T0307 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| rule.md:68 | T0311 | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:69 | T0312 | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:70 | T0313 | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:71 | T0314 | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:72 | T0315 | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:73 | T0316 | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| rule.md:76 | T0319 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:77 | T0320 | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:79 | T0322 | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:80 | T0323 | keep | `test/combo/source_migration_combo_test.dart:226` — [DiomanCache.clock] 插件级 DiomanClock 控制 TTL，零负有效期不钳制 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:81 | T0324 | keep | `test/boundary/source_options_boundary_test.dart:108` — [DiomanCache.option × DiomanShare.option] key false 方法否决与自定义方法和 shouldStore | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:82 | T0325 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:83 | T0326 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:152 | T0395 | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:153 | T0396 | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:155 | T0398 | change | `test/combo/b4_auth_migration_combo_test.dart:27` — [DiomanAuth.onRefresh × DiomanShare.option] 并发鉴权失败只刷新一次并共享重放成功 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:156 | T0399 | change | `test/combo/source_combo_test.dart:14` — [DiomanMock.mockUrl × DiomanCache.option × DiomanShare.option] 探测不缓存不共享，回落恢复两者 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:157 | T0400 | change | `test/combo/source_combo_test.dart:14` — [DiomanMock.mockUrl × DiomanCache.option × DiomanShare.option] 探测不缓存不共享，回落恢复两者 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:158 | T0401 | change | `test/combo/b4_auth_migration_combo_test.dart:27` — [DiomanAuth.onRefresh × DiomanShare.option] 并发鉴权失败只刷新一次并共享重放成功 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:159 | T0402 | change | `test/combo/source_combo_test.dart:222` — [DiomanRetry.max × DiomanMock.mockUrl] 每次尝试探测回落且 I7 嵌套请求体独立 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:160 | T0403 | change | `test/combo/source_combo_test.dart:222` — [DiomanRetry.max × DiomanMock.mockUrl] 每次尝试探测回落且 I7 嵌套请求体独立 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| rule.md:161 | T0404 | change | `test/combo/source_combo_test.dart:46` — [DiomanMock.routes × DiomanShare.option] 内联优先于 share 每个逻辑调用均处理，不触网 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:162 | T0405 | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:164 | T0407 | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:165 | T0408 | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:166 | T0409 | change | `test/combo/b4_retry_migration_combo_test.dart:21` — [DiomanMock.routes × DiomanRetry.max] 内联模拟传输失败由外层重试恢复成功 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:167 | T0410 | change | `test/combo/source_combo_test.dart:222` — [DiomanRetry.max × DiomanMock.mockUrl] 每次尝试探测回落且 I7 嵌套请求体独立 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:169 | T0412 | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:170 | T0413 | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:171 | T0414 | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:172 | T0415 | change | `test/boundary/source_review_boundary_test.dart:11` — [DiomanMock.mockUrl] 自审：path 内嵌 query 和独立 query 均保留 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:173 | T0416 | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:174 | T0417 | change | `test/boundary/mock_cancel_boundary_test.dart:10` — [DiomanMock.routes] 内联处理器异常原样抛出，不触发回落且外层收尾 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:175 | T0418 | change | `test/boundary/mock_cancel_boundary_test.dart:10` — [DiomanMock.routes] 内联处理器异常原样抛出，不触发回落且外层收尾 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:176 | T0419 | change | `test/rule/source_rule_test.dart:11` — [DiomanMock.routes] 默认生效，内联数据经工厂识别 business 且零触网 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:177 | T0420 | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:180 | T0429 | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:181 | T0430 | change | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:182 | T0431 | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:183 | T0432 | change | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:184 | T0433 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:217 | T0466 | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:218 | T0467 | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:219 | T0468 | keep | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:220 | T0469 | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:221 | T0470 | keep | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:222 | T0471 | change | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| rule.md:223 | T0472 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:224 | T0473 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:225 | T0474 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:226 | T0475 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:227 | T0476 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:228 | T0477 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:230 | T0479 | keep | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:231 | T0480 | change | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:233 | T0482 | keep | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 删除手工结算，按 next 自然落定及随后同 key 重发验证；原 keep 的 setter 部分不再适用。 |
| rule.md:234 | T0483 | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:235 | T0484 | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:237 | T0486 | change | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:238 | T0487 | keep | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:331 | DiomanCache.clear | keep | `test/boundary/source_boundary_test.dart:155` — [DiomanCacheApi.clear] clear 作废在途写入，屏障 finally 回收，remove 不复活 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:332 | DiomanCache.clone | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:333 | DiomanCache.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:334 | DiomanCache.expires | keep | `test/combo/source_migration_combo_test.dart:226` — [DiomanCache.clock] 插件级 DiomanClock 控制 TTL，零负有效期不钳制 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:335 | DiomanCache.maxEntries | change | `test/boundary/source_boundary_test.dart:184` — [DiomanCache.maxEntries] 新结果淘汰后旧在途不得回写，LRU 命中提升和不限容量 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:336 | DiomanCache.name | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:337 | DiomanCache.new(now) | keep | `test/combo/source_migration_combo_test.dart:226` — [DiomanCache.clock] 插件级 DiomanClock 控制 TTL，零负有效期不钳制 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:338 | DiomanCache.new(shouldCache) | keep | `test/boundary/source_options_boundary_test.dart:108` — [DiomanCache.option × DiomanShare.option] key false 方法否决与自定义方法和 shouldStore | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:339 | DiomanCache.onRequest | change | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:340 | DiomanCache.onResponse | change | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:341 | DiomanCache.onResponse#canceled-response | change | `test/boundary/source_lifecycle_boundary_test.dart:39` — [DiomanCache.shouldStore] 取消的在途响应不缓存且屏障回收 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:342 | DiomanCache.persist | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:343 | DiomanCache.pluginName | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:344 | DiomanCache.remove | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:345 | DiomanCacheOptions.cachePolicy | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:346 | DiomanCacheOptions.clone | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:347 | DiomanCacheOptions.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:348 | DiomanCacheOptions.expires | keep | `test/combo/source_migration_combo_test.dart:226` — [DiomanCache.clock] 插件级 DiomanClock 控制 TTL，零负有效期不钳制 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:351 | DiomanCacheOptions.shouldCache | keep | `test/boundary/source_options_boundary_test.dart:108` — [DiomanCache.option × DiomanShare.option] key false 方法否决与自定义方法和 shouldStore | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:352 | DiomanCacheOptions.shouldStore | change | `test/combo/source_migration_combo_test.dart:13` — [DiomanCache.shouldStore] 归一化判定表与请求级覆盖优先级 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:353 | DiomanCachePersist.erase | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:354 | DiomanCachePersist.read | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:355 | DiomanCachePersist.remove | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:356 | DiomanCachePersist.write | keep | `test/boundary/cache_persist_boundary_test.dart:41` — [DiomanCachePersist.write] clear 等待在途持久化写入后 erase，错误原样且尾链可恢复 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:357 | DiomanCachePolicy.both | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:358 | DiomanCachePolicy.memo | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:360 | DiomanCachePolicy.persist | keep | `test/rule/source_rule_test.dart:160` — [DiomanCache.cachePolicy] memo persist both 分层，持久化命中提升且惰性过期 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:361 | DiomanClonePolicy.deep | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:362 | DiomanClonePolicy.none | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:363 | DiomanClonePolicy.shallow | keep | `test/boundary/source_options_boundary_test.dart:156` — [DiomanCache.clone] deep 保留非字符串键隔离嵌套，shallow List 标量及非法策略 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:425 | DiomanMockAdapter.extraKey | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:426 | DiomanMockAdapter.fetch | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:428 | DiomanMockAdapter.new(enabled) | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:429 | DiomanMockAdapter.new(fallbackWhen) | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:431 | DiomanMockAdapter.new(mockUrl) | change | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:432 | DiomanMockAdapter.new(routes) | change | `test/rule/source_rule_test.dart:11` — [DiomanMock.routes] 默认生效，内联数据经工厂识别 business 且零触网 | C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。 |
| rule.md:433 | DiomanMockOptions.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:434 | DiomanMockOptions.fallbackWhen | keep | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:435 | DiomanMockOptions.mockUrl | keep | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:436 | DiomanMockOptions.routes | keep | `test/boundary/source_options_boundary_test.dart:70` — [DiomanMock.option] 请求级路由地址覆盖，network 默认回落，判定抛错原样 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:437 | defaultFallback | change | `test/boundary/mock_cancel_boundary_test.dart:27` — [DiomanMock.fallbackWhen] 探测取消不回落不调用判定，内联异步取消消费迟到错误 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:445 | DiomanOffline.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:446 | DiomanOffline.flush | change | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:447 | DiomanOffline.maxQueueSize | change | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:448 | DiomanOffline.maxWait | keep | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:449 | DiomanOffline.name | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:450 | DiomanOffline.new(isOnline) | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:451 | DiomanOffline.new(onConnectivityChanged) | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:452 | DiomanOffline.new(shouldQueue) | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:453 | DiomanOffline.onRequest | change | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:454 | DiomanOffline.pending | change | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:455 | DiomanOffline.pluginName | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:456 | DiomanOfflineOptions.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:457 | DiomanOfflineOptions.maxQueueSize | change | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:458 | DiomanOfflineOptions.maxWait | keep | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:459 | DiomanOfflineOptions.shouldQueue | keep | `test/rule/source_rule_test.dart:182` — [DiomanOfflineApi.flush] 离线排队恢复和手动 flush，shouldQueue false 放行 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:498 | DiomanShare.enabled | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:499 | DiomanShare.interval | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:500 | DiomanShare.name | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:501 | DiomanShare.onError | change | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:502 | DiomanShare.onRequest | change | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:503 | DiomanShare.onResponse | change | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:504 | DiomanShare.pluginName | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:505 | DiomanShare.policy | keep | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:506 | DiomanShare.retries | keep | `test/boundary/share_replay_boundary_test.dart:70` — [DiomanShare.retries] 默认内部重试三次，零负次数不重发 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:507 | DiomanShareOptions.enabled | keep | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:508 | DiomanShareOptions.interval | keep | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:509 | DiomanShareOptions.policy | keep | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:510 | DiomanShareOptions.retries | keep | `test/boundary/source_boundary_test.dart:13` — [DiomanSharePolicy.start] 首发取消不连累跟随者，最后离开才取消且清理 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:511 | DiomanSharePolicy.end | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:513 | DiomanSharePolicy.race | keep | `test/rule/source_rule_test.dart:58` — [DiomanShare.policy] end 最新失败归所有，race 首成功与全失败最后结果 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:514 | DiomanSharePolicy.retry | keep | `test/boundary/share_replay_boundary_test.dart:13` — [DiomanShare.retries] 内部重放独立保护 I7 嵌套请求体，首发次数与间隔覆盖 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| rule.md:515 | DiomanSharePolicy.start | keep | `test/rule/source_rule_test.dart:42` — [DiomanShare.policy] start 只发一次，跟随者为相同只读 R，省略不开启 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:115 | DiomanCache.dispose | keep | `test/boundary/cache_persist_boundary_test.dart:10` — [DiomanCachePersist.read] 慢读取被 clear remove dispose 作废，旧读取不回填 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:116 | DiomanCache.ordering | change | `test/boundary/source_options_boundary_test.dart:13` — [DiomanPlugin.enabled] 四 source 安装禁用与固定位置和非法请求选项 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| unit.md:196 | DiomanOffline.dispose | keep | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:197 | DiomanOffline.ordering | change | `test/combo/source_migration_combo_test.dart:143` — [DiomanLoadingApi.activeCount × DiomanCache.option × DiomanShare.option] 缓存命中和跟随者均计逻辑请求，失败释放外层 | 固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。 |
| unit.md:198 | DiomanOfflineException.reason | change | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:200 | DiomanOfflineReason.disposed | change | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:201 | DiomanOfflineReason.queueFull | change | `test/boundary/source_boundary_test.dart:269` — [DiomanOffline.maxQueueSize] 队满挤出最早，0 不限，请求级覆盖上限 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:202 | DiomanOfflineReason.timeout | change | `test/boundary/source_boundary_test.dart:214` — [DiomanOffline.maxWait] timeout cancel flush dispose 全出口清计时与订阅 I3 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
| unit.md:209 | DiomanShare.dispose | keep | `test/boundary/source_options_boundary_test.dart:229` — [DiomanShare.retries] retry 间隔取消与耗尽释放条目，dispose 所有策略清表 | 按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。 |
