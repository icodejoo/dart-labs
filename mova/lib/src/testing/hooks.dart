import '../core/kernel/kernel.dart';

/// The kernel factory `createMovaEngine()` consults before building its real
/// media_kit kernel. Always `null` in production; only `MovaTesting` sets it.
/// Deliberately not exported from the main barrel.
///
/// `createMovaEngine()` 在构建真实 media_kit 内核之前会先咨询的内核工厂。生产环境恒为
/// `null`；只有 `MovaTesting` 会设置它。刻意不从主 barrel 导出。
MovaKernel Function()? movaTestKernelFactory;
