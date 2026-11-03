import 'ui_state.dart';

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
  MovaUiConnections({required this.mirror, this.onFirst, this.onLast});

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

class _UiLink implements MovaUiLink {
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
}
