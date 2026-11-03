import 'dart:async';

import 'package:meta/meta.dart';

import '../model/source.dart';
import '../options/preview_config.dart';
import 'api.dart';
import 'cache.dart';
import 'extractor.dart';
import 'hash.dart';
import 'models.dart';
import 'net_probe.dart';
import 'source.dart';

/// The production [MovaPreviewApi]: debounces scrub ticks, aligns them to
/// buckets, enforces the network policy, serves cache hits, and walks the
/// configured source chain — one request in flight at a time.
///
/// A superseded request's result is still written to the cache rather than
/// discarded: the work is already paid for, and the user is very likely to
/// scrub back over that bucket (DESIGN §7.1).
///
/// 生产环境的 [MovaPreviewApi]：对拖动 tick 做防抖、按桶对齐、执行网络策略、
/// 优先吃缓存命中，再按配置的来源链依次尝试——同一时刻只有一个请求在飞。
///
/// 被后来者取代的请求，其结果仍会写入缓存而非丢弃：这份开销已经付过了，而且
/// 用户很可能会拖回那个桶（DESIGN §7.1）。
class MovaPreviewService implements MovaPreviewApi {
  /// Creates a preview service.
  ///
  /// 创建一个预览服务。
  ///
  /// - [config]: the resolved preview configuration / 已解析的预览配置
  /// - [cache]: thumbnail storage / 缩略图存储
  /// - [probe]: connectivity probe consulted under `wifiOnly` / `wifiOnly` 下
  ///   要咨询的连通性探针
  /// - [sources]: ordered source chain / 有序的来源链
  /// - [onBlocked]: refusal callback / 被拒回调
  /// - [audioOnly]: 纯音频引擎不启动 VTT 或抽帧，默认 false。
  MovaPreviewService({
    required this.config,
    required this.cache,
    required this.probe,
    required this.sources,
    this.onBlocked,
    this.audioOnly = false,
  });

  /// 是否为纯音频引擎；为 true 时不探测预览来源，默认 false。
  /// 示例：`MovaPreviewService(config: config, cache: cache, probe: probe, sources: [], audioOnly: true)`。
  final bool audioOnly;

  /// The resolved preview configuration.
  ///
  /// 已解析的预览配置。
  final MovaPreviewConfig config;

  /// Thumbnail storage; usually a two-level memory + disk cache.
  ///
  /// 缩略图存储；通常是内存 + 磁盘的两级缓存。
  final MovaThumbCache cache;

  /// Connectivity probe consulted under [MovaPreviewNet.wifiOnly].
  ///
  /// [MovaPreviewNet.wifiOnly] 下要咨询的连通性探针。
  final MovaNetProbe probe;

  /// Ordered source chain; the first non-null answer wins.
  ///
  /// 有序的来源链；第一个非 null 的结果获胜。
  final List<MovaThumbSource> sources;

  /// Called whenever a request is refused; null means stay silent.
  ///
  /// 请求被拒绝时的回调；为 null 表示静默。
  final MovaPreviewBlockCb? onBlocked;

  /// Broadcast sink for [thumbs].
  ///
  /// [thumbs] 的广播出口。
  final StreamController<MovaThumb?> _thumbs = StreamController<MovaThumb?>.broadcast();

  /// The media currently being previewed, or null before [attach].
  ///
  /// 当前正在预览的媒体；[attach] 之前为 null。
  MovaSource? _source;

  /// The debounce timer for the newest scrub tick.
  ///
  /// 最新一次拖动 tick 的防抖计时器。
  Timer? _debounce;

  /// The bucket the user is currently scrubbing over, or null when idle.
  ///
  /// 用户当前拖到的桶；空闲时为 null。
  Duration? _wanted;

  /// Serialises resolution work so only one source request is in flight.
  ///
  /// 把解析工作串行化，保证同一时刻只有一个来源请求在飞。
  Future<void> _queue = Future<void>.value();

  /// 只保留一个最新待处理请求，避免快速拖动堆积闭包。
  ({Duration bucket, int epoch, int revision})? _pending;

  /// 是否已有串行工作循环在运行。
  bool _running = false;

  /// 每次请求、取消、换源递增，防止同桶的旧请求复活。
  int _revision = 0;

  /// The thumbnail currently resolved for [_wanted], if any.
  ///
  /// [_wanted] 当前已解析出的缩略图（若有）。
  MovaThumb? _current;

  /// Bumped by every [attach]; in-flight work compares it to detect that the
  /// media changed underneath it.
  ///
  /// 每次 [attach] 都递增；在途任务据此判断媒体是否已在其脚下被换掉。
  int _epoch = 0;

  /// Whether [dispose] has run; further calls are no-ops.
  ///
  /// [dispose] 是否已执行；执行过后所有调用都变为空操作。
  bool _disposed = false;

