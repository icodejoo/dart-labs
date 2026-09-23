import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/mini/placement.dart';
import '../skins/skin.dart';
import 'mini_skin.dart';
import 'mini_window.dart';

/// How the mini window is mounted into the widget tree.
///
/// 小窗以何种方式挂进 widget 树。
enum MovaMiniMount {
  /// Not mounted. / 未挂载。
  none,

  /// Inserted as an [OverlayEntry] into the nearest ancestor [Overlay]
  /// (in-page floating; disappears with its page).
  ///
  /// 作为 [OverlayEntry] 插入最近祖先 [Overlay]（页内悬浮，随页面消失）。
  page,

  /// Rendered by a host-level [Stack] under `MaterialApp.builder`
  /// (survives route changes).
  ///
  /// 由 `MaterialApp.builder` 下的宿主级 [Stack] 渲染（跨路由存活）。
  persistent,
}

/// The route-independent holder of whatever is currently playing in the mini
/// window.
///
/// Lives outside the [Navigator] (a host-level singleton, or provided however
/// the host prefers) so that popping the page that started playback does not
/// take the engine down with it. It **borrows** the [MovaApi] — it never
/// creates and never disposes one; disposing stays the host's job, exactly as
/// with `MovaPlayer`.
///
/// 当前在小窗里播放的内容的持有者，独立于路由。
///
/// 它活在 [Navigator] 之外（宿主级单例，或宿主偏好的任何注入方式），使得弹出
/// 发起播放的那个页面不会把引擎一起带走。它**借用** [MovaApi]——既不创建也不
/// 销毁；销毁仍然是宿主的职责，与 `MovaPlayer` 的约定完全一致。
///
/// Example / 示例:
/// ```dart
/// final mini = MovaMiniCtl();
///
/// // 方式 A：页内悬浮（mova 负责插 OverlayEntry）
/// await mini.showInPage(context, api);
///
/// // 方式 B：跨路由持久（宿主自己在 MaterialApp.builder 里放 Stack）
/// // MaterialApp(builder: (c, child) => MovaMiniHost(ctl: mini, child: child!))
/// await mini.show(api, skin: const MovaMiniSkin());
/// Navigator.of(context).pop();   // 引擎不受影响，画面在小窗里继续
/// ```
class MovaMiniCtl extends ChangeNotifier {
  MovaApi? _api;
  MovaSkin _skin = const MovaMiniSkin();
  MovaMiniRect? _rect;
  MovaMiniMount _mount = MovaMiniMount.none;
  OverlayEntry? _entry;

  /// The api currently rendered in the mini window; `null` when hidden.
  ///
  /// 当前渲染在小窗里的 api；隐藏时为 `null`。
  MovaApi? get api => _api;

  /// The skin used inside the mini window.
  ///
  /// 小窗内使用的皮肤。
  MovaSkin get skin => _skin;

  /// The window's current rectangle; `null` before the first layout.
  ///
  /// 小窗当前矩形；首次布局前为 `null`。
  MovaMiniRect? get rect => _rect;

  /// How the window is currently mounted; [MovaMiniMount.none] when hidden.
  ///
  /// 当前挂载方式；隐藏时为 [MovaMiniMount.none]。
  MovaMiniMount get mount => _mount;

  /// Called after [close]; the host's hook for disposing the engine.
  ///
  /// [close] 之后触发；宿主销毁引擎的挂钩。
  void Function(MovaApi api)? onClosed;

  /// Hands [api] to the mini window and flips `MovaState.mini` on, **without
  /// mounting anything itself** — a host-level [Stack] (e.g. `MovaMiniHost`
  /// under `MaterialApp.builder`) is what renders it. Mount B / 方式 B。
  ///
  /// Idempotent for the same [api]. Showing a different [api] while one is
  /// already up first flips the previous one's `mini` back off (it is never
  /// disposed here).
  ///
  /// 把 [api] 交给小窗并置起 `MovaState.mini`，但**自己不挂载任何东西**——
  /// 真正渲染它的是宿主级 [Stack]（例如 `MaterialApp.builder` 下的
  /// `MovaMiniHost`）。即方式 B。
  ///
  /// 同一个 [api] 重复调用是幂等的。已有小窗时 show 另一个 [api]，会先把前一个
  /// 的 `mini` 置回 false（此处永不 dispose 它）。
  Future<void> show(MovaApi api, {MovaSkin skin = const MovaMiniSkin()}) async {
    if (identical(_api, api) && _mount == MovaMiniMount.persistent) return;
    await _switchTo(api, skin);
    _detachEntry();
    _mount = MovaMiniMount.persistent;
    notifyListeners();
  }

