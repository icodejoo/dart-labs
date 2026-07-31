import '../preview/cache.dart';
import '../preview/dir_provider.dart';
import '../preview/extractor.dart';
import '../preview/hash.dart';
import '../preview/net_probe.dart';
import '../preview/platform_kind.dart';
import '../preview/source.dart';
import '../preview/vtt_source.dart';

/// Why a scrub-preview request was refused before any work happened.
///
/// 一次拖动预览请求在真正开工前被拒绝的原因。
enum VmPreviewBlockReason {
  /// The network policy refused this connection.
  ///
  /// 网络策略拒绝了当前连接。
  network,

  /// Preview is switched off via [VmPreviewConfig.enabled].
  ///
  /// 预览已通过 [VmPreviewConfig.enabled] 关闭。
  disabled,

  /// No media has been opened yet.
  ///
  /// 尚未打开任何媒体。
  noSource,

  /// No configured source can serve this platform.
  ///
  /// 当前平台上没有任何已配置的来源可用。
  platform,
}

/// Notified when a preview request is refused; the default is silence.
///
/// 预览请求被拒绝时的回调；默认行为是静默。
///
/// - [reason]: why the request was refused / 被拒绝的原因
typedef VmPreviewBlockedCallback = void Function(VmPreviewBlockReason reason);

/// Configuration for the scrub-preview (thumbnail) feature.
///
/// Every decision videoman makes on the host's behalf appears here as a
/// default plus a knob, and — where a decision is a strategy rather than a
/// value — an injection point ([probe], [cache], [extractor], [sources],
/// [vttUrlResolver], [cacheKeyBuilder]). See DESIGN §6.1.
///
/// 拖动预览（缩略图）功能的配置。
///
/// videoman 替宿主做的每一个决策，在这里都以"默认值 + 配置项"的形式出现；
/// 若该决策本质是策略而非取值，还额外提供注入点（[probe]、[cache]、
/// [extractor]、[sources]、[vttUrlResolver]、[cacheKeyBuilder]）。见 DESIGN §6.1。
class VmPreviewConfig {
  /// Whether the preview feature runs at all.
  ///
  /// 是否启用预览功能。
  final bool enabled;

  /// When networked thumbnail sources may run.
  ///
  /// 何时允许运行需要联网的缩略图来源。
  final VmPreviewNetwork network;

  /// Injected connectivity probe; null uses [AlwaysAllowNetProbe] in core and
  /// the connectivity_plus probe when the host wires one in.
  ///
  /// 注入的连通性探针；为 null 时 core 内部使用 [AlwaysAllowNetProbe]，宿主
  /// 接入时可换成基于 connectivity_plus 的探针。
  final VmNetProbe? probe;

  /// Called when a request is refused; null means stay silent.
  ///
  /// 请求被拒绝时的回调；为 null 表示静默。
  final VmPreviewBlockedCallback? onBlocked;

  /// Ordered thumbnail source chain; null builds the default
  /// `[vtt, extract]` chain from [vttEnabled]/[extractFallback].
  ///
  /// 有序的缩略图来源链；为 null 时按 [vttEnabled]/[extractFallback] 构建默认
  /// 的 `[vtt, extract]` 链。
  final List<VmThumbSource>? sources;

  /// Whether the WebVTT source participates in the default chain.
  ///
  /// WebVTT 来源是否参与默认链。
  final bool vttEnabled;

  /// Fixed WebVTT track URL; overrides the `<video>.vtt` convention.
  ///
  /// 固定的 WebVTT 轨地址；覆盖 `<video>.vtt` 约定。
  final String? vttUrl;

  /// Strategy locating the WebVTT track; wins over [vttUrl] when both are set.
  ///
  /// 定位 WebVTT 轨的策略；与 [vttUrl] 同时设置时以本项为准。
  final VmVttUrlResolver? vttUrlResolver;

  /// Whether frame extraction backs up a missing/failing WebVTT track.
  ///
  /// WebVTT 轨缺失/失败时是否用抽帧兜底。
  final bool extractFallback;

  /// Platforms frame extraction is allowed to run on.
  ///
  /// 允许运行抽帧的平台集合。
  final Set<VmPlatformKind> extractPlatforms;

  /// Injected frame extractor; null uses the media_kit-backed default wired in
  /// by the host layer.
  ///
  /// 注入的抽帧器；为 null 时使用由宿主层接入的、基于 media_kit 的默认实现。
  final VmFrameExtractor? extractor;

  /// Target thumbnail width in pixels.
  ///
  /// 缩略图目标宽度（像素）。
  final int frameWidth;

