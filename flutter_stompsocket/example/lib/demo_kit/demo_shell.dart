import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'demo_app.dart';
import 'i18n.dart';
import 'links_stub.dart' if (dart.library.js_interop) 'links_web.dart';

/// 导航项的数据契约，所有项目相关信息由调用者传入。
class DemoDestination {
  /// 创建稳定标识与双语名称的导航项。
  const DemoDestination({
    required this.id,
    required this.en,
    required this.zh,
    required this.icon,
    required this.builder,
    this.sectionEn = 'Explore',
    this.sectionZh = '探索',
  });

  /// 用于 URL 的稳定页面标识。
  final String id;

  /// 英文名称。
  final String en;

  /// 中文名称。
  final String zh;

  /// 导航图标。
  final IconData icon;

  /// 页面构造器。
  final WidgetBuilder builder;

  /// 英文分组标题。
  final String sectionEn;

  /// 中文分组标题。
  final String sectionZh;
}

/// 带页头、分组导航和 URL hash 同步的演示骨架。
class DemoShell extends StatefulWidget {
  /// 创建骨架，外链必须由项目显式传入。
  const DemoShell({
    super.key,
    required this.project,
    required this.version,
    required this.destinations,
    required this.pubUrl,
    required this.githubUrl,
    required this.readmeUrl,
    this.initialFragment,
  });

  /// 项目名称。
  final String project;

  /// 包版本号。
  final String version;

  /// 页面导航项，至少一项且标识唯一。
  final List<DemoDestination> destinations;

  /// pub.dev 外链。
  final String pubUrl;

  /// GitHub 外链。
  final String githubUrl;

  /// README 外链。
  final String readmeUrl;

  /// 可选初始 hash，供宿主或测试注入。
  final String? initialFragment;

  /// 创建导航状态。
  @override
  State<DemoShell> createState() => _DemoShellState();
}

/// 管理当前页面与浏览器历史的骨架状态。
class _DemoShellState extends State<DemoShell> {
  /// hash 中的页面路径前缀。
  static const _prefix = '/pages/';

  /// 当前页面标识。
  late String _selected;

  /// 从 URL 中提取已知页面，未知页面回退第一项。
  String _resolve(String fragment) {
    final path = Uri.tryParse(fragment)?.path ?? '';
    final id = path.startsWith(_prefix) ? path.substring(_prefix.length) : '';
    return widget.destinations.any((item) => item.id == id)
        ? id
        : widget.destinations.first.id;
  }

  /// 注册浏览器历史监听并规范化初始 hash。
  @override
  void initState() {
    super.initState();
    assert(widget.destinations.isNotEmpty);
    _selected = _resolve(widget.initialFragment ?? Uri.base.fragment);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _writeRoute(replace: true);
    });
  }

  /// 将当前页写入默认 hash URL 策略。
  Future<void> _writeRoute({bool replace = false}) async {
    final uri = Uri(path: '$_prefix$_selected');
    DemoRouteScope.record(context, uri);
    await SystemNavigator.selectMultiEntryHistory();
    if (!mounted) return;
    await SystemNavigator.routeInformationUpdated(uri: uri, replace: replace);
  }

  /// 处理根作用域传来的浏览器后退和前进。
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = DemoRouteScope.routeOf(context);
    if (route != null) {
      _selected = _resolve(
        route.fragment.isNotEmpty ? route.fragment : route.path,
      );
    }
  }

  /// 选择页面并写入历史。
  void _navigate(String id) {
    if (_selected == id) return;
    setState(() => _selected = id);
    _writeRoute();
  }

  /// 打开外链；原生平台显示复制结果。
  Future<void> _link(String url) async {
    final opened = await openDemoLink(url);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(context, 'Link copied', '链接已复制'))),
      );
    }
  }

  /// 构建支持分组标题的导航列表。
  Widget _navigation(bool drawer) => ListView(
    padding: const EdgeInsets.all(DemoTokens.gap),
    children: [
      if (drawer)
        Padding(
          padding: const EdgeInsets.all(DemoTokens.gap),
          child: Text(
            widget.project,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
      for (var i = 0; i < widget.destinations.length; i++) ...[
        if (i == 0 ||
            widget.destinations[i].sectionEn !=
                widget.destinations[i - 1].sectionEn)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              tr(
                context,
                widget.destinations[i].sectionEn,
                widget.destinations[i].sectionZh,
              ),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DemoTokens.gap),
          ),
          selected: _selected == widget.destinations[i].id,
          selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
          leading: Icon(widget.destinations[i].icon),
          title: Text(
            tr(context, widget.destinations[i].en, widget.destinations[i].zh),
          ),
          onTap: () {
            if (drawer) Navigator.pop(context);
            _navigate(widget.destinations[i].id);
          },
        ),
      ],
    ],
  );

  /// 构建统一的双语分段开关。
  Widget _language() => SegmentedButton<String>(
    showSelectedIcon: false,
    style: const ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(48, DemoTokens.controlSize)),
    ),
    segments: const [
      ButtonSegment(value: 'en', label: Text('EN')),
      ButtonSegment(value: 'zh', label: Text('中文')),
    ],
    selected: {DemoLocaleScope.maybeOf(context)!.language},
    onSelectionChanged: (value) =>
        DemoLocaleScope.maybeOf(context)!.select(value.first),
  );

  /// 构建统一的亮暗与外链操作。
  List<Widget> _actions() => [
    IconButton(
      tooltip: tr(context, 'Toggle theme', '切换亮暗'),
      onPressed: DemoAppearance.of(context).toggle,
      icon: Icon(
        Theme.of(context).brightness == Brightness.dark
            ? Icons.light_mode_outlined
            : Icons.dark_mode_outlined,
      ),
    ),
    IconButton(
      tooltip: 'pub.dev',
      onPressed: () => _link(widget.pubUrl),
      icon: const Icon(Icons.inventory_2_outlined),
    ),
    IconButton(
      tooltip: 'GitHub',
      onPressed: () => _link(widget.githubUrl),
      icon: const Icon(Icons.code_rounded),
    ),
    IconButton(
      tooltip: tr(context, 'Read documentation', '阅读文档'),
      onPressed: () => _link(widget.readmeUrl),
      icon: const Icon(Icons.menu_book_outlined),
    ),
  ];

  /// 根据宽度切换侧栏与抽屉，手机页头分两行避免挤压。
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= DemoTokens.sidebarBreakpoint;
      final compact = constraints.maxWidth < DemoTokens.tabletBreakpoint;
      final page = widget.destinations.firstWhere(
        (item) => item.id == _selected,
      );
      return Scaffold(
        drawer: wide ? null : Drawer(child: SafeArea(child: _navigation(true))),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: wide
              ? null
              : Builder(
                  builder: (context) => IconButton(
                    tooltip: tr(context, 'Open navigation', '打开导航'),
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
          titleSpacing: wide ? DemoTokens.padding : 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.project,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: DemoTokens.smallGap),
              Chip(
                label: Text(widget.version),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
                padding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            if (!compact) _language(),
            if (compact) _actions().first else ..._actions(),
            const SizedBox(width: DemoTokens.smallGap),
          ],
          bottom: compact
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(56),
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: DemoTokens.smallGap),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DemoTokens.padding,
                      ),
                      child: Row(
                        children: [
                          _language(),
                          const Spacer(),
                          ..._actions().skip(1),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              SizedBox(
                key: const ValueKey('demo-sidebar'),
                width: 224,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: _navigation(false),
                ),
              ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_selected),
                child: page.builder(context),
              ),
            ),
          ],
        ),
      );
    },
  );
}
