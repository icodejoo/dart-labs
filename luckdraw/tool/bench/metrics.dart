import 'dart:math' as math;

/// 每个场景必须有三次独立运行。
const int kBenchRepetitions = 3;

/// 每轮 RSS 挂载与卸载次数；采集、脚本和结构检查的唯一来源。
const int kRssCycles = 5;

/// RSS 报告记录实际循环次数的字段，必须等于 [kRssCycles]。
const String kBenchRssCycles = 'rss_cycles';

/// 普通时间或字节指标的相对极差上限；比例和小耗时另用绝对容差。
const double kBenchMaxSpread = 0.30;

/// 120Hz 档的最低刷新率；90Hz 保守沿用 60Hz 掉帧预算。
const double kBenchHighRefreshThreshold = 100;

/// 120Hz 的掉帧率上限。
const double kBenchHighRefreshDropLimit = 0.01;

/// UI 平均耗时的标准键，单位毫秒。
const String kBenchBuildMean = 'average_frame_build_time_millis';

/// UI P90 耗时的标准键，单位毫秒。
const String kBenchBuildP90 = '90th_percentile_frame_build_time_millis';

/// Raster 平均耗时的标准键，单位毫秒。
const String kBenchRasterMean = 'average_frame_rasterizer_time_millis';

/// Raster P90 耗时的标准键，单位毫秒。
const String kBenchRasterP90 = '90th_percentile_frame_rasterizer_time_millis';

/// Raster P99 的诊断键；仅在预算显式提供上限时参与门禁。
const String kBenchRasterP99 = '99th_percentile_frame_rasterizer_time_millis';

/// 60Hz 保存窗口的最低交付帧率。
const double kBenchMinimumFps = 59;

/// 保存数据的目标刷新率；本规则不能外推到 120Hz。
const double kBenchDeliveryHz = 60;

/// 允许窗口边缘采样误差后的最低帧数完整比例。
const double kBenchMinimumDelivery = 0.98;

/// P90 背压阈值，位于保存窗口 8.848–16.490ms 的分布间隙。
const double kBenchBackpressureP90 = 15.5;

/// 成本门禁至少需要两个未污染窗口。
const int kBenchMinimumCleanWindows = 2;

/// 比例稳定性的绝对容差，一个百分点，避免近零值的相对误差放大。
const double kBenchRatioSpread = 0.01;

/// 时间中位数低于此毫秒数时采用绝对稳定性容差。
const double kBenchSmallMillis = 0.5;

/// 小耗时稳定性的绝对容差，单位毫秒。
const double kBenchMillisSpread = 0.15;

/// UI P99 的标准键，单位毫秒。
const String kBenchBuildP99 = '99th_percentile_frame_build_time_millis';

/// 同一帧 build 与 raster 合计 P99 的保存字段，单位毫秒。
const String kBenchCombinedP99 = '99th_percentile_build_plus_raster_millis';

/// 未污染窗口合计 P99 硬上限，为 60Hz 帧周期保留至少 4.5ms。
const double kBenchCombinedP99Limit = 12;

/// 未污染窗口 UI P99 硬上限，单位毫秒。
const double kBenchBuildP99Limit = 4;

/// 未达设计目标但回归预算通过的展示状态。
const String kBenchCalibratedDesign = '已按实测标定（未达最初设计目标）';

/// 达成设计目标的展示状态。
const String kBenchMeetsDesign = '满足设计目标';

/// 指标原始设计目标字段，与回归预算独立。
const String kBenchDesignTarget = 'design_target';

/// 实测中位数相对设计目标的差距字段；零目标无可定义比例。
const String kBenchDesignGap = 'gap_to_design';

/// 指标或场景的设计目标展示结论字段。
const String kBenchDesignStatus = 'design_status';

/// 帧预算余量的独立硬门禁字段。
const String kBenchFrameBudget = 'frame_budget';

