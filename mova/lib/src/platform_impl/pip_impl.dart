import '../../mova_platform_interface.dart';
import '../core/platform/ports.dart';

/// A [MovaPipPort] implementation that forwards to [MovaPlat.instance]'s
/// method-channel calls.
///
/// 转发到 [MovaPlat.instance] 方法通道调用的 [MovaPipPort] 实现。
class ChannelPipPort implements MovaPipPort {
  @override
  Future<bool> isSupported() => MovaPlat.instance.isPipSupported();

  @override
  Future<bool> enter({int? width, int? height}) =>
      MovaPlat.instance.enterPip(width: width, height: height);
}
