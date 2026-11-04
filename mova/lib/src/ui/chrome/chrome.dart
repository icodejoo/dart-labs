import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../core/api.dart';
import '../../core/bus/bus.dart';
import '../../core/events/events.dart';
import '../../core/options/controls_config.dart';
import '../../core/state/ui_bridge.dart';
import '../../core/state/ui_state.dart';
import '../scope/scope.dart';

/// 一个播放器视图自己的控制条、HUD、拖动与预览交互态。
///
/// 由视图创建的实例随视图销毁；宿主传入的实例由宿主销毁。
/// 同一时刻只能挂在一个视图上。
class MovaChrome extends ChangeNotifier
    implements ValueListenable<MovaUiState> {
  /// 创建控制条可见、无 HUD、无拖动的交互态。
  MovaChrome() {
    _timers = _newTimers();
  }

  final _bus = MovaBus<MovaUiState>(const MovaUiState());
  MovaCtrlsConfig _controls = const MovaCtrlsConfig();
  late MovaUiTimers _timers;

  MovaUiTimers _newTimers() => MovaUiTimers()
    ..onHide = hide
    ..onHud = () {
      if (!_disposed) {
        _emit(value.copyWith(hud: MovaHud.none, clearHudText: true));
      }
    };
  bool _sticky = false;
  bool _disposed = false;
  MovaApi? _api;
  MovaUiLink? _link;
  StreamSubscription<MovaEvent>? _eventSub;
  int _binding = 0;
  int _readyEpoch = 0;

  /// 查找最近视图的交互态；非桥接 API 且未显式传入时为 null。
  static MovaChrome? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MovaChromeScope>()?.chrome;

  /// 查找最近视图的交互态；未找到时抛出 FlutterError。
  /// 在 build 或回调中调用，例如 `MovaChrome.of(context).show()`。
  static MovaChrome of(BuildContext context) =>
      maybeOf(context) ??
      (throw FlutterError(
        'MovaChrome.of() requires a MovaPlayer with chrome.',
      ));

  void _bind(MovaApi api) {
    assert(!_disposed, '已销毁的 MovaChrome 不能挂载');
    assert(_api == null, '一个 MovaChrome 同一时刻只能挂一个视图');
    if (_disposed) return;
    _api = api;
    _cancelTimers();
    _sticky = false;
    _readyEpoch = api.state.renderEpoch;
    _bus.emit(MovaUiState(controlsVisible: api.uiState.controlsVisible));
    final generation = ++_binding;
    scheduleMicrotask(() {
      if (!_disposed && generation == _binding) notifyListeners();
    });
    final bridge = api is MovaUiBridge ? api as MovaUiBridge : null;
    _link = bridge?.linkUi(_ChromeSink(this));
    _link?.mirror(value);
    if (value.controlsVisible && (bridge?.uiReady ?? false)) _armAutoHide();
    _eventSub = api.events.listen(
      (event) {
        if (_disposed || generation != _binding || event is! MovaReady) return;
        final epoch = api.state.renderEpoch;
        // A28 会重放影子的 Ready；换指只替换画面，不重置本视图交互与计时。
        if (epoch != _readyEpoch) {
          _readyEpoch = epoch;
          return;
        }
        _controls.showOnStart ? show() : hide();
      },
      onDone: () {
        if (generation == _binding) _cancelTimers();
      },
    );
  }

  void _unbind() {
    ++_binding;
    final timers = _timers;
    // 拖动卸载等价于取消拖动；常显保持，否则从离开时恢复自动隐藏。
    if (value.dragging &&
        value.controlsVisible &&
        !_sticky &&
        _controls.autoHide) {
      timers.armHide(_controls.autoHideDelay);
    }
    _bus.emit(value.copyWith(dragging: false, clearPreview: true));
    _timers = _newTimers();
    unawaited(_eventSub?.cancel());
    _eventSub = null;
    final link = _link;
    if (link is MovaUiHandoffLink) {
      link.unlinkWith(MovaUiHandoff(value, timers));
    } else {
      timers.cancel();
      link?.unlink();
    }
    _link = null;
    _api = null;
  }

  void _cancelTimers() {
    _timers.cancelHide();
    _timers.cancelHud();
  }

  /// 当前交互态。
  @override
  MovaUiState get value => _bus.value;

  /// 当前交互态，与旧接口同名，便于迁移。
  MovaUiState get uiState => value;

  /// 交互态变化流；新订阅者收到当前值，相同值不重复通知。
  Stream<MovaUiState> get uiStates => _bus.stream;

  /// 显示控制条；[sticky] 为 true 时保持显示，直到再次显示或隐藏。
  void show({bool sticky = false}) {
    if (_disposed) return;
    _cancelAutoHide();
    _sticky = sticky;
    _emit(value.copyWith(controlsVisible: true));
    if (!_sticky) _armAutoHide();
  }

  /// 隐藏控制条并取消自动隐藏计时。
  void hide() {
    if (_disposed) return;
    _cancelAutoHide();
    _sticky = false;
    _emit(value.copyWith(controlsVisible: false));
  }

  /// 切换控制条显隐。
  void toggle() => value.controlsVisible ? hide() : show();

  /// 显示临时提示，[kMovaHudDuration] 后收起；不传文本会清空旧文本。
  void showHud(MovaHud hud, {String? text}) {
    if (_disposed) return;
    _timers.armHud(kMovaHudDuration);
    _emit(value.copyWith(hud: hud, hudText: text, clearHudText: text == null));
  }

  /// 拖动时保持控制条可见并暂停自动隐藏；结束后清空预览并重新计时。
  /// 常显状态不受拖动结束影响。
  void setDragging(bool v, {Duration? previewAt}) {
    if (_disposed) return;
    if (v) {
      _cancelAutoHide();
      _emit(
        value.copyWith(
          controlsVisible: true,
          dragging: true,
          previewAt: previewAt,
        ),
      );
    } else {
      _emit(value.copyWith(dragging: false, clearPreview: true));
      if (value.controlsVisible && !_sticky) _armAutoHide();
    }
  }

  /// 有操作发生时续期自动隐藏；隐藏、常显或拖动期间不启动计时。
  void touch() {
    if (_disposed || !value.controlsVisible || _sticky || value.dragging) {
      return;
    }
    _armAutoHide();
  }

  void _cancelAutoHide() {
    _timers.cancelHide();
  }

  void _armAutoHide() {
    _cancelAutoHide();
    if (_disposed || _sticky || value.dragging || !value.controlsVisible) {
      return;
    }
    if (_controls.autoHide) {
      _timers.armHide(_controls.autoHideDelay);
    }
  }

  void _emit(MovaUiState next) {
    if (_disposed || next == value) return;
    _bus.emit(next);
    _link?.mirror(next);
    notifyListeners();
  }

  /// 释放本实例计时并关闭变化流；绑定时交还剩余计时，之后各动词静默无效。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _unbind();
    unawaited(_bus.close());
    super.dispose();
  }
}

