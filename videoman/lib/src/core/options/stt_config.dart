import '../stt/port.dart';

/// Why an STT [start] request was refused before any recognition happened.
///
/// 一次 STT 启动请求在真正开始识别前被拒绝的原因。
enum VmSttBlockReason {
  /// The feature is switched off via [VmSttConfig.enabled].
  ///
  /// 功能已通过 [VmSttConfig.enabled] 关闭。
  disabled,

  /// No engine is configured (see [VmSttConfig.engine]).
  ///
  /// 未配置引擎（见 [VmSttConfig.engine]）。
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
typedef VmSttBlockedCallback = void Function(VmSttBlockReason reason);

/// Configuration for the speech-to-text subtitle feature.
///
/// Off by default (STT is expensive: model download + on-device inference).
/// [engine] is the injection point for "which recognizer runs" — leave it
/// `null` to get [NoopSttEngine] (no recognition happens) until a real engine
/// (e.g. a sherpa-onnx Zipformer binding from `platform_impl/`) is wired via
/// `createVmEngine(stt: ...)`. Only one engine is supported per player
/// instance in this version — see
/// `doc/notes/2026-08-04-stt-engine-decision.md` for the multi-language
/// routing design reserved for later.
///
/// 语音转字幕功能的配置。
///
/// 默认关闭（STT 代价不小：模型下载 + 端上推理）。[engine] 是"用哪个识别器"
/// 的注入点——留空得到 [NoopSttEngine]（不做任何识别），直到通过
/// `createVmEngine(stt: ...)` 接入真实引擎（如 `platform_impl/` 下的
/// sherpa-onnx Zipformer 绑定）。本版本每个播放器实例只支持一个引擎——多语言
/// 路由的预留设计见 `doc/notes/2026-08-04-stt-engine-decision.md`。
class VmSttConfig {
  /// Creates an STT configuration; disabled with no engine by default.
  ///
  /// 创建 STT 配置；默认关闭且不带引擎。
  const VmSttConfig({this.enabled = false, this.engine, this.onBlocked});

  /// Whether the STT subtitle feature runs at all.
  ///
  /// 是否启用 STT 字幕功能。
  final bool enabled;

  /// The recognizer to feed decoded audio into; `null` means no recognition
  /// happens (see [NoopSttEngine]).
  ///
  /// 接收解码音频的识别器；为空表示不做任何识别（见 [NoopSttEngine]）。
  final VmSttEngine? engine;

  /// Called whenever a [start] request is refused; null means stay silent.
  ///
  /// [start] 请求被拒绝时的回调；为 null 表示静默。
  final VmSttBlockedCallback? onBlocked;

  /// Returns a copy with the given fields replaced.
  ///
  /// 返回一份替换了指定字段的拷贝。
  ///
  /// - [enabled]: replacement enabled flag / 替换用的启用开关
  /// - [engine]: replacement engine / 替换用的引擎
  /// - [onBlocked]: replacement refusal callback / 替换用的被拒回调
  ///
  /// Returns the new [VmSttConfig] instance / 返回新的 [VmSttConfig] 实例。
  VmSttConfig copyWith({bool? enabled, VmSttEngine? engine, VmSttBlockedCallback? onBlocked}) {
    return VmSttConfig(
      enabled: enabled ?? this.enabled,
      engine: engine ?? this.engine,
      onBlocked: onBlocked ?? this.onBlocked,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmSttConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          identical(engine, other.engine) &&
          identical(onBlocked, other.onBlocked);

  @override
  int get hashCode => Object.hash(enabled, identityHashCode(engine), identityHashCode(onBlocked));
}
