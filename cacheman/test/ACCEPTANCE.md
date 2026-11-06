# cacheman 阶段 0 / 1a / 1b / 2 及全量评审修复验收矩阵

在指定 worktree 根目录复现（不切换目录）：

```powershell
flutter analyze
flutter test --coverage
dart run tool/coverage.dart --min=100
dart run tool/check_acceptance.dart
flutter analyze example
```

最近一次运行：**139/139 测试通过；lib 行覆盖率 561/561（100.00%），1 行豁免**；验收引用 207 条全部有效。
包及 example analyze 无问题。生成日期：2026-11-05（会话日期，Asia/Shanghai）。
commit 基线：`8ad38313`（全量评审 R1–R6 修复，主会话终审复跑）。
此摘要由最终命令验证；coverage/ 已在原有 .gitignore 中，不纳入版本控制。

名称格式为“test/文件.dart :: group > test”，与源码注册名称完全一致；参数化名称列出实际展开值。
`tool/check_acceptance.dart` 以轻量词法器排除注释/字符串里的括号，跟踪group深度，展开字面量列表
参数；既检查引用存在，也检查没有漏掉任何已注册测试。不能识别的动态名称明确报错。
本次使用同一提取器生成新增行，随后以自检工具逐项验证所有引用存在且无注册用例遗漏。

## 需求和不变量

