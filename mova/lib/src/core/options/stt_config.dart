import '../stt/port.dart';

/// Why an STT [start] request was refused before any recognition happened.
///
/// 一次 STT 启动请求在真正开始识别前被拒绝的原因。
enum MovaSttBlockReason {
  /// The feature is switched off via [MovaSttConfig.enabled].
  ///
  /// 功能已通过 [MovaSttConfig.enabled] 关闭。
  disabled,

  /// No engine is configured (see [MovaSttConfig.engine]).
  ///
  /// 未配置引擎（见 [MovaSttConfig.engine]）。
  noEngine,

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

/// Configuration for speech-to-text subtitles, disabled by default.
/// [engine] is the host-owned recognizer injection point; null means no
/// recognition (see [MovaNoopSttEngine]). This package bundles no recognizer.
/// Configure it through `options.stt`, not a factory-level `stt` parameter:
/// ```dart
/// final api = createMovaEngine(
///   options: MovaOpts(
///     stt: MovaSttConfig(enabled: true, engine: recognizer),
///   ),
/// );
/// ```
///
/// 语音转字幕默认关闭。[engine] 为宿主持有的识别器；留空不做识别，本包不内置引擎。
/// 通过上例的 options.stt 注入，工厂没有 stt 参数。本版本每播放器只支持一个识别器；
/// 多语言路由预留设计与 sherpa-onnx Zipformer 选型见
/// `doc/notes/2026-08-04-stt-engine-decision.md`。
class MovaSttConfig {
  /// Creates an STT configuration; disabled with no engine by default.
  ///
  /// 创建 STT 配置；默认关闭且不带引擎。
  const MovaSttConfig({this.enabled = false, this.engine, this.onBlocked});

  /// Whether the STT subtitle feature runs at all.
  ///
  /// 是否启用 STT 字幕功能。
  final bool enabled;

  /// The recognizer to feed decoded audio into; `null` means no recognition
  /// happens (see [MovaNoopSttEngine]).
  ///
  /// 接收解码音频的识别器；为空表示不做任何识别（见 [MovaNoopSttEngine]）。
  /// 识别器由宿主持有并销毁，播放引擎只取消自身订阅。
  final MovaSttEngine? engine;

  /// 返回是否已注入识别器；与 [enabled] 一起判断功能是否可启动。
  /// 示例：`if (!api.options.stt.hasEngine) showSetup();`。
  bool get hasEngine => engine != null;

  /// Called whenever a [start] request is refused; null means stay silent.
  ///
  /// [start] 请求被拒绝时的回调；为 null 表示静默。
  final MovaSttBlockCb? onBlocked;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  ///
  /// - [enabled]: replacement enabled flag / 替换用的启用开关
  /// - [engine]: replacement engine / 替换用的引擎
  /// - [onBlocked]: replacement refusal callback / 替换用的被拒回调
  ///
  /// Returns the new [MovaSttConfig] instance / 返回新的 [MovaSttConfig] 实例。
  MovaSttConfig copyWith({bool? enabled, MovaSttEngine? engine, MovaSttBlockCb? onBlocked}) {
    return MovaSttConfig(
      enabled: enabled ?? this.enabled,
      engine: engine ?? this.engine,
      onBlocked: onBlocked ?? this.onBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaSttConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(engine, other.engine) &&
          identical(onBlocked, other.onBlocked);

  @override
  int get hashCode => Object.hash(enabled, identityHashCode(engine), identityHashCode(onBlocked));
}
