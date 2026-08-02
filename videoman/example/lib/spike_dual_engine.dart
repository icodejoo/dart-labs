import 'package:flutter/material.dart';
import 'package:videoman/videoman.dart';

/// Video sources used by the spike; deliberately two *different* files so the
/// second engine cannot share any decoded state with the first.
///
/// spike 使用的视频源；刻意选两个*不同*的文件，使第二个引擎不可能与第一个
/// 共享任何已解码状态。
const _spikeSourceA =
    'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4';
const _spikeSourceB = 'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4';

/// A measurement harness for the dual-engine preload question: how much
/// memory does keeping a *second* [VmEngine] warm (opened and parked on its
/// first frame, ready to swap in) actually cost on top of the single-engine
/// baseline the feed uses today?
///
/// Not a demo and not shipped behaviour — it exists purely so
/// `adb shell dumpsys meminfo` can be sampled at each stage and the delta
/// read off real hardware instead of guessed. Drive it stage by stage:
/// stage 1 (single engine playing) is the baseline, stage 2 (second engine
/// preloaded) is the cost, stage 3 (second disposed) confirms the memory is
/// actually released rather than leaked.
///
/// 用于回答"双引擎预渲染"问题的测量装置：在 feed 目前的单引擎基线之上，额外
/// 保持*第二个* [VmEngine] 热着（已 open 并停在首帧、随时可切入），真实内存
/// 代价到底是多少？
///
/// 不是演示，也不是要发布的行为——它存在的唯一目的是让
/// `adb shell dumpsys meminfo` 能在每个阶段采样，从真机上读出差值而非靠猜。
/// 按阶段推进：阶段 1（单引擎播放）是基线，阶段 2（第二个引擎已预渲染）是
/// 代价，阶段 3（第二个已释放）确认内存是真的被回收而非泄漏。
class DualEngineMemorySpikePage extends StatefulWidget {
  /// Creates the dual-engine memory spike page.
  ///
  /// 创建双引擎内存 spike 页面。
  const DualEngineMemorySpikePage({super.key});

  @override
  State<DualEngineMemorySpikePage> createState() => _DualEngineMemorySpikePageState();
}

/// State for [DualEngineMemorySpikePage]; owns the always-present primary
/// engine and the optional second engine whose cost is being measured.
///
/// [DualEngineMemorySpikePage] 的状态；持有始终存在的主引擎，以及正在被测量
/// 其代价的可选第二引擎。
class _DualEngineMemorySpikePageState extends State<DualEngineMemorySpikePage> {
  /// The baseline engine — plays [_spikeSourceA] for the whole spike, exactly
  /// as today's single-engine feed would.
  ///
  /// 基线引擎——整个 spike 期间播放 [_spikeSourceA]，与当前的单引擎 feed 完全
  /// 一致。
  late final VmEngine _primary;

  /// The engine under measurement: opened with `autoPlay: false` so it decodes
  /// and parks on its first frame (the state a real preload would sit in),
  /// or `null` while not allocated.
  ///
  /// 被测量的引擎：以 `autoPlay: false` 打开，因此它会解码并停在首帧（真实
  /// 预渲染会停留的状态）；未分配时为 `null`。
  VmEngine? _preload;

  /// Human-readable description of what stage the spike is in, shown on
  /// screen so a screenshot alone identifies which meminfo sample belongs
  /// to which stage.
  ///
  /// spike 当前所处阶段的可读描述，显示在屏幕上，使单看截图就能判断某次
  /// meminfo 采样对应哪个阶段。
  String _stage = 'stage 1: single engine (baseline)';

  @override
  void initState() {
    super.initState();
    _primary = createVmEngine();
    _primary.open(const VmSource(_spikeSourceA));
  }

  /// Allocates the second engine and parks it on its first frame — the
  /// preloaded state whose memory cost this spike measures.
  ///
  /// 分配第二个引擎并让它停在首帧——本 spike 要测量其内存代价的"已预渲染"
  /// 状态。
  Future<void> _addPreload() async {
    if (_preload != null) return;
    final engine = createVmEngine();
    _preload = engine;
    setState(() => _stage = 'stage 2: + preloaded 2nd engine (measuring)');
    await engine.open(const VmSource(_spikeSourceB), autoPlay: false);
  }

  /// Disposes the second engine, so the next meminfo sample shows whether its
  /// memory actually comes back.
  ///
  /// 释放第二个引擎，使下一次 meminfo 采样能显示它的内存是否真的被归还。
  Future<void> _dropPreload() async {
    final engine = _preload;
    if (engine == null) return;
    _preload = null;
    setState(() => _stage = 'stage 3: 2nd engine disposed');
    await engine.dispose();
  }

  @override
  void dispose() {
    _preload?.dispose();
    _primary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: VmPlayer(api: _primary, autoLoadQualities: false)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _stage,
                    key: const Key('spikeStage'),
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        key: const Key('spikeAddPreload'),
                        onPressed: _addPreload,
                        child: const Text('add preload engine'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        key: const Key('spikeDropPreload'),
                        onPressed: _dropPreload,
                        child: const Text('dispose preload'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
