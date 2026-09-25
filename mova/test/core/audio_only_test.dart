import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/fake_kernel.dart';

/// Reads a source file under `lib/` relative to the package root.
///
/// 读取 `lib/` 下相对包根的某个源文件。
List<String> _sourceLines(String relative) => File(relative).readAsLinesSync();

void main() {
  group('audio-only kernel contract / 仅音频内核契约', () {
    test('an audio-only kernel reports no render handle', () {
      expect(FakeKernel.audioOnly().renderHandle, isNull);
    });

    test('an audio-only kernel captures no screenshot', () async {
      expect(await FakeKernel.audioOnly().screenshot(), isNull);
    });

    test('every non-video verb still works on an audio-only kernel', () async {
      final k = FakeKernel.audioOnly();
      await k.open('https://host/a.m4a', play: false);
      await k.play();
      await k.pause();
      await k.seek(const Duration(seconds: 12));
      await k.setVolume(0.5);
      await k.setRate(1.5);
      expect(
        k.calls,
        ['open', 'play', 'pause', 'seek', 'setVolume', 'setRate'],
        reason: 'turning the video pipeline off must not turn playback off / '
            '关掉视频管线不得顺手关掉播放能力',
      );
      expect(k.lastUri, 'https://host/a.m4a');
      expect(k.lastPlay, isFalse);
      expect(k.lastSeek, const Duration(seconds: 12));
      await k.dispose();
    });
  });

  group('mpv_kernel.dart structural guards / 源级结构守卫', () {
    test('VideoController is constructed exactly once, inside if (!audioOnly)', () {
      final lines = _sourceLines('lib/src/core/kernel/mpv_kernel.dart');
      final hits = <int>[];
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('VideoController(')) hits.add(i);
      }
      expect(
        hits.length,
        1,
        reason: 'this single line is what opens the entire video-side cost '
            '(decoded frame buffers, GPU texture, Flutter Texture registration); '
            'see doc/notes/2026-09-16-audio-only-feasibility.md §2.1 / '
            '这一行就是打开全部视频侧开销（解码帧缓冲、GPU 纹理、Flutter 纹理注册）'
            '的那一句，见可行性笔记 §2.1',
      );
      var prev = hits.single - 1;
      while (prev >= 0 && lines[prev].trim().isEmpty) {
        prev--;
      }
      expect(
        lines[prev],
        matches(RegExp(r'if\s*\(!audioOnly\)')),
        reason: 'VideoController must stay guarded by if (!audioOnly); dropping '
            'that guard silently restores the full video pipeline in audio-only '
            'mode / VideoController 必须始终被 if (!audioOnly) 包住，删掉这层守卫'
            '会让仅音频模式悄悄退回完整视频管线',
      );
    });

    test('screenshot short-circuits and renderHandle is nullable', () {
      final src = File('lib/src/core/kernel/mpv_kernel.dart').readAsStringSync();
      expect(
        src,
        contains('audioOnly ?'),
        reason: 'screenshot() must short-circuit in audio-only mode so the '
            'scrub-preview fallback degrades gracefully instead of surfacing an '
            'mpv error / screenshot() 必须在仅音频模式下短路，让拖动预览兜底平滑'
            '降级而不是把 mpv 错误抛给宿主',
      );
      expect(
        src,
        contains('Object? get renderHandle'),
        reason: 'MovaMpvKernel must expose the widened nullable handle contract / '
            'MovaMpvKernel 必须暴露放宽后的可空句柄契约',
      );
    });
  });
}
