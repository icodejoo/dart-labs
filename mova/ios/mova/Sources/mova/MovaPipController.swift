import AVFoundation
import AVKit
import CoreVideo
import Foundation

/// iOS 阶段0/1 骨架：`AVSampleBufferDisplayLayer` + `AVPictureInPictureController`
/// system PiP skeleton, fed with solid-color test-card frames only.
///
/// Corresponds to `doc/notes/2026-07-31-ios-pip-feasibility.md` §8 阶段1 —
/// "假帧先跑通" (get PiP启停/audio session/background-continuation working with
/// fake frames first, before real libmpv frame plumbing lands in 阶段2). This
/// class deliberately does NOT touch libmpv/media_kit: every enqueued frame is
/// a synthetic solid-color `CVPixelBuffer` produced on a timer, matching the
/// spike plan's own first step. Real-device verification (阶段0/阶段5) has not
/// happened — nothing here has been compiled or run; see the plugin's
/// `handle(_:result:)` for how the Dart-facing `isPipSupported` gate keeps
/// reporting `false` regardless of what this class can do, until that
/// verification lands.
///
/// iOS 阶段0/1 骨架：`AVSampleBufferDisplayLayer` +
/// `AVPictureInPictureController` 系统画中画骨架，仅喂纯色测试卡假帧。
///
/// 对应 `doc/notes/2026-07-31-ios-pip-feasibility.md` §8 阶段1——"假帧先跑通"
/// （先用假帧跑通 PiP 启停/音频会话/后台续播，真实 libmpv 取帧要到阶段2才接）。
/// 本类刻意不碰 libmpv/media_kit：每一帧都是定时器产出的合成纯色
/// `CVPixelBuffer`，与 spike 计划自己的第一步一致。真机验证（阶段0/阶段5）尚未
/// 进行——这里的代码从未编译或运行过；Dart 侧 `isPipSupported` 网关如何无视本类
/// 的能力、始终回报 `false`，直到真机验证落地，见插件的 `handle(_:result:)`。
@available(iOS 15.0, *)
final class MovaPipController: NSObject {
  /// Whether the current OS/device combination can in principle support this
  /// ASBDL-based PiP skeleton. Always `AVPictureInPictureController.isPictureInPictureSupported()`
  /// on iOS 15+; simulators report `false` here too (Apple: PiP is
  /// real-device-only), matching §4 "模拟器不支持 PiP".
  ///
  /// 当前系统/设备组合原则上能否支持这套基于 ASBDL 的 PiP 骨架。iOS 15+ 上就是
  /// `AVPictureInPictureController.isPictureInPictureSupported()`；模拟器在这里
  /// 也会报告 `false`（Apple 官方：PiP 仅支持真机），对应 §4"模拟器不支持 PiP"。
  static var isSupported: Bool {
    AVPictureInPictureController.isPictureInPictureSupported()
  }

  /// The layer PiP actually reads frames from.
  ///
  /// PiP 实际读取帧的图层。
  private let displayLayer = AVSampleBufferDisplayLayer()

  /// Drives PiP start/stop and receives the transport-control callbacks in
  /// [MovaPipController]'s `AVPictureInPictureSampleBufferPlaybackDelegate`
  /// conformance below.
  ///
  /// 驱动 PiP 启停，并接收下方 [MovaPipController] 对
  /// `AVPictureInPictureSampleBufferPlaybackDelegate` 遵从中的传输控制回调。
  private var pipController: AVPictureInPictureController?

  /// Fires on a fixed cadence to enqueue the next fake test-card frame while
  /// PiP is active.
  ///
  /// 在 PiP 激活期间按固定节奏触发，入队下一帧假测试卡画面。
  private var frameTimer: Timer?

  /// Monotonically increasing fake presentation timestamp, in the frame
  /// timer's tick units — real PTS from libmpv lands in 阶段2.
  ///
  /// 单调递增的假显示时间戳，单位为帧定时器的 tick——真实 PTS 要到阶段2接入
  /// libmpv 才有。
  private var frameCount: Int64 = 0

