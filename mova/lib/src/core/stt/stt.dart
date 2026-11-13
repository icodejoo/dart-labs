// Speech-to-text recognizer port: the abstract interface the core layer depends
// on for turning decoded audio into subtitle cues, plus a zero-dependency
// no-op implementation. Real recognizers (e.g. a sherpa-onnx Zipformer binding)
// live under `lib/src/platform_impl/` and may import native/FFI packages;
// this file must stay free of any flutter/media_kit/ffi imports.
//
// 语音转字幕识别器端口：core 层依赖的、把解码后音频转成字幕的抽象接口，以及
// 零依赖的空实现。真实识别器（如 sherpa-onnx Zipformer 绑定）放在
// `lib/src/platform_impl/`，可以引入 native/FFI 依赖；本文件必须保持不引入
// 任何 flutter/media_kit/ffi 依赖。

import 'dart:typed_data';

import 'cue.dart';

/// A port that turns a stream of decoded PCM audio into recognized subtitle
/// cues.
///
/// One instance is scoped to a fixed set of [languages] it was built/loaded
/// for (e.g. a bilingual Zipformer instance reports `['zh', 'en']`) — this
/// port does not itself decide which language an utterance is; multi-language
/// routing (if ever added) is a decision made above this port, by selecting
/// which recognizer instance to feed, not something an instance does internally.
///
/// 把解码后的 PCM 音频流转成识别字幕的端口。
///
/// 一个实例对应固定的 [languages] 集合（例如一个中英双语 Zipformer 实例会
/// 报告 `['zh', 'en']`）——本端口自己不做语种判断；多语言路由（如果未来要加）
/// 是这个端口之上的决策，靠选择喂给哪个识别器实例来实现，不是某个实例内部
/// 自己完成的事。
abstract class IMovaStt {
  /// Language codes this recognizer instance was loaded for (e.g. `['zh', 'en']`).
  ///
  /// Empty for a recognizer that recognizes nothing (see [MovaNoopStt]).
  ///
  /// 该识别器实例加载时对应的语言代码（如 `['zh', 'en']`）。
  ///
  /// 什么都不识别的识别器（见 [MovaNoopStt]）返回空列表。
  List<String> get languages;

  /// Recognized cues, emitted as they become available.
  ///
  /// 识别出的字幕，边产出边发出。
  Stream<MovaSttCue> get cues;

  /// Starts (or resumes) recognition; must be called before [feed].
  ///
  /// [atPosition] is the playback position [feed] will begin delivering audio
  /// from — the recognizer has no other way to know what media timestamp its
  /// first sample corresponds to, so it must derive every emitted
  /// [MovaSttCue.start]/[MovaSttCue.end] from [atPosition] plus however many
  /// samples (at their reported sample rate) it has consumed since.
  ///
  /// 开始（或恢复）识别；必须在 [feed] 之前调用。
  ///
  /// [atPosition] 是 [feed] 即将开始送入音频对应的播放位置——识别器没有其他
  /// 途径得知第一个采样对应的媒体时间戳，因此每条产出字幕的
  /// [MovaSttCue.start]/[MovaSttCue.end] 都必须由 [atPosition] 加上此后已消费的
  /// 采样数（按其上报的采样率折算）推算得出。
  Future<void> start(Duration atPosition);

  /// Feeds one chunk of mono PCM audio for recognition, continuing from
  /// wherever [start]'s `atPosition` (plus prior [feed] calls) left off.
  ///
  /// - [samples]: mono PCM samples in `[-1.0, 1.0]` / 单声道 PCM 采样，
  ///   取值范围 `[-1.0, 1.0]`
  /// - [sampleRateHz]: the sample rate of [samples] / [samples] 的采样率
  void feed(Float32List samples, int sampleRateHz);

  /// Stops recognition; safe to call [start] again afterwards.
  ///
  /// 停止识别；之后可以再次调用 [start]。
  Future<void> stop();

  /// Releases any resources held by this recognizer.
  ///
  /// 释放该识别器持有的资源。
  Future<void> dispose();
}

/// 可选的会话感知能力；旧的 `implements IMovaStt` 无需新增成员。
/// 实现者须在发起异步识别时捕获代际，并写入产出的 cue，不能在完成时读取最新值。
/// 示例：`final epoch = currentEpoch; recognize().then((text) => emit(cueWith(epoch)))`。
abstract interface class IMovaSttSession {
  /// 通知已切换到 [epoch]，不停止识别；无返回值。
  /// 示例：`recognizer.bindSession(2)`，随后新任务的 cue 使用 `sessionEpoch: 2`。
  void bindSession(int epoch);
}

/// A zero-dependency [IMovaStt] no-op: recognizes nothing, emits no cues.
///
/// The default until a real recognizer is wired (mirrors [MovaNoopPip] for an
/// unsupported capability, rather than a fallback value).
///
/// 零依赖的 [IMovaStt] 空实现：不识别任何内容，不产出字幕。
///
/// 在真实识别器接入前的默认值（对应"能力不支持"，仿照 [MovaNoopPip] 的处理
/// 方式，而非兜底数值）。
class MovaNoopStt implements IMovaStt {
  @override
  List<String> get languages => const [];

  @override
  Stream<MovaSttCue> get cues => const Stream.empty();

  @override
  Future<void> start(Duration atPosition) => Future.value();

  @override
  void feed(Float32List samples, int sampleRateHz) {}

  @override
  Future<void> stop() => Future.value();

  @override
  Future<void> dispose() => Future.value();
}
