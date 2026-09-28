// 真机验证探针：字幕是否贴着视频内容矩形底边，而非整个播放器容器底边。
// 不提交进仓库，跑法：
//   flutter run -t lib/main_subtitle_rect_verify.dart -d windows --release
//
// 把一个 16:9 横屏视频塞进一个人为收窄成竖屏比例的容器里（模拟"竖屏播放
// 横屏内容"场景），配一个假 STT 引擎（start() 后立刻推送一条覆盖全程的字幕），
// 用 GlobalKey 读取字幕气泡和视频画面渲染面各自的 RenderBox.localToGlobal，
// 打印精确坐标做对比——而非目测。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
// implementation_imports: 探针专用，直接复用 core 的纯函数做坐标校验。
// ignore: implementation_imports
import 'package:mova/src/ui/video_rect.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _VerifyApp());
}

/// 假 STT 引擎：start() 后立即推送一条覆盖 [0, 1 小时) 的固定字幕，不做任何
/// 真实识别，纯为触发 UI 渲染路径。
class _FakeSttEngine implements MovaSttEngine {
  final _controller = StreamController<MovaSttCue>.broadcast();

  @override
  List<String> get languages => const ['zh'];

  @override
  Stream<MovaSttCue> get cues => _controller.stream;

  @override
  Future<void> start(Duration atPosition) async {
    _controller.add(
      const MovaSttCue(
        text: '字幕对齐验证：应贴着视频内容底边',
        start: Duration.zero,
        end: Duration(hours: 1),
      ),
    );
  }

  @override
  void feed(Float32List samples, int sampleRateHz) {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _VerifyApp extends StatefulWidget {
  const _VerifyApp();

  @override
  State<_VerifyApp> createState() => _VerifyAppState();
}

class _VerifyAppState extends State<_VerifyApp> {
  late final MovaEngine _engine;
  final _playerAreaKey = GlobalKey();
  String _report = '(采样中…)';

  static const _videoUrl =
      'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';

  @override
  void initState() {
    super.initState();
    _engine = createMovaEngine(
      options: MovaOpts(stt: MovaSttConfig(enabled: true, engine: _FakeSttEngine())),
    );
    unawaited(() async {
      // open() 内部先 await beforeOpen 链再 attach() STT 服务——必须等 open()
      // 完全落地，stt.start() 才不会因为 _source 仍是 null 而被静默拒绝
      // （MovaSttService.start() 的 noSource 分支，本探针未接 onBlocked）。
      await _engine.open(const MovaSource(_videoUrl));
      await _engine.stt.start();
    }());
    // 定时采样坐标，直到拿到一次视频尺寸已知、字幕已渲染的稳定帧。
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      final ok = _sample();
      if (ok) t.cancel();
    });
  }

  /// 从根 Element 起递归查找带有指定 [key] 的 Element，返回其 RenderBox——
  /// 字幕气泡是内部私有 widget，没有暴露 GlobalKey 给外部构造，只能这样按
  /// ValueKey 反查。
  RenderBox? _findRenderBoxByKey(Key key) {
    RenderBox? found;
    void visit(Element el) {
      if (found != null) return;
      if (el.widget.key == key) {
        final ro = el.renderObject;
        if (ro is RenderBox) found = ro;
        return;
      }
      el.visitChildren(visit);
    }

    final root = WidgetsBinding.instance.rootElement;
    if (root != null) visit(root);
    return found;
  }

  bool _sample() {
    final playerBox = _playerAreaKey.currentContext?.findRenderObject() as RenderBox?;
    final subtitleBox = _findRenderBoxByKey(const ValueKey('movaSubtitleCueBubble'));
    if (playerBox == null || !playerBox.hasSize) return false;
    final state = _engine.state;
    if (state.width == 0 || state.height == 0) {
      setState(() => _report = '等待视频尺寸… state.width=${state.width} height=${state.height}');
      return false;
    }
    final containerSize = playerBox.size;
    final containerTopLeft = playerBox.localToGlobal(Offset.zero);
    final rect = computeVideoContentRect(
      container: containerSize,
      videoSize: Size(state.width.toDouble(), state.height.toDouble()),
      fit: state.fit,
    );
    final expectedVideoBottomGlobal = containerTopLeft.dy + rect.bottom;
    final expectedContainerBottomGlobal = containerTopLeft.dy + containerSize.height;

    if (subtitleBox == null || !subtitleBox.hasSize) {
      setState(() => _report =
          '视频尺寸已知：${state.width}x${state.height}，容器 $containerSize\n'
          '视频内容矩形（相对容器）：$rect\n'
          '视频内容底边（全局 Y）：${expectedVideoBottomGlobal.toStringAsFixed(1)}\n'
          '容器底边（全局 Y）：${expectedContainerBottomGlobal.toStringAsFixed(1)}\n'
          '字幕气泡尚未渲染（可能还没出字幕）……');
      return false;
    }

    final subtitleTopLeft = subtitleBox.localToGlobal(Offset.zero);
    final subtitleBottomGlobal = subtitleTopLeft.dy + subtitleBox.size.height;
    final gapToVideoBottom = expectedVideoBottomGlobal - subtitleBottomGlobal;
    final gapToContainerBottom = expectedContainerBottomGlobal - subtitleBottomGlobal;

    final report =
        '=== 精确坐标对比（RenderBox.localToGlobal） ===\n'
        '视频原始尺寸: ${state.width}x${state.height}（16:9 横屏）\n'
        '播放器容器尺寸: $containerSize（人为收窄为竖屏比例）\n'
        '视频内容矩形（相对容器）: $rect\n'
        '视频内容底边全局 Y: ${expectedVideoBottomGlobal.toStringAsFixed(1)}\n'
        '容器底边全局 Y: ${expectedContainerBottomGlobal.toStringAsFixed(1)}\n'
        '字幕气泡底边全局 Y: ${subtitleBottomGlobal.toStringAsFixed(1)}\n'
        '字幕底边 到 视频内容底边 的距离: ${gapToVideoBottom.toStringAsFixed(1)}px（应≈24px 留白）\n'
        '字幕底边 到 整个容器底边 的距离: ${gapToContainerBottom.toStringAsFixed(1)}px（修复前会是这个数，说明贴的是容器而非画面）\n';
    setState(() => _report = report);
    // 同步打印到控制台，便于在无 GUI 截图条件下也能拿到精确数字证据。
    debugPrint('MOVA_SUBTITLE_RECT_VERIFY_START');
    debugPrint(report);
    debugPrint('MOVA_SUBTITLE_RECT_VERIFY_END');
    return true;
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.grey.shade900,
        body: Column(
          children: [
            // 人为把播放器容器收窄成竖屏比例（宽 300、高 700），模拟"竖屏
            // 播放横屏内容"——16:9 视频在其中 contain 后必然上下留黑边。
            Center(
              child: Container(
                key: _playerAreaKey,
                width: 300,
                height: 700,
                color: Colors.black,
                child: MovaPlayer(api: _engine),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: Text(_report, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
