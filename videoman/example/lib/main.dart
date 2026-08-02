import 'package:flutter/material.dart';
import 'package:videoman/videoman.dart';

import 'spike_dual_engine.dart';

/// Example entry: init videoman core, then run the demo app.
///
/// 示例入口：初始化 videoman 内核，随后运行演示 app。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  VmEngine.ensureInitialized();
  runApp(const MyApp());
}

/// Demo app root.
///
/// 演示 app 根组件。
class MyApp extends StatelessWidget {
  /// Creates the demo app.
  ///
  /// 创建演示 app。
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(theme: ThemeData.dark(), home: const PlayerPage());
  }
}

/// A demo source with a display name and the options it needs.
///
/// 带显示名与所需配置的演示源。
class _Demo {
  /// Label shown in the app bar.
  ///
  /// 应用栏上显示的名称。
  final String name;

  /// The media source this entry plays.
  ///
  /// 该入口播放的媒体源。
  final VmSource source;

  /// Player options this entry needs (live mode, timeshift builder, …).
  ///
  /// 该入口所需的播放器配置（直播模式、时移地址构造器等）。
  final VmOptions options;

  /// Creates a demo entry.
  ///
  /// 创建一个演示入口。
  const _Demo(this.name, this.source, {this.options = const VmOptions()});
}

/// Sample danmaku for the bilibili-skin demo entry, timed to the first
/// ~20 seconds of the shared demo mp4.
///
/// bilibili 皮肤演示入口用的示例弹幕，按共用演示 mp4 的前约 20 秒计时。
const _sampleDanmaku = [
  VmDanmakuItem(text: '前方高能', time: Duration(seconds: 2)),
  VmDanmakuItem(text: '哈哈哈哈', time: Duration(seconds: 4)),
  VmDanmakuItem(text: '这也太好看了吧', time: Duration(seconds: 6)),
  VmDanmakuItem(text: '弹幕护体', time: Duration(seconds: 8)),
  VmDanmakuItem(text: '一键三连', time: Duration(seconds: 10)),
];

/// The demo sources: VOD mp4, multi-quality HLS, a custom-skin variant, a
/// DVR-seekable live stream, a time-shift (reopen-on-seek) live stream, and a
/// bilibili-style skin with danmaku + speed button.
///
/// 演示源：点播 mp4、多清晰度 HLS、自定义皮肤变体、DVR 可拖直播、
/// 时移（拖动即换源）直播、带弹幕 + 倍速按钮的 bilibili 风格皮肤。
final _demos = [
  _Demo(
    'VOD · mp4',
    VmSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '示例点播 mp4',
    ),
  ),
  _Demo(
    'HLS · 多清晰度',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      title: 'HLS 多清晰度示例',
    ),
  ),
  _Demo(
    '自定义皮肤 · 无画中画按钮',
    VmSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '自定义皮肤示例',
    ),
  ),
  _Demo(
    '直播 · DVR 可拖',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（DVR 窗口内可回看）',
    ),
    options: const VmOptions(
      live: VmLiveConfig(seekMode: VmLiveSeekMode.dvr),
    ),
  ),
  _Demo(
    '直播 · 时移换源',
    VmSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: VmStreamType.live,
      title: '直播（时移：拖动即换源）',
    ),
    options: VmOptions(
      live: VmLiveConfig(
        seekMode: VmLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        // Demo-only: this public test stream has no timeshift endpoint, so the
        // builder just appends a query the server ignores. It exists to show
        // *where* a real deployment plugs its own URL scheme in.
        //
        // 仅用于演示：这个公开测试流没有时移接口，构造器只是拼一个服务端会忽略
        // 的查询参数。它的意义是展示真实部署应当在**哪里**接入自己的地址方案。
        urlBuilder: (uri, behind, wallClock) =>
            '$uri?begin=${wallClock.subtract(behind).millisecondsSinceEpoch}',
      ),
    ),
  ),
  _Demo(
    'bilibili 皮肤',
    VmSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: 'bilibili 风格皮肤示例',
    ),
    options: const VmOptions(danmaku: VmDanmakuConfig(enabled: true, items: _sampleDanmaku)),
  ),
];

/// A skin used by the third demo entry: the default skin with the
/// picture-in-picture button patched out of the top bar.
///
/// 第三个演示入口使用的皮肤：在默认皮肤基础上，从顶栏中移除画中画按钮。
const _noPipSkin = VmDefaultSkin(patches: [VmPatch.remove('topBar/pipButton')]);

