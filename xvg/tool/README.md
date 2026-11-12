# xvg 构建工具

## native/web 桥接生成

`flutter_rust_bridge.yaml` 输出到 `lib/src/rust`。不要直接运行一次 codegen 就提交：
它会用完整 native 代码覆盖三行条件导出文件 `frb_generated.dart`，却不会更新
`frb_generated.native.dart` 和同步初始化的 web 变体。

未改 API、只需重出 web 桥接时：

```powershell
dart run tool/generate_web_bridge.dart
dart run tool/generate_web_bridge.dart --check
```

API 有变动时，在 `xvg/` 下按顺序运行（PowerShell）：

```powershell
$forwarder = [IO.File]::ReadAllBytes("$PWD/lib/src/rust/frb_generated.dart")
flutter_rust_bridge_codegen generate
if ($LASTEXITCODE -ne 0) { throw 'Native codegen failed; restore the saved forwarder before retrying.' }
Move-Item -LiteralPath lib/src/rust/frb_generated.dart -Destination lib/src/rust/frb_generated.native.dart -Force
[IO.File]::WriteAllBytes("$PWD/lib/src/rust/frb_generated.dart", $forwarder)
dart run tool/generate_web_bridge.dart
if ($LASTEXITCODE -ne 0) { throw 'Web codegen failed' }
dart run tool/generate_web_bridge.dart --check
```

web 生成器临时把 `frb(init)` 改成 `frb(init, sync)`；标记缺失或重复会立即报错。
无论 codegen 成败都会按字节恢复 native Rust、Dart API、平台 wire 和条件入口。
一致性检查比较完整 native/web 文件，仅允许初始化方法从异步变同步；
转发入口被覆盖、普通 API/内容哈希脱节都会失败。CI 的 `dart-analyze` job 执行该检查。
FRB 升级若改变生成模板，需同步更新检查器的初始化模板和测试。

## wasm demo 构建

`dart run tool/build_web.dart` 使用 nightly-2026-06-24。构建前校验
`Cargo.lock` 与本机 wasm-bindgen CLI 版本一致；不一致时输出对应安装命令。
可选 wasm-opt 使用 `--all-features`，因为 release strip 会删除 target_features 段。
随后在 `example/` 下用 PowerShell 执行：

```powershell
flutter build web --release --base-href /dart-labs/xvg/demo/
```
