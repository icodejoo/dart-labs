# 编解码对照样本

VP8 软解 dll / so 验证用，640x360、30fps、约 40 秒，带音频。

- `vp8.webm`：libvpx 编码
- `h264.mp4`：libx264 编码（对照，走硬解）

生成方式（ffmpeg，lavfi 合成源，无版权问题）：

    ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 40 -c:v libvpx -b:v 1M -c:a libvorbis vp8.webm
    ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 40 -c:v libx264 -c:a aac h264.mp4

用法见 `example/lib/main_vp8_dll_verify.dart`（Windows）与 `main_vp8_android_verify.dart`（Android）。
