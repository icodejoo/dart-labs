# CP1 逐项收口

本人执行，不转派；只修改 wt-mova-cp1/mova。历史报告中的原始 FAIL 不删除，以下为修正后的独立复测。

## 1. H28 落点采样

旧证据：`example/tool/coverage_evidence/matrix-cp1-android-h28-20261103-1703-cp0-h28/cp0-result.json`，verdicts[32,77]；对应 gap.json rows[8216,16944]。

- 暂停组在 09:05:23.915Z 读到 12 秒，09:05:24.005Z 再读为 0 秒；尚未到现有产品 1500ms 续播校验点，验证页已报失败并开始新 seek，使原校验链作废。
- cutover 的继续播放判断以错误的 `landed=0` 为起点，0→343ms 也能满足旧的 `> landed+300`，没有证明目标附近继续推进。
- 新增产品复现测试覆盖“目标回声→归零→现有校验链补发收敛”，播放/暂停两条均在未改 lib 时通过。产品恢复链未显示漏判；本项修正验证页，保留 500ms 初次落点误差及暂停意图判据。
- 新采样必须 path 匹配、原生 seeking=no，持续 400ms 并等 buffering=false 后才完成。初次原生落点独立于可能迟到的 Dart buffering 标志保存。播放组验证按时钟推进，报告该稳定窗的初次落点；暂停组验证位置稳定。后续推进不得回到目标之前。
- 旧采样逻辑的隔离副本使最终 4 条采样测试全红；新采样通过。副本及原始输出放在 `example/tool/coverage_evidence/h28-red/red-tests.log`。产品复现两条无需改 lib 即绿。
- 第一轮收口复测 `cp1-close-h28-1805` 因采样错误地要求播放中的整个稳定窗均处于目标±500ms而中止；归入验证器问题，原始记录保留，不计产品结论。
- 第二轮 `cp1-close-h28-r2-1810`：30/30、30/30、29/30。cutover iteration=27 的原生序列证明原校验链实际补发并恢复：1410ms 时归零，2032ms 再次 seek，2614ms seeking=no 且 position=12463ms；2705ms Dart buffering 才清除，position=12503ms。验证器把迟到的 UI 标志错误地用作落点计时起点，导致 3ms 假超限；完整稳定采样保留。修正后不扩大误差线，记录原生 12463ms 初次落点并另等 UI 缓冲清除。
- 全量首跑 2086 PASS / 7 FAIL；7 条均为 B09 的 `.dart_tool/b09` 父目录缺失。补齐工作区本地目录后重跑，不修改产品或既有测试来绕过错误。

最终复测 `cp1-close-h28-r3-1818`：playing/paused/cutover 各 30/30 PASS，90 次零失败，最大绝对落点误差分别 463/23/463ms，harness=[]。证据：`example/tool/coverage_evidence/matrix-cp1-close-h28-r3-1818-cp0-h28/cp0-result.json` verdicts[0..89] 与同目录 gap.jsonl 的逐次原生采样；宿主完成元数据 `example/tool/coverage_evidence/cp1-close-h28-r3-1818-completion.json`。APK 拉回哈希 `979e3d9ba3f8d45beb1425634636c77fe9b6d174de36819d2c573e658c989cf4`；构建证据 `matrix-cp1-build-20261103-181605`。子驱动和外层均执行设备设置恢复，读回 USB 常亮=7、媒体音量=0。

最终验证：全量 `flutter test --concurrency=3` **2094 PASS**（`cp1-close-h28-tests-r3.log`）；相关测试 21 PASS（其中新增产品复现 2 条、采样 4 条）；采样回退 4 FAIL→4 PASS；`flutter analyze lib test` 0 issues（`cp1-close-h28-analyze-r3.log`）。上述日志均在 `example/tool/coverage_evidence/`。

## 2. Skin 快照同步

设计核对：总计划 B14（577 行）明确锁定按钮进入组件树，落地记录（588 行）明确默认树加入 lockToggle 并同步 Bilibili 基准；C 块 `2026-11-03-c04-c06-chrome-style.md` 的 C06 文件清单仍包含默认皮肤锁定按钮（834 行）。这是设计内组件，不能删除来匹配旧验证页。

精确快照为 default/bilibili 完整树和 patch 树分别补上 `lockToggle@overlay`；Bilibili patch 期望改为按固定节点名映射 topBar/danmakuTrack，其余节点逐个原样保留，避免固定 sublist 截掉新组件。仍使用有序列表全量相等、真实挂树与点击判据。产品代码无修改。

`flutter test --concurrency=3 test/ui/skin_test.dart test/ui/bilibili_skin_test.dart test/ui/b14_test.dart`：24 PASS，证据 `example/tool/coverage_evidence/cp1-close-skin-tests.log`。

真机三轮 `cp1-close-skin-1825`：原 12 条快照 **12/12 PASS**。证据 `example/tool/coverage_evidence/matrix-cp1-close-skin-1825-skin/cp0-result.json`、`matrix-cp1-close-skin-1825-1-skin/cp0-result.json`、`matrix-cp1-close-skin-1825-2-skin/cp0-result.json`，每份 verdicts[6,8,56,61]。三轮完整 skin 各 68 PASS / 0 FAIL / 6 BLOCKED（人工布局/PiP/全屏视觉项），harness=[]；不把这些人工项当作 PASS。快照修正不证明 B03 专属底栏刺激已执行，底栏覆盖仍单独列项。构建拉回 SHA256=`9a9e047da9bcec323ad51ca88cd0b7097f5ec8fb54e86fc4caa70a52fe12e78c`。原 12 条 FAIL 保留在旧证据。