  /// Same as [show], but also inserts an [OverlayEntry] into the [Overlay]
  /// nearest to [context], so the window floats inside that page — free of the
  /// page's own scrolling and layout. Mount A / 方式 A。
  ///
  /// The entry lives and dies with that page's [Overlay]: popping the page
  /// takes the window with it, which is exactly what in-page floating means.
  /// For a window that must survive route changes use [show] + a host-level
  /// [Stack] instead (see README); passing [rootOverlay] `true` is **not** the
  /// way to get that — an entry in the root overlay is buried by the next
  /// `push`.
  ///
  /// The page **must** call [hide] or [close] in its `dispose()`, otherwise
  /// `MovaState.mini` stays `true` with nothing rendering it.
  ///
  /// 与 [show] 相同，但额外向离 [context] 最近的 [Overlay] 插入一个
  /// [OverlayEntry]，使小窗悬浮在那个页面内部——不受该页面自身滚动与布局影响。
  /// 即方式 A。
  ///
  /// entry 与该页面的 [Overlay] 同生共死：页面被 pop，小窗随之消失——这正是
  /// "页内悬浮"的语义。需要跨路由存活请改用 [show] + 宿主级 [Stack]（见
  /// README）；把 [rootOverlay] 传 `true` **不是**实现它的办法——插在根 overlay
  /// 里的 entry 会被下一次 `push` 埋掉。
  ///
  /// 页面**必须**在 `dispose()` 里调一次 [hide] 或 [close]，否则
  /// `MovaState.mini` 会停在 `true` 而无人渲染。
  ///
  /// - [context]: locates the target [Overlay] / 用于定位目标 [Overlay]
  /// - [api]: the borrowed engine / 借用的引擎
  /// - [skin]: chrome inside the window / 小窗内的皮肤
  /// - [rootOverlay]: insert into the root overlay instead / 改插根 overlay
  ///
  /// Example / 示例:
  /// ```dart
  /// // 列表页里点"小窗播放"：
  /// await mini.showInPage(context, api);
  /// // 页面 dispose 里：
  /// if (mini.isShowing(api)) await mini.hide();
  /// ```
  Future<void> showInPage(
    BuildContext context,
    MovaApi api, {
    MovaSkin skin = const MovaMiniSkin(),
    bool rootOverlay = false,
  }) async {
    final cfg = api.options.mini;
    if (!cfg.enabled) return; // 关闭态硬约束：不插 entry、不改任何状态
    // 提前解析目标 Overlay：await 之后不再触碰 context，避免跨异步间隙使用它。
    final overlay = Overlay.of(context, rootOverlay: rootOverlay);
    await _switchTo(api, skin);
    _detachEntry();
    _entry = OverlayEntry(
      // 不用 Positioned/maintainState：MovaMiniWindow 自己是全屏 Stack，
      // RenderTheatre 给未定位 child 的是 tight 约束（= Overlay 尺寸）。
      builder: (_) => MovaMiniWindow(ctl: this, api: api, config: cfg),
    );
    overlay.insert(_entry!);
    _mount = MovaMiniMount.page;
    notifyListeners();
  }

  /// Common "hand [api] over" logic shared by [show]/[showInPage]: leaves the
  /// previous api's mini state, seeds the new one's, resets [_rect].
  ///
  /// [show]/[showInPage] 共用的"交接 [api]"逻辑：退出旧 api 的小窗态，置起新
  /// api 的小窗态，重置 [_rect]。
  Future<void> _switchTo(MovaApi api, MovaSkin skin) async {
    if (!identical(_api, api)) {
      final prev = _api;
      _api = api;
      _skin = skin;
      _rect = null;
      if (prev != null) await prev.setMini(false);
      await api.setMini(true);
    } else {
      _skin = skin;
    }
  }

  /// Takes the picture back out of the mini window, leaving playback running.
  ///
  /// Use this when the user taps the window to return to the full page: the
  /// page remounts a `MovaPlayer` on the same api and playback never stops.
  ///
  /// 把画面从小窗里收回，播放继续。
  ///
  /// 用户点小窗回到整页时用它：页面用同一个 api 重新挂载 `MovaPlayer`，
  /// 播放全程不中断。
  Future<void> hide() async {
    final api = _api;
    if (api == null) return;
    _detachEntry();
    _api = null;
    _rect = null;
    _mount = MovaMiniMount.none;
    notifyListeners();
    await api.setMini(false);
  }

  /// Closes the mini window and pauses playback, then notifies [onClosed].
  ///
  /// Still does not dispose the api — the host decides that in [onClosed].
  ///
  /// 关闭小窗并暂停播放，随后回调 [onClosed]。
  ///
  /// 仍然不 dispose api——由宿主在 [onClosed] 里决定。
  Future<void> close() async {
    final api = _api;
    if (api == null) return;
    _detachEntry();
    _api = null;
    _rect = null;
    _mount = MovaMiniMount.none;
    notifyListeners();
    await api.pause();
    await api.setMini(false);
    onClosed?.call(api);
  }

  /// Whether [candidate] is the api the mini window currently renders.
  ///
  /// Page `dispose()` should consult this before disposing its engine.
  ///
  /// [candidate] 是否就是小窗当前渲染的那个 api。
  /// 页面 `dispose()` 在销毁引擎前应先问这一句。
  bool isShowing(MovaApi candidate) => identical(_api, candidate);

  /// Updates the window rectangle (called by `MovaMiniWindow` while dragging).
  ///
  /// 更新小窗矩形（拖动时由 `MovaMiniWindow` 调用）。
  void setRect(MovaMiniRect r) {
    _rect = r;
    notifyListeners();
  }

  /// Removes [_entry] from its [Overlay] if it is still mounted, then clears
  /// it unconditionally. The single choke point for entry teardown — [hide],
  /// [close], and re-[show]/[showInPage] all route through here instead of
  /// calling `remove()` themselves, so a since-destroyed host [Overlay] (the
  /// page was popped) never causes a double-remove crash.
  ///
  /// 若 [_entry] 仍挂载则把它从所属 [Overlay] 移除，随后无条件清空。是 entry
  /// 摘除的唯一关口——[hide]、[close]、重新 [show]/[showInPage] 都走这里而不是
  /// 自行调用 `remove()`，因此宿主 [Overlay] 已先销毁（页面被 pop）时不会造成
  /// 重复 remove 崩溃。
  void _detachEntry() {
    final entry = _entry;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
    _entry = null;
  }

  @override
  void dispose() {
    _detachEntry();
    super.dispose();
  }
}
