import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/bus/bus.dart';
import '../../core/options/controls_config.dart';
import '../../core/state/ui_state.dart';

/// 一个播放器视图自己的控制条、HUD、拖动与预览交互态。
///
/// 由视图创建的实例随视图销毁；宿主传入的实例由宿主销毁。
/// 同一时刻只能挂在一个视图上。
class MovaChrome extends ChangeNotifier
    implements ValueListenable<MovaUiState> {
  /// 创建控制条可见、无 HUD、无拖动的交互态。
  MovaChrome();

  final _bus = MovaBus<MovaUiState>(const MovaUiState());
  MovaCtrlsConfig _controls = const MovaCtrlsConfig();
  Timer? _autoHideTimer;
  Timer? _hudTimer;
  bool _sticky = false;
  bool _disposed = false;

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
    _hudTimer?.cancel();
    _emit(value.copyWith(hud: hud, hudText: text, clearHudText: text == null));
    _hudTimer = Timer(kMovaHudDuration, () {
      _hudTimer = null;
      _emit(value.copyWith(hud: MovaHud.none, clearHudText: true));
    });
  }

  /// 标记拖动与预览位置；结束拖动时清空预览位置。
  void setDragging(bool v, {Duration? previewAt}) {
    if (_disposed) return;
    _emit(
      v
          ? value.copyWith(dragging: true, previewAt: previewAt)
          : value.copyWith(dragging: false, clearPreview: true),
    );
  }

  void _cancelAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _armAutoHide() {
    if (_controls.autoHide) {
      _autoHideTimer = Timer(_controls.autoHideDelay, hide);
    }
  }

  void _emit(MovaUiState next) {
    if (next == value) return;
    _bus.emit(next);
    notifyListeners();
  }

  /// 同步取消计时器并关闭变化流；之后各动词静默无效。
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelAutoHide();
    _hudTimer?.cancel();
    _hudTimer = null;
    unawaited(_bus.close());
    super.dispose();
  }
}

/// 包内：更新视图的控制条配置。
void movaSetChromeControls(MovaChrome chrome, MovaCtrlsConfig controls) =>
    chrome._controls = controls;
