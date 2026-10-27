# Android 覆盖矩阵一键入口

在仓库根目录使用 Python 3.14，无第三方 Python 依赖：

```powershell
python example/tool/run_matrix.py --list
python example/tool/run_matrix.py --check
python example/tool/run_matrix.py --dry-run --fast
python -B -m unittest discover -s example/tool -p test_run_matrix.py -v
# 以下会实际占用设备、构建目录及本地服务；先结束其他会话的复测
python example/tool/run_matrix.py --run-id regression-01
python example/tool/run_matrix.py --fast --fail-fast
python example/tool/run_matrix.py --only native-inputs,final-hls
python example/tool/run_matrix.py --from he-recovery --run-id resume-02
python example/tool/run_matrix.py --baseline example/tool/coverage_evidence/rerun-final-ledger.json
```

`--list` / `--check` / `--dry-run` 全部离线，不启动进程、不连接设备、不写证据或 build。`--check` 检查 135 编号、覆盖、依赖顺序、引用脚本语法、argv 格式及显式 argparse 选项；不能证明运行环境已具备。`--only`、`--from` 自动补 `api-launch` 启动依赖；续跑使用新 run-id、新构建和新证据，不继承上次 PASS。`--fast` 是启动/API/最终 HLS 子集，仍包含完整 API 批次，可能耗时较长。未选编号仍输出 BLOCKED。

清单共 26 批，顺序来自 `rerun_plan.py` 与 `rerun_post_plan.py`：API → HLS/QoE → HE 首帧/恢复 → keepAlive → 既有验证页 → 组件/手势/PiP → 最终 TLS/HLS/ABR → 边界/直播/原生读回 → V6 → 安全视觉/转场/小窗/预览触摸。每批覆盖编号、超时、依赖、亮屏要求及 fast 标记在 `matrix_manifest.json`。默认序列号 `7NQBB23606003715`，可设置 `$env:MOVA_MATRIX_SERIAL`（其次 `ANDROID_SERIAL`）。SDK 设置 `ANDROID_SDK_ROOT` 或 `ANDROID_HOME`；OpenSSL 可用 `MOVA_MATRIX_OPENSSL` 覆盖，否则搜索 PATH。需要 adb、Gradle/Flutter、ffmpeg、Android build-tools 和现有 debug.keystore；LFS 指针补包需要设备上已安装的独立 coverage APK，哈希不匹配即停。源素材沿用 `coverage_sources/stall.mp4`，源工作目录、媒体夹具与 TLS 临时证书按运行隔离，避免复用过期证书。

实际运行先检查空闲端口、宿主 ≥5GiB、设备 `/data` ≥1GiB、在线且亮屏解锁，再保存 USB 常亮与媒体音量；不尝试解锁。复用 `coverage_build.py` 与严格校验 LFS 的 `coverage_repack.py`，zipalign/签名/安装后拉回 APK 比对 sha256，并确认 lastUpdateTime 更新。本地源复用 `verify_sources/start_sources.py`、`coverage_media.py`、`coverage_tls.py`，自动 reverse；服务只清理本次启动的进程树。结束恢复设置、force-stop 独立包、清理本轮映射。设备锁屏立即停，手动解锁后用新 run-id 续跑；端口冲突不自动杀其他会话。

证据：`coverage_evidence/matrix-<run-id>/matrix-<run-id>-*`。`matrix_compat.py` 在子进程内隔离旧脚本证据和 `coverage_record` 文档输出，所有历史脚本调用的 adb 均记录 argv/退出码/耗时到 `*.commands.driver.log`；主入口记录 `*driver.log`。失败保存 logcat、截图、window/audio、最近 50 条事件；验证器异常单列 HARNESS。总体输出为 `doc/plans/<日期>-matrix-run-<run-id>.md` 和 `.json`，含全编号台账、基线差异及复现批次。

**判定限制**：`rerun_finalize.py` 大多是人工复核后的硬编码，不可直接重放。本入口沿用 `coverage_record.update` 的本轮完整编号结论，并直接复用终审引用的 A4/A22 两实现完整 CHECK；目前其他编号缺完整自动判据时输出 BLOCKED，原有子项记录仍保留。不会用 exit=0、旧 PASS、旧事件快照比较来替代新矩阵口径。129 个编号有执行覆盖，6 个 manual：A31/C7 缺 STT 模型链、C2 缺历史时移服务、F15 缺 WHEP、N18 缺守卫专包、N22 缺 debug 断言专包。实际完整跑完仍会有大量 BLOCKED，需人工复核或补充完整判据；这不是 135 项全自动验收器。v2 S/P/G 扩展及设备端验证页完整 L 日志未纳入此入口。任一 FAIL/BLOCKED/HARNESS 返回 1，清单错误返回 2。

异常终止无法执行 finally 时，按本轮 `*restore.json` 手动恢复设置并检查 `*driver.log` 中自有服务 PID；不要删除基线或杀其他会话进程。正常超时会终止该批次进程树；已有证据保留，使用新 run-id 重跑。