  /// Starts the PiP skeleton: configures the audio session, builds the
  /// `AVPictureInPictureController.ContentSource`, and starts pumping fake
  /// solid-color frames into the display layer.
  ///
  /// - [width], [height]: aspect-ratio hint from the Dart side (see
  ///   `MovaApi.enterPip`); defaults to a 16:9 test-card size when absent.
  ///
  /// Returns whether PiP was requested to start — mirrors `startPictureInPicture()`
  /// being callable at all (`AVPictureInPictureController.isPictureInPictureSupported()`);
  /// actual PiP window presentation is asynchronous and reported via the
  /// controller's delegate, which this skeleton does not yet forward back to
  /// Dart (`// TODO(spike)`: wire pip start/stop callbacks to a Flutter event
  /// channel once 阶段2 lands real frames worth watching).
  ///
  /// 启动 PiP 骨架：配置音频会话、构建
  /// `AVPictureInPictureController.ContentSource`，并开始向显示图层灌入假纯色
  /// 帧。
  ///
  /// - [width], [height]：来自 Dart 侧的宽高比提示（见 `MovaApi.enterPip`）；
  ///   缺省时使用 16:9 测试卡尺寸。
  ///
  /// 返回是否已发起 PiP 启动请求——对应 `startPictureInPicture()`
  /// 本身是否可调用（`AVPictureInPictureController.isPictureInPictureSupported()`）；
  /// 实际 PiP 窗口呈现是异步的、经由 controller 的 delegate 回报，本骨架尚未
  /// 把它转发回 Dart（`// TODO(spike)`：待阶段2接入真实、值得观看的帧后，再把
  /// PiP 启停回调接到 Flutter 事件通道）。
  func start(width: Int?, height: Int?) -> Bool {
    guard MovaPipController.isSupported else { return false }

    do {
      // Hard requirement per the note's §4: PiP will not start in the
      // background without this, even when muted.
      //
      // 笔记 §4 的硬性要求：没有这步，即使静音，App 退后台时 PiP 也不会启动。
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback)
      try session.setActive(true)
    } catch {
      return false
    }

