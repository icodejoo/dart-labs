# Windows 安静模式验证（2026-11-03）

功能基线完成：18/18 PASS、零前台违规。严格 z 序要求未满足，整体验收未通过。

范围：仅本树 mova/example 与 mova/doc；未转派、未用 adb、未操作其他工作树。

驱动删除获取焦点、前台就绪与补跑；HTTP PID/HE 日志作为就绪条件。F3 每模式三个独立进程、每进程一次切换，dispose/V6/V10 各三个进程，共18轮。次数经 clamp_runs；独立线程每秒观测、逐行落盘，违规立即终止并 BLOCKED，连续两轮违规中止批次。monitor 只读。

runner 跳过安静模式下子窗口 SetFocus，在显示前固定640×360物理像素，避免DPI放大。

离线检查：run_matrix.py --check PASS（49 batches / 135 IDs / 6 manual，含焦点闸门）；test_win_policy.py 11/11 PASS；test_run_matrix.py 31/31 PASS。集成测试默认2项skip。

构建：libmpv_hydrate.py --check PASS。dot-source ~/.claude/msvc-env.ps1 后将 C:/Program Files/CMake/bin 放回PATH首位，显式 cmake 4.3.4重新配置并以 /m:1 构建Release INSTALL，退出0。MSVC自带4.3.1导致首次再生失败；生成的插件清单中有已不在依赖元数据里的sherpa残项，移除后配置成功。generated_plugin* 不进提交。安装前缀全程本树 example/build/windows/x64/runner/Release。

构建证据：example/tool/coverage_evidence/win-quiet-configure.log、win-quiet-build.log。

exe SHA256：`bf00b2687ff121517188f415887569cb90d9234d9353dced0d8671409771e343`。

## 首次真机集成测试（不重跑）

MOVA_WIN_IT=1 实际执行2项，unittest退出1，两项均在严格z序断言失败；保留原始失败，未改断言或过滤窗口。V10日志实际PASS。裸启动的必需焦点/尺寸/10秒内终止条件满足，但共用额外z序检查也报告FAIL。

- policy-v10：49次采样，0次前台违规，10.097秒，最后窗口：`{"rect": [4472, 1032, 5112, 1392], "width": 640, "height": 360, "virtualScreen": [0, 0, 5120, 1440], "rightGap": 8, "bottomGap": 48, "exStyle": "0x8000180", "zIndex": 22, "visibleCount": 25, "below": [{"hwnd": 66556, "pid": 12260, "windowClass": "Progman"}, {"hwnd": 789688, "pid": 38428, "windowClass": "SoPY_Status"}]}`。
- bare：45次采样，0次前台违规，9.204秒，最后窗口：`{"rect": [4472, 1032, 5112, 1392], "width": 640, "height": 360, "virtualScreen": [0, 0, 5120, 1440], "rightGap": 8, "bottomGap": 48, "exStyle": "0x8000180", "zIndex": 22, "visibleCount": 26, "below": [{"hwnd": 66556, "pid": 12260, "windowClass": "Progman"}, {"hwnd": 789688, "pid": 38428, "windowClass": "SoPY_Status"}, {"hwnd": 21368070, "pid": 38428, "windowClass": "SoPY_Comp"}]}`。

原始证据：example/tool/coverage_evidence/win-quiet-integration/ 与 win-quiet-integration-unittest.log。虚拟屏幕5120×1440；窗口矩形[4472,1032,5112,1392]，右间距8、底间距48；扩展样式0x08000180。HWND_BOTTOM没有把窗口放在Progman和输入法窗口之下；因此“低于所有可见顶层窗口”尚未满足。未激活或移动其他用户窗口去改变结果。

## (c) 新安静模式 Windows 基线

驱动仅执行一次，18个不同采样点各执行一次，没有补跑。F3每模式3个独立进程、每进程1次切换；与旧每模式1进程10次切换的采样结构不同，不能从3次推断同等压力覆盖。

|项目|新基线|旧：抢焦点模式，用户被打断，仅作对照|差异|
|---|---|---|---|
|F3 normal|3/3 PASS|10/10 PASS|结论一致，目标/落点偏差均0ms|
|F3 paused|3/3 PASS|10/10 PASS|结论一致，目标/落点偏差均0ms|
|F3 cutover|3/3 PASS|10/10 PASS|结论一致，目标/落点偏差均0ms|
|A23/F13 dispose|3/3 PASS，12次调用返回|20/20 PASS，80次调用返回|结论一致，采样减少|
|HE V6|3/3 PASS|5/5 PASS|结论一致；新超时偏移21/7/9ms，恢复位置偏差均0ms|
|HE V10|3/3 PASS|20/20 PASS|结论一致；路由覆盖、TickerMode均有暂停/恢复|

