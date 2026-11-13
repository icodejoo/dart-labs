# cacheman example / 交互示例

Since 0.8.0, `Cacheman()` defaults to memory. This demo explicitly uses the app-owned
[`GetStorageCache`](lib/get_storage_cache.dart) adapter through `demoCache` for persistence.
Copy that adapter into your app and add get_storage there if you need the same backend.
`box` exposes the raw GetStorage handle; `Cacheman.container` now refers to default memory.

0.8.0 起，`Cacheman()` 默认只用内存。本示例通过 `demoCache` 显式使用应用自有的
[`GetStorageCache`](lib/get_storage_cache.dart) 持久化；需要相同后端时，把适配器复制到应用里，
并在应用添加 get_storage。原始句柄是 `box`，`Cacheman.container` 已改为默认内存。


Current package: **0.7.1** (from `../pubspec.yaml`). This app uses `path: ..`,
Flutter 3.47.0, and a complete, local copy of the [shared demo kit](lib/demo_kit/README.md).
No third-party dependencies were added.

当前包版本 **0.7.1**，通过 `path: ..` 引用本包。完整复制 countman 试点的 demo_kit，
不依赖其他项目；未增加第三方依赖。

```sh
# Run in cacheman/example / 在本目录执行
flutter pub get
flutter run -d chrome
flutter build web --release --base-href /dart-labs/cacheman/
```

