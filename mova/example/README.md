# mova_example

Demonstrates how to use the mova plugin.

## 入口一览 / Entrypoints

每个入口都是独立的 `main()`，用 `-t` 选择；专项 demo 刻意不塞进 `main.dart`。

Each entrypoint is a standalone `main()`, selected with `-t`; focused demos are
deliberately kept out of `main.dart`.

| 入口 / Entrypoint | 用途 / Purpose |
|---|---|
| `lib/main.dart` | 综合 demo（点播/直播/时移/feed/广告）/ the general demo |
| `lib/main_seamless_test.dart` | 无缝广告→正片切换的自动化验收 / seamless ad→content swap acceptance |
| `lib/audio_only_demo.dart` | **仅音频模式手工/真机 demo**：模式、素材、封面面三个开关 + 实时事件日志 / **audio-only manual demo** |
| `lib/perf_probe_audio_only.dart` | **仅音频 vs 视频的 RSS 内存对比探针** / **audio-vs-video RSS probe** |
| `lib/spike_*.dart` | 一次性技术 spike，非 demo / one-off spikes, not demos |

仅音频 demo / audio-only demo:

```bash
flutter run -t lib/audio_only_demo.dart -d windows
```

内存对比探针（每进程一种模式，跑两次对比）/ RSS probe (one mode per process, run both):

```bash
flutter run -d windows --release -t lib/perf_probe_audio_only.dart --dart-define=MOVA_PERF_MODE=video
flutter run -d windows --release -t lib/perf_probe_audio_only.dart --dart-define=MOVA_PERF_MODE=audio
```

它打印 `MOVA_PERF|<模式>|<阶段>|<RSS MiB>`，三阶段为 `baseline`/`playing`/`disposed`。
实测结论见 [../doc/notes/2026-09-16-audio-only-feasibility.md](../doc/notes/2026-09-16-audio-only-feasibility.md)
的「Windows 桌面端实测」一节。

> Windows 路径超过 260 字符会让 media_kit 的插件构建失败（MSB3491）。若仓库路径较深，
> 先 `subst X: <仓库根>` 再从 `X:\mova\example` 跑。
>
> A repo path deep enough to exceed Windows' 260-char limit breaks the media_kit
> plugin build (MSB3491); `subst X: <repo root>` and run from `X:\mova\example`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
