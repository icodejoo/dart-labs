import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';

/// 当前 headless API 的接入说明，静态卡片不显示重放。
class SetupPage extends StatelessWidget {
  /// 创建接入说明页面。
  const SetupPage({super.key});

  /// 构建当前版本的初始化、存储和释放契约。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Setup', '接入说明'),
    description: tr(
      context,
      'The manager orchestrates; your backend owns rendering and exit animation.',
      'manager 负责编排；展示后端负责绘制和退场动画。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'A small integration', '最小接入'),
        code: '''final manager = Layerman(
  gap: const Duration(milliseconds: 300),
  pauseOnRoutes: const [RouteMatcher.exact('/checkout')],
);
final lifecycle = LayermanLifecycle(manager)..attach();
// In MaterialApp.navigatorObservers:
// LayermanNavigatorObserver(manager)
final dialogs = DialogManager(navigatorKey);
manager.open<bool>(present: dialogs<bool>((ctx, close) => AlertDialog(
  title: const Text('Confirm'),
  actions: [TextButton(onPressed: () => close(true), child: const Text('OK'))],
)));
// At the end of the owner's lifetime:
lifecycle.detach();
manager.dispose();''',
        child: DemoGrid(
          children: [
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Headless orchestration', '无渲染编排'),
                description: tr(
                  context,
                  'No manager widget to mount.',
                  '无需挂载 manager 组件。',
                ),
                child: Text(
                  tr(
                    context,
                    'Create Layerman, pass present:, then dispose when its owner ends.',
                    '创建 Layerman，通过 present: 接入后端，持有者结束时 dispose。',
                  ),
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Route & lifecycle', '路由与生命周期'),
                description: tr(
                  context,
                  'Independent pause sources compose with OR.',
                  '多个暂停来源按 OR 组合。',
                ),
                child: Text(
                  tr(
                    context,
                    'Attach LayermanNavigatorObserver and LayermanLifecycle. Detach the lifecycle binding before replacing its manager.',
                    '接入 LayermanNavigatorObserver 与 LayermanLifecycle；替换 manager 前解除生命周期绑定。',
                  ),
                ),
              ),
            ),
            DemoGridItem(
              child: DemoCard(
                replayable: false,
                title: tr(context, 'Cooldown storage', '冷却存储'),
                description: tr(
                  context,
                  'MemoryCooldownStorage is the default.',
                  '默认使用 MemoryCooldownStorage。',
                ),
                child: Text(
                  tr(
                    context,
                    'Implement OverlayCooldownStorage.read/write for persistence; storageKey separates namespaces. Any cooldown submission automatically awaits hydration. ready() is available for queries.',
                    '跨会话持久化需实现 OverlayCooldownStorage.read/write，storageKey 隔离命名空间。所有带 cooldown 的提交自动等待读取；查询前可 await ready()。',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'visible confirms the first painted frame. duration starts at activation and may expire earlier. dismissed must complete only after the backend has actually exited. Dismiss only the route or handle owned by this submission.',
          'visible 确认真实首帧；duration 从激活开始，可能更早到期。dismissed 必须等后端实际退场后完成；dismiss 只关闭本次提交持有的路由或句柄。',
        ),
      ),
    ],
  );
}
