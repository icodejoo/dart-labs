# Windows 安静模式验证（2026-11-03）

执行中，真机结果随后逐块追加；尚不声称验收通过。

范围：仅本树 mova/example 与 mova/doc；未转派、未用 adb、未操作其他工作树。

驱动删除获取焦点、前台就绪与补跑；HTTP PID/HE 日志作为就绪条件。F3 每模式三个独立进程、每进程一次切换，dispose/V6/V10 各三个进程，共18轮。次数经 clamp_runs；独立线程每秒观测、逐行落盘，违规立即终止并 BLOCKED，连续两轮违规中止批次。monitor 只读。

runner 跳过安静模式下子窗口 SetFocus，在显示前固定640×360物理像素，避免DPI放大。

离线检查：run_matrix.py --check PASS（49 batches / 135 IDs / 6 manual，含焦点闸门）；test_win_policy.py 11/11 PASS；test_run_matrix.py 31/31 PASS。集成测试默认2项skip。

构建：libmpv_hydrate.py --check PASS。dot-source ~/.claude/msvc-env.ps1 后将 C:/Program Files/CMake/bin 放回PATH首位，显式 cmake 4.3.4重新配置并以 /m:1 构建Release INSTALL，退出0。MSVC自带4.3.1导致首次再生失败；生成的插件清单中有已不在依赖元数据里的sherpa残项，移除后配置成功。generated_plugin* 不进提交。安装前缀全程本树 example/build/windows/x64/runner/Release。

构建证据：example/tool/coverage_evidence/win-quiet-configure.log、win-quiet-build.log。

exe SHA256：`bf00b2687ff121517188f415887569cb90d9234d9353dced0d8671409771e343`。
