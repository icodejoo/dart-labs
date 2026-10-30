---
name: dioman
description: 维护以 Dio 为引擎的 dioman 洋葱管线；修改 lib/src 前必读。
---

# 维护须知

Dart ^3.5.0，唯一运行依赖 Dio，不新增依赖。公开入口 lib/dioman.dart 使用 show 白名单；核心在 lib/src 平铺，插件在 lib/src/plugins。注释使用中文 ///。两个 README 的章节与行为保持一致。

## 改 lib/src 前必读

- docs/decisions/0001-pipeline-redesign.md
- docs/design/pipeline-architecture.md
- docs/design/pipeline-plugin-spec.md（含 §8.1、C1–C18）
- docs/design/pipeline-test-plan.md
- docs/design/pipeline-implementation-plan.md
- docs/guides/migrating-to-pipeline.md

## 阶段和边界

outer → prepare → attempt → credential → source → Dio。envs 只有 setup。固定内置顺序不能由注册顺序改写；自定义 pre/post 只在本阶段生效。插件工厂只放配置，setup 返回每客户端状态。禁止恢复宿主 setter、认领和手工结算基础设施。

next(patch) 从当前基准派生，链内返回归一化结果，程序错误只在公共边界原栈抛出。StateKey 使用非 const 身份键。await 等待用 ctx.wait，随后检查 ctx.cancelled()。多次发送先 markReplayable，先用 ctx.canReplay() 判断最近实际体，不能重放就返回本次结果，不能承诺单订阅流可重放。

## 不变量

- I1：每个逻辑请求恰好落定一次。
- I2：loading 回调成对，最后 false。
- I3：结束 pending=0，无残留取消订阅和计时器。
- I4：每个逻辑请求最多通知一次。
- I5：并发 401 每轮只刷新一次。
- I6：next 不抛异常；受控流程不出现 internal。
- I7：同一逻辑请求每次发送请求体一致，使用嵌套结构验证。
- I8：调用方自身取消或超时不污染其他调用方结果类别。
- I9：实际发送与回显必须等于调用方请求快照。

## 必跑验证

```sh
dart analyze
dart test
dart analyze example
dart test --coverage-path=coverage/local.info --branch-coverage
python tool/pipeline_b5a_coverage.py coverage/local.info --out coverage/audit
python tool/pipeline_b5a_mutations.py
dart run test/accept/bin/matrix.dart gates --lcov=coverage/local.info
```

覆盖率脚本参数见 --help；变异脚本无 CLI 参数，直接执行，保留证据。运行变异会临时改源码，必须检查恢复；仅文档任务不应运行会改 lib 的变异脚本。G0/G1/G2/G3/G5 必须保持通过；覆盖门槛见测试方案。真实 HTTP 超时与传输集成使用本地 HttpServer，纯规则用脚本化传输与假时钟；禁止用 fake 的绿灯声称网络行为成立。新增公开 API 同步台账与矩阵。文档新增、归档更新 docs/README.md 并跑 docs-index 检查。
