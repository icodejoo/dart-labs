import 'cue.dart';

/// The speech-to-text subtitle capability surface exposed on `IMovaApi.stt`.
///
/// UI components only ever listen to [cues]/[current] and call
/// [start]/[stop]; the audio pipeline (feeding decoded PCM into whichever
/// [IMovaStt] is configured) lives behind this abstraction in the core
/// layer.
///
/// 挂在 `IMovaApi.stt` 上的语音转字幕能力面。
///
/// UI 组件只会监听 [cues]/[current] 并调用 [start]/[stop]；音频管线（把解码后
/// 的 PCM 喂给配置好的 [IMovaStt]）都藏在该抽象之后的 core 层里。
abstract class IMovaSttApi {
  /// Language codes the active recognizer covers; empty when no recognizer is
  /// configured (see `MovaSttOpts.recognizer`).
  ///
  /// 当前识别器能识别的语言代码；未配置识别器时为空（见 `MovaSttOpts.recognizer`）。
  List<String> get languages;

  /// Emits each recognized cue as it becomes available.
  ///
  /// 边产出边推送每一条识别出的字幕。
  Stream<MovaSttCue> get cues;

  /// The cue covering the current playback position, if any.
  ///
  /// 覆盖当前播放位置的字幕（若有）。
  MovaSttCue? get current;

  /// Whether recognition is currently running (a successful [start] not yet
  /// followed by [stop]).
  ///
  /// 当前是否正在识别（[start] 成功后、尚未 [stop]）。
  bool get isRunning;

  /// Starts recognition for the currently open source.
  ///
  /// 对当前打开的媒体源开始识别。
  Future<void> start();

  /// Stops recognition.
  ///
  /// 停止识别。
  Future<void> stop();
}
