# curved_dual_tab_bar

**A curved, two-segment tab bar with an animated S-curve divider — built on a real Material `TabBar`, not a fake gesture layer.**

[![pub.dev](https://img.shields.io/pub/v/curved_dual_tab_bar.svg)](https://pub.dev/packages/curved_dual_tab_bar)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/icodejoo/dart-labs/blob/main/curved_dual_tab_bar/LICENSE)
[![Demo](https://img.shields.io/badge/demo-live-brightgreen)](https://icodejoo.github.io/dart-labs/curved_dual_tab_bar/)

**[▶ Live Demo](https://icodejoo.github.io/dart-labs/curved_dual_tab_bar/)** — every styling knob demoed interactively.

- 🎯 **A real `TabBar` underneath** — tap targets, the selection indicator, ripple/hover/focus feedback and a11y semantics all come from Flutter's own `TabBar`; this widget only paints the curved background around it.
- 🎨 **Fully themeable** — solid colors, gradients, per-side borders, divider color/width, corner radius, lean amplitude, animation duration/curve.
- 🧩 **Two ways to use it** — `CurvedDualTabBar` (drop-in header, owns its own `TabController`) or `CurvedTabBackground` (the standalone curve painter, if you already drive a native `TabBar` yourself).

---

## Screenshot

| Demo app |
| :---: |
| ![CurvedDualTabBar demo](https://raw.githubusercontent.com/icodejoo/dart-labs/main/curved_dual_tab_bar/example/screenshots/demo.png) |
| Captured on a physical Android device from the [example app](https://github.com/icodejoo/dart-labs/tree/main/curved_dual_tab_bar/example) |

> Try every variant live at the [demo site](https://icodejoo.github.io/dart-labs/curved_dual_tab_bar/).

---

## Install

```yaml
dependencies:
  curved_dual_tab_bar: ^0.1.0
```

## Usage

```dart
import 'package:curved_dual_tab_bar/curved_dual_tab_bar.dart';

CurvedDualTabBar(
  titles: const ['DEPOSIT', 'WITHDRAW'],
  selectedIndex: selectedIndex,
  onChanged: (i) => setState(() => selectedIndex = i),
)
```

That's a fully working, animated, two-tab header — `CurvedDualTabBar` creates and owns its own `TabController` internally, kept in sync with `selectedIndex`/`onChanged`.

### Already have a native `TabBar`?

Use `CurvedTabBackground` as pure decoration and let your own `TabController` drive it:

```dart
CurvedTabBackground(
  selectedIndex: selectedIndex,
  progress: tabController.animation,
  child: TabBar(
    controller: tabController,
    indicatorColor: Colors.transparent,
    dividerColor: Colors.transparent,
    tabs: const [Tab(text: 'LEFT'), Tab(text: 'RIGHT')],
  ),
)
```

### Styling

Both widgets accept `activeColor`/`inactiveColor` (or `activeGradient`/`inactiveGradient`), `unselectedColor`/`unselectedBorderColor`, `dividerColor`/`dividerWidth`, `activeBorderColor`/`inactiveBorderColor`, `borderRadius`, `leanAmplitude` (how much the S-curve leans), and `duration`/`curve` for the transition animation. See the [example app](https://github.com/icodejoo/dart-labs/tree/main/curved_dual_tab_bar/example) for every combination demoed side by side.

## Why exactly 2 tabs?

The curve divider is a single S-shaped seam between an active and an inactive half — that only has a well-defined shape for 2 segments. `CurvedDualTabBar` asserts `titles.length == 2` for that reason. For more segments, use a plain `TabBar`.

## License

MIT — see [LICENSE](LICENSE).
