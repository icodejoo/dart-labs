import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';
import '../support/pump.dart';

/// 用于验证插入位置的底栏自定义叶子。
class _Marker extends MovaComponent {
  /// 创建标记节点。
  _Marker();
  /// 补丁寻址名称。
  static const String componentName = 'marker';
  @override
  String get name => componentName;
  @override
  MovaSlot get slot => MovaSlot.bottom;
  /// 在 [context] 中构建标记文本；[api] 和 [children] 不参与显示。
  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) => const Text('marker');
}

void main() {
  for (final name in ['positionLabel', 'liveBadge', 'seekBar', 'timeshift', 'durationLabel', 'backToLive']) {
    testWidgets('底栏 $name 可移除及 insertAfter，直播布局不越界', (t) async {
      final api = FakeMovaApi();
      final live = !['positionLabel', 'durationLabel'].contains(name);
      api.push(MovaState(type: live ? MovaStreamType.live : MovaStreamType.vod, duration: const Duration(seconds: 100), liveSeekable: true));
      for (final patch in [MovaPatch.remove('bottomBar/$name'), MovaPatch.insertAfter('bottomBar/$name', _Marker())]) {
        final tree = applyPatches([MovaBottomBarComponent()], [patch]);
        await pumpComponent(t, api, tree.single);
        expect(t.takeException(), isNull);
        if (patch is MovaPatchRemove) {
          expect(find.byWidgetPredicate((w) => w is MovaBuiltChild && w.name == name), findsNothing);
        } else {
          expect(find.text('marker'), findsOneWidget);
          final anchor = find.byWidgetPredicate((w) => w is MovaBuiltChild && w.name == name);
          expect(t.getTopLeft(find.text('marker')).dx, greaterThanOrEqualTo(t.getTopLeft(anchor).dx));
        }
        api.push(const MovaState(type: MovaStreamType.live, liveSeekable: false));
        await t.pump();
        await t.pump();
        expect(t.takeException(), isNull);
        api.push(MovaState(type: live ? MovaStreamType.live : MovaStreamType.vod, duration: const Duration(seconds: 100), liveSeekable: true));
        await t.pumpWidget(const SizedBox());
      }
      await api.dispose();
    });
  }
}