/// Index of the bilibili-skin demo entry in [_demos].
///
/// [_demos] 中 bilibili 皮肤演示入口的下标。
const _bilibiliDemoIndex = 5;

/// A page that plays a demo source with [VmPlayer] and a source switcher.
///
/// 用 [VmPlayer] 播放演示源并提供源切换的页面。
class PlayerPage extends StatefulWidget {
  /// Creates the player page.
  ///
  /// 创建播放页面。
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// State for [PlayerPage]; owns the [VmEngine] lifecycle.
///
/// [PlayerPage] 的状态；持有 [VmEngine] 的生命周期。
class _PlayerPageState extends State<PlayerPage> {
  /// The playback facade backing every demo entry.
  ///
  /// 支撑每个演示入口的播放能力面。
  late VmEngine _engine;

  /// Index of the currently selected demo source.
  ///
  /// 当前选中的演示源下标。
  int _index = 0;

  /// Whether the scrub-preview bubble is enabled in this demo run.
  ///
  /// 本次 demo 运行中是否启用拖动预览气泡。
  bool _previewOn = true;

  @override
  void initState() {
    super.initState();
    _engine = createVmEngine(options: _optionsFor(_index));
    _engine.open(_demos[_index].source);
  }

  /// Builds the effective options for demo [i]: that demo's own `options`
  /// (live mode, timeshift builder, …) with the preview section overridden to
  /// respect [_previewOn] and relax the network policy for desktop/emulator
  /// use, where the connection type is unknown; production defaults to
  /// `wifiOnly`.
  ///
  /// 构建第 [i] 个演示的生效配置：该演示自身的 `options`（直播模式、时移地址
  /// 构造器等），并覆盖预览一节以遵循 [_previewOn]、放宽桌面/模拟器场景下
  /// 未知的网络策略；生产环境默认是 `wifiOnly`。
  ///
  /// - [i]: index into [_demos] / [_demos] 下标
  VmOptions _optionsFor(int i) => _demos[i].options.copyWith(
        preview: VmPreviewConfig(
          enabled: _previewOn,
          network: VmPreviewNetwork.always,
        ),
      );

