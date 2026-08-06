import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:mova/mova.dart';

import 'zipformer_engine.dart';

/// A balance point for [transcribeWavFileParallel]'s `parallelism`: enough
/// worker isolates to meaningfully speed up decode, without starving the
/// main isolate — which, on a phone, is also driving video playback and the
/// UI — of CPU.
///
/// Real-device finding (2026-08-05): speeding up the source audio itself
/// (ffmpeg's `atempo`) to cut decode time was tried first and **rejected** —
/// side-by-side transcription of the same content at 1x vs 2x showed
/// materially more recognition errors at 2x (e.g. "第二点缺少大型高并发项目
/// 开发经验的成员" at 1x became "第二点缺少大型高变化纸开发经理的证员" at
/// 2x) — the model's accuracy assumes real-world speech tempo, and speeding
/// up phoneme durations pushes it outside that. Worker parallelism has no
/// such cost: it changes how many segments decode at once, not what the
/// model hears, so it's the only lever used from here on.
///
/// The formula takes half the device's cores (rounded down) — leaving the
/// other half for whatever's driving the UI/video and for the OS/other apps
/// — then takes whichever is smaller between that and a *memory* budget:
/// [_maxWorkerMemoryBudgetMb] divided by [_perWorkerModelMemoryMb] (each
/// extra worker isolate loads its own full copy of the recognizer model). A
/// device with 2 or fewer cores gets `1` (no parallelism) rather than 0.
///
/// The memory budget is a fixed constant, not a real reading of the current
/// device's available RAM — there's no cross-platform way to get that from
/// pure Dart without a new native dependency, which wasn't taken on for this
/// (2026-08-05 decision). [_maxWorkerMemoryBudgetMb] is chosen to comfortably
/// fit modern phones' typical headroom without knowing their actual free
/// memory; it isn't adaptive to a specific device being unusually
/// memory-constrained.
///
/// Call this once and pass the result as `parallelism`; it's cheap but not
/// free (reads [Platform.numberOfProcessors]), so don't call it in a hot
/// loop.
///
/// [transcribeWavFileParallel] 的 `parallelism` 平衡点：工作 isolate 数量要
/// 足够让解码明显提速，但不能把主 isolate 的 CPU 挤没——手机上主 isolate 同时
/// 还在跑视频播放和 UI。
///
/// 真机发现（2026-08-05）：最先试的是给源音频本身提速（ffmpeg 的
/// `atempo`）来压解码时间，**已否决**——同一段内容 1 倍速 vs 2 倍速对比转写，
/// 2 倍速识别错误明显更多（例如 1 倍速"第二点缺少大型高并发项目开发经验的
/// 成员"，2 倍速变成"第二点缺少大型高变化纸开发经理的证员"）——模型的准确率
/// 是按真实语速的假设训练的，把音素时长压缩会把输入推出这个假设之外。
/// worker 并行没有这个代价：它改变的是"同时解码几段"，不改变模型听到的内容，
/// 所以从现在起只用这一条路提速。
///
/// 这个公式取设备核数的一半（向下取整）——另一半留给正在驱动 UI/视频播放的
/// 那个以及系统/其他 App——再和一个**内存**预算比较取较小值：
/// [_maxWorkerMemoryBudgetMb] 除以 [_perWorkerModelMemoryMb]（每多一个工作
/// isolate 就要各自加载一份完整的识别器模型）。核数 2 或更少的设备给
/// `1`（不并行），不会给 0。
///
/// 这个内存预算是个固定常量，不是真的去读当前设备的可用内存——纯 Dart 没有
/// 跨平台的办法拿到这个数字，除非引入新的原生依赖，这次（2026-08-05 的决定）
/// 没有为此引入。[_maxWorkerMemoryBudgetMb] 选得足够宽松，能舒服地放进现代
/// 手机通常有的余量里；但不会针对某台内存格外紧张的设备做自适应。
///
/// 调用一次、把结果传给 `parallelism` 就行；这个函数不是完全零开销（要读
/// [Platform.numberOfProcessors]），别放进热循环里反复调。
int recommendedSttParallelism() => parallelismForCoreCount(Platform.numberOfProcessors);

/// On-disk (and roughly resident-memory) size of one recognizer model copy —
/// 69MB encoder + 5MB decoder + 1MB joiner, rounded up — that each extra
/// worker isolate duplicates.
///
/// 每多一个工作 isolate 就要重复加载一份的识别器模型体积——69MB encoder +
/// 5MB decoder + 1MB joiner，向上取整。
const _perWorkerModelMemoryMb = 75;

/// Fixed ceiling on how much memory extra STT worker isolates may collectively
/// add, in the absence of a real per-device free-memory reading — see
/// [recommendedSttParallelism]'s doc comment for why this is a constant, not
/// a measurement.
///
/// 额外 STT 工作 isolate 总共能占用的内存上限，一个固定常量——为什么是常量
/// 而不是实测值，见 [recommendedSttParallelism] 的文档注释。
const _maxWorkerMemoryBudgetMb = 300;

