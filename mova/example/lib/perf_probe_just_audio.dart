import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// In-process RSS probe for `just_audio`, using **exactly** the methodology of
/// `perf_probe_audio_only.dart` (release build, `ProcessInfo.currentRss`,
/// three phases: baseline / playing / disposed) so the two sets of numbers can
/// sit in one table.
///
/// ## Read this before trusting the comparison / 看数字前先读这一段
///
/// `just_audio` has **no first-party Windows implementation**. Its official
/// platforms are Android, iOS, macOS and web; on Windows it requires a
/// federated backend, and the choice of backend decides what is actually being
/// measured:
///
/// - `just_audio_media_kit` wraps **the same media_kit/libmpv that mova uses**.
///   Measuring it would compare libmpv against libmpv — circular, and it would
///   tell you nothing about whether a "lighter" audio plugin exists.
/// - `just_audio_windows` (used here) drives **WinRT `MediaPlayer`**, i.e. the
///   operating system's own media stack. That is architecturally analogous to
///   what `just_audio` does on Android/iOS (thin wrapper over ExoPlayer /
///   `AVPlayer`), so it is the informative choice — but see the caveat below.
///
/// **The caveat that decides how to read the number:** Windows' media stack
/// does a large share of its work *outside this process* (Media Foundation /
/// `Windows.Media.Playback` service hosts). `ProcessInfo.currentRss` cannot see
/// that. So a low number here means "cheap **for my app's process**", not
/// "cheap for the machine". mova/libmpv, by contrast, is entirely in-process,
/// so its RSS is the whole cost. The two numbers answer different questions and
/// must not be subtracted as if they were the same quantity.
///
/// `just_audio` 在 Windows 上**没有第一方实现**（官方平台是 Android/iOS/macOS/web），
/// 桌面必须外挂联邦后端，而选哪个后端直接决定了到底在测什么：
/// `just_audio_media_kit` 包的是**和 mova 同一个 media_kit/libmpv**，测它等于拿
/// libmpv 比 libmpv，是循环论证；这里用的 `just_audio_windows` 走 WinRT
/// `MediaPlayer`，即操作系统自己的媒体栈，架构上对应 `just_audio` 在 Android/iOS
/// 上薄封装 ExoPlayer/`AVPlayer` 的做法，因此才有参考价值。
///
/// **但读数时必须记住**：Windows 媒体栈有很大一部分工作发生在**本进程之外**
/// （Media Foundation / `Windows.Media.Playback` 的服务宿主进程），
/// `ProcessInfo.currentRss` 看不到那部分。所以这里的低数字意味着"对**我的 App
/// 进程**便宜"，不等于"对整机便宜"；而 mova/libmpv 完全在进程内，它的 RSS 就是
/// 全部成本。两个数字回答的是不同问题，不能当同一个量直接相减。
///
/// Run (same shape as the mova probe):
/// ```
/// $env:MOVA_PERF_URI = "<path to source_audio.m4a>"
/// flutter run -d windows --release -t lib/perf_probe_just_audio.dart
/// ```

/// How long to let playback stabilise before sampling.
///
/// 采样前让播放稳定多久。
const _settle = Duration(seconds: 6);

/// How long to wait after `dispose()` before the release sample.
///
/// `dispose()` 后等多久再采释放后的样本。
const _afterDispose = Duration(seconds: 4);

/// The media to play. Point this at the audio track demuxed out of the very
/// same mp4 the mova probe used, so both players decode byte-identical audio.
///
/// 要播放的素材。指向从 mova 探针所用的同一个 mp4 里 demux 出来的音频轨，
/// 使两个播放器解的是逐字节相同的音频。
final _mediaUri = Platform.environment['MOVA_PERF_URI'] ??
    'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';

/// A remote audio URL, used as the last-resort attempt so a local-file
/// limitation in the Windows backend can be told apart from "cannot play at
/// all".
///
/// 一条远程音频 URL，作为最后一次尝试，用于把 Windows 后端的本地文件限制与
/// "根本放不了"区分开。
const _remoteAudio = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';

/// Current resident set size in MiB.
///
/// 当前常驻内存（MiB）。
double _rssMiB() => ProcessInfo.currentRss / 1024 / 1024;

