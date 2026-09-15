## 0.2.1

* `CurvedDualTabBar.controller` resolution now falls back to an ancestor `DefaultTabController` before creating its own internal controller (priority: explicit `controller` > `DefaultTabController.of(context)` > internal). Lets the bar share one `TabController`/animation with a sibling `TabBarView` without wiring it manually, so the curve/indicator tracks a swipe in real time instead of only snapping once it settles.

## 0.2.0

* Add divider styling: `dividerGradient` (gradient stroke, overrides `dividerColor`), `dividerCap` (`StrokeCap`), `dividerShadow` (a `BoxShadow` stroked behind the seam as a glow/shadow).
* Add `topControlOffset`/`bottomControlOffset` to shape the S-curve's bezier control points directly, independent of `leanAmplitude` — the curve no longer has to keep a flat tangent at the top/bottom edges.

## 0.1.0

* Initial release: `CurvedDualTabBar` (drop-in two-tab Material `TabBar` header with an animated S-curve background) and `CurvedTabBackground` (the standalone curve painter, for pairing with your own native `TabBar`).
