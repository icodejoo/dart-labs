import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luckdraw/extend.dart';

/// 验证实例注册表没有隐式加载或默认玩法。
void main() {
  group('LuckyGameRegistry', () {
    testWidgets(
        'is empty by default and only contains explicitly added builders',
        (tester) async {
      final first = LuckyGameRegistry();
      final second = LuckyGameRegistry();
      expect(first.keys, isEmpty);
      expect(second.keys, isEmpty);
      first.add('custom', (_, __) => const SizedBox());
      expect(first.keys, ['custom']);
      expect(second.keys, isEmpty);
      expect(() => (first.keys as List<String>).add('other'),
          throwsUnsupportedError);
    });
    testWidgets('builds a widget from a registered builder by key',
        (tester) async {
      final registry = LuckyGameRegistry();
      registry.add('custom', (_, json) => Text(json['label'] as String));
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) =>
                  registry.build('custom', context, {'label': '自定义'})!)));
      expect(find.text('自定义'), findsOneWidget);
      registry.add('custom', (_, __) => const Text('覆盖'));
      await tester.pumpWidget(Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
              builder: (context) => registry.build('custom', context, {})!)));
      expect(find.text('覆盖'), findsOneWidget);
    });
    testWidgets('unknown key returns null', (tester) async {
      final registry = LuckyGameRegistry();
      await tester.pumpWidget(Builder(builder: (context) {
        expect(registry.build('unknown', context, {}), isNull);
        return const SizedBox();
      }));
    });
  });
}