/// 首版标定保留的余量。
const double kBenchCalibrationHeadroom = 1.1;

/// 耗时预算向上取整的精度，与历史预算保持一致。
const double kBenchMillisPrecision = 1000;

/// 比例预算向上取整的精度。
const double kBenchRatioPrecision = 1000000;

/// 消除十进制预算换算中的浮点尾差，不改变有意义的向上取整。
const double kBenchRoundingEpsilon = 1e-9;

/// 预算中声明该场景仅供信息展示的键。
const String kBenchInformational = 'informational';

/// 预算中记录信息项原因的键。
const String kBenchInformationReason = 'reason';

/// 分类输出的通过状态。
const String kBenchPass = 'PASS';

/// 分类输出的失败状态。
const String kBenchFail = 'FAIL';

/// 未污染窗口不足或仍不稳定，不能下确定的成本结论。
const String kBenchUncertain = 'UNCERTAIN';

/// 实测信息项，不能解释为门禁通过。
const String kBenchInfo = 'INFO';

/// 实测帧率字段。
const String kBenchFps = 'fps';

/// 窗口时长字段，单位微秒。
const String kBenchElapsed = 'elapsed_micros';

/// 评估结果的状态字段。
const String kBenchStatus = 'status';

/// 评估结果的原目标字段。
const String kBenchTarget = 'target';

/// 评估结果的有效上限字段。
const String kBenchLimit = 'limit';

/// 评估结果的中位数字段。
const String kBenchMedian = 'median';

/// 评估结果的稳定性字段。
const String kBenchStable = 'stable';

/// 评估结果的首版标定字段。
const String kBenchCalibrated = 'calibrated';

/// 窗口的帧交付判定字段。
const String kBenchDeliveryPassed = 'delivery_passed';

/// 窗口的帧数完整比例字段。
const String kBenchDeliveryRatio = 'delivery_ratio';

/// 窗口的背压污染字段。
const String kBenchContaminated = 'backpressure_contaminated';

/// 窗口的分类名称字段。
const String kBenchClassification = 'classification';

/// 评估结果的窗口列表字段。
const String kBenchWindows = 'windows';

/// 评估结果的指标集合字段。
const String kBenchMetrics = 'metrics';

/// 真实卡顿的窗口分类值。
const String kBenchRealJank = 'REAL_JANK';

/// 背压污染的窗口分类值。
const String kBenchBackpressure = 'BACKPRESSURE';

/// 未污染且交付完整的窗口分类值。
const String kBenchClean = 'CLEAN';

/// 帧数相对于窗口时长的完整比例；缺失或零时长抛出格式错误。
double frameDeliveryRatio(Map<String, Object?> window) {
  final elapsed = benchNumber(window[kBenchElapsed], kBenchElapsed);
  if (elapsed == 0) throw const FormatException('窗口时长必须大于零');
  return benchNumber(window[kBenchFrameCount], kBenchFrameCount) /
      (elapsed / Duration.microsecondsPerSecond * kBenchDeliveryHz);
}

/// [window] 的 fps 与帧数均达下限才通过；所有稳态窗口都必须检查。
bool frameDeliveryPassed(Map<String, Object?> window) =>
    benchNumber(window[kBenchFps], kBenchFps) >= kBenchMinimumFps &&
    frameDeliveryRatio(window) >= kBenchMinimumDelivery;

/// [window] 交付完整且 Raster P90 达到阈值才判为背压污染。
///
/// 例如 `isBackpressureContaminated(summary)`；真实卡顿始终返回 false。
/// 这是保存的 60Hz 数据的操作性分类，不是 GPU 阻塞原因的直接测量。
bool isBackpressureContaminated(Map<String, Object?> window) =>
    frameDeliveryPassed(window) &&
    benchNumber(window[kBenchRasterP90], kBenchRasterP90) >=
        kBenchBackpressureP90;

