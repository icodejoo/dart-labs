import '../style/style.dart';
import '../../core/session/registry.dart';
import '../../core/session/cursor.dart';
import '../../core/session/timeline.dart' show MovaNodeId;

import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/playlist/playlist.dart';
import '../../core/state/progress.dart';
import '../scope/plugin.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// "Next up" card that fades in near the end of the current playlist item and
/// offers a one-tap jump to the next one. Renders nothing when the playlist is
/// disabled, there is no next item, or the host dismissed it for this item.
///
/// Host-wired: the host constructs a [MovaPlaylist] and passes it in
/// (e.g. via a UI kit patch), since the running index lives on [MovaPlaylist],
/// not on [IMovaApi]. Visibility is driven off the throttled progress stream vs.
/// [MovaState.duration] and [MovaPlaylistOpts.nextUpLeadTime].
///
/// "下一集"卡片：当前项临近结束时淡入，提供一键跳到下一项。播放列表关闭、没有
/// 下一项、或宿主已对本项关闭卡片时，不渲染任何内容。
///
/// 由宿主接线：宿主构造一个 [MovaPlaylist] 传入（例如经 UI 套件补丁），因为
/// 运行时下标在 [MovaPlaylist] 上、不在 [IMovaApi] 上。显隐由节流进度流对比
/// [MovaState.duration] 与 [MovaPlaylistOpts.nextUpLeadTime] 决定。
class MovaNextUpComponent extends MovaComponent {
  /// Creates the next-up card bound to [playlist].
  ///
  /// 创建绑定到 [playlist] 的下一集卡片。
  ///
  /// - [playlist]: the playlist driving navigation / 驱动导航的
  ///   播放列表（[MovaPlaylist]）
  MovaNextUpComponent(this.playlist);

  /// The playlist this card reads and drives.
  ///
  /// 该卡片读取并驱动的播放列表。
  final MovaPlaylist playlist;

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'nextUp';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.overlay;

  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) {
    if (!api.options.playlist.enabled) return const SizedBox.shrink();
    // A replacement playlist owns fresh subscriptions and dismissal state.
    //
    // 替换后的播放列表使用新的订阅与关闭状态。
    return _NextUpView(
      key: ObjectKey(playlist),
      api: api,
      playlist: playlist,
    );
  }
}

/// Stateful body of [MovaNextUpComponent]: tracks visibility from progress ticks
/// and resets when the playlist moves to another item.
///
/// [MovaNextUpComponent] 的有状态主体：依进度 tick 跟踪显隐，并在播放列表切到另一项
/// 时重置。
class _NextUpView extends StatefulWidget {
  /// Creates the internal next-up view.
  ///
  /// 创建内部的下一集视图。
  const _NextUpView({super.key, required this.api, required this.playlist});

  /// The capability surface followed for position/duration.
  ///
  /// 用于跟随位置/时长的能力面。
  final IMovaApi api;

  /// The playlist providing the next item and navigation.
  ///
  /// 提供下一项与导航的播放列表。
  final MovaPlaylist playlist;

  @override
  State<_NextUpView> createState() => _NextUpViewState();
}

/// State for [_NextUpView]; owns the visible flag and the per-item dismissal.
///
/// [_NextUpView] 的状态；持有可见标志与"本项已被关闭"的标记。
class _NextUpViewState extends State<_NextUpView> with MovaPlugin<_NextUpView> {
  /// Poster size shared by the image and its error placeholder.
  ///
  /// 图片与加载失败占位共用的封面尺寸。
  static const double _posterWidth = 72;
  static const double _posterHeight = 40;

  /// Whether the card is currently shown.
  ///
  /// 卡片当前是否显示。
  bool _visible = false;

  /// Whether the host dismissed the card for the current item; cleared on the
  /// next item so each item gets its own prompt.
  ///
  /// 宿主是否已对当前项关闭卡片；切到下一项时清除，使每项各有一次提示。
  bool _dismissed = false;
  int? _sessionEpoch;
  MovaNodeId? _sessionNode;
  MovaSessionPhase? _sessionPhase;