    let w = width ?? 1920
    let h = height ?? 1080
    displayLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)

    let contentSource = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: displayLayer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: contentSource)
    controller.canStartPictureInPictureAutomaticallyFromInline = true
    pipController = controller

    frameCount = 0
    frameTimer?.invalidate()
    // 30fps test-card cadence — plenty for a solid-color placeholder; real
    // cadence follows the source's actual frame rate once 阶段2 wires libmpv.
    //
    // 30fps 的测试卡节奏——对纯色占位画面绰绰有余；真实节奏要等阶段2接入
    // libmpv 后跟随片源实际帧率。
    frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
      self?.enqueueNextFrame(width: w, height: h)
    }

    controller.startPictureInPicture()
    return true
  }

  /// Stops the frame timer and PiP session, if either is active.
  ///
  /// 停止帧定时器与 PiP 会话（若正在运行）。
  func stop() {
    frameTimer?.invalidate()
    frameTimer = nil
    pipController?.stopPictureInPicture()
    pipController = nil
    displayLayer.flushAndRemoveImage()
  }

  /// Builds one synthetic solid-color `CVPixelBuffer` frame, wraps it into a
  /// `CMSampleBuffer` with a monotonically increasing fake PTS, and enqueues
  /// it onto [displayLayer].
  ///
  /// 构建一帧合成纯色 `CVPixelBuffer`，包上带单调递增假 PTS 的
  /// `CMSampleBuffer`，入队到 [displayLayer]。
  private func enqueueNextFrame(width: Int, height: Int) {
    guard let pixelBuffer = MovaPipController.makeSolidColorPixelBuffer(width: width, height: height) else {
      return
    }
    guard let sampleBuffer = MovaPipController.makeSampleBuffer(
      pixelBuffer: pixelBuffer,
      presentationTick: frameCount
    ) else {
      return
    }
    frameCount += 1
    if displayLayer.isReadyForMoreMediaData {
      displayLayer.enqueue(sampleBuffer)
    }
  }

  /// Creates a `kCVPixelFormatType_32BGRA` pixel buffer filled with a fixed
  /// dark test-card color.
  ///
  /// 创建一个填充固定深色测试卡颜色的 `kCVPixelFormatType_32BGRA` 像素缓冲。
  private static func makeSolidColorPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer
    )
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    if let base = CVPixelBufferGetBaseAddress(buffer) {
      let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
      // Fixed dark-gray test-card fill (B, G, R, A) — a placeholder, not a
      // themed color; real frames replace this entirely in 阶段2.
      //
      // 固定深灰色测试卡填充（B、G、R、A）——只是占位，不是主题色；阶段2会
      // 用真实帧完全替换。
      let pattern: [UInt8] = [0x33, 0x33, 0x33, 0xFF]
      let row = UnsafeMutableRawPointer(base)
      for y in 0..<height {
        let rowPtr = row.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
        for x in 0..<width {
          rowPtr[x * 4 + 0] = pattern[0]
          rowPtr[x * 4 + 1] = pattern[1]
          rowPtr[x * 4 + 2] = pattern[2]
          rowPtr[x * 4 + 3] = pattern[3]
        }
      }
    }
    return buffer
  }

  /// Wraps [pixelBuffer] into a displayable `CMSampleBuffer` with a fake PTS
  /// derived from [presentationTick] at the fixed 30fps test-card cadence.
  ///
  /// 把 [pixelBuffer] 包装成可显示的 `CMSampleBuffer`，PTS 由 [presentationTick]
  /// 按固定 30fps 测试卡节奏推导（假值）。
  private static func makeSampleBuffer(pixelBuffer: CVPixelBuffer, presentationTick: Int64) -> CMSampleBuffer? {
    var formatDescription: CMVideoFormatDescription?
    let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let format = formatDescription else { return nil }

    let pts = CMTime(value: presentationTick, timescale: 30)
    var timingInfo = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: pts,
      decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      dataReady: true,
      makeDataReadyCallback: nil,
      refcon: nil,
      formatDescription: format,
      sampleTiming: &timingInfo,
      sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
  }
}

/// Transport-control stubs required by `AVPictureInPictureController` to
/// treat this as a valid sample-buffer content source. All bodies are
/// no-op/best-guess placeholders — real play/pause/seek wiring depends on
/// 阶段2's not-yet-landed frame pump reporting real playback state back here.
///
/// `// TODO(spike)`: once 阶段2 lands, forward these to `MovaApi`
/// (play/pause/seek) via the plugin's method channel and reflect real
/// position/duration instead of the placeholder `CMTimeRange` below.
///
/// `AVPictureInPictureController` 要求实现的传输控制桩——只有实现这些，才能
/// 被当作合法的 sample-buffer 内容源。所有方法体都是空实现/最佳猜测占位——真实
/// 的播放/暂停/跳转接线依赖阶段2尚未落地的帧推送把真实播放状态回报到这里。
///
/// `// TODO(spike)`：阶段2落地后，把这些回调经插件方法通道转发给 `MovaApi`
/// （play/pause/seek），并用真实的位置/时长替换下面的占位 `CMTimeRange`。
@available(iOS 15.0, *)
extension MovaPipController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    // TODO(spike): forward to MovaApi.play()/pause() once 阶段2 wires real
    // playback state through this controller.
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    // Placeholder: reports an effectively-unbounded live-like range so PiP's
    // transport UI doesn't assume a fixed VOD duration it doesn't have yet.
    //
    // 占位：回报一个近似无界的类直播区间，避免 PiP 传输控件条 UI 假设一个
    // 尚不存在的固定点播时长。
    CMTimeRange(start: .zero, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    // TODO(spike): report MovaApi.state.playing's inverse once wired.
    false
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    // No-op: nothing to resize yet since frames are a fixed-size test card.
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    // TODO(spike): forward to MovaApi.seekBy(skipInterval) once wired.
    completionHandler()
  }

  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    false
  }
}
