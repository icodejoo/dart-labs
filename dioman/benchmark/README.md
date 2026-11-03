# 洋葱管线性能验证

新版入口：

```powershell
dart run benchmark/pipeline.dart
python tool/pipeline_b6_bench.py --out coverage/bench-recheck
python tool/pipeline_b6_bench_summary.py --out coverage/bench-recheck
```

交错脚本每次运行 A1 B1 A2 B2 A3 B3，A 使用 tool/bench_legacy.py 固定的 895d959 临时 worktree，B 使用当前新版。临时 worktree 创建在本工作区，finally 删除；不移动主工作区分支。重复完整一组可用 --set 2；汇总脚本使用同样的 --set 和 --out 参数，独立目录避免覆盖历史证据。

R4b 起，两个 runner 共用 `tool/dioman_bench_load.py`：独立进程运行中逐秒使用 Windows GetSystemTimes 与独立作业对象累计 CPU 时间差（包含已退出子进程），按同一系统分母扣除基准树占用。外部均值须 ≤20%，不得连续三个一秒采样点 >35%；丢点或间隔 >2s 作废。起跑前须连续三个采样点均值 ≤15%、最大 ≤25%。任一成员污染则整对 A/B 作废并重跑，每轮最多五次，任务预算 30 分钟；超时保留已有曲线，停止测量，不降低规则、不跨时段拼轮。

原始输出、每秒负载点与等待曲线保存在 `coverage/r4b-raw/`；证据只保留逐次污染原因、接受标记与小摘要。优先级须先做普通/高优先级旧版自身干净三轮试验，只有六场景极差的中位数降低才使用 `--high-priority`；以 dart run 的相同参数直接启动同 Flutter SDK 的 dartvm.exe，避免启动器另启普通优先级 VM，旧版 runner 同样显式传递 HIGH_PRIORITY_CLASS，不使用实时优先级。先前仅因启动器优先级传递不完整而中止的未完成试验组整体留在 coverage，不参与优先级比较。预登记规则见 [R4b harness](../docs/reports/round2-r4b-evidence/preregistered-harness.json)。

每场景先验证发送数，再预热 500ms、正式测量至少 2s。每次独立 JIT 进程。mean 是操作端到端均值，p99 使用最近秩，ops/s 包含采样 bookkeeping。构造与释放不计时。S5 一次操作是 100 个并发请求，单位为组/秒。

| 场景 | 内容 |
|---|---|
| S1 | 裸 Dio，新 JSON 信封与真实 Transformer |
| S2 | 客户端无插件 |
| S3 | 全插件，递增 query，cache/share 开启且缓存持续未命中 |
| S4 | 同样全插件，固定 key，memo 命中，正式发送数必须为零 |
| S5 | share(start)，100 并发同 key，每组一次传输 |
| S6 | 嵌套 Map/List POST，retry(max=2) 安装但不触发 |

三轮吞吐极差为 (max/min-1)×100%，必须小于 10%。按吞吐中位数选整行，不能拼接不同轮的延迟。S2/S3 先逐轮计算 mean(Sn)/mean(S1)-1，再取三个比例的中位数；汇总 JSON 同时保存三个比例与选中轮次。R4b 按场景依赖判定稳定性：S2/S3 另需 S1 稳定，S4/S5/S6 检查自身；依赖不稳定时 gates JSON 的 passed 为 null，同时保留 groupStable 整组标记，不从不同时段裸 Dio 绝对延迟相减；其它门槛与限制见 [测试方案 §6](../docs/design/pipeline-test-plan.md)。不稳定数字仅留档。

简单热点计时：dart run benchmark/pipeline_profile.dart。它在阶段 pre/post 插入探针，先预热 1000 次，再计 5000 次。时间差含探针开销，source:post 包含 Dio 与响应归一化；只作热点线索，不参与性能门槛。

[B6 报告](../docs/reports/2026-10-29-pipeline-b6.md) 保存两组交错数据与结论；B0 历史基线不替代同期 A/B。

[R4 报告](../docs/reports/2026-11-03-round2-r4.md) 保存四组补测、两项优化实验、克隆开关和最终旧版对照。两项候选均因无法证明满足事前阈值而撤回，快照行为回归保留；运行时与 R3 相同。

针对性微基准：

```powershell
dart run benchmark/round2_r4_micro.dart
dart run benchmark/round2_r4_micro.dart clone-off
dart run benchmark/round2_r4_micro.dart clone-on
```

同步诊断每批 100 次操作，分别测请求构造、patch、导出、URI、严格 JSON 与构键。克隆实验使用相同的 S6 类嵌套 POST 与 attempt 探针，只切换 markReplayable，避免关闭 retry 时同时移除其余插件成本。均预热 500ms、正式至少 2s；mean 使用总时间/次数，包含循环 bookkeeping，只用于同一入口内的对照，不替代标准 S1–S6 门槛。

## R4b 本轮执行与停止状态

本轮固定旧版 895d959，对照 R6 后的 797a9f4d；保持普通优先级。直接调用已入库 campaign 的 baseline-only 流程与 followup，各任务使用新的空原始目录，整轮共享同一个新建的 1800 秒 deadline；不能沿用上次中断的 deadline 或重置预算续测。原始记录为 `coverage/r4b-raw/20261103-145823/`，小摘要在 `docs/reports/round2-r4b-evidence/`。本地薄调用文件只指定新目录与截止时间，没有重写门控或改变事前规则。

三组基线、两个旧候选及克隆开关均完成干净三轮；干净不等于稳定，三组基线的整组标记与五项场景依赖判定均不稳定。两个候选不满足全部事前保留阈值，已恢复 lib 原字节。独立终测第一轮始终没有取得干净配对，30 分钟预算耗尽即停止，不拼轮或补开预算。13 个完整污染配对作废、另 1 对未完成；详细数据及稳健口径裁决请求见 [R4b 报告](../docs/reports/2026-11-03-round2-r4b.md) 和 [汇总](summary.md)。
