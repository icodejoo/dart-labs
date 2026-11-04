// scope_resolution 是包内文件，不从 countman.dart 导出，测试直接导入。
import 'package:countman/countman.dart';
import 'package:countman/src/widgets/scope_resolution.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// 找不到任何祖先 InheritedWidget 的上下文，模拟没有 MediaQuery 的场景
/// （测试宿主自带 MediaQuery，无法用真实组件树构造）。
class _NoMediaQueryContext extends Fake implements BuildContext {
  @override
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() => null;

  @override
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) => null;
}

/// 构造只设置插件的作用域；其余视觉默认值全部为空。
Widget _scope<P>(P? plugin, Widget child) => CountmanScope<P>(
  plugin: plugin,
  textStyle: null,
  color: null,
  trackColor: null,
  duration: null,
  curve: null,
  allowNegative: null,
  repaintBoundary: null,
  child: child,
);

/// 在 initState 与 didChangeDependencies 里分别解析插件，并回调解析结果。
class _Probe extends StatefulWidget {
  /// [widgetPlugin] 为组件显式插件，[fallback] 为兜底插件。
  const _Probe({
    super.key,
    required this.fallback,
    this.widgetPlugin,
    required this.onInit,
    required this.onDependent,
  });

  /// 组件显式插件。
  final Countdown? widgetPlugin;

  /// 兜底插件。
  final Countdown fallback;

  /// initState 里（不注册依赖）解析的结果回调。
  final void Function(Countdown) onInit;

  /// didChangeDependencies 里（注册依赖）解析的结果回调。
  final void Function(Countdown) onDependent;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onInit(
      resolvePlugin<Countdown>(
        context,
        widgetPlugin: widget.widgetPlugin,
        fallback: () => widget.fallback,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onDependent(
      resolvePluginDependent<Countdown>(
        context,
        widgetPlugin: widget.widgetPlugin,
        fallback: () => widget.fallback,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// 验证减弱动画判断与插件解析的优先级、依赖注册语义。
void main() {
  group('reduceMotionOf', () {
    late bool result;
    Widget probe() => Builder(
      builder: (context) {
        result = reduceMotionOf(context);
        return const SizedBox();
      },
    );

    testWidgets('优先读取 MediaQuery 的 disableAnimations', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: probe(),
        ),
      );
      expect(result, isTrue);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: probe(),
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('MediaQuery 的值覆盖平台标志', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: probe(),
        ),
      );
      expect(result, isFalse);
    });

    testWidgets('没有 MediaQuery 时回退到平台标志', (tester) async {
      final context = _NoMediaQueryContext();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      expect(reduceMotionOf(context), isTrue);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      expect(reduceMotionOf(context), isFalse);
    });
  });

  group('resolvePlugin', () {
    testWidgets('优先级：组件显式插件 > 作用域插件 > 兜底', (tester) async {
      final explicit = Countdown(name: 'explicit');
      final scoped = Countdown(name: 'scoped');
      final fallback = Countdown(name: 'fallback');
      Countdown? initResult;
      Countdown? dependentResult;
      Widget probe({Countdown? widgetPlugin}) => _Probe(
        key: UniqueKey(),
        widgetPlugin: widgetPlugin,
        fallback: fallback,
        onInit: (p) => initResult = p,
        onDependent: (p) => dependentResult = p,
      );

      await tester.pumpWidget(probe());
      expect(initResult, same(fallback));
      expect(dependentResult, same(fallback));

      await tester.pumpWidget(_scope<Countdown>(scoped, probe()));
      expect(initResult, same(scoped));
      expect(dependentResult, same(scoped));

      await tester.pumpWidget(
        _scope<Countdown>(scoped, probe(widgetPlugin: explicit)),
      );
      expect(initResult, same(explicit));
      expect(dependentResult, same(explicit));
    });

    testWidgets('作用域按插件类型查找，其他类型的作用域不会命中', (tester) async {
      final fallback = Countdown(name: 'fallback-type');
      Countdown? result;
      await tester.pumpWidget(
        _scope<Elapsed>(
          Elapsed(name: 'other-family'),
          _Probe(
            fallback: fallback,
            onInit: (p) => result = p,
            onDependent: (_) {},
          ),
        ),
      );
      expect(result, same(fallback));
    });

    testWidgets('作用域里没有插件时回退到 fallback', (tester) async {
      final fallback = Countdown(name: 'fallback-null-scope');
      Countdown? result;
      await tester.pumpWidget(
        _scope<Countdown>(
          null,
          _Probe(
            fallback: fallback,
            onInit: (p) => result = p,
            onDependent: (_) {},
          ),
        ),
      );
      expect(result, same(fallback));
    });

    testWidgets('resolvePlugin 不注册依赖，resolvePluginDependent 会', (tester) async {
      final first = Countdown(name: 'scope-1');
      final second = Countdown(name: 'scope-2');
      final fallback = Countdown(name: 'fallback-dep');
      var inits = 0;
      var dependents = 0;
      Countdown? lastDependent;
      Widget tree(Countdown scoped) => _scope<Countdown>(
        scoped,
        _Probe(
          fallback: fallback,
          onInit: (_) => inits++,
          onDependent: (p) {
            dependents++;
            lastDependent = p;
          },
        ),
      );

      await tester.pumpWidget(tree(first));
      expect(inits, 1);
      expect(dependents, 1);
      await tester.pumpWidget(tree(second));
      // 作用域变化：依赖版本再次解析，initState 版本不会重复执行。
      expect(inits, 1);
      expect(dependents, 2);
      expect(lastDependent, same(second));
    });

    testWidgets('fallback 仅在需要时才调用', (tester) async {
      var created = 0;
      late Countdown result;
      final explicit = Countdown(name: 'lazy-explicit');
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            result = resolvePlugin<Countdown>(
              context,
              widgetPlugin: explicit,
              fallback: () {
                created++;
                return Countdown(name: 'lazy-fallback');
              },
            );
            return const SizedBox();
          },
        ),
      );
      expect(result, same(explicit));
      expect(created, 0);
    });
  });
}
