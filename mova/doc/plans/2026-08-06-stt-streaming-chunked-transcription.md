# STT 流式分片转写 + 双队列优先级调度 — 设计规格

**Goal:** 把 STT 从"整段音频一次性 batch transcribe"改成"按固定时长切片、分片独立解码、
按优先级调度"，做到"首段字幕秒出、快进/快退命中段插队、其余分片后台顺序填充"。

**Architecture:** `ChunkManifest`（纯计算的时间切片清单）+ `ChunkScheduler`（高/低两条
优先级队列，固定 worker 池）+ 边界重叠去重（分片解码带 3-5s 重叠，按"cue 中点落在本片
[start,end) 内"归属）+ 展示层合并（`SplayTreeMap<Duration, MovaSttCue>` 按分片完成事件增量
合入，`SubtitleOverlayComponent` 现有的按 `progress` 取当前 cue 逻辑不用改）。

**⚠️ 硬依赖，未满足前不可实现**：本方案要求端上能按 `(uri, startMs, durationMs)` 抽取一段
WAV。当前唯一相关实现 `MpvAudioExtractor`（`platform_impl/mpv_audio_extractor_impl.dart`）
已真机实测判死刑（mpv `ao=pcm`/`ao-pcm-file` 静默失败，mpv 官方历史 issue #7833 同症状）。
必须先有二期 ffmpeg 瘦身产出的自建 FFI 绑定（`vm_extract_audio_chunk` 或等价物）才能接入
阶段 3 及之后。阶段 1/2/6 是纯 Dart 逻辑，不依赖此前提，可以现在先做。

**Tech Stack:** 沿用现有 `mova_stt` 包（`sherpa_onnx` + `ZipformerSttEngine`），新增模块
放在 `mova_stt/lib/src/`（调度/清单/去重为纯 Dart）与 `mova` 主包
`lib/src/core/stt/`（`MovaApi` 暴露的分片状态视图）。不新增第三方依赖。

设计讨论依据：本次对话（2026-08-06），承接
[2026-08-04-stt-engine-decision.md](../notes/2026-08-04-stt-engine-decision.md)
"批量预转写"一节记录的 ffmpeg FFI 阻塞现状。

---

## 1. 数据结构

```dart
enum SttChunkState { pending, queued, decoding, done, failed }

class SttChunk {
  final int index;
  final Duration start;   // 含前置重叠
  final Duration end;     // 含后置重叠
  final Duration ownStart; // 不含重叠——去重时用这个判断 cue 归属
  final Duration ownEnd;
  SttChunkState state;
}

class ChunkManifest {
  ChunkManifest.build({
    required Duration totalDuration,
    Duration chunkDuration = const Duration(minutes: 4),
    Duration overlap = const Duration(seconds: 4),
  });
  List<SttChunk> chunks;
  int chunkIndexAt(Duration position);
}
```

## 2. 双队列调度器（`ChunkScheduler`，纯 Dart，可脱离 ffmpeg 单测）

```dart
class ChunkScheduler {
  final Queue<int> _high = Queue();
  final Queue<int> _low = Queue();

  void seedLowPriority(Iterable<int> allIndices);   // 初始化：全部进低优先级
  void enqueueHigh(int chunkIndex);                 // 去重：先从 low 里移除，再插到 high 头部
  int? nextTask();                                  // high 优先，空了才取 low
}
```

- worker 池固定数量（复用已验证的 `recommendedSttParallelism()` 手机资源保护经验，
  默认 2，可配置但不建议超过 3）。
- `chunk[0]` 启动时直接 `enqueueHigh(0)`。
- 每个 worker 循环 `nextTask()` 拿分片索引 → 调 extractor 抽取 → 喂
  `ZipformerSttEngine` 解码 → 标记 `done` → 发出"分片完成"事件。

## 3. seek / 快进快退 → 抢占高优先级