/// 返回非空有限非负 [values] 的中位数；偶数样本取中间两项平均。
double benchMedian(Iterable<Object?> values) {
  final sorted = values.map((v) => benchNumber(v, kBenchMedian)).toList()
    ..sort();
  if (sorted.isEmpty) throw const FormatException('中位数样本不能为空');
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// 返回 [values] 是否稳定；比例绝对极差不超过一个百分点。
///
/// [millis] 时间中位数低于 0.5ms 时绝对极差不超过 0.15ms；其余
/// 时间或字节采用相对极差 30%。空样本返回 false，非法值抛格式异常。
bool benchStable(List<double> values,
    {bool ratio = false, bool millis = true}) {
  if (values.isEmpty) return false;
  final median = benchMedian(values);
  final spread = values.reduce(math.max) - values.reduce(math.min);
  final tolerance = ratio
      ? kBenchRatioSpread
      : millis && median < kBenchSmallMillis
          ? kBenchMillisSpread
          : median * kBenchMaxSpread;
  return spread <= tolerance + kBenchRoundingEpsilon;
}

/// 对 [values] 应用分类型稳定性和冻结回归预算，返回完整证据。
///
/// 成本调用方只能传入未污染窗口；不足两个返回 UNCERTAIN。RSS 调用方
/// 传 [rss] 保持 FIN 的绝对上限。[informational] 项始终返回 INFO。
/// [designTarget] 保留原设计目标；[calibrate] 仅用于显式离线首版标定，
/// 时间预算取中位数乘 1.1 向上取整与有来源的 [calibratedFloor] 的最大值。
/// 正常比较不自动放宽 [target]；比例、计数、RSS 不重新标定。
Map<String, Object?> assessMetric(List<double> values, double target,
    {bool rss = false,
    bool informational = false,
    bool ratio = false,
    bool millis = true,
    bool calibrate = false,
    double? calibratedFloor,
    double? designTarget}) {
  final design = designTarget ?? target;
  if (values.isEmpty ||
      (!rss && !informational && values.length < kBenchMinimumCleanWindows)) {
    return {
      kBenchStatus: kBenchUncertain,
      kBenchDesignTarget: design,
      kBenchDesignGap: null,
      kBenchDesignStatus: kBenchUncertain,
      kBenchTarget: target,
      kBenchLimit: target
    };
  }
  final median = benchMedian(values);
  final spread = values.reduce(math.max) - values.reduce(math.min);
  final stable =
      rss || informational || benchStable(values, ratio: ratio, millis: millis);
  final eligible =
      !rss && !informational && !ratio && millis && calibrate && stable;
  final precision = ratio ? kBenchRatioPrecision : kBenchMillisPrecision;
  final measuredLimit =
      (median * kBenchCalibrationHeadroom * precision - kBenchRoundingEpsilon)
              .ceil() /
          precision;
  final limit =
      eligible ? math.max(measuredLimit, calibratedFloor ?? 0) : target;
  final status = informational
      ? kBenchInfo
      : !stable
          ? kBenchUncertain
          : median <= limit
              ? kBenchPass
              : kBenchFail;
  return {
    'values': values,
    kBenchMedian: median,
    'spread_ratio': median == 0 ? null : spread / median,
    'spread_absolute': spread,
    kBenchDesignTarget: design,
    kBenchDesignGap: design == 0 ? null : median / design - 1,
    kBenchDesignStatus: status != kBenchPass
        ? status
        : median <= design
            ? kBenchMeetsDesign
            : kBenchCalibratedDesign,
    kBenchStable: stable,
    kBenchTarget: target,
    kBenchLimit: limit,
    kBenchCalibrated: eligible,
    kBenchStatus: status,
  };
}

/// 对单个 [scenario] 的保存窗口作帧交付、成本和可选 RSS 验收。
///
/// 至少三次独立采集；污染值保留在窗口表内，成本不足两轮时不通过。
/// [limits] 为冻结回归预算；[designTargets] 记录独立的最初设计目标。
/// 仅显式传 [calibrate] 时输出稳定时间指标的标定建议。
Map<String, Object?> assessScenario(String scenario,
    List<Map<String, Object?>> runs, Map<String, Object?> limits,
    {Map<String, Object?>? rssLimits,
    Map<String, Object?>? designTargets,
    Map<String, Object?>? calibratedFloors,
    bool calibrate = false}) {
  if (runs.length < kBenchRepetitions) {
    throw const FormatException('必须至少提供三次独立测量');
  }
  final frames = kBenchSchema[scenario]!.contains(kBenchDroppedRatio);
  final windows = <Map<String, Object?>>[];
  final clean = <Map<String, Object?>>[];
  for (final run in runs) {
    final delivered = !frames || frameDeliveryPassed(run);
    final contaminated = frames && isBackpressureContaminated(run);
    if (frames && benchNumber(run[kBenchFrameCount], kBenchFrameCount) <= 0) {
      throw const FormatException('报告没有有效帧');
    }
    windows.add({
      ...run,
      kBenchDeliveryPassed: frames ? delivered : null,
      kBenchDeliveryRatio: frames ? frameDeliveryRatio(run) : null,
      kBenchContaminated: frames ? contaminated : null,
      kBenchClassification: !frames
          ? kBenchInfo
          : !delivered
              ? kBenchRealJank
              : contaminated
                  ? kBenchBackpressure
                  : kBenchClean,
    });
    if (!contaminated) clean.add(run);
  }
  final metrics = <String, Object?>{};
  final allLimits = <String, Object?>{
    ...limits,
    if (rssLimits != null) ...rssLimits,
  };
  for (final entry in allLimits.entries) {
    if (const {kBenchInformational, kBenchInformationReason}
        .contains(entry.key)) continue;
    final rss = const {kBenchRssDelta, kBenchRssGrowth}.contains(entry.key);
    final selected = rss ? runs : clean;
    metrics[entry.key] = assessMetric(
        selected.map((r) => benchNumber(r[entry.key], entry.key)).toList(),
        benchNumber(entry.value, entry.key),
        designTarget: (designTargets?[entry.key] as num?)?.toDouble(),
        calibratedFloor: (calibratedFloors?[entry.key] as num?)?.toDouble(),
        calibrate: calibrate,
        millis: entry.key.endsWith('_millis'),
        rss: rss,
        informational: limits[kBenchInformational] == true,
        ratio: entry.key == kBenchDroppedRatio);
  }
  if (frames && !limits.containsKey(kBenchRasterP99)) {
    metrics[kBenchRasterP99] = {
      kBenchMedian: clean.isEmpty
          ? null
          : benchMedian(clean.map((r) => r[kBenchRasterP99])),
      kBenchStatus: kBenchInfo,
      kBenchInformationReason: '首版没有 P99 预算，保留诊断，不虚构目标',
    };
  }
  final statuses = metrics.values
      .map((m) => (m! as Map<String, Object?>)[kBenchStatus])
      .toSet();
  final deliveryPassed =
      !frames || windows.every((w) => w[kBenchDeliveryPassed] == true);
  final guard = <String, Object?>{};
  if (frames) {
    for (final entry in const {
      kBenchCombinedP99: kBenchCombinedP99Limit,
      kBenchBuildP99: kBenchBuildP99Limit,
    }.entries) {
      final values =
          clean.map((w) => benchNumber(w[entry.key], entry.key)).toList();
      guard[entry.key] = {
        'values': values,
        'max': values.isEmpty ? null : values.reduce(math.max),
        kBenchLimit: entry.value,
        kBenchStatus: values.any((v) => v > entry.value)
            ? kBenchFail
            : values.length < kBenchMinimumCleanWindows
                ? kBenchUncertain
                : kBenchPass,
      };
    }
  }
  final guardStatuses =
      guard.values.map((v) => (v! as Map<String, Object?>)[kBenchStatus]);
  final status = !deliveryPassed ||
          statuses.contains(kBenchFail) ||
          guardStatuses.contains(kBenchFail)
      ? kBenchFail
      : statuses.contains(kBenchUncertain) ||
              guardStatuses.contains(kBenchUncertain)
          ? kBenchUncertain
          : limits[kBenchInformational] == true
              ? kBenchInfo
              : kBenchPass;
  return {
    'scenario': scenario,
    kBenchWindows: windows,
    'clean_count': frames ? clean.length : null,
    'contaminated_count': frames ? runs.length - clean.length : null,
    kBenchDeliveryPassed: frames ? deliveryPassed : null,
    kBenchMetrics: metrics,
    kBenchFrameBudget: guard,
    kBenchStatus: status,
    kBenchDesignStatus: status != kBenchPass
        ? status
        : metrics.values.any((v) =>
                (v! as Map<String, Object?>)[kBenchDesignStatus] ==
                kBenchCalibratedDesign)
            ? kBenchCalibratedDesign
            : kBenchMeetsDesign,
  };
}

/// 任一线程超出实际刷新周期的帧比例，单帧只计一次。
const String kBenchDroppedRatio = 'dropped_frame_ratio';

/// 场景比同轮参照多出的新生代 GC 次数。
const String kBenchExtraGc = 'new_gen_gc_over_reference';

/// 实际屏幕刷新率。
const String kBenchRefreshRate = 'refresh_rate_hz';

/// 已采集帧的数量。
const String kBenchFrameCount = 'frame_count';

/// 冷页面首帧 UI 总耗时，包含 build、layout 和 paint，单位毫秒。
const String kBenchFirstFrame = 'first_frame_ui_millis';

/// 页面相对空白页的 RSS 最大增量，单位字节。
const String kBenchRssDelta = 'rss_delta_bytes';

/// 第一次返回空白页相对初始空白页的增长，仅供诊断，不参与门禁。
const String kBenchRssWarmup = 'rss_warmup_bytes';

/// 第二至第五次循环的净增长；负增长按零比较上限，原值数组完整保留。
const String kBenchRssGrowth = 'rss_steady_growth_bytes';

/// 稳态 RSS 增长预算，单位字节（1.5 MiB）。
const int kBenchRssSteadyLimit = 1572864;

/// 参照场景的报告键。
const String kBenchReference = 'reference_spin';

/// 场景报告的身份字段。
const String kBenchReportKey = 'report_key';

/// 单次执行的唯一标识字段。
const String kBenchRunId = 'run_id';

/// 每个耗时场景必须包含的预算指标。
const Set<String> kBenchFrameMetrics = {
  kBenchBuildMean,
  kBenchBuildP90,
  kBenchRasterMean,
  kBenchRasterP90,
  kBenchDroppedRatio,
  kBenchExtraGc,
};

/// 已有公开玩法入口支持的场景及其必需指标，拉霸机独立登记。
const Map<String, Set<String>> kBenchSchema = {
  'wheel_steady': kBenchFrameMetrics,
  'wheel_first_frame': {kBenchFirstFrame},
  'grid_steady': kBenchFrameMetrics,
  'slot_steady': kBenchFrameMetrics,
  'slot_raster': kBenchFrameMetrics,
  'lever_steady': kBenchFrameMetrics,
  'capsule_mixing': kBenchFrameMetrics,
  'number_wheel_spin': kBenchFrameMetrics,
  'lots_shaking': kBenchFrameMetrics,
  'lotto_draw': kBenchFrameMetrics,
  'memory_cycles': {kBenchRssDelta, kBenchRssGrowth},
};

/// 检查 RSS 原值是否来自本轮 [kRssCycles] 次采样，拒绝旧数据或缺样。
///
/// [data] 必须包含循环次数、页面和返回空白页的 RSS 数组；错误抛出
/// [FormatException]。例如 `validateRssSamples(report)`。
void validateRssSamples(Map<String, Object?> data) {
  if (benchNumber(data['rss_baseline'], 'rss_baseline') <= 0) {
    throw const FormatException('RSS 初始原值必须大于零');
  }
  if (data[kBenchRssCycles] != kRssCycles) {
    throw const FormatException('RSS 循环次数必须为 $kRssCycles');
  }
  for (final key in const ['rss_pages', 'rss_blank']) {
    final samples = data[key];
    if (samples is! List<Object?> || samples.length != kRssCycles) {
      throw FormatException('RSS 样本必须为 $kRssCycles 项: $key');
    }
    for (final value in samples) {
      if (benchNumber(value, key) <= 0) {
        throw FormatException('RSS 原值必须大于零: $key');
      }
    }
  }
}

/// 从五次 [data] 原始采样重算页面增量、首次预热和稳态增长。
///
/// 返回非负字节数；回收导致的负差按零计，原始数组不变。旧汇总字段
/// 不参与计算；缺失或非法采样抛出 [FormatException]。
Map<String, double> summarizeRss(Map<String, Object?> data) {
  validateRssSamples(data);
  final baseline = benchNumber(data['rss_baseline'], 'rss_baseline');
  final pages = (data['rss_pages']! as List<Object?>)
      .map((value) => benchNumber(value, 'rss_pages'));
  final blanks = (data['rss_blank']! as List<Object?>)
      .map((value) => benchNumber(value, 'rss_blank'))
      .toList();
  return {
    kBenchRssDelta: math.max(0, pages.reduce(math.max) - baseline),
    kBenchRssWarmup: math.max(0, blanks.first - baseline),
    kBenchRssGrowth: math.max(0, blanks.last - blanks.first),
  };
}

/// 帧采样，只保存微秒耗时和开始时间；例如 `BenchFrame(1000, 2000, 3000)`。
class BenchFrame {
  /// [buildMicros]、[rasterMicros] 为非负耗时，[startMicros] 用于过滤批量回调。
  const BenchFrame(this.buildMicros, this.rasterMicros, this.startMicros);

  /// UI 线程耗时。
  final int buildMicros;

  /// Raster 线程耗时。
  final int rasterMicros;

  /// 帧开始的单调时钟时间。
  final int startMicros;
}

/// 一项预算比较结果；[passed] 为含边界的上限判断。
class BenchComparison {
  /// 使用场景、指标、实测中位数与上限构造结果。
  const BenchComparison(this.scenario, this.metric, this.actual, this.limit);

  /// 场景报告键。
  final String scenario;

  /// 指标名称。
  final String metric;

  /// 三次运行的中位数。
  final double actual;

  /// 当前刷新率档位对应的上限。
  final double limit;

  /// 实测小于或等于上限时通过。
  bool get passed => actual <= limit;
}

/// 从 [value] 读取有限非负数，否则抛出 [FormatException] 并附带 [label]。
double benchNumber(Object? value, String label) {
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('缺失或非法指标: $label');
  }
  return value.toDouble();
}

