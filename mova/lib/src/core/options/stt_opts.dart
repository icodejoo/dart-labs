import '../stt/stt.dart';

/// Why an STT [start] request was refused before any recognition happened.
///
/// 一次 STT 启动请求在真正开始识别前被拒绝的原因。
enum MovaSttBlockReason {
  /// The feature is switched off via [MovaSttOpts.enabled].
  ///
  /// 功能已通过 [MovaSttOpts.enabled] 关闭。
  disabled,

  /// No recognizer is configured (see [MovaSttOpts.recognizer]).
  ///
  /// 未配置识别器（见 [MovaSttOpts.recognizer]）。
  noRecognizer,

  /// No media has been opened yet.
  ///
  /// 尚未打开任何媒体。
  noSource,
}

/// Notified when a [start] request is refused; the default is silence.
///
/// [start] 请求被拒绝时的回调；默认行为是静默。
///
/// - [reason]: why the request was refused / 被拒绝的原因
typedef MovaSttBlockCb = void Function(MovaSttBlockReason reason);

/// Options for speech-to-text subtitles, disabled by default.
/// [recognizer] is the host-owned recognizer injection point; null means no
/// recognition (see [MovaNoopStt]). This package bundles no recognizer.
/// Configure it through `options.stt`, not a factory-level `stt` parameter:
/// ```dart
/// final api = createMova(
///   options: MovaOpts(
///     stt: MovaSttOpts(enabled: true, recognizer: recognizer),
///   ),
/// );
/// ```
///
/// 语音转字幕默认关闭。[recognizer] 为宿主持有的识别器；留空不做识别，本包不内置识别器。
/// 通过上例的 options.stt 注入，工厂没有 stt 参数。本版本每播放器只支持一个识别器；
/// 多语言路由预留设计与 sherpa-onnx Zipformer 选型见
/// `doc/notes/2026-08-04-stt-recognizer-decision.md`。
class MovaSttOpts {
  /// Creates STT options; disabled with no recognizer by default.
  ///
  /// 创建 STT 配置；默认关闭且不带识别器。
  const MovaSttOpts({this.enabled = false, this.recognizer, this.onBlocked});

  /// Whether the STT subtitle feature runs at all.
  ///
  /// 是否启用 STT 字幕功能。
  final bool enabled;

  /// The recognizer to feed decoded audio into; `null` means no recognition
  /// happens (see [MovaNoopStt]).
  ///
  /// 接收解码音频的识别器；为空表示不做任何识别（见 [MovaNoopStt]）。
  /// 识别器由宿主持有并销毁，播放器只取消自身订阅。
  final IMovaStt? recognizer;

  /// 返回是否已注入识别器；与 [enabled] 一起判断功能是否可启动。
  /// 示例：`if (!api.options.stt.hasRecognizer) showSetup();`。
  bool get hasRecognizer => recognizer != null;

  /// Called whenever a [start] request is refused; null means stay silent.
  ///
  /// [start] 请求被拒绝时的回调；为 null 表示静默。
  final MovaSttBlockCb? onBlocked;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  ///
  /// - [enabled]: replacement enabled flag / 替换用的启用开关
  /// - [recognizer]: replacement recognizer / 替换用的识别器
  /// - [onBlocked]: replacement refusal callback / 替换用的被拒回调
  ///
  /// Returns the new [MovaSttOpts] instance / 返回新的 [MovaSttOpts] 实例。
  MovaSttOpts copyWith({bool? enabled, IMovaStt? recognizer, MovaSttBlockCb? onBlocked}) {
    return MovaSttOpts(
      enabled: enabled ?? this.enabled,
      recognizer: recognizer ?? this.recognizer,
      onBlocked: onBlocked ?? this.onBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaSttOpts &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(recognizer, other.recognizer) &&
          identical(onBlocked, other.onBlocked);

  @override
  int get hashCode => Object.hash(enabled, identityHashCode(recognizer), identityHashCode(onBlocked));
}
