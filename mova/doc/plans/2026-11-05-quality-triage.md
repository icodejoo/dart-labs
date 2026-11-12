# CP3 headers 清晰度五条离线定性

2026-11-05；本人执行，未转派。工作树 `E:\workspaces\wt-mova-cp2fix`，起点 detached `dbf3e0ec`（main 当前 HEAD）；用户给定测试基线 2448。本次不运行真机、adb、Gradle，不构建 APK。

## 结论

第六轮 `CP3.headers.quality.0..4` 的 FAIL 均为**判据缺陷**：清晰度正负对照已经成功，但总判据仍把旧原生 `pool` 截图失败并入；新 `pool-ready` 与 `pool-ready-cutover` 已全部通过。没有证据支持本批存在清晰度产品缺陷或环境故障，因此不改产品 lib、不修改 `MovaHttpFetch.get(Uri)` 签名、不增加 `MovaApi` 成员。

旧 FAIL 原样保留。本次修改后的夹具必须用新 APK 复验；离线解释不能把历史结果改成 PASS。

## 原始证据与逐条定性

只读核对 `doc/plans/2026-11-05-cp3-results.md` 第三至第六轮，以及下列目录中的 `*-cp3-headers.json` 原始 CHECK、`*-cp3-headers.requests.json` 服务端回执。目录均位于 `example/tool/coverage_evidence/`：

|目录|已完成 quality CHECK|positive / negative|旧 pool|新普通 / cutover 截图|
|---|---:|---|---|---|
|matrix-cp3-headers-r3-20261105-094946|5|全部 true / false|0、4 通过，其余失败|未启用|
|matrix-cp3-headers-r3-20261105-095110|5|全部 true / false|1、3 通过，其余失败；1 的 extract 失败|未启用|
|matrix-cp3-headers-r4-20261105-102159|5|全部 true / false|全部失败|未启用|
|matrix-cp3-headers-r5-20261105-111319|5|全部 true / false|全部失败|全部失败|
|matrix-cp3-headers-r5-20261105-112414|1|true / false|失败|失败；后续批次中断不算完成样本|
|matrix-cp3-headers-r6-20261105-114531|5|全部 true / false|全部失败|全部通过|
|matrix-cp3-headers-r6-20261105-115808|5|全部 true / false|全部失败|全部通过|

共读取 31 条已完成 quality CHECK；所有清晰度正负对照均满足原条件。历史第三至第五轮还包含原生抽帧/截图问题，不能用第六轮的新结论反写历史。第六轮两批 extract 均为 true，旧 pool 均为 false，新普通和 cutover 截图均为 true。

以下请求次数取第六轮第二批 `115808` 每条 CHECK 自带的 `numbers.requests`；第一批 `114531` 的结论相同（quality.2 第一批未观察到 index 请求）。

|ID|带头 master / index 回执|无头 master 回执|清晰度原始观察|定性及直接失败项|
|---|---|---|---|---|
|CP3.headers.quality.0|3 次 / 1 次，均 200，Referer 正确|2 次 403，无 Referer|positive=true，negative=false|判据缺陷：旧 pool=false 被并入|
|CP3.headers.quality.1|3 次 / 1 次，均 200，Referer 正确|2 次 403，无 Referer|positive=true，negative=false|判据缺陷：旧 pool=false 被并入|
|CP3.headers.quality.2|3 次 / 1 次，均 200，Referer 正确|2 次 403，无 Referer|positive=true，negative=false|判据缺陷：旧 pool=false 被并入|
|CP3.headers.quality.3|3 次 / 1 次，均 200，Referer 正确|2 次 403，无 Referer|positive=true，negative=false|判据缺陷：旧 pool=false 被并入|
|CP3.headers.quality.4|2 次 / 0 次，均 200，Referer 正确|2 次 403，无 Referer|positive=true，negative=false|判据缺陷：旧 pool=false 被并入|

七批服务端回执中，带正确 Referer 的 quality 请求被 403 的次数均为 0。第六轮两批完整 requests 文件各观察到 3 次 `/index0.ts`，均带正确 Referer、200；这些分片 query 为空，不能按 case 逐条归属。不能把未观察到原生 index 请求等同于旁路探测失败：列表探测只拉 master，且夹具很快释放实例。

## 代码契约及四种疑点

当前仓库没有名为 `MovaQualityProbe` 的类或接口；对应路径为 `MovaEngine.loadQualities()` / `_probeQualities()`（`lib/src/core/engine.dart`），HLS 解析为 `parseHlsMasterPlaylist`（`lib/src/core/model/quality.dart`）。

