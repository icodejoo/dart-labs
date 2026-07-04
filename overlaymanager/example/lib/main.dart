import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:layerman/layerman.dart';

/// One manager orchestrates everything: builtin cards in
/// [OverlayManagerScope]'s own layer, route-backed dialogs (native
/// `showDialog` / `Get.dialog`), GetX snackbars and bot_toast toasts.
OverlayManager om = _newManager();

/// `/zone` is a "no-overlay zone": entering it pauses the whole queue (no new
/// overlay activates) via [OverlayNavigatorObserver], leaving it resumes —
/// zero manual `setContext`/`pauseAll` calls anywhere in this page's code.
OverlayManager _newManager() => OverlayManager(
      gap: const Duration(milliseconds: 300),
      pauseOnRoutes: const ['/zone'],
    );

/// Lets [restartApp] reach the running [_AppRootState].
final GlobalKey<_AppRootState> _appRootKey = GlobalKey<_AppRootState>();

/// Restart the whole app: dispose the manager, build a fresh one and remount
/// `HomePage`. We do NOT call `runApp` again — re-running it would build a
/// second `GetMaterialApp` / `BotToastInit`, and those are init-once globals
/// (that was why the old restart button did nothing). Instead the stable root
/// swaps the manager and bumps a generation key so `HomePage` remounts fresh.
void restartApp() => _appRootKey.currentState?.restart();

void main() {
  om.setContext({'route': '/home'}); // initial state before any navigation
  runApp(AppRoot(key: _appRootKey));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  int _gen = 0;

  void restart() {
    setState(() {
      om.dispose(); // clears every active/queued overlay
      om = _newManager();
      om.setContext({'route': '/home'}); // initial state before any navigation
      _gen++; // remounts HomePage (resets its local state + rebinds to new om)
    });
  }

  @override
  Widget build(BuildContext context) {
    final botToastBuilder = BotToastInit();
    return GetMaterialApp(
      title: 'layerman × GetX × bot_toast',
      // OverlayNavigatorObserver feeds every push/pop/replace into om's route
      // context automatically — no more manual setContext calls per page.
      navigatorObservers: [
        BotToastNavigatorObserver(),
        OverlayNavigatorObserver(om),
      ],
      // bot_toast paints above everything; our Scope sits between it and the
      // Navigator, so: toasts > managed builtin entries > routes/dialogs.
      // The Scope re-attaches to the new manager on swap (didUpdateWidget).
      builder: (context, child) => botToastBuilder(
        context,
        OverlayManagerScope(manager: om, child: child!),
      ),
      // `home:` would leave the initial route named '/' (Flutter's own
      // Navigator.defaultRouteName, not '/home') — named `initialRoute` +
      // `routes` gives it the real name the rest of this demo assumes.
      initialRoute: '/home',
      routes: {'/home': (_) => HomePage(key: ValueKey(_gen))},
    );
  }
}

/// A real page: entering pushes route '/promo' automatically via
/// [OverlayNavigatorObserver] (no manual setContext call in this widget —
/// entering/leaving used to need initState/dispose boilerplate, gone now).
class PromoPage extends StatelessWidget {
  const PromoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PROMO PAGE')),
      body: const Center(
        child: Text('这里是 /promo 页面\n(条件卡只在此路由有资格显示)',
            textAlign: TextAlign.center),
      ),
    );
  }
}