/// 检查预算或测量数据的场景集合、必需指标与数值；返回全部结构错误。
///
/// [budgets] 为 true 时还拒绝未知指标，避免拼错键名导致假通过。
/// 例如 `validateStructure({}, budgets: true)` 会报告缺少场景。
List<String> validateStructure(Map<String, Object?> data,
    {required bool budgets}) {
  final errors = <String>[];
  for (final key in data.keys) {
    if (!kBenchSchema.containsKey(key)) errors.add('未知场景: $key');
  }
  for (final entry in kBenchSchema.entries) {
    final raw = data[entry.key];
    if (raw is! Map<String, Object?>) {
      errors.add('缺少场景或场景不是对象: ${entry.key}');
      continue;
    }
    for (final metric in entry.value) {
      try {
        benchNumber(raw[metric], '${entry.key}/$metric');
      } on FormatException catch (error) {
        errors.add(error.message);
      }
    }
    if (budgets) {
      if (raw.containsKey(kBenchInformational) &&
          raw[kBenchInformational] is! bool) {
        errors.add('信息项标记必须为布尔值: ${entry.key}');
      }
      if (raw.containsKey(kBenchRasterP99)) {
        try {
          benchNumber(raw[kBenchRasterP99], kBenchRasterP99);
        } on FormatException catch (error) {
          errors.add(error.message);
        }
      }
      for (final metric in raw.keys) {
        if (!entry.value.contains(metric) &&
            !const {
              kBenchInformational,
              kBenchInformationReason,
              kBenchRasterP99
            }.contains(metric)) {
          errors.add('未知预算指标: ${entry.key}/$metric');
        }
      }
    }
  }
  return errors;
}

