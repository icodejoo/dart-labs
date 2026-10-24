import 'hooks.dart';
import 'test_kernel.dart';

/// Switches `createMovaEngine()` to [MovaTestKernel]s for the current test, so
/// widgets that build their engine through it (`MovaView`, or your own code)
/// can be pumped without `MediaKit.ensureInitialized()`.
///
/// 在当前测试里把 `createMovaEngine()` 切换为使用 [MovaTestKernel]，让经由它构建引擎的
/// 组件（`MovaView` 或你自己的代码）无需 `MediaKit.ensureInitialized()` 即可 pump。
///
/// Example / 示例:
/// ```dart
/// setUp(MovaTesting.useTestKernels);
/// tearDown(MovaTesting.reset);
/// ```
abstract final class MovaTesting {
  static final List<MovaTestKernel> _kernels = <MovaTestKernel>[];

  /// While installed, `createMovaEngine()` builds `MovaEngine(kernel: factory())`
  /// with no-op platform ports and a memory-only thumbnail cache; an explicitly
  /// passed `kernel:`/port still wins.
  ///
  /// 安装期间，`createMovaEngine()` 构建 `MovaEngine(kernel: factory())`，平台端口用空
  /// 实现、缩略图只用内存缓存；显式传入的 `kernel:`/端口仍然优先。
  ///
  /// - [factory]: builds each kernel; defaults to a plain [MovaTestKernel] / 构建每个内核；默认是普通的 [MovaTestKernel]
  static void useTestKernels([MovaTestKernel Function()? factory]) {
    final make = factory ?? MovaTestKernel.new;
    movaTestKernelFactory = () {
      final k = make();
      _kernels.add(k);
      return k;
    };
  }

  /// Kernels created since [useTestKernels], oldest first.
  ///
  /// 自 [useTestKernels] 以来创建的内核，按创建顺序。
  static List<MovaTestKernel> get kernels => List<MovaTestKernel>.unmodifiable(_kernels);

  /// The most recently created kernel, or `null` if none yet.
  ///
  /// 最近创建的内核；还没有时为 `null`。
  static MovaTestKernel? get lastKernel => _kernels.isEmpty ? null : _kernels.last;

  /// Whether [useTestKernels] is currently installed.
  ///
  /// 当前是否已安装 [useTestKernels]。
  static bool get active => movaTestKernelFactory != null;

  /// Uninstalls and forgets every kernel.
  ///
  /// 卸载并清空已记录的内核。
  static void reset() {
    movaTestKernelFactory = null;
    _kernels.clear();
  }
}
