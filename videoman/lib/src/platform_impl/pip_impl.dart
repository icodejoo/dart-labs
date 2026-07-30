import '../../videoman_platform_interface.dart';
import '../core/platform/ports.dart';

/// A [VmPipPort] implementation that forwards to [VmPlatform.instance]'s
/// method-channel calls.
///
/// 转发到 [VmPlatform.instance] 方法通道调用的 [VmPipPort] 实现。
class ChannelPipPort implements VmPipPort {
  @override
  Future<bool> isSupported() => VmPlatform.instance.isPipSupported();

  @override
  Future<bool> enter({int? width, int? height}) =>
      VmPlatform.instance.enterPip(width: width, height: height);
}
