# 洋葱管线性能验证

新版入口：

```powershell
dart run benchmark/pipeline.dart
python tool/pipeline_b6_bench.py
python tool/pipeline_b6_bench_summary.py
```

交错脚本每次运行 A1 B1 A2 B2 A3 B3，A 使用 tool/bench_legacy.py 固定的 895d959 临时 worktree，B 使用当前新版。临时 worktree 创建在本工作区，finally 删除；不移动主工作区分支。重复完整一组可用 --set 2；汇总脚本使用同样参数。

每场景先验证发送数，再预热 500ms、正式测量至少 2s。每次独立 JIT 进程。mean 是操作端到端均值，p99 使用最近秩，ops/s 包含采样 bookkeeping。构造与释放不计时。S5 一次操作是 100 个并发请求，单位为组/秒。

| 场景 | 内容 |
|---|---|
| S1 | 裸 Dio，新 JSON 信封与真实 Transformer |
| S2 | 客户端无插件 |
| S3 | 全插件，递增 query，cache/share 开启且缓存持续未命中 |
| S4 | 同样全插件，固定 key，memo 命中，正式发送数必须为零 |
| S5 | share(start)，100 并发同 key，每组一次传输 |
| S6 | 嵌套 Map/List POST，retry(max=2) 安装但不触发 |

三轮吞吐极差为 (max/min-1)×100%，必须小于 10%。按吞吐中位数选整行，不能拼接不同轮的延迟。S2/S3 比较相对本轮 S1 的比例开销，不从不同时段裸 Dio 绝对延迟相减；其它门槛与限制见 [测试方案 §6](../docs/design/pipeline-test-plan.md)。不稳定数字仅留档。

简单热点计时：dart run benchmark/pipeline_profile.dart。它在阶段 pre/post 插入探针，先预热 1000 次，再计 5000 次。时间差含探针开销，source:post 包含 Dio 与响应归一化；只作热点线索，不参与性能门槛。

[B6 报告](../docs/reports/2026-10-29-pipeline-b6.md) 保存两组交错数据与结论；B0 历史基线不替代同期 A/B。
