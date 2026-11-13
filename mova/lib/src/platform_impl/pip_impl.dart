import '../../mova_platform_interface.dart';
import '../core/platform/platform.dart';

/// A [IMovaPip] implementation that forwards to [MovaPlatform.instance]'s
/// method-channel calls.
///
/// 转发到 [MovaPlatform.instance] 方法通道调用的 [IMovaPip] 实现。
class MovaPip implements IMovaPip, IMovaPipObservable {
  @override
  Stream<bool> get changes => MovaPlatform.instance.pipChanges;

  @override
  Future<bool> isSupported() => MovaPlatform.instance.isPipSupported();

  @override
  Future<bool> enter({int? width, int? height}) =>
      MovaPlatform.instance.enterPip(width: width, height: height);
}