  /// Rebuilds the engine with preview switched to [on], reopening the current
  /// demo source.
  ///
  /// 以预览开关 [on] 重建 engine，并重新打开当前演示源。
  ///
  /// - [on]: whether the preview bubble should be enabled / 是否启用预览气泡
  Future<void> _togglePreview(bool on) async {
    final old = _engine;
    setState(() {
      _previewOn = on;
      _engine = createVmEngine(options: _optionsFor(_index));
    });
    await old.dispose();
    await _engine.open(_demos[_index].source);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  /// Switches to demo source [i], rebuilding the engine because options are
  /// construction-time.
  ///
  /// 切换到第 [i] 个演示源；因为配置是构造期参数，需要重建 engine。
  ///
  /// - [i]: index into the demo list / 演示列表下标
  Future<void> _switch(int i) async {
    final old = _engine;
    setState(() {
      _index = i;
      _engine = createVmEngine(options: _optionsFor(i));
    });
    await old.dispose();
    await _engine.open(_demos[i].source);
    await _engine.loadQualities();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('videoman'),
        actions: [
          IconButton(
            tooltip: '抖音风 feed 演示',
            icon: const Icon(Icons.view_carousel_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DouyinFeedDemoPage()),
            ),
          ),
          IconButton(
            tooltip: '双引擎内存 spike',
            icon: const Icon(Icons.memory_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DualEngineMemorySpikePage()),
            ),
          ),
          IconButton(
            tooltip: _previewOn ? '关闭预览' : '开启预览',
            icon: Icon(_previewOn ? Icons.image : Icons.image_not_supported),
            onPressed: () => _togglePreview(!_previewOn),
          ),
          // The demo count keeps growing (6 as of the bilibili entry) and a
          // plain Row silently clips the tail entries off-screen on anything
          // narrower than a very wide monitor — `bilibili 皮肤` was
          // unreachable by mouse before this. Scroll just this segment
          // instead of the whole actions row, so the feed/preview icons stay
          // put.
          //
          // demo 数量一直在涨（加上 bilibili 这条已到 6 个），普通 Row 在
          // 不够宽的显示器上会把尾部条目静默裁掉——加上 `bilibili 皮肤` 之前
          // 鼠标根本点不到它。只让这一段可横向滚动，而非整个 actions 行，
          // feed/预览图标保持固定位置。
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _demos.length; i++)
                    TextButton(
                      onPressed: i == _index ? null : () => _switch(i),
                      child: Text(
                        _demos[i].name,
                        style: TextStyle(color: i == _index ? Colors.grey : Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Center(
        // Deliberately NOT the demo videos' own ~16:9 aspect ratio: when the
        // box matches the content exactly, contain/cover/fill render
        // identically and the fit-mode button appears to do nothing. 4:3
        // guarantees visible letterboxing/cropping/stretching between modes.
        //
        // 故意不用演示视频自身的 ~16:9 宽高比：容器与内容完全一致时，
        // contain/cover/fill 渲染结果相同，观感上"填充模式"按钮像是没反应。
        // 4:3 能保证三种模式之间出现可见的黑边/裁切/拉伸差异。
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: VmPlayer(
            api: _engine,
            skin: _index == 2
                ? _noPipSkin
                : _index == _bilibiliDemoIndex
                    ? VmBilibiliSkin()
                    : const VmDefaultSkin(),
          ),
        ),
      ),
    );
  }
}

/// Sample feed items for the douyin-style demo: three short public mp4s,
/// looped with per-loop-varying like/comment/share counts so repeated swipes
/// visibly show different numbers rather than the exact same three forever.
///
/// 抖音风演示的示例 feed 条目：三个公开短 mp4 循环播放，点赞/评论/分享数按圈数
/// 变化，使反复上滑时数字可见地在变，而非永远是完全相同的三条。
final _feedSources = [
  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
  'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/friday.mp4',
];

/// A full-screen page demoing [VmFeedPlayer]: vertical swipe-for-next-video,
/// douyin-style social rail, and local like state — see doc/SPEC.md's feed
/// entry for the engine-pool architecture this is built on.
///
/// 演示 [VmFeedPlayer] 的全屏页面：纵向上滑切下一个视频、抖音风社交竖排、
/// 本地点赞状态——其所基于的引擎池架构见 doc/SPEC.md 的 feed 条目。
class DouyinFeedDemoPage extends StatefulWidget {
  /// Creates the douyin-feed demo page.
  ///
  /// 创建抖音 feed 演示页面。
  const DouyinFeedDemoPage({super.key});

  @override
  State<DouyinFeedDemoPage> createState() => _DouyinFeedDemoPageState();
}

/// State for [DouyinFeedDemoPage]. Note it owns no engine of its own — the
/// feed's pool creates and disposes every engine, the host only supplies the
/// factory.
///
/// [DouyinFeedDemoPage] 的状态。注意它自身不持有任何引擎——所有引擎都由 feed
/// 的引擎池创建与释放，宿主只负责提供工厂。
class _DouyinFeedDemoPageState extends State<DouyinFeedDemoPage> {
  /// Resolves feed item [index], looping over [_feedSources] forever — a
  /// real app would page through a backend feed API instead and return
  /// `null` once exhausted.
  ///
  /// 解析 feed 第 [index] 条，在 [_feedSources] 上无限循环——真实 app 应改为
  /// 分页请求后端 feed 接口，取完后返回 `null`。
  ///
  /// - [index]: the feed index to resolve / 要解析的 feed 索引
  Future<VmFeedItem?> _loadItem(int index) async {
    final loop = index ~/ _feedSources.length;
    final uri = _feedSources[index % _feedSources.length];
    return VmFeedItem(
      source: VmSource(uri),
      authorName: 'demo_user_$index',
      musicName: '原创音频 · demo',
      initialLikeCount: 100 + loop * 37 + index,
      commentCount: 10 + index,
      shareCount: 3 + index,
      onLikeChanged: (liked, count) => debugPrint('feed[$index] liked=$liked count=$count'),
      onComment: () => debugPrint('feed[$index] comment tapped'),
      onShare: () => debugPrint('feed[$index] share tapped'),
      onAvatarTap: () => debugPrint('feed[$index] avatar tapped'),
      onFollowTap: () => debugPrint('feed[$index] follow tapped'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          VmFeedPlayer(engineFactory: createVmEngine, loader: _loadItem),
          SafeArea(
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
