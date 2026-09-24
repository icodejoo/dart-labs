import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Standalone manual/on-device demo for the in-app mini window (0.6.0).
/// Deliberately not folded into `main.dart`: this page exists so both
/// mounting modes — in-page floating and cross-route persistent — can each be
/// walked on their own with real event-driven logging, per the project's
/// "verification demo gets its own page, never mixed with other spikes"
/// convention.
///
/// Run with: `flutter run -t lib/mini_window_demo.dart -d windows` (or
/// `-d <android-device-id>`).
///
/// App 内小窗（0.6.0）的独立手工/真机 demo 页。刻意不塞进 `main.dart`：本页存在
/// 的意义就是让两种挂载方式——页内悬浮与跨路由持久——各自能被单独走一遍，配合
/// 真实事件打点，对齐项目"验收 demo 要为该功能单独建一个页面，不与其他 spike
/// 混用"的约定。
///
/// 运行：`flutter run -t lib/mini_window_demo.dart -d windows`。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaEngine.ensureInitialized();
  runApp(const _MiniWindowDemoApp());
}

/// The demo source shared by every entry point in this page.
///
/// 本页所有入口共用的演示素材。
const _demoSource = MovaSource(
  'https://user-images.githubusercontent.com/28951144/229373695-22f88f13-d18f-4288-9bf1-c3e078d83722.mp4',
  title: '小窗演示素材 / mini-window demo material',
);

/// Route-independent state shared by the whole demo app — created once at
/// the app root, exactly matching the README's "step 1" for mount B.
///
/// 整个 demo app 共用的路由外状态——在 app 根节点建一次，与 README 方式 B
/// "第一步"完全对齐。
// onTapContent 留空（默认无操作）：本 demo 刻意只允许显式点击关闭（✕）按钮
// 收起小窗，避免真机验证时误触画面就把小窗“弄没了”。
final _miniCtl = MovaMiniCtl();

/// Append-only log of real events (`MovaMiniChg`/`MovaPipChg`/
/// `MovaFullScreenChg`) so the demo works without logcat, per project
/// convention.
///
/// 真实事件（`MovaMiniChg`/`MovaPipChg`/`MovaFullScreenChg`）的追加日志，
/// 不依赖 logcat，对齐项目约定。
final ValueNotifier<List<String>> _eventLog = ValueNotifier(const []);

void _log(String line) {
  final now = TimeOfDay.now();
  _eventLog.value = [
    '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')} $line',
    ..._eventLog.value,
  ].take(30).toList();
}

/// Wires [engine]'s event stream into [_log]; call once per engine created.
///
/// 把 [engine] 的事件流接进 [_log]；每个新建的 engine 调一次。
void _wireEventLog(MovaEngine engine) {
  engine.events.listen((e) {
    if (e is MovaMiniChg) _log('MovaMiniChg(${e.mini})');
    if (e is MovaPipChg) _log('MovaPipChg(${e.value})');
    if (e is MovaFullScreenChg) _log('MovaFullScreenChg(${e.value})');
  });
}

/// The demo app shell — `MaterialApp.builder` wires [MovaMiniHost] for
/// mount B (persistent), exactly as the README documents.
///
/// demo 应用外壳——`MaterialApp.builder` 接入 [MovaMiniHost] 实现方式 B
/// （跨路由持久），与 README 文档完全一致。
class _MiniWindowDemoApp extends StatelessWidget {
  /// Creates the demo app.
  ///
  /// 创建 demo 应用。
  const _MiniWindowDemoApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'mova mini-window demo',
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MovaMiniHost(ctl: _miniCtl, child: child!),
        home: const _HubPage(),
      );
}

/// Landing page: four config toggles + entry points into both mounting
/// modes.
///
/// 首页：四个配置开关 + 两种挂载方式的入口。
class _HubPage extends StatefulWidget {
  const _HubPage();

  @override
  State<_HubPage> createState() => _HubPageState();
}

class _HubPageState extends State<_HubPage> {
  bool _enabled = true;
  bool _snapToEdge = true;
  bool _dismissible = true;
  MovaMiniCorner _corner = MovaMiniCorner.bottomRight;

