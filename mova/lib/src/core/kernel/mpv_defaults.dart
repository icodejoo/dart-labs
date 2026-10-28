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

/// Whether an mpv error line is a non-terminal diagnostic that must not
/// surface as a playback error. mpv itself issues a refresh seek on some
/// internal transitions (e.g. video chain re-init once the render surface
/// attaches); on a non-seekable live stream (WHEP, raw TS) it refuses with
/// these two lines and playback carries on unaffected.
/// A codec-open attempt can also fail before another decoder succeeds.
/// mpv 0.41 reports exhausted decoders separately as "Failed to initialize
/// a decoder for codec ..."; keep that terminal error, even without END_FILE.
///
/// 判断一条 mpv 错误日志是否只是非终结诊断、不应作为播放错误上报。
/// mpv 自己会在某些内部切换时（如渲染面挂上后重建视频链）发一次刷新 seek；
/// 对不可 seek 的直播流（WHEP、裸 TS）它会打这两行拒绝信息，播放不受影响。
/// 某次 codec 打开失败后仍可能换解码器成功；mpv 0.41 在所有解码器耗尽时
/// 另报 "Failed to initialize a decoder for codec ..."，保留该终结错误，
/// 因此不依赖 END_FILE 订阅也能报出真正的解码失败。
///
/// - [text]: the mpv log text / mpv 日志文本
///
/// Returns `true` when it should be dropped / 返回 `true` 表示应丢弃。
bool isBenignMpvError(String text) {
  final t = text.trim();
  return t.startsWith(_cannotSeek) || t.startsWith(_forceSeekable) || t == _codecOpenAttemptFailed;
}

/// Failure of one decoder attempt, before mpv exhausts its alternatives.
///
/// 单次解码器尝试失败，此时 mpv 尚未耗尽备选解码器。
const String _codecOpenAttemptFailed = 'Could not open codec.';

/// Prefix of mpv's refusal line. / mpv 拒绝 seek 的首行前缀。
const String _cannotSeek = 'Cannot seek in this stream';

/// Prefix of mpv's follow-up hint line. / mpv 紧随其后的提示行前缀。
const String _forceSeekable = "You can force it with '--force-seekable";

/// mpv 属性名：解复用器后向缓冲上限（字节）。
const String kDemuxerMaxBackBytes = 'demuxer-max-back-bytes';

/// mpv 属性名：是否允许在解复用缓存里 seek。
const String kDemuxerSeekableCache = 'demuxer-seekable-cache';

/// mpv 属性名：当前文件的容器/协议格式（WHEP 流打开后为 `whep`，HLS 为 `hls`）。
const String kFileFormat = 'file-format';

/// 明确只用于实时的 `file-format` 取值，命中即限制后向缓冲。
/// 只收有实测值的格式：目前只有 `whep`（rtsp/sdp/rtp 在瘦身版 libmpv 里没有对应
/// demuxer，打不开，没有实测值，故不收；`mpegts` 点播也会命中，更不能收）。
const Set<String> kRealtimeFileFormats = {'whep'};

/// 播放列表式格式：HLS 直播的 `seekable` 也是 `no`，但能在 mpv 缓存内回拉，兜底判断不碰它。
const Set<String> kPlaylistFileFormats = {'hls'};

/// mpv 属性名：当前流是否可 seek（`yes`/`no`）。
const String kSeekable = 'seekable';

/// mpv 属性名：媒体时长（秒；未知时读不到）。
const String kDuration = 'duration';

/// `seekable` 为不可 seek 时的取值。
const String kNotSeekable = 'no';

/// 兜底探测的采样间隔：track-list 刷新后等一个间隔读第一次，再等一个间隔读第二次。
const Duration kLiveProbeInterval = Duration(milliseconds: 1500);

/// 两次采样之间时长至少增长 间隔 x 该比例（秒），才认为时长在随时间增长（实时流特征）。
const double kLiveDurationGrowthRatio = 0.5;

/// 实时源的后向缓冲上限：0 表示播过的包立即丢弃，避免实时流缓冲线性增长。
const String kLiveMaxBackBytes = '0';

/// 实时源关闭缓存内 seek（无后向缓冲时本就无意义）。
const String kLiveSeekableCache = 'no';

/// 读不到原值时的后向缓冲上限兜底：mpv 默认值 150 MiB（实际优先还原限制前读到的原值）。
const String kVodMaxBackBytes = '157286400';

/// 读不到原值时的缓存内 seek 兜底：mpv 默认 `auto`（实际优先还原限制前读到的原值）。
const String kVodSeekableCache = 'auto';
