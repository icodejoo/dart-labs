import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/models.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/components/preview.dart';

import '../support/fake_api.dart';
import '../support/pump.dart';

/// A 1x1 transparent PNG — the smallest payload `Image.memory` will decode.
///
/// 一张 1x1 透明 PNG——`Image.memory` 能解码的最小负载。
final Uint8List _png = Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

void main() {
  late FakeMovaApi api;

  setUp(() => api = FakeMovaApi());
  tearDown(() => api.dispose());

  testWidgets('renders nothing while previewAt is null', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('shows the formatted scrub timestamp once previewAt is set', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 65)));
    await t.pump();
    await t.pump();
    expect(find.text('01:05'), findsOneWidget);
  });

  testWidgets('requests the thumbnail for the scrub position', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 42)));
    await t.pump();
    expect(api.preview.calls, contains('requestAt'));
    expect(api.preview.lastRequestedAt, const Duration(seconds: 42));
  });

  testWidgets('renders a pushed thumbnail as an image', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    expect(find.byType(Image), findsNothing);
    api.preview.push(MovaThumb(at: const Duration(seconds: 10), bytes: _png));
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a synchronous cache hit renders without waiting for the stream', (t) async {
    api.preview.peekResult = MovaThumb(at: const Duration(seconds: 10), bytes: _png);
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('a cropped sprite is clipped to the crop rectangle', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    api.preview.push(MovaThumb(
      at: const Duration(seconds: 10),
      bytes: _png,
      crop: const MovaThumbCrop(x: 160, y: 0, w: 160, h: 90),
    ));
    await t.pump();
    final clip = t.widget<ClipRect>(find.byKey(const ValueKey('movaPrevClip')));
    expect(clip, isNotNull);
    final box = t.getSize(find.byKey(const ValueKey('movaPrevClip')));
    expect(box.width / box.height, closeTo(160 / 90, 0.01));
  });

  testWidgets('clearing previewAt hides the bubble again', (t) async {
    await pumpComponent(t, api, PreviewComponent());
    api.pushUi(const MovaUiState(dragging: true, previewAt: Duration(seconds: 10)));
    await t.pump();
    api.preview.push(MovaThumb(at: const Duration(seconds: 10), bytes: _png));
    await t.pump();
    expect(find.byType(Image), findsOneWidget);
    api.pushUi(const MovaUiState());
    await t.pump();
    await t.pump();
    expect(find.byType(Image), findsNothing);
    expect(api.preview.calls, contains('cancel'));
  });

  testWidgets('the component is addressable at path "preview" in slot bottomAbove', (t) async {
    final c = PreviewComponent();
    expect(c.name, 'preview');
    expect(c.slot.name, 'bottomAbove');
    expect(c.children, isEmpty);
  });
}
