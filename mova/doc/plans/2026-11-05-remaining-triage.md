# CP3 剩余项离线定性

起点 `76805160`，仅在 `E:\workspaces\wt-mova-cp2fix` 自行执行。原始证据只读，未使用真机、adb、Gradle；不将离线修正当作真机 PASS。下列 run-id 的证据目录均为 `example/tool/coverage_evidence/matrix-<run-id>/`，records 下标从零开始；累计日志仅取最后一个 BEGIN 后的本命令记录。

## 1. 字幕：打包夹具缺陷，已离线修正，真机 BLOCKED 保留

- 证据：`cp3-r2-subtitles-r2-20261105-085403` 的 `cp3-r2-subtitles.json` records[9] 为 SRT 资产加载 SCRIPT_ERROR；前一尝试 `cp3-r2-subtitles-r2-20261105-085320` 同因。
- `coverage_new.dart:subtitles` 已把包内视频/字幕写入临时目录，再经原生 `sub-add` 或 MP4 内嵌 mov_text 播放；不走旧 HTTP 404 路径。SRT 文件已受 git 管理，但 pubspec 只声明 ASS/VTT 和两段视频，缺 SRT。补齐声明并移除过时的临时资产注释，无产品修改，无需引入 HTTP 服务。
- 下一次必须新 APK：逐格式取得 `F11.srt/ass/vtt/movtext` CHECK 和 `SUBTITLE_SHOT` 的 sub-text、track-list、position；四项本轮均未验收，包声明正确不能替代原生解码与人工画面复核。

后续类别、检查结果和提交见后续追加。
