// ignore_for_file: avoid_print
// S 皮肤专项验证页：按皮肤参数化，复用 coverage_gap.dart 的 gap 日志/caseOf/verdict。
// Skin-specific verification (matrix §3.3 S): parameterised per skin, reusing the
// `gap` logger / `caseOf` / `verdict` from coverage_gap.dart.
import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

import 'coverage_gap.dart';

/// 五套皮肤的固定顺序。 / The five skins under test, in run order.
const skinNames = ['default', 'bilibili', 'douyin', 'minimal', 'mini'];

/// 合成指针事件之间的停顿。 / Pause between synthetic pointer events.
const _pointerPause = Duration(milliseconds: 60);

/// 点击后等待组件树稳定的时长。 / Settle time after a layout-changing action.
const _settle = Duration(milliseconds: 700);

/// 主题/文案注入用的非默认探针值。 / Non-default probe values for S13.
const _probeTheme = MovaTheme(
  iconColor: 0xFF00C853,
  textColor: 0xFFFFD600,
  accentColor: 0xFF2979FF,
  titleFontSize: 21,
  timeFontSize: 15,
  captionFontSize: 13,
  centerIconSize: 88,
  bufferingSize: 37,
  bufferingStrokeWidth: 6,
  bufferingColor: 0xFFFF1744,
);
const _probeStrings = MovaStrs(
  fitContain: 'FIT-A',
  fitCover: 'FIT-B',
  fitFill: 'FIT-C',
  speedSuffix: 'XX',
);

/// 控制条不自动隐藏，保证点击目标稳定。 / Bars never auto-hide so targets stay put.
const _baseOptions = MovaOpts(controls: MovaCtrlsConfig(autoHide: false));

/// 皮肤舞台的配置：引擎 + 皮肤。 / Stage config: engine plus skin.
class GapSkinStage {
  /// 创建舞台配置。 / Creates the stage config.
  const GapSkinStage(this.api, this.skin);

  /// 被测引擎。 / Engine under test.
  final MovaApi api;

  /// 当前挂载的皮肤。 / Currently mounted skin.
  final MovaSkin skin;
}

/// 非空时 main_coverage_gap 改为渲染该舞台。 / When non-null the entry renders this stage.
final gapSkinStage = ValueNotifier<GapSkinStage?>(null);

/// 渲染舞台：整屏 MovaPlayer，换皮肤只改 skin 参数。 / Full-screen player; swapping skin only changes `skin`.
Widget gapSkinStageView(GapSkinStage s) =>
    SizedBox.expand(child: MovaPlayer(api: s.api, skin: s.skin));

/// 向 gap 运行器注册 skin 分组。 / Registers the `skin` group with the gap runner.
void registerGapSkinGroup() => gapGroups['skin'] = runSkinGroup;

/// 皮肤专用探针组件：可挂到任意槽位并带点击回调。 / Probe component for patch checks.
class GapProbe extends MovaComponent {
  /// 创建探针；[label] 同时是 name。 / Creates a probe; [label] doubles as `name`.
  GapProbe(this.label, this._slot, {this.onTap});

  /// 组件名与文本标签。 / Component name and text label.
  final String label;
  final MovaSlot _slot;

  /// 点击回调。 / Tap callback.
  final VoidCallback? onTap;

  @override
  String get name => label;

  @override
  MovaSlot get slot => _slot;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'GAP:$label',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      );
}

/// 皮肤夹具：Douyin 需要 feed，其余无状态；统计宿主回调次数。
/// Per-skin fixture: Douyin needs a feed; counts host callbacks.
class SkinFixture {
  /// 创建夹具。 / Creates the fixture.
  SkinFixture(this.name);

  /// 皮肤名。 / Skin name.
  final String name;

  /// 宿主回调计数。 / Host callback counters.
  final counts = <String, int>{};

  /// Douyin 用的 feed。 / Feed for Douyin.
  MovaFeed? feed;

  /// Douyin 点赞状态。 / Douyin like state.
  ValueNotifier<({bool liked, int count})>? like;

  /// 本夹具构造的皮肤。 / Skin built by this fixture.
  late MovaSkin skin;

  void _bump(String key) => counts[key] = (counts[key] ?? 0) + 1;

  /// 初始化皮肤（Douyin 预载一个 feed 条目，不创建池引擎）。
  /// Builds the skin (Douyin preloads one feed item; no pool engine is created).
  Future<void> init() async {
    switch (name) {
      case 'default':
        skin = const MovaDefaultSkin();
      case 'bilibili':
        skin = MovaBilibiliSkin();
      case 'minimal':
        skin = const MovaMinimalSkin();
      case 'mini':
        skin = MovaMiniSkin(onClose: () => _bump('miniClose'));
      case 'douyin':
        final item = MovaFeedItem(
          source: MovaSource('http://127.0.0.1:18085/long.mp4'),
          authorName: 'gap-author',
          musicName: 'gap-music',
          initialLikeCount: 5,
          commentCount: 2,
          shareCount: 3,
          onLikeChanged: (liked, count) => _bump('like'),
          onComment: () => _bump('comment'),
          onShare: () => _bump('share'),
          onAvatarTap: () => _bump('avatar'),
          onFollowTap: () => _bump('follow'),
        );
        final f = MovaFeed(
          pool: MovaFeedEnginePool(
            engineFactory: () {
              throw StateError('skin fixture must never build pool engines');
            },
          ),
          loader: (i) async => item,
        );
        await f.ensure(0);
        feed = f;
        like = ValueNotifier((liked: item.initialLiked, count: item.initialLikeCount));
        skin = MovaDouyinSkin(
          item: f.peek(0)!,
          controller: f,
          index: 0,
          likeNotifier: like!,
        );
      default:
        throw ArgumentError('unknown skin $name');
    }
  }

  /// 释放夹具资源。 / Releases fixture resources.
  Future<void> dispose() async {
    feed?.dispose();
    await feed?.pool.dispose();
    like?.dispose();
  }
}

/// 一次皮肤用例的运行句柄。 / Handle of one running skin case.
class SkinRun {
  /// 创建句柄。 / Creates the handle.
  SkinRun(this.name, this.a, this.fx, this.skin);

  /// 皮肤名。 / Skin name.
  final String name;

  /// 引擎。 / Engine.
  final MovaApi a;

  /// 夹具。 / Fixture.
  final SkinFixture fx;

  /// 实际挂载的皮肤（可能是补丁变体）。 / Mounted skin (may be a patched variant).
  final MovaSkin skin;
}

// ---------------------------------------------------------------- 组件树工具

/// 递归描述组件：name@slot[children]。 / Describes a component as `name@slot[children]`.
String describe(MovaComponent c) {
  final kids = c.children;
  return '${c.name}@${c.slot.name}'
      '${kids.isEmpty ? '' : '[${kids.map(describe).join(',')}]'}';
}

