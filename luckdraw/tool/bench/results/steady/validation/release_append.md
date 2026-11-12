

## STEADY 第六轮本机门禁与收尾

已回滚库候选后的最终实现：新增工具4条，四组覆盖全部145个测试文件，1112/1112通过、零失败跳过；工具单独227通过。实验阶段lotto36条仅为拒绝实验历史，不计作最终新增。

| 命令 | 实际输出摘要 |
| --- | --- |
| analyze | exit=0，7.254s；Analyzing luckdraw...                                            / No issues found! (ran in 5.3s) |
| bench_analyze | exit=0，5.333s；Analyzing bench...                                               / No issues found! (ran in 3.5s) |
| format | exit=0，2.045s；Formatted 361 files (0 changed) in 0.86 seconds. |
| format_check | exit=0，1.892s；Formatted 361 files (0 changed) in 0.85 seconds. |
| tools | exit=0，38.401s；227 passed; failed=0; skipped=0 |
| steady-a | exit=0，71.916s；554 passed; failed=0; skipped=0 |
| steady-b | exit=0，36.24s；130 passed; failed=0; skipped=0 |
| steady-c | exit=0，75.947s；405 passed; failed=0; skipped=0 |
| steady-d | exit=0，9.634s；23 passed; failed=0; skipped=0 |
| coverage | exit=0，1.52s；TOTAL: 6878/6878 (100.00%) / PASS: coverage >= 100.0% |
| imports | exit=0，1.916s；PASS: 145 lib files; IMP-R1…R12 / 依赖图与静态规则通过 |
| acceptance | exit=0，1.528s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| acceptance_json | exit=0，1.425s；PASS: 1564 references resolve; 1137 registered tests all mapped. / 全部测试引用有效且无遗漏 |
| parity | exit=0，10.874s；PASS: parity manifest 16 cases, 96 artifacts; hashes and frames verified |
| publish | exit=0，4.507s； / Package has 0 warnings. |

LCOV独立使用coverage/steady-{a,b,c,d}.lcov，验证四组并集后合并coverage/steady.lcov；JSON仅平移ID/时间合并真实事件，--from-json校验通过。日志与执行元数据见tool/bench/results/steady/validation，逐组真实计数在test_summary.json。

真机A：slot/grid/lots各3/3；lotto4/5、未污染2；wheel CPU3/3。lotto候选复测3/3未污染，但无稳定净收益且UI P99仍失败，已回滚。原实现grid/slot/lotto仍失败，lots本轮通过，不放宽预算。原始时间线57份（含response）无损gzip校验后归档；拒绝实验diff只作历史，不应应用。

手机收尾：stay_on=2、亮度模式0、亮度1，dumpsys display为ON、Awake且未锁；reverse为空。卸载exit1/DELETE_FAILED_INTERNAL_ERROR，但pm list packages与pm path均空，实测无bench包。没有改手机设置或批杀java；自有进程末检在真实仓库复验后追加。

[STEADY完整报告](../tool/bench/results/steady/REPORT.md)，[逐帧归因](../tool/bench/results/steady/ATTRIBUTION.md)。副本完成所有本地门禁，真实库不覆盖，回拷仅工具/测试/文档且共享文件重读定点追加。
