
## 需求和不变量

### STEADY 第六轮（带打点稳态与 /proc CPU）

| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| STEADY-01 | 帧号关联、嵌套去重、缺失证据不填零 | 用户 STEADY；TEST_STRATEGY §7.9 | `test/tool/bench_steady_test.dart :: bench STEADY > attributes paired frames without nested double counting` | 单元/工具 | 已落地 |
| STEADY-02 | 四稳态场景与 wheel CPU 启动有界 | 用户 STEADY；TEST_STRATEGY §7.9 | `test/tool/bench_steady_test.dart :: bench STEADY > plans four instrumented scenes and proc wheel CPU with bounded starts` | 单元/工具 | 已落地 |
| STEADY-03 | slot 入场 trace 不混入稳态 GC 参照 | 用户 STEADY；TEST_STRATEGY §7.9 | `test/tool/bench_steady_test.dart :: bench STEADY > keeps slot entry trace separate from steady GC reference` | 单元/工具 | 已落地 |
| STEADY-04 | 有效 /proc 结果显式标识且解析错误仍抛出 | 用户 STEADY；TEST_STRATEGY §7.9 | `test/tool/bench_steady_test.dart :: bench STEADY > marks validated proc deltas explicitly valid for device orchestration` | 单元/工具 | 已落地 |

### STEADY 真机证据（单台 V2417，不把采集成功当达标）

| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| STEADY-05 | slot_raster 带打点三轮与入场图集帧号 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；3/3，未污染3，冻结门禁失败 |
| STEADY-06 | grid_steady 带打点三轮 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；3/3，未污染3，冻结门禁失败 |
| STEADY-07 | lotto_draw 带打点与污染边界 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；4/5，未污染2，UI P99失败 |
| STEADY-08 | lots_shaking 稳定性复测 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；3/3，未污染3，本轮通过；历史根因无法判定 |
| STEADY-09 | wheel /proc 进程及合并UI/Raster三轮 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；3/3，CPU仅标定 |
| STEADY-12 | lotto候选复用画笔三轮复测与回滚 | 用户 STEADY；TEST_STRATEGY §7.9 | `tool/bench/integration_test/pending_bench_test.dart :: pending > selected device check` | 真机基准 | 已落地；3/3未污染，净收益不稳定且UI P99仍失败，已回滚 |