Published demo / 线上地址：[cacheman demo](https://icodejoo.github.io/dart-labs/cacheman/)

- `?lang=zh` / `?lang=en` overrides browser language; Chinese browser locales select Chinese,
  other languages select English. The header switch stores the selection in memory.
- URL 参数优先，其次跟随浏览器语言，其他语言回退英语。页头可切换语言，选择保存在内存中。
- The URL hash `#/pages/<id>` restores the page on reload and supports Back/Forward.
  Desktop uses a sidebar; narrow layouts use a drawer. Theme initially follows the system.
- hash 记录当前页面，刷新可恢复，支持浏览器前进/后退；宽屏侧栏、窄屏抽屉，明暗默认跟随系统。
- Cards use a responsive grid; section code starts collapsed and can be copied.
- 卡片使用响应式网格，代码默认折叠，展开后跨分区显示并可复制。

## Pages / 页面审计

All eight existing feature pages were retained and rewritten against the current public API.
No duplicate feature pages or development benchmark pages existed. The old bespoke shell was
removed; no library API or workflow was changed.

保留并重写原有 8 个入口，没有重复页或开发期基准页；删除旧专用骨架，不修改 lib 或 workflow。

| Hash ID | Page / 页面 | Current behavior / 当前演示 |
| --- | --- | --- |
| `basic` | Basic operations / 基础读写 | CRUD, scoped erase, keys snapshot, length / 读写删、作用域清空、快照枚举 |
| `ttl` | TTL & expiry / 过期与续期 | Four-second TTL, absolute expiry, sliding renewal, lazy deletion and purge / 4 秒 TTL、绝对过期、滑动续期、懒删除与清理 |
| `batch` | Batch & accessors / 批量与快捷访问 | writeAll/readAll/removeAll, fast/lazy/batchFast with default TTL / 批量与三种快捷访问器 |
| `namespace` | Namespaces / 命名空间 | Shared-container account isolation, escaped prefixes, setNamespace / 同容器账户隔离、前缀转义、切域 |
| `advanced` | Jsonx & debug / 扩展类型与快照 | Explicit Jsonx hooks; DateTime/Duration/Set/BigInt/Uri round trips; decoded debug values / 显式 Jsonx 钩子、类型往返、解码快照 |
| `async` | Layered storage / 分层存储 | Default persistent cache, awaited AsyncCacheman, Cacheman.custom / 默认持久化、异步、自定义同步后端 |
| `hub` | Shared Hub / 共享监听 | includeOwnWrites false/true, peer erase, flushDelay, flush, purgeOnInit / 自身写入过滤对照、清空通知、延迟落盘 |
| `types` | Types & errors / 类型与错误 | ValueAdapter, default values, TypeMismatchError, CorruptEntryError, SerializeError / 适配器、默认值、分类错误 |

Corrections / 纠正的旧内容：

- The old TTL page claimed a live countdown but displayed only read results. The new clocks inspect
  expiry metadata without calling read, so observing a sliding entry never renews it.
- 原 TTL 页只有读取结果，没有真实剩余时间；新时钟观察底层过期元数据，不会因渲染触发续期。
- debug() returns decoded values, not expiry metadata; it can delete expired entries and renew sliding TTL.
- debug() 不含过期元数据，正常读取本身可能清理过期或续期，页面已明确说明。
- Jsonx requires explicit serialize/deserialize hooks when storing extended types directly.
  The demo now exercises the actual cache round trip instead of storing an already encoded string.
- 直接缓存扩展类型时须显式配置 Jsonx 钩子；演示验证实际读写往返，替代“编码字符串再存一次”。
- Namespaces no longer mutate one global cache during rendering. Each card owns its instances.
- 不再通过 getter 或构建过程反复切换全局命名空间，避免页面间串数据。
- The old README said 0.7.0. The chip is 0.7.1; a widget test reads the package pubspec to catch drift.
- README 的旧版本号已更新，widget 测试从包 pubspec 读取版本并校验 chip。

## Replay & storage / 重放与存储

All **18 interactive cards** provide Replay / 重放. Replay remounts only that card's body:
CRUD/enumeration (2), expiry clocks (3), batch/accessors (2), namespace scenarios (2),
Jsonx/snapshot (2), layered storage (3), Hub subscriptions (2), and adapters/errors (2).
Static notes and code samples do not add replay controls.

18 张交互卡片均可独立重放；计时器、输入值、结果、异步会话与 Hub 监听都在卡片主体内管理。
重放不影响其他卡片；静态提示和代码不加重放。

Persistent examples use a dedicated get_storage container, `cacheman_demo_kit`, with per-card
namespaces. Web uses localStorage. **Entering a page or replaying a card clears that scenario's
scope** so the demonstration starts predictably; it never clears the app's default container.
The custom synchronous and asynchronous Map backends are example-only, not disk benchmarks.

持久化演示使用独占容器与逐卡片命名空间；进入页面或重放会复位该场景的数据，
不清理默认容器。两个 Map 后端只说明存储边界，不代表磁盘性能。

flush() returns void and requests persistence; it does not await a disk acknowledgement.
A crash can lose writes within flushDelay. A peer's immediate mutations still queue a whole-container save.

flush() 仅请求保存，不等待磁盘确认；延迟窗口内崩溃可能丢数据，其他实例即时变更仍会排整库保存。

The local demo_kit copy fixes one pilot inconsistency: Replay measured 40px with compact density,
while DemoTokens promises a 44px control target. Standard density and a regression test preserve 44px.
Its Chinese tooltip is normalized to 重放. Other worktrees were not modified.

通用组件副本仅修正重放点击区域 40px 与约定 44px 不一致的问题，并统一中文为“重放”；
附回归测试，未修改试点或其他 worktree。

## Verification / 验证

Run package checks in `cacheman/`, then example checks here:

```sh
# cacheman/
flutter analyze --no-fatal-infos
flutter test
# cacheman/example/
flutter analyze --no-fatal-infos
flutter test
flutter build web --release --base-href /dart-labs/cacheman/
```

Widget tests cover all pages in English/Chinese and light/dark at 375×667 and 1440×900,
real storage actions, replay, countdown observation versus explicit renewal, subscription cleanup,
async disposal, navigation/history, clipboard, collapsed code, and grid widths from 360 to 1600.

widget 测试覆盖全部页面的双语与明暗、两种视口、实际存储交互、重放、过期续期、订阅清理、
异步销毁、导航历史、剪贴板、折叠代码及 360–1600 网格宽度。

The workflow is absent from this sparse worktree; its tracked `origin/main` copy was inspected
read-only. `deploy-cacheman.yml` uses the exact build command above; no workflow change is needed.
The demo's Wasm dry-run warning comes from its chosen get_storage adapter's dart:html backend.
The release JavaScript build succeeds. The main cacheman package no longer depends on get_storage;
choose a Wasm-compatible adapter when targeting Wasm.

工作树未检出 workflow，已只读核对 origin/main 中的部署文件；命令和子路径一致，无需修改。
示例自选 get_storage 的 dart:html 会触发 Wasm 探测告警，不影响 JavaScript release 构建；
主包已移除该依赖，目标为 Wasm 的应用应选择兼容后端。

Chrome DevTools MCP is unavailable in this session. Real-browser smoke tests and viewport screenshots
were not performed; no existing user tab was touched and no preview server was started.

本会话无 chrome-devtools MCP，未进行真实浏览器冒烟或截图；未碰用户标签页，未启动预览服务。

### Recorded run / 本轮实测（2026-11-12）

| Check / 检查 | Result / 结果 |
| --- | --- |
| Package analyze / 包分析 | No issues found, 0 issues |
| Example analyze / 示例分析 | No issues found, 0 issues |
| Package tests / 包测试 | 147 passed |
| Example tests / 示例测试 | 56 passed |
| Release web | Built build/web, base href `/dart-labs/cacheman/` |
| Browser smoke / 浏览器冒烟 | Not run: Chrome DevTools MCP unavailable / 工具不可用，未运行 |

Both size measurements used Flutter 3.47.0 and the exact same release command.
Gzip was measured with Python `gzip.compress(bytes, mtime=0)`, default compression level 9.

前后使用相同 Flutter 与构建命令；gzip 为 Python 默认 level 9，固定 mtime=0。

| main.dart.js | Before / 迁移前 | After / 迁移后 | Change / 增量 |
| --- | ---: | ---: | ---: |
| Raw bytes / 原始字节 | 2,656,408 | 2,700,229 | +43,821 (+1.65%) |
| Gzip bytes / 压缩字节 | 776,227 | 791,255 | +15,028 (+1.94%) |
