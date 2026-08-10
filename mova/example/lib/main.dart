import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

import 'spike_audio_extract.dart';
import 'spike_dual_engine.dart';
import 'spike_native_tracks.dart';
import 'spike_stt_engine.dart';

/// Example entry: init mova core, then run the demo app.
///
/// 示例入口：初始化 mova 内核，随后运行演示 app。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
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
  final MovaSource source;

  /// Player options this entry needs (live mode, timeshift builder, …).
  ///
  /// 该入口所需的播放器配置（直播模式、时移地址构造器等）。
  final MovaOpts options;

  /// Creates a demo entry.
  ///
  /// 创建一个演示入口。
  const _Demo(this.name, this.source, {this.options = const MovaOpts()});
}

/// Sample danmaku for the bilibili-skin demo entry, timed to the first
/// ~20 seconds of the shared demo mp4.
///
/// bilibili 皮肤演示入口用的示例弹幕，按共用演示 mp4 的前约 20 秒计时。
const _sampleDanmaku = [
  MovaDanmakuItem(text: '前方高能', time: Duration(seconds: 2)),
  MovaDanmakuItem(text: '哈哈哈哈', time: Duration(seconds: 4)),
  MovaDanmakuItem(text: '这也太好看了吧', time: Duration(seconds: 6)),
  MovaDanmakuItem(text: '弹幕护体', time: Duration(seconds: 8)),
  MovaDanmakuItem(text: '一键三连', time: Duration(seconds: 10)),
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
    MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '示例点播 mp4',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · HEVC',
    MovaSource(
      'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/720/Big_Buck_Bunny_720_10s_1MB.mp4',
      title: 'HEVC 硬解/软解验证',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · VP9',
    MovaSource(
      'https://test-videos.co.uk/vids/bigbuckbunny/webm/vp9/720/Big_Buck_Bunny_720_10s_1MB.webm',
      title: 'VP9 硬解验证',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · AV1',
    MovaSource(
      'https://api.elysiatools.com/public/samples/av1/earth_720p_horizontal.mp4',
      title: 'AV1 硬解/软解验证',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · 字幕(mov_text内封)',
    MovaSource(
      'http://127.0.0.1:8756/mova-subtitle-test.mp4',
      title: '字幕渲染 + avfilter 回归验证',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · AV1高码率长视频',
    MovaSource(
      'http://127.0.0.1:8756/mova-av1-highbitrate-fs.mp4',
      title: 'AV1 软解高码率/长视频压力验证',
    ),
  ),
  _Demo(
    'ffmpeg瘦身 · FLV容器',
    MovaSource(
      'http://127.0.0.1:8756/mova-flv-test.flv',
      title: 'FLV 容器/demuxer 验证',
    ),
  ),
  _Demo(
    'HLS · 多清晰度',
    MovaSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      title: 'HLS 多清晰度示例',
    ),
  ),
  _Demo(
    '自定义皮肤 · 无画中画按钮',
    MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: '自定义皮肤示例',
    ),
  ),
  _Demo(
    '直播 · DVR 可拖',
    MovaSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: MovaStreamType.live,
      title: '直播（DVR 窗口内可回看）',
    ),
    options: const MovaOpts(
      live: MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr),
    ),
  ),
  _Demo(
    '直播 · 时移换源',
    MovaSource(
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      type: MovaStreamType.live,
      title: '直播（时移：拖动即换源）',
    ),
    options: MovaOpts(
      live: MovaLiveConfig(
        seekMode: MovaLiveSeekMode.timeshift,
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
    MovaSource(
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
      title: 'bilibili 风格皮肤示例',
    ),
    options: const MovaOpts(danmaku: MovaDanmakuConfig(enabled: true, items: _sampleDanmaku)),
  ),
];

/// A skin used by the third demo entry: the default skin with the
/// picture-in-picture button patched out of the top bar.
///
/// 第三个演示入口使用的皮肤：在默认皮肤基础上，从顶栏中移除画中画按钮。
const _noPipSkin = MovaDefSkin(patches: [MovaPatch.remove('topBar/pipButton')]);

/// Index of the bilibili-skin demo entry in [_demos].
///
/// [_demos] 中 bilibili 皮肤演示入口的下标。
const _bilibiliDemoIndex = 5;

/// A page that plays a demo source with [MovaPlayer] and a source switcher.
///
/// 用 [MovaPlayer] 播放演示源并提供源切换的页面。
class PlayerPage extends StatefulWidget {
  /// Creates the player page.
  ///
  /// 创建播放页面。
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// State for [PlayerPage]; owns the [MovaEngine] lifecycle.
///
/// [PlayerPage] 的状态；持有 [MovaEngine] 的生命周期。
class _PlayerPageState extends State<PlayerPage> {
  /// The playback facade backing every demo entry.
  ///
  /// 支撑每个演示入口的播放能力面。
  late MovaEngine _engine;

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
    _engine = createMovaEngine(options: _optionsFor(_index));
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
  MovaOpts _optionsFor(int i) => _demos[i].options.copyWith(
        preview: MovaPrevConfig(
          enabled: _previewOn,
          network: MovaPrevNet.always,
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
      _engine = createMovaEngine(options: _optionsFor(_index));
    });
    await old.dispose();
    await _engine.open(_demos[_index].source);
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  /// Captures a screenshot via [MovaEngine.screenshot] and shows the result
  /// (byte count + a preview dialog, or an error snackbar) — a manual probe
  /// for the ffmpeg-slim png-encoder-path regression check.
  ///
  /// 通过 [MovaEngine.screenshot] 截图并展示结果（字节数 + 预览弹窗，或错误
  /// 提示）——手动验证 ffmpeg 瘦身后 png 编码器路径是否还能用。
  Future<void> _takeScreenshot() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await _engine.screenshot();
      if (bytes == null) {
        messenger.showSnackBar(const SnackBar(content: Text('screenshot() 返回 null')));
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('截图成功：${bytes.length} 字节')));
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(child: Image.memory(bytes)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('截图失败：$e')));
    }
  }

  /// Index into [_extSubtitles] of the format to load on the next tap of the
  /// external-subtitle demo button.
  ///
  /// 外挂字幕 demo 按钮下一次点击时要加载的格式，在 [_extSubtitles] 中的下标。
  int _extSubIndex = 0;

  /// The external subtitle formats cycled through by [_loadNextExtSubtitle]:
  /// SRT, WebVTT, then ASS — each served from the same local HTTP fixture
  /// server used by the other ffmpeg-slim demo sources.
  ///
  /// [_loadNextExtSubtitle] 依次加载的外挂字幕格式：SRT、WebVTT、ASS——都由
  /// 其他 ffmpeg 瘦身 demo 源共用的本机 HTTP 测试文件服务器提供。
  static const _extSubtitles = [
    ('SRT', 'http://127.0.0.1:8756/ext.srt'),
    ('WebVTT', 'http://127.0.0.1:8756/ext.vtt'),
    ('ASS', 'http://127.0.0.1:8756/ext.ass'),
  ];

  /// Loads the next external subtitle format in [_extSubtitles] via
  /// [MovaEngine.loadSubtitle] — a manual probe for the ffmpeg-slim
  /// ASS/SRT/WebVTT external-subtitle regression check.
  ///
  /// 通过 [MovaEngine.loadSubtitle] 加载 [_extSubtitles] 里的下一种格式——
  /// 手动验证 ffmpeg 瘦身后 ASS/SRT/WebVTT 外挂字幕这条路径还能用。
  Future<void> _loadNextExtSubtitle() async {
    final messenger = ScaffoldMessenger.of(context);
    final (label, uri) = _extSubtitles[_extSubIndex];
    _extSubIndex = (_extSubIndex + 1) % _extSubtitles.length;
    try {
      await _engine.loadSubtitle(uri);
      messenger.showSnackBar(SnackBar(content: Text('已加载外挂字幕：$label')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('加载外挂字幕失败（$label）：$e')));
    }
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
      _engine = createMovaEngine(options: _optionsFor(i));
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
        title: const Text('mova'),
        actions: [
          IconButton(
            tooltip: '抖音风 feed 演示',
            icon: const Icon(Icons.view_carousel_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DouyinFeedDemoPage()),
            ),
          ),
          IconButton(
            tooltip: '播放列表 + 下一集演示',
            icon: const Icon(Icons.playlist_play_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlaylistDemoPage()),
            ),
          ),
          IconButton(
            tooltip: '广告演示（前/中贴片 + 运行时插入）',
            icon: const Icon(Icons.ad_units_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdDemoPage()),
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
            tooltip: '音频抽取 spike',
            icon: const Icon(Icons.audiotrack_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AudioExtractSpikePage()),
            ),
          ),
          IconButton(
            tooltip: '原生 track spike（清晰度迁原生）',
            icon: const Icon(Icons.high_quality_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NativeTracksSpikePage()),
            ),
          ),
          IconButton(
            tooltip: 'STT 引擎 spike（ZipformerSttEngine 隔离验证）',
            icon: const Icon(Icons.record_voice_over_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SttEngineSpikePage()),
            ),
          ),
          IconButton(
            tooltip: 'ffmpeg瘦身 · 截图验证',
            icon: const Icon(Icons.camera_alt_rounded),
            onPressed: _takeScreenshot,
          ),
          IconButton(
            tooltip: 'ffmpeg瘦身 · 外挂字幕(依次 SRT/WebVTT/ASS)',
            icon: const Icon(Icons.subtitles_rounded),
            onPressed: _loadNextExtSubtitle,
          ),
          IconButton(
            tooltip: '画中画悬浮窗兜底演示（阶段3）',
            icon: const Icon(Icons.picture_in_picture_alt_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PipOverlayDemoPage()),
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
          child: MovaPlayer(
            api: _engine,
            skin: _index == 2
                ? _noPipSkin
                : _index == _bilibiliDemoIndex
                    ? MovaBilibiliSkin()
                    : const MovaDefSkin(),
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

/// A full-screen page demoing [MovaFeedPlayer]: vertical swipe-for-next-video,
/// douyin-style social rail, and local like state — see doc/SPEC.md's feed
/// entry for the engine-pool architecture this is built on.
///
/// 演示 [MovaFeedPlayer] 的全屏页面：纵向上滑切下一个视频、抖音风社交竖排、
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
  Future<MovaFeedItem?> _loadItem(int index) async {
    final loop = index ~/ _feedSources.length;
    final uri = _feedSources[index % _feedSources.length];
    return MovaFeedItem(
      source: MovaSource(uri),
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
          MovaFeedPlayer(engineFactory: createMovaEngine, loader: _loadItem),
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

/// Playlist items for the playlist demo: three short public mp4s treated as a
/// three-episode series, reusing the same URLs as the feed demo.
///
/// 播放列表演示的项：三个公开短 mp4 当作三集连播，复用与 feed 演示相同的 URL。
final _playlistItems = [
  for (var i = 0; i < _feedSources.length; i++)
    MovaPlistItem(
      source: MovaSource(_feedSources[i], title: '第 ${i + 1} 集'),
      subtitle: '播放列表演示 · 共 ${_feedSources.length} 集',
    ),
];

/// A page demoing sequential playlist playback: a [MovaPlistCtrl] drives
/// auto-advance between three episodes, a [NextUpComponent] fades in near each
/// item's end, and manual prev/next buttons exercise the same navigation.
///
/// 演示顺序播放列表：[MovaPlistCtrl] 在三集间驱动自动续播，
/// [NextUpComponent] 在每项临近结束时淡入，手动上一集/下一集按钮演示同一套导航。
class PlaylistDemoPage extends StatefulWidget {
  /// Creates the playlist demo page.
  ///
  /// 创建播放列表演示页面。
  const PlaylistDemoPage({super.key});

  @override
  State<PlaylistDemoPage> createState() => _PlaylistDemoPageState();
}

/// State for [PlaylistDemoPage]; owns the engine and the playlist controller.
///
/// [PlaylistDemoPage] 的状态；持有引擎与播放列表控制器。
class _PlaylistDemoPageState extends State<PlaylistDemoPage> {
  /// The playback facade backing the playlist.
  ///
  /// 支撑播放列表的播放能力面。
  late MovaEngine _engine;

  /// Drives current-index tracking and prev/next/auto-advance navigation.
  ///
  /// 驱动当前下标跟踪与上一集/下一集/自动续播导航。
  late MovaPlistCtrl _controller;

  @override
  void initState() {
    super.initState();
    _engine = createMovaEngine(
      options: MovaOpts(
        playlist: MovaPlistConfig(enabled: true, items: _playlistItems),
      ),
    );
    _controller = MovaPlistCtrl(_engine);
    // The controller never opens the first item on its own — the host kicks
    // playback off.
    //
    // 控制器不会自动打开首项——由宿主起播。
    _controller.jumpTo(0);
  }

  @override
  void dispose() {
    _controller.dispose();
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放列表 + 下一集')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MovaPlayer(
              api: _engine,
              // Patch the "next up" card into the overlay slot; it reads the
              // controller directly for the running index.
              //
              // 把"下一集"卡片补进 overlay 槽位；它直接从控制器读取运行时下标。
              skin: MovaDefSkin(
                patches: [MovaPatch.add(MovaSlot.overlay, NextUpComponent(_controller))],
              ),
            ),
          ),
          // Manual navigation, mirroring what auto-advance and the card do.
          //
          // 手动导航，与自动续播、卡片所做的一致。
          Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<int>(
              stream: _controller.indexChanges,
              builder: (context, _) {
                final item = _controller.currentItem;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _controller.hasPrevious ? _controller.previous : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                      label: const Text('上一集'),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(item?.displayTitle ?? '—'),
                    ),
                    TextButton.icon(
                      onPressed: _controller.hasNext ? _controller.next : null,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('下一集'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Content + ad schedule for the ad demo: a pre-roll and a mid-roll at 10s,
/// both skippable after 3s, built from the shared sample clips.
///
/// 广告演示的正片 + 广告排期：一个前贴片、一个 10 秒处的中插，均 3 秒后可跳过，
/// 复用共享样片构建。
final _adContent = MovaSource(_feedSources[0], title: '正片');
final _adBreaks = [
  MovaAdBreak(
    kind: MovaAdBreakKind.pre,
    source: MovaSource(_feedSources[1]),
    skippableAfter: const Duration(seconds: 3),
    clickThroughUrl: 'https://example.com/ad',
  ),
  MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: MovaSource(_feedSources[2]),
    offset: const Duration(seconds: 10),
    skippableAfter: const Duration(seconds: 3),
  ),
];

/// A page demoing pre/mid-roll ads plus runtime insertion: a [MovaAdCtrl]
/// orchestrates the content↔ad source swaps, [AdOverlayComponent] renders the
/// badge/skip/countdown, a button inserts an ad at the current position via
/// [MovaAdCtrl.playAdNow], and click-through is surfaced through
/// [MovaAdConfig.onAdEvent] (no url_launcher — the host decides what to do).
///
/// 演示前/中贴片广告与运行时插入：[MovaAdCtrl] 编排正片↔广告的源切换，
/// [AdOverlayComponent] 渲染角标/跳过/倒计时，一个按钮经
/// [MovaAdCtrl.playAdNow] 在当前位置插播广告，点击跳转经
/// [MovaAdConfig.onAdEvent] 暴露（不引 url_launcher——由宿主决定如何处理）。
class AdDemoPage extends StatefulWidget {
  /// Creates the ad demo page.
  ///
  /// 创建广告演示页面。
  const AdDemoPage({super.key});

  @override
  State<AdDemoPage> createState() => _AdDemoPageState();
}

/// State for [AdDemoPage]; owns the engine, the ad controller, and the last
/// reported ad event for display.
///
/// [AdDemoPage] 的状态；持有引擎、广告控制器，以及用于展示的最近一次广告事件。
class _AdDemoPageState extends State<AdDemoPage> {
  /// The playback facade the ads run on.
  ///
  /// 广告运行其上的播放能力面。
  late MovaEngine _engine;

  /// Orchestrates the pre/mid/post-roll and runtime-inserted ads.
  ///
  /// 编排前/中/后贴片与运行时插入的广告。
  late MovaAdCtrl _controller;

  /// The most recent ad lifecycle event, shown so the callback is visible.
  ///
  /// 最近一次广告生命周期事件，展示出来以便看到回调。
  final ValueNotifier<String> _lastEvent = ValueNotifier<String>('—');

  @override
  void initState() {
    super.initState();
    _engine = createMovaEngine(
      options: MovaOpts(
        ads: MovaAdConfig(enabled: true, breaks: _adBreaks, onAdEvent: _onAdEvent),
      ),
    );
    _controller = MovaAdCtrl(_engine);
    _controller.load(_adContent);
  }

  /// Records an ad event for display; a real host would act on a
  /// [MovaAdEventType.clicked] event's click-through URL here.
  ///
  /// 记录一次广告事件用于展示；真实宿主会在此处理 [MovaAdEventType.clicked]
  /// 事件的点击跳转地址。
  void _onAdEvent(MovaAdEvent e) {
    final url = e.type == MovaAdEventType.clicked ? e.adBreak.clickThroughUrl : null;
    _lastEvent.value = url == null ? e.type.name : '${e.type.name} → $url';
  }

  @override
  void dispose() {
    _controller.dispose();
    _engine.dispose();
    _lastEvent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('广告演示')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: MovaPlayer(
              api: _engine,
              // Patch the ad overlay into the overlay slot; it reads the
              // controller for the current ad and skip state.
              //
              // 把广告叠层补进 overlay 槽位；它从控制器读取当前广告与跳过状态。
              skin: MovaDefSkin(
                patches: [MovaPatch.add(MovaSlot.overlay, AdOverlayComponent(_controller))],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Insert an ad at the current content position on demand.
                //
                // 按需在当前正片位置插播一条广告。
                TextButton.icon(
                  onPressed: () => _controller.playAdNow(MovaAdBreak(
                    kind: MovaAdBreakKind.mid,
                    source: MovaSource(_feedSources[2]),
                    skippableAfter: const Duration(seconds: 2),
                  )),
                  icon: const Icon(Icons.ad_units_rounded),
                  label: const Text('此刻插入广告'),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _lastEvent,
                  builder: (context, value, _) => Text('广告事件：$value'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Demo page for the阶段3 in-app floating-window PiP fallback
/// (`MovaPipOverlay`, see `doc/notes/2026-07-31-ios-pip-feasibility.md` §3/§8):
/// tap the top bar's PiP button and — since desktop/this example always
/// reports `pipSupported == false` — the video shrinks into a small
/// draggable/resizable window floating over this page instead of doing
/// nothing, letting the rest of the page stay usable underneath.
///
/// 阶段3应用内悬浮窗画中画降级方案（`MovaPipOverlay`，参见
/// `doc/notes/2026-07-31-ios-pip-feasibility.md` §3/§8）演示页：点击顶部条的
/// 画中画按钮——由于桌面端/本示例始终报告 `pipSupported == false`——视频会缩成
/// 一个悬浮在本页面之上、可拖动/可缩放的小窗，而非毫无反应，页面其余部分仍可
/// 正常使用。
class PipOverlayDemoPage extends StatefulWidget {
  /// Creates the PiP-overlay demo page.
  ///
  /// 创建画中画悬浮窗演示页面。
  const PipOverlayDemoPage({super.key});

  @override
  State<PipOverlayDemoPage> createState() => _PipOverlayDemoPageState();
}

/// State for [PipOverlayDemoPage]; owns the demo engine.
///
/// [PipOverlayDemoPage] 的状态；持有演示引擎。
class _PipOverlayDemoPageState extends State<PipOverlayDemoPage> {
  /// The playback facade backing this page's player.
  ///
  /// 支撑本页面播放器的播放能力面。
  late final MovaEngine _engine = createMovaEngine()..open(MovaSource(_feedSources.first));

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('画中画悬浮窗兜底演示')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('点顶部条的画中画图标：小窗会悬浮出来，可拖动/可缩放，右上角关闭。'),
          ),
          AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: _engine)),
        ],
      ),
    );
  }
}
