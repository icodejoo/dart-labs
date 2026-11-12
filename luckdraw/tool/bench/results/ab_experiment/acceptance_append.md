
## AB 真机双峰受控实验

| ID | 需求 / 不变量 | 来源 | 用例 | 类型 | 结果 |
| --- | --- | --- | --- | --- | --- |
| AB-01 | 条件A固定Picture三轮 | AB；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数6.920ms，高档1/3；见AB_REPORT |
| AB-02 | 条件B固定Picture三轮 | AB；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数6.712ms，高档1/3；见AB_REPORT |
| AB-03 | 条件C固定Picture三轮 | AB；TEST_STRATEGY §5.3 R2-10、§7 | `tool/bench/integration_test/perf_bench_test.dart :: perf > selected device scenario` | 真机 | 已落地：3/3；Raster中位数13.899ms，高档2/3；见AB_REPORT |
| AB-04 | 原值、极差、事后显示/合成/温度证据 | AB；TEST_STRATEGY §7 | `cmd: python tool/bench/results/ab_experiment/analyze_ab.py` | 工具/真机 | 已落地：9次有效；看护仍运行，A/C无可控差异；无法隔离看护效应 |
| AB-05 | 结束恢复手动最低及USB常亮 | AB | `cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness_mode`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get system screen_brightness`<br>`cmd: adb -s 10AE9K17UE0011S shell settings get global stay_on_while_plugged_in` | 真机 | 已落地：实测0、1、2；见restored_settings.json |
