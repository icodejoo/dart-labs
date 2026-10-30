// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' show NativePlayer, Player;
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

import 'verify_auto/auto_kit.dart';

/// Zero-copy (`hwdec=mediacodec`) vs default (`mediacodec-copy`) compatibility matrix page.
/// Scenarios (select with ONLY): `codec` (sample x config matrix), `shot`, `extract`, `cutover`, `mini`,
/// `pip`, `bg`, `rate`, `quality`. Every scenario runs once per config per run. Rows are printed as
/// `HWM_ROW <scenario> k=v ...`; external probes hook on `HWM_PROBE` / `HWM_SHOT` / `HWM_PIPCHECK` / `WAIT_HOME`.
/// Sources come from `example/tool/verify_sources/range_server.py` (18090) and start_sources.py (18080).
///
/// 零拷贝与默认配置的兼容矩阵验证页。场景由 ONLY 选择；每个场景每轮对两种配置各跑一次。
/// 结果行 `HWM_ROW`；外部脚本在 `HWM_PROBE`/`HWM_SHOT`/`HWM_PIPCHECK`/`WAIT_HOME` 处采样。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(MaterialApp(
    builder: (context, child) => MovaMiniHost(ctl: _mini, child: child!),
    home: const _HwmPage(),
  ));
}

/// Codec sample server base / 编解码样本服务器基地址。
const String kCodecBase = String.fromEnvironment('CODEC_BASE', defaultValue: 'http://127.0.0.1:18090');

/// Exit when done / 跑完是否退出。
const bool kHwmAutoExit = bool.fromEnvironment('AUTOEXIT', defaultValue: true);

/// Multi-bitrate HLS master (needs internet on the device) / 多码率 HLS（设备需联网）。
const String kHls = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

/// The two configurations under comparison: label -> per-source mpv options.
///
/// 对照的两种配置：标签 -> 按源 mpv 选项。
const Map<String, Map<String, String>> kConfigs = {
  'copy': <String, String>{},
  'zero': <String, String>{'hwdec': 'mediacodec'},
};

/// Codec matrix samples: file name -> description.
///
/// 编解码矩阵样本：文件名 -> 说明。
const Map<String, String> kSamples = {
  'h264_720.mp4': 'H.264 8bit 720p',
  'h264_fs.mp4': 'H.264 8bit 360p',
  'hevc8.mp4': 'HEVC 8bit 720p',
  'hevc10.mp4': 'HEVC Main10 720p',
  'vp9.webm': 'VP9 profile0 720p',
  'vp8.webm': 'VP8 360p',
};

final MovaMini _mini = MovaMini();

/// One engine with its player/kernel kept for property reads.
///
/// 一个引擎及其 player/kernel，用于读属性。
class _Rig {
  _Rig(this.player, this.kernel, this.engine);
  final Player player;
  final MovaMpvKernel kernel;
  final MovaEngine engine;
  final List<MovaEvent> events = <MovaEvent>[];
  StreamSubscription<MovaEvent>? sub;
  Duration pos = Duration.zero;
  StreamSubscription<MovaProg>? progSub;
}

class _HwmPage extends StatefulWidget {
  const _HwmPage();

  @override
  State<_HwmPage> createState() => _HwmPageState();
}

class _HwmPageState extends State<_HwmPage> with WidgetsBindingObserver {
  final AutoLog _out = AutoLog('[HWM]');
  final Stopwatch _clock = Stopwatch()..start();
  final List<String> _lines = <String>[];
  final GlobalKey _surfaceKey = GlobalKey();
  final List<String> _lifecycle = <String>[];

  _Rig? _rig;
  bool _showSurface = true;
  MovaCutoverEngine? _cutover;
  MovaAds? _ads;
  final List<_Rig> _cutRigs = <_Rig>[];

  void _log(String msg) {
    final line = _out.line('${_clock.elapsedMilliseconds.toString().padLeft(7)}ms $msg');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  void _row(String scenario, Map<String, Object?> kv) =>
      _log('HWM_ROW $scenario ${kv.entries.map((e) => '${e.key}=${e.value}').join(' ')}');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_runAll()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle.add('${state.name}@${_clock.elapsedMilliseconds}');
    _log('LIFECYCLE ${state.name}');
  }

