import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'demo_kit/demo_kit.dart';
import 'demo_session.dart';
import 'demo_settings.dart';
import 'demo_widgets.dart';
import 'pages/config_page.dart';
import 'pages/connection_page.dart';
import 'pages/send_page.dart';
import 'pages/subscribe_page.dart';

/// 从打包的包配置读取版本，避免 demo chip 与包版本分叉。
Future<String> loadPackageVersion() async {
  final manifest = await rootBundle.loadString(DemoSettings.packageManifest);
  return RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(manifest)!.group(1)!;
}

/// 初始化绑定并启动双语演示。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StompsocketDemoApp(version: await loadPackageVersion()));
}

/// 演示入口，测试可注入语言、会话和初始页。
class StompsocketDemoApp extends StatefulWidget {
  /// 接收来自包配置的版本；注入会话由调用者释放。
  const StompsocketDemoApp({
    super.key,
    required this.version,
    this.locale,
    this.session,
    this.initialFragment,
  });

  /// 当前包版本。
  final String version;

  /// 测试或宿主指定的语言状态。
  final DemoLocale? locale;

  /// 测试或宿主指定的会话。
  final DemoSession? session;

  /// 初始页面 hash。
  final String? initialFragment;

  /// 创建拥有会话生命周期的状态。
  @override
  State<StompsocketDemoApp> createState() => _StompsocketDemoAppState();
}

/// 在页面切换之间保留会话，并在应用退出时释放。
class _StompsocketDemoAppState extends State<StompsocketDemoApp> {
  /// 使用外部会话或创建应用自己的会话。
  late final DemoSession _session = widget.session ?? DemoSession();

  /// 释放本入口创建的会话。
  @override
  void dispose() {
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  /// 构建统一页头、响应式导航与四个 API 页面。
  @override
  Widget build(BuildContext context) => DemoApp(
    title: DemoSettings.project,
    seedColor: Colors.deepPurple,
    locale: widget.locale,
    home: DemoSessionScope(
      session: _session,
      child: DemoShell(
        project: DemoSettings.project,
        version: widget.version,
        pubUrl: DemoSettings.pubUrl,
        githubUrl: DemoSettings.githubUrl,
        readmeUrl: DemoSettings.readmeUrl,
        initialFragment: widget.initialFragment,
        destinations: [
          DemoDestination(
            id: 'connection',
            en: DemoCopy.connectionEn,
            zh: DemoCopy.connectionZh,
            icon: Icons.wifi_outlined,
            builder: (_) => const ConnectionPage(),
          ),
          DemoDestination(
            id: 'subscribe',
            en: DemoCopy.subscriptionsEn,
            zh: DemoCopy.subscriptionsZh,
            icon: Icons.notifications_active_outlined,
            builder: (_) => const SubscribePage(),
          ),
          DemoDestination(
            id: 'send',
            en: DemoCopy.sendEn,
            zh: DemoCopy.sendZh,
            icon: Icons.send_outlined,
            builder: (_) => const SendPage(),
          ),
          DemoDestination(
            id: 'config',
            en: DemoCopy.referenceEn,
            zh: DemoCopy.referenceZh,
            icon: Icons.tune_outlined,
            builder: (_) => const ConfigPage(),
          ),
        ],
      ),
    ),
  );
}
