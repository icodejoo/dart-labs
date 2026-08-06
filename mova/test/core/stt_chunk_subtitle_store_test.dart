import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/stt/chunk_subtitle_store.dart';
import 'package:mova/src/core/stt/cue.dart';
import 'package:mova/src/core/stt/subtitle_dir_provider.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('mova_stt_chunk_subtitle_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('loadChunk returns null when that chunk has never been cached', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    expect(await store.loadChunk('https://host/a.mp4', 0), isNull);
  });

  test('saveChunk then loadChunk round-trips the cue list for that chunk', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    final cues = [
      const MovaSttCue(text: '大家好', start: Duration.zero, end: Duration(seconds: 2)),
    ];
    await store.saveChunk('https://host/a.mp4', 2, cues);
    expect(await store.loadChunk('https://host/a.mp4', 2), cues);
  });

  test('different chunk indices of the same source are cached independently', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    final chunk0 = [const MovaSttCue(text: 'a', start: Duration.zero, end: Duration(seconds: 1))];
    final chunk1 = [const MovaSttCue(text: 'b', start: Duration.zero, end: Duration(seconds: 1))];

    await store.saveChunk('https://host/a.mp4', 0, chunk0);
    await store.saveChunk('https://host/a.mp4', 1, chunk1);

    expect(await store.loadChunk('https://host/a.mp4', 0), chunk0);
    expect(await store.loadChunk('https://host/a.mp4', 1), chunk1);
  });

  test('different sources never collide even with the same chunk index', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    final a = [const MovaSttCue(text: 'a', start: Duration.zero, end: Duration(seconds: 1))];
    final b = [const MovaSttCue(text: 'b', start: Duration.zero, end: Duration(seconds: 1))];

    await store.saveChunk('https://host/a.mp4', 0, a);
    await store.saveChunk('https://host/b.mp4', 0, b);

    expect(await store.loadChunk('https://host/a.mp4', 0), a);
    expect(await store.loadChunk('https://host/b.mp4', 0), b);
  });

  test('removeAllChunks deletes every chunk of a source but leaves others intact', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.saveChunk('https://host/a.mp4', 0, [
      const MovaSttCue(text: 'x', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    await store.saveChunk('https://host/a.mp4', 1, [
      const MovaSttCue(text: 'y', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    await store.saveChunk('https://host/b.mp4', 0, [
      const MovaSttCue(text: 'z', start: Duration.zero, end: Duration(seconds: 1)),
    ]);

    await store.removeAllChunks('https://host/a.mp4');

    expect(await store.loadChunk('https://host/a.mp4', 0), isNull);
    expect(await store.loadChunk('https://host/a.mp4', 1), isNull);
    expect(await store.loadChunk('https://host/b.mp4', 0), isNotNull);
  });

  test('removeAllChunks on a never-cached source is a silent no-op', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.removeAllChunks('https://host/never.mp4');
  });

  test('loadChunk degrades to null on a cache file that fails to decode as text', () async {
    final store = MovaFileSttChunkSubStore(dir: FixedSttSubtitleDirProvider(tempDir.path));
    await store.saveChunk('https://host/a.mp4', 0, [
      const MovaSttCue(text: 'x', start: Duration.zero, end: Duration(seconds: 1)),
    ]);
    final file = Directory(tempDir.path).listSync().whereType<File>().first;
    file.writeAsBytesSync([0xFF, 0xFE, 0xFD]);

    expect(await store.loadChunk('https://host/a.mp4', 0), isNull);
  });
}
