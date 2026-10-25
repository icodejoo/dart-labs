// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// WHEP 端到端真机验证（带 WHEP 的 libmpv：ffmpeg whep demuxer + mbedtls DTLS-SRTP）。
///
/// 手机没有和电脑同网段的 Wi-Fi（只有移动数据），而 `adb reverse` 只转发 TCP，所以媒体面的 UDP
/// 由本页内置的"UDP-over-TCP 中继"搬运：手机回环 UDP 38189 <-> TCP 38190（adb reverse）<-> 电脑
/// relay.py <-> MediaMTX UDP 38189。信令走 `adb reverse tcp:38889`。流量内容是真实的 ICE/DTLS/SRTP 报文，
/// 只是 UDP 这一跳被换成了 TCP 隧道（局限：没覆盖真实 UDP 网络的丢包/抖动）。
/// 输出一律走 print，logcat 里 tag=flutter，行首 WHEP。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(MaterialApp(
    home: Scaffold(
      body: ValueListenableBuilder<MovaEngine?>(
        valueListenable: _engineNotifier,
        builder: (_, e, __) => e == null ? const Center(child: Text('whep verify')) : MovaPlayer(api: e),
      ),
    ),
  ));
  Future<void>.delayed(const Duration(seconds: 2), _run);
}

/// 当前被挂到界面上的引擎。
final ValueNotifier<MovaEngine?> _engineNotifier = ValueNotifier<MovaEngine?>(null);

/// MediaMTX 的 UDP 端口（也是手机回环上中继监听的端口）。
const int kUdpPort = int.fromEnvironment('WHEP_UDP', defaultValue: 38189);

/// 电脑 relay.py 的 TCP 端口（经 adb reverse）。
const int kRelayTcpPort = int.fromEnvironment('WHEP_RELAY', defaultValue: 38190);

/// 信令地址。
const String kWhepUrl = String.fromEnvironment('WHEP_URL', defaultValue: 'whep+http://127.0.0.1:38889/test/whep');

/// 是否启用 UDP-over-TCP 中继；真实局域网 UDP 验证时传 `--dart-define=WHEP_RELAY_ON=false`。
const bool kRelayOn = bool.fromEnvironment('WHEP_RELAY_ON', defaultValue: true);

/// 观察总时长（首帧之后）。
const int kObserveSec = 40;

/// 运行时覆盖信令地址的文件（`adb push`），存在且非空时优先于编译期 `WHEP_URL`。
const String kUrlOverrideFile = '/data/local/tmp/whep_url.txt';

/// 取实际信令地址。
String _resolveUrl() {
  try {
    final f = File(kUrlOverrideFile);
    if (f.existsSync()) {
      final t = f.readAsStringSync().trim();
      if (t.isNotEmpty) return t;
    }
  } on Object catch (_) {}
  return kWhepUrl;
}

/// 观察结束后的收尾等待秒数（留给 screencap）。
const int kTailSec = int.fromEnvironment('WHEP_TAIL', defaultValue: 25);

/// 输出一行。
void _out(String m) => print('WHEP $m');

/// 中继计数。
int _up = 0, _down = 0;

/// 启动 UDP<->TCP 中继。
Future<void> _startRelay() async {
  final udp = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, kUdpPort);
  final tcp = await Socket.connect(InternetAddress.loopbackIPv4, kRelayTcpPort);
  tcp.setOption(SocketOption.tcpNoDelay, true);
  InternetAddress? peerAddr;
  int peerPort = 0;
  udp.listen((ev) {
    if (ev != RawSocketEvent.read) return;
    final d = udp.receive();
    if (d == null) return;
    peerAddr = d.address;
    peerPort = d.port;
    final b = BytesBuilder()
      ..add([d.data.length >> 8, d.data.length & 0xff])
      ..add(d.data);
    tcp.add(b.toBytes());
    _up++;
  });
  final buf = BytesBuilder();
  tcp.listen((chunk) {
    buf.add(chunk);
    var all = buf.takeBytes();
    var off = 0;
    while (all.length - off >= 2) {
      final l = (all[off] << 8) | all[off + 1];
      if (all.length - off - 2 < l) break;
      final pkt = Uint8List.sublistView(all, off + 2, off + 2 + l);
      if (peerAddr != null) udp.send(pkt, peerAddr!, peerPort);
      _down++;
      off += 2 + l;
    }
    if (off < all.length) buf.add(Uint8List.sublistView(all, off));
  }, onDone: () => _out('relay tcp closed'));
  _out('relay up udp=127.0.0.1:$kUdpPort tcp=$kRelayTcpPort');
}

/// 读 mpv 属性，失败返回 '?'。
Future<String> _prop(Player p, String name) async {
  try {
    final n = p.platform as NativePlayer;
    final v = await n.getProperty(name);
    return v.isEmpty ? '(empty)' : v;
  } on Object catch (e) {
    return '!$e';
  }
}