/// 对恰好三次 [runs] 按各指标取中位数；输入不变。
///
/// 每次必须拥有相同的非空指标集合，值为有限非负数；三次极差/中位数
/// 超出分类型稳定性容差时抛出 [FormatException]；全零视为稳定。
/// RSS 是粗粒度上限观测，不用相对极差判定；[requireStable] 为 false
/// 时仅返回中位数，供比较器在保留失败结论的同时完整输出诊断表。
Map<String, double> summarize(List<Map<String, Object?>> runs,
    {bool requireStable = true}) {
  if (runs.length != kBenchRepetitions || runs.first.isEmpty) {
    throw const FormatException('必须提供三次非空测量');
  }
  final keys = runs.first.keys.toSet();
  if (runs.any(
      (run) => run.length != keys.length || !run.keys.every(keys.contains))) {
    throw const FormatException('三次指标集合不一致');
  }
  final result = <String, double>{};
  for (final key in keys) {
    final values = runs.map((run) => benchNumber(run[key], key)).toList()
      ..sort();
    final median = values[kBenchRepetitions ~/ 2];
    if (requireStable &&
        !const {kBenchRssDelta, kBenchRssWarmup, kBenchRssGrowth}
            .contains(key) &&
        !benchStable(values,
            ratio: key.endsWith('_ratio'),
            millis: key.endsWith('_millis') || key == 'ms')) {
      throw FormatException('三次极差 > 30%，本组不稳定，不自动重跑: $key');
    }
    result[key] = median;
  }
  return result;
}

