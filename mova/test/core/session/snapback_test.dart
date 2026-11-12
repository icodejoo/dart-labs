import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/timeline.dart';
import '../../support/fake_api.dart';
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, sessionFor, done;

const breaks = [
  MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: b,
    offset: Duration(seconds: 30),
    waitForReady: false,
  ),
  MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: b,
    offset: Duration(seconds: 60),
    waitForReady: false,
  ),
  MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: b,
    offset: Duration(seconds: 90),
    waitForReady: false,
  ),
  MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: b,
    offset: Duration(seconds: 90),
    waitForReady: false,
  ),
];
const position = Duration(seconds: 95);

void main() {
  for (final mode in MovaAdSnapback.values) {
    test('补播纯函数 $mode 保留 pod，过滤已播，不改输入', () {
      final nodes = movaBuildNodes(0, breaks);
      final played = <MovaNodeId>{};
      final result = movaSnapback(nodes, position, played, mode);
      expect(played, isEmpty);
      switch (mode) {
        case MovaAdSnapback.all:
          expect(result.play?.id.ordinal, 0);
          expect(result.skip, isEmpty);
        case MovaAdSnapback.last:
          expect(result.play?.id.ordinal, 2);
          expect(result.skip.map((id) => id.ordinal), [0, 1]);
        case MovaAdSnapback.none:
          expect(result.play, isNull);
          expect(result.skip.map((id) => id.ordinal), [0, 1, 2, 3]);
      }
      // 同一个插入点的两条广告不是“跨过多个点”，不能被 none 跳过。
      final single = movaSnapback(nodes, position, {
        nodes[0].id,
        nodes[1].id,
      }, mode);
      expect(single.play?.id.ordinal, 2);
      expect(single.skip, isEmpty);
      const original = MovaAdConfig();
      final configured = original.copyWith(midRollSnapback: mode);
      expect(configured.midRollSnapback, mode);
      expect(configured.copyWith(), configured);
      expect(configured.hashCode, configured.copyWith().hashCode);
      expect(configured == original, mode == MovaAdSnapback.all);
    });
  }
  for (final lastOnly in [true, false]) {
    test('会话前跳 ${lastOnly ? 'last' : '默认 all'} 连播后只回一次正片', () async {
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: lastOnly
              ? const MovaAdConfig(
                  enabled: true,
                  breaks: breaks,
                  midRollSnapback: MovaAdSnapback.last,
                )
              : const MovaAdConfig(enabled: true, breaks: breaks),
        ),
      );
      final session = sessionFor(api);
      final starts = <MovaNodeId>[];
      session.events.listen((e) {
        if (e is MovaNodeStart) starts.add(e.node);
      });
      await session.load(a);
      api.pushProgress(const MovaProg(position: Duration(seconds: 10)));
      await settleOperations();
      api.pushProgress(const MovaProg(position: position));
      await settleOperations();
      final expected = lastOnly ? [2, 3] : [0, 1, 2, 3];
      for (final ordinal in expected) {
        expect(session.cursor.node?.ordinal, ordinal);
        await done(api);
      }
      expect(
        starts
            .where((node) => node.kind == MovaNodeKind.mid)
            .map((node) => node.ordinal),
        expected,
      );
      expect(api.openedUris.where((uri) => uri == a.uri), hasLength(2));
      expect(session.cursor.phase, MovaSessionPhase.content);
      api.pushProgress(const MovaProg(position: position));
      await settleOperations();
      expect(session.isShowingAd, isFalse);
    });
  }
}
