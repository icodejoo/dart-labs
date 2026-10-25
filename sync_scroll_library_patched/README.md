# sync_scroll_library (patched)

[中文](README.zh.md)

A patched fork of
[fluttercandies/sync_scroll_library](https://github.com/fluttercandies/sync_scroll_library)
1.1.0, the scroll-linking library behind
[extended_tabs](https://pub.dev/packages/extended_tabs). The package name is
unchanged, so an app picks it up through `dependency_overrides`. It is **not**
published to pub.dev (`publish_to: none`); the version is `1.1.0+patched.1`.

## What is fixed

When a child scrollable reaches its boundary, `LinkScrollControllerMixin`
hands the drag to the parent (a tab view or page view). Upstream never takes
it back: `linkActivedParent` returns early while any parent is active, so if
the finger reverses in the same gesture the parent keeps the drag until the
finger lifts, and the child cannot scroll again.

Minimal repro: a horizontal list (child) on the first page of an
`ExtendedTabBarView` (parent). Drag left until the list hits its end and the
tab view starts moving to page two. Without lifting the finger, drag right:
the tab view follows back to page one and then keeps swallowing the drag,
while the list sits at its end with plenty of content on its left.

The fix records the parent's offset when it takes over (the anchor). On a
reversed drag the parent keeps the drag until it has unwound to the anchor;
then its drag is cancelled and the child scrolls again within the same
gesture. This only happens if the child can scroll in that direction;
otherwise the parent keeps the drag as before. The delta is normalized for
`TextDirection.rtl` before any check. The whole change lives in
`lib/src/link/link_controller.dart`; everything else matches 1.1.0.

Known limitation: the check runs once per pointer move, before that move is
applied. The parent can therefore end up past its anchor by at most one move's
delta when the child takes over. A parent with page physics snaps back once its
drag is cancelled.

## Use it in an app

`dependency_overrides` only takes effect in the root package, and it ignores
version constraints (`extended_tabs` asks for `^1.1.0`).

From a local checkout:

```yaml
dependency_overrides:
  sync_scroll_library:
    path: ../dart-labs/sync_scroll_library_patched
```

From git (pin `ref` to a commit for reproducible builds):

```yaml
dependency_overrides:
  sync_scroll_library:
    git:
      url: https://github.com/icodejoo/dart-labs.git
      path: sync_scroll_library_patched
      ref: main
```

## Tests

```sh
flutter test
```

`test/link_reverse_drag_test.dart` nests a linked child list in a linked
parent list and replays one gesture with `startGesture` and repeated
`moveBy`. It covers both boundaries in ltr and rtl, a second takeover in the
same gesture, and a child that cannot scroll. The hand-back tests fail against
the upstream `link_controller.dart` and pass with the patch.

## License

MIT, original copyright FlutterCandies. See [LICENSE](LICENSE).