/// 将全场景 [measurements] 与 [budgets] 比较；结构错误直接抛 [FormatException]。
///
/// 120Hz 档按文件中 60Hz 上限的两倍比较，且上限至多 1%。
/// 例如 `compareToBudget(measurements, budgets).every((r) => r.passed)`。
List<BenchComparison> compareToBudget(
    Map<String, Object?> measurements, Map<String, Object?> budgets) {
  final errors = [
    ...validateStructure(measurements, budgets: false),
    ...validateStructure(budgets, budgets: true),
  ];
  if (errors.isNotEmpty) throw FormatException(errors.join('\n'));
  final comparisons = <BenchComparison>[];
  for (final scenario in kBenchSchema.keys) {
    final actual = measurements[scenario] as Map<String, Object?>;
    final limits = budgets[scenario] as Map<String, Object?>;
    if (limits[kBenchInformational] == true) continue;
    for (final metric in limits.keys) {
      if (const {kBenchInformational, kBenchInformationReason}
          .contains(metric)) {
        continue;
      }
      var limit = benchNumber(limits[metric], metric);
      if (metric == kBenchDroppedRatio) {
        final hz = benchNumber(actual[kBenchRefreshRate], kBenchRefreshRate);
        if (hz <= 0) throw const FormatException('刷新率必须大于零');
        if (hz >= kBenchHighRefreshThreshold) {
          limit = math.min(limit * 2, kBenchHighRefreshDropLimit);
        }
      }
      comparisons.add(BenchComparison(
          scenario, metric, benchNumber(actual[metric], metric), limit));
    }
  }
  return comparisons;
}

