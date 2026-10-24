## 1.1.0+patched.1

* Fork of fluttercandies/sync_scroll_library 1.1.0 (upstream commit c5c66e9), maintained in icodejoo/dart-labs and not published to pub.dev. Consume it through `dependency_overrides`.
* Fix: after a parent controller took over a drag at the child's boundary, reversing the finger in the same gesture left the parent holding the drag, so the child could not scroll back. The parent now keeps the drag only until it unwinds to the offset it was activated at; then its drag is cancelled and the child handles the rest of the gesture (when the child can scroll in that direction).
* Fix: `linkActivedParent` normalizes the drag delta for `TextDirection.rtl` before any check, so the hand-back also works in right-to-left layouts.
* Add regression tests (`test/link_reverse_drag_test.dart`): both boundaries in ltr and rtl, a second takeover in the same gesture, and a child that cannot scroll.
* Exclude platform folders (`build`, `android`, `ios`, `web`, `windows`, `macos`, `linux`) from analysis; add `flutter_test` as a dev dependency; drop the pubspec template comments.

## 1.1.0

* Migrate to Flutter 3.10.0

## 1.0.1

* fix simulation scroll is not sync

## 1.0.0

* refactor code

## 0.0.3

* check hasDrag in handleDragUpdate (maybe some positions will not accept handleDragStart event, for example, the content of FlexGrid is not loaded,  scroll horizontal headers then content is loaded, at that moment the other positions are not accept handleDragStart, they will not be sync)

## 0.0.2

* support TextDirection.rtl

## 0.0.1

* The library for extended_tabs and flex_grid.
