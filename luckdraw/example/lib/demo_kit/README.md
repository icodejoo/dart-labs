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
  DemoCard replay remounts local child state. Set `replayable: false` when
  controls or controllers outside the card already manage replay.
- Put complete code on `DemoSection.code`. `CodeBlock` starts collapsed,
  expands across the section, scrolls horizontally and copies exact text.
- `InfoNoteKind` supports tip, warning and deprecated messages.
- Keep titles to one line and descriptions to two; tap a card heading for
  full details. Use readable text, 12px gaps and 24px section spacing.
- Copy `test/demo_kit_test.dart` too and adjust its package import.
- Validate both languages and themes at 375x667 and 1440x900 before shipping.

## luckdraw host

- `main.dart` hosts three bilingual routes: `games`, `physics`, `integration`.
- The version chip loads the packaged `../pubspec.yaml` asset (the luckdraw
  manifest, not the example manifest). No version constant needs updating.
- All twelve animated cards use `DemoCard` replay to remount their complete
  page/controller subtree. The original pages embed through `GamePanel` when
  a `DemoLocaleScope` is present; standalone native regression pages keep
  their existing controls and reset behavior.
- `flutter run -d windows -t lib/native_main.dart` preserves the original
  standalone routes, 76 upstream screenshot comparisons, custom Chinese
  lots artwork and compiled README snippets for native regression work.
  These duplicate/reference screens are absent from the web navigation.
- The actual performance harness stays in `luckdraw/tool/bench/`; it is not
  imported by this app. Historical budgets and device claims are not shown.
- The online lots canvas uses the public default style so both languages
  can render translated labels without baking Chinese text into painters.
- Existing package/example README edits are owned by another contributor
  and were intentionally left byte-for-byte unchanged in this migration.

## Local copy adjustments

The complete countman kit was copied, then adjusted only in this example:

- Use a two-row header below the 900px sidebar breakpoint. The original
  single row overflowed around a 600px viewport under Flutter widget tests.
- Preserve a minimum 44px replay target instead of compact icon density.
- Translate Replay as 重放; add enum documentation and sort exports to meet
  this example's lint rules. Tests use Dart 3.5-compatible callback names
  and typed platform-channel argument casts.

`test/demo_kit_test.dart` covers the shared contracts. `test/playground_test.dart`
checks 375/600/900/1000/1440/1600 layouts, both languages/themes, every draw
through settlement, replay during motion, another completed round and cleanup.
