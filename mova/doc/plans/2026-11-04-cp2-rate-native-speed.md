# CP2 第四轮 rate 原生倍速读回补丁

原 V13 只读取 proxy.state.rate，不能证明原生 mpv speed。本补丁保留原代理断言，额外从当前 renderHandle 的 VideoController.player.platform（NativePlayer）读取 path/speed；同时记录 renderEpoch 及读回前后句柄/epoch 是否稳定。广告期间每100ms触发一次非重叠采样，按真实 ad.mp4 路径过滤；返回正片后另读 vod.mp4，要求广告稳定段1x、正片恢复到2x/1.5x。采样缺失判 BLOCKED，不据代理值推断原生通过。原始 NATIVE_SPEED / ERROR 行落在 rate 日志，RESULT 带完整性与原生判定。

验证：flutter analyze --no-pub lib/main_review_fixes_verify2.dart：No issues found。设备验证随新 release APK 第四轮执行，本提交本身不宣称真机通过。仅修改 example/doc，未改 lib/test。
