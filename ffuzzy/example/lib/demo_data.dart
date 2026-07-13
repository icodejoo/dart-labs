// Shared sample data used across the demo tabs.
//
// 各 demo Tab 共用的示例数据。
library;

/// Plain-string corpus used by the search-mode / raws / async tabs.
///
/// 搜索模式/Raws变体/Async镜像 三个 Tab 共用的纯字符串语料。
const List<String> demoItems = [
  'lib/src/widgets/scaffold.dart',
  'lib/src/material/app_bar.dart',
  'packages/ffz/lib/ffz.dart',
  'README.md',
  'CHANGELOG.md',
  '中文搜索引擎',
  'café_menu.json',
  'src/main.rs',
];

/// Map records for the byKey / byKeys static-constructor demos.
///
/// 静态构造 Tab 里 byKey / byKeys 演示用的 Map 记录。
const List<Map<String, dynamic>> demoContacts = [
  {'name': 'Alice Chen', 'email': 'alice@example.com', 'company': 'Acme'},
  {'name': 'Bob Zhang', 'email': 'bob@example.com', 'company': 'Globex'},
  {'name': 'Carol Wu', 'email': 'carol@acme.com', 'company': 'Acme'},
];