```dart
void onSeek(Duration target) {
  final chunk = manifest.chunkIndexAt(target);
  scheduler.enqueueHigh(chunk);
  scheduler.enqueueHigh(chunk + 1);   // 预读下一片
}
```

**必须做防抖**：拖动条连续 `onSeek` 事件不能每次都入队，等落点稳定 ~300ms 再取最终
target；否则一次拖动产生几十个高优先级请求，队列失去意义。防抖逻辑本身是纯函数，可单测
（喂一串带时间戳的 seek 事件，断言只有最后一个触发 `enqueueHigh`）。

## 4. 边界重叠去重

抽取时每片前后各留 `overlap`（默认 4s）。VAD 照常在重叠区检测语音段，产出的 cue 若其
**中点**落在 `[ownStart, ownEnd)` 之外，则归属应移交给相邻分片，本分片丢弃该 cue：

```dart
bool cueBelongsToChunk(MovaSttCue cue, SttChunk chunk) {
  final mid = cue.start + (cue.end - cue.start) ~/ 2;
  return mid >= chunk.ownStart && mid < chunk.ownEnd;
}
```

纯函数，用构造的 fixture cue 列表单测即可，不需要真实音频。

## 5. 展示层合并

`SubtitleOverlayComponent` 现有逻辑（监听 `api.stt.cues` + `api.progress`，按当前位置取
覆盖的 cue）不用大改；改造点在 `MovaSttSvc`：cue 来源从"一次性 transcribe 返回的
List"改成"按分片完成事件增量合入 `SplayTreeMap<Duration, MovaSttCue>`"。

## 6. 断点续存

延伸现有 `MovaSttSubStore`（`fnv1a64(sourceUri)` 命名）模式——**从"整视频一个
`.srt`"改成"按 `(sourceHash, chunkIndex)` 存每片"**。重新打开同一视频：已 `done` 的分片
读缓存直接标记完成、跳过重新入队；`pending` 的分片正常走调度。

## 7. `MovaApi` 新增状态面

```dart
abstract class MovaSttApi {
  // ...已有字段...
  Stream<Map<int, SttChunkState>> get chunkStates;  // 供 UI 显示"这段还没生成"
}
```

## 8. 落地顺序

| 阶段 | 内容 | 依赖 ffmpeg FFI？ |
|---|---|---|
| 0 | 二期 ffmpeg 瘦身 → 产出 `vm_extract_audio_chunk` 或等价 FFI | **是，硬阻塞** |
| 1 | `ChunkManifest` + `ChunkScheduler`（注入假 extractor 单测） | 否 |
| 2 | 边界去重纯函数 + seek 防抖纯函数 | 否 |
| 3 | 接入真实 extractor + `ZipformerSttEngine` 单片解码联调 | 是 |
| 4 | seek 抢占接入真实 `MovaApi` seek 事件 | 是（联调） |
| 5 | `SubtitleOverlayComponent`/`MovaSttSvc` 接入合并展示 | 是 |
| 6 | 断点续存缓存（按分片存取） | 否/是均可，独立模块 |
| 7 | 真机端到端验证（本项目 STT 相关迄今全部未做过完整端到端真机验证，见
     [2026-08-05 STT 验收记录](../../../../.claude/../..) 相关 memory） | — |

阶段 1、2、6 不依赖 ffmpeg，可以现在先做；阶段 0 是"二期"本身。

## 9. 明确不做的事（本期范围外）

- 不做跨分片的语义级句子重组（比如把因为分片被切断、语义上其实是同一句但物理上被
  overlap 规则分给了两个分片的极端情况做二次合并）——重叠区去重规则已经是"够用但不完美"
  的权衡，进一步优化留作后续。
- 不做"高优先级抢占正在解码的低优先级任务"（非抢占式调度）——分片时长控制在几分钟级、
  单片解码耗时有界（RTF~0.35-0.5），worst-case 等待可接受，抢占会引入 isolate 取消的
  复杂度，性价比不高。