/// 将非空 [frames] 汇总为耗时均值、最近秩 P90 和实际刷新率的掉帧率。
///
/// [refreshRate] 必须为有限正数；任一线程超时视为一个掉帧，避免重复相加。
Map<String, double> summarizeFrames(
    List<BenchFrame> frames, double refreshRate) {
  if (frames.isEmpty ||
      !refreshRate.isFinite ||
      refreshRate <= 0 ||
      frames.any((f) => f.buildMicros < 0 || f.rasterMicros < 0)) {
    throw const FormatException('帧样本和刷新率必须有效');
  }
  final builds = frames
      .map((f) => f.buildMicros / Duration.microsecondsPerMillisecond)
      .toList()
    ..sort();
  final rasters = frames
      .map((f) => f.rasterMicros / Duration.microsecondsPerMillisecond)
      .toList()
    ..sort();
  final p90 = (frames.length * 0.9).ceil() - 1;
  final budgetMicros = Duration.microsecondsPerSecond / refreshRate;
  final missed = frames
      .where(
          (f) => f.buildMicros > budgetMicros || f.rasterMicros > budgetMicros)
      .length;
  return {
    kBenchBuildMean: builds.reduce((a, b) => a + b) / builds.length,
    kBenchBuildP90: builds[p90],
    kBenchRasterMean: rasters.reduce((a, b) => a + b) / rasters.length,
    kBenchRasterP90: rasters[p90],
    kBenchDroppedRatio: missed / frames.length,
    kBenchFrameCount: frames.length.toDouble(),
    kBenchRefreshRate: refreshRate,
  };
}

