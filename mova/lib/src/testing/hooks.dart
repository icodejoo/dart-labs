import 'dart:typed_data';

import '../core/preview/fetcher.dart';
import '../core/kernel/kernel.dart';

/// The kernel factory `createMova()` consults before building its real
/// media_kit kernel. Always `null` in production; only `MovaTesting` sets it.
/// Deliberately not exported from the main barrel.
///
/// `createMova()` 在构建真实 media_kit 内核之前会先咨询的内核工厂。生产环境恒为
/// `null`；只有 `MovaTesting` 会设置它。刻意不从主 barrel 导出。
IMovaKernel Function()? movaTestKernelFactory;

/// 测试接缝默认的空 HTTP 端口，不创建网络连接或超时计时器。
/// 示例：`createMova(fetcher: const MovaTestHttpFetch())`。
class MovaTestHttpFetch implements IMovaHttpFetch {
  /// 创建无资源的空端口。
  const MovaTestHttpFetch();

  /// 对任意 [url] 返回 null，模拟没有辅助资源。
  @override
  Future<Uint8List?> get(Uri url) async => null;

  /// 释放空端口，返回已完成任务。
  @override
  Future<void> close() async {}
}
