| 迁移来源行 | 原 ID | 分类 | 新用例（文件:行 / 完整标题） | 范围说明 |
|---|---|---|---|---|
| [boundary.md:57](../reference/pipeline-migration/boundary.md#L57) | T0052 | keep | `test/boundary/stateless_prepare_boundary_test.dart:66` — [DiomanFilter] FormData、Stream 和非 Map 原样；无剔除不打补丁 |  |
| [boundary.md:65](../reference/pipeline-migration/boundary.md#L65) | T0060 | keep | `test/boundary/stateless_outer_boundary_test.dart:34` — [DiomanLoading.delay] 显示前结束、延迟到期和 0→1 决定窗口 |  |
| [boundary.md:66](../reference/pipeline-migration/boundary.md#L66) | T0061 | keep | `test/boundary/stateless_outer_boundary_test.dart:94` — [DiomanLoadingApi] dispose 取消显示/隐藏、立即配对，在途及旧链不再通知 |  |
| [boundary.md:67](../reference/pipeline-migration/boundary.md#L67) | T0062 | keep | `test/boundary/stateless_outer_boundary_test.dart:94` — [DiomanLoadingApi] dispose 取消显示/隐藏、立即配对，在途及旧链不再通知 |  |
| [boundary.md:68](../reference/pipeline-migration/boundary.md#L68) | T0063 | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [boundary.md:77](../reference/pipeline-migration/boundary.md#L77) | T0073 | keep | `test/boundary/stateless_prepare_boundary_test.dart:25` — [DiomanRepath.pattern] URL 只处理路径，缺键、无捕获和空捕获保持原样 |  |
| [boundary.md:78](../reference/pipeline-migration/boundary.md#L78) | T0074 | keep | `test/rule/stateless_prepare_rule_test.dart:22` — [DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费 |  |
| [boundary.md:79](../reference/pipeline-migration/boundary.md#L79) | T0075 | keep | `test/boundary/stateless_prepare_boundary_test.dart:25` — [DiomanRepath.pattern] URL 只处理路径，缺键、无捕获和空捕获保持原样 |  |
| [boundary.md:98](../reference/pipeline-migration/boundary.md#L98) | T0094 | keep | `test/boundary/stateless_prepare_boundary_test.dart:118` — [DiomanTimeout.probe] 缺档无补丁，空档保留请求超时，probe 错误原样抛出 |  |
| [combo.md:17](../reference/pipeline-migration/combo.md#L17) | T0109 | keep | `test/combo/stateless_combo_test.dart:52` — [DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:46](../reference/pipeline-migration/combo.md#L46) | T0139 | keep | `test/combo/stateless_combo_test.dart:52` — [DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:47](../reference/pipeline-migration/combo.md#L47) | T0140 | change | `test/combo/stateless_combo_test.dart:180` — [DiomanLoading × DiomanNotify] 取消与 source 短路仍成对、无多余通知 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:75](../reference/pipeline-migration/combo.md#L75) | T0168 | change | `test/combo/stateless_combo_test.dart:180` — [DiomanLoading × DiomanNotify] 取消与 source 短路仍成对、无多余通知 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:93](../reference/pipeline-migration/combo.md#L93) | T0186 | keep | `test/combo/stateless_combo_test.dart:126` — [DiomanLoading × DiomanNotify] 多次 next 仅一个 loading 周期与最终通知，I2/I4 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:94](../reference/pipeline-migration/combo.md#L94) | T0187 | keep | `test/combo/stateless_combo_test.dart:21` — [DiomanLoadingApi.activeCount] 并发成功失败各自落定，任何请求都不能遗留括号 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:95](../reference/pipeline-migration/combo.md#L95) | T0188 | change | `test/combo/stateless_combo_test.dart:155` — [DiomanLoading × DiomanNotify] 共享同一响应的两个逻辑请求按 ctx.id 分开通知 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:96](../reference/pipeline-migration/combo.md#L96) | T0189 | keep | `test/combo/stateless_combo_test.dart:21` — [DiomanLoadingApi.activeCount] 并发成功失败各自落定，任何请求都不能遗留括号 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:97](../reference/pipeline-migration/combo.md#L97) | T0190 | keep | `test/combo/stateless_combo_test.dart:21` — [DiomanLoadingApi.activeCount] 并发成功失败各自落定，任何请求都不能遗留括号 | 仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。 |
| [combo.md:107](../reference/pipeline-migration/combo.md#L107) | T0200 | change | `test/rule/stateless_outer_rule_test.dart:105` — [DiomanNotify.stringify] 默认忽略成功、取消和 silent，失败消息与空消息回退 | 改读最终归一化结果。 |
| [integration.md:14](../reference/pipeline-migration/integration.md#L14) | T0095 | keep | `test/integration/timeout_effective_integration_test.dart:118` — [DiomanTimeouts.receive] $mode 停顿按插件值超时 |  |
| [integration.md:15](../reference/pipeline-migration/integration.md#L15) | T0096 | keep | `test/integration/timeout_effective_integration_test.dart:127` — [DiomanTimeouts.receive] 分块间隔小于超时即成功，总时长可超过超时 |  |
| [integration.md:16](../reference/pipeline-migration/integration.md#L16) | T0097 | keep | `test/integration/timeout_effective_integration_test.dart:118` — [DiomanTimeouts.receive] $mode 停顿按插件值超时 |  |
| [integration.md:17](../reference/pipeline-migration/integration.md#L17) | T0098 | keep | `test/integration/timeout_effective_integration_test.dart:137` — [DiomanTimeoutOptions.timeouts] 请求级收紧接收时限实际生效 |  |
| [integration.md:18](../reference/pipeline-migration/integration.md#L18) | T0099 | keep | `test/integration/timeout_effective_integration_test.dart:148` — [DiomanTimeoutOptions.timeouts] 请求级放宽接收时限实际生效 |  |
| [integration.md:19](../reference/pipeline-migration/integration.md#L19) | T0100 | keep | `test/integration/timeout_effective_integration_test.dart:174` — [DiomanTimeouts.send] 正常读取小请求体时成功 |  |
| [integration.md:20](../reference/pipeline-migration/integration.md#L20) | T0101 | keep | `test/integration/timeout_effective_integration_test.dart:161` — [DiomanTimeouts.send] 发送缓冲阻塞时真实超时 |  |
| [integration.md:90](../reference/pipeline-migration/integration.md#L90) | DiomanTimeouts.connect#effective | keep | `test/boundary/stateless_prepare_boundary_test.dart:12` — [DiomanTimeouts.connect] 档位补丁送达 adapter，连接超时按 timeout 归类 | 配置/归类已测；真实 SYN 黑洞计时留 B7 netem，不声称回环验证了连接超时。 |
| [integration.md:91](../reference/pipeline-migration/integration.md#L91) | DiomanTimeouts.receive#effective | keep | `test/integration/timeout_effective_integration_test.dart:118` — [DiomanTimeouts.receive] $mode 停顿按插件值超时 |  |
| [integration.md:92](../reference/pipeline-migration/integration.md#L92) | DiomanTimeouts.send#effective | keep | `test/integration/timeout_effective_integration_test.dart:161` — [DiomanTimeouts.send] 发送缓冲阻塞时真实超时 |  |
| [rule.md:90](../reference/pipeline-migration/rule.md#L90) | T0333 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:91](../reference/pipeline-migration/rule.md#L91) | T0334 | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:92](../reference/pipeline-migration/rule.md#L92) | T0335 | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:93](../reference/pipeline-migration/rule.md#L93) | T0336 | keep | `test/rule/envs_rule_test.dart:65` — [EnvRule.config] 空地址、默认 json 保留宿主，未命中与禁用完全不修改 |  |
| [rule.md:94](../reference/pipeline-migration/rule.md#L94) | T0337 | change | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:95](../reference/pipeline-migration/rule.md#L95) | T0338 | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:96](../reference/pipeline-migration/rule.md#L96) | T0339 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:97](../reference/pipeline-migration/rule.md#L97) | T0340 | keep | `test/rule/envs_rule_test.dart:65` — [EnvRule.config] 空地址、默认 json 保留宿主，未命中与禁用完全不修改 |  |
| [rule.md:98](../reference/pipeline-migration/rule.md#L98) | T0341 | keep | `test/rule/envs_rule_test.dart:65` — [EnvRule.config] 空地址、默认 json 保留宿主，未命中与禁用完全不修改 |  |
| [rule.md:99](../reference/pipeline-migration/rule.md#L99) | T0342 | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:100](../reference/pipeline-migration/rule.md#L100) | T0343 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:101](../reference/pipeline-migration/rule.md#L101) | T0344 | change | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:102](../reference/pipeline-migration/rule.md#L102) | T0345 | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:103](../reference/pipeline-migration/rule.md#L103) | T0346 | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:104](../reference/pipeline-migration/rule.md#L104) | T0347 | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:119](../reference/pipeline-migration/rule.md#L119) | T0362 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:120](../reference/pipeline-migration/rule.md#L120) | T0363 | keep | `test/combo/stateless_combo_test.dart:52` — [DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号 |  |
| [rule.md:121](../reference/pipeline-migration/rule.md#L121) | T0364 | keep | `test/boundary/stateless_outer_boundary_test.dart:62` — [DiomanLoading.delayClose] 新请求取消隐藏窗口，1→0 请求决定关闭延迟 |  |
| [rule.md:122](../reference/pipeline-migration/rule.md#L122) | T0365 | keep | `test/boundary/stateless_outer_boundary_test.dart:34` — [DiomanLoading.delay] 显示前结束、延迟到期和 0→1 决定窗口 |  |
| [rule.md:123](../reference/pipeline-migration/rule.md#L123) | T0366 | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:124](../reference/pipeline-migration/rule.md#L124) | T0367 | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:125](../reference/pipeline-migration/rule.md#L125) | T0368 | keep | `test/rule/stateless_outer_rule_test.dart:77` — [DiomanLoadingOptions.onChanged] 独占回调替代默认且两个延迟都生效 |  |
| [rule.md:126](../reference/pipeline-migration/rule.md#L126) | T0369 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:178](../reference/pipeline-migration/rule.md#L178) | T0427 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:179](../reference/pipeline-migration/rule.md#L179) | T0428 | keep | `test/rule/stateless_outer_rule_test.dart:140` — [DiomanNotify.option] true 开启、自定义 stringify 与空串关闭，I4 按 ctx.id 记录 |  |
| [rule.md:185](../reference/pipeline-migration/rule.md#L185) | T0434 | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:186](../reference/pipeline-migration/rule.md#L186) | T0435 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:187](../reference/pipeline-migration/rule.md#L187) | T0436 | keep | `test/rule/stateless_prepare_rule_test.dart:22` — [DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费 |  |
| [rule.md:188](../reference/pipeline-migration/rule.md#L188) | T0437 | keep | `test/rule/stateless_prepare_rule_test.dart:37` — [DiomanRepath.option] 开关、字段继承、自定义模式与保留来源 |  |
| [rule.md:189](../reference/pipeline-migration/rule.md#L189) | T0438 | keep | `test/rule/stateless_prepare_rule_test.dart:37` — [DiomanRepath.option] 开关、字段继承、自定义模式与保留来源 |  |
| [rule.md:190](../reference/pipeline-migration/rule.md#L190) | T0439 | keep | `test/rule/stateless_prepare_rule_test.dart:37` — [DiomanRepath.option] 开关、字段继承、自定义模式与保留来源 |  |
| [rule.md:239](../reference/pipeline-migration/rule.md#L239) | T0488 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:240](../reference/pipeline-migration/rule.md#L240) | T0489 | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:241](../reference/pipeline-migration/rule.md#L241) | T0490 | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:242](../reference/pipeline-migration/rule.md#L242) | T0491 | keep | `test/integration/timeout_effective_integration_test.dart:148` — [DiomanTimeoutOptions.timeouts] 请求级放宽接收时限实际生效 |  |
| [rule.md:243](../reference/pipeline-migration/rule.md#L243) | T0492 | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:244](../reference/pipeline-migration/rule.md#L244) | T0493 | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:245](../reference/pipeline-migration/rule.md#L245) | T0494 | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 | 旧 keep 文字中“true 可点亮插件级 false”与规格 §0.2 冲突：按新规格总开关不允许请求重启。 |
| [rule.md:246](../reference/pipeline-migration/rule.md#L246) | T0495 | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:247](../reference/pipeline-migration/rule.md#L247) | T0496 | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:364](../reference/pipeline-migration/rule.md#L364) | DiomanEnvs.apply | change | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:365](../reference/pipeline-migration/rule.md#L365) | DiomanEnvs.config | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:366](../reference/pipeline-migration/rule.md#L366) | DiomanEnvs.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:367](../reference/pipeline-migration/rule.md#L367) | DiomanEnvs.new(dio) | change | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:368](../reference/pipeline-migration/rule.md#L368) | DiomanEnvs.new(enabled) | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:369](../reference/pipeline-migration/rule.md#L369) | DiomanEnvs.onRequest | change | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:370](../reference/pipeline-migration/rule.md#L370) | DiomanEnvs.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:371](../reference/pipeline-migration/rule.md#L371) | DiomanEnvs.rules | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:372](../reference/pipeline-migration/rule.md#L372) | DiomanEnvsOptions.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:373](../reference/pipeline-migration/rule.md#L373) | EnvRule.config | keep | `test/rule/envs_rule_test.dart:65` — [EnvRule.config] 空地址、默认 json 保留宿主，未命中与禁用完全不修改 |  |
| [rule.md:374](../reference/pipeline-migration/rule.md#L374) | EnvRule.rule | keep | `test/rule/envs_rule_test.dart:21` — [DiomanEnvs.setup] 首个命中、全部旧字段合并、请求期不求值、不进链 |  |
| [rule.md:375](../reference/pipeline-migration/rule.md#L375) | DiomanFilter.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:376](../reference/pipeline-migration/rule.md#L376) | DiomanFilter.ignoreKeys | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:377](../reference/pipeline-migration/rule.md#L377) | DiomanFilter.ignoreValues | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:378](../reference/pipeline-migration/rule.md#L378) | DiomanFilter.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:379](../reference/pipeline-migration/rule.md#L379) | DiomanFilter.onRequest | change | `test/rule/stateless_prepare_rule_test.dart:64` — [DiomanFilter.defaultPredicate] C9 剔除空值与 NaN，保留零 false 和嵌套字段 |  |
| [rule.md:380](../reference/pipeline-migration/rule.md#L380) | DiomanFilter.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:381](../reference/pipeline-migration/rule.md#L381) | DiomanFilter.predicate | change | `test/rule/stateless_prepare_rule_test.dart:64` — [DiomanFilter.defaultPredicate] C9 剔除空值与 NaN，保留零 false 和嵌套字段 |  |
| [rule.md:382](../reference/pipeline-migration/rule.md#L382) | DiomanFilterOptions.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:383](../reference/pipeline-migration/rule.md#L383) | DiomanFilterOptions.ignoreKeys | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:384](../reference/pipeline-migration/rule.md#L384) | DiomanFilterOptions.ignoreValues | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:385](../reference/pipeline-migration/rule.md#L385) | DiomanFilterOptions.predicate | keep | `test/rule/stateless_prepare_rule_test.dart:93` — [DiomanFilter.option] 豁免并集、谓词覆盖与空字段继承 |  |
| [rule.md:389](../reference/pipeline-migration/rule.md#L389) | DiomanLoading.activeCount | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:390](../reference/pipeline-migration/rule.md#L390) | DiomanLoading.delay | keep | `test/boundary/stateless_outer_boundary_test.dart:34` — [DiomanLoading.delay] 显示前结束、延迟到期和 0→1 决定窗口 |  |
| [rule.md:391](../reference/pipeline-migration/rule.md#L391) | DiomanLoading.delayClose | keep | `test/boundary/stateless_outer_boundary_test.dart:62` — [DiomanLoading.delayClose] 新请求取消隐藏窗口，1→0 请求决定关闭延迟 |  |
| [rule.md:392](../reference/pipeline-migration/rule.md#L392) | DiomanLoading.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:393](../reference/pipeline-migration/rule.md#L393) | DiomanLoading.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:394](../reference/pipeline-migration/rule.md#L394) | DiomanLoading.new(onChanged) | keep | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:395](../reference/pipeline-migration/rule.md#L395) | DiomanLoading.onError | change | `test/combo/stateless_combo_test.dart:52` — [DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号 |  |
| [rule.md:396](../reference/pipeline-migration/rule.md#L396) | DiomanLoading.onRequest | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:397](../reference/pipeline-migration/rule.md#L397) | DiomanLoading.onResponse | change | `test/combo/stateless_combo_test.dart:52` — [DiomanLoadingApi.activeCount] credential 等待期间已计数，失败出口均释放自己的括号 |  |
| [rule.md:398](../reference/pipeline-migration/rule.md#L398) | DiomanLoading.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:399](../reference/pipeline-migration/rule.md#L399) | DiomanLoadingOptions.delay | keep | `test/boundary/stateless_outer_boundary_test.dart:34` — [DiomanLoading.delay] 显示前结束、延迟到期和 0→1 决定窗口 |  |
| [rule.md:400](../reference/pipeline-migration/rule.md#L400) | DiomanLoadingOptions.delayClose | keep | `test/boundary/stateless_outer_boundary_test.dart:62` — [DiomanLoading.delayClose] 新请求取消隐藏窗口，1→0 请求决定关闭延迟 |  |
| [rule.md:401](../reference/pipeline-migration/rule.md#L401) | DiomanLoadingOptions.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:402](../reference/pipeline-migration/rule.md#L402) | DiomanLoadingOptions.onChanged | change | `test/rule/stateless_outer_rule_test.dart:21` — [DiomanLoadingApi.activeCount] 同回调并发聚合，换回调独立计数，I2 成对 |  |
| [rule.md:438](../reference/pipeline-migration/rule.md#L438) | DiomanNotify.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:439](../reference/pipeline-migration/rule.md#L439) | DiomanNotify.notify | change | `test/rule/stateless_outer_rule_test.dart:105` — [DiomanNotify.stringify] 默认忽略成功、取消和 silent，失败消息与空消息回退 |  |
| [rule.md:440](../reference/pipeline-migration/rule.md#L440) | DiomanNotify.onError | change | `test/rule/stateless_outer_rule_test.dart:105` — [DiomanNotify.stringify] 默认忽略成功、取消和 silent，失败消息与空消息回退 |  |
| [rule.md:441](../reference/pipeline-migration/rule.md#L441) | DiomanNotify.onRequest | change | `test/rule/stateless_outer_rule_test.dart:140` — [DiomanNotify.option] true 开启、自定义 stringify 与空串关闭，I4 按 ctx.id 记录 |  |
| [rule.md:442](../reference/pipeline-migration/rule.md#L442) | DiomanNotify.onResponse | change | `test/rule/stateless_outer_rule_test.dart:140` — [DiomanNotify.option] true 开启、自定义 stringify 与空串关闭，I4 按 ctx.id 记录 |  |
| [rule.md:443](../reference/pipeline-migration/rule.md#L443) | DiomanNotify.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:444](../reference/pipeline-migration/rule.md#L444) | DiomanNotify.stringify | change | `test/rule/stateless_outer_rule_test.dart:105` — [DiomanNotify.stringify] 默认忽略成功、取消和 silent，失败消息与空消息回退 |  |
| [rule.md:460](../reference/pipeline-migration/rule.md#L460) | DiomanRepath.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:461](../reference/pipeline-migration/rule.md#L461) | DiomanRepath.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:462](../reference/pipeline-migration/rule.md#L462) | DiomanRepath.onRequest | change | `test/rule/stateless_prepare_rule_test.dart:22` — [DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费 |  |
| [rule.md:463](../reference/pipeline-migration/rule.md#L463) | DiomanRepath.pattern | keep | `test/rule/stateless_prepare_rule_test.dart:22` — [DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费 |  |
| [rule.md:464](../reference/pipeline-migration/rule.md#L464) | DiomanRepath.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:465](../reference/pipeline-migration/rule.md#L465) | DiomanRepath.removeKey | keep | `test/rule/stateless_prepare_rule_test.dart:22` — [DiomanRepath] 三语法、query 优先、重复替换、编码和默认 query 消费 |  |
| [rule.md:466](../reference/pipeline-migration/rule.md#L466) | DiomanRepathOptions.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:467](../reference/pipeline-migration/rule.md#L467) | DiomanRepathOptions.pattern | keep | `test/rule/stateless_prepare_rule_test.dart:37` — [DiomanRepath.option] 开关、字段继承、自定义模式与保留来源 |  |
| [rule.md:468](../reference/pipeline-migration/rule.md#L468) | DiomanRepathOptions.removeKey | keep | `test/rule/stateless_prepare_rule_test.dart:37` — [DiomanRepath.option] 开关、字段继承、自定义模式与保留来源 |  |
| [rule.md:516](../reference/pipeline-migration/rule.md#L516) | DiomanTimeout.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:517](../reference/pipeline-migration/rule.md#L517) | DiomanTimeout.name | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:518](../reference/pipeline-migration/rule.md#L518) | DiomanTimeout.new(probe) | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:519](../reference/pipeline-migration/rule.md#L519) | DiomanTimeout.onRequest | change | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:520](../reference/pipeline-migration/rule.md#L520) | DiomanTimeout.pluginName | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:521](../reference/pipeline-migration/rule.md#L521) | DiomanTimeout.timeouts | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:522](../reference/pipeline-migration/rule.md#L522) | DiomanTimeoutOptions.enabled | keep | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [rule.md:523](../reference/pipeline-migration/rule.md#L523) | DiomanTimeoutOptions.timeouts | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:524](../reference/pipeline-migration/rule.md#L524) | DiomanTimeouts.connect | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:525](../reference/pipeline-migration/rule.md#L525) | DiomanTimeouts.receive | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:526](../reference/pipeline-migration/rule.md#L526) | DiomanTimeouts.send | keep | `test/rule/stateless_prepare_rule_test.dart:148` — [DiomanTimeout.option] 按档并集、单档替换、非空覆盖和请求关闭 |  |
| [rule.md:527](../reference/pipeline-migration/rule.md#L527) | NetworkQuality.excellent | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:528](../reference/pipeline-migration/rule.md#L528) | NetworkQuality.good | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:529](../reference/pipeline-migration/rule.md#L529) | NetworkQuality.none | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [rule.md:530](../reference/pipeline-migration/rule.md#L530) | NetworkQuality.poor | keep | `test/rule/stateless_prepare_rule_test.dart:125` — [DiomanTimeout.timeouts] 默认四档和 probe 每请求一次 |  |
| [unit.md:173](../reference/pipeline-migration/unit.md#L173) | DiomanLoading.dispose | keep | `test/boundary/stateless_outer_boundary_test.dart:94` — [DiomanLoadingApi] dispose 取消显示/隐藏、立即配对，在途及旧链不再通知 |  |
| [unit.md:174](../reference/pipeline-migration/unit.md#L174) | DiomanLoading.ordering | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |
| [unit.md:195](../reference/pipeline-migration/unit.md#L195) | DiomanNotify.ordering | change | `test/rule/stateless_prepare_rule_test.dart:183` — [DiomanPlugin.enabled] 六插件名称、固定位置、总开关与类型化键 |  |

逐行验证：{'boundary.md': 9, 'combo.md': 10, 'integration.md': 10, 'rule.md': 107, 'unit.md': 3}；共 139 行，每行目标测试唯一存在。