1. `open` 默认可自动启动探测；显式 `loadQualities` 与同会话、同源正在进行/已完成的探测复用 Future。探测通过 `movaFetchWithHeaders(_fetcher, masterUri, source.requestHeaders)` 拉取 master。默认 `MovaIoHttpFetcher` 实现 `MovaHeaderedHttpFetch`，头逐请求设置，不泄漏给下一源。旧自定义 fetcher 仍兼容 `get(Uri)`，没有带头能力时只退化并 debug 提示；本夹具使用默认引擎，不是该退化情形。
2. 带头源：`Referer=https://cp3.example/authorized`，master 应为 200。`referer_server.py` 明确返回一个 640x360、400000 带宽的变体 `/index.m3u8?case=quality-N-yes`；解析结果应为 **auto + 360p 共两档**，初始 `currentQuality` 为 auto。STATE 中显示“自动”只表示当前档，不能推出列表只有 auto。
3. 无头源：同一防盗链 master 应 403；fetcher 返回 null，探测列表为空、默认当前档清空。这是正确的拒绝对照，不能期待与带头源相同的档位。无鉴权要求的普通 HLS 才应在无头时仍正常发现变体。
4. “带头仍被 403”：本次原始回执排除；“变体为空”：positive=true 排除原始列表为空。“只有 auto”：旧 CHECK 未保存完整列表，不能单凭 positive 排除，但当前解析器仅在至少一个真实变体存在时才添加 auto，夹具 master 也含真实变体，代码不支持此解释。“选档后 path 不匹配”：旧 quality 分支没有调用 `switchQuality`，没有选档后 path 证据，不能定性为选档失败或声称已验过。

因此**已能确定五条 FAIL 的直接成因**；完整档位和选档落地的真机验收仍缺证据。补证需每条保存完整 qualities、预期变体 URI、选档原生 path 及异常、正负请求回执，用新 APK 执行，不能以列表非空或 `open` 接受代替。

## 本次夹具修改

- 新增纯判据 `cp3_headers_criteria.dart`。启用 `CP3_HEADERS_READY` 时必须具备并通过 extract、pool-ready、pool-ready-cutover，旧 pool 保留全部采样和失败记录作对照；未启用时仍要求 extract 和旧 pool。新必需路径缺失也失败，避免空集合误通过。
- quality 正对照保存完整档位，要求 auto + 360p、变体 URI 匹配；选择真实档位并读回原生 path，地址错误或超时失败并保留异常。负对照保留“任何非空列表即异常”的语义，不能以选档失败掩盖鉴权泄漏。
- CHECK 保存采用的截图判据及 `captureReady` 开关。缩略图、预取及所有旧原始对照继续保留。CHANGELOG 已记录夹具行为变化。

## 离线验证

|验证|结果|
|---|---|
|开跑前清理 flutter_tester|已执行用户指定命令|
|example `flutter analyze --no-pub` 前后对照|均 41 issues；逐条诊断比较无差异，新增 0|
|example `flutter test --no-pub test/cp3_headers_criteria_test.dart --reporter expanded`|12/12；回退聚合判据后恢复，再跑仍 12/12|
|回退聚合判据为旧 `paths.values.every(pass)`|11 PASS / 1 FAIL；第六轮 pool=false、新截图=true 的回归变红 **1 条**，随后恢复修复|
|根 `source_headers_test.dart` + `engine_quality_probe_test.dart`，concurrency=3|19/19；覆盖带头 fetch、无头不泄漏、探测会话去重/旧结果丢弃等|
|`python run_matrix.py --check`|CHECK PASS：92 batches / 135 IDs / 6 manual，无设备操作|
|`python -m unittest test_run_matrix test_cp3`|72/72（66 + 6）|

本次共运行 103 个通过的测试用例（12 + 19 + 72；重复执行不重复计数），外加矩阵静态检查。产品修复 0 条、产品回退变红 0 条；夹具回退变红 1 条。没有产品代码改动，未触发产品修改后的全量测试/analyze 门禁，未重跑基线 2448 全量测试。

## 新 APK 复验范围

用包含本次夹具的 APK，开启 `CP3_HEADERS_READY=true` 和 `CP3_HEADERS_R4=true`，重跑 cp3-headers 原 15 条 CHECK。逐条确认 quality.0..4 的授权 master 200、auto + 360p、选档原生 path 等于变体 URI、无头 master 403 且列表为空；抽帧及普通/cutover 新截图正负对照仍全部通过，旧 pool 失败仅保留诊断。thumb/prefetch 原 10 PASS 也需保持。

本次不生成、不安装新 APK，没有新的设备 PASS 结论；历史 10 PASS / 5 FAIL 不变。无需放宽产品截图 2 秒契约，也不以离线判断替代原生播放/选档证据。
