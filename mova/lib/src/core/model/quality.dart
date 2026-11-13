/// 自动档的兼容标签；界面使用 MovaStrs.auto，下个版本计划改为中性值。
const String kMovaAutoQualityLabel = '自动';

/// 无分辨率、无码率时的兼容标签；界面使用 MovaStrs.unknownQuality。
/// 下个版本计划改为中性值，本版本保留现有宿主展示。
const String kMovaUnknownQualityLabel = '未知';

/// HLS variant tag shared by detection and attribute parsing.
///
/// 检测与属性解析共用的 HLS 档位标签。
const String _variantTag = '#EXT-X-STREAM-INF:';

/// Reused playlist line and resolution patterns.
///
/// 重复使用的播放列表分行与分辨率模式。
final RegExp _lineBreak = RegExp(r'\r?\n');
final RegExp _resolution = RegExp(r'(\d+)x(\d+)');

/// A selectable video quality variant.
///
/// For adaptive sources (HLS), "auto" delegates bitrate selection to the
/// player; a concrete variant pins playback to one rendition.
///
/// 可选择的视频清晰度档位。
///
/// 对自适应源（HLS），"自动"把码率选择交给内核；具体档位则锁定到某一路。
class MovaQuality {
  /// Human label, e.g. "1080p" or "自动".
  ///
  /// 展示标签，如 "1080p" 或 "自动"。
  final String label;

  /// Variant playlist URI; empty when [isAuto].
  ///
  /// 变体播放列表地址；[isAuto] 时为空。
  final String uri;

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
  const MovaQuality({
    required this.label,
    required this.uri,
    this.bandwidth,
    this.width,
    this.height,
    this.isAuto = false,
  });

  /// The adaptive "auto" entry (player picks the bitrate).
  ///
  /// 自适应"自动"档（内核自动选码率）。
  factory MovaQuality.auto() =>
      const MovaQuality(label: kMovaAutoQualityLabel, uri: '', isAuto: true);
}

/// Parses an HLS master playlist into a quality list (auto first, then
/// variants sorted by resolution, then bandwidth, with heightless entries last).
/// Returns an empty list if [content] is not
/// a master playlist (no `#EXT-X-STREAM-INF`).
///
/// 解析 HLS master playlist（"自动"在前，按分辨率、码率降序，无高度的档位最后）。
/// 若 [content] 不是 master（无 `#EXT-X-STREAM-INF`），返回空列表。
///
/// - [content]: raw .m3u8 text / m3u8 原文
/// - [base]: base URI to resolve relative variant paths / 用于解析相对路径的基地址
/// - returns the quality list / 返回清晰度列表
///
/// Example / 示例:
/// ```dart
/// final qs = parseHlsMasterPlaylist(text, base: Uri.parse(url));
/// ```
List<MovaQuality> parseHlsMasterPlaylist(String content, {Uri? base}) {
  final lines = content.split(_lineBreak);
  final variants = <MovaQuality>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith(_variantTag)) continue;
    // The URI is the next non-empty, non-comment line.
    // 地址是下一条非空、非注释行。
    String? uri;
    for (var j = i + 1; j < lines.length; j++) {
      final n = lines[j].trim();
      if (n.isEmpty || n.startsWith('#')) continue;
      uri = n;
      break;
    }
    if (uri == null) continue;
    final attrs = _parseAttrs(line.substring(_variantTag.length));
    final bw = int.tryParse(
      attrs['BANDWIDTH'] ?? attrs['AVERAGE-BANDWIDTH'] ?? '',
    );
    int? w, h;
    final res = attrs['RESOLUTION'];
    if (res != null) {
      final m = _resolution.firstMatch(res);
      if (m != null) {
        w = int.tryParse(m.group(1)!);
        h = int.tryParse(m.group(2)!);
      }
    }
    final resolved = base != null ? base.resolve(uri).toString() : uri;
    variants.add(
      MovaQuality(
        label: h != null
            ? '${h}p'
            : (bw != null
                  ? '${(bw / 1000).round()}kbps'
                  : kMovaUnknownQualityLabel),
        uri: resolved,
        bandwidth: bw,
        width: w,
        height: h,
      ),
    );
  }
  if (variants.isEmpty) return [];
  variants.sort((a, b) {
    if (a.height != null && b.height == null) return -1;
    if (a.height == null && b.height != null) return 1;
    final height = (b.height ?? 0).compareTo(a.height ?? 0);
    if (height != 0) return height;
    return (b.bandwidth ?? 0).compareTo(a.bandwidth ?? 0);
  });
  return [MovaQuality.auto(), ...variants];
}

/// Splits an HLS attribute list on commas not enclosed in double quotes.
///
/// 按不在双引号内的逗号切分 HLS 属性列表。
Map<String, String> _parseAttrs(String s) {
  final out = <String, String>{};
  final buf = StringBuffer();
  final parts = <String>[];
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == '"') inQuotes = !inQuotes;
    if (c == ',' && !inQuotes) {
      parts.add(buf.toString());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  if (buf.isNotEmpty) parts.add(buf.toString());
  for (final p in parts) {
    final eq = p.indexOf('=');
    if (eq <= 0) continue;
    final key = p.substring(0, eq).trim();
    final val = p.substring(eq + 1).trim().replaceAll('"', '');
    out[key] = val;
  }
  return out;
}
