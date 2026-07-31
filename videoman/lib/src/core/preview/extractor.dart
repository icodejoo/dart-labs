import 'dart:typed_data';

import '../model/source.dart';
import 'models.dart';
import 'source.dart';

/// Decodes one frame of a media at a given position, downscaled for preview.
///
/// A port rather than a concrete class because the only implementation spins a
/// second, hidden media_kit `Player`, and `lib/src/core/**` must stay
/// media_kit-free — the implementation lives in
/// `lib/src/platform_impl/mpv_extractor_impl.dart`.
///
/// 在给定位置解出媒体的一帧，并按预览需要缩小。
///
/// 之所以做成端口而非具体类：唯一的实现会另起一个隐藏的 media_kit `Player`，
/// 而 `lib/src/core/**` 必须与 media_kit 解耦——实现放在
/// `lib/src/platform_impl/mpv_extractor_impl.dart`。
abstract class VmFrameExtractor {
  /// Extracts the frame of [uri] at [at], encoded as JPEG.
  ///
  /// 抽取 [uri] 在 [at] 处的一帧，编码为 JPEG。
  ///
  /// - [uri]: the media address / 媒体地址
  /// - [at]: the position to extract / 要抽取的位置
  /// - [width]: target width in pixels; height follows the aspect ratio /
  ///   目标宽度（像素），高度按宽高比推导
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  ///
  /// Returns the encoded frame, or null when extraction failed.
  ///
  /// 返回编码后的帧；抽取失败时返回 null。
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  });

  /// Frees the underlying decoder while staying reusable — called when the
  /// player goes idle or opens a different media.
  ///
  /// 释放底层解码器但保持可复用——播放器空闲或换源时调用。
  Future<void> release();

  /// Releases everything permanently.
  ///
  /// 永久释放全部资源。
  Future<void> dispose();
}

/// Adapts a [VmFrameExtractor] to the [VmThumbSource] contract so the preview
/// service can treat extraction as just another entry in its ordered source
/// list.
///
/// An extracted frame is always the whole image, so [VmThumb.crop] is null.
///
/// 把 [VmFrameExtractor] 适配为 [VmThumbSource] 契约，让预览服务可以把抽帧
/// 当作有序来源表里的普通一项对待。
///
/// 抽出来的帧总是整张图，因此 [VmThumb.crop] 恒为 null。
class VmExtractorThumbSource implements VmThumbSource {
  /// Creates an extractor-backed thumbnail source.
  ///
  /// 创建基于抽帧器的缩略图来源。
  ///
  /// - [extractor]: the frame extractor port / 抽帧端口
  /// - [width]: target frame width in pixels / 目标帧宽度（像素）
  /// - [hwdec]: whether hardware decoding may be used / 是否允许硬件解码
  VmExtractorThumbSource({
    required this.extractor,
    this.width = 160,
    this.hwdec = false,
  });

  /// The frame extractor this source drives.
  ///
  /// 该来源驱动的抽帧端口。
  final VmFrameExtractor extractor;

  /// Target frame width in pixels.
  ///
  /// 目标帧宽度（像素）。
  final int width;

  /// Whether hardware decoding may be used.
  ///
  /// 是否允许硬件解码。
  final bool hwdec;

  @override
  String get name => 'extract';

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async {
    final bytes = await extractor.extract(
      source.uri,
      bucket,
      width: width,
      hwdec: hwdec,
    );
    if (bytes == null) return null;
    return VmThumb(at: bucket, bytes: bytes);
  }

  @override
  Future<void> reset() => extractor.release();

  @override
  Future<void> dispose() => extractor.dispose();
}
