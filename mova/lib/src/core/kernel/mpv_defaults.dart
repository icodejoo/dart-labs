/// The protocol whitelist media_kit 1.2.6 ships as its default
/// (`PlayerConfiguration.protocolWhitelist`), copied verbatim. Re-check on
/// every media_kit upgrade.
///
/// media_kit 1.2.6 默认的协议白名单（`PlayerConfiguration.protocolWhitelist`），
/// 原样复制。升级 media_kit 时须重新核对。
const List<String> kMediaKitDefaultProtocols = [
  'udp',
  'rtp',
  'tcp',
  'tls',
  'data',
  'file',
  'http',
  'https',
  'crypto',
];

/// Extra protocol WHEP needs on top of the media_kit default. The default
/// libmpv has no `dtls` protocol compiled in, so whitelisting it is harmless
/// there; it only lets builds that do carry it (WHEP-enabled libmpv) work.
///
/// 在 media_kit 默认白名单之上，WHEP 额外需要的协议。默认 libmpv 并未编入
/// `dtls`，放行它不会有副作用；它只是让带 `dtls` 的构建（含 WHEP 的 libmpv）能用。
const String kDtlsProtocol = 'dtls';

/// Protocol whitelist mova uses when it creates the default `Player` itself:
/// media_kit's default plus [kDtlsProtocol]. A caller-injected `Player` is
/// never touched.
///
/// 返回 mova 自建默认 `Player` 时使用的协议白名单：media_kit 默认项再加
/// [kDtlsProtocol]。调用方自行注入的 `Player` 不受影响。
///
/// Example / 示例:
/// ```dart
/// Player(configuration: PlayerConfiguration(protocolWhitelist: movaProtocolWhitelist()));
/// ```
List<String> movaProtocolWhitelist() => const [...kMediaKitDefaultProtocols, kDtlsProtocol];

/// Whether an mpv error line is a harmless "can't seek" notice that must not
/// surface as a playback error. mpv itself issues a refresh seek on some
/// internal transitions (e.g. video chain re-init once the render surface
/// attaches); on a non-seekable live stream (WHEP, raw TS) it refuses with
/// these two lines and playback carries on unaffected.
///
/// 判断一条 mpv 错误日志是否只是无害的"无法 seek"提示、不应作为播放错误上报。
/// mpv 自己会在某些内部切换时（如渲染面挂上后重建视频链）发一次刷新 seek；
/// 对不可 seek 的直播流（WHEP、裸 TS）它会打这两行拒绝信息，播放不受影响。
///
/// - [text]: the mpv log text / mpv 日志文本
///
/// Returns `true` when it should be dropped / 返回 `true` 表示应丢弃。
bool isBenignMpvError(String text) {
  final t = text.trim();
  return t.startsWith(_cannotSeek) || t.startsWith(_forceSeekable);
}

/// Prefix of mpv's refusal line. / mpv 拒绝 seek 的首行前缀。
const String _cannotSeek = 'Cannot seek in this stream';

/// Prefix of mpv's follow-up hint line. / mpv 紧随其后的提示行前缀。
const String _forceSeekable = "You can force it with '--force-seekable";
