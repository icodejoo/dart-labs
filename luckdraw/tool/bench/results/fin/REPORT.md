# FIN 离线基准重算（2026-11-10）

未连接手机；原始报告不改写。DEV 与 PERF 分开列出，最终比较采用 PERF 五个修复场景与 DEV 其余场景。字节差直接从 rss_blank[last] − rss_blank[first] 计算；负差表示回收，门禁按零计。首次预热仅信息，建议6MiB不写入预算。RSS 不用相对极差判泄漏；确定性释放由现有 dispose 计数测试保证。

| 来源 | 场景 | 稳态原值1 / 2 / 3（B） | 中位数（B） | ≤1572864 B |
| --- | --- | --- | --- | --- |
| DEV | capsule_mixing | 1163264 / 856064 / 1417216 | 1163264 | PASS |
| DEV | grid_steady | -10981376 / 831488 / 466944 | 466944 | PASS |
| DEV | lever_steady | 753664 / 1523712 / -4182016 | 753664 | PASS |
| DEV | lots_shaking | 819200 / 802816 / -10776576 | 802816 | PASS |
| DEV | lotto_draw | 843776 / 905216 / 221184 | 843776 | PASS |
| DEV | memory_cycles | 933888 / 106496 / 1224704 | 933888 | PASS |
| DEV | number_wheel_spin | 1576960 / 851968 / -2052096 | 851968 | PASS |
| DEV | slot_raster | 483328 / -929792 / -970752 | -929792 | PASS |
| DEV | slot_steady | 331776 / 331776 / 77824 | 331776 | PASS |
| DEV | wheel_steady | 1540096 / -114688 / 1179648 | 1179648 | PASS |
| PERF | wheel_steady | -2789376 / 1323008 / -10059776 | -2789376 | PASS |
| PERF | number_wheel_spin | 1110016 / -2125824 / 1409024 | 1110016 | PASS |
| PERF | capsule_mixing | 585728 / 1208320 / 487424 | 585728 | PASS |
| PERF | lotto_draw | 1163264 / -8925184 / 1470464 | 1163264 | PASS |
| PERF | grid_steady | -565248 / 933888 / 925696 | 925696 | PASS |

## UI 平均耗时预算

| 场景 | PERF三轮中位数 ms | 新预算 ms |
| --- | --- | --- |
| wheel_steady | 0.956402 | 1.0 |
| number_wheel_spin | 1.131299 | 1.3 |
| capsule_mixing | 1.654103 | 2.0 |
| lotto_draw | 2.171597 | 2.5 |
| grid_steady | 1.024326 | 1.2 |

预算按批准值更新。wheel 0.956ms 保持1.0ms是明确例外；若严格×1.1并向上取0.1ms则为1.1ms，未据此扩大已批准预算。capsule/lotto若统一按0.1ms取整会得到1.9/2.4ms，本轮遵循明确批准的2.0/2.5ms。Raster、掉帧率以及其余指标预算保持原文件值。

默认 auto 缓存使转盘典型帧 Raster 由约16.4ms降到约5ms，AB2 的 Impeller 三轮极稳；vivo V2417 / Android16 仍约三成轮次整轮处于12–17ms高档，与亮度、监控轮询、Skia/Impeller均无关，根因未解释，不是luckdraw已知缺陷，也未证明设备缺陷。真机性能验收未完全通过；转盘/数字转盘/大乐透因双峰判不稳定。

最终75项指标中10项中位数超预算、23项不稳定（有重叠），合计30项未通过、45项通过；首帧40.378ms超过4ms，额外的grid/slot/lots等不稳定及其余超标也完整保留，不能只报告三个双峰玩法。

完整原始路径、SHA-256、预热原值见 [rss_recalculated.json](rss_recalculated.json)。[comparison.txt](comparison.txt) 保留真实 CLI 输出与失败状态；所有场景的逐指标原值/中位数/上限/稳定性见 [metrics.json](metrics.json)。
