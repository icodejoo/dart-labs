// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:mova/mova.dart';

/// Probe for HE V10 (Windows crash when a route covering the player is popped).
/// Pure environment-driven so one release build covers every control experiment:
///
/// - `PROBE_MODE`: `mk` (media_kit `Video` only, no mova) | `mova` (MovaView, no guard) | `movaguard` (MovaView + auto-pause)
///   | `texture` (mova engine + bare `Video`, no mova ui widgets)
/// - `PROBE_ROUTE`: `opaque` (default) | `translucent` (PageRouteBuilder, opaque:false) | `dialog` (showDialog)
///   | `offstage` (no route: toggle `Offstage` around the video) | `opacity0` (toggle `Opacity(0)`)
/// - `PROBE_THEME`: page transition of the app theme: `zoom` (default on Windows, snapshots the page) | `nosnap`
///   (`ZoomPageTransitionsBuilder(allowSnapshotting: false)`) | `fadeup` (`FadeUpwardsPageTransitionsBuilder`)
/// - `PROBE_NOOPEN=1`: create the `Video` but never open media (mode `mk` only)
/// - `PROBE_CYCLES` (default 20), `PROBE_HOLD_MS` (covered time, default 600), `PROBE_GAP_MS` (uncovered time, default 800)
/// - `PROBE_URL` (default the local live FLV), `PROBE_LOG` (log file, appended + flushed per line)
/// - `PROBE_MAINTAIN` (`1` default / `0`: `maintainState: false` on the covering route's parent is not applicable; this
///   flag instead pushes the cover with `maintainState: false`)
///
/// 针对 HE V10（弹出覆盖播放器的路由时 Windows 崩溃）的探针页。全部由环境变量驱动，同一个 release 包即可跑所有对照实验。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  final builder = switch (_env('PROBE_THEME', 'zoom')) {
    'nosnap' => const ZoomPageTransitionsBuilder(allowSnapshotting: false),
    'fadeup' => const FadeUpwardsPageTransitionsBuilder(),
    _ => const ZoomPageTransitionsBuilder(),
  };
  runApp(
    MaterialApp(
      theme: ThemeData(
        pageTransitionsTheme: PageTransitionsTheme(builders: {for (final p in TargetPlatform.values) p: builder}),
      ),
      home: const _ProbePage(),
    ),
  );
}

/// Reads a string environment variable with a default.
///
/// 读取字符串环境变量，缺省返回 [d]。
String _env(String k, String d) {
  final v = Platform.environment[k];
  return (v == null || v.isEmpty) ? d : v;
}