| ID | 需求 / 不变量 | 来源 | 用例（文件 :: 测试名，可多条） | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| INV-01 | 原语是唯一后端接触点；extends 薄封装不隐式创建 GetStorage | SKILL 不变量 | `test/cacheman_primitives_test.dart :: all primitives override default backend; CRUD is synchronous` | 子类内存后端 | 通过 |
| INV-01b | 只转发构造参数的子类（默认构造）保留 get_storage 共享 Hub、watch 与增量索引；自带原语须经 `Cacheman.custom` | 用户需求 | `test/cacheman_test.dart :: forwarding subclass keeps get_storage hub, watch and incremental index` | 集成·真 get_storage | 通过 |
| INV-02 | 同步构造/同步 CRUD，ensureInitialized 是唯一公开 Future 边界；失败 init 不标记成功 | SKILL 不变量 | `test/hub_test.dart :: failed initialization leaves sync and async writes guarded until retry succeeds` | 子类内存后端 | 通过 |
| INV-03 | GetStorage late final；带 path 的首次访问初始化，不调用静态 GetStorage.init | SKILL 不变量 | `test/cacheman_primitives_test.dart :: lazy default initialization still loads the explicitly supplied path` | 集成·真 get_storage | 通过 |
| INV-04 | 不缓存读取的值；多个同步/异步后端并行，调用处自行选择，无自动路由 | 用户需求 | `test/hub_test.dart :: sync and async backends run in parallel and never cache read values` | 子类内存后端 | 通过 |
| INV-05 | AsyncCacheman 枚举每次从 keysRaw 取键，无自有键集合缓存 | SKILL 不变量 | `test/async_cacheman_test.dart :: enckey and codeable roundtrip separately; fresh enumeration sees external writes` | 子类内存后端 | 通过 |
| INV-06 | 同步键索引 version 自愈；同 container/namespace 多实例及外部写删可见 | 阶段 1b | `test/hub_test.dart :: real shared container indexes heal after peers and external changes` | 集成·真 get_storage | 通过 |
| INV-07 | 单个 Hub 只订阅一次；单实例连续 N 写 O(1) 维护，无重复全扫 | 阶段 1b | `test/hub_test.dart :: one shared subscription and N local writes need no index rebuild` | 子类内存后端 | 通过 |
| INV-08 | 重入外部写不能将部分索引错误标新；回调切 namespace 安全 | 阶段 1b | `test/hub_test.dart :: reentrant peer writes do not bless an incomplete owned-key index` | 子类内存后端 | 通过 |
| INV-09 | namespace 先转义 % 再转义 :；getter 为转义前缀；不相互误删 | SKILL 不变量 | `test/cacheman_test.dart :: review fixes > namespace with "%" is escaped and isolated from the literal-prefixed one`<br>`test/cacheman_test.dart :: review fixes > namespaces containing ":" do not collide or erase each other` | 集成·真 get_storage | 通过 |
| INV-10 | 两个键映射各上限1024，溢出整体清空，切 namespace 同时清空 | SKILL 不变量 | `test/hub_test.dart :: both key maps clear on 1024 overflow and namespace resets both` | 子类内存后端 | 通过 |
| INV-11 | 键 codec null 回退原键且不缓存失败；enckey 要求成功解码才拥有键 | SKILL 不变量 | `test/hub_test.dart :: null key decoding falls back without memoizing and excludes unowned keys` | 子类内存后端 | 通过 |
| INV-12 | enckey 缺 codec、codeable 缺 codec 警告并退化；keyCodec 与 value codec 独立 | SKILL 不变量 | `test/async_cacheman_test.dart :: missing codecs degrade to plain keys and values` | 子类内存后端 | 通过 |
| INV-13 | createdAt 是信封标记；foreign expireAt 数据不懒删/purge；enckey-only erase 保护外部键 | SKILL 不变量 | `test/hub_test.dart :: sync enckey-only erase preserves foreign keys and unmarked envelopes never expire` | 子类内存后端 | 通过 |
| INV-14 | sliding 在剩余 ttl <=90% 时续期；保留 createdAt/ttl，原实体不变 | SKILL 不变量 | `test/hub_test.dart :: sync sliding includes exactly 90 percent and preserves the original entity` | 子类内存后端 | 通过 |
| INV-15 | raw 只接受 String；跳过信封/值codec/TTL/purge；仍按namespace/enckey隔离 | SKILL 不变量 | `test/async_cacheman_test.dart :: raw rejects non-String, bypasses codec/serialization/expiry and purge` | 子类内存后端 | 通过 |
| INV-16 | readonly 在 raw/entity 分支前检查存在性；存 null 算存在；probe 无副作用 | SKILL 不变量 | `test/hub_test.dart :: readonly raw null foreign and expired probes have no renewal side effects` | 子类内存后端 | 通过 |
| INV-17 | 同步 force 只重试底层同步写异常；成功重试维护索引；编码/Future 失败不重试 | SKILL 不变量 | `test/cacheman_primitives_test.dart :: force retries synchronous throws and maintains owned keys on retry` | 子类内存后端 | 通过 |
| INV-18 | 异步 force 只捕获底层同步/awaited 写失败，清理后重试一次，耗尽上报 WriteError(cause) | SKILL 不变量 | `test/async_cacheman_test.dart :: two failures report final error with storage key, force false never retries` | 子类内存后端 | 通过 |
| INV-19 | 异步续期/force purge 失败仍返回原读取值 | SKILL 不变量 | `test/async_cacheman_test.dart :: renewal force scan failure is reported and read still returns the value` | 子类内存后端 | 通过 |
| INV-20 | 解码失败：删除后报告 CorruptEntryError(dropped:true) 一次；codec null 的 cause 为 FormatException；purge/readonly 静默 | SKILL 不变量 | `test/async_cacheman_test.dart :: decode null/throw/deserialize failures delete then report once; probes stay quiet` | 子类内存后端 | 通过 |
| INV-21 | erase 有 namespace 或 enckey 时只删自有键，否则全清；Async 默认 clear 枚举快照 | SKILL 不变量 | `test/async_cacheman_test.dart :: unscoped erase default clears every backend key via snapshot enumeration` | 子类内存后端 | 通过 |
| INV-22 | CacheContext key 惰性且缓存null；storageKey为实际键；保留const构造及捕获的namespace | 阶段 1b | `test/hub_test.dart :: CacheContext is lazy memoized and captures namespace before switching` | 子类内存后端 | 通过 |
| INV-23 | CacheContext 按实际原语操作传逻辑key/转义namespace，内部续期/懒删传write/remove | SKILL 不变量 | `test/async_cacheman_test.dart :: context carries logical keys, escaped namespace and actual operation` | 子类内存后端 | 通过 |
| INV-24 | 真实 get_storage write/remove/erase 在返回前同步通知；erase 键为空串 | 阶段 1b | `test/cacheman_test.dart :: get_storage write remove erase notify synchronously before return` | 集成·真 get_storage | 通过 |
| INV-25 | watch 缺省忽略自身写，includeOwnWrites接收；peer/external/clear/cancel/namespace迁移 | 阶段 1b | `test/hub_test.dart :: real watch suppresses own writes and handles external clear cancel and namespace` | 集成·真 get_storage | 通过 |
| INV-26 | 读路径滑动写与懒删除也属于自身写，整库erase亦可抑制 | 阶段 1b | `test/hub_test.dart :: own erase lazy deletion and sliding renewal are suppressed` | 集成·真 get_storage | 通过 |
| INV-27 | watch 类型错误为 TypeMismatchError 且回调收到 null，不阻断其他监听；快照容许回调里增删订阅 | 阶段 1b | `test/hub_test.dart :: watch type errors report and snapshot dispatch supports reentrant changes` | 子类内存后端 | 通过 |
| INV-28 | Map 型简易 Rx 双向绑定断环，不要求按身份判等 | 阶段 1b | `test/hub_test.dart :: Map Rx two-way binding has bounded callbacks without equality checks` | 集成·真 get_storage | 通过 |
| INV-29 | 不支持通知时watch抛UnsupportedError；无同步通知每次重扫，异步后端可能收到自己写入 | 阶段 1b | `test/hub_test.dart :: unsupported and asynchronous notifications rescan on every query` | 子类内存后端 | 通过 |
| INV-30 | flushDelay 默认null；共享Timer保留最早deadline，多次写仅一次save，flush同步取消Timer并排save | 阶段 1b | `test/hub_test.dart :: flushDelay coalesces shared writers and keeps the earliest deadline` | 子类内存后端 | 通过 |
| INV-31 | 生命周期 inactive/paused/hidden/detached 排保存，resumed不保存 | 阶段 1b | `test/hub_test.dart :: all background lifecycle states flush pending writes; resumed does not` | 子类内存后端 | 通过 |
| INV-32 | flush错误上报最近延迟写入者/主动调用者，含同步异常和Future错误 | 阶段 1b | `test/hub_test.dart :: delayed flush errors report to latest writer and explicit caller` | 子类内存后端 | 通过 |
| INV-33 | 默认延迟写writeInMemory可立即读到；flush排落盘；删除仍立即保存整个map | 阶段 1b | `test/hub_test.dart :: real deferred writes flush to disk and deletes still save immediately` | 集成·真 get_storage | 通过 |
| INV-34 | 已有子类的deferred原语退化setRaw、flush默认no-op；失败不重复force | 阶段 1b | `test/hub_test.dart :: deferred fallback Future failures report without force retry` | 子类内存后端 | 通过 |
| INV-35 | purgeOnInit 默认false，true为Timer.run非阻塞清理；raw忽略，Async不启用 | 阶段 1b | `test/hub_test.dart :: purgeOnInit is nonblocking clears expired envelopes and ignores raw` | 集成·真 get_storage | 通过 |
| INV-36 | ttl=0/负数忽略；绝对过期接受DateTime/int、拒绝过去/非法值；sliding+ttl可重起 | 用户需求 | `test/hub_test.dart :: ttl zero negative and absolute expiry validation retain intended behavior` | 子类内存后端 | 通过 |
| INV-37 | 无onError时print保留错误；force:false只尝试一次；onError自身异常在同步/异步读写中均传播 | SKILL 不变量 | `test/hub_test.dart :: force false reports once and fallback print preserves the error` | 子类内存后端 | 通过 |
| INV-38 | 同步/异步原语覆写遵循内存立即更新/awaited持久化各自契约 | 阶段 1a | `test/async_cacheman_test.dart :: read/write await persistence and read fresh data every time` | 子类内存后端 | 通过 |
| INV-39 | 完整验收：保留原有功能回归（阶段2语义断言更新、删除 CacheOptions 测试）、每个注册用例必须出现在矩阵、lib行覆盖率100% | 用户需求 | `test/hub_test.dart :: Jsonx unknown tags shape mismatch and cast errors` | 子类内存后端 | 通过 |

| INV-40 | read/readWith 类型/adapter 失败默认值 + TypeMismatchError，不删；dynamic/Object?不报；int/double不互转 | 阶段 2 | `test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=false)`<br>`test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=true)` | 子类内存后端 | 通过 |
| INV-41 | listOf/mapOf 立即复制检查，业务类/nullable/数字 adapter 双向转换，fromJson 原因保留 | 阶段 2 | `test/type_safety_test.dart :: typed adapters roundtrip collections and business values (async=false)`<br>`test/type_safety_test.dart :: typed adapters roundtrip collections and business values (async=true)`<br>`test/type_safety_test.dart :: collection adapters eagerly validate and copy JSON structures` | 子类内存后端 | 通过 |
| INV-42 | fast/lazy/batchFast adapter + 默认 ttl，set 显式 ttl 覆盖；类型不符不抛 | 阶段 2 | `test/type_safety_test.dart :: fast lazy and batch accessors adapt values and apply default ttl` | 子类内存后端 | 通过 |

## 全部公开功能及回归用例

下表包含全部139个真实测试，覆盖原有公开API、评审已落地修复、阶段0/1a/1b/2，以及错误和边界分支。