/// 主流程。
Future<void> _run() async {
  if (kRelayOn) await _startRelay();
  final player = Player(
    configuration: const PlayerConfiguration(
      logLevel: MPVLogLevel.v,
      // media_kit 默认白名单不含 dtls，WHEP 的 DTLS 握手会被拦（实测 Protocol 'dtls' not on whitelist）
      protocolWhitelist: ['udp', 'rtp', 'tcp', 'tls', 'data', 'file', 'http', 'https', 'crypto', 'dtls'],
    ),
  );
  final mpvLogPath = '${Directory.systemTemp.path}/mpv_whep.log';
  try {
    File(mpvLogPath).deleteSync();
  } on Object catch (_) {}
  try {
    // 关闭 demuxer 时 mpv 事件流可能已断，改用 log-file 落盘再读回
    await (player.platform as NativePlayer).setProperty('log-file', mpvLogPath);
  } on Object catch (e) {
    _out('log-file set failed $e');
  }
  final keep = RegExp(r'whep|RTCP|RTP|dtls|ice|stun|ffmpeg/demuxer|srtp|fingerprint|mbedtls|tls|error|fatal|fail|hwdec|mediacodec|demux|probe|Opening|Stream #|Video:|Audio:', caseSensitive: false);
  player.stream.log.listen((l) {
    final t = '${l.level}/${l.prefix}: ${l.text.trim()}';
    if (l.level == 'error' || l.level == 'fatal' || keep.hasMatch(t)) _out('MPVLOG $t');
  });
  final kernel = MovaMpvKernel(player: player, lazyVideo: true, observeQoeSignals: false);
  final engine = createMovaEngine(kernel: kernel);
  _engineNotifier.value = engine;
  final sw = Stopwatch()..start();
  int? sizeMs;
  String size = '';
  int firstPosMs = -1;
  int lastPos = 0;
  engine.events.listen((e) {
    if (e is MovaReady) _out('MovaReady @${sw.elapsedMilliseconds}ms');
    if (e is MovaSizeChange) {
      _out('MovaSizeChange ${e.width}x${e.height} @${sw.elapsedMilliseconds}ms');
      if (e.width > 0 && e.height > 0 && sizeMs == null) {
        sizeMs = sw.elapsedMilliseconds;
        size = '${e.width}x${e.height}';
      }
    }
    if (e is MovaErrorEvent) _out('ERROREVENT $e @${sw.elapsedMilliseconds}ms');
  });
  engine.progress.listen((p) {
    lastPos = p.position.inMilliseconds;
    if (firstPosMs < 0 && lastPos > 0) {
      firstPosMs = sw.elapsedMilliseconds;
      _out('first position>0 ($lastPos ms) @$firstPosMs ms');
    }
  });
  final url = _resolveUrl();
  _out('open $url');
  try {
    await engine.open(MovaSource(url));
  } on Object catch (e) {
    _out('open threw $e');
  }
  for (var i = 0; i < 300 && sizeMs == null && firstPosMs < 0; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  _out('FIRSTFRAME sizeMs=$sizeMs firstPosMs=$firstPosMs size=$size');
  final t0 = sw.elapsedMilliseconds;
  final p0 = lastPos;
  for (var s = 5; s <= kObserveSec; s += 5) {
    await Future<void>.delayed(const Duration(seconds: 5));
    _out('t+${s}s pos=$lastPos paused=${await _prop(player, 'core-idle')} size=${"${engine.state.width}x${engine.state.height}"} '
        'hwdec=${await _prop(player, 'hwdec-current')} vcodec=${await _prop(player, 'video-codec')} '
        'acodec=${await _prop(player, 'audio-codec-name')} fps=${await _prop(player, 'estimated-vf-fps')} '
        'drop=${await _prop(player, 'frame-drop-count')}/${await _prop(player, 'decoder-frame-drop-count')} '
        'relayUp=$_up relayDown=$_down');
  }
  final dt = sw.elapsedMilliseconds - t0;
  _out('SUMMARY observed=${dt}ms posDelta=${lastPos - p0}ms size=${"${engine.state.width}x${engine.state.height}"} relayUp=$_up relayDown=$_down');
  await Future<void>.delayed(const Duration(seconds: kTailSec)); // 留时间给 screencap
  await player.stop(); // 关闭 demuxer 才会打印 RTP/RTCP 汇总
  await Future<void>.delayed(const Duration(seconds: 3));
  try {
    for (final l in File(mpvLogPath).readAsLinesSync()) {
      if (RegExp(r'RTCP |RTP (video|audio)|STUN:|First (RTP|video)|nack|pli', caseSensitive: false).hasMatch(l)) {
        _out('FILELOG $l');
      }
    }
  } on Object catch (e) {
    _out('read log-file failed $e');
  }
  _out('DONE');
}
