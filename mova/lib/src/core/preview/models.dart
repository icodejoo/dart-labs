import 'dart:typed_data';

/// A rectangular sub-region of a sprite sheet, in image pixels.
///
/// 雪碧图中的一块矩形子区域，单位为图像像素。
class MovaThumbCrop {
  /// Left edge in image pixels.
  ///
  /// 左边界（图像像素）。
  final int x;

  /// Top edge in image pixels.
  ///
  /// 上边界（图像像素）。
  final int y;

  /// Region width in image pixels.
  ///
  /// 区域宽度（图像像素）。
  final int w;

  /// Region height in image pixels.
  ///
  /// 区域高度（图像像素）。
  final int h;

  /// Creates a crop rectangle.
  ///
  /// 创建一个裁剪矩形。
  ///
  /// - [x], [y]: top-left corner in image pixels / 左上角（图像像素）
  /// - [w], [h]: size in image pixels / 尺寸（图像像素）
  const MovaThumbCrop({required this.x, required this.y, required this.w, required this.h});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaThumbCrop && other.x == x && other.y == y && other.w == w && other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() => 'MovaThumbCrop($x,$y,$w,$h)';
}

/// One resolved preview frame: encoded image bytes, the sub-rectangle to
/// display, and the bucket-aligned position it represents.
///
/// 一帧已就绪的预览图：编码后的图像字节、要显示的子矩形，以及它所代表的
/// 桶对齐位置。
class MovaThumb {
  /// The bucket-aligned media position this thumbnail represents.
  ///
  /// 该缩略图代表的桶对齐媒体位置。
  final Duration at;

  /// Encoded image bytes (JPEG or PNG); may be a whole sprite sheet when
  /// [crop] is non-null.
  ///
  /// 编码后的图像字节（JPEG 或 PNG）；[crop] 非空时可能是整张雪碧图。
  final Uint8List bytes;

  /// Sub-rectangle of [bytes] to display, or null to display the whole image.
  ///
  /// [bytes] 中要显示的子矩形；为空表示显示整张图。
  final MovaThumbCrop? crop;

  /// Creates a preview frame.
  ///
  /// 创建一帧预览图。
  ///
  /// - [at]: bucket-aligned position / 桶对齐位置
  /// - [bytes]: encoded image bytes / 编码后的图像字节
  /// - [crop]: optional sub-rectangle / 可选的子矩形
  const MovaThumb({required this.at, required this.bytes, this.crop});
}

/// One WebVTT thumbnail cue: a time range plus the image (and optional
/// sub-rectangle) covering it.
///
/// 一条 WebVTT 缩略图 cue：一个时间区间，以及覆盖该区间的图像（及可选子矩形）。
class MovaThumbCue {
  /// Inclusive start of the covered range.
  ///
  /// 覆盖区间的起点（含）。
  final Duration start;

  /// Exclusive end of the covered range.
  ///
  /// 覆盖区间的终点（不含）。
  final Duration end;

  /// Absolute URL of the sprite sheet or standalone image.
  ///
  /// 雪碧图或独立图片的绝对 URL。
  final Uri image;

  /// Sub-rectangle within [image], or null when the whole image is the frame.
  ///
  /// [image] 内的子矩形；为空表示整张图就是该帧。
  final MovaThumbCrop? crop;

  /// Creates a cue.
  ///
  /// 创建一条 cue。
  ///
  /// - [start], [end]: covered time range / 覆盖的时间区间
  /// - [image]: absolute image URL / 图片的绝对 URL
  /// - [crop]: optional sub-rectangle / 可选的子矩形
  const MovaThumbCue({
    required this.start,
    required this.end,
    required this.image,
    this.crop,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaThumbCue &&
          other.start == start &&
          other.end == end &&
          other.image == image &&
          other.crop == crop;

  @override
  int get hashCode => Object.hash(start, end, image, crop);

  @override
  String toString() =>
      'MovaThumbCue(${start.inMilliseconds}-${end.inMilliseconds}, $image, $crop)';
}

/// A time-ordered set of [MovaThumbCue]s with O(log n) lookup.
///
/// 按时间排序的 [MovaThumbCue] 集合，查找复杂度 O(log n)。
class MovaThumbIndex {
  /// The cues, sorted ascending by [MovaThumbCue.start].
  ///
  /// 按 [MovaThumbCue.start] 升序排列的 cue 列表。
  final List<MovaThumbCue> cues;

  /// Creates an index over already-sorted [cues].
  ///
  /// 用已排序的 [cues] 创建索引。
  ///
  /// - [cues]: cues sorted ascending by start / 按起点升序排列的 cue 列表
  const MovaThumbIndex(this.cues);

  /// Whether this index holds no cues.
  ///
  /// 该索引是否不含任何 cue。
  bool get isEmpty => cues.isEmpty;

  /// Finds the cue covering [t], clamping to the first/last cue when [t]
  /// falls outside the indexed range.
  ///
  /// 查找覆盖 [t] 的 cue；[t] 落在索引范围之外时，钳到首/末条 cue。
  ///
  /// - [t]: the media position to look up / 要查找的媒体位置
  ///
  /// Returns the matching cue, or null when the index is empty.
  ///
  /// 返回匹配的 cue；索引为空时返回 null。
  MovaThumbCue? cueAt(Duration t) {
    if (cues.isEmpty) return null;
    if (t < cues.first.start) return cues.first;
    var lo = 0;
    var hi = cues.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (cues[mid].start <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return cues[lo];
  }
}
