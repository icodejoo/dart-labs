import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/stt/cue.dart';
import 'package:videoman/src/core/stt/subtitle_dir_provider.dart';
import 'package:videoman/src/core/stt/subtitle_store.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('videoman_stt_subtitle_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('load returns null when nothing is cached for this source', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    expect(await store.load('https://host/a.mp4'), isNull);
  });

  test('save then load round-trips the cue list', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    final cues = [
      const VmSttCue(text: '大家好', start: Duration.zero, end: Duration(seconds: 2)),
      const VmSttCue(text: '再见', start: Duration(seconds: 2), end: Duration(seconds: 4)),
    ];

    await store.save('https://host/a.mp4', cues);
    expect(await store.load('https://host/a.mp4'), cues);
  });

  test('different sources are cached under different keys', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    final a = [const VmSttCue(text: 'a', start: Duration.zero, end: Duration(seconds: 1))];
    final b = [const VmSttCue(text: 'b', start: Duration.zero, end: Duration(seconds: 1))];

    await store.save('https://host/a.mp4', a);
    await store.save('https://host/b.mp4', b);

    expect(await store.load('https://host/a.mp4'), a);
    expect(await store.load('https://host/b.mp4'), b);
  });

  test('save overwrites a previous entry for the same source', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.save('https://host/a.mp4', [
      const VmSttCue(text: 'old', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    await store.save('https://host/a.mp4', [
      const VmSttCue(text: 'new', start: Duration.zero, end: Duration(seconds: 1)),
    ]);

    final loaded = await store.load('https://host/a.mp4');
    expect(loaded, hasLength(1));
    expect(loaded!.first.text, 'new');
  });

  test('remove deletes the cached entry', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.save('https://host/a.mp4', [
      const VmSttCue(text: 'x', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    await store.remove('https://host/a.mp4');

    expect(await store.load('https://host/a.mp4'), isNull);
  });

  test('remove on a never-cached source is a silent no-op', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.remove('https://host/never.mp4');
  });

  test('load degrades to null on a cache file that fails to decode as text', () async {
    final store = VmFileSttSubtitleStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.save('https://host/a.mp4', [
      const VmSttCue(text: 'x', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    // Corrupt the underlying file with invalid UTF-8 so `readAsString()`
    // itself throws — `parseSrt` is tolerant of malformed *content* (it just
    // skips bad blocks), so only an actual decode failure exercises the
    // catch path.
    //
    // 用非法 UTF-8 破坏底层文件，使 `readAsString()` 本身抛异常——`parseSrt`
    // 对畸形*内容*是容忍的（只是跳过坏块），只有真正的解码失败才会触发
    // catch 分支。
    final file = Directory(tempDir.path).listSync().whereType<File>().first;
    file.writeAsBytesSync([0xFF, 0xFE, 0xFD]);

    expect(await store.load('https://host/a.mp4'), isNull);
  });
}
