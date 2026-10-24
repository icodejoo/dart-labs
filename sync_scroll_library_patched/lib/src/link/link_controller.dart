import 'package:flutter/widgets.dart';
import 'package:sync_scroll_library/src/drag_hold_controller.dart';
import 'package:sync_scroll_library/src/sync/sync_controller.dart';

import 'link_scroll_state.dart';

/// The [LinkScrollController] to sync pixels for all of positions
class LinkScrollController extends ScrollController
    with LinkScrollControllerMixin {
  /// Creates a scroll controller that continually updates its
  /// [initialScrollOffset] to match the last scroll notification it received.
  LinkScrollController({
    double initialScrollOffset = 0.0,
    bool keepScrollOffset = true,
    String? debugLabel,
    this.parent,
  }) : super(
          initialScrollOffset: initialScrollOffset,
          keepScrollOffset: keepScrollOffset,
          debugLabel: debugLabel,
        );

  /// The Outer SyncScrollController, for example [ExtendedTabBarView] or [ExtendedPageView]
  /// It make better experience when scroll on horizontal direction
  @override
  final LinkScrollControllerMixin? parent;
}

/// The [LinkPageController] to scroll Pages(PageView or TabBarView) when [FlexGrid] is reach the horizontal boundary
class LinkPageController extends PageController with LinkScrollControllerMixin {
  /// Creates a page controller.
  ///
  /// The [initialPage], [keepPage], and [viewportFraction] arguments must not be null.
  LinkPageController({
    int initialPage = 0,
    bool keepPage = true,
    double viewportFraction = 1.0,
    this.parent,
  }) : super(
          initialPage: initialPage,
          keepPage: keepPage,
          viewportFraction: viewportFraction,
        );

  /// The Outer SyncScrollController, for example [ExtendedTabBarView] or [ExtendedPageView]
  /// It make better experience when scroll on horizontal direction
  @override
  final LinkScrollControllerMixin? parent;
}

