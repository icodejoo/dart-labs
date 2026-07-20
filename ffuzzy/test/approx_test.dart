// Tests for FuzzyCorpus.approx() — approximate SUBSTRING search (not
// whole-string): a typo'd query should match a window inside a longer item,
// not require the item's entire length to align.
//
// FuzzyCorpus.approx() 的测试 —— 近似子串搜索（不是整串匹配）：带拼写错误
// 的查询应当匹配到较长条目内部的一个窗口，而不要求整个条目的长度都对齐。
//
//   flutter test test/approx_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ffuzzy/ffuzzy.dart';

String _libPath() {
  final root = Directory.current.path;
  if (Platform.isWindows) return '$root${Platform.pathSeparator}ffz.dll';
  if (Platform.isMacOS) return '$root/libffz.dylib';
  return '$root/build_x86_64/libffuzzy.so';
}

// Levenshtein distance, used to independently re-verify a reported window.
//
// Levenshtein（编辑）距离，用于独立地重新验证所报告的窗口。
int _editDistance(String a, String b) {
  final m = a.length, n = b.length;
  var prev = List<int>.generate(n + 1, (j) => j);
  for (var i = 1; i <= m; i++) {
    final cur = List<int>.filled(n + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= n; j++) {
      final sub = prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      cur[j] = [sub, del, ins].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[n];
}

void main() {
  late String lib;
  setUpAll(() { lib = _libPath(); });

  group('approx: substring semantics (verified: fuzzy finds none of these)', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings([
          'lib/src/widgets/scaffold.dart',
          'README.md',
          'CHANGELOG.md',
        ], libraryPath: lib, matchPaths: true));
    tearDown(() => c.dispose());

    test('substitution typo matches a window inside a much longer path', () {
      expect(c.fuzzy('scaffolx'), isEmpty); // confirms this isn't a subsequence win
      //
      // 确认这不是子序列匹配的命中结果
      final hits = c.approx('scaffolx');
      expect(hits.map((h) => h.raw), contains('lib/src/widgets/scaffold.dart'));
    });

    test('substitution typo at the START of a shorter item still resolves', () {
      expect(c.fuzzy('xeadme'), isEmpty);
      final hits = c.approx('xeadme');
      expect(hits.map((h) => h.raw), contains('README.md'));
    });

    test('query far from every item does not match', () {
      expect(c.approx('zzzzzzzzzz'), isEmpty);
    });
  });

  group('approx: highlight', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings(['lib/src/widgets/scaffold.dart'],
        libraryPath: lib, matchPaths: true));
    tearDown(() => c.dispose());

    test('highlight:false (default) leaves indices empty', () {
      final hits = c.approx('scaffolx');
      expect(hits.single.indices, isEmpty);
    });

    test('highlight:true populates a contiguous window achieving the reported distance', () {
      const text = 'lib/src/widgets/scaffold.dart';
      final hits = c.approx('scaffolx', highlight: true);
      final h = hits.single;

      expect(h.indices, isNotEmpty);
      final sorted = [...h.indices]..sort();
      expect(h.indices, equals(sorted), reason: 'window must already be ascending');
      for (var i = 1; i < sorted.length; i++) {
        expect(sorted[i], sorted[i - 1] + 1, reason: 'window must be contiguous, no gaps');
      }

      // Distance is encoded as -score (see ffz_corpus.c's edit-hit scoring).
      //
      // 距离被编码为 -score（参见 ffz_corpus.c 中编辑命中的评分逻辑）。
      final reportedDistance = -h.score;
      final window = text.substring(sorted.first, sorted.last + 1);
      expect(_editDistance('scaffolx', window), reportedDistance,
          reason: 'the reported window must actually achieve the reported distance');
    });
  });

  group('approx-derived strategies inherit substring semantics', () {
    late FuzzyCorpus<String> c;
    setUp(() => c = FuzzyCorpus.strings(['lib/src/widgets/scaffold.dart', 'README.md'],
        libraryPath: lib, matchPaths: true));
    tearDown(() => c.dispose());

    test('search(strategy: fallback) falls through to substring edit-distance', () {
      expect(c.search('scaffolx', strategy: SearchStrategy.fuzzy), isEmpty);
      final hits = c.search('scaffolx', strategy: SearchStrategy.fallback);
      expect(hits.map((h) => h.raw), contains('lib/src/widgets/scaffold.dart'));
    });

    test('dual() edit bucket uses substring semantics independently of the seq bucket', () {
      final d = c.dual('scaffolx');
      expect(d.fuzzy, isEmpty);
      expect(d.approx.map((h) => h.raw), contains('lib/src/widgets/scaffold.dart'));
    });

    test('dual() only populates indices when highlight is requested', () {
      final noHighlight = c.dual('scaffolx');
      expect(noHighlight.approx.single.indices, isEmpty);

      final highlighted = c.dual('scaffolx', highlight: true);
      expect(highlighted.approx.single.indices, isNotEmpty);
    });
  });
}