  MovaMiniConfig get _config => MovaMiniConfig(
        enabled: _enabled,
        snapToEdge: _snapToEdge,
        dismissible: _dismissible,
        initialCorner: _corner,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App 内小窗（0.6.0）')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('enabled'),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            title: const Text('snapToEdge'),
            value: _snapToEdge,
            onChanged: (v) => setState(() => _snapToEdge = v),
          ),
          SwitchListTile(
            title: const Text('dismissible（甩出关闭）'),
            value: _dismissible,
            onChanged: (v) => setState(() => _dismissible = v),
          ),
          ListTile(
            title: const Text('initialCorner'),
            trailing: DropdownButton<MovaMiniCorner>(
              value: _corner,
              items: MovaMiniCorner.values
                  .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                  .toList(),
              onChanged: (c) => setState(() => _corner = c!),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('方式 A · 页内悬浮（长列表）'),
            subtitle: const Text('滚动不受影响，可拖拽；push 新页会被盖住（预期行为）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _InPageListDemo(config: _config),
            )),
          ),
          ListTile(
            title: const Text('方式 B · 跨路由持久'),
            subtitle: const Text('缩小后 pop/push 任意多层，小窗一直在最上'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _PersistentPlayerPage(config: _config),
            )),
          ),
          const Divider(),
          ListTile(
            title: const Text('故意错误用法：dispose 前不检查 isShowing'),
            subtitle: const Text('debug 下应触发 MovaEngine.dispose() 的 mini 态 assert'),
            trailing: const Icon(Icons.warning_amber_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => _MisuseDemo(config: _config),
            )),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('事件日志', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ValueListenableBuilder<List<String>>(
            valueListenable: _eventLog,
            builder: (context, lines, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.map((l) => Text(l, style: const TextStyle(fontSize: 12))).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mount A demo: a long scrollable list with an in-page floating mini window.
///
/// 方式 A demo：带页内悬浮小窗的长可滚动列表。
class _InPageListDemo extends StatefulWidget {
  const _InPageListDemo({required this.config});

  final MovaMiniConfig config;

  @override
  State<_InPageListDemo> createState() => _InPageListDemoState();
}

class _InPageListDemoState extends State<_InPageListDemo> {
  MovaEngine? _engine;

  @override
  void dispose() {
    // 页面必须在 dispose 里调一次 hide()/close()，否则 MovaState.mini 会停在
    // true 而无人渲染 —— 本 demo 正确演示这一步（§1.7 的必做动作）。
    final e = _engine;
    if (e != null) {
      if (_miniCtl.isShowing(e)) {
        _miniCtl.hide();
      }
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _showInPage(BuildContext context) async {
    final engine = createMovaEngine(options: MovaOpts(mini: widget.config));
    _wireEventLog(engine);
    await engine.open(_demoSource);
    _engine = engine;
    if (!context.mounted) return;
    await _miniCtl.showInPage(context, engine);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('方式 A · 页内悬浮')),
      body: ListView.builder(
        itemCount: 100,
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton(
                onPressed: () => _showInPage(context),
                child: const Text('页内小窗播放'),
              ),
            );
          }
          return ListTile(title: Text('列表项 $i'));
        },
      ),
    );
  }
}

/// Mount B demo: shrink-to-mini, pop back to the hub, push another route —
/// the window stays on top and keeps playing throughout.
///
/// 方式 B demo：缩小到小窗、pop 回首页、再 push 另一个路由——小窗全程留在
/// 最上层且持续播放。
class _PersistentPlayerPage extends StatefulWidget {
  const _PersistentPlayerPage({required this.config});

  final MovaMiniConfig config;

  @override
  State<_PersistentPlayerPage> createState() => _PersistentPlayerPageState();
}

class _PersistentPlayerPageState extends State<_PersistentPlayerPage> {
  late final MovaEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = createMovaEngine(options: MovaOpts(mini: widget.config));
    _wireEventLog(_engine);
    _engine.open(_demoSource);
    _miniCtl.onClosed = (api) => (api as MovaEngine).dispose();
  }

  @override
  void dispose() {
    // 借用不持有：本引擎的销毁完全交给 _miniCtl.onClosed（用户点了关闭）或者
    // 页面自己在从未进入过小窗态时兜底销毁。
    if (!_miniCtl.isShowing(_engine)) {
      _engine.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('方式 B · 跨路由持久')),
      // 用 SingleChildScrollView 兜底：窗口偏窄/偏矮时 16:9 的 AspectRatio 会
      // 撑出比可视区域更高的高度，Center+Column(mainAxisSize.min) 挡不住这种
      // 溢出，会把下面的按钮挤出屏幕——加滚动容器保证按钮始终可达。
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: MovaPlayer(api: _engine),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await _miniCtl.show(_engine, skin: const MovaMiniSkin());
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('缩小到小窗并返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A deliberately-wrong-usage page: disposes its engine on `dispose()`
/// without checking `isShowing` first — used to see the debug-only assert
/// from `MovaEngine.dispose()` fire on purpose (teaching + regression).
///
/// 一个故意的错误用法页面：`dispose()` 时不先检查 `isShowing` 就销毁引擎——
/// 用来亲眼看到 `MovaEngine.dispose()` 那条 debug-only assert 被触发
/// （教学 + 回归）。
class _MisuseDemo extends StatefulWidget {
  const _MisuseDemo({required this.config});

  final MovaMiniConfig config;

  @override
  State<_MisuseDemo> createState() => _MisuseDemoState();
}

class _MisuseDemoState extends State<_MisuseDemo> {
  late final MovaEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = createMovaEngine(options: MovaOpts(mini: widget.config));
    _engine.open(_demoSource);
  }

  @override
  void dispose() {
    // 故意不检查 isShowing —— 这是文档明令警告的错误用法，用来演示
    // MovaEngine.dispose() 的 debug-only assert。但 dispose() 是 async 的，
    // State.dispose() 又不能 await 它——不接住这个 Future 的错误，assert
    // 失败会变成没人处理的 Future rejection，直接杀死整个 isolate/app（表现
    // 为窗口悄无声息消失，无崩溃弹窗、无原生崩溃日志），而不是仅在控制台打印
    // 一条调试期错误。这里补一个 catchError 只做展示用途的错误上报，不改变
    // "不检查 isShowing"这个故意错误用法本身。
    _engine.dispose().catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'mova mini_window_demo',
        context: ErrorDescription('故意错误用法页面 dispose() 时未检查 isShowing'),
      ));
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('故意错误用法')),
      // 同 _PersistentPlayerPage：加滚动容器兜底，避免窗口偏窄/偏矮时
      // AspectRatio 撑出溢出（曾在真机上引发密集纹理重建循环并使应用崩溃）。
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: MovaPlayer(api: _engine)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await _miniCtl.show(_engine);
                if (context.mounted) Navigator.of(context).pop(); // 触发 dispose() 时仍在小窗态
              },
              child: const Text('缩小到小窗后直接返回（不检查 isShowing）'),
            ),
          ],
        ),
      ),
    );
  }
}
