import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../../support/fake_api.dart';
import '../ads_interleaving_test.dart' show AdOperationRig;
import '../cutover/cutover_operation_test.dart' show settleOperations;

/// 测试使用的两集正片。
const a = MovaSource('https://host/a.mp4');
const b = MovaSource('https://host/b.mp4');

/// 按配置播放的前贴片。
const pre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre.mp4'),
);

/// 立即到期的默认等待型中插。
const mid = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/mid.mp4'),
  offset: Duration(seconds: 1),
);

/// 创建借用替身的会话并登记清理。
MovaSession sessionFor(
  FakeMovaApi api, {
  List<MovaPlaylistItem> items = const [],
  bool autoAdvance = false,
}) {
  final session = MovaSession(api, items: items, autoAdvance: autoAdvance);
  addTearDown(() async {
    await session.dispose();
    await api.dispose();
  });
  return session;
}

/// 用确定的结束信号驱动下一段，排空既有操作队列。
Future<void> done(FakeMovaApi api) async {
  api.pushEvent(const MovaDone());
  await settleOperations();
}

void main() {
  test('直接构造识别 cutover：中插预热提交并换指', () async {
    final rig = AdOperationRig(breaks: [mid]);
    await rig.ads.dispose();
    final session = MovaSession(rig.api);
    addTearDown(() async {
      await session.dispose();
      await rig.api.dispose();
    });
    await session.load(a);
    rig.engines.first.pushProgress(
      const MovaProg(position: Duration(seconds: 2)),
    );
    await settleOperations();
    expect(session.isAdPending, isTrue);
    expect(rig.engines, hasLength(2));
    await rig.ready(rig.engines.last);
    expect(session.isShowingAd, isTrue);
    expect(rig.api.state.renderEpoch, 1);
  });

  test('关闭直通代理不创建影子，中插直接 open', () async {
    final engines = <FakeMovaApi>[];
    final api = MovaCutoverEngine(
      engineFactory: () {
        final engine = FakeMovaApi(
          options: const MovaOpts(
            ads: MovaAdConfig(enabled: true, breaks: [mid]),
          ),
        );
        engines.add(engine);
        return engine;
      },
    );
    final session = MovaSession(api);
    addTearDown(() async {
      await session.dispose();
      await api.dispose();
    });
    await session.load(a);
    engines.first.pushProgress(const MovaProg(position: Duration(seconds: 2)));
    await settleOperations();
    expect(engines, hasLength(1));
    expect(engines.first.openedUris, [a.uri, mid.source.uri]);
    expect(session.isShowingAd, isTrue);
  });

  test('MovaAds 不传 cutover 保留直接 open', () async {
    final rig = AdOperationRig(breaks: [mid]);
    await rig.ads.dispose();
    final ads = MovaAds(rig.api);
    addTearDown(() async {
      await ads.dispose();
      await rig.api.dispose();
    });
    expect(ads.session, same(ads.session));
    await ads.load(a);
    rig.engines.first.pushProgress(
      const MovaProg(position: Duration(seconds: 2)),
    );
    await settleOperations();
    expect(rig.engines, hasLength(1));
    expect(rig.engines.first.openedUris, [a.uri, mid.source.uri]);
  });

  test('load 接受返回 accepted', () async {
    final session = sessionFor(FakeMovaApi());
    expect(await session.load(a), MovaLoadOutcome.accepted);
    expect(session.cursor.phase, MovaSessionPhase.content);
  });

  test('正片被拒返回 rejected 且回 idle', () async {
    final session = sessionFor(FakeMovaApi()..acceptOpens = false);
    expect(await session.load(a), MovaLoadOutcome.rejected);
    expect(session.cursor.phase, MovaSessionPhase.idle);
  });

  test('正片抛出返回 failed 并发 contentError', () async {
    final error = StateError('open');
    final session = sessionFor(FakeMovaApi()..openThrows = error);
    final errors = <Object>[];
    session.contentError.listen(errors.add);
    expect(await session.load(a), MovaLoadOutcome.failed);
    await settleOperations();
    expect(errors, [same(error)]);
  });

  test('解析器失败返回 failed', () async {
    final session = sessionFor(FakeMovaApi());
    expect(
      await session.loadDeferred(() async => throw StateError('resolve')),
      MovaLoadOutcome.failed,
    );
    expect(session.cursor.phase, MovaSessionPhase.idle);
  });

  test('load 在途再 load：旧请求 superseded', () async {
    final gate = Completer<void>();
    final api = FakeMovaApi()..openGate = gate;
    final session = sessionFor(api);
    final old = session.load(a);
    await settleOperations();
    api.openGate = null;
    expect(await session.load(b), MovaLoadOutcome.accepted);
    gate.complete();
    expect(await old, MovaLoadOutcome.superseded);
  });

  test('dispose 后 load 返回 disposed', () async {
    final api = FakeMovaApi();
    final session = MovaSession(api);
    await session.dispose();
    expect(await session.load(a), MovaLoadOutcome.disposed);
    expect(api.calls, isEmpty);
    await api.dispose();
  });

  test('前贴片被拒而正片接受仍返回 accepted', () async {
    final gate = Completer<void>();
    final api =
        FakeMovaApi(
            options: const MovaOpts(
              ads: MovaAdConfig(enabled: true, breaks: [pre]),
            ),
          )
          ..acceptOpens = false
          ..openGate = gate;
    final session = sessionFor(api);
    final loading = session.load(a);
    await settleOperations();
    gate.complete();
    scheduleMicrotask(() {
      api.acceptOpens = true;
      api.openGate = null;
    });
    expect(await loading, MovaLoadOutcome.accepted);
    expect(api.source, a);
  });

  test('接受不等于首帧', () async {
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])),
    );
    final session = sessionFor(api);
    expect(await session.load(a), MovaLoadOutcome.accepted);
    expect(api.state.rendered, isFalse);
    expect(session.isShowingAd, isTrue);
  });

  test('按集广告覆盖配置，null 回落配置，空列表覆盖为空', () async {
    const own = MovaAdBreak(kind: MovaAdBreakKind.pre, source: b);
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [pre])),
    );
    final session = sessionFor(
      api,
      items: const [
        MovaPlaylistItem(source: a, adBreaks: [own]),
        MovaPlaylistItem(source: b),
        MovaPlaylistItem(source: a, adBreaks: []),
      ],
    );
    await session.jumpTo(0);
    expect(api.source, b);
    await session.jumpTo(1);
    expect(api.source, pre.source);
    await session.jumpTo(2);
    expect(api.source, a);
    expect(session.cursor.item, 2);
    expect(() => session.items.clear(), throwsUnsupportedError);
  });

  test('jumpTo 被拒或取代不提交下标，越界 rejected', () async {
    final api = FakeMovaApi();
    final session = sessionFor(
      api,
      items: const [
        MovaPlaylistItem(source: a),
        MovaPlaylistItem(source: b),
      ],
    );
    api.acceptOpens = false;
    expect(await session.jumpTo(1), MovaLoadOutcome.rejected);
    expect(session.cursor.item, 0);
    api.acceptOpens = true;
    final gate = Completer<void>();
    api.openGate = gate;
    final old = session.jumpTo(1);
    await settleOperations();
    api.openGate = null;
    await session.jumpTo(0);
    gate.complete();
    expect(await old, MovaLoadOutcome.superseded);
    expect(session.cursor.item, 0);
    expect(await session.previous(), MovaLoadOutcome.rejected);
    expect(await session.jumpTo(99), MovaLoadOutcome.rejected);
  });

  test('autoAdvance 全部结束后下一集，末尾不回绕', () async {
    final api = FakeMovaApi();
    final session = sessionFor(
      api,
      autoAdvance: true,
      items: const [
        MovaPlaylistItem(source: a),
        MovaPlaylistItem(source: b),
      ],
    );
    await session.jumpTo(0);
    await done(api);
    expect(session.cursor.item, 1);
    expect(api.source, b);
    await done(api);
    expect(api.openedUris, [a.uri, b.uri]);
    expect(session.cursor.phase, MovaSessionPhase.idle);
  });

  test('会话 dispose 后借用 api 仍可用', () async {
    final api = FakeMovaApi();
    final session = MovaSession(api);
    await session.load(a);
    await session.dispose();
    expect(await api.open(b), isTrue);
    expect(api.source, b);
    await api.dispose();
  });
}
