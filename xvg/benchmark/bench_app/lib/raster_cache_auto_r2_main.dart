import 'raster_cache_auto_bench.dart';

/// 从运行时批次计划启动第二轮真机基准。
Future<void> main() => const bool.fromEnvironment('XVG_AUTOMATIC_BENCH')
    ? runRasterCacheAutomatic()
    : runRasterCacheAutoR2();
