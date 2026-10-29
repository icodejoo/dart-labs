/// 白盒测试及内核夹具入口；不从 lib/dioman.dart 导出。
library;

export 'client.dart' show DiomanDiagnostics;
export 'context.dart' show DiomanContextInternal;
export 'plugins/cache.dart' show DiomanCacheDiagnostics;
export 'plugins/share.dart' show DiomanShareApi, DiomanShareDiagnostics;
export 'response.dart' show DiomanResponseFactoryInternal;