/// 当前所有已挂载元素。 / All currently mounted elements.
List<Element> allElements() {
  final out = <Element>[];
  void visit(Element e) {
    out.add(e);
    e.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return out;
}

/// 指定图标的元素。 / Elements showing [icon].
List<Element> iconsOf(IconData icon) => allElements()
    .where((e) => e.widget is Icon && (e.widget as Icon).icon == icon)
    .toList();

/// 指定文本的元素。 / Elements showing exactly [text].
List<Element> textsOf(String text) => allElements()
    .where((e) => e.widget is Text && (e.widget as Text).data == text)
    .toList();

/// 按 runtimeType 名统计挂载的 widget。 / Counts mounted widgets by runtime type name.
int countKind(String type) =>
    allElements().where((e) => '${e.widget.runtimeType}' == type).length;

/// 元素中心的全局逻辑坐标，未渲染则为 null。 / Global logical centre of [e], null if not laid out.
Offset? centerOf(Element e) {
  final ro = e.renderObject;
  if (ro is RenderBox && ro.attached && ro.hasSize) {
    return ro.localToGlobal(ro.size.center(Offset.zero));
  }
  return null;
}

/// 当前视图逻辑尺寸。 / Logical size of the implicit view.
Size viewSize() {
  final v = PlatformDispatcher.instance.implicitView;
  return v == null ? Size.zero : v.physicalSize / v.devicePixelRatio;
}

int _viewId() => PlatformDispatcher.instance.implicitView?.viewId ?? 0;

/// 等待若干帧。 / Waits [n] frames.
Future<void> frames([int n = 3]) async {
  for (var i = 0; i < n; i++) {
    await WidgetsBinding.instance.endOfFrame;
  }
}

// ---------------------------------------------------------------- 注入与截图

int _pointerSeq = 9000;
int _shotSeq = 0;

/// 命中路径的前几个 target 类型。 / First few hit-test target types at [p].
List<String> hitPath(Offset p) {
  final r = HitTestResult();
  WidgetsBinding.instance.hitTestInView(r, p, _viewId());
  return r.path.take(8).map((e) => '${e.target.runtimeType}').toList();
}

/// 在 [p] 注入 [count] 次点击（count=2 为双击）。走与真实触摸相同的 GestureBinding 命中链路。
/// Injects [count] taps at [p] (2 = double tap) through the same GestureBinding path as real touches.
Future<void> injectTap(Offset p, String why, {int count = 1}) {
  final dpr = PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1;
  return gap.call(
    'inject.tap',
    {
      'why': why,
      'gesture': count == 1 ? 'tap' : 'doubleTap',
      'logical': '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}',
      'adbEquivalent':
          'adb shell input tap ${(p.dx * dpr).round()} ${(p.dy * dpr).round()}',
      'hitPath': hitPath(p),
    },
    () async {
      for (var i = 0; i < count; i++) {
        final id = _pointerSeq++;
        GestureBinding.instance.handlePointerEvent(
          PointerDownEvent(
            pointer: id,
            position: p,
            kind: PointerDeviceKind.touch,
            viewId: _viewId(),
          ),
        );
        await Future<void>.delayed(_pointerPause);
        GestureBinding.instance.handlePointerEvent(
          PointerUpEvent(
            pointer: id,
            position: p,
            kind: PointerDeviceKind.touch,
            viewId: _viewId(),
          ),
        );
        await Future<void>.delayed(_pointerPause);
      }
      await frames(2);
    },
  );
}

/// 点击指定图标；找不到返回 false 并记 STEP。 / Taps the first [icon]; false (logged) if absent.
Future<bool> tapIcon(IconData icon, String why) async {
  final hits = iconsOf(icon);
  final c = hits.isEmpty ? null : centerOf(hits.first);
  if (c == null) {
    gap.log('STEP', {'tapIcon': why, 'found': false, 'icon': '$icon'});
    return false;
  }
  await injectTap(c, why);
  return true;
}

/// 发 SHOT 行并等宿主截图落盘（mark 名 `shot-seq`）。 / Emits SHOT and waits for the host capture mark.
Future<void> shot(String tag) async {
  final seq = ++_shotSeq;
  gap.log('SHOT', {'name': 'skin-$tag-$seq', 'manual': tag});
  await gap.until(() => gap.marks.contains('shot-$seq'));
}

// ---------------------------------------------------------------- 引擎与挂载

/// 构造引擎并接入 gap 观察，不动 gapScreen。 / Builds an engine and wires gap observation without touching gapScreen.
Future<MovaApi> skinEngine(MovaOpts options) async {
  final a = await gap.call<MovaApi>(
    'createMovaEngine',
    {'skinOptions': true},
    () => createMovaEngine(options: options),
  );
  gap.api = a;
  gap.observe(a);
  return a;
}

/// 打开 HLS 母带并等待可用清晰度。 / Opens the HLS master and waits for selectable qualities.
Future<void> openMaster(MovaApi a, {String? title, String path = 'master.m3u8'}) async {
  final src = MovaSource(gap.source(path).uri, title: title);
  await gap.call('open', {'uri': src.uri, 'title': title}, () => a.open(src));
  await gap.until(() => a.state.duration.inSeconds >= 40 && !a.state.buffering);
  await gap.until(() async => await gap.pos() > 500);
  await gap.call('loadQualities', {}, a.loadQualities);
  await gap.until(() => a.state.qualities.where((q) => !q.isAuto).length >= 2);
}

/// L 规范第 6 条：当前皮肤类名、组件名单、各槽位组件、视图信息。
/// L-rule 6: skin class, component names, per-slot components, view info.
void logSkin(String name, MovaSkin skin) {
  final comps = skin.components();
  final slots = <String, List<String>>{};
  for (final c in comps) {
    slots.putIfAbsent(c.slot.name, () => []).add(c.name);
  }
  final v = PlatformDispatcher.instance.implicitView;
  gap.log('STEP', {
    'skin': '${skin.runtimeType}',
    'name': name,
    'components': comps.map((c) => c.name).toList(),
    'tree': comps.map(describe).toList(),
    'slots': slots,
    'view': {
      'logical': '${viewSize()}',
      'dpr': v?.devicePixelRatio,
      'platform': '$defaultTargetPlatform',
    },
  });
}

/// 皮肤用例封装：建夹具与引擎、挂舞台、跑 [body]，结束先卸舞台再交给 caseOf 销毁引擎。
/// Skin case wrapper: builds fixture/engine, mounts the stage, runs [body]; unmounts the stage before caseOf disposes the engine.
Future<void> skinCase(
  String id,
  List<String> refs,
  String skinName,
  Future<void> Function(SkinRun r) body, {
  MovaOpts options = _baseOptions,
  bool open = true,
  String? title,
  MovaSkin Function(SkinFixture fx, MovaApi a)? skinOf,
}) {
  return gap.caseOf(id, refs, () async {
    final fx = SkinFixture(skinName);
    try {
      await fx.init();
      final a = await skinEngine(options);
      final skin = skinOf == null ? fx.skin : skinOf(fx, a);
      gapSkinStage.value = GapSkinStage(a, skin);
      await frames();
      logSkin(skinName, skin);
      if (open) await openMaster(a, title: title);
      a.showControls(sticky: true);
      await frames();
      await body(SkinRun(skinName, a, fx, skin));
    } finally {
      gapSkinStage.value = null;
      await frames();
      await fx.dispose();
    }
  });
}

/// 自 [start] 起某类事件的数量。 / Count of events of type [T] since [start].
int evCount<T extends MovaEvent>(int start) =>
    gap.events.skip(start).whereType<T>().length;

/// 自 [start] 起的事件类型名。 / Event type names since [start].
List<String> evNames(int start) =>
    gap.events.skip(start).map((e) => '${e.runtimeType}').toList();

// ---------------------------------------------------------------- 期望表（S1）

const _hud =
    'hudLayer@hud[volumeHud@hud,brightnessHud@hud,seekHud@hud,zoomHud@hud]';
const _bottomBar =
    'bottomBar@bottom[positionLabel@bottom,liveBadge@bottom,seekBar@bottom,timeshift@bottom,durationLabel@bottom,backToLive@bottom]';

String _topBar(bool speed) => 'topBar@top[title@top,pipButton@top,'
    'qualityButton@top,${speed ? 'speedButton@top,' : ''}subtitleButton@top,'
    'fitButton@top,orientationButton@top,fullscreenButton@top]';

List<String> _defaultTree({required bool bilibili}) => [
      'gestureLayer@gesture',
      _hud,
      _topBar(bilibili),
      'centerPlay@center[playPause@center]',
      'preview@bottomAbove',
      'subtitleOverlay@overlay',
      _bottomBar,
      'buffering@center',
      'error@center',
      'lockMask@overlay',
      if (bilibili) 'danmakuTrack@overlay',
    ];

const _douyinTree = [
  'douyinGestureLayer@gesture',
  'socialRail@right[avatar@right,likeButton@right,commentButton@right,shareButton@right]',
  'feedInfo@bottom',
];
const _miniTree = [
  'centerPlay@center[playPause@center]',
  'buffering@center',
  'miniClose@top',
];

List<String> _expectedTree(String skin) => switch (skin) {
      'default' => _defaultTree(bilibili: false),
      'bilibili' => _defaultTree(bilibili: true),
      'douyin' => _douyinTree,
      'minimal' => const ['buffering@center'],
      'mini' => _miniTree,
      _ => const [],
    };

/// 点播布局下各皮肤应挂载的图标。 / Icons each skin must mount in VOD layout.
List<IconData> _expectedIcons(String skin) => switch (skin) {
      'default' || 'bilibili' => [
          Icons.pause_circle_filled_rounded,
          Icons.fullscreen_rounded,
          Icons.aspect_ratio_rounded,
          Icons.lock_open_rounded,
        ],
      'douyin' => [
          Icons.favorite_border_rounded,
          Icons.chat_bubble_rounded,
          Icons.reply_rounded,
          Icons.music_note_rounded,
        ],
      'mini' => [Icons.pause_circle_filled_rounded, Icons.close],
      _ => const [],
    };

// ---------------------------------------------------------------- 用例

/// 矩阵里已标 N/A 的 17 格：只记日志与依据，不出结论。
/// The 17 matrix cells already marked N/A: log basis only, no verdict.
Future<void> matrixNa() async {
  const minimal = 'N/A¹ MovaMinimalSkin.components() 只有缓冲层与错误层 (minimal_skin.dart:49)';
  const mini = 'N/A² MovaMiniSkin.components() 只有中心播放/缓冲/关闭 (mini_skin.dart:42)';
  const patch = 'N/A³ 只有 MovaDefaultSkin.components() 调 applyPatches (default_skin.dart:62)，Bilibili 继承；Douyin/Minimal/Mini 不经补丁';
  final cells = <String, String>{
    for (final s in ['S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9']) '$s×minimal': minimal,
    for (final s in ['S3', 'S4', 'S5', 'S6', 'S7', 'S8']) '$s×mini': mini,
    for (final s in ['douyin', 'minimal', 'mini']) 'S12×$s': patch,
  };
  gap.log('STEP', {'matrixNA': cells, 'count': cells.length});
}

/// S1：所有被皮肤引用的组件 componentName 常量 == name getter == 期望字面量。
/// S1: componentName constant == name getter == expected literal for every skin-referenced component.
Future<void> componentNames() async {
  final fx = SkinFixture('douyin');
  await fx.init();
  try {
    final f = fx.feed!;
    final item = f.peek(0)!;
    final n = fx.like!;
    final rows = <(String, String, MovaComponent)>[
      ('gestureLayer', MovaGestureLayerComponent.componentName, MovaGestureLayerComponent()),
      ('hudLayer', MovaHudLayerComponent.componentName, MovaHudLayerComponent()),
      ('volumeHud', MovaVolumeHudComponent.componentName, MovaVolumeHudComponent()),
      ('brightnessHud', MovaBrightnessHudComponent.componentName, MovaBrightnessHudComponent()),
      ('seekHud', MovaSeekHudComponent.componentName, MovaSeekHudComponent()),
      ('zoomHud', MovaZoomHudComponent.componentName, MovaZoomHudComponent()),
      ('topBar', MovaTopBarComponent.componentName, MovaTopBarComponent()),
      ('title', MovaTitleComponent.componentName, MovaTitleComponent()),
      ('pipButton', MovaPipButtonComponent.componentName, MovaPipButtonComponent()),
      ('qualityButton', MovaQualityButtonComponent.componentName, MovaQualityButtonComponent()),
      ('subtitleButton', MovaSubtitleButtonComponent.componentName, MovaSubtitleButtonComponent()),
      ('fitButton', MovaFitButtonComponent.componentName, MovaFitButtonComponent()),
      ('orientationButton', MovaOrientationButtonComponent.componentName, MovaOrientationButtonComponent()),
      ('fullscreenButton', MovaFullscreenButtonComponent.componentName, MovaFullscreenButtonComponent()),
      ('speedButton', MovaSpeedButtonComponent.componentName, MovaSpeedButtonComponent()),
      ('centerPlay', MovaCenterPlayComponent.componentName, MovaCenterPlayComponent()),
      ('playPause', MovaPlayPauseComponent.componentName, MovaPlayPauseComponent()),
      ('preview', MovaPreviewComponent.componentName, MovaPreviewComponent()),
      ('subtitleOverlay', MovaSubtitleOverlayComponent.componentName, MovaSubtitleOverlayComponent()),
      ('bottomBar', MovaBottomBarComponent.componentName, MovaBottomBarComponent()),
      ('positionLabel', MovaPositionLabelComponent.componentName, MovaPositionLabelComponent()),
      ('liveBadge', MovaLiveBadgeComponent.componentName, MovaLiveBadgeComponent()),
      ('seekBar', MovaSeekBarComponent.componentName, MovaSeekBarComponent()),
      ('timeshift', MovaTimeshiftLabelComponent.componentName, MovaTimeshiftLabelComponent()),
      ('durationLabel', MovaDurationLabelComponent.componentName, MovaDurationLabelComponent()),
      ('backToLive', MovaBackToLiveComponent.componentName, MovaBackToLiveComponent()),
      ('buffering', MovaBufferingComponent.componentName, MovaBufferingComponent()),
      ('error', MovaErrorComponent.componentName, MovaErrorComponent()),
      ('lockMask', MovaLockMaskComponent.componentName, MovaLockMaskComponent()),
      ('danmakuTrack', MovaDanmakuTrackComponent.componentName, MovaDanmakuTrackComponent()),
      ('miniClose', MovaMiniCloseComponent.componentName, MovaMiniCloseComponent()),
      ('douyinGestureLayer', MovaDouyinGestureLayerComponent.componentName, MovaDouyinGestureLayerComponent(controller: f, index: 0, likeNotifier: n)),
      ('socialRail', MovaSocialRailComponent.componentName, MovaSocialRailComponent(item: item, controller: f, index: 0, likeNotifier: n)),
      ('avatar', MovaAvatarComponent.componentName, MovaAvatarComponent(item: item)),
      ('likeButton', MovaLikeButtonComponent.componentName, MovaLikeButtonComponent(controller: f, index: 0, likeNotifier: n)),
      ('commentButton', MovaCommentButtonComponent.componentName, MovaCommentButtonComponent(item: item)),
      ('shareButton', MovaShareButtonComponent.componentName, MovaShareButtonComponent(item: item)),
      ('feedInfo', MovaFeedInfoComponent.componentName, MovaFeedInfoComponent(item: item)),
    ];
    final bad = <String>[
      for (final (literal, constant, c) in rows)
        if (!(literal == constant && constant == c.name))
          '$literal: const=$constant name=${c.name}',
    ];
    gap.verdict(
      bad.isEmpty,
      'componentName const == name getter == literal for ${rows.length} components',
      {'checked': rows.length, 'mismatches': bad},
    );
    gap.log('STEP', {
      'notCovered': ['nextUp (needs MovaPlaylist)', 'adOverlay (needs MovaAds)'],
    });
  } finally {
    await fx.dispose();
  }
}

/// S1：组件树对账 + 挂载探针（点播）。 / S1: tree reconciliation plus mounted probes (VOD).
Future<void> treeCase(SkinRun r) async {
  final actual = r.skin.components().map(describe).toList();
  gap.verdict(
    listEquals(actual, _expectedTree(r.name)),
    {'skin': r.name, 'tree': _expectedTree(r.name)},
    {'tree': actual},
  );
  // 挂载探针：GradBar 数、期望图标、(default/bilibili) 标题文本。
  final grad = countKind('MovaGradBar');
  final wantGrad = r.name == 'default' || r.name == 'bilibili' ? 2 : 0;
  final missing = [
    for (final i in _expectedIcons(r.name))
      if (iconsOf(i).isEmpty) '$i',
  ];
  final title = r.name == 'default' || r.name == 'bilibili'
      ? textsOf('Gap Skin Title').length
      : -1;
  final icons = allElements().where((e) => e.widget is Icon).length;
  gap.verdict(
    grad == wantGrad &&
        missing.isEmpty &&
        (title == -1 || title >= 1) &&
        (r.name != 'minimal' || icons == 0),
    {
      'MovaGradBar': wantGrad,
      'mustMountIcons': _expectedIcons(r.name).map((i) => '$i').toList(),
      'titleTextMounted': r.name == 'default' || r.name == 'bilibili',
      'minimalIconCount': r.name == 'minimal' ? 0 : null,
    },
    {
      'MovaGradBar': grad,
      'missingIcons': missing,
      'titleTexts': title,
      'iconCount': icons,
    },
  );
}

/// S1 Minimal 的开关变体，纯树检查。 / S1 pure-tree checks for the Minimal flags.
Future<void> minimalVariants() async {
  final cases = <(MovaMinimalSkin, List<String>)>[
    (const MovaMinimalSkin(), ['buffering@center']),
    (const MovaMinimalSkin(showError: true), ['buffering@center', 'error@center']),
    (const MovaMinimalSkin(showBuffering: false), <String>[]),
    (const MovaMinimalSkin(showBuffering: false, showError: true), ['error@center']),
  ];
  for (final (skin, want) in cases) {
    final got = skin.components().map(describe).toList();
    gap.verdict(
      listEquals(got, want),
      {'showBuffering': skin.showBuffering, 'showError': skin.showError, 'tree': want},
      {'tree': got},
    );
  }
}

/// S4：单击切控制条、双击左右各 doubleTapStep 跳转（Default/Bilibili）。
/// S4: single tap toggles bars, double tap seeks ±doubleTapStep (Default/Bilibili).
Future<void> tapCase(SkinRun r) async {
  final a = r.a;
  final size = viewSize();
  final left = Offset(size.width * .25, size.height * .4);
  final right = Offset(size.width * .75, size.height * .4);
  await gap.seek(a, 30000);
  await gap.until(() async => (await gap.pos() - 30000).abs() < 800);
  var start = gap.events.length;
  final before = a.uiState.controlsVisible;
  await injectTap(left, 'single tap hides bars');
  await gap.until(() => a.uiState.controlsVisible != before);
  gap.verdict(
    before && !a.uiState.controlsVisible,
    'single tap on empty area toggles controlsVisible true->false',
    {'before': before, 'after': a.uiState.controlsVisible},
  );
  await injectTap(left, 'single tap shows bars');
  await gap.until(() => a.uiState.controlsVisible);
  gap.verdict(
    a.uiState.controlsVisible,
    'second single tap shows bars again',
    {'controlsVisible': a.uiState.controlsVisible},
  );
  final step = a.options.gesture.doubleTapStep.inMilliseconds;
  for (final backward in [true, false]) {
    start = gap.events.length;
    final from = gap.progress.position.inMilliseconds;
    await injectTap(backward ? left : right, 'double tap ${backward ? 'left' : 'right'}', count: 2);
    await gap.until(() => evCount<MovaSeek>(start) >= 1);
    final target =
        gap.events.skip(start).whereType<MovaSeek>().first.target.inMilliseconds;
    final want = from + (backward ? -step : step);
    gap.verdict(
      (target - want).abs() <= 2000,
      {'seekTargetMs': want, 'toleranceMs': 2000, 'stepMs': step},
      {'fromMs': from, 'seekTargetMs': target, 'deltaMs': target - want},
    );
    await gap.until(() async => await gap.native('seeking') == 'no');
  }
}

/// S4：Douyin 单击播放/暂停、双击点赞。 / S4: Douyin tap toggles play, double tap likes.
Future<void> douyinTapCase(SkinRun r) async {
  final a = r.a;
  final size = viewSize();
  final p = Offset(size.width * .3, size.height * .4);
  var start = gap.events.length;
  await injectTap(p, 'single tap pauses');
  await gap.until(() => !a.state.playing);
  gap.verdict(
    !a.state.playing && evCount<MovaPause>(start) >= 1,
    'single tap pauses playback (state + MovaPause)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
  start = gap.events.length;
  await injectTap(p, 'single tap resumes');
  await gap.until(() => a.state.playing);
  gap.verdict(
    a.state.playing && evCount<MovaPlay>(start) >= 1,
    'second single tap resumes playback (state + MovaPlay)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
  start = gap.events.length;
  final likes = r.fx.counts['like'] ?? 0;
  await injectTap(p, 'double tap likes', count: 2);
  await gap.until(() => (r.fx.counts['like'] ?? 0) > likes);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  gap.verdict(
    (r.fx.counts['like'] ?? 0) == likes + 1 &&
        r.fx.like!.value.liked &&
        evCount<MovaPlay>(start) + evCount<MovaPause>(start) == 0,
    'double tap likes once and does not toggle playback',
    {'likeCallbacks': r.fx.counts['like'], 'like': '${r.fx.like!.value}', 'events': evNames(start)},
  );
}

/// S7：锁定屏蔽（Default/Bilibili）+ 锁定按钮可达（S9 锁定切换）。
/// S7: lock blocks interaction (Default/Bilibili) and the toggle stays reachable (S9 lock toggle).
Future<void> lockCase(SkinRun r) async {
  final a = r.a;
  final size = viewSize();
  final empty = Offset(size.width * .25, size.height * .4);
  Offset? firstCenter(IconData d) {
    final hits = iconsOf(d);
    return hits.isEmpty ? null : centerOf(hits.first);
  }

  final fitC = firstCenter(Icons.aspect_ratio_rounded);
  final playC = firstCenter(Icons.pause_circle_filled_rounded);
  var start = gap.events.length;
  if (!await tapIcon(Icons.lock_open_rounded, 'lock toggle on')) {
    gap.verdict(false, 'lock toggle mounted', 'Icons.lock_open_rounded absent');
    return;
  }
  await gap.until(() => a.state.locked);
  await frames();
  gap.verdict(
    a.state.locked && evCount<MovaLockChange>(start) == 1,
    'lock toggle sets locked and emits one MovaLockChange(true)',
    {'locked': a.state.locked, 'events': evNames(start)},
  );
  gap.verdict(
    iconsOf(Icons.aspect_ratio_rounded).isEmpty &&
        iconsOf(Icons.pause_circle_filled_rounded).isEmpty &&
        countKind('MovaGradBar') == 0 &&
        iconsOf(Icons.lock_rounded).isNotEmpty,
    'locked: bars/center hidden, unlock toggle still mounted',
    {
      'fit': iconsOf(Icons.aspect_ratio_rounded).length,
      'center': iconsOf(Icons.pause_circle_filled_rounded).length,
      'gradBars': countKind('MovaGradBar'),
      'unlockToggle': iconsOf(Icons.lock_rounded).length,
    },
  );
  start = gap.events.length;
  final snap = (a.state.playing, a.state.fit, a.state.rate, a.state.fullscreen, a.uiState.controlsVisible);
  if (playC != null) await injectTap(playC, 'locked: tap where play/pause was');
  if (fitC != null) await injectTap(fitC, 'locked: tap where fit button was');
  await injectTap(empty, 'locked: tap empty area');
  await injectTap(empty, 'locked: double tap empty area', count: 2);
  await Future<void>.delayed(const Duration(seconds: 1));
  const guarded = {
    'MovaPlay', 'MovaPause', 'MovaFitChange', 'MovaSeek',
    'MovaRateChange', 'MovaFullScreenChange', 'MovaVolumeChange',
  };
  final leaked = evNames(start).where(guarded.contains).toList();
  gap.verdict(
    leaked.isEmpty &&
        snap == (a.state.playing, a.state.fit, a.state.rate, a.state.fullscreen, a.uiState.controlsVisible),
    'locked: taps/double taps are swallowed (no play/fit/seek/rate/fullscreen events, state unchanged)',
    {'leakedEvents': leaked, 'allEvents': evNames(start), 'state': '$snap'},
  );
  start = gap.events.length;
  await tapIcon(Icons.lock_rounded, 'lock toggle off');
  await gap.until(() => !a.state.locked);
  await frames();
  gap.verdict(
    !a.state.locked && evCount<MovaLockChange>(start) == 1,
    'unlock restores state and emits one MovaLockChange(false)',
    {'locked': a.state.locked, 'events': evNames(start)},
  );
  start = gap.events.length;
  await tapIcon(Icons.pause_circle_filled_rounded, 'after unlock: play/pause works');
  await gap.until(() => !a.state.playing);
  gap.verdict(
    !a.state.playing && evCount<MovaPause>(start) >= 1,
    'after unlock the center button works again (MovaPause)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
}

/// S7：Douyin 没有锁定入口，只记录锁定时单击是否仍切换播放（观察项，无矩阵判据）。
/// S7: Douyin has no lock UI; records whether a tap still toggles playback while locked (observation, no matrix criterion).
Future<void> douyinLockObserve(SkinRun r) async {
  final a = r.a;
  final size = viewSize();
  final p = Offset(size.width * .3, size.height * .4);
  await gap.call('setLocked', {'value': true}, () => a.setLocked(true));
  final start = gap.events.length;
  final before = a.state.playing;
  await injectTap(p, 'locked (API): single tap on Douyin surface');
  await Future<void>.delayed(const Duration(seconds: 1));
  final toggled = a.state.playing != before;
  gap.verdict(
    true,
    'OBSERVATION only (no matrix criterion): does a Douyin tap still toggle playback while locked?',
    {
      'locked': a.state.locked,
      'playingBefore': before,
      'playingAfter': a.state.playing,
      'tapStillToggles': toggled,
      'events': evNames(start),
      'note': 'douyin_skin has no lock toggle/mask; douyin_gesture_layer has no locked check',
    },
  );
  await gap.call('setLocked', {'value': false}, () => a.setLocked(false));
}

/// S9：Default/Bilibili 顶栏、中心按钮逐个点击对应的 state/事件。
/// S9: tap each Default/Bilibili top-bar / center button and check state + events.
Future<void> buttonsCase(SkinRun r) async {
  final a = r.a;
  final bilibili = r.name == 'bilibili';
  var start = gap.events.length;

  // 中心播放/暂停
  await tapIcon(Icons.pause_circle_filled_rounded, 'center pause');
  await gap.until(() => !a.state.playing);
  gap.verdict(
    !a.state.playing && evCount<MovaPause>(start) >= 1,
    'center button pauses (state.playing=false + MovaPause)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
  start = gap.events.length;
  await tapIcon(Icons.play_circle_filled_rounded, 'center play');
  await gap.until(() => a.state.playing);
  gap.verdict(
    a.state.playing && evCount<MovaPlay>(start) >= 1,
    'center button resumes (state.playing=true + MovaPlay)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );

  // 观看模式
  final fit = a.state.fit;
  start = gap.events.length;
  final fitOk = await tapIcon(Icons.aspect_ratio_rounded, 'fit button');
  if (fitOk) await gap.until(() => a.state.fit != fit);
  final fitEv = gap.events.skip(start).whereType<MovaFitChange>().toList();
  gap.verdict(
    fitOk && a.state.fit == fit.next && fitEv.length == 1 && fitEv.first.fit == fit.next,
    'fit button cycles fit.next with one MovaFitChange',
    {'mounted': fitOk, 'from': fit.name, 'to': a.state.fit.name, 'events': evNames(start)},
  );
  await gap.call('setFit', {'restore': fit.name}, () => a.setFit(fit));

  // 方向（仅移动端挂载）
  final mobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (mobile) {
    final o = a.state.orientation;
    start = gap.events.length;
    final ok = await tapIcon(Icons.screen_rotation_rounded, 'orientation button');
    if (ok) await gap.until(() => a.state.orientation != o);
    gap.verdict(
      ok && a.state.orientation == o.toggled && evCount<MovaOrientationChange>(start) == 1,
      'orientation button applies orientation.toggled with one MovaOrientationChange',
      {'mounted': ok, 'from': o.name, 'to': a.state.orientation.name, 'events': evNames(start)},
    );
    await gap.call('setOrientation', {'restore': 'auto'}, () => a.setOrientation(MovaOrientation.auto));
    await Future<void>.delayed(_settle);
    await frames();
  } else {
    gap.verdict(false, 'orientation button on mobile', '$defaultTargetPlatform',
        blocked: 'orientation button is mounted on Android/iOS only');
  }

  // 全屏
  start = gap.events.length;
  var ok = await tapIcon(Icons.fullscreen_rounded, 'fullscreen enter');
  if (ok) await gap.until(() => a.state.fullscreen);
  await Future<void>.delayed(_settle);
  await frames();
  gap.verdict(
    ok && a.state.fullscreen && evCount<MovaFullScreenChange>(start) == 1,
    'fullscreen button enters fullscreen with one MovaFullScreenChange(true)',
    {'mounted': ok, 'fullscreen': a.state.fullscreen, 'events': evNames(start)},
  );
  start = gap.events.length;
  ok = await tapIcon(Icons.fullscreen_exit_rounded, 'fullscreen exit');
  if (ok) await gap.until(() => !a.state.fullscreen);
  await Future<void>.delayed(_settle);
  await frames();
  gap.verdict(
    ok && !a.state.fullscreen && evCount<MovaFullScreenChange>(start) == 1,
    'exit icon leaves fullscreen with one MovaFullScreenChange(false)',
    {'mounted': ok, 'fullscreen': a.state.fullscreen, 'events': evNames(start)},
  );

  // 画中画：只核对挂载；点击会把应用带进系统小窗，由 gap:A15.miniPip 覆盖。
  final pipMounted = iconsOf(Icons.picture_in_picture_alt_rounded).isNotEmpty;
  gap.verdict(
    pipMounted == a.state.pipSupported,
    'pip button is mounted iff state.pipSupported',
    {'pipSupported': a.state.pipSupported, 'mounted': pipMounted},
  );
  gap.verdict(
    false,
    'pip button click enters system PiP',
    'not clicked',
    blocked: 'clicking leaves the app in a system PiP window; covered by gap:A15.miniPip',
  );

  // 字幕按钮：无 STT 引擎时不应挂载
  gap.verdict(
    iconsOf(Icons.subtitles_off_rounded).isEmpty && iconsOf(Icons.subtitles_rounded).isEmpty,
    'subtitle button is not mounted without an STT engine',
    {
      'languages': a.stt.languages,
      'subtitleIcons': iconsOf(Icons.subtitles_off_rounded).length,
    },
  );

  // 倍速：Bilibili 有，Default 没有
  if (bilibili) {
    final rate = a.state.rate;
    start = gap.events.length;
    ok = await tapIcon(Icons.speed_rounded, 'speed button');
    if (ok) await gap.until(() => a.state.rate != rate);
    gap.verdict(
      ok && a.state.rate == 1.25 && evCount<MovaRateChange>(start) == 1,
      'speed button steps 1.0 -> 1.25 with one MovaRateChange',
      {'mounted': ok, 'from': rate, 'to': a.state.rate, 'caption1.25x': textsOf('1.25x').length, 'events': evNames(start)},
    );
    await gap.call('setRate', {'restore': 1.0}, () => a.setRate(1.0));
  } else {
    gap.verdict(
      iconsOf(Icons.speed_rounded).isEmpty,
      'Default skin has no speed button (Bilibili-only patch)',
      {'speedIcons': iconsOf(Icons.speed_rounded).length},
    );
  }

  // 清晰度（放最后：会重载）
  final qs = a.state.qualities;
  final cur = a.state.currentQuality;
  final target = qs.firstWhere((q) => !q.isAuto && q.uri != cur?.uri);
  start = gap.events.length;
  ok = await tapIcon(Icons.high_quality_rounded, 'quality button');
  await frames(4);
  final listed = [for (final q in qs) if (textsOf(q.label).isEmpty) q.label];
  gap.verdict(
    ok && listed.isEmpty,
    'quality button opens a sheet listing every quality label',
    {'mounted': ok, 'labels': qs.map((q) => q.label).toList(), 'missingInSheet': listed},
  );
  final items = textsOf(target.label)
    ..sort((x, y) => (centerOf(y)?.dy ?? 0).compareTo(centerOf(x)?.dy ?? 0));
  if (items.isNotEmpty) {
    await injectTap(centerOf(items.first)!, 'quality sheet item ${target.label}');
    await gap.until(() => a.state.currentQuality?.uri == target.uri);
    await gap.until(() async => await gap.native('path') == target.uri);
  }
  final qEv = gap.events.skip(start).whereType<MovaQualityChange>().toList();
  gap.verdict(
    items.isNotEmpty &&
        a.state.currentQuality?.uri == target.uri &&
        qEv.isNotEmpty &&
        qEv.last.quality.label == target.label,
    'sheet item switches quality (state.currentQuality + MovaQualityChange)',
    {
      'target': target.label,
      'current': a.state.currentQuality?.label,
      'path': await gap.optionalNative('path'),
      'events': evNames(start),
    },
  );
}

/// S9：错误层重试按钮 → reload() 重新 open。 / S9: error-overlay retry triggers reload() and a fresh open.
Future<void> errorRetryCase(SkinRun r) async {
  final a = r.a;
  final bad = MovaSource(gap.source('missing').uri);
  try {
    await gap.call('open', {'uri': bad.uri}, () => a.open(bad));
  } catch (_) {
    // open 抛错也是合法路径，error 状态照样应出现。
  }
  try {
    await gap.until(() => a.state.error != null, seconds: 20);
  } on TimeoutException {
    throw GapBlocked('no error state produced for a 404 source; retry button never mounted');
  }
  await frames();
  final start = gap.events.length;
  final ok = await tapIcon(Icons.refresh_rounded, 'error retry');
  bool retried() =>
      evCount<MovaSourceChange>(start) + evCount<MovaErrorEvent>(start) >= 1;
  if (ok) await gap.until(retried);
  gap.verdict(
    ok && retried(),
    'retry button calls reload(): a fresh open attempt (new MovaSourceChange, or a new MovaErrorEvent if it fails again)',
    {'mounted': ok, 'events': evNames(start), 'uri': bad.uri},
  );
}

/// S9：Douyin 社交竖排 → 宿主回调与点赞状态。 / S9: Douyin rail buttons drive host callbacks and like state.
Future<void> douyinButtonsCase(SkinRun r) async {
  final fx = r.fx;
  Future<void> check(String key, IconData icon, String why) async {
    final before = fx.counts[key] ?? 0;
    final ok = await tapIcon(icon, why);
    if (ok) await gap.until(() => (fx.counts[key] ?? 0) > before, seconds: 5).catchError((_) {});
    gap.verdict(
      ok && (fx.counts[key] ?? 0) == before + 1,
      '$why invokes the host callback exactly once',
      {'mounted': ok, 'callback': key, 'before': before, 'after': fx.counts[key] ?? 0},
    );
  }

  await check('avatar', Icons.person_rounded, 'avatar');
  await check('follow', Icons.add_circle_rounded, 'follow');
  await check('comment', Icons.chat_bubble_rounded, 'comment');
  await check('share', Icons.reply_rounded, 'share');
  await check('like', Icons.favorite_border_rounded, 'like');
  gap.verdict(
    fx.like!.value.liked &&
        fx.like!.value.count == 6 &&
        iconsOf(Icons.favorite_rounded).isNotEmpty,
    'like toggles notifier (liked, 5->6) and swaps to the filled heart',
    {'like': '${fx.like!.value}', 'filledHearts': iconsOf(Icons.favorite_rounded).length},
  );
}

/// S9：Mini 中心播放与关闭按钮。 / S9: Mini centre play and close buttons.
Future<void> miniButtonsCase(SkinRun r) async {
  final a = r.a;
  var start = gap.events.length;
  await tapIcon(Icons.pause_circle_filled_rounded, 'mini center pause');
  await gap.until(() => !a.state.playing);
  gap.verdict(
    !a.state.playing && evCount<MovaPause>(start) >= 1,
    'mini center button pauses (state + MovaPause)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
  start = gap.events.length;
  await tapIcon(Icons.play_circle_filled_rounded, 'mini center play');
  await gap.until(() => a.state.playing);
  gap.verdict(
    a.state.playing && evCount<MovaPlay>(start) >= 1,
    'mini center button resumes (state + MovaPlay)',
    {'playing': a.state.playing, 'events': evNames(start)},
  );
  final closes = r.fx.counts['miniClose'] ?? 0;
  final ok = await tapIcon(Icons.close, 'mini close');
  if (ok) await gap.until(() => (r.fx.counts['miniClose'] ?? 0) > closes, seconds: 5).catchError((_) {});
  gap.verdict(
    ok && (r.fx.counts['miniClose'] ?? 0) == closes + 1,
    'close button invokes onClose exactly once',
    {'mounted': ok, 'before': closes, 'after': r.fx.counts['miniClose'] ?? 0},
  );
}

/// S2：点播布局截图，人工核对。 / S2: VOD layout screenshot for manual review.
Future<void> layoutShotCase(SkinRun r) async {
  await frames(5);
  await shot('S2-${r.name}');
  gap.verdict(
    false,
    'VOD layout visually correct',
    'screenshot captured by host',
    blocked: 'manual visual review required (layout/spacing/legibility)',
  );
}

/// S10：全屏截图，人工核对。 / S10: fullscreen screenshot for manual review.
Future<void> fullscreenShotCase(SkinRun r) async {
  final a = r.a;
  try {
    await gap.call('setFullscreen', {'value': true}, () => a.setFullscreen(true));
    await gap.until(() => a.state.fullscreen);
    await Future<void>.delayed(_settle);
    await frames(5);
    gap.verdict(
      a.state.fullscreen,
      'setFullscreen(true) lands in state',
      {'fullscreen': a.state.fullscreen, 'size': viewSize().toString()},
    );
    await shot('S10-${r.name}');
    gap.verdict(
      false,
      'fullscreen/rotation visually correct',
      'screenshot captured by host',
      blocked: 'manual visual review required (rotation, letterbox, chrome placement)',
    );
  } finally {
    await gap.call('setFullscreen', {'value': false}, () => a.setFullscreen(false));
    await Future<void>.delayed(_settle);
  }
}

/// S12：纯函数层，未匹配路径一律空操作、输入不被修改。
/// S12: pure layer: unmatched paths are no-ops and the input is not mutated.
Future<void> patchNoop() async {
  final base = const MovaDefaultSkin().components();
  final before = base.map(describe).toList();
  final probe = GapProbe('gapNoop', MovaSlot.top);
  final patches = <MovaPatch>[
    const MovaPatch.remove('nope'),
    const MovaPatch.remove('topBar/nope'),
    MovaPatch.replace('x/y', probe),
    MovaPatch.insertAfter('zzz', probe),
    MovaPatch.insertAfter('topBar/zzz', probe),
  ];
  Object? thrown;
  var after = <String>[];
  try {
    after = applyPatches(base, patches).map(describe).toList();
  } catch (e) {
    thrown = '$e';
  }
  gap.verdict(
    thrown == null && listEquals(after, before) && listEquals(base.map(describe).toList(), before),
    {'criterion': 'unmatched remove/replace/insertAfter are silent no-ops and never mutate the input', 'expected': {'tree': before}},
    {'thrown': thrown, 'afterTree': after, 'inputAfter': base.map(describe).toList()},
  );
}

/// S12：Default 四种补丁在真实树上生效（树 + 挂载 + 点击）。
/// S12: Default four patch kinds on the real tree (tree + mounted + tap).
MovaSkin defaultPatchSkin(SkinFixture fx, MovaApi a) => MovaDefaultSkin(
      patches: [
        MovaPatch.add(MovaSlot.top, GapProbe('gapAdd', MovaSlot.top, onTap: () => a.setRate(1.25))),
        MovaPatch.replace('topBar/fitButton', GapProbe('gapReplace', MovaSlot.top, onTap: () => a.setRate(1.5))),
        const MovaPatch.remove('topBar/fullscreenButton'),
        MovaPatch.insertAfter('topBar/title', GapProbe('gapInsert', MovaSlot.top, onTap: () => a.setRate(2.0))),
        const MovaPatch.remove('preview'),
      ],
    );

/// S12：Bilibili 在内置补丁之上叠加补丁（含锚定到补丁新增的节点）。
/// S12: Bilibili stacking patches over its own (including anchoring on a patch-added node).
MovaSkin bilibiliPatchSkin(SkinFixture fx, MovaApi a) => MovaBilibiliSkin(
      patches: [
        MovaPatch.insertAfter('topBar/speedButton', GapProbe('gapInsert', MovaSlot.top, onTap: () => a.setRate(2.0))),
        MovaPatch.replace('danmakuTrack', GapProbe('gapOverlay', MovaSlot.overlay, onTap: () => a.setRate(1.5))),
        const MovaPatch.remove('topBar/fullscreenButton'),
      ],
    );

/// S12：补丁皮肤的树/挂载/点击核对。 / S12: tree/mount/tap checks for a patched skin.
Future<void> patchCase(SkinRun r) async {
  final a = r.a;
  final bilibili = r.name == 'bilibili';
  final tree = r.skin.components().map(describe).toList();
  final topKids = bilibili
      ? 'title@top,pipButton@top,qualityButton@top,speedButton@top,gapInsert@top,subtitleButton@top,fitButton@top,orientationButton@top'
      : 'title@top,gapInsert@top,pipButton@top,qualityButton@top,subtitleButton@top,gapReplace@top,orientationButton@top';
  final want = bilibili
      ? [
          ..._defaultTree(bilibili: true).sublist(0, 2),
          'topBar@top[$topKids]',
          ..._defaultTree(bilibili: true).sublist(3, 10),
          'gapOverlay@overlay',
        ]
      : [
          'gestureLayer@gesture',
          _hud,
          'topBar@top[$topKids]',
          'centerPlay@center[playPause@center]',
          'subtitleOverlay@overlay',
          _bottomBar,
          'buffering@center',
          'error@center',
          'lockMask@overlay',
          'gapAdd@top',
        ];
  gap.verdict(listEquals(tree, want), {'tree': want}, {'tree': tree});

  gap.verdict(
    iconsOf(Icons.fullscreen_rounded).isEmpty &&
        iconsOf(Icons.picture_in_picture_alt_rounded).length <= 1 &&
        textsOf('GAP:gapInsert').isNotEmpty &&
        (bilibili
            ? iconsOf(Icons.speed_rounded).isNotEmpty && textsOf('GAP:gapOverlay').isNotEmpty
            : iconsOf(Icons.aspect_ratio_rounded).isEmpty &&
                textsOf('GAP:gapReplace').isNotEmpty &&
                textsOf('GAP:gapAdd').isNotEmpty),
    {'criterion': 'mounted tree matches patches (removed gone, added/replaced/inserted present)', 'expected': {'removed': 'fullscreenButton${bilibili ? '' : ', fitButton(replaced)'}'}},
    {
      'fullscreenIcons': iconsOf(Icons.fullscreen_rounded).length,
      'fitIcons': iconsOf(Icons.aspect_ratio_rounded).length,
      'speedIcons': iconsOf(Icons.speed_rounded).length,
      'probes': [
        for (final l in ['gapAdd', 'gapReplace', 'gapInsert', 'gapOverlay'])
          '$l=${textsOf('GAP:$l').length}',
      ],
    },
  );

  final probes = bilibili
      ? {'gapInsert': 2.0, 'gapOverlay': 1.5}
      : {'gapAdd': 1.25, 'gapReplace': 1.5, 'gapInsert': 2.0};
  for (final entry in probes.entries) {
    final start = gap.events.length;
    final hits = textsOf('GAP:${entry.key}');
    final c = hits.isEmpty ? null : centerOf(hits.first);
    if (c != null) await injectTap(c, 'tap probe ${entry.key}');
    if (c != null) await gap.until(() => a.state.rate == entry.value, seconds: 8).catchError((_) {});
    gap.verdict(
      c != null && a.state.rate == entry.value && evCount<MovaRateChange>(start) >= 1,
      'patched component ${entry.key} is live: tap sets rate ${entry.value}',
      {'mounted': c != null, 'rate': a.state.rate, 'events': evNames(start)},
    );
    await gap.call('setRate', {'reset': 1.0}, () => a.setRate(1.0));
  }
}

/// 在元素树里找 CircularProgressIndicator 的属性。 / Reads CircularProgressIndicator props from the tree.
Map<String, Object?>? spinnerProps() {
  for (final e in allElements()) {
    final w = e.widget;
    if (w is CircularProgressIndicator) {
      double? size;
      e.visitAncestorElements((p) {
        if (p.widget is SizedBox) {
          size = (p.widget as SizedBox).width;
          return false;
        }
        return true;
      });
      return {'color': w.color?.toARGB32(), 'strokeWidth': w.strokeWidth, 'size': size};
    }
  }
  return null;
}

/// S13：主题/文案注入（Default/Bilibili）。 / S13: theme/strings injection (Default/Bilibili).
Future<void> injectCase(SkinRun r) async {
  final a = r.a;
  final t = _probeTheme;
  Icon? icon(IconData d) => iconsOf(d).isEmpty ? null : iconsOf(d).first.widget as Icon;
  final play = icon(Icons.pause_circle_filled_rounded);
  final full = icon(Icons.fullscreen_rounded);
  final titleText = textsOf('Gap Skin Title');
  final titleStyle = titleText.isEmpty ? null : (titleText.first.widget as Text).style;
  final fitCaption = textsOf(_probeStrings.fitLabel(a.state.fit));
  final fitStyle = fitCaption.isEmpty ? null : (fitCaption.first.widget as Text).style;
  final timeLabel = allElements().where((e) {
    final w = e.widget;
    return w is Text && w.style?.fontSize == t.timeFontSize && w.style?.color == Color(t.textColor);
  });
  final bad = <String>[
    if (play?.size != t.centerIconSize) 'centerPlay size=${play?.size}',
    if (play?.color != Color(t.iconColor)) 'centerPlay color=${play?.color}',
    if (full?.color != Color(t.iconColor)) 'fullscreen color=${full?.color}',
    if (titleStyle?.fontSize != t.titleFontSize) 'title fontSize=${titleStyle?.fontSize}',
    if (titleStyle?.color != Color(t.textColor)) 'title color=${titleStyle?.color}',
    if (fitStyle?.fontSize != t.captionFontSize) 'fit caption fontSize=${fitStyle?.fontSize}',
    if (fitStyle?.color != Color(t.textColor)) 'fit caption color=${fitStyle?.color}',
    if (timeLabel.isEmpty) 'no Text with timeFontSize/textColor (position/duration label)',
  ];
  gap.verdict(
    bad.isEmpty,
    {'criterion': 'MovaTheme icon/text colours and sizes land on the skin', 'expected': {'iconColor': t.iconColor, 'textColor': t.textColor, 'centerIconSize': t.centerIconSize, 'titleFontSize': t.titleFontSize, 'captionFontSize': t.captionFontSize, 'timeFontSize': t.timeFontSize}},
    {'mismatches': bad},
  );
  final fit = a.state.fit;
  await gap.call('setFit', {'next': fit.next.name}, () => a.setFit(fit.next));
  await frames(3);
  final wantA = _probeStrings.fitLabel(fit);
  final wantB = _probeStrings.fitLabel(fit.next);
  final speed = r.name == 'bilibili' ? textsOf('1${_probeStrings.speedSuffix}').length : -1;
  gap.verdict(
    fitCaption.isNotEmpty && textsOf(wantB).isNotEmpty && (speed == -1 || speed >= 1),
    {'criterion': 'MovaStrs fit labels and speed suffix are rendered and follow state', 'expected': {'fitBefore': wantA, 'fitAfter': wantB, 'speedCaption': r.name == 'bilibili' ? '1XX' : null}},
    {'beforeFound': fitCaption.length, 'afterFound': textsOf(wantB).length, 'speedFound': speed},
  );
  await gap.call('setFit', {'restore': fit.name}, () => a.setFit(fit));
}

/// S13：Douyin 主题注入。 / S13: theme injection on Douyin.
Future<void> douyinInjectCase(SkinRun r) async {
  final t = _probeTheme;
  Icon? icon(IconData d) => iconsOf(d).isEmpty ? null : iconsOf(d).first.widget as Icon;
  final bad = <String>[
    for (final d in [Icons.favorite_border_rounded, Icons.chat_bubble_rounded, Icons.reply_rounded])
      if (icon(d)?.color != Color(t.iconColor)) '$d color=${icon(d)?.color}',
  ];
  final counts = textsOf('5');
  final countStyle = counts.isEmpty ? null : (counts.first.widget as Text).style;
  if (countStyle?.color != Color(t.textColor) || countStyle?.fontSize != t.captionFontSize) {
    bad.add('like count style=${countStyle?.color}/${countStyle?.fontSize}');
  }
  final author = textsOf('@gap-author');
  final authorStyle = author.isEmpty ? null : (author.first.widget as Text).style;
  if (authorStyle?.fontSize != t.titleFontSize || authorStyle?.color != Color(t.textColor)) {
    bad.add('author style=${authorStyle?.color}/${authorStyle?.fontSize}');
  }
  gap.verdict(
    bad.isEmpty,
    {'criterion': 'MovaTheme icon/text colours land on the social rail', 'expected': {'iconColor': t.iconColor, 'textColor': t.textColor, 'captionFontSize': t.captionFontSize}},
    {'mismatches': bad},
  );
  await tapIcon(Icons.favorite_border_rounded, 'like');
  await gap.until(() => r.fx.like!.value.liked, seconds: 5);
  await frames(3);
  gap.verdict(
    icon(Icons.favorite_rounded)?.color == Color(t.accentColor),
    {'criterion': 'liked heart uses MovaTheme.accentColor', 'expected': {'accentColor': t.accentColor}},
    {'color': icon(Icons.favorite_rounded)?.color.toString()},
  );
}

/// S13：Minimal 缓冲转圈取主题。 / S13: Minimal spinner follows the theme.
Future<void> minimalInjectCase(SkinRun r) async {
  final a = r.a;
  final t = _probeTheme;
  final src = MovaSource(gap.source('delayed/master.m3u8').uri);
  final opening = gap.call('open', {'uri': src.uri}, () => a.open(src));
  Map<String, Object?>? seen;
  final watch = Stopwatch()..start();
  while (watch.elapsed.inSeconds < 10 && seen == null) {
    seen = spinnerProps();
    if (seen == null) await Future<void>.delayed(const Duration(milliseconds: 40));
  }
  await opening;
  if (seen == null) {
    gap.verdict(
      false,
      'buffering spinner observed while opening',
      'spinner never mounted',
      blocked: 'buffering state not observed during a 2s-delayed open; theme probe precondition absent',
    );
    return;
  }
  gap.verdict(
    seen['color'] == t.bufferingColor &&
        seen['strokeWidth'] == t.bufferingStrokeWidth &&
        seen['size'] == t.bufferingSize,
    {'criterion': 'buffering spinner takes bufferingColor/StrokeWidth/Size from MovaTheme', 'expected': {'color': t.bufferingColor, 'strokeWidth': t.bufferingStrokeWidth, 'size': t.bufferingSize}},
    seen,
  );
}

/// S13：Mini 中心播放取主题；关闭按钮图标色写死白色，仅记录。
/// S13: Mini centre play follows the theme; the close icon hard-codes white (recorded only).
Future<void> miniInjectCase(SkinRun r) async {
  final t = _probeTheme;
  final play = iconsOf(Icons.pause_circle_filled_rounded);
  final w = play.isEmpty ? null : play.first.widget as Icon;
  gap.verdict(
    w != null && w.size == t.centerIconSize && w.color == Color(t.iconColor),
    {'criterion': 'Mini centre play icon takes centerIconSize/iconColor from MovaTheme', 'expected': {'size': t.centerIconSize, 'color': t.iconColor}},
    {'size': w?.size, 'color': w?.color?.toString()},
  );
  final close = iconsOf(Icons.close);
  gap.log('ACTUAL', {
    'observation': 'miniClose icon colour is not theme-driven',
    'closeIconColor': close.isEmpty ? null : (close.first.widget as Icon).color?.toString(),
    'themeIconColor': Color(t.iconColor).toString(),
  });
}

/// S14：运行中换皮肤，同一 api 不重开、位置连续、事件不重复。
/// S14: swap skins at runtime: same api, no reopen, continuous position, no duplicate events.
Future<void> swapCase(String from, String to) {
  return gap.caseOf('S14.$from.to-$to', ['S14', 'U2'], () async {
    final fxFrom = SkinFixture(from);
    final fxTo = SkinFixture(to);
    try {
      await fxFrom.init();
      await fxTo.init();
      final a = await skinEngine(_baseOptions);
      gapSkinStage.value = GapSkinStage(a, fxFrom.skin);
      await frames();
      logSkin(from, fxFrom.skin);
      await openMaster(a);
      await frames();
      final start = gap.events.length;
      final epoch = a.state.renderEpoch;
      final path = await gap.native('path');
      final playing = a.state.playing;
      final p0 = await gap.pos();
      gap.log('STEP', {'swap': '$from -> $to', 'skinTo': '${fxTo.skin.runtimeType}'});
      gapSkinStage.value = GapSkinStage(a, fxTo.skin);
      await frames(3);
      logSkin(to, fxTo.skin);
      final p1 = await gap.pos();
      await gap.until(() async => await gap.pos() > p1 + 800);
      final p2 = await gap.pos();
      const forbidden = {
        'MovaSourceChange', 'MovaSeek', 'MovaReady', 'MovaFirstFrame',
        'MovaPlay', 'MovaPause', 'MovaCutoverChange', 'MovaQualityChange',
      };
      final dup = evNames(start).where(forbidden.contains).toList();
      final wantGrad = to == 'default' || to == 'bilibili' ? 2 : 0;
      gap.verdict(
        dup.isEmpty &&
            a.state.renderEpoch == epoch &&
            await gap.native('path') == path &&
            a.state.playing == playing &&
            p1 >= p0 - 200 &&
            p1 - p0 < 3000 &&
            p2 > p1 + 800 &&
            countKind('MovaGradBar') == wantGrad,
        {
          'sameApi': true,
          'noReopenEvents': forbidden.toList()..sort(),
          'renderEpoch': epoch,
          'positionContinuous': 'p1 >= p0-200 && p1-p0 < 3000 && p2 > p1+800',
          'newSkinMounted': 'MovaGradBar=$wantGrad',
        },
        {
          'duplicateEvents': dup,
          'allEvents': evNames(start),
          'renderEpoch': a.state.renderEpoch,
          'path': await gap.native('path'),
          'playing': a.state.playing,
          'p0': p0,
          'p1': p1,
          'p2': p2,
          'gradBars': countKind('MovaGradBar'),
        },
      );
    } finally {
      gapSkinStage.value = null;
      await frames();
      await fxFrom.dispose();
      await fxTo.dispose();
    }
  });
}

/// skin 分组入口：按 args['skins']（逗号分隔）过滤。 / Group entry: filters by args['skins'] (comma-separated).
Future<void> runSkinGroup(Map<String, String> args) async {
  final wanted = (args['skins'] ?? skinNames.join(','))
      .split(',')
      .where(skinNames.contains)
      .toList();
  bool has(String s) => wanted.contains(s);
  await gap.caseOf('S0.matrixNA', ['S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S12'], matrixNa);
  await gap.caseOf('S1.componentNames', ['S1', 'U2'], componentNames);
  await gap.caseOf('S1.minimal.variants', ['S1', 'N16'], minimalVariants);
  await gap.caseOf('S12.default.noop', ['S12'], patchNoop);

  for (final s in wanted) {
    await skinCase('S1.$s.tree', ['S1', 'U2'], s, treeCase, title: 'Gap Skin Title');
  }
  for (final s in wanted.where((s) => s != 'minimal')) {
    await skinCase('S2.$s.layoutShot', ['S2'], s, layoutShotCase);
  }
  for (final s in ['default', 'bilibili'].where(has)) {
    await skinCase('S4.$s.tap', ['S4'], s, tapCase);
    await skinCase('S7.$s.lock', ['S7', 'S9', 'A13'], s, lockCase);
    await skinCase('S9.$s.buttons', ['S9', 'A10', 'A11', 'A14', 'A16', 'A17'], s, buttonsCase);
    await skinCase('S9.$s.errorRetry', ['S9', 'A19'], s, errorRetryCase, open: false);
  }
  if (has('douyin')) {
    await skinCase('S4.douyin.tap', ['S4', 'U6'], 'douyin', douyinTapCase);
    await skinCase('S7.douyin.lockObserve', ['S7', 'A13'], 'douyin', douyinLockObserve);
    await skinCase('S9.douyin.buttons', ['S9', 'U7'], 'douyin', douyinButtonsCase);
  }
  if (has('mini')) {
    await skinCase('S9.mini.buttons', ['S9'], 'mini', miniButtonsCase);
  }
  if (has('default')) {
    await skinCase('S12.default.patches', ['S12'], 'default', patchCase,
        skinOf: defaultPatchSkin, title: 'Gap Skin Title');
  }
  if (has('bilibili')) {
    await skinCase('S12.bilibili.patches', ['S12'], 'bilibili', patchCase,
        skinOf: bilibiliPatchSkin, title: 'Gap Skin Title');
  }
  const themed = MovaOpts(
    controls: MovaCtrlsConfig(autoHide: false),
    theme: _probeTheme,
    strings: _probeStrings,
  );
  for (final s in ['default', 'bilibili'].where(has)) {
    await skinCase('S13.$s.inject', ['S13', 'C10'], s, injectCase,
        options: themed, title: 'Gap Skin Title');
  }
  if (has('douyin')) {
    await skinCase('S13.douyin.inject', ['S13', 'C10'], 'douyin', douyinInjectCase, options: themed);
  }
  if (has('minimal')) {
    await skinCase('S13.minimal.inject', ['S13', 'C10', 'N16'], 'minimal', minimalInjectCase,
        options: themed, open: false);
  }
  if (has('mini')) {
    await skinCase('S13.mini.inject', ['S13', 'C10'], 'mini', miniInjectCase, options: themed);
  }
  for (var i = 0; i < skinNames.length; i++) {
    final from = skinNames[i], to = skinNames[(i + 1) % skinNames.length];
    if (has(from) && has(to)) await swapCase(from, to);
  }
  for (final s in wanted) {
    await skinCase('S10.$s.fullscreenShot', ['S10', 'A14'], s, fullscreenShotCase);
  }
}
