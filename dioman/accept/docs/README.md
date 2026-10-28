# dioman testkit 执行器

复用已启动的 `http://127.0.0.1:47080` 与 `http://127.0.0.1:47090`。不管理服务进程，每个轮次使用独立 `X-Test-Run`；只清理自己创建且记录了 id 的代理。遇 429/503 或服务不可达停止，主动注入 429/503 的既有场景继续明确跳过。

## 目录与运行

| 位置 | 职责 |
|---|---|
| `accept/bin/` | cli、矩阵生成/执行、inventory、audit、字面量维护、share 专项探针入口 |
| `accept/lib/` | runner、client、probes、common、powerset、pairwise、plugin_rules、literals；API 清单与五方法执行计划 |
| `accept/docs/` | 映射、中文矩阵、历史覆盖及源码复核说明 |
| `accept/results/` | 原始历史证据，只读保留 |
| `coverage/accept/` | 本轮及后续命令的新证据、代理归属日志 |
| `coverage/reorganization/` | 整理前后测试、lcov、验收对比与文件校验记录 |

以下命令均从 dioman 根目录运行：

```powershell
dart test
dart test -t real --configuration=dart_test.real.yaml --fail-fast
dart run accept/bin/cli.dart --networks=normal --styles=http --jobs=1 --report=coverage/accept/normal-http.json
dart run accept/bin/run_plugin_matrix.dart
```

当前 test 包的 `exclude_tags` 优先于 `-t`，所以默认配置排除 real，真实测试必须用独立配置解除排除；单独 `dart test -t real` 无法选择到被默认排除的用例。真实测试不再需要 DIOMAN_ACCEPT / DIOMAN_ACCEPT_POWERSET；DIOMAN_ACCEPT_ARGS 可覆盖场景矩阵参数。默认真实测试执行 154 个确定性组合、公开 API 探针和 normal×http 全场景；其余网络/风格使用 CLI 显式指定，不将未执行项算作通过。

CLI 参数：`--filter=场景id子串`、`--networks=normal,weak`、`--styles=http,business`、`--testkit=绝对目录`、`--report=报告路径`、`--jobs=1..4`。完整 JSON 在结束时生成，逐项 NDJSON 在运行中追加。TESTKIT_SERVER / TESTKIT_NETEM 可覆盖完整服务地址，上游从业务地址派生。

## 维护入口

```powershell
dart run accept/bin/build_plugin_matrix.dart
node E:/workspaces/api-ws-demo/testkit/tools/gen-index.mjs
node E:/workspaces/api-ws-demo/testkit/tools/validate.mjs --check-index
dart run accept/bin/inventory.dart
dart run accept/bin/hoist_literals.dart
dart format test accept
dart run accept/bin/share_prepare_probe.dart
dart run accept/bin/audit.dart coverage/accept/normal-http.json
```

生成器将单体和边界写回相应领域，plugins.json 保留配对和全量；矩阵执行器从全部领域加载 id。两组缺省等价零值边界已合并，详情见 [测试映射](../../test/README.md)。`share_prepare_probe.dart` 保留用于 multipart 重放准备失败的双风格专项复验；`hoist_literals.dart` 保留为可重复执行的维护工具，相邻字符串按完整值提取。历史一次性 review_skips.py / write_review_report.py 已删除，历史证据保持原样。

能力与错误映射见 [mapping.md](mapping.md)，历史五方法结果见 [MATRIX-plugins.md](MATRIX-plugins.md)，源码复核见 [REVIEW-library.md](REVIEW-library.md)。API 构造/读取/调用登记、选项值覆盖和 lib 行覆盖分别报告，不能互相替代。历史未声明组合、未穷尽的单体选项及边界不因本次结构整理变为已完成。