总前台观测274次，违规0；崩溃0，watchdog 0，BLOCKED 0。驱动退出0。独立集成测试另有49+45次观测，全部测试合计368次、违规0。

|轮次|结果|每秒前台采样数|违规|
|---|---|---|---|
|F3-normal-0|PASS / PASS|14|0|
|F3-normal-1|PASS / PASS|13|0|
|F3-normal-2|PASS / PASS|15|0|
|F3-paused-0|PASS / PASS|14|0|
|F3-paused-1|PASS / PASS|13|0|
|F3-paused-2|PASS / PASS|15|0|
|F3-cutover-0|PASS / PASS|17|0|
|F3-cutover-1|PASS / PASS|17|0|
|F3-cutover-2|PASS / PASS|18|0|
|dispose-0|PASS / PASS|14|0|
|dispose-1|PASS / PASS|11|0|
|dispose-2|PASS / PASS|10|0|
|V6-0|PASS / PASS|32|0|
|V6-1|PASS / PASS|19|0|
|V6-2|PASS / PASS|19|0|
|V10-0|PASS / PASS|10|0|
|V10-1|PASS / PASS|11|0|
|V10-2|PASS / PASS|12|0|


证据：example/tool/coverage_evidence/cp0-windows-quiet/（每轮result、foreground.jsonl、progress；F3/dispose另有HTTP原生事件日志和PrintWindow截图；HE自然退出留完整HE日志）；results.json与build.json记录轮次和二进制哈希。旧目录cp0-windows-formal不变。

## 差异机制与需要前台的项目

本次测量范围没有出现“因为不在系统前台而失败”的功能项，没有需要前台才能成立的已测项目。不得将这个结论推广到未测项目。

V10在系统前台采样全部为false时，HE日志仍记录LIFECYCLE resumed。Win32前台所有权与Flutter生命周期状态不能当作同一条件。lib/src/ui/guard/auto_pause.dart的_onLifecycle对inactive只记播放意图，不暂停；hidden/paused/detached才设置background原因，resumed清除。路由遮盖、TickerMode还有独立信号；此次均确实产生pause/play，未修改lib来强行通过。

明确需要前台/交互的未覆盖清单：真实键盘焦点/快捷键/用户点击；真正的系统前后台切换与resumed恢复路径（例如HE V9操作员后台流程）；MOVA_WIN_INTERACTIVE=1普通窗口对照。它们不属于此次18轮，未运行、未计PASS；不通过获取系统焦点补齐。PiP等其他操作员场景也未验证。

## 限制与未完成项

- 严格“低于所有可见顶层窗口”的z序断言失败：policy最后索引22/25，下方Progman、SoPY_Status；bare最后索引22/26，下方再含SoPY_Comp。HWND_BOTTOM的实测结果有桌面/输入法窗口在下方，未通过过滤它们来伪造成功。没有修改win_policy或闸门，也没有操作其他应用窗口。此项尚未解决，因此任务不能标为全部验收通过。
- 集成测试实际2项FAIL都发生在共用z序断言；(b)规定的尺寸、零前台违规和10秒终止条件有实测支持，但当前测试对它额外检查同样严格z序，故保留其FAIL。未再次裸启动。
- 200ms为目标采样周期，实测policy相邻间隔202.5–235.4ms，bare201.6–208.4ms；操作系统调度/落盘有抖动。批次1秒观测也有同样限制；零采样违规不证明采样间隙绝无短暂焦点变更。
- 裸启动循环观测9.204秒，随后立即terminate；记录的elapsedSeconds是terminate前的观测时间。未设置交互模式，未运行隐藏桌面、flutter run或adb。
- 生成的example/windows/flutter/generated_plugins.cmake只在本地修复过期sherpa条目，按要求不进提交；其他工作树没有写入或git操作。
- 本次仅重建Windows Release（复用main_win_retest.dart的已有Dart release产物，CMake的Flutter assemble也完成）；构建/安装均落本树example下，不更改核心库或根test目录。

最后离线复核：run_matrix.py --check PASS；test_win_policy.py 11/11；test_run_matrix.py 31/31。构建退出0。真机集成失败如上，未抹去失败记录。
