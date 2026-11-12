import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';

/// 演示语言状态；优先 URL，其次系统语言，最后英语。
class DemoLocale extends ChangeNotifier {
  /// 创建语言状态，可注入地址与系统语言供测试使用。
  DemoLocale({Uri? uri, Locale? browserLocale}) {
    final requested = (uri ?? Uri.base).queryParameters['lang'];
    final language =
        (browserLocale ?? PlatformDispatcher.instance.locale).languageCode;
    _language = requested == 'zh' || requested == 'en'
        ? requested!
        : language.toLowerCase().startsWith('zh')
        ? 'zh'
        : 'en';
  }

  /// 当前语言代码。
  late String _language;

  /// 当前是否为中文。
  bool get isChinese => _language == 'zh';

  /// 当前语言代码，只接受 zh 和 en。
  String get language => _language;

  /// 切换语言并通知全页更新。
  void select(String language) {
    if (!const ['zh', 'en'].contains(language) || language == _language) return;
    _language = language;
    notifyListeners();
  }
}

/// 向子树提供语言状态与变更通知。
class DemoLocaleScope extends InheritedNotifier<DemoLocale> {
  /// 创建语言作用域。
  const DemoLocaleScope({
    super.key,
    required DemoLocale locale,
    required super.child,
  }) : super(notifier: locale);

  /// 读取当前作用域的语言状态。
  static DemoLocale? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoLocaleScope>()?.notifier;
}

/// 按当前语言选择文案；作用域外默认使用英语。
String tr(BuildContext context, String en, String zh) =>
    DemoLocaleScope.maybeOf(context)?.isChinese == true ? zh : en;

/// 跨页面复用的双语控件文案。
abstract final class DemoLabels {
  /// 暂停按钮文案。
  static String pause(BuildContext context) => tr(context, 'Pause', '暂停');

  /// 继续按钮文案。
  static String resume(BuildContext context) => tr(context, 'Resume', '继续');

  /// 单个实例的重播提示文案。
  static String replay(BuildContext context) => tr(context, 'Replay', '重播');

  /// 重播按钮文案。
  static String restart(BuildContext context) => tr(context, 'Restart', '重新开始');

  /// 完成状态文案。
  static String completed(BuildContext context) =>
      tr(context, 'Completed', '已完成');

  /// 更新次数标签。
  static String updates(BuildContext context) => tr(context, 'Updates', '更新');
}
