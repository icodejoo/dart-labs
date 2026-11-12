
## AB2 Skia 与 Impeller GLES 对照

| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| AB2-01 | S后端默认auto三轮 | AB2；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数4.727ms；高档1/3；见AB_REPORT的Skia对照 |
| AB2-02 | I后端默认auto三轮 | AB2；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数5.138ms；高档0/3；见AB_REPORT的Skia对照 |
| AB2-03 | APK、后端响应、原值/中位数/极差、即时SF和温度证据 | AB2；TEST_STRATEGY §7 | `cmd: python tool/bench/results/ab_experiment/skia_compare/analyze_compare.py` | 工具/真机 | 已落地：6/6有效；与后端无关；保留120秒轻量看护限制 |
| AB2-04 | 结束手动最低与USB常亮只读确认 | AB2 | `cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness_mode`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get global stay_on_while_plugged_in` | 真机 | 已落地：实测0、1、2；未写入设置；见skia_compare/final_settings_confirmation.json |