/// 包内：更新视图的控制条配置。
void movaSetChromeControls(MovaChrome chrome, MovaCtrlsConfig controls) {
  if (chrome._controls == controls) return;
  chrome._controls = controls;
  final api = chrome._api;
  if (chrome._autoHideTimer != null ||
      (api is MovaUiBridge && (api as MovaUiBridge).uiReady)) {
    chrome._armAutoHide();
  }
}

/// 包内：绑定视图，种子只继承控制条显隐。
void movaBindChrome(MovaChrome chrome, MovaApi api) => chrome._bind(api);

/// 包内：解绑视图，保留宿主拥有的实例。
void movaUnbindChrome(MovaChrome chrome) => chrome._unbind();

class _ChromeSink implements MovaUiSink {
  _ChromeSink(this.chrome);
  final MovaChrome chrome;
  @override
  void legacyShow({required bool sticky}) => chrome.show(sticky: sticky);
  @override
  void legacyHide() => chrome.hide();
  @override
  void legacyHud(MovaHud hud, String? text) => chrome.showHud(hud, text: text);
  @override
  void legacyDragging(bool dragging, Duration? previewAt) =>
      chrome.setDragging(dragging, previewAt: previewAt);
}

/// 包内：向后代发布当前视图的交互态。
class MovaChromeScope extends InheritedWidget {
  /// 发布可空交互态；null 表示回落旧 API。
  const MovaChromeScope({
    required this.chrome,
    required super.child,
    super.key,
  });

  /// 当前视图的交互态。
  final MovaChrome? chrome;
  @override
  bool updateShouldNotify(MovaChromeScope oldWidget) =>
      !identical(chrome, oldWidget.chrome);
}

/// 包内：组件统一读写口，非桥接宿主保持旧行为。
class MovaUiPort {
  /// 选择视图交互态或旧 API。
  MovaUiPort.of(this._chrome, this._api);
  final MovaChrome? _chrome;
  final MovaApi _api;

  /// 当前快照。
  MovaUiState get uiState => _chrome?.uiState ?? _api.uiState;

  /// 变化流。
  Stream<MovaUiState> get uiStates => _chrome?.uiStates ?? _api.uiStates;

  /// 显示控制条，并保留当前视图已有的常显标记。
  void show({bool sticky = false}) => _chrome != null
      ? _chrome.show(sticky: sticky || _chrome._sticky)
      : _api.showControls(sticky: sticky);

  /// 有交互时续期；非桥接旧路径保持空操作。
  void touch() => _chrome?.touch();

  /// 隐藏控制条。
  void hide() => _chrome != null ? _chrome.hide() : _api.hideControls();

  /// 切换显隐。
  void toggle() => uiState.controlsVisible ? hide() : show();

  /// 显示 HUD。
  void showHud(MovaHud hud, {String? text}) => _chrome != null
      ? _chrome.showHud(hud, text: text)
      : _api.showHud(hud, text: text);

  /// 设置拖动与预览位置。
  void setDragging(bool v, {Duration? previewAt}) => _chrome != null
      ? _chrome.setDragging(v, previewAt: previewAt)
      : _api.setDragging(v, previewAt: previewAt);
}

/// 包内：默认不建立依赖，可在 initState 中调用；build 中可传 listen。
MovaUiPort movaUiOf(BuildContext context, {bool listen = false}) {
  final scope = listen
      ? context.dependOnInheritedWidgetOfExactType<MovaChromeScope>()
      : context.getInheritedWidgetOfExactType<MovaChromeScope>();
  return MovaUiPort.of(
    scope?.chrome,
    listen ? MovaScope.of(context) : MovaScope.readOf(context),
  );
}
