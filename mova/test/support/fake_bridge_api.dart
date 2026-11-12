import 'package:mova/src/core/state/ui_bridge.dart';
import 'package:mova/src/core/state/ui_state.dart';

import 'fake_api.dart';

/// 可独立控制就绪和连接的桥接替身，旧替身保持不变。
class FakeBridgeApi extends FakeMovaApi implements MovaUiBridge {
  /// 使用指定引擎选项。
  FakeBridgeApi({super.options});

  /// 当前是否就绪。
  bool ready = false;

  /// 已连接的视图端。
  final List<MovaUiSink> sinks = [];
  final List<_FakeLink> _links = [];
  bool _closed = false;

  @override
  bool get uiReady => ready && !_closed;

  @override
  MovaUiLink linkUi(MovaUiSink sink) {
    final link = _FakeLink(this, sink)..closed = _closed;
    if (!_closed) {
      sinks.add(sink);
      _links.add(link);
    }
    return link;
  }

  @override
  void showControls({bool sticky = false}) {
    super.showControls(sticky: sticky);
    for (final sink in [...sinks]) {
      sink.legacyShow(sticky: sticky);
    }
  }

  @override
  void hideControls() {
    super.hideControls();
    for (final sink in [...sinks]) {
      sink.legacyHide();
    }
  }

  @override
  void showHud(MovaHud hud, {String? text}) {
    super.showHud(hud, text: text);
    for (final sink in [...sinks]) {
      sink.legacyHud(hud, text);
    }
  }

  @override
  void setDragging(bool v, {Duration? previewAt}) {
    super.setDragging(v, previewAt: previewAt);
    for (final sink in [...sinks]) {
      sink.legacyDragging(v, previewAt);
    }
  }

  @override
  Future<void> dispose() {
    _closed = true;
    for (final link in _links) {
      link.closed = true;
    }
    _links.clear();
    sinks.clear();
    return super.dispose();
  }
}

class _FakeLink implements MovaUiLink {
  _FakeLink(this.api, this.sink);
  final FakeBridgeApi api;
  final MovaUiSink sink;
  bool closed = false;

  @override
  void mirror(MovaUiState state) {
    if (!closed) api.pushUi(state);
  }

  @override
  void unlink() {
    if (closed) return;
    closed = true;
    api.sinks.remove(sink);
    api._links.remove(this);
  }
}
