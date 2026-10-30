---
title: dioman testkit 验收执行器手册
status: active
updated: 2026-10-29
summary: 怎么连 47080/47090（或新端口实例）跑 testkit 场景、插件矩阵和维护工具。
---
# dioman testkit 执行器

复用已启动的 `http://127.0.0.1:47080` 与 `http://127.0.0.1:47090`。不管理服务进程，每个轮次使用独立 `X-Test-Run`；只清理自己创建且记录了 id 的代理。遇不带注入标记的真实 429/503 或服务不可达停止；testkit 主动注入的 429/503（响应体 `reason: injected`）由 `ServiceGuardAdapter` 放行，按真实预期执行（D20）。

## 新能力需要新服务端二进制

testkit 新增的场景（multipart、keep-alive、share-retry、timeout-send，以及 `meta.conn`、`read_delay_ms`、multipart 回显等服务端能力）只有新构建的 api-ws-demo 才有。长期占用 47080/47090 的旧实例不含这些能力，场景会因 `meta.conn` 缺失、回显无 `multipart` 等原因失败。做法：另起一对新端口的实例，用 `TESTKIT_SERVER` / `TESTKIT_NETEM` 指过去，不要停掉旧实例：

```powershell
# 在 api-ws-demo 里构建（旧实例占着 target/release 下的 exe 时，用 --target-dir 指到别处）
cargo build --release --target-dir <另一个目录>
$env:TEST_MODE = 1; $env:PORT = 47081; <目录>/release/api-ws-demo        # 业务服务
<目录>/release/netem --control 127.0.0.1:47091                           # 代理控制
curl http://127.0.0.1:47081/t/ping                                       # 应返回 {"code":0}

$env:TESTKIT_SERVER = 'http://127.0.0.1:47081'
$env:TESTKIT_NETEM  = 'http://127.0.0.1:47091'
dart run test/accept/bin/cli.dart --filter=auth.expired-multipart-replay --networks=normal --styles=http,business --jobs=1 --report=coverage/accept/tk-new.json
```

跑完关掉自己起的两个进程。

## 目录与运行

| 位置 | 职责 |
|---|---|
| `test/accept/bin/` | cli、矩阵生成/执行、inventory、audit、字面量维护、share 专项探针入口 |
| `test/accept/lib/` | runner、client、probes、common、powerset、pairwise、plugin_rules、literals；API 清单与五方法执行计划 |
| `docs/` | 映射、矩阵、覆盖与源码复核文档已归入项目 docs，见 [索引](../README.md) |
| `test/accept/results/` | 原始历史证据，本地保留，不入库（gitignore） |
| `coverage/accept/` | 本轮及后续命令的新证据、代理归属日志 |
| `coverage/reorganization/` | 整理前后测试、lcov、验收对比与文件校验记录 |

以下命令均从 dioman 根目录运行：

```powershell
dart test
dart test -t real --configuration=dart_test.real.yaml --fail-fast
dart run test/accept/bin/cli.dart --networks=normal --styles=http --jobs=1 --report=coverage/accept/normal-http.json
dart run test/accept/bin/run_plugin_matrix.dart
```

当前 test 包的 `exclude_tags` 优先于 `-t`，所以默认配置排除 real，真实测试必须用独立配置解除排除；单独 `dart test -t real` 无法选择到被默认排除的用例。真实测试不再需要 DIOMAN_ACCEPT / DIOMAN_ACCEPT_POWERSET；DIOMAN_ACCEPT_ARGS 可覆盖场景矩阵参数。默认真实测试执行 154 个确定性组合、公开 API 探针和 normal×http 全场景；其余网络/风格使用 CLI 显式指定，不将未执行项算作通过。

CLI 参数：`--filter=场景id子串`（逗号分隔多个，命中任一即选中）、`--networks=normal,weak`、`--styles=http,business`、`--testkit=绝对目录`、`--report=报告路径`、`--jobs=1..4`。完整 JSON 在结束时生成，逐项 NDJSON 在运行中追加。TESTKIT_SERVER / TESTKIT_NETEM 可覆盖完整服务地址，上游从业务地址派生。

## 维护入口

```powershell
dart run test/accept/bin/build_plugin_matrix.dart
node E:/workspaces/api-ws-demo/testkit/tools/gen-index.mjs
node E:/workspaces/api-ws-demo/testkit/tools/validate.mjs --check-index
dart run test/accept/bin/inventory.dart
dart run test/accept/bin/hoist_literals.dart
dart format test
dart run test/accept/bin/share_prepare_probe.dart
dart run test/accept/bin/audit.dart coverage/accept/normal-http.json
```

生成器将单体和边界写回相应领域，plugins.json 保留配对和全量；矩阵执行器从全部领域加载 id。两组缺省等价零值边界已合并，详情见 [测试分层](test-layers.md)。`share_prepare_probe.dart` 保留用于 multipart 重放准备失败的双风格专项复验；`hoist_literals.dart` 保留为可重复执行的维护工具，相邻字符串按完整值提取。历史一次性 review_skips.py / write_review_report.py 已删除，历史证据保持原样。

能力与错误映射见 [testkit 映射](../reference/testkit-mapping.md)，历史五方法结果见 [插件五方法矩阵](../reports/2026-10-27-plugin-matrix.md)，源码复核见 [源码复核](../reports/2026-10-27-library-review.md)。API 构造/读取/调用登记、选项值覆盖和 lib 行覆盖分别报告，不能互相替代。历史未声明组合、未穷尽的单体选项及边界不因本次结构整理变为已完成。

## 管线切换后

请求装配使用 Dioman 客户端，固定阶段由内核决定；cache/share 的中立默认由执行器显式开启。旧插件名只作为 testkit 能力标签，不能据此推断仍有同名插件类。当前字段和结果映射见 [映射](../reference/testkit-mapping.md)。默认真实测试数和历史 PASS 只描述对应记录，当前运行以实际输出为准。
