import 'models.dart';

/// Matches a WebVTT timing line such as `00:00:10.000 --> 00:00:20.000`,
/// tolerating the `MM:SS.mmm` short form and trailing cue settings.
///
/// 匹配 WebVTT 时间轴行，如 `00:00:10.000 --> 00:00:20.000`；兼容 `MM:SS.mmm`
/// 短格式与行尾的 cue 设置。
final RegExp _kTimingLine = RegExp(
  r'^\s*(\d{1,3}:)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})\s*-->\s*'
  r'(\d{1,3}:)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})',
);

/// Matches an `xywh=x,y,w,h` media fragment (the leading `#` already removed).
///
/// 匹配 `xywh=x,y,w,h` 媒体片段（前导 `#` 已被去掉）。
final RegExp _kXywh = RegExp(r'^xywh=(-?\d+),(-?\d+),(-?\d+),(-?\d+)$');

/// Converts one side of a timing line's captured groups into a [Duration].
///
/// 把时间轴行一侧捕获到的分组转换为 [Duration]。
///
/// - [hours]: the `HH:` group including its colon, or null / 含冒号的 `HH:`
///   分组，可为 null
/// - [minutes]: the minutes group / 分钟分组
/// - [seconds]: the seconds group / 秒分组
/// - [millis]: the fractional group, right-padded to milliseconds /
///   小数分组，右补零到毫秒
///
/// Returns the parsed duration.
///
/// 返回解析出的时长。
Duration _toDuration(String? hours, String minutes, String seconds, String millis) {
  final h = hours == null ? 0 : int.parse(hours.substring(0, hours.length - 1));
  return Duration(
    hours: h,
    minutes: int.parse(minutes),
    seconds: int.parse(seconds),
    milliseconds: int.parse(millis.padRight(3, '0')),
  );
}

/// Parses a WebVTT thumbnail track into a time-ordered [MovaThumbIndex].
///
/// Only cues whose payload is a single image reference are kept. A payload may
/// carry an `#xywh=x,y,w,h` media fragment selecting a sub-rectangle of a
/// sprite sheet; without one, the whole image is the frame. Relative payload
/// paths resolve against [base]. Malformed timing lines, empty payloads and
/// unparsable fragments never throw — the offending cue is skipped, or, for a
/// bad fragment only, kept without a crop.
///
/// 把 WebVTT 缩略图轨解析为按时间排序的 [MovaThumbIndex]。
///
/// 只保留 payload 为单个图片引用的 cue。payload 可带 `#xywh=x,y,w,h` 媒体片段
/// 以选取雪碧图的子矩形；不带时整张图即为该帧。相对路径按 [base] 解析。
/// 畸形时间轴行、空 payload、无法解析的片段都不会抛异常——对应 cue 会被跳过；
/// 仅片段畸形时则保留 cue 但不带裁剪。
///
/// - [content]: raw `.vtt` file content / 原始 `.vtt` 文件内容
/// - [base]: URL the `.vtt` itself was fetched from, used to resolve relative
///   sprite paths / 该 `.vtt` 自身的 URL，用于解析相对雪碧图路径
///
/// Returns the parsed index; empty when [content] is empty or is not a WebVTT
/// document.
///
/// 返回解析出的索引；[content] 为空或不是 WebVTT 文档时返回空索引。
MovaThumbIndex parseVttThumbs(String content, {required Uri base}) {
  if (!content.trimLeft().startsWith('WEBVTT')) {
    return const MovaThumbIndex(<MovaThumbCue>[]);
  }

  final lines = content.split(RegExp(r'\r\n|\n|\r'));
  final cues = <MovaThumbCue>[];

  for (var i = 0; i < lines.length; i++) {
    final m = _kTimingLine.firstMatch(lines[i]);
    if (m == null) continue;
    final start = _toDuration(m.group(1), m.group(2)!, m.group(3)!, m.group(4)!);
    final end = _toDuration(m.group(5), m.group(6)!, m.group(7)!, m.group(8)!);

    // Payload is the line right after the timing line; a blank line there
    // means this cue has no image and is skipped.
    //
    // payload 取时间轴行的下一行；该行为空说明本 cue 没有图片，直接跳过。
    final payload = i + 1 < lines.length ? lines[i + 1].trim() : '';
    if (payload.isEmpty) continue;

    final hashAt = payload.indexOf('#');
    final path = hashAt < 0 ? payload : payload.substring(0, hashAt);
    final fragment = hashAt < 0 ? '' : payload.substring(hashAt + 1);
    if (path.isEmpty) continue;

    final f = _kXywh.firstMatch(fragment);
    final crop = f == null
        ? null
        : MovaThumbCrop(
            x: int.parse(f.group(1)!),
            y: int.parse(f.group(2)!),
            w: int.parse(f.group(3)!),
            h: int.parse(f.group(4)!),
          );

    final Uri image;
    try {
      image = base.resolve(path);
    } on FormatException {
      continue;
    }
    cues.add(MovaThumbCue(start: start, end: end, image: image, crop: crop));
  }

  cues.sort((a, b) => a.start.compareTo(b.start));
  return MovaThumbIndex(cues);
}
