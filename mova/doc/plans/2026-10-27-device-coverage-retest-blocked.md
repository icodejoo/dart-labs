# 2026-10-27 Android 修复后复测

本次状态：**BLOCKED，开测前设备锁屏，按用户要求立即停止**。没有执行真机测试，不能给修复项标记 PASS/FAIL。所有本次证据位于 `example/tool/coverage_evidence/`，前缀 `rerun2-`。

## 开始：工程约定与开测安全检查

先读取 CLAUDE.md、上一轮复跑报告及现有构建/驱动脚本，再检查指定设备的锁屏与亮屏标志，确保真机证据有效；若锁屏，停止后续执行。

检查点（2026-10-27 20:50，Asia/Shanghai）：设备 `7NQBB23606003715` 实际为 `isKeyguardShowing=true`、`mScreenOnFully=false`，未满足开测门槛。首次检查与保存证据时均为此状态。已停止，未尝试唤醒、解锁或驱动 UI。

原始证据：

- `example/tool/coverage_evidence/rerun2-preflight-window.txt`
- `example/tool/coverage_evidence/rerun2-preflight-audio.txt`
- `example/tool/coverage_evidence/rerun2-preflight-power.txt`

## 基线与构建

- 本次 `flutter analyze lib test`、`flutter test` 未执行：开测检查触发用户的立即停止条件。预期 1516 不能作为本次实测数字。
- 上一轮报告实际基线为 analyze 2 issues、test 1424 通过且 1 文件加载失败；该历史结果不能代表当前修复后的工作区。
- 新 APK 未构建、未重打包、未安装；因此本次没有新构建 SHA256 或 lastUpdateTime，不能证明设备现装包包含新修复。
- 未改 `lib/`、`test/`、`packages/`，未操作 `../dioman` 改动，未执行 git commit/stash/reset/checkout。

## 五项复测台账及上轮对比

用户所述“5 个问题”按 F3、A17、A15/F5、A23、A12 列出；F3/A17 共用同一换档续播验证场景。

| 项目 | 上一轮 | 本次结论与次数 | 本次证据 |
|---|---|---|---|
| F3 换档续播 | FAIL，39/40；失败 RESTART 为 [23,23]ms | BLOCKED；代理播放 0/100、普通引擎 0/30、暂停态 0/30 | rerun2-preflight-window.txt |
| A17 清晰度切换续播 | FAIL，同 F3 的一次失败 | BLOCKED；与 F3 共用计数，本次 0 次 | rerun2-preflight-window.txt |
| A15/F5 MiniHost→enterPip→展开 | FAIL，mini=false 仍残留小窗 | BLOCKED；0 次，未读取 controller 或拍摄验证截图 | rerun2-preflight-window.txt |
| A23 二次 dispose | FAIL，两实现第二次抛 disposed | BLOCKED；普通 audioOnly 0 次、cutover audioOnly 0 次 | rerun2-preflight-window.txt |
| A12 setZoom 下限 | FAIL，-1/0 可塌缩，100 接受 | BLOCKED；-1/0/100 均 0 次 | rerun2-preflight-window.txt |

本次未进入媒体场景，没有产品失败最小复现或 EVENT/RESTART/duration/seek 时间线；不能以未执行推断修复成功或失败。恢复后仍须完成全部次数并保存每次 target、原生 RESTART 序列、landed、continued，任何未续播均判失败。

## 最终设备状态

停止时最后一次原生读回：锁屏且屏幕未 fully on；USB 常亮 `7`；媒体流未静音、speaker `6/20`，均见上述三份原始证据。没有修改常亮或音量，无须恢复。因立即停止条件，未执行后续 force-stop；本次也未启动测试包或服务，未安装 APK。

继续所需条件：用户将设备保持解锁亮屏，重新读回同时满足 `isKeyguardShowing=false`、`mScreenOnFully=true` 后再开测。
