import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/slot.dart';

import '../lib/shadow_scene.dart';

/// 捕获同一标准场景，并记录设备像素中的 ROI，供驱动端保存与对比。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('shadow device', () {
    testWidgets('captures blur spaces and canvas scales on Android',
        (tester) async {
      expect(Platform.isAndroid, isTrue);
      const backend = String.fromEnvironment('SHADOW_BACKEND');
      expect(const ['skia', 'impeller'], contains(backend));
      await tester.pumpWidget(const ShadowScene());
      await tester.pumpAndSettle();
      expect(find.byType(LuckyGrid), findsNWidgets(5));
      expect(find.byType(LuckySlotMachine), findsOneWidget);
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      final dpr = tester.view.devicePixelRatio;
      binding.reportData = {
        'backend_requested': backend,
        'dpr': dpr,
        'physical_width': tester.view.physicalSize.width,
        'physical_height': tester.view.physicalSize.height,
        'panels': {
          for (final name in kShadowPanels.keys)
            name: {
              'left': tester.getRect(find.byKey(ValueKey(name))).left * dpr,
              'top': tester.getRect(find.byKey(ValueKey(name))).top * dpr,
              'width': kShadowPanelSize.width * dpr,
              'height': kShadowPanelSize.height * dpr,
              'scale': kShadowPanels[name],
            },
        },
      };
      final png = await binding.takeScreenshot('shadow_$backend');
      expect(png.length, greaterThan(1000));
      expect(png.take(4), [137, 80, 78, 71]);
    });
  });
}
