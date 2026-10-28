# Q13B / Q13C 间歇失败分诊（full-01）

> 日期 2026-10-29。数据来自 full-01 的 `rerun-batch10-mute` 日志（`example/tool/coverage_evidence/matrix-full-01/matrix-full-01-rerun-batch10-mute.log`，已 gitignore）。
> 结论强度：**耗时规律为实测，因果归因为推断**，未上机复现。

## 现象

Q13（预热期间静音只改 mpv `mute`、不写系统音量）本轮：Q13A 5/5 通过，Q13B 4/5、Q13C 4/5。
两次失败的判据行均为 `swapped=false committed(live k2).mute=gone ...`，即**影子引擎 k2 在提交时已不存在**，
而不是 mute 读回错误。上一轮为 5/5。

## 实测耗时（从“请求待机/唤醒”到 `committed`）

| 用例 | 通过的 4 次 | 失败的 1 次 |
|---|---|---|
| Q13B | 4.0 / 4.6 / 4.5 / 4.3 s | **12.5 s** |
| Q13C | 4.4 / 4.2 / 4.6 / 4.2 s | **13.4 s** |

两次失败都比正常路径多出约 8 s–9 s。`MovaCutoverConfig.readyTimeout` 默认值是 **8 秒**
（`lib/src/core/options/cutover_config.dart:79`，`cutover_engine.dart:489` 用它作为就绪期限）：
正常 ≈4.5 s 就绪，加上一次 8 s 等待恰好落在 12.5–13.4 s。

## 判断（推断）

失败那次的影子引擎在 8 s 内没有达到就绪判据 → cutover 按设计**放弃预热、走非无缝降级路径**
→ 影子引擎被丢弃（所以 `k2=gone`）→ 探针按“必须 swapped=true”判 FAIL。

- **不是** mute 误写系统音量（Q13 要防的缺陷）：`k1.mute` 全程 `no`，没有系统音量写入。
- 降级路径本身是设计内行为（广告/预热“放弃后正片照常播”已有真机用例覆盖）。
- **待查**：为什么 5 次里有 1 次影子引擎 8 s 内没就绪（本机 HTTP 直播源的缓冲抖动？还是
  “待机请求发生在预热中”这个时序下就绪判据读不到缓冲？）。通过的运行里“shadow k2 loaded”约 4.5 s。

## 建议

1. 设备解锁后单独复现：Q13B/C 各跑 ≥20 次，记录影子引擎的 `buffer`/`MovaBufferWarm` 判据读数和是否触发超时，
   区分“源抖动”与“待机请求期间判据失效”。
2. 若证实是源抖动：探针应允许“放弃预热则 swapped=false”这条降级（并另记一次），避免把设计内降级当 FAIL。
3. 若证实判据失效：才是产品缺陷，另开修复。