/// The pure formula behind [recommendedSttParallelism] — split out so it's
/// testable without depending on the current machine's actual core count.
///
/// [recommendedSttParallelism] 背后的纯函数——单独拆出来是为了不依赖当前
/// 机器的实际核数也能测。
int parallelismForCoreCount(int numberOfProcessors) {
  final coreBased = (numberOfProcessors ~/ 2).clamp(1, 4);
  final memoryBased = (_maxWorkerMemoryBudgetMb ~/ _perWorkerModelMemoryMb).clamp(1, 4);
  return coreBased < memoryBased ? coreBased : memoryBased;
}

/// Batch-transcribes [wavPath] like
/// [ZipformerSttEngine.transcribeWavFile], but decodes the VAD-detected
/// speech segments across up to [parallelism] worker isolates instead of
/// one at a time on the caller's isolate.
///
/// VAD segmentation itself stays single-threaded on the caller's isolate —
/// the silero-vad model is tiny and fast; the actual bottleneck this exists
/// to address is the Zipformer decode step, one native inference call per
/// segment. Segments are first collected in full, then split into
/// [parallelism] contiguous chunks and decoded concurrently; results are
/// merged and re-sorted by position before being returned, since chunk
/// completion order isn't the original time order.
///
/// ⚠️ Memory, not just CPU, scales with [parallelism]: each worker isolate
/// loads its own independent copy of the recognizer model (~75MB on disk for
/// this bilingual Zipformer — 69MB encoder + 5MB decoder + 1MB joiner), so
/// `parallelism: 3` means roughly 3x that resident in memory at once, on top
/// of whatever the host app already holds. The default of `1` matches
/// [ZipformerSttEngine.transcribeWavFile]'s sequential behavior exactly (one
/// recognizer, no isolates spawned) — raising it is a deliberate choice for
/// a caller that has checked its memory budget, not a default that scales
/// with CPU core count. On a phone in particular, prefer a small fixed
/// number (2, maybe 3) over anything resembling `Platform.numberOfProcessors`.
///
/// - [files]/[vadModelPath]/[numThreads]/[maxSpeechDurationSeconds]/
///   [speedFactor]: same meaning as [ZipformerSttEngine]'s constructor
///   parameters / 含义与 [ZipformerSttEngine] 构造函数的同名参数相同
/// - [wavPath]: absolute path to a mono WAV file / 单声道 WAV 文件的绝对路径
/// - [parallelism]: number of worker isolates to decode with concurrently;
///   see the memory warning above before raising this past `1` /
///   并发解码的工作 isolate 数；调大之前请先看上面关于内存的提醒
///
/// Returns every cue recognized, in chronological order.
///
/// 像 [ZipformerSttEngine.transcribeWavFile] 一样批量转写 [wavPath]，但把
/// VAD 检测到的语音段分给最多 [parallelism] 个工作 isolate 并发解码，而不是
/// 在调用方 isolate 上一段段顺序解码。
///
/// VAD 分段本身仍在调用方 isolate 单线程跑——silero-vad 模型很小很快；这里
/// 真正要解决的瓶颈是 Zipformer 解码这一步，每段语音都要单独一次原生推理
/// 调用。先把全部语音段收集齐，再切成 [parallelism] 个连续分片并发解码，
/// 结果合并后按位置重新排序返回——因为各分片跑完的顺序不等于原始时间顺序。
///
/// ⚠️ 内存开销会跟着 [parallelism] 涨，不只是 CPU：每个工作 isolate 都会
/// 各自加载一份独立的识别器模型（这个双语 Zipformer 磁盘上约 75MB——69MB
/// encoder + 5MB decoder + 1MB joiner），`parallelism: 3` 意味着同时驻留内存
/// 里的大致是 3 倍这个体积，还要叠加宿主 App 本来就占用的部分。默认值 `1`
/// 精确对应 [ZipformerSttEngine.transcribeWavFile] 的顺序行为（一个识别器，
/// 不起任何 isolate）——调大它应该是调用方核实过内存预算之后的主动选择，
/// 不该是跟着 CPU 核数走的默认值。手机上尤其应该用一个较小的固定数字
/// （2，至多 3），而不是接近 `Platform.numberOfProcessors` 的数字。
Future<List<MovaSttCue>> transcribeWavFileParallel({
  required MovaSttModelFiles files,
  required String vadModelPath,
  required String wavPath,
  int numThreads = 1,
  double maxSpeechDurationSeconds = 8.0,
  double speedFactor = 1.0,
  int parallelism = 1,
}) async {
  sherpa.initBindings();
  final wave = sherpa.readWave(wavPath);
  final segments = _collectSegments(
    samples: wave.samples,
    sampleRateHz: wave.sampleRate,
    vadModelPath: vadModelPath,
    maxSpeechDurationSeconds: maxSpeechDurationSeconds,
    speedFactor: speedFactor,
  );
  if (segments.isEmpty) return const [];

  final chunkCount = parallelism < 1 ? 1 : parallelism;
  final chunkSize = (segments.length / chunkCount).ceil();
  final chunks = <List<_PendingSegment>>[];
  for (var i = 0; i < segments.length; i += chunkSize) {
    chunks.add(segments.sublist(i, (i + chunkSize).clamp(0, segments.length)));
  }

  final filePaths = files.paths;
  final decoded = await Future.wait(chunks.map(
    (chunk) => _decodeChunk(
      filePaths: filePaths,
      numThreads: numThreads,
      sampleRateHz: wave.sampleRate,
      starts: [for (final s in chunk) s.start],
      samplesList: [for (final s in chunk) s.samples],
    ),
  ));

  final results = decoded.expand((r) => r).toList()..sort((a, b) => a.$1.compareTo(b.$1));
  return [
    for (final (start, numSamples, text) in results)
      MovaSttCue(
        text: text,
        start: Duration(
          microseconds:
              (start / wave.sampleRate * Duration.microsecondsPerSecond * speedFactor).round(),
        ),
        end: Duration(
          microseconds: ((start + numSamples) /
                  wave.sampleRate *
                  Duration.microsecondsPerSecond *
                  speedFactor)
              .round(),
        ),
      ),
  ];
}