  @override
  Stream<MovaThumb?> get thumbs => _thumbs.stream;

  @override
  MovaThumb? get current => _current;

  /// Points the service at [source], resetting every source's per-media state
  /// and dropping the current thumbnail.
  ///
  /// 把服务指向 [source]，重置每个来源与当前媒体相关的状态，并丢弃当前缩略图。
  ///
  /// - [source]: the newly opened media, or null when the player has none /
  ///   新打开的媒体；播放器无媒体时为 null
  void attach(MovaSource? source) {
    _epoch++;
    _revision++;
    _pending = null;
    _source = source;
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    _publish(null);
    for (final s in sources) {
      unawaited(s.reset());
    }
  }

  /// Aligns [position] down to the configured bucket size.
  ///
  /// 把 [position] 向下对齐到配置的桶大小。
  ///
  /// - [position]: the raw scrub position / 原始拖动位置
  ///
  /// Returns the bucket-aligned position.
  ///
  /// 返回桶对齐后的位置。
  Duration _bucketOf(Duration position) {
    final step = config.bucket.inMilliseconds;
    if (step <= 0) return position;
    final ms = position.inMilliseconds;
    return Duration(milliseconds: (ms < 0 ? 0 : ms) ~/ step * step);
  }

  /// Builds the cache key for [bucket] using the configured strategy.
  ///
  /// 用配置的策略为 [bucket] 生成缓存 key。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  /// - [media]: the media to key for, defaults to the attached one / 要生成 key
  ///   的媒体，默认取当前附着的
  ///
  /// Returns the cache key, or null when no media is attached.
  ///
  /// 返回缓存 key；未附着媒体时返回 null。
  String? _keyFor(Duration bucket, [MovaSource? media]) {
    final src = media ?? _source;
    if (src == null) return null;
    final builder = config.cacheKeyBuilder ?? defaultCacheKey;
    return builder(src.uri, bucket.inSeconds, config.frameWidth);
  }

  /// Exposes [_keyFor] to tests that assert on cache contents.
  ///
  /// 把 [_keyFor] 暴露给需要断言缓存内容的测试。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  ///
  /// Returns the cache key, or null when no media is attached.
  ///
  /// 返回缓存 key；未附着媒体时返回 null。
  @visibleForTesting
  String? debugKeyFor(Duration bucket) => _keyFor(bucket);

  /// Publishes [thumb] as the current preview.
  ///
  /// 把 [thumb] 作为当前预览发布出去。
  ///
  /// - [thumb]: the thumbnail to show, or null to hide / 要展示的缩略图，
  ///   null 表示隐藏
  void _publish(MovaThumb? thumb) {
    _current = thumb;
    if (!_thumbs.isClosed) _thumbs.add(thumb);
  }

  /// Reports [reason] to [onBlocked], swallowing host callback errors.
  ///
  /// 把 [reason] 报给 [onBlocked]，并吞掉宿主回调抛出的异常。
  ///
  /// - [reason]: why the request was refused / 被拒原因
  void _block(MovaPreviewBlockReason reason) {
    final cb = onBlocked;
    if (cb == null) return;
    try {
      cb(reason);
    } on Object {
      // A host callback must never break the preview pipeline.
      //
      // 宿主回调绝不能打断预览流水线。
    }
  }

  @override
  MovaThumb? peekAt(Duration position) {
    final bucket = _bucketOf(position);
    final key = _keyFor(bucket);
    if (key == null) return null;
    final bytes = cache.peek(key);
    if (bytes == null) return null;
    return MovaThumb(at: bucket, bytes: bytes);
  }

  @override
  void requestAt(Duration position) {
    if (_disposed) return;
    _revision++;
    _pending = null;
    _debounce?.cancel();
    _debounce = null;
    final bucket = _bucketOf(position);
    _wanted = bucket;

    final hit = peekAt(bucket);
    if (hit != null) {
      _publish(hit);
      return;
    }

    _debounce?.cancel();
    if (config.debounce <= Duration.zero) {
      _enqueue(bucket);
    } else {
      _debounce = Timer(config.debounce, () => _enqueue(bucket));
    }
  }

  /// 用 [bucket] 覆盖待处理槽；同一时刻只运行一个工作循环。
  void _enqueue(Duration bucket) {
    _pending = (bucket: bucket, epoch: _epoch, revision: _revision);
    if (_running) return;
    _running = true;
    _queue = Future<void>(() async {
      try {
        while (!_disposed && _pending != null) {
          final request = _pending!;
          _pending = null;
          if (!_isWanted(request.epoch, request.revision)) continue;
          try {
            await _resolve(request.bucket, request.epoch, request.revision);
          } on Object {
            // 宿主的探针/缓存异常仅结束本次请求，循环仍接着处理最新请求。
          }
        }
      } finally {
        _running = false;
      }
    });
  }

