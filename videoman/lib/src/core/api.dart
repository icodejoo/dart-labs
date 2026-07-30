import 'events/events.dart';
import 'model/fit.dart';
import 'model/quality.dart';
import 'model/source.dart';
import 'options/options.dart';
import 'state/progress.dart';
import 'state/state.dart';
import 'state/ui_state.dart';

/// The capability surface the UI layer depends on.
///
/// This is the sole abstraction the `controls` layer (widgets, gestures,
/// skins) is allowed to talk to — it never reaches into [VmKernel] or any
/// concrete implementation directly. Production code is backed by the
/// kernel-driven implementation; tests use `FakeVmApi`.
///
/// UI 层依赖的唯一能力面。
///
/// 这是 `controls` 层（组件、手势、皮肤）唯一允许打交道的抽象——它绝不会
/// 直接触达 [VmKernel] 或任何具体实现。生产环境由内核驱动的实现支撑；
/// 测试用 `FakeVmApi`。
abstract class VmApi {
  /// Discrete, low-frequency lifecycle/change events (source changed,
  /// quality switched, errors, …).
  ///
  /// 离散、低频的生命周期/变更事件（源变化、清晰度切换、错误等）。
  Stream<VmEvent> get events;

  /// Deduplicated snapshots of playback state.
  ///
  /// 去重后的播放状态快照流。
  Stream<VmState> get states;

  /// Throttled position/buffer progress updates.
  ///
  /// 节流后的位置/缓冲进度更新流。
  Stream<VmProgress> get progress;

  /// Control-bar visibility, HUD, and preview-position updates.
  ///
  /// 控制条可见性、HUD、预览位置的更新流。
  Stream<VmUiState> get uiStates;

  /// The current playback state snapshot, synchronously available so the
  /// first frame never flashes an empty/default state.
  ///
  /// 当前播放状态快照，同步可取，避免首帧闪一下空/默认状态。
  VmState get state;

  /// The current UI state snapshot.
  ///
  /// 当前 UI 状态快照。
  VmUiState get uiState;

  /// The configuration this instance was constructed with.
  ///
  /// 构造该实例时使用的配置。
  VmOptions get options;

  /// Title of the currently open source, or null before [open] / when the
  /// source has none.
  ///
  /// 当前已打开源的标题；[open] 之前或源未提供标题时为 null。
  String? get sourceTitle;

  /// Opens [source] for playback.
  ///
  /// [source] is the media to load. [autoPlay] controls whether playback
  /// starts immediately after opening; defaults to `true`.
  ///
  /// 打开 [source] 以播放。
  ///
  /// [source] 为要加载的媒体来源。[autoPlay] 控制打开后是否立即播放；
  /// 默认 `true`。
  Future<void> open(VmSource source, {bool autoPlay = true});

  /// Resumes/starts playback.
  ///
  /// 恢复/开始播放。
  Future<void> play();

  /// Pauses playback.
  ///
  /// 暂停播放。
  Future<void> pause();

  /// Toggles between playing and paused.
  ///
  /// 在播放与暂停之间切换。
  Future<void> playOrPause();

  /// Seeks to an absolute position.
  ///
  /// [to] is the target position to seek to.
  ///
  /// 跳转到一个绝对位置。
  ///
  /// [to] 为要跳转到的目标位置。
  Future<void> seek(Duration to);

  /// Seeks relative to the current position.
  ///
  /// [delta] is the offset to apply to the current position; may be
  /// negative to seek backwards.
  ///
  /// 相对当前位置跳转。
  ///
  /// [delta] 为相对当前位置的偏移量；可为负以向后跳转。
  Future<void> seekBy(Duration delta);

  /// Sets playback volume.
  ///
  /// [v] is the volume level in the 0–100 range.
  ///
  /// 设置播放音量。
  ///
  /// [v] 为音量值，取值范围 0–100。
  Future<void> setVolume(double v);

  /// Sets screen brightness.
  ///
  /// [v] is the brightness level in the 0–1 range.
  ///
  /// 设置屏幕亮度。
  ///
  /// [v] 为亮度值，取值范围 0–1。
  Future<void> setBrightness(double v);

