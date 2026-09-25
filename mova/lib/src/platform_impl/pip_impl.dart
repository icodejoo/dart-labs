import '../../mova_platform_interface.dart';
import '../core/platform/ports.dart';

/// A [MovaPipPort] implementation that forwards to [MovaPlatform.instance]'s
/// method-channel calls.
///
/// 转发到 [MovaPlatform.instance] 方法通道调用的 [MovaPipPort] 实现。
class MovaChannelPipPort implements MovaPipPort {
  @override
  Future<bool> isSupported() => MovaPlatform.instance.isPipSupported();

  @override
  Future<bool> enter({int? width, int? height}) =>
      MovaPlatform.instance.enterPip(width: width, height: height);
}
