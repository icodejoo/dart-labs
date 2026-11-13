import '../../mova_platform_interface.dart';
import '../core/platform/platform.dart';

/// Full system media volume, in percent. / 系统媒体满音量的百分比。
const double _maxVolume = 100;

/// A [IMovaVolume] backed by the native `mova` method channel, driving
/// the real system media volume (`[0, 100]`).
///
/// Only Android implements the channel methods today; on platforms without a
/// native implementation the channel returns null/false and this port becomes
/// a best-effort no-op (reporting 100). `createMova` therefore only wires
/// it on Android and leaves iOS/desktop on the player-volume path — see
/// `wiring.dart`.
///
/// 基于原生 `mova` method channel 的 [IMovaVolume]，驱动真实系统媒体
/// 音量（`[0, 100]`）。
///
/// 目前只有 Android 实现了这些通道方法；在无原生实现的平台上，通道返回
/// null/false，本端口退化为尽力而为的空操作（回报 100）。因此 `createMova`
/// 只在 Android 上接入它，iOS/桌面保持播放器音量路径——见 `wiring.dart`。
class MovaSystemVolume implements IMovaVolume {
  /// Reads system volume, falling back to full volume.
  ///
  /// 读取系统音量，缺省时返回满音量。
  @override
  Future<double> get() async {
    final v = await MovaPlatform.instance.getSystemVolume();
    return v ?? _maxVolume;
  }

  /// Clamps the requested percent before forwarding it to the platform.
  ///
  /// 将请求百分比限制在有效范围后转发至平台。
  @override
  Future<void> set(double percent) async {
    await MovaPlatform.instance.setSystemVolume(percent.clamp(0, _maxVolume));
  }
}