| ID | 需求 / 不变量 | 来源 | 用例（文件 :: 测试名，可多条） | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| CASE-001 | batch defaults, short values, ttl/expireAt and remove forwarding | 阶段 1a | `test/async_cacheman_test.dart :: batch defaults, short values, ttl/expireAt and remove forwarding` | 子类内存后端 | 通过 |
| CASE-002 | context carries logical keys, escaped namespace and actual operation | 阶段 1a | `test/async_cacheman_test.dart :: context carries logical keys, escaped namespace and actual operation` | 子类内存后端 | 通过 |
| CASE-003 | decode null/throw/deserialize failures delete then report once; probes stay quiet | 阶段 1a | `test/async_cacheman_test.dart :: decode null/throw/deserialize failures delete then report once; probes stay quiet` | 子类内存后端 | 通过（阶段2：CorruptEntryError(dropped:true)，原异常移到 cause） |
| CASE-004 | enckey and codeable roundtrip separately; fresh enumeration sees external writes | 阶段 1a | `test/async_cacheman_test.dart :: enckey and codeable roundtrip separately; fresh enumeration sees external writes` | 子类内存后端 | 通过 |
| CASE-005 | expireAt accepts DateTime/int, rejects past/invalid; invalid ttl ignored | 阶段 1a | `test/async_cacheman_test.dart :: expireAt accepts DateTime/int, rejects past/invalid; invalid ttl ignored` | 子类内存后端 | 通过 |
| CASE-006 | force purges then retries once (synchronous=false) | 阶段 1a | `test/async_cacheman_test.dart :: force purges then retries once (synchronous=false)` | 子类内存后端 | 通过 |
| CASE-007 | force purges then retries once (synchronous=true) | 阶段 1a | `test/async_cacheman_test.dart :: force purges then retries once (synchronous=true)` | 子类内存后端 | 通过 |
| CASE-008 | initialization is explicit and forwards context | 阶段 1a | `test/async_cacheman_test.dart :: initialization is explicit and forwards context` | 子类内存后端 | 通过 |
| CASE-009 | missing codecs degrade to plain keys and values | 阶段 1a | `test/async_cacheman_test.dart :: missing codecs degrade to plain keys and values` | 子类内存后端 | 通过 |
| CASE-010 | namespace escaping, isolation, scope switching and scoped erase | 阶段 1a | `test/async_cacheman_test.dart :: namespace escaping, isolation, scope switching and scoped erase` | 子类内存后端 | 通过 |
| CASE-011 | purge protects foreign unmarked envelopes and other namespaces | 阶段 1a | `test/async_cacheman_test.dart :: purge protects foreign unmarked envelopes and other namespaces` | 子类内存后端 | 通过 |
| CASE-012 | raw rejects non-String, bypasses codec/serialization/expiry and purge | 阶段 1a | `test/async_cacheman_test.dart :: raw rejects non-String, bypasses codec/serialization/expiry and purge` | 子类内存后端 | 通过 |
| CASE-013 | read/write await persistence and read fresh data every time | 阶段 1a | `test/async_cacheman_test.dart :: read/write await persistence and read fresh data every time` | 子类内存后端 | 通过 |
| CASE-014 | readonly counts null, does not renew/report, allows expired replacement | 阶段 1a | `test/async_cacheman_test.dart :: readonly counts null, does not renew/report, allows expired replacement` | 子类内存后端 | 通过 |
| CASE-015 | renewal failure reports without throwing from read or changing envelope | 阶段 1a | `test/async_cacheman_test.dart :: renewal failure reports without throwing from read or changing envelope` | 子类内存后端 | 通过（阶段2：WriteError，cause 保留原异常；读值不变） |
| CASE-016 | renewal force scan failure is reported and read still returns the value | 阶段 1a | `test/async_cacheman_test.dart :: renewal force scan failure is reported and read still returns the value` | 子类内存后端 | 通过（阶段2：WriteError.cause 为扫描异常，原读值仍返回） |
| CASE-017 | serialize errors never retry and preserve the original exception | 阶段 1a | `test/async_cacheman_test.dart :: serialize errors never retry and preserve the original exception` | 子类内存后端 | 通过（阶段2：一次构造，无 purge/重试；SerializeError 保留 cause） |
| CASE-018 | sliding plus ttl restarts a past absolute expiry | 阶段 1a | `test/async_cacheman_test.dart :: sliding plus ttl restarts a past absolute expiry` | 子类内存后端 | 通过 |
| CASE-019 | sliding skips above 90 percent and renews at inclusive boundary | 阶段 1a | `test/async_cacheman_test.dart :: sliding skips above 90 percent and renews at inclusive boundary` | 子类内存后端 | 通过 |
| CASE-020 | ttl expires and lazy read physically deletes the key | 阶段 1a | `test/async_cacheman_test.dart :: ttl expires and lazy read physically deletes the key` | 子类内存后端 | 通过 |
| CASE-021 | two failures report final error with storage key, force false never retries | 阶段 1a | `test/async_cacheman_test.dart :: two failures report final error with storage key, force false never retries` | 子类内存后端 | 通过（阶段2：WriteError，保留实际 key 和最终 cause） |
| CASE-022 | unscoped erase default clears every backend key via snapshot enumeration | 阶段 1a | `test/async_cacheman_test.dart :: unscoped erase default clears every backend key via snapshot enumeration` | 子类内存后端 | 通过 |
| CASE-023 | unscoped erase dispatches to overridden clearRaw with null key | 阶段 1a | `test/async_cacheman_test.dart :: unscoped erase dispatches to overridden clearRaw with null key` | 子类内存后端 | 通过 |
| CASE-024 | all primitives override default backend; CRUD is synchronous | 阶段 1a | `test/cacheman_primitives_test.dart :: all primitives override default backend; CRUD is synchronous` | 子类内存后端 | 通过 |
| CASE-025 | expiry, sliding, namespace and owned-key cache work over primitives | 阶段 1a | `test/cacheman_primitives_test.dart :: expiry, sliding, namespace and owned-key cache work over primitives` | 子类内存后端 | 通过 |
| CASE-026 | flush Future errors report once and are never retried | 阶段 1a | `test/cacheman_primitives_test.dart :: flush Future errors report once and are never retried` | 子类内存后端 | 通过（阶段2：FlushError，cause 保留原异常且不重试） |
| CASE-027 | force retries synchronous throws and maintains owned keys on retry | 阶段 1a | `test/cacheman_primitives_test.dart :: force retries synchronous throws and maintains owned keys on retry` | 子类内存后端 | 通过 |
| CASE-028 | lazy default initialization still loads the explicitly supplied path | 阶段 1a | `test/cacheman_primitives_test.dart :: lazy default initialization still loads the explicitly supplied path` | 集成·真 get_storage | 通过 |
| CASE-029 | does not write anything back — keys()/length stay unaffected | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > debug() > does not write anything back — keys()/length stay unaffected` | 集成·真 get_storage | 通过 |
| CASE-030 | returns every owned entry decrypted, namespace preserved | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > debug() > returns every owned entry decrypted, namespace preserved` | 集成·真 get_storage | 通过 |
| CASE-031 | batchFast binds several keys at once | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > fast / lazy / batchFast > batchFast binds several keys at once` | 集成·真 get_storage | 通过 |
| CASE-032 | fast binds a key and forwards get/set/remove | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > fast / lazy / batchFast > fast binds a key and forwards get/set/remove` | 集成·真 get_storage | 通过 |
| CASE-033 | lazy only builds the accessor on first call, then reuses it | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > fast / lazy / batchFast > lazy only builds the accessor on first call, then reuses it` | 集成·真 get_storage | 通过 |
| CASE-034 | ls persists via get_storage | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > ls persists via get_storage` | 集成·真 get_storage | 通过 |
| CASE-035 | ls.key(index)/length walk get_storage directly without materializing keys() | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > ls.key(index)/length walk get_storage directly without materializing keys()` | 集成·真 get_storage | 通过 |
| CASE-036 | setNamespace switches ls | 原有功能 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > setNamespace switches ls` | 集成·真 get_storage | 通过 |
| CASE-037 | round-trips DateTime, Duration, Set, and BigInt | 原有功能 | `test/cacheman_test.dart :: Jsonx > round-trips DateTime, Duration, Set, and BigInt` | 单元 | 通过 |
| CASE-038 | round-trips RegExp, flags included | 原有功能 | `test/cacheman_test.dart :: Jsonx > round-trips RegExp, flags included` | 单元 | 通过 |
| CASE-039 | round-trips Uri | 原有功能 | `test/cacheman_test.dart :: Jsonx > round-trips Uri` | 单元 | 通过 |
| CASE-040 | a plain Map shaped like a tag round-trips unchanged | 阶段 0 | `test/cacheman_test.dart :: Jsonx edge cases > a plain Map shaped like a tag round-trips unchanged` | 单元 | 通过 |
| CASE-041 | escapes nested, Set and toJson() results too | 阶段 0 | `test/cacheman_test.dart :: Jsonx edge cases > escapes nested, Set and toJson() results too` | 单元 | 通过 |
| CASE-042 | falls back to toJson() for custom objects | 阶段 0 | `test/cacheman_test.dart :: Jsonx edge cases > falls back to toJson() for custom objects` | 单元 | 通过 |
| CASE-043 | legacy tag-shaped Map with an invalid Map payload is kept as is | 阶段 0 | `test/cacheman_test.dart :: Jsonx edge cases > legacy tag-shaped Map with an invalid Map payload is kept as is` | 单元 | 通过 |
| CASE-044 | unsupported objects still throw | 阶段 0 | `test/cacheman_test.dart :: Jsonx edge cases > unsupported objects still throw` | 单元 | 通过 |
| CASE-045 | missing key returns null, or the given default | 原有功能 | `test/cacheman_test.dart :: basic read/write/remove > missing key returns null, or the given default` | 集成·真 get_storage | 通过 |
| CASE-046 | remove deletes the key | 原有功能 | `test/cacheman_test.dart :: basic read/write/remove > remove deletes the key` | 集成·真 get_storage | 通过 |
| CASE-047 | values round-trip through JSON (maps, lists, nested) | 原有功能 | `test/cacheman_test.dart :: basic read/write/remove > values round-trip through JSON (maps, lists, nested)` | 集成·真 get_storage | 通过 |
| CASE-048 | write then read roundtrips | 原有功能 | `test/cacheman_test.dart :: basic read/write/remove > write then read roundtrips` | 集成·真 get_storage | 通过 |
| CASE-049 | writes assert before initialization and succeed after awaiting it | 原有功能 | `test/cacheman_test.dart :: basic read/write/remove > writes assert before initialization and succeed after awaiting it` | 集成·真 get_storage | 通过 |
| CASE-050 | readAll pairs defaults positionally, missing slots fall back to null | 原有功能 | `test/cacheman_test.dart :: batch operations > readAll pairs defaults positionally, missing slots fall back to null` | 集成·真 get_storage | 通过 |
| CASE-051 | writeAll / readAll / removeAll | 原有功能 | `test/cacheman_test.dart :: batch operations > writeAll / readAll / removeAll` | 集成·真 get_storage | 通过 |
| CASE-052 | writeAll with fewer values than keys skips the missing entries | 原有功能 | `test/cacheman_test.dart :: batch operations > writeAll with fewer values than keys skips the missing entries` | 集成·真 get_storage | 通过 |
| CASE-053 | a null codec result is reported once, deleted and returned as the default | 原有功能 | `test/cacheman_test.dart :: codec / enckey > a null codec result is reported once, deleted and returned as the default` | 集成·真 get_storage | 通过（阶段2：CorruptEntryError(dropped:true)，cause 为 FormatException） |
| CASE-054 | a throwing replacement codec reports the original exception once and deletes the entry | 原有功能 | `test/cacheman_test.dart :: codec / enckey > a throwing replacement codec reports the original exception once and deletes the entry` | 集成·真 get_storage | 通过（阶段2：CorruptEntryError，cause 保留原异常身份） |
| CASE-055 | a throwing replacement deserialize reports once after deleting the entry | 原有功能 | `test/cacheman_test.dart :: codec / enckey > a throwing replacement deserialize reports once after deleting the entry` | 集成·真 get_storage | 通过（阶段2：CorruptEntryError，保持先删后报和原 cause） |
| CASE-056 | codeable + codec obfuscates the persisted string but reads decode transparently | 原有功能 | `test/cacheman_test.dart :: codec / enckey > codeable + codec obfuscates the persisted string but reads decode transparently` | 集成·真 get_storage | 通过 |
| CASE-057 | enckey keys()/key() reuse decoded logical keys across repeated enumeration | 原有功能 | `test/cacheman_test.dart :: codec / enckey > enckey keys()/key() reuse decoded logical keys across repeated enumeration` | 集成·真 get_storage | 通过 |
| CASE-058 | enckey obfuscates the storage key so foreign readers cannot see it | 原有功能 | `test/cacheman_test.dart :: codec / enckey > enckey obfuscates the storage key so foreign readers cannot see it` | 集成·真 get_storage | 通过 |
| CASE-059 | raw reads bypass throwing codecs/deserializers and do not report decode errors | 原有功能 | `test/cacheman_test.dart :: codec / enckey > raw reads bypass throwing codecs/deserializers and do not report decode errors` | 集成·真 get_storage | 通过 |
| CASE-060 | setNamespace clears enckey logical mappings before enumerating the new scope | 原有功能 | `test/cacheman_test.dart :: codec / enckey > setNamespace clears enckey logical mappings before enumerating the new scope` | 集成·真 get_storage | 通过 |
| CASE-061 | a background flush failure never throws out of write() | 原有功能 | `test/cacheman_test.dart :: force / onError > a background flush failure never throws out of write()` | 集成·真 get_storage | 通过 |
| CASE-062 | write() does not throw synchronously even under default force:true | 原有功能 | `test/cacheman_test.dart :: force / onError > write() does not throw synchronously even under default force:true` | 集成·真 get_storage | 通过 |
| CASE-063 | get_storage write remove erase notify synchronously before return | 阶段 1b | `test/cacheman_test.dart :: get_storage write remove erase notify synchronously before return` | 集成·真 get_storage | 通过 |
| CASE-064 | erase() with a namespace only removes owned keys | 原有功能 | `test/cacheman_test.dart :: namespace > erase() with a namespace only removes owned keys` | 集成·真 get_storage | 通过 |
| CASE-065 | keys()/length() stay accurate as entries are added and removed (owned-key cache) | 原有功能 | `test/cacheman_test.dart :: namespace > keys()/length() stay accurate as entries are added and removed (owned-key cache)` | 集成·真 get_storage | 通过 |
| CASE-066 | setNamespace invalidates the owned-key cache so keys() reflects the new namespace | 原有功能 | `test/cacheman_test.dart :: namespace > setNamespace invalidates the owned-key cache so keys() reflects the new namespace` | 集成·真 get_storage | 通过 |
| CASE-067 | setNamespace switches the prefix in place | 原有功能 | `test/cacheman_test.dart :: namespace > setNamespace switches the prefix in place` | 集成·真 get_storage | 通过 |
| CASE-068 | two engines sharing a backend but different namespaces do not collide | 原有功能 | `test/cacheman_test.dart :: namespace > two engines sharing a backend but different namespaces do not collide` | 集成·真 get_storage | 通过 |
| CASE-069 | a String value is stored and read back untouched, no envelope | 原有功能 | `test/cacheman_test.dart :: raw mode > a String value is stored and read back untouched, no envelope` | 集成·真 get_storage | 通过 |
| CASE-070 | a non-String value is warned and the write is skipped | 原有功能 | `test/cacheman_test.dart :: raw mode > a non-String value is warned and the write is skipped` | 集成·真 get_storage | 通过 |
| CASE-071 | writes again once the key expires | 原有功能 | `test/cacheman_test.dart :: readonly > writes again once the key expires` | 集成·真 get_storage | 通过 |
| CASE-072 | writes only when the key is empty; a second write is discarded | 原有功能 | `test/cacheman_test.dart :: readonly > writes only when the key is empty; a second write is discarded` | 集成·真 get_storage | 通过 |
| CASE-073 | keyCodec encodes keys independently of the value codec | 阶段 0 | `test/cacheman_test.dart :: review fixes > keyCodec encodes keys independently of the value codec` | 集成·真 get_storage | 通过 |
| CASE-074 | length/key/keys agree under a namespace | 阶段 0 | `test/cacheman_test.dart :: review fixes > length/key/keys agree under a namespace` | 集成·真 get_storage | 通过 |
| CASE-075 | namespace with "%" is escaped and isolated from the literal-prefixed one | 阶段 0 | `test/cacheman_test.dart :: review fixes > namespace with "%" is escaped and isolated from the literal-prefixed one` | 集成·真 get_storage | 通过 |
| CASE-076 | namespaces containing ":" do not collide or erase each other | 阶段 0 | `test/cacheman_test.dart :: review fixes > namespaces containing ":" do not collide or erase each other` | 集成·真 get_storage | 通过 |
| CASE-077 | purge() leaves raw values alone even if they look like an expired entity | 阶段 0 | `test/cacheman_test.dart :: review fixes > purge() leaves raw values alone even if they look like an expired entity` | 集成·真 get_storage | 通过 |
| CASE-078 | readonly treats a stored null as present and does not slide-renew | 阶段 0 | `test/cacheman_test.dart :: review fixes > readonly treats a stored null as present and does not slide-renew` | 集成·真 get_storage | 通过 |
| CASE-079 | readonly write attempt does not extend the old value lifetime (sliding) | 阶段 0 | `test/cacheman_test.dart :: review fixes > readonly write attempt does not extend the old value lifetime (sliding)` | 集成·真 get_storage | 通过 |
| CASE-080 | serialize failing once is not retried by force | 阶段 0 | `test/cacheman_test.dart :: review fixes > serialize failing once is not retried by force` | 集成·真 get_storage | 通过（阶段2：只序列化一次，失败不写入、不重试） |
| CASE-081 | serialize throwing is caught by write (reported via onError), read keeps working | 阶段 0 | `test/cacheman_test.dart :: review fixes > serialize throwing is caught by write (reported via onError), read keeps working` | 集成·真 get_storage | 通过（阶段2：SerializeError，cause 保留 StateError） |
| CASE-082 | a read hit past 10% of ttl renews expireAt | 原有功能 | `test/cacheman_test.dart :: sliding expiry > a read hit past 10% of ttl renews expireAt` | 集成·真 get_storage | 通过 |
| CASE-083 | without sliding, the same read pattern lets the entry expire on schedule | 原有功能 | `test/cacheman_test.dart :: sliding expiry > without sliding, the same read pattern lets the entry expire on schedule` | 集成·真 get_storage | 通过 |
| CASE-084 | a positive ttl expires the entry after it elapses | 原有功能 | `test/cacheman_test.dart :: ttl / expiry > a positive ttl expires the entry after it elapses` | 集成·真 get_storage | 通过 |
| CASE-085 | expireAt in the past (no sliding) skips the write entirely | 原有功能 | `test/cacheman_test.dart :: ttl / expiry > expireAt in the past (no sliding) skips the write entirely` | 集成·真 get_storage | 通过 |
| CASE-086 | purge() proactively deletes an expired entry | 原有功能 | `test/cacheman_test.dart :: ttl / expiry > purge() proactively deletes an expired entry` | 集成·真 get_storage | 通过 |
| CASE-087 | ttl <= 0 is warned and ignored — value persists with no expiry | 原有功能 | `test/cacheman_test.dart :: ttl / expiry > ttl <= 0 is warned and ignored — value persists with no expiry` | 集成·真 get_storage | 通过 |
| CASE-088 | CacheContext is lazy memoized and captures namespace before switching | 阶段 1b | `test/hub_test.dart :: CacheContext is lazy memoized and captures namespace before switching` | 子类内存后端 | 通过 |
| CASE-089 | Map Rx two-way binding has bounded callbacks without equality checks | 阶段 1b | `test/hub_test.dart :: Map Rx two-way binding has bounded callbacks without equality checks` | 集成·真 get_storage | 通过 |
| CASE-090 | all background lifecycle states flush pending writes; resumed does not | 阶段 1b | `test/hub_test.dart :: all background lifecycle states flush pending writes; resumed does not` | 子类内存后端 | 通过 |
| CASE-091 | both key maps clear on 1024 overflow and namespace resets both | 阶段 1b | `test/hub_test.dart :: both key maps clear on 1024 overflow and namespace resets both` | 子类内存后端 | 通过 |
| CASE-092 | custom delayed fallback delegates to setRaw and needs no default backend | 阶段 1b | `test/hub_test.dart :: custom delayed fallback delegates to setRaw and needs no default backend` | 子类内存后端 | 通过 |
| CASE-093 | deferred fallback Future failures report without force retry | 阶段 1b | `test/hub_test.dart :: deferred fallback Future failures report without force retry` | 子类内存后端 | 通过（阶段2：FlushError.cause 保留原异常，不重试） |
| CASE-094 | delayed flush errors report to latest writer and explicit caller | 阶段 1b | `test/hub_test.dart :: delayed flush errors report to latest writer and explicit caller` | 子类内存后端 | 通过（阶段2：FlushError.cause 保留原异常及上报归属） |
| CASE-095 | delete and clear Future errors are reported once without retry | 阶段 1b | `test/hub_test.dart :: delete and clear Future errors are reported once without retry` | 子类内存后端 | 通过（阶段2：两个 FlushError，仍各上报一次） |
| CASE-096 | failed initialization leaves sync and async writes guarded until retry succeeds | 阶段 1b | `test/hub_test.dart :: failed initialization leaves sync and async writes guarded until retry succeeds` | 子类内存后端 | 通过 |
| CASE-097 | flushDelay coalesces shared writers and keeps the earliest deadline | 阶段 1b | `test/hub_test.dart :: flushDelay coalesces shared writers and keeps the earliest deadline` | 子类内存后端 | 通过 |
| CASE-098 | force false reports once and fallback print preserves the error | 阶段 1b | `test/hub_test.dart :: force false reports once and fallback print preserves the error` | 子类内存后端 | 通过 |
| CASE-099 | Jsonx unknown tags shape mismatch and cast errors | 阶段 1b | `test/hub_test.dart :: Jsonx unknown tags shape mismatch and cast errors` | 单元 | 通过（阶段2：删除 CacheOptions 构造断言，保留全部 Jsonx 断言） |
| CASE-100 | null key decoding falls back without memoizing and excludes unowned keys | 阶段 1b | `test/hub_test.dart :: null key decoding falls back without memoizing and excludes unowned keys` | 子类内存后端 | 通过 |
| CASE-101 | one shared subscription and N local writes need no index rebuild | 阶段 1b | `test/hub_test.dart :: one shared subscription and N local writes need no index rebuild` | 子类内存后端 | 通过 |
| CASE-102 | own erase lazy deletion and sliding renewal are suppressed | 阶段 1b | `test/hub_test.dart :: own erase lazy deletion and sliding renewal are suppressed` | 集成·真 get_storage | 通过 |
| CASE-103 | purgeOnInit is nonblocking clears expired envelopes and ignores raw | 阶段 1b | `test/hub_test.dart :: purgeOnInit is nonblocking clears expired envelopes and ignores raw` | 集成·真 get_storage | 通过 |
| CASE-104 | readonly raw null foreign and expired probes have no renewal side effects | 阶段 1b | `test/hub_test.dart :: readonly raw null foreign and expired probes have no renewal side effects` | 子类内存后端 | 通过 |
| CASE-105 | real deferred writes flush to disk and deletes still save immediately | 阶段 1b | `test/hub_test.dart :: real deferred writes flush to disk and deletes still save immediately` | 集成·真 get_storage | 通过 |
| CASE-106 | real shared container indexes heal after peers and external changes | 阶段 1b | `test/hub_test.dart :: real shared container indexes heal after peers and external changes` | 集成·真 get_storage | 通过 |
| CASE-107 | real watch suppresses own writes and handles external clear cancel and namespace | 阶段 1b | `test/hub_test.dart :: real watch suppresses own writes and handles external clear cancel and namespace` | 集成·真 get_storage | 通过 |
| CASE-108 | reentrant peer writes do not bless an incomplete owned-key index | 阶段 1b | `test/hub_test.dart :: reentrant peer writes do not bless an incomplete owned-key index` | 子类内存后端 | 通过 |
| CASE-109 | sync and async backends run in parallel and never cache read values | 阶段 1b | `test/hub_test.dart :: sync and async backends run in parallel and never cache read values` | 子类内存后端 | 通过 |
| CASE-110 | sync enckey-only erase preserves foreign keys and unmarked envelopes never expire | 阶段 1b | `test/hub_test.dart :: sync enckey-only erase preserves foreign keys and unmarked envelopes never expire` | 子类内存后端 | 通过 |
| CASE-111 | sync sliding includes exactly 90 percent and preserves the original entity | 阶段 1b | `test/hub_test.dart :: sync sliding includes exactly 90 percent and preserves the original entity` | 子类内存后端 | 通过 |
| CASE-112 | ttl zero negative and absolute expiry validation retain intended behavior | 阶段 1b | `test/hub_test.dart :: ttl zero negative and absolute expiry validation retain intended behavior` | 子类内存后端 | 通过 |
| CASE-113 | unsupported and asynchronous notifications rescan on every query | 阶段 1b | `test/hub_test.dart :: unsupported and asynchronous notifications rescan on every query` | 子类内存后端 | 通过 |
| CASE-114 | watch can change its namespace during an own write safely | 阶段 1b | `test/hub_test.dart :: watch can change its namespace during an own write safely` | 子类内存后端 | 通过 |
| CASE-115 | watch migration handles encoded keys and cancellation during clear snapshot | 阶段 1b | `test/hub_test.dart :: watch migration handles encoded keys and cancellation during clear snapshot` | 子类内存后端 | 通过 |
| CASE-116 | watch type errors report and snapshot dispatch supports reentrant changes | 阶段 1b | `test/hub_test.dart :: watch type errors report and snapshot dispatch supports reentrant changes` | 子类内存后端 | 通过（阶段2：TypeMismatchError，回调收到 null，后续 watcher 继续） |