  /// Sets playback rate.
  ///
  /// [r] is the playback speed multiplier, e.g. `1.0` for normal speed.
  ///
  /// 设置播放倍速。
  ///
  /// [r] 为播放速度倍数，例如 `1.0` 表示正常速度。
  Future<void> setRate(double r);

  /// Sets the video fill/fit mode.
  ///
  /// [f] is the fit mode to apply.
  ///
  /// 设置视频填充/观看模式。
  ///
  /// [f] 为要应用的观看模式。
  Future<void> setFit(VmFit f);

  /// Sets the pinch-zoom scale factor.
  ///
  /// [z] is the zoom factor to apply.
  ///
  /// 设置双指缩放的缩放系数。
  ///
  /// [z] 为要应用的缩放系数。
  Future<void> setZoom(double z);

  /// Locks or unlocks gesture/control interaction.
  ///
  /// [v] is `true` to lock, `false` to unlock.
  ///
  /// 锁定或解锁手势/控制交互。
  ///
  /// [v] 为 `true` 表示锁定，`false` 表示解锁。
  Future<void> setLocked(bool v);

  /// Enters or exits fullscreen mode.
  ///
  /// [v] is `true` to enter fullscreen, `false` to exit.
  ///
  /// 进入或退出全屏模式。
  ///
  /// [v] 为 `true` 表示进入全屏，`false` 表示退出。
  Future<void> setFullscreen(bool v);

  /// Loads the available quality list for the current source, if any.
  ///
  /// 加载当前源可用的清晰度列表（若有）。
  Future<void> loadQualities();

  /// Switches to a specific quality.
  ///
  /// [q] is the quality to switch to.
  ///
  /// 切换到指定清晰度。
  ///
  /// [q] 为要切换到的清晰度。
  Future<void> switchQuality(VmQuality q);

  /// Attempts to enter system picture-in-picture mode.
  ///
  /// Returns `true` if PiP was entered, `false` if unsupported or refused.
  ///
  /// 尝试进入系统级画中画模式。
  ///
  /// 返回 `true` 表示已进入画中画，`false` 表示不支持或被拒绝。
  Future<bool> enterPip();

  /// Reloads the current source from scratch (e.g. after a fatal error).
  ///
  /// 从头重新加载当前源（例如发生致命错误后）。
  Future<void> reload();

  /// Seeks a live stream back to the live edge, clearing any timeshift.
  ///
  /// 将直播流跳回直播边缘，清除时移状态。
  Future<void> backToLiveEdge();

  /// Shows the control bar/overlay.
  ///
  /// [sticky] is `true` to keep it visible without the usual auto-hide
  /// timer; defaults to `false`.
  ///
  /// 显示控制条/浮层。
  ///
  /// [sticky] 为 `true` 表示保持常显、不启用自动隐藏计时；默认 `false`。
  void showControls({bool sticky = false});

  /// Hides the control bar/overlay.
  ///
  /// 隐藏控制条/浮层。
  void hideControls();

  /// Shows a transient HUD overlay.
  ///
  /// [hud] is the HUD variant to display.
  ///
  /// 显示一个临时 HUD 浮层。
  ///
  /// [hud] 为要展示的 HUD 类型。
  void showHud(VmHud hud);

  /// Updates the drag-gesture-in-progress flag and optional seek-preview
  /// position.
  ///
  /// [v] is `true` while a drag gesture (seek/volume/brightness) is in
  /// progress. [previewAt] is the seek-preview position to show while
  /// dragging, or `null` to hide it.
  ///
  /// 更新拖动手势进行中标志及可选的预览位置。
  ///
  /// [v] 为 `true` 表示拖动手势（进度/音量/亮度）正在进行。[previewAt] 为
  /// 拖动过程中要展示的预览位置，`null` 表示不展示。
  void setDragging(bool v, {Duration? previewAt});

  /// Releases all resources held by this instance; must be called exactly
  /// once when the player is torn down.
  ///
  /// 释放该实例持有的所有资源；播放器销毁时必须且只能调用一次。
  Future<void> dispose();
}
