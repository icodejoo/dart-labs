import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/player_mute.dart';

import '../support/fake_api.dart';
import '../support/warm_mute_kernel.dart';
import 'ads_interleaving_test.dart' show AdOperationRig;
import 'cutover/cutover_operation_test.dart' show OperationRig, settleOperations;

/// 本组固定正片。
const _content = MovaSource('https://host/content.mp4');

/// 不等待预热的可跳过前贴片。
const _pre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/ad.mp4'),
  waitForReady: false,
  skippableAfter: Duration.zero,
);

/// 构造普通广告路径；默认加载仍须主动起播。
(FakeMovaApi, MovaAds) _plain({List<MovaAdBreak> breaks = const [_pre]}) {
  final api = FakeMovaApi(options: MovaOpts(ads: MovaAdOpts(enabled: true, breaks: breaks)));
  return (api, MovaAds(api));
}

/// 让广告背后的真实正片影子就绪。
Future<FakeMovaApi> _contentShadow(AdOperationRig rig) async {
  await rig.ads.load(_content);
  rig.movas.first.pushProgress(const MovaProg(position: Duration(seconds: 1)));
  await settleOperations();
  final shadow = rig.movas.last;
  expect(rig.movas, hasLength(2));
  await rig.ready(shadow);
  shadow.calls.clear();
  return shadow;
}

/// 只接入真实局部静音能力；命令与播放意图沿用共享门控替身。
class _WarmApi extends FakeMovaApi implements IMovaPlayerMute {
  /// 启用切换与默认局部静音。
  _WarmApi() : super(options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)));

  /// 可控解静音结果的内核。
  final kernel = FakeWarmMuteKernel();

  /// 将局部静音直接交给内核，不经过系统音量。
  @override
  Future<bool> setWarmMute(bool on) => kernel.setWarmMute(on);
}

void main() {
  test('广告自然播完：意图为真则正片开播（真实 cutover）', () async {
    final rig = AdOperationRig(breaks: const [_pre]);
    addTearDown(rig.dispose);
    final shadow = await _contentShadow(rig);
    rig.movas.first.push(rig.movas.first.state.copyWith(playing: false));
    rig.movas.first.emitDone();
    await settleOperations();
    expect(rig.api.active, same(shadow));
    expect(shadow.calls, contains('play'));
    expect(shadow.calls, isNot(contains('pause')));
    expect(rig.api.state.playbackIntent, isTrue);
  });

  test('广告中用户暂停后跳过：正片以暂停态提交（真实 cutover）', () async {
    final rig = AdOperationRig(breaks: const [_pre]);
    addTearDown(rig.dispose);
    final shadow = await _contentShadow(rig);
    await rig.api.pause();
    rig.ads.skip();
    await settleOperations();
    expect(rig.api.active, same(shadow));
    expect(shadow.calls, contains('pause'));
    expect(shadow.calls, isNot(contains('play')));
    expect(shadow.state.playbackIntent, isFalse);
  });

  test('普通路径：自然播完 autoPlay 为真，暂停后跳过 autoPlay 为假', () async {
    for (final paused in [false, true]) {
      final (api, ads) = _plain();
      await ads.load(_content);
      if (paused) {
        await api.pause();
        ads.skip();
      } else {
        api.emitDone();
      }
      await settleOperations();
      expect(api.source, same(_content));
      expect(api.lastAutoPlay, !paused);
      await ads.dispose();
      await api.dispose();
    }
  });

  test('commit 按旧播放器意图决定影子开播', () async {
    for (final intent in [false, true]) {
      final rig = OperationRig();
      addTearDown(rig.api.dispose);
      // 暂停请求尚未被内核观测时 playing 仍为真，不能覆盖意图。
      rig.movas.first.push(rig.movas.first.state.copyWith(playbackIntent: intent, playing: true));
      final shadow = await rig.warm('shadow');
      shadow.calls.clear();
      expect(await rig.api.commit(), isTrue);
      expect(shadow.calls, contains(intent ? 'play' : 'pause'));
      expect(shadow.calls, isNot(contains(intent ? 'pause' : 'play')));
      expect(shadow.state.playbackIntent, intent);
    }
  });

  test('意图在 old.pause() 之前取', () async {
    final rig = OperationRig();
    addTearDown(rig.api.dispose);
    final shadow = await rig.warm('shadow');
    final old = rig.movas.first;
    final gate = old.pauseGate = Completer<void>();
    final commit = rig.api.commit();
    await settleOperations();
    expect(old.calls, contains('pause'));
    expect(shadow.calls, isNot(contains('play')));
    gate.complete();
    expect(await commit, isTrue);
    expect(old.state.playbackIntent, isFalse);
    expect(shadow.calls, contains('play'));
    expect(shadow.state.playbackIntent, isTrue);
  });

  test('解静音失败的回退按意图：意图假不恢复旧播放器播放', () async {
    final made = <_WarmApi>[];
    final api = MovaCutover(movaFactory: () {
      final mova = _WarmApi();
      made.add(mova);
      return mova;
    });
    addTearDown(api.dispose);
    made.first.push(made.first.state.copyWith(playing: true));
    await settleOperations();
    expect(api.state.playbackIntent, isFalse);
    await api.prepare(_content, plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
    final shadow = made.last;
    shadow.kernel.releaseResult = false;
    for (var i = 0; i < 2; i++) {
      shadow.pushProgress(const MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10)));
      await settleOperations();
    }
    expect(await api.commit(), isFalse);
    expect(shadow.kernel.calls, contains('warmMute:false'));
    final calls = made.first.calls;
    expect(calls, contains('pause'));
    expect(calls.skip(calls.indexOf('pause') + 1), isNot(contains('play')));
  });

  test('待机意愿 + 意图假：影子不进待机，只暂停', () async {
    final made = <FakeKeepAliveApi>[];
    final api = MovaCutover(movaFactory: () {
      final mova = FakeKeepAliveApi(options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)));
      made.add(mova);
      return mova;
    });
    addTearDown(api.dispose);
    await api.setKeepAlive(true);
    await api.pause();
    await api.prepare(_content, plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
    final shadow = made.last;
    for (var i = 0; i < 2; i++) {
      shadow.pushProgress(const MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10)));
      await settleOperations();
    }
    shadow.calls.clear();
    expect(await api.commit(), isTrue);
    expect(shadow.calls, isNot(contains('setKeepAlive:true')));
    expect(shadow.calls, contains('pause'));
    expect(shadow.calls, isNot(contains('play')));
  });

  test('暂停中插播与起播', () async {
    final (api, ads) = _plain(breaks: const []);
    await ads.load(_content);
    await api.pause();
    await ads.playAdNow(_pre);
    expect(api.lastAutoPlay, isFalse);
    await ads.dispose();
    await api.dispose();
    final (fresh, preAds) = _plain();
    expect(fresh.state.playbackIntent, isFalse);
    await preAds.load(_content);
    expect(fresh.lastAutoPlay, isTrue);
    await fresh.pause();
    preAds.skip();
    await settleOperations();
    expect(fresh.lastAutoPlay, isFalse);
    await preAds.dispose();
    await fresh.dispose();
  });
}