  @override
  void initState() {
    super.initState();
    bind(api.progress, _onProgress);
    final session = movaPlaylistSessions[widget.playlist];
    if (session != null) {
      _sessionEpoch = session.cursor.epoch;
      _sessionNode = session.cursor.node;
      _sessionPhase = session.cursor.phase;
      bind(session.changes, (_) {
        final cursor = session.cursor;
        final changed =
            cursor.epoch != _sessionEpoch ||
            cursor.node != _sessionNode ||
            cursor.phase != _sessionPhase;
        _sessionEpoch = cursor.epoch;
        _sessionNode = cursor.node;
        _sessionPhase = cursor.phase;
        // 换集、进出广告与落地窗口都须等待下一次正片进度，不能沿用旧卡片。
        if (changed && _visible) setState(() => _visible = false);
      });
    }
    // A new item re-arms the card: clear the dismissal and hide until the
    // next lead-time window is entered.
    //
    // 切到新项时重新武装卡片：清除关闭标记并隐藏，直到进入下一次提前量窗口。
    bind(widget.playlist.indexChanges, (_) {
      setState(() {
        _dismissed = false;
        _visible = false;
      });
    });
  }

  /// Recomputes visibility: show when a next item exists, the duration is
  /// known, the remaining time is within the lead window, and the host hasn't
  /// dismissed the card for this item.
  ///
  /// 重算显隐：存在下一项、时长已知、剩余时间进入提前量窗口、且宿主未对本项
  /// 关闭卡片时显示。
  void _onProgress(MovaProg p) {
    final duration = widget.api.state.duration;
    final lead = widget.api.options.playlist.nextUpLeadTime;
    final remaining = duration - p.position;
    final session = movaPlaylistSessions[widget.playlist];
    final show =
        (session == null || session.cursor.phase == MovaSessionPhase.content) &&
        widget.playlist.hasNext &&
        !_dismissed &&
        duration > Duration.zero &&
        remaining > Duration.zero &&
        remaining <= lead;
    if (show != _visible) setState(() => _visible = show);
  }

  /// Builds the next-up card with matching poster and placeholder sizes.
  ///
  /// 构建下一集卡片，使封面与失败占位尺寸一致。
  @override
  Widget build(BuildContext context) {
    final next = widget.playlist.nextItem;
    if (!_visible || next == null) return const SizedBox.shrink();
    final theme = MovaPlayerStyle.themeOf(context);
    final strings = MovaPlayerStyle.stringsOf(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 16, bottom: 72),
        child: Container(
          width: 260,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color(theme.sheetBackgroundColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.nextUp,
                style: TextStyle(
                  color: Color(theme.textColor),
                  fontSize: theme.captionFontSize,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (next.poster != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        next.poster!,
                        width: _posterWidth,
                        height: _posterHeight,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox(
                          width: _posterWidth,
                          height: _posterHeight,
                        ),
                      ),
                    ),
                  if (next.poster != null) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next.displayTitle ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(theme.textColor),
                            fontSize: theme.titleFontSize,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (next.subtitle != null)
                          Text(
                            next.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(theme.textColor),
                              fontSize: theme.captionFontSize,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _CardButton(
                    label: strings.cancel,
                    color: theme.textColor,
                    onTap: () => setState(() {
                      _dismissed = true;
                      _visible = false;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _CardButton(
                    label: strings.playNow,
                    color: theme.accentColor,
                    filled: true,
                    onTap: () => widget.playlist.next(),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small tappable label used for the card's two actions.
///
/// 卡片两个动作使用的小型可点击标签。
class _CardButton extends StatelessWidget {
  /// Creates a card button.
  ///
  /// 创建一个卡片按钮。
  const _CardButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  /// Button text.
  ///
  /// 按钮文案。
  final String label;

  /// Accent/text color; also the fill color when [filled].
  ///
  /// 强调/文字颜色；[filled] 时同时作为填充色。
  final int color;

  /// Whether the button is filled (primary) or text-only (secondary).
  ///
  /// 按钮是填充（主要）还是纯文字（次要）。
  final bool filled;

  /// Tap handler.
  ///
  /// 点击回调。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? Color(color) : null,
          border: filled ? null : Border.all(color: Color(color)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: filled ? const Color(0xFF000000) : Color(color),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