/// A "no-overlay zone" page: while shown, `pauseOnRoutes: ['/zone']` freezes
/// the whole queue automatically (no new overlay activates) — leaving resumes
/// it. Also no manual pauseAll/resumeAll calls anywhere in this widget.
class NoOverlayZonePage extends StatelessWidget {
  const NoOverlayZonePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('免打扰区 /zone')),
      body: const Center(
        child: Text(
          '这里是免打扰区\n(pauseOnRoutes 自动冻结队列,离开后自动恢复)',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Route-backed dialog (native showDialog / Get.dialog) as an external
/// presenter: unique route name for targeted close, route future = dismissed.
PresentedOverlay<T> presentRouteDialog<T>(
  PresentContext ctx,
  Widget dialog, {
  bool useGetx = false,
}) {
  final name = 'om://${ctx.id}';
  final Future<T?> future = useGetx
      ? Get.dialog<T>(dialog, routeSettings: RouteSettings(name: name))
      : showDialog<T>(
          context: Get.overlayContext!,
          useRootNavigator: true,
          routeSettings: RouteSettings(name: name),
          builder: (_) => dialog,
        );
  return PresentedOverlay<T>(
    dismissed: future,
    dismiss: ([T? r]) async => Get.until((rt) => rt.settings.name != name),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool allowClose = false;
  int updN = 0;

  // Built once per HomePage mount (HomePage remounts on restart via its _gen
  // key, so this rebinds to the fresh manager) — avoids re-allocating and
  // re-subscribing every rebuild. No separate route mirror needed anymore:
  // om.currentRoute is read directly (om already notifies on every setContext).
  late final Listenable _stateListenable = om;

  /// A centered card overlay. [offset] positions stacked cards so several stay
  /// visible at once. [actions] are in-card buttons — multi-overlay interplay
  /// (replace/affix/overlap) is driven from INSIDE overlays.
  Widget _card(
    String text,
    OverlayHandle<Object?> handle, {
    Offset offset = Offset.zero,
    List<Widget> actions = const [],
    String? hint,
  }) =>
      Center(
        child: Transform.translate(
          offset: offset,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: const TextStyle(fontSize: 16)),
                  if (hint != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(hint,
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ...actions,
                      FilledButton(
                        onPressed: () => handle.close(),
                        child: Text('close $text'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _dialog(String title, String okKey) => AlertDialog(
        title: Text(title),
        content: const Text('scheduled by layerman'),
        actions: [
          Builder(
            builder: (context) => TextButton(
              key: Key(okKey),
              onPressed: () => Navigator.of(context).pop('ok'),
              child: Text(okKey),
            ),
          ),
        ],
      );

  /// One tap → three systems, strictly serialized by the manager.
  void _mixed() {
    om.open<String>(
      id: 'native-dlg',
      exitDuration: const Duration(milliseconds: 200),
      present: (ctx) =>
          presentRouteDialog(ctx, _dialog('Native dialog', 'OK-native')),
    );
    om.open<String>(
      id: 'getx-dlg',
      exitDuration: const Duration(milliseconds: 200),
      present: (ctx) => presentRouteDialog(
        ctx,
        _dialog('GetX dialog', 'OK-getx'),
        useGetx: true,
      ),
    );
    om.open<void>(
      id: 'toast',
      present: (ctx) {
        final done = Completer<void>();
        final cancel = BotToast.showText(
          text: 'bot_toast hello',
          duration: const Duration(seconds: 1),
          onlyOne: false,
          onClose: () {
            if (!done.isCompleted) done.complete();
          },
        );
        return PresentedOverlay<void>(
          dismissed: done.future,
          dismiss: ([_]) async => cancel(),
        );
      },
    );
  }

  void _snack() {
    om.open<void>(
      id: 'snack-${DateTime.now().millisecondsSinceEpoch}',
      slot: 'snack',
      present: (ctx) {
        final c = Get.snackbar(
          'Saved',
          'scheduled by layerman',
          duration: const Duration(seconds: 1),
          animationDuration: const Duration(milliseconds: 300),
        );
        return PresentedOverlay<void>(
          dismissed: c.future,
          dismiss: ([_]) => c.close(),
        );
      },
    );
  }

  /// #1 replace 演示：先开 R1，R1 内部按钮再开一个 replace 弹窗顶掉自己。
  void _replaceDemo() {
    om.open(
      id: 'r1',
      builder: (c, h) => _card(
        'R1',
        h,
        hint: '点「替换为 R2」→ R2 顶掉 R1；关掉 R2 后 R1 会自动回来',
        actions: [
          FilledButton.tonal(
            onPressed: () => om.open(
              id: 'r2',
              replace: true,
              builder: (c2, h2) => _card('R2', h2,
                  hint: 'R1 被顶掉但退回了队列；关掉我，R1 就回来'),
            ),
            child: const Text('替换为 R2'),
          ),
        ],
      ),
    );
  }

  /// #2 affix 演示：FIX 固定；其内部按钮尝试 replace，观察 FIX 不被覆盖。
  void _affixDemo() {
    om.open(
      id: 'fix',
      affix: true,
      builder: (c, h) => _card(
        'FIX',
        h,
        hint: 'affix 固定：下面的 replace 顶不掉我，只能排队',
        actions: [
          FilledButton.tonal(
            onPressed: () => om.open(
              id: 'try',
              replace: true,
              builder: (c2, h2) =>
                  _card('TRY', h2, hint: '我在 FIX 关闭后才轮到'),
            ),
            child: const Text('尝试 replace 顶掉 FIX'),
          ),
        ],
      ),
    );
  }

  /// #3 程序驱动：先开 1 个，2 秒后程序继续向队列推送 2 个（串行推进可观察）。
  void _dataDriven() {
    final m = om; // 防重启后误推
    m.open(id: 'x1', builder: (c, h) => _card('X1', h, hint: '2 秒后程序会追加 X2/X3 入队'));
    Timer(const Duration(seconds: 2), () {
      if (!identical(m, om)) return;
      m.open(id: 'x2', builder: (c, h) => _card('X2', h));
      m.open(id: 'x3', builder: (c, h) => _card('X3', h));
    });
  }

  /// #4 两组 2×2：A 组左列、B 组右列，clearWhere 只清 A 组。
  void _groups() {
    const a = {'group': 'a'};
    const b = {'group': 'b'};
    om.open(id: 'a1', overlap: true, data: a, builder: (c, h) => _card('A1', h, offset: const Offset(-130, -70)));
    om.open(id: 'a2', overlap: true, data: a, builder: (c, h) => _card('A2', h, offset: const Offset(-130, 70)));
    om.open(id: 'b1', overlap: true, data: b, builder: (c, h) => _card('B1', h, offset: const Offset(130, -70)));
    om.open(id: 'b2', overlap: true, data: b, builder: (c, h) => _card('B2', h, offset: const Offset(130, 70)));
  }

  Widget _btn(String key, String text, VoidCallback onTap) => FilledButton.tonal(
        key: Key(key),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 30),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('layerman 全功能真机演示')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _btn('btn-mixed', '三系统串行', _mixed),
                _btn('btn-snack', 'GetX snackbar', _snack),
                _btn('btn-queue3', '串行3个(蒙层可关)', () {
                  for (var i = 1; i <= 3; i++) {
                    om.open(
                      id: 'c$i',
                      barrierColor: const Color(0x66000000),
                      barrierDismissible: true,
                      builder: (c, h) => _card('C$i', h),
                    );
                  }
                }),
                _btn('btn-replace-demo', 'replace 演示', _replaceDemo),
                _btn('btn-affix', 'affix 演示', _affixDemo),
                _btn('btn-overlap', 'overlap 演示', () {
                  om.open(
                    id: 'ova',
                    builder: (c, h) => _card(
                      'OVA',
                      h,
                      hint: '点「stack B」叠加 OVB，两卡同屏',
                      actions: [
                        FilledButton.tonal(
                          onPressed: () => om.open(
                            id: 'ovb',
                            overlap: true,
                            builder: (c2, h2) =>
                                _card('OVB', h2, offset: const Offset(0, 110)),
                          ),
                          child: const Text('stack B'),
                        ),
                      ],
                    ),
                  );
                }),
                _btn('btn-pause', 'pauseAll', om.pauseAll),
                _btn('btn-resume', 'resumeAll', om.resumeAll),
                _btn('btn-data', '程序驱动(渐进入队)', _dataDriven),
                _btn('btn-groups', '两组 2×2', _groups),
                _btn('btn-clear-a', 'clearWhere 清A组', () {
                  om.clearWhere(
                      (r) => r.data is Map && (r.data as Map)['group'] == 'a');
                }),
                _btn('btn-goto-promo', '跳转 /promo 页', () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/promo'),
                    builder: (_) => const PromoPage(),
                  ));
                }),
                _btn('btn-queue-in-zone', '免打扰区内排一张卡', () {
                  om.open(id: 'zone-card', builder: (c, h) => _card('ZONE',
                      h, hint: '在 /zone 时不会弹出;离开后自动显示'));
                }),
                _btn('btn-goto-zone', '跳转免打扰区(/zone)', () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/zone'),
                    builder: (_) => const NoOverlayZonePage(),
                  ));
                }),
                _btn('btn-cond', '入队条件卡(仅/promo)', () {
                  om.open(
                    id: 'cond',
                    route: '/promo',
                    builder: (c, h) => _card(
                      'COND',
                      h,
                      hint: "route:'/promo' 精确匹配 setContext 的 route；\n"
                          '离开 promo 页会被 dismissWhenUnmet 自动撤下',
                    ),
                  );
                }),
                _btn('btn-nudge', '触发重评', () => om.setContext({})),
                _btn('btn-cds', '冷却 session=1', () {
                  om.open(
                    id: 'cd-s',
                    cooldown: const OverlayCooldown(session: 1),
                    builder: (c, h) => _card('CDS', h),
                  );
                }),
                _btn('btn-cdg', '冷却 minGap=2s', () {
                  om.open(
                    id: 'cd-g',
                    cooldown:
                        const OverlayCooldown(minGap: Duration(seconds: 2)),
                    builder: (c, h) => _card('CDG', h,
                        hint: '关掉后 2s 内再点会入队；到 2s 冷却期满自动弹出'),
                  );
                }),
                _btn('btn-resolve', 'resolve 取数', () {
                  om.open(
                    id: 'rsv',
                    resolve: () async {
                      await Future<void>.delayed(
                          const Duration(milliseconds: 300));
                      return const {'v': 42};
                    },
                    builder: (c, h) =>
                        _card('DATA:${(h.data as Map)['v']}', h),
                  );
                }),
                _btn('btn-guard', 'beforeClose 卡', () {
                  allowClose = false; // 每次打开都重置为锁定
                  om.open(
                    id: 'guard',
                    data: const {'locked': true},
                    beforeClose: () => allowClose,
                    builder: (c, h) => _card(
                      (h.data as Map)['locked'] == true
                          ? 'GUARD 🔒'
                          : 'GUARD 🔓',
                      h,
                      hint: '🔒 时 close 被守卫否决；点「解锁 guard」后才能关',
                    ),
                  );
                }),
                _btn('btn-unlock', '解锁 guard', () {
                  allowClose = true;
                  om.update('guard', {'locked': false});
                }),
                _btn('btn-upd-show', 'update 演示卡', () {
                  updN = 0;
                  om.open(
                    id: 'upd',
                    data: const {'n': 0},
                    builder: (c, h) => _card('n=${(h.data as Map)['n']}', h),
                  );
                }),
                _btn('btn-update', 'update n+1', () {
                  updN++;
                  om.update('upd', {'n': updN});
                }),
                _btn('btn-clear', 'clear', om.clear),
                _btn('btn-restart', '⟳ 重启应用', restartApp),
              ],
            ),
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _stateListenable,
              builder: (context, _) => Text(
                '路由: ${om.currentRoute ?? "(未知)"}${om.isPaused ? "  [已暂停]" : ""}\n'
                '活跃: ${om.activeIds.join(", ")}\n'
                '队列: ${om.queuedIds.join(", ")}',
                key: const Key('state'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