  /// Bucket size positions are aligned to, so scrubbing within one bucket
  /// reuses one image.
  ///
  /// 位置对齐所用的桶大小，使同一桶内的拖动复用同一张图。
  final Duration bucket;

  /// Whether extraction may use hardware decoding.
  ///
  /// 抽帧是否允许使用硬件解码。
  final bool hwdec;

  /// Memory cache entry ceiling.
  ///
  /// 内存缓存条目上限。
  final int memMaxEntries;

  /// Disk cache byte budget.
  ///
  /// 磁盘缓存字节预算。
  final int diskMaxBytes;

  /// Fixed disk cache directory; null uses the platform temporary directory.
  ///
  /// 固定的磁盘缓存目录；为 null 时使用平台临时目录。
  final String? diskDir;

  /// Injected cache implementation; null builds the default two-level cache
  /// from [memMaxEntries]/[diskMaxBytes]/[diskDir].
  ///
  /// 注入的缓存实现；为 null 时按 [memMaxEntries]/[diskMaxBytes]/[diskDir]
  /// 构建默认的两级缓存。
  final VmThumbCache? cache;

  /// Injected disk directory resolver; null uses [diskDir] when set, otherwise
  /// the host-wired temporary-directory provider.
  ///
  /// 注入的磁盘目录解析器；为 null 时优先用 [diskDir]，否则使用宿主接入的
  /// 临时目录 provider。
  final VmThumbDirProvider? dirProvider;

  /// Strategy building cache keys; null uses [defaultCacheKey].
  ///
  /// 构建缓存 key 的策略；为 null 时使用 [defaultCacheKey]。
  final VmCacheKeyBuilder? cacheKeyBuilder;

  /// Whether the disk cache directory is wiped on dispose.
  ///
  /// 销毁时是否清空磁盘缓存目录。
  final bool clearOnDispose;

  /// How long scrub movement must settle before a request is issued.
  ///
  /// 拖动静止多久之后才发出请求。
  final Duration debounce;

  /// Creates a preview configuration; every field defaults to the value
  /// documented in DESIGN §6.1.
  ///
  /// 创建预览配置；每个字段的默认值均与 DESIGN §6.1 一致。
  ///
  /// - [enabled]: master switch / 总开关
  /// - [network]: network policy / 网络策略
  /// - [probe]: injected connectivity probe / 注入的连通性探针
  /// - [onBlocked]: refusal callback / 被拒回调
  /// - [sources]: full source-chain override / 整条来源链的覆盖
  /// - [vttEnabled]: include the WebVTT source / 是否启用 WebVTT 来源
  /// - [vttUrl]: fixed WebVTT URL / 固定 WebVTT 地址
  /// - [vttUrlResolver]: WebVTT URL strategy / WebVTT 地址策略
  /// - [extractFallback]: include the extraction source / 是否启用抽帧兜底
  /// - [extractPlatforms]: platforms extraction runs on / 允许抽帧的平台
  /// - [extractor]: injected extractor / 注入的抽帧器
  /// - [frameWidth]: target width in px / 目标宽度（像素）
  /// - [bucket]: bucket size / 桶大小
  /// - [hwdec]: allow hardware decoding / 是否允许硬解
  /// - [memMaxEntries]: memory entry ceiling / 内存条目上限
  /// - [diskMaxBytes]: disk byte budget / 磁盘字节预算
  /// - [diskDir]: fixed disk directory / 固定磁盘目录
  /// - [cache]: injected cache / 注入的缓存
  /// - [dirProvider]: injected directory resolver / 注入的目录解析器
  /// - [cacheKeyBuilder]: cache-key strategy / 缓存 key 策略
  /// - [clearOnDispose]: wipe disk cache on dispose / 销毁时清盘
  /// - [debounce]: scrub settle delay / 拖动防抖时长
  const VmPreviewConfig({
    this.enabled = true,
    this.network = VmPreviewNetwork.wifiOnly,
    this.probe,
    this.onBlocked,
    this.sources,
    this.vttEnabled = true,
    this.vttUrl,
    this.vttUrlResolver,
    this.extractFallback = true,
    this.extractPlatforms = const {
      VmPlatformKind.android,
      VmPlatformKind.ios,
      VmPlatformKind.windows,
      VmPlatformKind.macos,
      VmPlatformKind.linux,
      VmPlatformKind.other,
    },
    this.extractor,
    this.frameWidth = 160,
    this.bucket = const Duration(seconds: 10),
    this.hwdec = false,
    this.memMaxEntries = 40,
    this.diskMaxBytes = 64 * 1024 * 1024,
    this.diskDir,
    this.cache,
    this.dirProvider,
    this.cacheKeyBuilder,
    this.clearOnDispose = true,
    this.debounce = const Duration(milliseconds: 120),
  });

