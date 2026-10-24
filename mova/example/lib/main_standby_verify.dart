// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/platform_impl/mpv_event_backend_ffi.dart';

/// 低功耗待机（standby）的真机验证页（计划 doc/plans/2026-10-23-standby-mode.md 的 Task 10 用）。
///
/// 一个页面只验这一件事：直播被隐藏时保持流连接、不出画面不出声，再显示时只恢复视频解码。
/// 所有日志以固定前缀 `[STANDBY]` 加"页面启动起算的毫秒数"打印，方便
/// `adb logcat | grep STANDBY`。
///
/// 跑法（三个源按需替换，不传的源按钮置灰；地址每次打开都会自动追加 `?t=<微秒时间戳>` 防缓存）：
/// `flutter run --release -t lib/main_standby_verify.dart \
///    --dart-define=FLV_AUDIO=http://host/a.flv \
///    --dart-define=FLV_SILENT=http://host/silent.flv \
///    --dart-define=HLS=http://host/live.m3u8`
///
/// 用法：
/// - 「隐藏」开关用 `TickerMode(enabled: false)` 包住播放器，模拟切 Tab；
/// - 「待机/唤醒」按钮走命令式入口 `MovaStandbyController.setStandby`；
/// - 下方开关切换 `hiddenMode`（守卫自动处理）与 `MovaStandbyConfig` 各项，改动会让 `MovaView` 重建引擎；
/// - 每秒一行 `position` 与 `cache-speed`（`MovaStatsProbe.sample().inputBps`），用来看待机期间网络是否持续。
///
/// 本页只在 `flutter analyze` 层面验证过，没有上机；测量方法与判据见计划 Task 10。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const MaterialApp(home: _StandbyPage()));
}

/// 有声 FLV 直播源（编译期传入）。
const String _kFlvAudio = String.fromEnvironment('FLV_AUDIO');

/// 无声 FLV 直播源（编译期传入）。
const String _kFlvSilent = String.fromEnvironment('FLV_SILENT');

/// HLS 直播源（编译期传入）。
const String _kHls = String.fromEnvironment('HLS');

/// 日志固定前缀，便于 logcat 过滤。
const String _kTag = '[STANDBY]';

/// 待机验证页。
class _StandbyPage extends StatefulWidget {
  const _StandbyPage();

  @override
  State<_StandbyPage> createState() => _StandbyPageState();
}

class _StandbyPageState extends State<_StandbyPage> {
  /// 页面启动的时刻，日志里的毫秒数从这里起算。
  final Stopwatch _clock = Stopwatch()..start();

  /// 页面上展示的最近日志。
  final List<String> _lines = <String>[];

  /// 当前要播的源。
  MovaSource? _source;

  /// 是否把播放器藏起来（`TickerMode(enabled: false)`）。
  bool _hidden = false;

  /// 守卫的隐藏处理方式。
  MovaHiddenMode _hiddenMode = MovaHiddenMode.standby;

  /// 待机调参：HLS/DASH 是否也待机。
  bool _allowHls = false;

  /// 待机调参：无声流是否改为暂停。
  bool _silentPause = false;

  /// 待机最长时长（秒）。
  int _maxSeconds = 30;

  /// 当前引擎与它所用的内核（取统计用）。
  MovaApi? _api;
  MovaMpvKernel? _kernel;

  /// 当前引擎事件订阅与进度订阅。
  StreamSubscription<MovaEvent>? _eventSub;
  StreamSubscription<MovaProg>? _progSub;

  /// 最近一次进度位置。
  Duration _position = Duration.zero;

