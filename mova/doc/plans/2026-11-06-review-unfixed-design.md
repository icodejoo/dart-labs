# 2026-11-06 全量评审未修项设计

全量评审 41 条里，39 条已修；剩 2 条核实成立但未改，本文给处置方案。

## 1. mpv 旧文件 `END_FILE(error)` 误归新尝试（mpv_kernel.dart）

**结论：建议关闭，不再开发（won't fix），只补一条已知限制说明。**

- 现象：`open()` 在 `_pump.discardPending()` 之后、`Player.open` 的 `stop` 生效之前，旧文件若恰好报错，会被记到新尝试（`_eventAttempt` 已更新）。
- 为什么不修：[2026-11-05 全量评审交接](2026-11-05-full-review-handoff.md) 已试过两种方案，真机都被证伪并撤销：
  1. START_FILE 起始闸门：HE V9 仅 1/5 通过；
  2. 按 `playlist_entry_id` 过滤：cp1-recovery 夹具超时，根因是 open 后额外 `getProperty` 读取扰动停滞恢复时序。
- 真机日志：被替换旧文件的 END_FILE 24 次全部是 `STOP`（引擎不判失败），0 次 error。误归属只剩「旧文件恰在窗口内真报错」这一极罕见情形，后果仅是新尝试多一次误判重试。
- 处置：
  - 在 `doc/SPEC.md` 已知限制补一句；`mpv_kernel.dart` 该处注释写明"已评估，不修"及原因，避免下次评审重复报；
  - 若将来要重开：必须先在真机对照 `playlist/0/id` 与 END_FILE id 在换档/恢复重载时的关系，且不得新增 open 后的原生读取。

## 2. 缩略图随机目录越积越多（thumb_dir_impl.dart）

**结论：建议做，方案 B（租约 + 复用/清扫）。约 1 个 Task。**

- 现状：`MovaTempThumbDirProvider` 每实例 `createTemp('engine_')`。`clearOnDispose: false` 或进程被杀时，旧目录残留；新实例不复用，旧目录也不进 `diskMaxBytes` 淘汰，磁盘无上限增长。同时 `clearOnDispose:false` 想要的「跨次启动保留缓存」因随机目录名根本做不到。
- 目标：只回收**确认无人使用**的目录；不误删其他引擎或进程正在用的目录。
- 设计：
  1. 每个 `engine_*` 目录里放 `.lease` 文件；provider 持有其 `RandomAccessFile.lock(FileLock.exclusive)` 直到 `dispose`，进程退出/被杀时由 OS 自动释放，无需心跳。
  2. `resolve()` 先扫根目录：对每个 `engine_*` 非阻塞尝试加锁——成功 = 无主；失败 = 在用，跳过。
  3. 无主目录处理：按 mtime 取最新一个**收养**（实现跨次启动复用缓存）；其余无主目录删除；另设保险：mtime 超过 7 天的无主目录一律删。
  4. 没有 `.lease` 的旧版遗留目录视为无主，按 mtime 规则处理。
- 坑：POSIX 的 `fcntl` 锁按**进程**计，同进程内第二个 provider 对同一文件再加锁会「成功」。必须再加一个进程内静态集合记录已被本进程占用的目录，扫描时先排除。
- 不动：`MovaThumbDirProvider` 端口与 `MovaPreviewConfig` 公开面不变；其他自定义 provider 不受影响。
- 测试：纯 Dart 用临时目录——(a) 无主目录被收养；(b) 在用目录（同进程注册表）不被删；(c) 超期无主目录被清；(d) 无 `.lease` 的遗留目录被处理；(e) 两个 provider 并发 `resolve` 不拿到同一目录。跨进程互斥需在 Windows + Android 各手测一次（起两个进程互相不删对方目录）。
- 风险：Windows 上目录被删时句柄必须已关闭，删除前先 close 自己的 lease；锁在网络盘/某些 Android 存储上可能不可靠，临时目录一般是本地盘，可接受；加锁失败一律按"在用"处理（失败开放，宁可留垃圾不误删）。
