# CP3 剩余项离线定性

起点 `76805160`，仅在 `E:\workspaces\wt-mova-cp2fix` 自行执行。原始证据只读，未使用真机、adb、Gradle；不将离线修正当作真机 PASS。下列 run-id 的证据目录均为 `example/tool/coverage_evidence/matrix-<run-id>/`，records 下标从零开始；累计日志仅取最后一个 BEGIN 后的本命令记录。

## 1. 字幕：打包夹具缺陷，已离线修正，真机 BLOCKED 保留

- 证据：`cp3-r2-subtitles-r2-20261105-085403` 的 `cp3-r2-subtitles.json` records[9] 为 SRT 资产加载 SCRIPT_ERROR；前一尝试 `cp3-r2-subtitles-r2-20261105-085320` 同因。
- `coverage_new.dart:subtitles` 已把包内视频/字幕写入临时目录，再经原生 `sub-add` 或 MP4 内嵌 mov_text 播放；不走旧 HTTP 404 路径。SRT 文件已受 git 管理，但 pubspec 只声明 ASS/VTT 和两段视频，缺 SRT。补齐声明并移除过时的临时资产注释，无产品修改，无需引入 HTTP 服务。
- 下一次必须新 APK：逐格式取得 `F11.srt/ass/vtt/movtext` CHECK 和 `SUBTITLE_SHOT` 的 sub-text、track-list、position；四项本轮均未验收，包声明正确不能替代原生解码与人工画面复核。

## 2. headers 池预热：夹具判据错误，未证产品缺陷

- `cp3-headers-r2-20261105-085001` records[38,73,108,144,180]：pool positive/negative 都为 true；第 0 轮无 negative 回执，第 2 轮两侧回执均尚未出现。`085001` 与 `084854` 两试均 0/5。原判据在 `pool.bind` 返回即读取 ready、立刻 dispose；异步请求可迟到，甚至在真正打开前被销毁。
- `engine_pool.dart:_openBinding` 明确将 ready 定义为 open accepted；拒绝结果撤销绑定，成功接受并不代表加载/解码成功。这与公开文档一致，不能改产品 ready 含义来迎合探针。
- `MovaHeaderedHttpFetch` 用于 Dart 辅助请求（清晰度/VTT/预取）；池走 engine → mpv 原生媒体加载头。原回执中 authorized Referer/200、denied 无头/403 均出现，不能据 ready 双 true 认定头丢失。
- 修正：单引擎池挂载真实 surface，开启 preciseFirstFrame，等待 rendered+非零 duration/尺寸或错误；保留 accepted、decoded、状态和原生 path/time-pos/pause。再释放池、汇总两侧 HTTP 回执。负对照超时/错误不冒充成功，缺服务端回执仍 FAIL。
- 需要新 APK、原 5 轮正负对照复验。解码预热尚未获得有效设备验收。
