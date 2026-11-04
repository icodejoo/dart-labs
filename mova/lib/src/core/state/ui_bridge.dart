import 'dart:async';

import 'ui_state.dart';

/// 可移交的 UI 计时责任；移交只更换回调，保留计时器剩余期限。
class MovaUiTimers {
  /// 控制条到期动作。
  void Function()? onHide;

  /// HUD 到期动作。
  void Function()? onHud;
  Timer? _hide;
  Timer? _hud;

  /// 重新登记自动隐藏。
  void armHide(Duration delay) {
    cancelHide();
    _hide = Timer(delay, () {
      _hide = null;
      onHide?.call();
    });
  }

  /// 在对外通知之前登记 HUD，允许通知监听器重入并取代本次计时。
  void armHud(Duration delay) {
    cancelHud();
    _hud = Timer(delay, () {
      _hud = null;
      onHud?.call();
    });
  }

  /// 取消自动隐藏。
  void cancelHide() {
    _hide?.cancel();
    _hide = null;
  }

  /// 取消 HUD。
  void cancelHud() {
    _hud?.cancel();
    _hud = null;
  }

  /// 同步释放所有计时责任。
  void cancel() {
    cancelHide();
    cancelHud();
    onHide = null;
    onHud = null;
  }
}

/// 最后一个视图离开时交还的镜像和计时责任。
class MovaUiHandoff {
  /// 状态必须已清理拖动与预览瞬时态。
  MovaUiHandoff(this.state, this.timers);

  /// 最后视图的快照。
  final MovaUiState state;

  /// 保留原到期时间的计时器。
  final MovaUiTimers timers;
}

/// 包内：接收从最后一个视图交还的 UI 责任。
abstract interface class MovaUiHandoffReceiver {
  /// 恢复旧镜像，不重新计算剩余期限。
  void resumeUi(MovaUiHandoff handoff);
}

/// 可在解绑时移交计时责任的连接；不扩充自定义连接必需成员。
abstract interface class MovaUiHandoffLink implements MovaUiLink {
  /// 仅末次解绑移交，其余解绑取消本视图计时器。
  void unlinkWith(MovaUiHandoff handoff);
}

/// 支持每视图交互态的包内过渡能力，不扩充 MovaApi。
abstract interface class MovaUiBridge {
  /// 当前源是否已宣布就绪。
  bool get uiReady;

  /// 挂接视图；销毁后返回已关闭的连接。
  MovaUiLink linkUi(MovaUiSink sink);
}

/// 接收旧 UI 动词的视图端。
abstract interface class MovaUiSink {
  /// 显示控制条。
  void legacyShow({required bool sticky});

  /// 隐藏控制条。
  void legacyHide();

  /// 显示 HUD。
  void legacyHud(MovaHud hud, String? text);

  /// 更新拖动与预览位置。
  void legacyDragging(bool dragging, Duration? previewAt);
}

/// 视图与引擎之间可幂等断开的连接。
abstract interface class MovaUiLink {
  /// 写给旧读者的镜像；多视图时后写者胜出。
  void mirror(MovaUiState state);

  /// 断开连接；最后一个视图断开后恢复旧路径。
  void unlink();
}

/// 包内连接集合，共用广播、关闭与镜像的生命周期规则。
class MovaUiConnections {
  /// 创建镜像接收口与首连、末次断开的钩子。
  MovaUiConnections({
    required this.mirror,
    this.onFirst,
    this.onLast,
    this.onHandoff,
  });

  /// 末次解绑时接收原有计时责任。
  final void Function(MovaUiHandoff)? onHandoff;

  /// 旧读者镜像写入口。
  final void Function(MovaUiState) mirror;

  /// 首个视图接管时调用。
  final void Function()? onFirst;

  /// 最后一个视图离开时调用。
  final void Function()? onLast;
  final Set<_UiLink> _links = {};
  bool _closed = false;

  /// 是否没有视图。
  bool get isEmpty => _links.isEmpty;

  /// 建立连接，销毁后不再持有视图。
  MovaUiLink link(MovaUiSink sink) {
    final link = _UiLink(this, sink);
    if (_closed) return link..closed = true;
    if (isEmpty) onFirst?.call();
    _links.add(link);
    return link;
  }

  /// 广播旧动词，允许回调重入时断开连接。
  void broadcast(void Function(MovaUiSink) call) {
    for (final link in [..._links]) {
      if (!link.closed) call(link.sink);
    }
  }

  /// 同步关闭所有连接，不回调视图。
  void close() {
    _closed = true;
    for (final link in _links) {
      link.closed = true;
    }
    _links.clear();
  }
}

class _UiLink implements MovaUiHandoffLink {
  _UiLink(this.owner, this.sink);
  final MovaUiConnections owner;
  final MovaUiSink sink;
  bool closed = false;

  @override
  void mirror(MovaUiState state) {
    if (!closed) owner.mirror(state);
  }

  @override
  void unlink() {
    if (closed) return;
    closed = true;
    owner._links.remove(this);
    if (owner.isEmpty) owner.onLast?.call();
  }

  @override
  void unlinkWith(MovaUiHandoff handoff) {
    if (closed) {
      handoff.timers.cancel();
      return;
    }
    unlink();
    if (owner.isEmpty && !owner._closed && owner.onHandoff != null) {
      owner.onHandoff!(handoff);
    } else {
      handoff.timers.cancel();
    }
  }
}