  String _stamp(String url) {
    final uri = Uri.parse(url);
    return uri.replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'}).toString();
  }

  MovaSource _src(String file, String cfg, {String? title}) =>
      MovaSource(_stamp('$kCodecBase/$file'), title: title ?? file, mpvOptions: kConfigs[cfg]!);

  Future<String> _prop(Player p, String name) async {
    final native = p.platform;
    if (native is! NativePlayer) return 'n/a';
    try {
      return await native.getProperty(name).timeout(const Duration(seconds: 1), onTimeout: () => 'timeout');
    } on Object {
      return 'gone';
    }
  }

  Future<_Rig> _newRig({MovaOpts options = const MovaOpts()}) async {
    await _disposeRig();
    final player = Player();
    final kernel = MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false);
    final engine = createMovaEngine(kernel: kernel, options: options);
    final rig = _Rig(player, kernel, engine);
    rig.sub = engine.events.listen((e) => rig.events.add(e));
    rig.progSub = engine.progress.listen((p) => rig.pos = p.position);
    _rig = rig;
    _showSurface = true;
    if (mounted) setState(() {});
    return rig;
  }

  Future<void> _disposeRig() async {
    final rig = _rig;
    _rig = null;
    if (mounted) setState(() {});
    if (rig == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await rig.sub?.cancel();
    await rig.progSub?.cancel();
    try {
      await rig.engine.dispose().timeout(const Duration(seconds: 6));
    } on Object catch (e) {
      _log('dispose error $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  /// Waits until [test] is true, polling 50ms; returns elapsed ms or null on timeout.
  ///
  /// 轮询等待条件成立，返回耗时毫秒，超时返回 null。
  Future<int?> _until(bool Function() test, {int timeoutMs = 15000}) async {
    final t0 = _clock.elapsedMilliseconds;
    while (_clock.elapsedMilliseconds - t0 < timeoutMs) {
      if (test()) return _clock.elapsedMilliseconds - t0;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }

  /// Opens [source] on [rig]; returns ms to the first `MovaFirstFrame` (null = never), and ms to first position > 0.
  Future<(int?, int?)> _openAndWait(_Rig rig, MovaSource source, {int timeoutMs = 15000}) async {
    final t0 = _clock.elapsedMilliseconds;
    int? tPos;
    int? tFirst;
    final sub = rig.engine.progress.listen((p) {
      if (tPos == null && p.position > Duration.zero) tPos = _clock.elapsedMilliseconds - t0;
    });
    final evSub = rig.engine.events.listen((e) {
      if (e is MovaFirstFrame && tFirst == null) tFirst = _clock.elapsedMilliseconds - t0;
    });
    try {
      await rig.engine.open(source);
    } on Object catch (e) {
      _log('open threw $e');
    }
    await _until(() => tFirst != null, timeoutMs: timeoutMs);
    await sub.cancel();
    await evSub.cancel();
    final firstFrameAt = tFirst;
    return (firstFrameAt, tPos);
  }

  /// Decodes an encoded screenshot and returns (meanLuma 0-255, colorful pixel fraction 0-1).
  ///
  /// 解码截图，返回（平均亮度，彩色像素占比）。
  Future<(double, double)> _luma(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var sum = 0.0;
    var colorful = 0;
    var n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4 * 7) {
      final r = data.getUint8(i), g = data.getUint8(i + 1), b = data.getUint8(i + 2);
      sum += 0.299 * r + 0.587 * g + 0.114 * b;
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      if (mx - mn > 60) colorful++;
      n++;
    }
    image.dispose();
    return n == 0 ? (0.0, 0.0) : (sum / n, colorful / n);
  }

  Future<String> _kernelShot(_Rig rig) async {
    try {
      final bytes = await rig.kernel.screenshot().timeout(const Duration(seconds: 6), onTimeout: () => null);
      if (bytes == null) return 'null';
      final (l, c) = await _luma(bytes);
      return 'bytes=${bytes.length} luma=${l.toStringAsFixed(1)} colorful=${c.toStringAsFixed(3)}';
    } on Object catch (e) {
      return 'error:$e';
    }
  }

  /// Physical-pixel rect of the player surface as `l,t,r,b`, plus screen size.
  ///
  /// 播放面物理像素矩形，外加屏幕尺寸。
  String _rect({bool quadrant = false}) {
    final dpr = View.of(context).devicePixelRatio;
    final size = View.of(context).physicalSize;
    if (quadrant) return '${(size.width / 2).round()},${(size.height / 2).round()},${size.width.round()},${size.height.round()} screen=${size.width.round()}x${size.height.round()}';
    final box = _surfaceKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return 'none screen=${size.width.round()}x${size.height.round()}';
    final o = box.localToGlobal(Offset.zero);
    return '${(o.dx * dpr).round()},${(o.dy * dpr).round()},${((o.dx + box.size.width) * dpr).round()},${((o.dy + box.size.height) * dpr).round()} screen=${size.width.round()}x${size.height.round()}';
  }

  Future<void> _probe(String id, {Duration wait = const Duration(seconds: 6)}) async {
    _log('HWM_PROBE $id rect=${_rect()}');
    await Future<void>.delayed(wait);
  }

  Future<void> _shotMark(String id, {bool quadrant = false}) async {
    _log('HWM_SHOT $id rect=${_rect(quadrant: quadrant)}');
    await Future<void>.delayed(const Duration(milliseconds: 2500));
  }

  String _errs(_Rig rig) {
    final errs = rig.events.whereType<MovaErrorEvent>().toList();
    return errs.isEmpty ? '0' : '${errs.length}:${errs.map((e) => e.toString().replaceAll(RegExp(r'\s+'), '_')).take(3).join('|')}';
  }

  // -------------------------------------------------------------------------------------------------

  /// Codec matrix: one sample under one config.
  Future<void> _codec(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    final (ff, firstPos) = await _openAndWait(rig, _src(file, cfg));
    final sizeEv = rig.events.whereType<MovaSizeChange>().map((e) => e.toString()).take(2).join('|');
    await Future<void>.delayed(const Duration(seconds: 2));
    final hw = await _prop(rig.player, 'hwdec-current');
    final codec = await _prop(rig.player, 'video-codec');
    final fmt = await _prop(rig.player, 'video-params/pixelformat');
    final w = await _prop(rig.player, 'video-params/w');
    final shot = await _kernelShot(rig);
    final pos0 = rig.pos;
    await _probe(id);
    final pos1 = rig.pos;
    final drops = '${await _prop(rig.player, 'frame-drop-count')}/${await _prop(rig.player, 'decoder-frame-drop-count')}';
    final done = await _until(() => rig.events.any((e) => e is MovaDone), timeoutMs: 35000);
    _row('codec', {
      'id': id,
      'hwdecOpt': kConfigs[cfg]!['hwdec'] ?? 'default',
      'hwdecCurrent': hw,
      'vcodec': codec,
      'pixfmt': fmt,
      'w': w,
      'ttffMs': ff,
      'firstPosMs': firstPos,
      'size': sizeEv.isEmpty ? 'none' : sizeEv.replaceAll(' ', '_'),
      'posAdvanced': '${pos0.inMilliseconds}->${pos1.inMilliseconds}',
      'eof': done != null,
      'lastPosMs': rig.pos.inMilliseconds,
      'duration': rig.engine.state.duration.inMilliseconds,
      'drops': drops,
      'errors': _errs(rig),
      'kernelShot': shot,
    });
  }

  /// Kernel screenshot + device screencap marker.
  Future<void> _shot(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    final (ff, _) = await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 2));
    final hw = await _prop(rig.player, 'hwdec-current');
    final shot = await _kernelShot(rig);
    await _shotMark(id);
    _row('shot', {'id': id, 'hwdecCurrent': hw, 'ttffMs': ff, 'kernelShot': shot, 'errors': _errs(rig)});
  }

  /// Frame extractor (own player, vid=auto vo=null) while a zero-copy/copy engine plays.
  Future<void> _extract(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 1));
    final p0 = rig.pos;
    final sw = Stopwatch()..start();
    final bytes = await MovaFrameExtractor().extract(_stamp('$kCodecBase/$file'), const Duration(seconds: 6), width: 320, hwdec: false).timeout(const Duration(seconds: 20), onTimeout: () => null);
    final ms = sw.elapsedMilliseconds;
    String shot = 'null';
    if (bytes != null) {
      final (l, c) = await _luma(bytes);
      shot = 'bytes=${bytes.length} luma=${l.toStringAsFixed(1)} colorful=${c.toStringAsFixed(3)}';
    }
    await Future<void>.delayed(const Duration(seconds: 1));
    _row('extract', {
      'id': id,
      'hwdecCurrent': await _prop(rig.player, 'hwdec-current'),
      'extractMs': ms,
      'frame': shot,
      'playerPos': '${p0.inMilliseconds}->${rig.pos.inMilliseconds}',
      'errors': _errs(rig),
    });
  }

  /// Cutover: ad inserted into VOD content then skipped; both sources carry the config.
  Future<void> _cutoverScn(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    await _disposeRig();
    await _disposeCutover();
    final opts = const MovaOpts(
      ads: MovaAdConfig(enabled: true),
      cutover: MovaCutoverConfig(enabled: true, trigger: MovaEagerWarm()),
    );
    final cutover = MovaCutoverEngine(engineFactory: () {
      final player = Player();
      final kernel = MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false);
      final engine = createMovaEngine(kernel: kernel, options: opts);
      final rig = _Rig(player, kernel, engine);
      rig.sub = engine.events.listen((e) => rig.events.add(e));
      _cutRigs.add(rig);
      return engine;
    });
    _cutover = cutover;
    Duration lastPos = Duration.zero;
    var trackEpoch = 0;
    Duration atTakeover = Duration.zero;
    Duration? resumePos;
    var resumeEpoch = -1;
    final progSub = cutover.progress.listen((p) {
      lastPos = p.position;
      final ep = cutover.state.renderEpoch;
      if (ep == trackEpoch) atTakeover = p.position;
      if (resumeEpoch >= 0 && ep == resumeEpoch && resumePos == null) resumePos = p.position;
    });
    _ads = MovaAds(cutover, cutover: cutover);
    if (mounted) setState(() {});
    final ads = _ads!;
    try {
      await ads.load(_src(file, cfg, title: 'content'));
      final playing = await _until(() => lastPos > Duration.zero && !cutover.state.buffering, timeoutMs: 20000);
      if (playing == null) {
        _row('cutover', {'id': id, 'result': 'content_never_played', 'errors': cutRigErrors()});
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
      final e0 = cutover.state.renderEpoch;
      await ads.playAdNow(MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: _src('h264_fs.mp4', cfg, title: 'ad'),
        skippableAfter: Duration.zero,
      ));
      final swappedToAd = await _until(() => cutover.state.renderEpoch != e0, timeoutMs: 12000);
      if (swappedToAd == null) {
        _row('cutover', {'id': id, 'result': 'ad_never_active', 'errors': cutRigErrors()});
        return;
      }
      await _until(() => lastPos > Duration.zero, timeoutMs: 8000);
      await Future<void>.delayed(const Duration(seconds: 2));
      final adIdx = await _firstAlive();
      final adHw = adIdx < 0 ? 'n/a' : await _prop(_cutRigs[adIdx].player, 'hwdec-current');
      final adShot = adIdx < 0 ? 'n/a' : await _kernelShot(_cutRigs[adIdx]);
      await _shotMark('$id-ad');
      atTakeover = lastPos;
      trackEpoch = -1;
      final epoch = cutover.state.renderEpoch;
      resumeEpoch = epoch + 1;
      final phaseAtSkip = cutover.cutoverPhase.name;
      final tSkip = _clock.elapsedMilliseconds;
      ads.skip();
      final swapped = await _until(() => cutover.state.renderEpoch != epoch, timeoutMs: 12000);
      final skipToCommit = _clock.elapsedMilliseconds - tSkip;
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      final pA = lastPos;
      final newest = _cutRigs.length - 1;
      final hw = await _prop(_cutRigs[newest].player, 'hwdec-current');
      final shot = await _kernelShot(_cutRigs[newest]);
      await _shotMark('$id-content');
      await Future<void>.delayed(const Duration(seconds: 1));
      final err = resumePos == null ? null : resumePos!.inMilliseconds - atTakeover.inMilliseconds;
      _row('cutover', {
        'id': id,
        'swappedToAd': swappedToAd,
        'swappedBack': swapped != null,
        'skipToCommitMs': skipToCommit,
        'phaseAtSkip': phaseAtSkip,
        'adHwdec': adHw,
        'adShot': adShot,
        'contentHwdec': hw,
        'contentShot': shot,
        'resumeErrMs': err,
        'posAfter': '${pA.inMilliseconds}->${lastPos.inMilliseconds}',
        'epoch': cutover.state.renderEpoch,
        'errors': cutRigErrors(),
      });
    } finally {
      await progSub.cancel();
      await _disposeCutover();
    }
  }

  String cutRigErrors() {
    final all = _cutRigs.expand((r) => r.events.whereType<MovaErrorEvent>()).toList();
    return all.isEmpty ? '0' : '${all.length}:${all.map((e) => e.toString().replaceAll(RegExp(r'\s+'), '_')).take(3).join('|')}';
  }

  Future<int> _firstAlive() async {
    for (var i = 0; i < _cutRigs.length; i++) {
      if (await _prop(_cutRigs[i].player, 'mute') != 'gone') return i;
    }
    return -1;
  }

  Future<void> _disposeCutover() async {
    final ads = _ads;
    final cutover = _cutover;
    _ads = null;
    _cutover = null;
    if (mounted) setState(() {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    ads?.dispose();
    try {
      await cutover?.dispose().timeout(const Duration(seconds: 8));
    } on Object catch (e) {
      _log('cutover dispose error $e');
    }
    for (final r in _cutRigs) {
      await r.sub?.cancel();
    }
    _cutRigs.clear();
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  /// In-page floating mini window, then persistent (cross-route) mini.
  Future<void> _miniScn(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig(options: const MovaOpts(mini: MovaMiniConfig(enabled: true)));
    await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 2));
    final hw0 = await _prop(rig.player, 'hwdec-current');
    final p0 = rig.pos;
    setState(() => _showSurface = false);
    await _mini.showInPage(context, rig.engine);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final a1 = rig.pos;
    await _shotMark('$id-inpage', quadrant: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final a2 = rig.pos;
    final hwA = await _prop(rig.player, 'hwdec-current');
    final miniA = rig.engine.state.mini;
    await _mini.hide();
    await rig.engine.setMini(false);
    setState(() => _showSurface = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final a3 = rig.pos;
    // Persistent mount across a route push.
    await _mini.show(rig.engine);
    setState(() => _showSurface = false);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final nav = Navigator.of(context);
    unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Center(child: Text('route 2'))))));
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final b1 = rig.pos;
    await _shotMark('$id-route', quadrant: true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final b2 = rig.pos;
    final hwB = await _prop(rig.player, 'hwdec-current');
    nav.pop();
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _mini.hide();
    await rig.engine.setMini(false);
    setState(() => _showSurface = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _row('mini', {
      'id': id,
      'hwdecBefore': hw0,
      'inpageHwdec': hwA,
      'miniFlag': miniA,
      'inpagePos': '${p0.inMilliseconds}->${a1.inMilliseconds}->${a2.inMilliseconds}->back:${a3.inMilliseconds}',
      'routeHwdec': hwB,
      'routePos': '${b1.inMilliseconds}->${b2.inMilliseconds}->end:${rig.pos.inMilliseconds}',
      'errors': _errs(rig),
    });
  }

  /// Enter system PiP, check events, return to the activity.
  Future<void> _pip(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 2));
    final hw0 = await _prop(rig.player, 'hwdec-current');
    final p0 = rig.pos;
    final supported = rig.engine.pipSupported;
    final entered = await rig.engine.enterPip();
    final evIn = await _until(() => rig.events.whereType<MovaPipChange>().any((e) => e.value), timeoutMs: 4000);
    _log('HWM_PIPCHECK $id');
    await Future<void>.delayed(const Duration(seconds: 4));
    final pInPip = rig.pos;
    final hwPip = await _prop(rig.player, 'hwdec-current');
    _log('WAIT_RESTORE $id');
    final evOut = await _until(() => rig.events.whereType<MovaPipChange>().any((e) => !e.value), timeoutMs: 10000);
    await Future<void>.delayed(const Duration(seconds: 2));
    final pAfter = rig.pos;
    final shot = await _kernelShot(rig);
    await _shotMark('$id-after');
    _row('pip', {
      'id': id,
      'supported': supported,
      'enterPip': entered,
      'pipChangeInMs': evIn,
      'pipChangeOutMs': evOut,
      'hwdecBefore': hw0,
      'hwdecInPip': hwPip,
      'pos': '${p0.inMilliseconds}->inPip:${pInPip.inMilliseconds}->after:${pAfter.inMilliseconds}',
      'afterShot': shot,
      'errors': _errs(rig),
    });
  }

  /// Background then foreground.
  Future<void> _bg(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 3));
    final p0 = rig.pos;
    final hw0 = await _prop(rig.player, 'hwdec-current');
    _lifecycle.clear();
    _log('WAIT_HOME $id');
    final resumed = await _until(() => _lifecycle.any((s) => s.startsWith('resumed')), timeoutMs: 25000);
    await Future<void>.delayed(const Duration(seconds: 3));
    final p1 = rig.pos;
    await Future<void>.delayed(const Duration(seconds: 2));
    final p2 = rig.pos;
    final pausedProp = await _prop(rig.player, 'pause');
    final hw1 = await _prop(rig.player, 'hwdec-current');
    final autoResumed = p2 > p1 + const Duration(milliseconds: 1200);
    await _shotMark('$id-back');
    var manual = 'n/a';
    if (!autoResumed) {
      await rig.engine.play();
      await Future<void>.delayed(const Duration(seconds: 3));
      final p3 = rig.pos;
      manual = '${p2.inMilliseconds}->${p3.inMilliseconds}';
      await _shotMark('$id-manual');
    }
    _row('bg', {
      'id': id,
      'resumedEvent': resumed != null,
      'lifecycle': _lifecycle.join('>'),
      'hwdecBefore': hw0,
      'hwdecAfter': hw1,
      'pos': '${p0.inMilliseconds}->back:${p1.inMilliseconds}->${p2.inMilliseconds}',
      'pauseProp': pausedProp,
      'autoResumed': autoResumed,
      'afterManualPlay': manual,
      'shot': await _kernelShot(rig),
      'errors': _errs(rig),
    });
  }

  /// Playback rate 0.5 / 2.0.
  Future<void> _rate(String file, String cfg, int run) async {
    final id = '$file-$cfg-$run';
    final rig = await _newRig();
    await _openAndWait(rig, _src(file, cfg));
    await Future<void>.delayed(const Duration(seconds: 2));
    final out = <String, Object?>{'id': id, 'hwdecCurrent': await _prop(rig.player, 'hwdec-current')};
    for (final r in const [0.5, 2.0, 1.0]) {
      await rig.engine.setRate(r);
      await Future<void>.delayed(const Duration(seconds: 1));
      final t1 = double.tryParse(await _prop(rig.player, 'time-pos')) ?? -1;
      final sw = Stopwatch()..start();
      await Future<void>.delayed(const Duration(seconds: 4));
      final t2 = double.tryParse(await _prop(rig.player, 'time-pos')) ?? -1;
      final wall = sw.elapsedMilliseconds / 1000;
      out['rate$r'] = 'speed=${await _prop(rig.player, 'speed')} ratio=${((t2 - t1) / wall).toStringAsFixed(2)}';
    }
    out['drops'] = '${await _prop(rig.player, 'frame-drop-count')}/${await _prop(rig.player, 'decoder-frame-drop-count')}';
    out['errors'] = _errs(rig);
    _row('rate', out);
  }

  /// HLS quality switch (needs internet on the device).
  Future<void> _quality(String file, String cfg, int run) async {
    final id = 'hls-$cfg-$run';
    final rig = await _newRig();
    final (ff, _) = await _openAndWait(rig, MovaSource(kHls, title: 'hls', mpvOptions: kConfigs[cfg]!), timeoutMs: 25000);
    await Future<void>.delayed(const Duration(seconds: 3));
    final hw0 = await _prop(rig.player, 'hwdec-current');
    await rig.engine.loadQualities();
    final qs = rig.engine.state.qualities.where((q) => !q.isAuto).toList();
    if (qs.length < 2) {
      _row('quality', {'id': id, 'ttffMs': ff, 'qualities': qs.length, 'hwdecCurrent': hw0, 'errors': _errs(rig)});
      return;
    }
    final cur = rig.engine.state.currentQuality;
    final target = qs.firstWhere((q) => q.uri != cur?.uri, orElse: () => qs.last);
    final posBefore = rig.pos;
    final sizeBefore = rig.events.whereType<MovaSizeChange>().length;
    await rig.engine.switchQuality(target);
    final moved = await _until(() => rig.pos > posBefore + const Duration(seconds: 2), timeoutMs: 20000);
    await Future<void>.delayed(const Duration(seconds: 1));
    _row('quality', {
      'id': id,
      'qualities': qs.length,
      'hwdecBefore': hw0,
      'hwdecAfter': await _prop(rig.player, 'hwdec-current'),
      'posBefore': posBefore.inMilliseconds,
      'movedPast2sMs': moved,
      'posAfter': rig.pos.inMilliseconds,
      'sizeChanges': '$sizeBefore->${rig.events.whereType<MovaSizeChange>().length}',
      'shot': await _kernelShot(rig),
      'errors': _errs(rig),
    });
  }

  Future<void> _runAll() async {
    final only = parseOnly(autoOnlyRaw()).map((e) => e.toLowerCase()).toList();
    final runs = autoRuns();
    _log('AUTORUN start runs=$runs only=${only.isEmpty ? 'all' : only.join(',')} os=${Platform.operatingSystemVersion}');
    bool want(String id) => only.isEmpty || only.contains(id);
    final cfgs = kConfigs.keys.toList();
    if (want('codec')) {
      for (final f in kSamples.keys) {
        for (var i = 1; i <= runs; i++) {
          for (final c in cfgs) {
            await _guard('codec $f $c', () => _codec(f, c, i));
          }
        }
      }
    }
    final feature = <String, Future<void> Function(String, String, int)>{
      'shot': _shot,
      'extract': _extract,
      'cutover': _cutoverScn,
      'mini': _miniScn,
      'pip': _pip,
      'bg': _bg,
      'rate': _rate,
    };
    for (final entry in feature.entries) {
      if (!want(entry.key)) continue;
      for (final f in const ['h264_720.mp4', 'hevc8.mp4']) {
        if (f == 'hevc8.mp4' && !(only.contains('${entry.key}+hevc'))) continue;
        for (var i = 1; i <= runs; i++) {
          for (final c in cfgs) {
            await _guard('${entry.key} $f $c', () => entry.value(f, c, i));
          }
        }
      }
    }
    if (want('quality')) {
      for (var i = 1; i <= runs; i++) {
        for (final c in cfgs) {
          await _guard('quality $c', () => _quality('', c, i));
        }
      }
    }
    await _disposeRig();
    await _disposeCutover();
    _log('AUTORUN DONE');
    if (kHwmAutoExit) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    }
  }

  Future<void> _guard(String name, Future<void> Function() run) async {
    _log('--- $name');
    try {
      await run().timeout(const Duration(minutes: 3));
    } catch (e, st) {
      _log('HWM_ROW error $name $e ${st.toString().split('\n').first}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final MovaApi? api = _cutover ?? _rig?.engine;
    return Scaffold(
      appBar: AppBar(title: const Text('hwdec matrix')),
      body: Column(
        children: [
          Container(
            key: _surfaceKey,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: (api != null && _showSurface) ? MovaPlayer(api: api, skin: const MovaMinimalSkin()) : const ColoredBox(color: Colors.black12),
            ),
          ),
          Expanded(child: ListView(children: [for (final l in _lines.take(40)) Text(l, style: const TextStyle(fontSize: 10))])),
        ],
      ),
    );
  }
}