| CASE-117 | watch的codec/回调错误沿注册storageKey上报，后续watcher继续分发 | 阶段 1b | `test/hub_test.dart :: watch codec and callback failures preserve registered error keys and keep dispatching` | 子类内存后端 | 通过（阶段2：WatchError 保留注册 key / cause，后续 watcher 继续） |

| CASE-118 | throwing watch onError propagates once through own and peer writes | 阶段 2 | `test/hub_test.dart :: throwing watch onError propagates once through own and peer writes` | 子类内存后端 | 通过 |
| CASE-119 | read mismatches retain data defaults and exact numeric types (async=false) | 阶段 2 | `test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=false)` | 子类内存后端 | 通过 |
| CASE-120 | read mismatches retain data defaults and exact numeric types (async=true) | 阶段 2 | `test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=true)` | 子类内存后端 | 通过 |
| CASE-121 | corrupt entries report dropped cause and trace (async=false) | 阶段 2 | `test/type_safety_test.dart :: corrupt entries report dropped cause and trace (async=false)` | 子类内存后端 | 通过 |
| CASE-122 | corrupt entries report dropped cause and trace (async=true) | 阶段 2 | `test/type_safety_test.dart :: corrupt entries report dropped cause and trace (async=true)` | 子类内存后端 | 通过 |
| CASE-123 | raw ignores write adapters and keeps String storage (async=false) | 阶段 2 | `test/type_safety_test.dart :: raw ignores write adapters and keeps String storage (async=false)` | 子类内存后端 | 通过 |
| CASE-124 | raw ignores write adapters and keeps String storage (async=true) | 阶段 2 | `test/type_safety_test.dart :: raw ignores write adapters and keeps String storage (async=true)` | 子类内存后端 | 通过 |
| CASE-125 | typed adapters roundtrip collections and business values (async=false) | 阶段 2 | `test/type_safety_test.dart :: typed adapters roundtrip collections and business values (async=false)` | 子类内存后端 | 通过 |
| CASE-126 | typed adapters roundtrip collections and business values (async=true) | 阶段 2 | `test/type_safety_test.dart :: typed adapters roundtrip collections and business values (async=true)` | 子类内存后端 | 通过 |
| CASE-127 | encoding failures never scan remove or retry (async=false) | 阶段 2 | `test/type_safety_test.dart :: encoding failures never scan remove or retry (async=false)` | 子类内存后端 | 通过 |
| CASE-128 | encoding failures never scan remove or retry (async=true) | 阶段 2 | `test/type_safety_test.dart :: encoding failures never scan remove or retry (async=true)` | 子类内存后端 | 通过 |
| CASE-129 | backend retries reuse one build and classify final failures (async=false) | 阶段 2 | `test/type_safety_test.dart :: backend retries reuse one build and classify final failures (async=false)` | 子类内存后端 | 通过 |
| CASE-130 | backend retries reuse one build and classify final failures (async=true) | 阶段 2 | `test/type_safety_test.dart :: backend retries reuse one build and classify final failures (async=true)` | 子类内存后端 | 通过 |
| CASE-131 | fast lazy and batch accessors adapt values and apply default ttl | 阶段 2 | `test/type_safety_test.dart :: fast lazy and batch accessors adapt values and apply default ttl` | 子类内存后端 | 通过 |
| CASE-132 | collection adapters eagerly validate and copy JSON structures | 阶段 2 | `test/type_safety_test.dart :: collection adapters eagerly validate and copy JSON structures` | 子类内存后端 | 通过 |
| CASE-133 | sync failed mutation Future is FlushError without retry | 阶段 2 | `test/type_safety_test.dart :: sync failed mutation Future is FlushError without retry` | 子类内存后端 | 通过 |
| CASE-134 | R1：重入切 namespace 并枚举后，索引不含旧域键，erase 保留旧域数据 | 全量评审 R1–R6 | `test/hub_test.dart :: R1 reentrant namespace enumeration preserves scope isolation` | 子类内存后端 | 通过 |
| CASE-135 | R2：双语 DirectoryCache 示例用 UTF-8 小写十六进制，避免文件名大小写碰撞 | 全量评审 R1–R6 | scratchpad：从双语 README 提取并核对相同示例；review_directory_hex_test.dart 验证 aaa=1、aaG=2，枚举恰好两个键（文件 616161.cache / 616147.cache） | 手动·Windows 真文件 | 通过（按要求不在仓库保留示例测试文件） |
| CASE-136 | R3：吞掉无关 onError 异常后业务异常仍报 WatchError，继续分发；新上报清空身份标记 | 全量评审 R1–R6 | `test/hub_test.dart :: R3 caught unrelated handler errors do not poison watch dispatch` | 子类内存后端 | 通过 |
| CASE-137 | R4：真实 get_storage 的 write/remove/erase Future 保留处理器异常身份，走 Zone，不误报 FlushError | 全量评审 R1–R6 | `test/hub_test.dart :: R4 real get_storage handler errors propagate unchanged through Zone` | 集成·真 get_storage | 通过 |
| CASE-138 | R5：快照跳过已迁移 watcher，仍接收新域键和 clear 通知 | 全量评审 R1–R6 | `test/hub_test.dart :: R5 migrated snapshot watchers skip old keys and still receive clear` | 子类内存后端 | 通过 |
| CASE-139 | R6：延迟写先登记 flush，watch 重入写入后落盘失败只报最新嵌套写入者 | 全量评审 R1–R6 | `test/hub_test.dart :: R6 reentrant delayed flush failures belong to the nested writer` | 子类内存后端 | 通过 |

