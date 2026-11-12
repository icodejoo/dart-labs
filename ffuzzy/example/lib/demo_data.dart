/// 搜索方法与变体共用的纯字符串语料。
const List<String> demoItems = [
  'lib/src/widgets/scaffold.dart',
  'lib/src/material/app_bar.dart',
  'packages/ffuzzy/lib/ffuzzy.dart',
  readmeItem,
  'CHANGELOG.md',
  '中文搜索引擎',
  'café_menu.json',
  'src/main.rs',
];

/// byKey 与 byKeys 工厂共用的联系人。
const List<Map<String, dynamic>> demoContacts = [
  {
    nameField: 'Alice Chen',
    emailField: 'alice@example.com',
    companyField: sampleCompany
  },
  {
    nameField: 'Bob Zhang',
    emailField: 'bob@example.com',
    companyField: 'Globex'
  },
  {
    nameField: 'Carol Wu',
    emailField: 'carol@acme.com',
    companyField: sampleCompany
  },
];

/// 卡片最多展示的命中条数。
const resultLimit = 3;

/// 联系人主字段。
const nameField = 'name';

/// 联系人多字段索引。
const contactFields = [nameField, emailField, companyField];

/// 开发期异步构建基准保留的条目数。
const benchmarkSize = 3000;

/// 联系人邮箱字段。
const emailField = 'email';

/// 联系人公司字段。
const companyField = 'company';

/// 查询标签英文。
const queryEn = 'Query';

/// 查询标签中文。
const queryZh = '查询';

/// 空结果英文。
const emptyEn = 'No matches';

/// 空结果中文。
const emptyZh = '无匹配结果';

/// 完整匹配示例的文档路径。
const readmeItem = 'README.md';

/// 多字段搜索用的共享公司名。
const sampleCompany = 'Acme';