mixin LinkScrollControllerMixin on ScrollController
// TODO(zmtzawqlp): i want something like mixin LinkScrollControllerMixin with SyncScrollControllerMixin
// so don't need to override everything in SyncScrollControllerMixin
// https://github.com/dart-lang/language/issues/540
// https://github.com/dart-lang/sdk/issues/50167
    implements
        SyncScrollControllerMixin {
  late final SyncScrollHandler _syncHandler = SyncScrollHandler();
  // The parent from user
  LinkScrollControllerMixin? get parent;
  // The parent from link
  LinkScrollControllerMixin? _parent;

  // The actual used parent
  LinkScrollControllerMixin? get _internalParent => parent ?? _parent;

  // The current actived controller
  LinkScrollControllerMixin? _activedLinkParent;

  // The pixels of [_activedLinkParent] at the moment it was actived.
  // It's the anchor we unwind back to when the drag direction is reversed.
  double _activedLinkParentPixels = 0;

  bool get parentIsNotNull => _internalParent != null;

  bool get isSelf => _activedLinkParent == null;

  void linkParent<S extends StatefulWidget, T extends LinkScrollState<S>>(
      BuildContext context) {
    _parent = context.findAncestorStateOfType<T>()?.linkScrollController;
  }

  void unlinkParent() {
    _parent = null;
  }

  @override
  void handleDragDown(DragDownDetails? details) {
    _syncHandler.handleDragDown(details);
  }

  @override
  void handleDragStart(DragStartDetails details) {
    _syncHandler.handleDragStart(details);
  }

  @override
  void handleDragUpdate(DragUpdateDetails details) {
    if (_activedLinkParent != null && _activedLinkParent!.hasDrag) {
      _activedLinkParent!.handleDragUpdate(details);
    } else {
      _syncHandler.handleDragUpdate(details);
    }
  }

  @override
  void handleDragEnd(DragEndDetails details) {
    _activedLinkParent?.handleDragEnd(details);
    _syncHandler.handleDragEnd(details);
  }

  @override
  void handleDragCancel() {
    _activedLinkParent?.handleDragCancel();
    _activedLinkParent = null;
    _syncHandler.handleDragCancel();
  }

  @override
  void forceCancel() {
    _activedLinkParent?.forceCancel();
    _activedLinkParent = null;
    _syncHandler.forceCancel();
  }

  double get extentAfter => _activedLinkParent != null
      ? _activedLinkParent!.extentAfter
      : _extentAfter;

  double get extentBefore => _activedLinkParent != null
      ? _activedLinkParent!.extentBefore
      : _extentBefore;

  double get _extentAfter => _syncHandler.positionToListener.keys.isEmpty
      ? 0
      : _syncHandler.positionToListener.keys.first.extentAfter;

  double get _extentBefore => _syncHandler.positionToListener.keys.isEmpty
      ? 0
      : _syncHandler.positionToListener.keys.first.extentBefore;

  /// Current scroll offset of this controller, 0 when no position is attached.
  ///
  /// 当前控制器的滚动偏移，没有挂载 position 时返回 0。
  double get _pixels => _syncHandler.positionToListener.keys.isEmpty
      ? 0
      : _syncHandler.positionToListener.keys.first.pixels;

  /// Whether this controller can still consume [delta] by itself.
  ///
  /// 判断本层自己还能不能消化这个 delta（也就是该方向上还没到边界）。
  bool _canConsume(double delta) =>
      (delta < 0 && _extentAfter != 0) || (delta > 0 && _extentBefore != 0);

  bool get hasDrag =>
      _activedLinkParent != null ? _activedLinkParent!.hasDrag : _hasDrag;
  bool get hasHold =>
      _activedLinkParent != null ? _activedLinkParent!.hasHold : _hasHold;

  bool get _hasDrag => _syncHandler.positionToListener.values
      .any((DragHoldController element) => element.hasDrag);
  bool get _hasHold => _syncHandler.positionToListener.values
      .any((DragHoldController element) => element.hasHold);

  LinkScrollControllerMixin? _findParent(
      bool test(LinkScrollControllerMixin parent)) {
    if (_internalParent == null) {
      return null;
    }
    if (test(_internalParent!)) {
      return _internalParent!;
    }

    return _internalParent!._findParent(test);
  }

  /// Hands the drag back from the actived parent to this controller.
  ///
  /// The parent keeps the drag until it has unwound to the offset it was
  /// actived from; after that this controller is able to scroll again within
  /// the same gesture.
  ///
  /// 把拖拽控制权从已激活的父层交还给本层。父层会一直持有拖拽，直到它退回
  /// 到当初被激活时的偏移；之后同一次手势里本层就能重新滚动了。
  ///
  /// [delta] the drag delta of this frame, already normalized by text direction.
  /// Returns true when the parent was released.
  ///
  /// Example:
  /// ```dart
  /// if (_releaseActivedParent(delta)) {
  ///   // this controller handles the rest of the gesture
  /// }
  /// ```
  bool _releaseActivedParent(double delta) {
    final LinkScrollControllerMixin? activedParent = _activedLinkParent;
    if (activedParent == null) {
      return false;
    }
    // The parent still owns the drag while this controller is stuck at its
    // boundary in this direction.
    if (!_canConsume(delta)) {
      return false;
    }
    // A positive delta moves the content right, so pixels decrease.
    final double parentPixels = activedParent._pixels;
    final bool unwound = delta < 0
        ? parentPixels >= _activedLinkParentPixels
        : parentPixels <= _activedLinkParentPixels;
    if (!unwound) {
      return false;
    }
    _activedLinkParent = null;
    activedParent.handleDragCancel();
    return true;
  }

  void linkActivedParent(
    double delta,
    DragUpdateDetails details,
    TextDirection textDirection,
  ) {
    if (textDirection == TextDirection.rtl) {
      delta = -delta;
    }

    if (_activedLinkParent != null) {
      _releaseActivedParent(delta);
      return;
    }
    LinkScrollControllerMixin? activedParent;

    if (delta < 0 && _extentAfter == 0) {
      activedParent = _findParent(
          (LinkScrollControllerMixin parent) => parent._extentAfter != 0);
    } else if (delta > 0 && _extentBefore == 0) {
      activedParent = _findParent(
          (LinkScrollControllerMixin parent) => parent._extentBefore != 0);
    }

    if (activedParent != null) {
      _activedLinkParent = activedParent;
      _activedLinkParentPixels = activedParent._pixels;
      activedParent.handleDragDown(null);
      activedParent.handleDragStart(
        DragStartDetails(
          globalPosition: details.globalPosition,
          localPosition: details.localPosition,
          sourceTimeStamp: details.sourceTimeStamp,
        ),
      );
    }
  }

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    _syncHandler.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    _syncHandler.detach(position);
    super.detach(position);
  }

  @override
  void dispose() {
    _syncHandler.forceCancel();
    super.dispose();
  }
}
