/// mova 的语音转字幕引擎实现（sherpa-onnx + 双语 Zipformer）。
///
/// 独立成包是为了不让 mova 主包背上 sherpa_onnx 的原生二进制体积——只有
/// 依赖了本包的宿主才会打包进这部分体积，未接入的宿主完全不受影响。
///
/// mova's speech-to-text subtitle engine (sherpa-onnx + bilingual
/// Zipformer).
///
/// Split into its own package so the mova core package never carries
/// sherpa_onnx's native binary weight — only hosts that depend on this
/// package pay that cost; hosts that don't are entirely unaffected.
library;

export 'src/chunk_cue_ownership.dart';
export 'src/chunk_manifest.dart';
export 'src/chunk_scheduler.dart';
export 'src/chunk_seek_prioritizer.dart';
export 'src/model_specs.dart';
export 'src/parallel_transcriber.dart';
export 'src/punctuate.dart';
export 'src/zipformer_engine.dart';
