import 'package:flutter/material.dart';

import 'snippets/readme_compat.dart';
import 'snippets/readme_grid.dart';
import 'snippets/readme_slot.dart';
import 'snippets/readme_wheel.dart';

export 'snippets/readme_compat.dart' show migratedWheel;
export 'snippets/readme_grid.dart' show GridDemo;
export 'snippets/readme_slot.dart' show SlotDemo;
export 'snippets/readme_wheel.dart' show WheelDemo;

/// README 的可运行代码片段页；例如 `const ReadmeSnippetsPage()`。
class ReadmeSnippetsPage extends StatelessWidget {
  /// 创建片段页，原始示例各自独立持有控制器。
  const ReadmeSnippetsPage({super.key});

  /// 按原 README 配置展示三玩法与迁移代码。
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('README 代码片段')),
        body: ListView(children: [
          const Center(child: WheelDemo()),
          const Center(child: GridDemo()),
          const Center(child: SlotDemo()),
          Center(
              child: SizedBox(
                  width: 300,
                  height: 300,
                  child: migratedWheel(<String, dynamic>{
                    'prizes': [<String, dynamic>{}]
                  }))),
        ]),
      );
}