/// Prints one labelled sample in the same grep-friendly shape the mova probe
/// uses, so both runs can be parsed by one expression.
///
/// 以与 mova 探针完全相同、便于 grep 的格式打印一条带标签的样本，使两边的输出
/// 能用同一个表达式解析。
void _sample(String label) {
  stdout.writeln('MOVA_PERF|just_audio|$label|${_rssMiB().toStringAsFixed(2)}');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ProbeApp());
}

/// The probe shell.
///
/// 探针外壳。
class _ProbeApp extends StatefulWidget {
  /// Creates the probe shell.
  ///
  /// 创建探针外壳。
  const _ProbeApp();

  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  /// The latest phase label, shown on screen.
  ///
  /// 最近的阶段标签，显示在屏幕上。
  String _phase = 'baseline';

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  /// Drives the three-phase measurement and exits the process when done.
  ///
  /// 驱动三阶段测量，完成后退出进程。
  Future<void> _run() async {
    // Phase 0: process baseline, before any player exists.
    // 阶段 0：进程基线，此时还没有任何播放器。
    await Future<void>.delayed(const Duration(seconds: 3));
    _sample('baseline');
    stdout.writeln('MOVA_PERF|just_audio|uri|$_mediaUri');
    stdout.writeln('MOVA_PERF|just_audio|backend|just_audio_windows (WinRT MediaPlayer)');

    final player = AudioPlayer();
    // Several source forms are tried in order because just_audio's Windows
    // backend is community-maintained and its local-file handling is listed as
    // partially untested. Whichever form actually reaches a playing state is
    // the one measured; if none does, that is itself the reported result.
    //
    // 依次尝试多种 source 形式：just_audio 的 Windows 后端是社区维护的，其本地
    // 文件处理在文档里标注为部分未经测试。哪种形式真正进入播放态就测哪种；
    // 如果一种都进不去，那这件事本身就是要如实报告的结论。
    final attempts = <String, Future<Duration?> Function()>{
      'setFilePath': () => player.setFilePath(_mediaUri),
      'AudioSource.file': () => player.setAudioSource(AudioSource.file(_mediaUri)),
      'setUrl(file-uri)': () => player.setUrl(Uri.file(_mediaUri).toString()),
      'setUrl(http-remote)': () => player.setUrl(_remoteAudio),
    };

    var playingForm = 'none';
    for (final entry in attempts.entries) {
      try {
        final duration = await entry.value().timeout(const Duration(seconds: 20));
        await player.play().timeout(const Duration(seconds: 5), onTimeout: () {});
        await Future<void>.delayed(const Duration(seconds: 3));
        stdout.writeln(
          'MOVA_PERF|just_audio|attempt|${entry.key}|duration=${duration?.inMilliseconds}'
          '|state=${player.processingState}|playing=${player.playing}'
          '|pos=${player.position.inMilliseconds}',
        );
        if (player.playing && player.position > Duration.zero) {
          playingForm = entry.key;
          break;
        }
      } catch (e) {
        stdout.writeln('MOVA_PERF|just_audio|attempt|${entry.key}|ERROR|$e');
      }
    }
    stdout.writeln('MOVA_PERF|just_audio|playingForm|$playingForm');

    if (playingForm != 'none') {
      setState(() => _phase = 'playing');
      await Future<void>.delayed(_settle);

      // Phase 1: steady-state playback.
      // 阶段 1：稳定播放中。
      _sample('playing');
      stdout.writeln('MOVA_PERF|just_audio|playing|${player.playing}');
      stdout.writeln('MOVA_PERF|just_audio|position|${player.position.inMilliseconds}');
    } else {
      // An honest failure is a result too: it means this comparison cannot be
      // made on this machine, which must be reported rather than papered over.
      //
      // 如实失败也是一种结果：说明这台机器上做不成这个对比，必须如实报告而不是
      // 糊弄过去。
      stdout.writeln('MOVA_PERF|just_audio|UNPLAYABLE|no source form reached a playing state');
    }

    await player.dispose();
    setState(() => _phase = 'disposed');
    await Future<void>.delayed(_afterDispose);

    // Phase 2: after release — the leak check.
    // 阶段 2：释放后——泄漏检查。
    _sample('disposed');
    stdout.writeln('MOVA_PERF|just_audio|done');
    await stdout.flush();
    exit(0);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: Center(child: Text('just_audio perf probe · $_phase')),
        ),
      );
}
