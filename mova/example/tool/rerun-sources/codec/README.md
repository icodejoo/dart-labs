# 编解码对照样本

VP8 软解 dll / so 验证用，640x360、30fps、约 40 秒，带音频。

- `vp8.webm`：libvpx 编码
- `h264.mp4`：libx264 编码（对照，走硬解）

生成方式（ffmpeg，lavfi 合成源，无版权问题）：

    ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 40 -c:v libvpx -b:v 1M -c:a libvorbis vp8.webm
    ffmpeg -f lavfi -i testsrc2=size=640x360:rate=30 -f lavfi -i sine=frequency=440 -t 40 -c:v libx264 -c:a aac h264.mp4

用法见 `example/lib/main_vp8_dll_verify.dart`（Windows）与 `main_vp8_android_verify.dart`（Android）。

## 零拷贝（hwdec）兼容矩阵样本（2026-10-29 追加）

1280x720、30fps、20 秒、带音频、faststart（moov 在前，验证过 box 顺序为 ftyp/moov/free/mdat）。`h264.mp4`/`vp8.webm` 未改动。

    V="-f lavfi -i testsrc2=size=1280x720:rate=30 -f lavfi -i sine=frequency=440"
    ffmpeg -i h264.mp4 -c copy -movflags +faststart h264_fs.mp4
    ffmpeg $V -t 20 -c:v libx264 -preset veryfast -pix_fmt yuv420p -profile:v high -c:a aac -movflags +faststart h264_720.mp4
    ffmpeg $V -t 20 -c:v libx265 -preset veryfast -pix_fmt yuv420p -tag:v hvc1 -c:a aac -movflags +faststart hevc8.mp4
    ffmpeg $V -t 20 -c:v libx265 -preset veryfast -pix_fmt yuv420p10le -profile:v main10 -tag:v hvc1 -c:a aac -movflags +faststart hevc10.mp4
    ffmpeg $V -t 20 -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 2M -pix_fmt yuv420p -c:a libopus vp9.webm

服务：`python example/tool/verify_sources/range_server.py`（18090，支持 Range），`adb reverse tcp:18090 tcp:18090`。
验证页 `example/lib/main_hwdec_matrix_verify.dart`，驱动 `example/tool/zero_copy_run.py`，汇总 `example/tool/zero_copy_report.py`。