## 覆盖率豁免

| 文件:行号 | 原因 |
| --- | --- |
| lib/src/jsonx.dart:154 | 私有且从不被库内使用的 `Jsonx._()` 构造函数；仅有静态方法，从库外无法调用，也无生产调用路径。只标注这一行 `coverage:ignore-line`，其余所有可执行行均有测试。 |

coverage.dart 识别 ignore-line / ignore-start / ignore-end，按 lcov 的可执行行统计；导出入口
lib/cacheman.dart 无可执行行，显示0/0。本次 lcov 采集561行并全部命中（100%）；
上述1行保留显式豁免，本次无采集记录；
不以ignore掩盖web分支/错误处理/可测逻辑，当前没有其他豁免。

## 评审 P1/P2 逐项编号映射

| 编号 | 问题 | 处理阶段 / 状态 | 用例或“不在范围”原因 |
| --- | --- | --- | --- |
| P1-1 | 全量 flush 写放大，读懒删/续期触发写，未读过期数据残留 | 1b：flushDelay / purgeOnInit opt-in；阈值仍为剩余 <=90% | `test/hub_test.dart :: flushDelay coalesces shared writers and keeps the earliest deadline`<br>`test/hub_test.dart :: purgeOnInit is nonblocking clears expired envelopes and ignores raw`<br>`test/hub_test.dart :: own erase lazy deletion and sliding renewal are suppressed`；信封二次 JSON 转义方案 C 不采纳，不改现有格式/体积。 |
| P1-2 | ownedKeysCache 多实例/外部写漂移 | 1b Hub 版本自愈，INV-06 | `test/hub_test.dart :: real shared container indexes heal after peers and external changes` |
| P1-3 | GetX 示例死循环、erase 空键 listenKey 丢通知、isolate 不互通 | 阶段0文档守卫 + 1b watch(includeOwnWrites:false) | `test/hub_test.dart :: Map Rx two-way binding has bounded callbacks without equality checks`<br>`test/hub_test.dart :: real watch suppresses own writes and handles external clear cancel and namespace`；跨 isolate 通知不在范围，README 已说明。 |
| P1-4 | read 泛型强转抛 TypeError | 阶段2：默认值 + TypeMismatchError，不删数据 | `test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=false)`<br>`test/type_safety_test.dart :: read mismatches retain data defaults and exact numeric types (async=true)` |
| P1-5 | 更换 deserialize/codec 后静默删数据 | 阶段0上报；阶段2 CorruptEntryError(dropped:true) | `test/type_safety_test.dart :: corrupt entries report dropped cause and trace (async=false)`<br>`test/type_safety_test.dart :: corrupt entries report dropped cause and trace (async=true)`；信封版本/迁移钩子不在范围，待首次格式变更。 |
| P2-1 | force 默认 true 导致失败全扫 | 阶段2：仅底层写失败清理/重试，默认不变 | `test/type_safety_test.dart :: encoding failures never scan remove or retry (async=false)`<br>`test/type_safety_test.dart :: encoding failures never scan remove or retry (async=true)`<br>`test/type_safety_test.dart :: backend retries reuse one build and classify final failures (async=false)`<br>`test/type_safety_test.dart :: backend retries reuse one build and classify final failures (async=true)` |
| P2-2 | enckey 枚举每次解码 | 阶段0逻辑键缓存，最多1024项 | `test/hub_test.dart :: both key maps clear on 1024 overflow and namespace resets both` |
| P2-3 | 初始化前写无防护 | 阶段0 debug assert | `test/hub_test.dart :: failed initialization leaves sync and async writes guarded until retry succeeds` |
| P2-4 | listener 同步异常误报 flush 错误 | 阶段2：分类；watch 回调/键读取为 WatchError，类型为 TypeMismatchError，后台为 FlushError | `test/hub_test.dart :: watch codec and callback failures preserve registered error keys and keep dispatching`<br>`test/hub_test.dart :: throwing watch onError propagates once through own and peer writes`<br>`test/type_safety_test.dart :: sync failed mutation Future is FlushError without retry` |
| P2-5 | key(index) O(index)、无 scope erase 清整库、默认 read 仍为 T? | 阶段2弃用 key，建议 keys；其余语义保留并文档化 | `test/cacheman_test.dart :: Cacheman() — real get_storage integration > ls.key(index)/length walk get_storage directly without materializing keys()`；erase 覆盖见 INV-21；T? 返回类型不改，破坏面过大，不在范围。 |
| P2-6 | 文档与代码脱节 | 阶段0已校正文档；阶段1a/1b/2同步维护 | 双语 README / ARCHITECTURE / SKILL / CHANGELOG / example 人工核对；矩阵用 `dart run tool/check_acceptance.dart` 校验真实注册名称。 |
| P2-7 | 多 isolate / web localStorage 配额 | 不在本次范围 | 跨 isolate/进程通知和配额扩容均非本库保证；README 提示 isolate-local、配额依赖后端；WriteError/FlushError 只分类可观察失败。 |
| P2-8 | container getter 泄漏 GetStorage | 1a 原语接缝 + Cacheman.custom 缓解；getter 兼容保留 | `test/cacheman_primitives_test.dart :: all primitives override default backend; CRUD is synchronous`<br>`test/cacheman_test.dart :: forwarding subclass keeps get_storage hub, watch and incremental index` |

