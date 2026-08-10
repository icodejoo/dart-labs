/// A selectable video quality variant.
///
/// For adaptive sources (HLS/DASH), "auto" delegates bitrate selection to the
/// engine; a concrete variant pins playback to one rendition — either a
/// native mpv track (via [trackId]) or, for non-adaptive multi-file sources,
/// a reopen-able variant [uri].
///
/// 可选择的视频清晰度档位。
///
/// 对自适应源（HLS/DASH），"自动"把码率选择交给内核；具体档位则锁定到某一路——
/// 或是一个原生 mpv 轨（经 [trackId]），或是（对非自适应的多文件源）一个可重开
/// 的变体 [uri]。
class MovaQual {
  /// Human label, e.g. "1080p" or "自动".
  ///
  /// 展示标签，如 "1080p" 或 "自动"。
  final String label;

  /// Variant playlist/file URI; empty when this quality routes through
  /// [trackId] instead, or when [isAuto].
  ///
  /// 变体播放列表/文件地址；当改走 [trackId] 或 [isAuto] 时为空。
  final String uri;

  /// The native mpv video track id this quality maps to, or `null` when
  /// there is no native track (routes through [uri] instead).
  ///
  /// 该清晰度映射到的原生 mpv 视频轨 id；无原生轨（改走 [uri]）时为 `null`。
  final String? trackId;

  /// Advertised bandwidth in bits per second, if known.
  ///
  /// 声明的带宽（bps），若已知。
  final int? bandwidth;

  /// Variant pixel width, if known.
  ///
  /// 变体像素宽，若已知。
  final int? width;

  /// Variant pixel height, if known.
  ///
  /// 变体像素高，若已知。
  final int? height;

  /// Whether this is the adaptive "auto" entry.
  ///
  /// 是否为自适应"自动"档。
  final bool isAuto;

  /// Creates a quality entry.
  ///
  /// 创建一个清晰度档位。
  const MovaQual({
    required this.label,
    this.uri = '',
    this.trackId,
    this.bandwidth,
    this.width,
    this.height,
    this.isAuto = false,
  });

  /// The adaptive "auto" entry (engine picks the bitrate).
  ///
  /// [trackId] wires it to mpv's native `VideoTrack.auto()` when this entry
  /// came from [qualitiesFromVideoTracks]; omit it for the non-adaptive
  /// reopen-URL path, where there is no native track to switch to.
  ///
  /// 自适应"自动"档（内核自动选码率）。
  ///
  /// 当该条目来自 [qualitiesFromVideoTracks] 时，[trackId] 把它接到 mpv 原生的
  /// `VideoTrack.auto()`；非自适应的重开 URL 路径无原生轨可切，省略即可。
  factory MovaQual.auto({String? trackId}) =>
      MovaQual(label: '自动', isAuto: true, trackId: trackId);

  @override
  bool operator ==(Object other) =>
      other is MovaQual &&
      other.label == label &&
      other.uri == uri &&
      other.trackId == trackId &&
      other.bandwidth == bandwidth &&
      other.width == width &&
      other.height == height &&
      other.isAuto == isAuto;

  @override
  int get hashCode => Object.hash(label, uri, trackId, bandwidth, width, height, isAuto);
}

/// A native video track reported by the kernel (e.g. an HLS/DASH variant
/// enumerated by mpv), engine-agnostic mirror of media_kit's `VideoTrack`.
///
/// 内核报告的原生视频轨（如 mpv 枚举出的 HLS/DASH 变体），是 media_kit
/// `VideoTrack` 的引擎无关镜像。
class MovaVideoTrack {
  /// The engine-native track id (e.g. mpv's `--vid`); `'auto'` is the
  /// adaptive entry.
  ///
  /// 引擎原生的轨道 id（如 mpv 的 `--vid`）；`'auto'` 为自适应档。
  final String id;

  /// Human-readable title reported by the demuxer, if any.
  ///
  /// demuxer 上报的可读标题，若有。
  final String? title;

  /// Pixel width, if known.
  ///
  /// 像素宽，若已知。
  final int? width;

  /// Pixel height, if known.
  ///
  /// 像素高，若已知。
  final int? height;

  /// Advertised bitrate in bits per second, if known.
  ///
  /// 声明的码率（bps），若已知。
  final int? bitrate;

  /// Codec name, if known.
  ///
  /// 编解码器名称，若已知。
  final String? codec;

  /// Creates a native video track descriptor.
  ///
  /// 创建一个原生视频轨描述。
  const MovaVideoTrack({
    required this.id,
    this.title,
    this.width,
    this.height,
    this.bitrate,
    this.codec,
  });

  /// Whether this is the adaptive "auto" entry.
  ///
  /// 是否为自适应"自动"档。
  bool get isAuto => id == 'auto';

  @override
  bool operator ==(Object other) => other is MovaVideoTrack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'MovaVideoTrack($id, title: $title, w: $width, h: $height, bitrate: $bitrate, codec: $codec)';
}

/// Builds a quality list (auto first, then variants sorted highest-first) from
/// native mpv video tracks. Same-height variants are deduplicated, keeping
/// the first (highest-bitrate, since callers pass tracks already
/// bitrate-sorted) entry per height. A variant with no known height falls
/// back to a bitrate-based label.
///
/// [tracks] must already exclude mpv's `id: 'no'` ("disable video output")
/// entry — that filtering is the kernel's responsibility (see [MpvKernel]).
///
/// 从原生 mpv 视频轨构建清晰度列表（"自动"在前，其余按从高到低排序）。相同
/// 高度的变体会去重，每个高度只保留第一条（因调用方已按码率排序，故为码率最高
/// 的那条）。没有已知高度的变体退化为按码率的标签。
///
/// [tracks] 必须已排除 mpv 的 `id: 'no'`（"关闭视频输出"）条目——该过滤是内核
/// （见 [MpvKernel]）的职责。
///
/// - [tracks]: native video tracks reported by the kernel / 内核上报的原生
///   视频轨
/// - returns the quality list, possibly empty when [tracks] has no non-auto
///   entry / 返回清晰度列表；[tracks] 无非自动条目时可能为空
///
/// Example / 示例:
/// ```dart
/// final qs = qualitiesFromVideoTracks(tracks);
/// ```
List<MovaQual> qualitiesFromVideoTracks(List<MovaVideoTrack> tracks) {
  final variants = tracks.where((t) => !t.isAuto).toList()
    ..sort((a, b) => (b.height ?? b.bitrate ?? 0).compareTo(a.height ?? a.bitrate ?? 0));
  final seenHeights = <int>{};
  final quals = <MovaQual>[];
  for (final t in variants) {
    if (t.height != null) {
      if (!seenHeights.add(t.height!)) continue;
    }
    quals.add(MovaQual(
      label: t.height != null
          ? '${t.height}p'
          : (t.bitrate != null ? '${(t.bitrate! / 1000).round()}kbps' : '未知'),
      trackId: t.id,
      bandwidth: t.bitrate,
      width: t.width,
      height: t.height,
    ));
  }
  if (quals.isEmpty) return [];
  return [MovaQual.auto(trackId: 'auto'), ...quals];
}