  /// Returns a copy with the given knobs replaced; omitted knobs keep their
  /// current value.
  ///
  /// 返回一份替换了指定配置项的拷贝；未指定的项保持当前值。
  ///
  /// Every parameter mirrors the same-named field.
  ///
  /// 每个参数对应同名字段。
  ///
  /// Returns the new [VmPreviewConfig].
  ///
  /// 返回新的 [VmPreviewConfig]。
  VmPreviewConfig copyWith({
    bool? enabled,
    VmPreviewNetwork? network,
    VmNetProbe? probe,
    VmPreviewBlockedCallback? onBlocked,
    List<VmThumbSource>? sources,
    bool? vttEnabled,
    String? vttUrl,
    VmVttUrlResolver? vttUrlResolver,
    bool? extractFallback,
    Set<VmPlatformKind>? extractPlatforms,
    VmFrameExtractor? extractor,
    int? frameWidth,
    Duration? bucket,
    bool? hwdec,
    int? memMaxEntries,
    int? diskMaxBytes,
    String? diskDir,
    VmThumbCache? cache,
    VmThumbDirProvider? dirProvider,
    VmCacheKeyBuilder? cacheKeyBuilder,
    bool? clearOnDispose,
    Duration? debounce,
  }) {
    return VmPreviewConfig(
      enabled: enabled ?? this.enabled,
      network: network ?? this.network,
      probe: probe ?? this.probe,
      onBlocked: onBlocked ?? this.onBlocked,
      sources: sources ?? this.sources,
      vttEnabled: vttEnabled ?? this.vttEnabled,
      vttUrl: vttUrl ?? this.vttUrl,
      vttUrlResolver: vttUrlResolver ?? this.vttUrlResolver,
      extractFallback: extractFallback ?? this.extractFallback,
      extractPlatforms: extractPlatforms ?? this.extractPlatforms,
      extractor: extractor ?? this.extractor,
      frameWidth: frameWidth ?? this.frameWidth,
      bucket: bucket ?? this.bucket,
      hwdec: hwdec ?? this.hwdec,
      memMaxEntries: memMaxEntries ?? this.memMaxEntries,
      diskMaxBytes: diskMaxBytes ?? this.diskMaxBytes,
      diskDir: diskDir ?? this.diskDir,
      cache: cache ?? this.cache,
      dirProvider: dirProvider ?? this.dirProvider,
      cacheKeyBuilder: cacheKeyBuilder ?? this.cacheKeyBuilder,
      clearOnDispose: clearOnDispose ?? this.clearOnDispose,
      debounce: debounce ?? this.debounce,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VmPreviewConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          network == other.network &&
          identical(probe, other.probe) &&
          identical(onBlocked, other.onBlocked) &&
          identical(sources, other.sources) &&
          vttEnabled == other.vttEnabled &&
          vttUrl == other.vttUrl &&
          identical(vttUrlResolver, other.vttUrlResolver) &&
          extractFallback == other.extractFallback &&
          _setEq(extractPlatforms, other.extractPlatforms) &&
          identical(extractor, other.extractor) &&
          frameWidth == other.frameWidth &&
          bucket == other.bucket &&
          hwdec == other.hwdec &&
          memMaxEntries == other.memMaxEntries &&
          diskMaxBytes == other.diskMaxBytes &&
          diskDir == other.diskDir &&
          identical(cache, other.cache) &&
          identical(dirProvider, other.dirProvider) &&
          identical(cacheKeyBuilder, other.cacheKeyBuilder) &&
          clearOnDispose == other.clearOnDispose &&
          debounce == other.debounce;

  @override
  int get hashCode => Object.hashAll(<Object?>[
        enabled,
        network,
        probe,
        onBlocked,
        sources,
        vttEnabled,
        vttUrl,
        vttUrlResolver,
        extractFallback,
        Object.hashAllUnordered(extractPlatforms),
        extractor,
        frameWidth,
        bucket,
        hwdec,
        memMaxEntries,
        diskMaxBytes,
        diskDir,
        cache,
        dirProvider,
        cacheKeyBuilder,
        clearOnDispose,
        debounce,
      ]);
}

/// Order-insensitive set equality; core cannot import `setEquals` from
/// `package:flutter/foundation.dart`.
///
/// 与顺序无关的集合相等判断；core 不能从 `package:flutter/foundation.dart`
/// 引入 `setEquals`。
///
/// - [a], [b]: the sets to compare / 要比较的两个集合
///
/// Returns whether the sets hold the same elements.
///
/// 返回两个集合元素是否相同。
bool _setEq(Set<VmPlatformKind> a, Set<VmPlatformKind> b) =>
    a.length == b.length && a.containsAll(b);