/// Log sink: file when `PROBE_LOG` is set, flushed synchronously so a native crash cannot lose lines.
///
/// 日志落点：设置了 `PROBE_LOG` 就同步写文件并刷盘，原生崩溃也丢不了行。
void _log(String m) {
  final line = '[PROBE] ${DateTime.now().toIso8601String().substring(11, 23)} $m';
  print(line);
  final f = _env('PROBE_LOG', '');
  if (f.isNotEmpty) File(f).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

class _ProbePage extends StatefulWidget {
  const _ProbePage();

  @override
  State<_ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<_ProbePage> {
  final String _mode = _env('PROBE_MODE', 'mova');
  final String _route = _env('PROBE_ROUTE', 'opaque');
  final int _cycles = int.parse(_env('PROBE_CYCLES', '20'));
  final int _holdMs = int.parse(_env('PROBE_HOLD_MS', '600'));
  final int _gapMs = int.parse(_env('PROBE_GAP_MS', '800'));
  final bool _maintain = _env('PROBE_MAINTAIN', '1') == '1';
  final bool _noOpen = _env('PROBE_NOOPEN', '0') == '1';

  /// Whether the video is currently hidden by the `offstage` / `opacity0` variants.
  ///
  /// `offstage` / `opacity0` 变体下视频当前是否被隐藏。
  bool _hidden = false;
  final String _url = _env('PROBE_URL', 'http://127.0.0.1:18080/live.flv?gop=50&audio=1');

  mk.Player? _player;
  mkv.VideoController? _controller;
  MovaApi? _engine;

  @override
  void initState() {
    super.initState();
    final stamped = '$_url${_url.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}';
    _log('mode=$_mode route=$_route cycles=$_cycles hold=$_holdMs gap=$_gapMs maintain=$_maintain');
    if (_mode == 'mk') {
      _player = mk.Player();
      _controller = mkv.VideoController(_player!);
      if (!_noOpen) _player!.open(mk.Media(stamped));
    } else if (_mode == 'texture') {
      _engine = createMovaEngine();
      _engine!.open(MovaSource(stamped, type: MovaStreamType.live));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  /// Drives push/pop cycles, logging before each action.
  ///
  /// 驱动 push/pop 循环，每步动作前先写日志。
  Future<void> _run() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    if (!mounted) return;
    final nav = Navigator.of(context);
    for (var i = 1; i <= _cycles; i++) {
      _log('cycle $i/$_cycles push');
      if (_route == 'offstage' || _route == 'opacity0') {
        setState(() => _hidden = true);
        await Future<void>.delayed(Duration(milliseconds: _holdMs));
        _log('cycle $i/$_cycles pop');
        setState(() => _hidden = false);
        await Future<void>.delayed(Duration(milliseconds: _gapMs));
        _log('cycle $i/$_cycles done');
        continue;
      }
      final Route<void> r = switch (_route) {
        'translucent' => PageRouteBuilder<void>(
          opaque: false,
          maintainState: _maintain,
          pageBuilder: (_, _, _) => const Center(child: Text('covering page', style: TextStyle(color: Colors.red))),
        ),
        _ => MaterialPageRoute<void>(
          maintainState: _maintain,
          builder: (_) => const Scaffold(body: Center(child: Text('covering page'))),
        ),
      };
      if (!mounted) return;
      if (_route == 'dialog') {
        unawaited(showDialog<void>(context: context, builder: (_) => const AlertDialog(title: Text('cover'))));
      } else {
        unawaited(nav.push(r));
      }
      await Future<void>.delayed(Duration(milliseconds: _holdMs));
      _log('cycle $i/$_cycles pop');
      nav.pop();
      await Future<void>.delayed(Duration(milliseconds: _gapMs));
      _log('cycle $i/$_cycles done');
    }
    _log('ALL DONE cycles=$_cycles');
    await Future<void>.delayed(const Duration(seconds: 1));
    exit(0);
  }

  @override
  void dispose() {
    _player?.dispose();
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final src = MovaSource(
      '$_url${_url.contains('?') ? '&' : '?'}t=${DateTime.now().microsecondsSinceEpoch}',
      type: MovaStreamType.live,
    );
    final Widget video;
    switch (_mode) {
      case 'mk':
        video = mkv.Video(controller: _controller!, controls: mkv.NoVideoControls);
      case 'texture':
        video = mkv.Video(controller: _engine!.renderHandle! as mkv.VideoController, controls: mkv.NoVideoControls);
      case 'movaguard':
        video = MovaView(source: _stable ??= src, skin: const MovaMinimalSkin(), autoPause: const MovaAutoPauseConfig());
      default:
        video = MovaView(source: _stable ??= src, skin: const MovaMinimalSkin());
    }
    return Scaffold(
      appBar: AppBar(title: Text('route cover probe: $_mode/$_route')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: switch (_route) {
              'offstage' => Offstage(offstage: _hidden, child: video),
              'opacity0' => Opacity(opacity: _hidden ? 0 : 1, child: video),
              _ => video,
            },
          ),
          const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  /// Source built once so rebuilds do not reopen the stream.
  ///
  /// 只构建一次的源，避免重建时重开流。
  MovaSource? _stable;
}