## 已知限制 / 不在范围

| 项目 | 状态 / 原因 |
| --- | --- |
| 无新增第三方依赖、无包内后端/路由/迁移 | 静态检查 lib/pubspec + INV-01/04；Hive/SharedPreferences/dart:io只保留应用侧适配示例。 |
| 真磁盘flush错误的可靠捕获/持久化完成确认 | 不在本次范围：get_storage 2.1.1丢弃实际flush Future，flush()按任务返回void。内存子类注入失败覆盖错误上报，但不能证明真实磁盘失败必然走onError。 |
| 崩溃/跨isolate/其他进程变更通知 | 不在本次范围：Hub只共享当前isolate的底层身份，get_storage不跨isolate刷新；flushDelay崩溃可丢失窗口内写入，生命周期保存为尽力而为。 |
| 无通知/异步通知后端的自身事件抑制 | 明确退化：每次枚举全扫；无通知watch抛UnsupportedError，异步通知可能包含自身事件，调用方自行判等。 |
| 子类的新原语默认值 | 经 `Cacheman.custom` 构造的自带原语子类：hubIdentity默认this、listenRaw默认null，deferred写退化setRaw、flush为no-op；共享身份/通知须显式覆写。默认构造（含只转发参数的子类）共享GetStorage身份（终审修正：原按 runtimeType 判定会误伤转发子类，见 INV-01b）。 |
| 生命周期注册细节 | 比任务允许的长期观察器更短：仅有待保存Timer时注册，flush后移除，避免绑定长期强引用Hub；仍覆盖全部四种后台状态。 |
| CacheOp兼容 | 不增加enum成员，保留旧用例对CacheOp.values的断言：订阅使用无键init上下文，flush使用无键write上下文。 |
| reentrant通知 | 仅在原索引fresh、身份未替换、作用域代数未变且恰好一次同步通知时增量标新，否则失效重建；键通知快照跳过已迁移watcher，clear仍通知全部活跃记录；延迟写先登记flush，再通知以保留嵌套写入者归属。 |
| read adapter 签名 | Dart 不支持可选位置与命名参数混用；保留 read(key, [default])，新增 readWith(key, {defaultValue, adapter})，两者复用同一读取编排/内核。 |
| onError本身抛错 | 保留SKILL原契约：向上传播；不吞用户错误处理器异常。 |
| 异步访问器/debug/key(index)、并发readonly事务、跨box自动路由 | 不在本次范围：阶段1a已明确；AsyncCacheman只保留已提供的awaited API，不参与Hub/watch/flush。 |
| Windows文件句柄 | get_storage不关闭RandomAccessFile；测试临时目录只尽力清理。其备份也是不等待的后台任务，hub测试isolate持续保留fake path provider。 |

## scratch 基准（不进仓库）

同一机器、同一Flutter VM、覆写内存getRaw、不访问ctx.key，raw+namespace，预热1万次后每轮10万次read，5轮。
修改前：9874 / 7911 / 8766 / 5951 / 6132 µs；中位数7911 µs。
修改后：7031 / 3379 / 3389 / 3256 / 3106 µs；中位数3379 µs（约减少57%）。
脚本仅放忽略的.dart_tool/read_bench_test.dart；这是受JIT/调度影响的微基准，不代表所有真实后端/codec吞吐。
