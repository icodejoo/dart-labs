import '../../videoman_platform_interface.dart';
import '../core/platform/ports.dart';

/// A [VmVolumePort] backed by the native `videoman` method channel, driving
/// the real system media volume (`[0, 100]`).
///
/// Only Android implements the channel methods today; on platforms without a
/// native implementation the channel returns null/false and this port becomes
/// a best-effort no-op (reporting 100). `createVmEngine` therefore only wires
/// it on Android and leaves iOS/desktop on the player-volume path — see
/// `wiring.dart`.
///
/// 基于原生 `videoman` method channel 的 [VmVolumePort]，驱动真实系统媒体
/// 音量（`[0, 100]`）。
///
/// 目前只有 Android 实现了这些通道方法；在无原生实现的平台上，通道返回
/// null/false，本端口退化为尽力而为的空操作（回报 100）。因此 `createVmEngine`
/// 只在 Android 上接入它，iOS/桌面保持播放器音量路径——见 `wiring.dart`。
class SystemVolumePort implements VmVolumePort {
  @override
  Future<double> get() async {
    final v = await VmPlatform.instance.getSystemVolume();
    return v ?? 100;
  }

  @override
  Future<void> set(double percent) async {
    await VmPlatform.instance.setSystemVolume(percent.clamp(0, 100));
  }
}
