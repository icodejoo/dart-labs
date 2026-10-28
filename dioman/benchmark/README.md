# B0 旧版性能基线

```powershell
dart run benchmark/legacy.dart > benchmark/run-1.json
dart run benchmark/legacy.dart > benchmark/run-2.json
dart run benchmark/legacy.dart > benchmark/run-3.json
python benchmark/summarize.py
```

每条 `dart run` 启动独立 JIT 进程；一个进程依次跑 S1–S6，每场景先做发送数自检，再预热至少 500ms、正式测量至少 2s。构造、场景自检、预热、排序和资源释放不计入正式时间。`Stopwatch` 逐次采样，p99 用最近秩 `ceil(n × .99)`，平均值为操作端到端耗时的算术均值；ops/s 用操作数除以整段墙钟时间，包含采样 bookkeeping。

| 场景 | 构造与操作 |
|---|---|
| S1 | 裸 Dio，立即返回新信封的薄 adapter；真实 Dio JSON Transformer 每次解码出新 Map |
| S2 | 同一个 Dio 操作，调用旧 `Dioman.install` 且不传插件 |
| S3 | 全部旧插件 + mock adapter（无路由，回落），GET 递增 query，缓存和共享开启，memo 缓存持续未命中 |
| S4 | 和 S3 相同的全插件构造，固定 key，memo TTL 一小时；自检/预热已填充，正式计时发送数须为零 |
| S5 | key + share(start)，每次同时发 100 个同 key GET；整组完成才开始下一组，每组须只发一次传输 |
| S6 | 只装 retry(max=2)，每次新建嵌套 Map/List POST data，始终返回成功，不触发 retry |

S3/S4 安装 envs、timeout、repath、filter、key、cache、offline、share、cancel、loading、auth、retry、breaker、log、normalize、notify，并包装 mock adapter。auth 使用有效 token；offline 在线；mock 无命中；loading/notify/log 输出回调为空操作，但仍保留旧插件执行与格式化成本。cache 的 persist 仅满足旧构造契约，memo 不访问它。通知通过 `plugins` 参数安装。

S5 的 ops/s 是**组/秒**，延迟是**整组端到端延迟**，不得和单请求场景直接比较；乘以 100 才是逻辑请求/秒。原始数据同时保留操作数、发送数、正式秒数和每操作请求数。

稳定性以三轮吞吐 `(max/min - 1) × 100 < 10%` 判断，同时展示 mean/p99 的离散度。未达标只留档，不得据其差值宣称性能提升或负开销。取中位值时选吞吐中位数所在轮的整行，不能拼接不同轮的指标。

B5/B6 共用 `scenarios.dart` 的 `DiomanBenchClient`/`DiomanBenchFactory` 和 `runner.dart`，只另写新客户端构造器及入口；场景操作的 query、data、插件集合、cache/share 开关、TTL、自检计数必须等价。旧依赖都隔离在 `legacy_client.dart`，删除旧 API 后不应把它混入新入口。需要交错 A/B 时在保留旧源码的独立版本运行旧入口，再运行新入口：A1、B1、A2、B2、A3、B3，每次独立进程；不能把本批旧数值与未来不同时段的新数值直接当作 A/B。

本批环境、三轮数据和限制见 [B0 报告](../docs/reports/2026-10-29-pipeline-b0.md)。