/// 在未提供 GC 汇总键的 SDK 上，从 [events] 统计新生代 GC 开始事件。
///
/// 完成事件 X 与开始事件 B/b 只计一次；结束 E/e 不计，防止成对翻倍。
int countNewGenerationGc(List<Map<String, Object?>> events) =>
    events.where((event) {
      final name = event['name'];
      final phase = event['ph'];
      return name is String &&
          (name.contains('Scavenge') ||
              name.contains('CollectNewGeneration')) &&
          const {'X', 'B', 'b'}.contains(phase);
    }).length;

/// 累计布局、录制事件毫秒数；同时支持 X 与按线程配对的 B/E。
///
/// [events] 必须按时间排序。缺失打点、未闭合或负时长均抛 [FormatException]。
double firstFrameMillis(List<Map<String, Object?>> events) {
  const names = {'luckdraw.layout', 'luckdraw.record'};
  final stacks = <Object?, List<({double start, bool measured})>>{};
  var total = 0.0;
  final found = <String>{};
  for (final event in events) {
    final phase = event['ph'];
    final thread = event['tid'];
    final measured = names.contains(event['name']);
    if (measured && const {'X', 'B'}.contains(phase)) {
      found.add(event['name']! as String);
    }
    if (phase == 'B') {
      (stacks[thread] ??= [])
          .add((start: benchNumber(event['ts'], 'ts'), measured: measured));
    } else if (phase == 'E' && (stacks[thread]?.isNotEmpty ?? false)) {
      final opening = stacks[thread]!.removeLast();
      if (opening.measured) {
        final duration = benchNumber(event['ts'], 'ts') - opening.start;
        total += benchNumber(duration, 'duration');
      }
    } else if (measured && phase == 'X') {
      total += benchNumber(event['dur'], 'dur');
    }
  }
  if (!found.containsAll(names) ||
      stacks.values.any((s) => s.any((opening) => opening.measured))) {
    throw const FormatException('缺少或未闭合布局/录制打点，请启用 LUCKDRAW_TIMELINE');
  }
  return total / Duration.microsecondsPerMillisecond;
}