  /// [epoch] 与 [revision] 同时匹配才有权启动昂贵工作或发布结果。
  bool _isWanted(int epoch, int revision) =>
      !_disposed && epoch == _epoch && revision == _revision && _wanted != null;

  /// Resolves [bucket] through cache then the source chain, publishing it only
  /// while it is still the bucket the user wants.
  ///
  /// 依次通过缓存与来源链解析 [bucket]；仅当它仍是用户想要的桶时才发布。
  ///
  /// - [bucket]: the bucket-aligned position / 桶对齐位置
  /// [epoch] 绑定媒体，[revision] 绑定最新拖动意图；无返回值。
  Future<void> _resolve(Duration bucket, int epoch, int revision) async {
    if (!_isWanted(epoch, revision)) return;
    if (!config.enabled) {
      _block(MovaPreviewBlockReason.disabled);
      return;
    }
    final src = _source;
    if (src == null) {
      _block(MovaPreviewBlockReason.noSource);
      return;
    }
    if (audioOnly || sources.isEmpty) {
      _block(MovaPreviewBlockReason.platform);
      return;
    }
    // Capture media, key and epoch before any await: a later attach() must
    // neither re-key this request nor let its result surface for the new media.
    //
    // 在任何 await 之前就捕获媒体、key 与 epoch：之后的 attach() 既不能给本请求
    // 换 key，也不能让它的结果出现在新媒体上。
    final key = _keyFor(bucket, src);
    if (key == null) return;
    final allowed = await previewAllowedOn(config.network, probe);
    if (!_isWanted(epoch, revision)) return;
    if (!allowed) {
      _block(MovaPreviewBlockReason.network);
      return;
    }

    final cached = await cache.read(key);
    if (!_isWanted(epoch, revision)) return;
    if (cached != null) {
      if (_wanted == bucket) _publish(MovaThumb(at: bucket, bytes: cached));
      return;
    }

    for (final source in sources) {
      if (!_isWanted(epoch, revision)) return;
      // DVR 仍是直播；独立解码器无法可靠寻址滑动窗口，VTT 可继续提供预览。
      if (src.type == MovaStreamType.live && source is MovaPullerThumbSource) continue;
      MovaThumb? thumb;
      try {
        thumb = await source.thumbAt(src, bucket);
      } on Object {
        thumb = null;
      }
      if (epoch != _epoch) return;
      if (thumb == null) continue;
      // Cache first, publish second: a superseded bucket still earns its place
      // in the cache, it just never becomes the visible thumbnail.
      //
      // 先缓存再发布：被取代的桶依然值得留在缓存里，只是不会成为可见的缩略图。
      //
      // A cropped thumb carries a whole sprite sheet as its bytes; caching it
      // would later resurface as an uncropped thumb, so it is never cached (the
      // VTT source memoises sheets itself).
      //
      // 带 crop 的缩略图其 bytes 是整张雪碧图；缓存后会以无 crop 形态复现，所以
      // 一律不缓存（VTT 来源自己会记忆雪碧图）。
      if (thumb.crop == null) {
        await cache.write(key, thumb.bytes);
        if (epoch != _epoch) return;
      }
      if (_isWanted(epoch, revision) && _wanted == bucket) _publish(thumb);
      return;
    }
  }

  @override
  void cancel() {
    _revision++;
    _pending = null;
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    _publish(null);
  }

  @override
  Future<void> clear() async {
    await cache.clear();
    _publish(null);
  }

  /// Waits for every queued resolution to settle; test-only.
  ///
  /// 等待队列中全部解析工作完成；仅供测试使用。
  @visibleForTesting
  Future<void> drain() => _queue;

  /// Releases the service, its sources and its cache.
  ///
  /// Wipes the cache first when [MovaPreviewConfig.clearOnDispose] is set, so a
  /// killed process does not leave a temp directory full of thumbnails.
  ///
  /// 释放服务、其来源与其缓存。
  ///
  /// [MovaPreviewConfig.clearOnDispose] 打开时先清空缓存，避免进程被杀后临时
  /// 目录里堆满缩略图。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    _revision++;
    _pending = null;
    _debounce?.cancel();
    _debounce = null;
    _wanted = null;
    // Each step is isolated: one failing teardown must not skip the rest.
    //
    // 每一步相互隔离：某一步销毁失败不能跳过其余步骤。
    Future<void> step(Future<void> Function() f) async {
      try {
        await f();
      } catch (_) {}
    }

    for (final s in sources) {
      await step(s.dispose);
    }
    // 先关闭来源以中止网络与解码，再等待队列收敛。
    await _queue;
    if (config.clearOnDispose) await step(cache.clear);
    await step(cache.dispose);
    await step(probe.dispose);
    await step(_thumbs.close);
  }
}