  /// 每秒采样计时器。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_sample()));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(_eventSub?.cancel());
    unawaited(_progSub?.cancel());
    super.dispose();
  }

  /// 打一行带毫秒时间戳的日志（同时进页面和 stdout）。
  void _log(String msg) {
    final line = '${_clock.elapsedMilliseconds.toString().padLeft(7)}ms $msg';
    print('$_kTag $line');
    if (mounted) setState(() => _lines.insert(0, line));
  }

  /// 每秒一行：位置、待机阶段、网络速度。
  Future<void> _sample() async {
    final api = _api;
    if (api == null) return;
    final snap = await _kernel?.sample();
    _log('tick pos=${_position.inMilliseconds}ms phase=${api.state.standby.name} inputBps=${snap?.inputBps}');
  }

  /// 追加防缓存时间戳。
  String _stamp(String url) {
    final uri = Uri.parse(url);
    return uri
        .replace(queryParameters: {...uri.queryParameters, 't': '${DateTime.now().microsecondsSinceEpoch}'})
        .toString();
  }

  /// 打开 [url]（直播）。
  void _open(String url, String label) {
    setState(() => _source = MovaSource(_stamp(url), type: MovaStreamType.live));
    _log('open $label');
  }

  /// 构造引擎：自己建内核，才能拿到 `MovaStatsProbe`；引擎创建后订阅关心的事件。
  MovaApi _makeEngine(MovaOpts options) {
    final kernel = MovaMpvKernel(
      lazyVideo: true,
      observeQoeSignals: true,
      observeNativeEvents: true,
      backendFactory: (native, addr) => createFfiMpvEventBackend(native, addr, pollInDebug: kDebugMode),
    );
    _kernel = kernel;
    return createMovaEngine(kernel: kernel, options: options, preciseFirstFrame: true);
  }

  /// 引擎创建后接事件。
  void _onEngine(MovaApi api) {
    _api = api;
    unawaited(_eventSub?.cancel());
    unawaited(_progSub?.cancel());
    _progSub = api.progress.listen((p) => _position = p.position);
    _eventSub = api.events.listen((e) {
      switch (e) {
        case MovaStandbyChange():
          _log('StandbyChange phase=${e.phase.name} reason=${e.reason.name} mode=${e.mode?.name}');
        case MovaStandbyResume():
          _log('StandbyResume elapsed=${e.elapsed.inMilliseconds}ms signal=${e.signal?.name} from=${e.from?.name}');
        case MovaFirstFrame():
          _log('FirstFrame sinceOpen=${e.sinceOpen.inMilliseconds}ms signal=${e.signal.name}');
        case MovaSizeChange():
          _log('SizeChange ${e.width}x${e.height}');
        case MovaBufferChange():
          _log('BufferChange ${e.buffering}');
        case MovaPlay():
          _log('Play');
        case MovaPause():
          _log('Pause');
        case MovaPlayFailure():
          _log('PlayFailure kind=${e.fail.kind.name} action=${e.action.name}');
        case MovaLiveEdgeReach():
          _log('LiveEdgeReach');
        default:
          break;
      }
    });
  }

  /// 命令式待机/唤醒。
  Future<void> _command(bool on) async {
    final api = _api;
    if (api is! MovaStandbyController) {
      _log('engine has no standby capability');
      return;
    }
    final phase = await (api as MovaStandbyController).setStandby(on);
    _log('setStandby($on) -> ${phase.name}');
  }

  @override
  Widget build(BuildContext context) {
    final options = MovaOpts(
      recovery: const MovaRecoveryConfig(enabled: true),
      standby: MovaStandbyConfig(
        maxDuration: Duration(seconds: _maxSeconds),
        allowHls: _allowHls,
        silentStreams: _silentPause ? MovaSilentStandby.pause : MovaSilentStandby.keepDecoding,
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('standby verify')),
      body: ListView(
        children: [
          TickerMode(
            enabled: !_hidden,
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: MovaView(
                source: _source,
                fit: MovaFit.cover,
                poster: const ColoredBox(color: Color(0xFF223344), child: Center(child: Text('POSTER'))),
                skin: const MovaMinimalSkin(),
                options: options,
                autoPause: MovaAutoPauseConfig(hiddenMode: _hiddenMode),
                engineFactory: _makeEngine,
                onEngine: _onEngine,
                onOpenError: (e, s) => _log('openError $e'),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              ElevatedButton(
                onPressed: _kFlvAudio.isEmpty ? null : () => _open(_kFlvAudio, 'flv-audio'),
                child: const Text('FLV 有声'),
              ),
              ElevatedButton(
                onPressed: _kFlvSilent.isEmpty ? null : () => _open(_kFlvSilent, 'flv-silent'),
                child: const Text('FLV 无声'),
              ),
              ElevatedButton(
                onPressed: _kHls.isEmpty ? null : () => _open(_kHls, 'hls'),
                child: const Text('HLS'),
              ),
              ElevatedButton(onPressed: () => unawaited(_command(true)), child: const Text('setStandby(true)')),
              ElevatedButton(onPressed: () => unawaited(_command(false)), child: const Text('setStandby(false)')),
            ],
          ),
          SwitchListTile(
            title: const Text('隐藏播放器（TickerMode 关）'),
            value: _hidden,
            onChanged: (v) {
              setState(() => _hidden = v);
              _log('hidden=$v');
            },
          ),
          SwitchListTile(
            title: const Text('hiddenMode = standby（关则为 pause）'),
            value: _hiddenMode == MovaHiddenMode.standby,
            onChanged: (v) => setState(() => _hiddenMode = v ? MovaHiddenMode.standby : MovaHiddenMode.pause),
          ),
          SwitchListTile(
            title: const Text('allowHls'),
            value: _allowHls,
            onChanged: (v) => setState(() => _allowHls = v),
          ),
          SwitchListTile(
            title: const Text('无声流改为暂停（silentStreams: pause）'),
            value: _silentPause,
            onChanged: (v) => setState(() => _silentPause = v),
          ),
          ListTile(
            title: Text('maxDuration = ${_maxSeconds}s'),
            trailing: Wrap(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () => setState(() => _maxSeconds = (_maxSeconds - 10).clamp(10, 300)),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => setState(() => _maxSeconds = (_maxSeconds + 10).clamp(10, 300)),
                ),
              ],
            ),
          ),
          for (final l in _lines.take(60)) Text(l, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}
