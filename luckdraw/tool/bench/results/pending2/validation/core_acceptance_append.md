
## 需求和不变量

| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| INSTR-18 | 时间线、CPU 解析与等价性回归 | 用户 INSTR；TEST_STRATEGY §7.8 | `test/core/text/instr_text_equivalence_test.dart :: TextPainterMeasurer INSTR > cached widths and lineClamp match uncached multilingual and emoji shaping` | 单元/工具 | 已落地 |
| INSTR-19 | 时间线、CPU 解析与等价性回归 | 用户 INSTR；TEST_STRATEGY §7.8 | `test/core/text/instr_text_equivalence_test.dart :: TextPainterMeasurer INSTR > repeated width hits avoid layout and dispose invalidates the bounded cache` | 单元/工具 | 已落地 |

## 覆盖率豁免

| 编号 | 文件 | 位置 | 原因 |
| --- | --- | --- | --- |
| COV-02 | lib/src/core/render/perf_trace.dart | 第14行 | luckyTraceStart 的 arguments.layouts Map 表达式仅在编译期 LUCKDRAW_TIMELINE=true 分支执行；默认单测无法到达，逐行豁免这一行，调用/结束沿用 COV-01 |
