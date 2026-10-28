import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/api.dart';
import 'package:mova/src/core/feed/engine_pool.dart';
import 'package:mova/src/core/feed/feed.dart';
import 'package:mova/src/core/model/feed_item.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/ui/components/bottom_bar.dart';
import 'package:mova/src/ui/components/center_play.dart';
import 'package:mova/src/ui/components/danmaku.dart';
import 'package:mova/src/ui/components/gesture_layer.dart';
import 'package:mova/src/ui/components/hud_layer.dart';
import 'package:mova/src/ui/components/overlays.dart';
import 'package:mova/src/ui/components/preview.dart';
import 'package:mova/src/ui/components/speed_button.dart';
import 'package:mova/src/ui/components/subtitle.dart';
import 'package:mova/src/ui/components/top_bar.dart';
import 'package:mova/src/ui/mini/mini_skin.dart';
import 'package:mova/src/ui/skins/bilibili_skin.dart';
import 'package:mova/src/ui/skins/default_skin.dart';
import 'package:mova/src/ui/skins/douyin_skin.dart';
import 'package:mova/src/ui/skins/minimal_skin.dart';
import 'package:mova/src/ui/skins/skin.dart';
import 'package:mova/src/ui/slots/component.dart';
import 'package:mova/src/ui/slots/patch.dart';
import 'package:mova/src/ui/slots/slot.dart';

import '../support/fake_api.dart';

/// Flattens [cs] depth-first into `path@slot` strings, the way `MovaPatch`
/// addresses nodes (`parent/child`).
///
/// 把 [cs] 深度优先拍平成 `路径@槽位` 字符串，路径写法与 `MovaPatch` 寻址一致
/// （`父/子`）。
List<String> _flat(List<MovaComponent> cs, [String prefix = '']) {
  final out = <String>[];
  for (final c in cs) {
    final p = prefix.isEmpty ? c.name : '$prefix/${c.name}';
    out.add('$p@${c.slot.name}');
    out.addAll(_flat(c.children, p));
  }
  return out;
}

/// Just the paths of [cs], slot suffix dropped.
///
/// 只取 [cs] 的路径，去掉槽位后缀。
List<String> _paths(List<MovaComponent> cs) => _flat(cs).map((s) => s.split('@').first).toList();

/// The default skin's tree, in order, with each node's slot.
///
/// 默认皮肤的组件树，按顺序并带每个节点的槽位。
const _defaultTree = <String>[
  'gestureLayer@gesture',
  'hudLayer@hud',
  'hudLayer/volumeHud@hud',
  'hudLayer/brightnessHud@hud',
  'hudLayer/seekHud@hud',
  'hudLayer/zoomHud@hud',
  'topBar@top',
  'topBar/title@top',
  'topBar/pipButton@top',
  'topBar/qualityButton@top',
  'topBar/subtitleButton@top',
  'topBar/fitButton@top',
  'topBar/orientationButton@top',
  'topBar/fullscreenButton@top',
  'centerPlay@center',
  'centerPlay/playPause@center',
  'preview@bottomAbove',
  'subtitleOverlay@overlay',
  'bottomBar@bottom',
  'bottomBar/positionLabel@bottom',
  'bottomBar/liveBadge@bottom',
  'bottomBar/seekBar@bottom',
  'bottomBar/timeshift@bottom',
  'bottomBar/durationLabel@bottom',
  'bottomBar/backToLive@bottom',
  'buffering@center',
  'error@center',
  'lockMask@overlay',
];

/// A marker leaf for patch tests.
///
/// 补丁测试用的标记叶子。
class _Marker extends MovaComponent {
  _Marker(this.name, this.slot);
  @override
  final String name;
  @override
  final MovaSlot slot;
  @override
  Widget build(BuildContext c, MovaApi api, List<Widget> children) => const SizedBox.shrink();
}

/// Builds a feed controller whose pool hands out [api] for every page.
///
/// 构建一个控制器，其池为每一页都发放 [api]。
Future<MovaFeed> _feedWith(FakeMovaApi api, MovaFeedItem item) async {
  final controller = MovaFeed(
    pool: MovaFeedEnginePool(engineFactory: () => api, size: 1),
    loader: (i) async => item,
  );
  await controller.ensure(0);
  return controller;
}

