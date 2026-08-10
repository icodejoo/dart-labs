import Flutter
import UIKit

/// Method-channel entry point for mova's iOS native surface.
///
/// `isPipSupported`/`enterPip` back [MovaPipController] (阶段0/1 skeleton, see
/// `doc/notes/2026-07-31-ios-pip-feasibility.md` §8) — real system PiP with
/// fake test-card frames on iOS 15+, `false`/no-op below that. This has not
/// been compiled or run on a real device; see `MovaPipController`'s doc
/// comment for what remains unverified.
///
/// mova iOS 原生侧的方法通道入口。
///
/// `isPipSupported`/`enterPip` 由 [MovaPipController]（阶段0/1骨架，见
/// `doc/notes/2026-07-31-ios-pip-feasibility.md` §8）支撑——iOS 15+ 上是喂假
/// 测试卡帧的真实系统 PiP，以下版本则为 `false`/空操作。本文件从未在真机上
/// 编译或运行过；尚待验证的部分见 `MovaPipController` 的文档注释。
public class MovaPlugin: NSObject, FlutterPlugin {
  /// Backing PiP skeleton, lazily created on iOS 15+ only; `nil` (and thus
  /// PiP always unsupported) below that OS version.
  ///
  /// 支撑的 PiP 骨架，仅在 iOS 15+ 惰性创建；低于该系统版本时为 `nil`（因此
  /// 画中画始终不支持）。
  private var pipController: Any?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mova", binaryMessenger: registrar.messenger())
    let instance = MovaPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "isPipSupported":
      result(currentIsPipSupported())
    case "enterPip":
      let args = call.arguments as? [String: Any]
      result(startPip(width: args?["width"] as? Int, height: args?["height"] as? Int))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Native-capability probe backing the `isPipSupported` method call.
  ///
  /// NOTE: this reports the *native* skeleton's real capability. The Dart
  /// side (`MethodChannelMova.isPipSupported()` in `lib/mova_method_channel.dart`)
  /// deliberately does NOT forward this value on iOS yet — per
  /// `doc/notes/2026-07-31-ios-pip-feasibility.md`'s SPEC guidance,
  /// `MovaApi.pipSupported` must keep reporting `false` on iOS until a real
  /// device verifies frame delivery + audio session + background
  /// continuation (阶段5, not done). Native code is wired ahead of that gate
  /// so a human with Xcode only needs to flip the Dart-side gate once 阶段5
  /// passes, rather than write this from scratch.
  ///
  /// 支撑 `isPipSupported` 方法调用的原生能力探测。
  ///
  /// 注意：这里回报的是**原生**骨架的真实能力。Dart 侧
  /// （`lib/mova_method_channel.dart` 的 `MethodChannelMova.isPipSupported()`）
  /// 目前刻意不在 iOS 上转发这个值——按
  /// `doc/notes/2026-07-31-ios-pip-feasibility.md` 的 SPEC 指导，
  /// `MovaApi.pipSupported` 在真机验证过取帧+音频会话+后台续播（阶段5，尚未
  /// 完成）之前必须继续在 iOS 上回报 `false`。原生代码提前把这道门槛之前的部分
  /// 接好，这样阶段5通过后，持有 Xcode 的人只需翻转 Dart 侧的这道门，而不必
  /// 从零再写一遍。
  private func currentIsPipSupported() -> Bool {
    if #available(iOS 15.0, *) {
      return MovaPipController.isSupported
    }
    return false
  }

  /// Starts the fake-frame PiP skeleton on iOS 15+; no-op `false` below that.
  ///
  /// 在 iOS 15+ 上启动假帧 PiP 骨架；低于该版本则空操作回报 `false`。
  private func startPip(width: Int?, height: Int?) -> Bool {
    if #available(iOS 15.0, *) {
      let controller = (pipController as? MovaPipController) ?? MovaPipController()
      pipController = controller
      return controller.start(width: width, height: height)
    }
    return false
  }
}
