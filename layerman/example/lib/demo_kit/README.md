# demo_kit

Copy this directory into another Flutter project's `example/lib/`.
It depends only on the Flutter SDK, with no countman imports or packages.

```dart
import 'demo_kit/demo_kit.dart';

DemoApp(
  title: 'my_package',
  seedColor: const Color(0xFF4263EB),
  home: DemoShell(
    project: 'my_package', version: '1.0.0',
    pubUrl: 'https://pub.dev/packages/my_package',
    githubUrl: 'https://github.com/org/repo',
    readmeUrl: 'https://github.com/org/repo/blob/main/README.md',
    destinations: [DemoDestination(
      id: 'start', en: 'Start', zh: '开始', icon: Icons.play_arrow,
      builder: (context) => DemoPage(
        title: tr(context, 'Start', '开始'),
        description: tr(context, 'Try it.', '试一试。'),
        sections: [DemoSection(title: 'API', child: DemoGrid(children: [
          DemoGridItem(child: DemoCard(title: 'Preview',
            description: 'A small example', child: YourDemo())),
          DemoGridItem(span: 0, child: YourLargePanel()),
        ]), code: 'Your compilable Dart example')],
      ),
    )],
  ),
)
```

- Supply stable, unique destination IDs and translated names/section labels.
- Use `tr(context, english, chinese)` for all prose, controls and tooltips.
- `DemoLocale`: `?lang=zh|en` overrides the browser locale; otherwise Chinese
  language codes select Chinese and other languages fall back to English.
  Selection is held in memory. Inject a locale for tests; dispose it yourself.
- `DemoApp` supplies Material 3, system light/dark, a manual toggle, CJK font
  fallbacks and `DemoTokens`. Host apps must not add another MaterialApp.
- `DemoShell` uses a sidebar at 900px and a drawer below. It restores
  `#/pages/<id>` and supports browser history using SystemNavigator.
- Web links open a new tab with noopener/noreferrer through dart:js_interop.
  Native platforms copy the link and show confirmation.
- `DemoGrid` uses available width: 1 / 2 / 3 / 4 columns at 600 / 1000 / 1500.
  Page content is capped at 1200px. Rows share height; cards cap at 420px.
  `DemoGridItem.span` is a column count; zero spans the whole row.
- Use compact cards for small interactive examples; large panels span a row.
  DemoCard replay remounts local child state. Supply `onReplay` when a controller outside the card owns the state;
  use `replayable: false` for static content.
- Put complete code on `DemoSection.code`. `CodeBlock` starts collapsed,
  expands across the section, scrolls horizontally and copies exact text.
- `InfoNoteKind` supports tip, warning and deprecated messages.
- Keep titles to one line and descriptions to two; tap a card heading for
  full details. Use readable text, 12px gaps and 24px section spacing.
- Copy `test/demo_kit_test.dart` too and adjust its package import.
- Validate both languages and themes at 375x667 and 1440x900 before shipping.

## Host extensions in the layerman copy

- `DemoApp.appBuilder` optionally supplies a single existing app host with the kit themes, theme mode and home. It must not nest another MaterialApp around the returned app.
- `DemoCard.onReplay` resets an externally owned controller. Without it, Replay remounts only the card body. Static cards use `replayable: false`.
- Chinese Replay is labelled 重放. These are local integration extensions, not generic bug fixes.
