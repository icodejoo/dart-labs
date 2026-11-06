# example/tool 脚本索引

真机/桌面验证用的驱动、夹具与单测。**文件路径写死在 `matrix_manifest.json` 与各驱动里，不要随意搬目录**；
分类以本表为准。一键入口与用法见 [README-matrix.md](README-matrix.md)。
（2026-11-06 清理：删除了 rerun2–7 / cp3_r2–r7 / cp1 closeout 等一次性战役脚本与 `rerun-sources/` 数据，历史结论见 `doc/plans/`。）

## 1. 一键入口与矩阵规则

| 文件 | 作用 |
|---|---|
| `run_matrix.py` | Android 覆盖矩阵一键入口（构建→安装→起共享源→逐批次→汇总） |
| `matrix_manifest.json` / `matrix_rules.json` | 批次清单与判据规则 |
| `matrix_compat.py` / `matrix_evidence.py` | 历史驱动隔离运行、证据归约（只列观察，不下结论） |
| `rerun_*.py` | 被清单引用的 135 项矩阵批次驱动（plan/batch/extra/finalize/各类输入） |

## 2. 检查点驱动（CP0–CP3，单场景运行）

用法：`python tool/coverage_cpN.py <scene> --run-id <id> --runs 5 [--build]`。
`--build` 只装对应的 suite APK；`v9/pip/liveedge/events/rate/warmmute` 等标准 suite 场景请走 `run_matrix.py --only cp2-<scene>`。

| 检查点 | 驱动 | 辅助 |
|---|---|---|
| CP0 | `coverage_cp0.py` | `cp0_autotier.py` `cp0_device_guard.py` `cp0_android_extra.py` |
| CP1 | `coverage_cp1.py` | `cp1_sources.py` `cp1_capture.py` `cp1_keepalive.py` |
| CP2 | `coverage_cp2.py`（含 `qoepause`） | `cp2_alias.py` `cp2_volume.py` |
| CP3 | `coverage_cp3.py` | `cp3_alias.py` `cp3_checks.py` `cp3_compare.py` `cp3_f3.py` `cp3_r2_legacy.py` `cp3_runtime.py` |

## 3. 构建与设备

`coverage_build.py`（隔离 release 构建）· `coverage_device.py` / `coverage_suite_device.py`（驱动验证页并留证据）·
`coverage_repack.py`（LFS 指针回填）· `coverage_record.py`（批次台账）· `coverage_event_audit.py`

## 4. 覆盖批次（历史矩阵用，被 manifest 引用）

`coverage_api_batches.py` `coverage_final_batches.py` `coverage_followup_batches.py` `coverage_gap.py`
`coverage_hls_final.py` `coverage_interactive.py` `coverage_ui*.py` `coverage_visual_final.py`
`coverage_widgets_ui.py` `coverage_transition_final.py` `coverage_s00c.py` `coverage_s00d_offline.py`
`coverage_s00e*.py`

## 5. 夹具与本地源

| 文件 | 作用 |
|---|---|
| `verify_sources/` | 直播 FLV / HLS 滑窗 / Range / Referer 源（`start_sources.py` 一键起） |
| `coverage_media.py` `coverage_gap_media.py` | 预览/HLS/缺口测试素材生成与本地服务 |
| `coverage_tls.py` | 好/过期/错主机/自签 TLS 源 |
| `online_sources_probe.py` + `online_sources.json` | 在线测试源批量复测 |

## 6. 性能

`perf_judge.py`（统计，纯标准库）· `coverage_perf.py`（宿主侧性能运行）· `perf_baseline/`（按设备序列号的基线）

## 7. 桌面端策略与隐私闸门

`win_policy.py`（Windows 唯一启动入口与统一策略）· `win_job.py` · `win_focus_gate.py`（静态闸门，禁止抢焦点）·
`shot_guard.py`（截图前台守卫，所有设备脚本共用）

## 8. 离线单测

```powershell
cd example/tool
foreach ($t in Get-ChildItem test_*.py) { python -m unittest $t.BaseName }
```

`test_run_matrix.py` `test_cp3.py` `test_cp3_compare.py` `test_cp2_volume.py` `test_cp0_device_guard.py`
`test_perf_judge.py` `test_shot_guard.py` `test_win_*.py`（共 152 项，不需要设备）

## 9. 数据与 gradle 脚本

`testdata/`（S00d/S00e 离线检查）· `s00d_rules_inventory.json` `s00e_rules_inventory.json` ·
`coverage.init.gradle` `coverage_gap_variants.init.gradle`

## 10. 运行时产物（均 git 忽略，可随时删）

`coverage_evidence/` 真机证据 · `coverage_native/` 构建用 libmpv 拷贝 · `coverage_media/` `coverage_sources/` 素材 ·
`coverage_isolated_build.log` 构建日志。建议只留最近一轮证据里的 `*.json`/日志，APK 与素材拷贝用完即删。