void main() {
  group('S1: componentName matches the instance name', () {
    // Each triple is (instance, its componentName constant, the exact path
    // segment hosts address in MovaPatch).
    // 每个三元组是（实例、它的 componentName 常量、宿主在 MovaPatch 里寻址用的确切路径片段）。
    final triples = <(MovaComponent, String, String)>[
      (MovaBottomBarComponent(), MovaBottomBarComponent.componentName, 'bottomBar'),
      (MovaPositionLabelComponent(), MovaPositionLabelComponent.componentName, 'positionLabel'),
      (MovaDurationLabelComponent(), MovaDurationLabelComponent.componentName, 'durationLabel'),
      (MovaSeekBarComponent(), MovaSeekBarComponent.componentName, 'seekBar'),
      (MovaLiveBadgeComponent(), MovaLiveBadgeComponent.componentName, 'liveBadge'),
      (MovaTimeshiftLabelComponent(), MovaTimeshiftLabelComponent.componentName, 'timeshift'),
      (MovaBackToLiveComponent(), MovaBackToLiveComponent.componentName, 'backToLive'),
      (MovaCenterPlayComponent(), MovaCenterPlayComponent.componentName, 'centerPlay'),
      (MovaPlayPauseComponent(), MovaPlayPauseComponent.componentName, 'playPause'),
      (MovaDanmakuTrackComponent(), MovaDanmakuTrackComponent.componentName, 'danmakuTrack'),
      (MovaGestureLayerComponent(), MovaGestureLayerComponent.componentName, 'gestureLayer'),
      (MovaHudLayerComponent(), MovaHudLayerComponent.componentName, 'hudLayer'),
      (MovaVolumeHudComponent(), MovaVolumeHudComponent.componentName, 'volumeHud'),
      (MovaBrightnessHudComponent(), MovaBrightnessHudComponent.componentName, 'brightnessHud'),
      (MovaSeekHudComponent(), MovaSeekHudComponent.componentName, 'seekHud'),
      (MovaZoomHudComponent(), MovaZoomHudComponent.componentName, 'zoomHud'),
      (MovaBufferingComponent(), MovaBufferingComponent.componentName, 'buffering'),
      (MovaErrorComponent(), MovaErrorComponent.componentName, 'error'),
      (MovaLockMaskComponent(), MovaLockMaskComponent.componentName, 'lockMask'),
      (MovaPreviewComponent(), MovaPreviewComponent.componentName, 'preview'),
      (MovaSpeedButtonComponent(), MovaSpeedButtonComponent.componentName, 'speedButton'),
      (MovaSubtitleOverlayComponent(), MovaSubtitleOverlayComponent.componentName, 'subtitleOverlay'),
      (MovaSubtitleButtonComponent(), MovaSubtitleButtonComponent.componentName, 'subtitleButton'),
      (MovaTopBarComponent(), MovaTopBarComponent.componentName, 'topBar'),
      (MovaTitleComponent(), MovaTitleComponent.componentName, 'title'),
      (MovaPipButtonComponent(), MovaPipButtonComponent.componentName, 'pipButton'),
      (MovaQualityButtonComponent(), MovaQualityButtonComponent.componentName, 'qualityButton'),
      (MovaFitButtonComponent(), MovaFitButtonComponent.componentName, 'fitButton'),
      (MovaOrientationButtonComponent(), MovaOrientationButtonComponent.componentName, 'orientationButton'),
      (MovaFullscreenButtonComponent(), MovaFullscreenButtonComponent.componentName, 'fullscreenButton'),
      (MovaMiniCloseComponent(), MovaMiniCloseComponent.componentName, 'miniClose'),
    ];

    test('every no-argument component: name == componentName == the published string', () {
      for (final (c, constant, literal) in triples) {
        expect(c.name, constant, reason: '${c.runtimeType}.name vs componentName');
        expect(constant, literal, reason: '${c.runtimeType}.componentName changed - it breaks MovaPatch paths');
      }
    });

    test('component names are unique across the table', () {
      final names = triples.map((p) => p.$3).toList();
      expect(names.toSet(), hasLength(names.length));
    });
  });

  group('S1: each skin ships the documented tree and slot layout', () {
    test('MovaDefaultSkin', () {
      expect(_flat(const MovaDefaultSkin().components()), _defaultTree);
    });

    test('MovaBilibiliSkin is the default tree plus speedButton (top bar) and danmakuTrack (overlay)', () {
      final tree = _flat(MovaBilibiliSkin().components());
      expect(tree, containsAll(_defaultTree));
      expect(tree.toSet().difference(_defaultTree.toSet()), {'topBar/speedButton@top', 'danmakuTrack@overlay'});
      // The speed button sits right after the quality button.
      // 倍速按钮紧跟在清晰度按钮之后。
      final top = tree.where((s) => s.startsWith('topBar/')).toList();
      expect(top.indexOf('topBar/speedButton@top'), top.indexOf('topBar/qualityButton@top') + 1);
      expect(tree.last, 'danmakuTrack@overlay');
    });

    test('MovaMinimalSkin: buffering only by default, flags swap the pieces', () {
      expect(_flat(const MovaMinimalSkin().components()), ['buffering@center']);
      expect(_flat(const MovaMinimalSkin(showBuffering: false, showError: true).components()), ['error@center']);
      expect(_flat(const MovaMinimalSkin(showBuffering: true, showError: true).components()), [
        'buffering@center',
        'error@center',
      ]);
      expect(const MovaMinimalSkin(showBuffering: false).components(), isEmpty);
    });

    test('MovaMiniSkin: centre play, buffering and a top-corner close', () {
      expect(_flat(const MovaMiniSkin().components()), [
        'centerPlay@center',
        'centerPlay/playPause@center',
        'buffering@center',
        'miniClose@top',
      ]);
    });

    test('MovaDouyinSkin: gesture layer, right-edge rail and bottom info', () async {
      final api = FakeMovaApi();
      final item = MovaFeedItem(source: const MovaSource('https://h/0.mp4'));
      final controller = await _feedWith(api, item);
      final skin = MovaDouyinSkin(
        item: item,
        controller: controller,
        index: 0,
        likeNotifier: ValueNotifier(controller.likeStateOf(0)),
      );
      final tree = _flat(skin.components());
      expect(tree.first, 'douyinGestureLayer@gesture');
      expect(tree, containsAll(<String>['socialRail@right', 'feedInfo@bottom']));
      expect(
        tree.where((s) => s.startsWith('socialRail/')).map((s) => s.split('@').first),
        containsAll(<String>[
          'socialRail/avatar',
          'socialRail/likeButton',
          'socialRail/commentButton',
          'socialRail/shareButton',
        ]),
      );
      await api.dispose();
    });
  });

  group('S12: the four patch kinds on the skins that accept patches', () {
    /// Every skin that takes `patches:` and the factory that builds it.
    ///
    /// 所有接受 `patches:` 的皮肤及其构造方式。
    final skins = <String, MovaSkin Function(List<MovaPatch>)>{
      'default': (p) => MovaDefaultSkin(patches: p),
      'bilibili': (p) => MovaBilibiliSkin(patches: p),
    };

    for (final entry in skins.entries) {
      group(entry.key, () {
        test('remove drops the node and its subtree', () {
          final tree = _paths(entry.value([MovaPatch.remove('topBar/fitButton')]).components());
          expect(tree, isNot(contains('topBar/fitButton')));
          expect(tree, contains('topBar/fullscreenButton'));
          final gone = _paths(entry.value([MovaPatch.remove('hudLayer')]).components());
          expect(gone.where((p) => p.startsWith('hudLayer')), isEmpty);
        });

        test('replace swaps the node in place, keeping its position', () {
          final base = _paths(entry.value(const []).components());
          final patched = _paths(
            entry.value([MovaPatch.replace('topBar/fitButton', _Marker('myFit', MovaSlot.top))]).components(),
          );
          expect(patched, isNot(contains('topBar/fitButton')));
          final i = base.indexOf('topBar/fitButton');
          expect(patched[i], 'topBar/myFit');
          expect(patched.length, base.length);
        });

        test('insertAfter lands the new node right behind its anchor', () {
          final patched = _paths(
            entry.value([MovaPatch.insertAfter('topBar/title', _Marker('badge', MovaSlot.top))]).components(),
          );
          expect(patched.indexOf('topBar/badge'), patched.indexOf('topBar/title') + 1);
        });

        test('add puts a new top-level node into the given slot', () {
          final flat = _flat(
            entry.value([MovaPatch.add(MovaSlot.left, _Marker('side', MovaSlot.left))]).components(),
          );
          expect(flat, contains('side@left'));
        });

        test('patches apply in order and compose', () {
          final tree = _paths(
            entry.value([
              MovaPatch.remove('topBar/fitButton'),
              MovaPatch.insertAfter('topBar/title', _Marker('badge', MovaSlot.top)),
              MovaPatch.add(MovaSlot.right, _Marker('rail', MovaSlot.right)),
            ]).components(),
          );
          expect(tree, isNot(contains('topBar/fitButton')));
          expect(tree, contains('topBar/badge'));
          expect(tree, contains('rail'));
        });
      });
    }

    test('bilibili: user patches stack on top of the preset ones', () {
      final tree = _paths(MovaBilibiliSkin(patches: [MovaPatch.remove('topBar/speedButton')]).components());
      expect(tree, isNot(contains('topBar/speedButton')));
      expect(tree, contains('danmakuTrack'), reason: 'the preset danmaku patch must survive');
    });
  });
}