/// A VAD-detected speech segment awaiting decode — plain data (no FFI
/// state), safe to hand to a worker isolate.
///
/// 一段等待解码的 VAD 语音段——纯数据（不含 FFI 状态），可以安全交给工作
/// isolate。
class _PendingSegment {
  _PendingSegment({required this.start, required this.samples});
  final int start;
  final Float32List samples;
}

/// Runs VAD alone (no decode) over [samples], single-threaded, returning
/// every detected segment in order.
///
/// 只跑 VAD（不解码），单线程处理 [samples]，按顺序返回检测到的每一段语音。
List<_PendingSegment> _collectSegments({
  required Float32List samples,
  required int sampleRateHz,
  required String vadModelPath,
  required double maxSpeechDurationSeconds,
  required double speedFactor,
}) {
  // See the matching comment in `ZipformerSttEngine.start` — VAD's duration
  // thresholds are measured against whatever audio it's actually given, so
  // they need dividing by `speedFactor` when that audio has been sped up, or
  // real-world pauses shrink below its silence-detection threshold and
  // sentences that should be separate segments merge into one.
  //
  // 见 `ZipformerSttEngine.start` 里对应的注释——VAD 的时长门槛是照它实际
  // 收到的音频去量的，音频被加速过就要把这些门槛除以 `speedFactor`，否则
  // 真实世界的停顿会缩到它的静音检测门槛以下，本该分开的句子就会被合并成
  // 一个语音段。
  final vad = sherpa.VoiceActivityDetector(
    config: sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: vadModelPath,
        minSilenceDuration: 0.5 / speedFactor,
        minSpeechDuration: 0.25 / speedFactor,
        maxSpeechDuration: maxSpeechDurationSeconds / speedFactor,
      ),
      sampleRate: sampleRateHz,
      debug: false,
    ),
    bufferSizeInSeconds: 30,
  );
  final windowSize = vad.config.sileroVad.windowSize;
  final segments = <_PendingSegment>[];
  void drain() {
    while (!vad.isEmpty()) {
      final segment = vad.front();
      if (segment.samples.isNotEmpty) {
        segments.add(_PendingSegment(start: segment.start, samples: segment.samples));
      }
      vad.pop();
    }
  }

  var offset = 0;
  while (samples.length - offset >= windowSize) {
    vad.acceptWaveform(Float32List.sublistView(samples, offset, offset + windowSize));
    drain();
    offset += windowSize;
  }
  vad.flush();
  drain();
  vad.free();
  return segments;
}

/// Decodes one chunk of segments inside a fresh worker isolate — its own
/// recognizer, loaded from [filePaths], lives and dies with that isolate.
///
/// 在一个全新的工作 isolate 里解码一个分片的语音段——它自己的识别器，从
/// [filePaths] 加载，随这个 isolate 的生命周期一起结束。
Future<List<(int, int, String)>> _decodeChunk({
  required Map<String, String> filePaths,
  required int numThreads,
  required int sampleRateHz,
  required List<int> starts,
  required List<Float32List> samplesList,
}) {
  return Isolate.run(() {
    sherpa.initBindings();
    final recognizer = buildZipformerRecognizer(
      files: MovaSttModelFiles(filePaths),
      numThreads: numThreads,
    );
    try {
      final results = <(int, int, String)>[];
      for (var i = 0; i < samplesList.length; i++) {
        final samples = samplesList[i];
        final stream = recognizer.createStream();
        stream.acceptWaveform(samples: samples, sampleRate: sampleRateHz);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        if (text.isNotEmpty) {
          results.add((starts[i], samples.length, text));
        }
      }
      return results;
    } finally {
      recognizer.free();
    }
  });
}
