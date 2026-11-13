[English](README.md) | **简体中文**

# xvg

在 Flutter 里渲染静态和动画 SVG。

## 目录

* [在线展示](#在线展示)
* [安装](#安装)
* [快速上手](#快速上手)
* [`Xvg.string` 详解](#xvgstring-详解)
* [重新着色](#重新着色)
* [动画播放](#动画播放)
* [动画画质](#动画画质)
* [仅静态 / 仅动画组件](#仅静态--仅动画组件)
* [混合格式图片迁移（ImageProvider）](#混合格式图片迁移)
* [API 参考](#api-参考)
* [注意事项与限制](#注意事项与限制)

## 在线展示

[icodejoo.github.io/dart-labs/xvg](https://icodejoo.github.io/dart-labs/xvg/)：
静态展示页（功能导览、SVG 预览与实测性能数据）。另有
[实验性 Flutter Web demo](https://icodejoo.github.io/dart-labs/xvg/demo/)，
使用 Rust 编译的 wasm 运行真实 xvg 渲染，并播放 Dart SMIL 动画。
pub 包仍仅支持 native 平台；未附带 web 预编译产物或自动加载配置。

本地构建：在 `xvg/` 执行 `dart run tool/build_web.dart`，再在 `example/` 执行
`flutter build web --release --base-href /dart-labs/xvg/demo/`，按此子路径托管产物。
需要 nightly-2026-06-24、wasm32-unknown-unknown target，以及与 Cargo.lock
一致的 wasm-bindgen-cli（0.2.130）；wasm-opt 可选。不需要 COOP/COEP。
重新生成 web 桥接用 `dart run tool/generate_web_bridge.dart`（FRB 2.13.0），
脚本会恢复 native 桥接文件，仅产出 web 同步变体。
网络受浏览器 CORS 限制，不支持本地 file 路径；大型动画文档在主线程解析。

* **静态 SVG** 经 Rust（`usvg`）解析为缓存的 `ui.Picture`，再交给 Flutter
  自带的 GPU 管线绘制，不走 CPU 光栅化。
* **动画 SVG**（SMIL：`<animate>`、`<animateTransform>`、`<animateMotion>`、
  `<set>`，以及 CSS `@keyframes`）由 xvg 自己的 Dart 侧引擎驱动：解析一次，之后每帧
  在纯 Dart 里采样并绘制，所以每帧都没有数据穿过 Rust FFI 边界。
* 只需要一个组件 `Xvg`，它会自己判断每个源走哪条路径。

## 安装

```yaml
dependencies:
  xvg: ^0.1.1
```

在构建第一个 `Xvg` 组件之前，先启动一次原生（Rust）后端：

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Xvg.ensureInitialized(); // 首次成功后再调用是空操作
  runApp(const SizedBox.shrink());
}
```

pub 包未声明 Web 支持；源码中的 wasm demo 为实验性构建。

## 快速上手

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="2"/>
</svg>''';

Widget quickStart() => const Xvg.string(svgSource, width: 48, height: 48);
```

`Xvg` 会检查源中是否含 SMIL 与 CSS `@keyframes` 动画标记，并选择静态或
动画渲染器。大多数情况下不用关心走的是哪条。

五个入口共用同一组渲染参数：

| 入口 | 源 | 加载方式 |
| --- | --- | --- |
| `Xvg.string(String)` | 你手里已有的 SVG 文本 | 同步组件（可 `const` 构造） |
| `Xvg.asset(String)` | asset 名（`bundle`、`package` 规则同 `AssetImage`） | 异步，文本有缓存 |
| `Xvg.network(String)` | HTTP(S) URL（可选 `headers`） | 异步，文本有缓存，连接与响应头各 30 秒超时 |
| `Xvg.file(File)` | 磁盘文件 | 异步，按路径缓存文本 |
| `Xvg.memory(Uint8List)` | UTF-8 编码的 SVG 字节 | 同步，解码后转发给 `Xvg.string` |

## `Xvg.string` 详解

`Xvg.string` 是最基础的入口：其余入口都是先加载或解码出文本，再交给它渲染。
它也是唯一一个可 `const` 构造的组件类（其余是返回 `Widget` 的静态工厂方法）。

```dart
const Xvg.string(
  String source, {
  Key? key,
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  XvgPixelSnap pixelSnap = XvgPixelSnap.auto,
  Alignment alignment = Alignment.center,
  ColorFilter? colorFilter,
  XvgTheme? theme,
  XvgAnimationQuality? quality,
  XvgAnimationController? controller,
  Animation<double>? animation,
  Duration? animationSpan,
  bool autoplay = true,
  double playbackRate = 1.0,
  double? fps,
  ValueChanged<XvgAnimationInfo>? onLoaded,
  void Function(Object error, StackTrace stackTrace)? onError,
  ImageErrorWidgetBuilder? errorBuilder,
  ValueChanged<XvgAnimationEvent>? onEvent,
  VoidCallback? onAnimationStart,
  VoidCallback? onAnimationComplete,
  ValueChanged<int>? onAnimationLoop,
})
```

### 源字符串从哪来

任何包含 SVG 标记的 `String` 都可以。常见来源：

**1. 字面量或常量。** 最理想：字符串只创建一次，组件还能 `const`。

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const _checkIcon = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <path d="M5 13l4 4L19 7" fill="none" stroke="currentColor" stroke-width="2"/>
</svg>''';

Widget checkIcon() => const Xvg.string(_checkIcon, width: 24, height: 24);
```

**2. 变量或运行时生成的字符串。** 适合标记里有一部分由数据决定的情形。每个不同
的字符串都是一条独立缓存，所以要控制不同字符串的数量，并且每个只构造一次
（见[缓存与性能](#缓存与性能)）。

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

String _dotSvg(Color color) {
  final rgb = (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<circle cx="12" cy="12" r="10" fill="#$rgb"/></svg>';
}

// 每种颜色只构造一次，不要放进 build()。
final _redDot = _dotSvg(const Color(0xFFE53935));

Widget redDot() => Xvg.string(_redDot, width: 16, height: 16);
```

**3. 从 assets 读取后传入。** 普通场景请直接用 `Xvg.asset`。需要预处理文本
（替换占位符、去掉根节点 `width`/`height`、选变体）或想把字符串放进自己的状态
时，再自己读取。

```dart
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

class AssetStringIcon extends StatefulWidget {
  const AssetStringIcon({super.key});

  @override
  State<AssetStringIcon> createState() => _AssetStringIconState();
}

class _AssetStringIconState extends State<AssetStringIcon> {
  // 只创建一次；每次 build 新建 Future 会让每次重建都重新加载。
  late final Future<String> _svg = rootBundle.loadString('assets/logo.svg');

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _svg,
      builder: (context, snapshot) {
        final svg = snapshot.data;
        if (svg == null) return const SizedBox(width: 48, height: 48);
        return Xvg.string(svg, width: 48, height: 48);
      },
    );
  }
}
```

**4. 网络下载后传入。** 普通 GET 请直接用 `Xvg.network`。需要自定义重试、鉴权
流程、清洗内容，或把字节共享给其它代码时，再自己下载。

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xvg/xvg.dart';

Future<String> fetchSvg(Uri uri) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: uri);
    }
    return await response.transform(utf8.decoder).join();
  } finally {
    client.close();
  }
}

class RemoteStringIcon extends StatefulWidget {
  const RemoteStringIcon(this.uri, {super.key});

  final Uri uri;

  @override
  State<RemoteStringIcon> createState() => _RemoteStringIconState();
}

class _RemoteStringIconState extends State<RemoteStringIcon> {
  late Future<String> _svg = fetchSvg(widget.uri);

  @override
  void didUpdateWidget(RemoteStringIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _svg = fetchSvg(widget.uri);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _svg,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Icon(Icons.error_outline);
        final svg = snapshot.data;
        if (svg == null) return const SizedBox(width: 64, height: 64);
        return Xvg.string(svg, width: 64, height: 64);
      },
    );
  }
}
```

**5. 已经在手里的字节。** `Xvg.memory(bytes)` 按 UTF-8 解码后调用
`Xvg.string`；适用于来自数据库或压缩包的 `Uint8List`。

### 参数参考

| 参数 | 默认值 | 作用 |
| --- | --- | --- |
| `source` | 必填 | SVG 文本。源变化时由动画标记决定走哪个渲染器。 |
| `width`、`height` | `null` | 目标盒子。`null` 时回退到 SVG 自身的宽高（或 `viewBox`）。内容加载或变化时盒子不能抖动的话，两个都给上。 |
| `fit` | `BoxFit.contain` | picture 如何适配到盒子（含义同 `Image.fit`）。 |
| `alignment` | `Alignment.center` | `fit` 留出空白时 picture 在盒子里的位置。类型是 `Alignment`，不是 `AlignmentGeometry`。 |
| `colorFilter` | `null` | Flutter `ColorFilter`，两条路径都生效。动画源仅在传入滤镜时才多加一层 `ColorFiltered`。 |
| `theme` | `null` | `XvgTheme(currentColor: …)`，解析 SVG 里的 `currentColor` 关键字（默认不透明黑色）。 |
| `pixelSnap` | `XvgPixelSnap.auto` | 合成阶段把视口对齐到物理像素。`auto` 仅对遮罩/裁剪文档启用，`always` / `never` 强制覆盖。 |
| `quality` | `null`（使用 `XvgAnimationQuality.defaultQuality`） | 动画吞吐与保真的取舍。静态源忽略。 |
| `controller` | `null` | 共享的 `XvgAnimationController`。与 `animation` 互斥；`playbackRate` 保持 1.0，改用控制器自己的速率。 |
| `animation` | `null` | 由 Flutter `Animation<double>` 驱动文档时间（`value × animationSpan`）。 |
| `animationSpan` | `null` | 对应 `animation` 的 0..1 的时长；`null` 使用文档自然时长。 |
| `autoplay` | `true` | 是否启动隐式播放（未传 `controller`/`animation` 时）。传 `animation` 时必须保持 `true`。 |
| `playbackRate` | `1.0` | 隐式播放的有限有符号速率；负值倒放，`0` 暂停。传 `controller` 或 `animation` 时必须保持 `1.0`。 |
| `fps` | `null` | null 跟随 `Xvg.fps`；正数限制采样/重绘帧率；0 冻结首帧；`double.infinity` 不限速且无视全局。外部 `animation` 与静态源忽略。 |
| `onLoaded` | `null` | 动画源（及其内嵌图片）就绪时回调，携带 `XvgAnimationInfo`。静态源永不调用。 |
| `onError` | `null` | 接收加载、解析、时长映射错误。静态源的失败在帧结束后通知，每次源/主题变更一次。 |
| `errorBuilder` | `null` | 失败时的替代内容（`ImageErrorWidgetBuilder`，与 `Image.errorBuilder` 相同）。 |
| `onEvent` | `null` | 播放及元素 begin/end/repeat 事件（`XvgAnimationEvent`）。 |
| `onAnimationStart` / `onAnimationComplete` / `onAnimationLoop` | `null` | 首次 tick / 有限文档自然完成 / 已知周期穿越（轮次从一开始）。传 `animation` 时不调用。 |

非法组合在调试构建中会触发 `assert`：负数或 NaN 的 `fps`、非有限的 `playbackRate`、
`controller` 与 `animation` 同时给出、给 `controller` 配了非默认 `playbackRate`、
给 `animation` 配了非默认 `autoplay` 或 `playbackRate`。

组件有意不提供 `semanticsLabel`、`placeholder`、`currentColor` 参数：见下文的
[无障碍](#无障碍)、[错误与占位](#错误与占位)和[重新着色](#重新着色)。

### 尺寸

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<circle cx="12" cy="12" r="10"/></svg>';

List<Widget> sizingExamples() => const [
  // 使用 SVG 的固有尺寸（width/height 属性，否则取 viewBox）。
  Xvg.string(svgSource),
  // 固定盒子；picture 以 BoxFit.contain 居中适配。
  Xvg.string(svgSource, width: 120, height: 60),
  // 铺满盒子并裁掉溢出部分，锚定在左上角。
  Xvg.string(
    svgSource,
    width: 120,
    height: 60,
    fit: BoxFit.cover,
    alignment: Alignment.topLeft,
  ),
];
```

父级约束依然生效：超过传入最大值的尺寸会被钳制，行为与 `CustomPaint` 相同。

### `Xvg.string` 与其它入口对照

| | `Xvg.string` | `Xvg.asset` / `.network` / `.file` | `Xvg.memory` |
| --- | --- | --- | --- |
| 返回类型 | `Xvg` 组件（可 `const`） | `Widget`（内部异步包装） | `Xvg` 组件 |
| 文本何时可用 | 立即 | 异步加载之后 | 立即 |
| 首帧 | 有内容（静态源冷解析按帧限额） | 加载完成前是空的 `SizedBox(width, height)` | 有内容 |
| 源变化 | 重新判断动画并重新渲染 | 新文本加载完成前保留旧图 | 同 `Xvg.string` |
| 加载失败 | 不涉及 | 走 `onError` / `errorBuilder`，都没给则抛给 `ErrorWidget.builder` | UTF-8 解码失败时在 build 中抛出 |
| 文本缓存 | 自身没有，使用下文的 picture/文档缓存 | 额外有源文本 LRU（100 条，内存） | 无 |
| 参数 | 全部 | 全部（同一组） | 全部（同一组） |

五个入口接受完全相同的渲染参数，所以换一种源类型，调用的其余部分不用动。

### 动画源

字符串里只要含 SMIL（`<animate>`、`<animateTransform>`、`<animateMotion>`、
`<set>`）或 CSS `@keyframes`（不区分大小写，含厂商前缀），源就会被路由到 Dart 侧
动画引擎并自动播放：

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const spinnerSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
  <path fill="currentColor"
        d="M12,4a8,8,0,0,1,7.89,6.7A1.5,1.5,0,0,0,21.38,12h0a1.5,1.5,0,0,0,1.48-1.75,11,11,0,0,0-21.72,0A1.5,1.5,0,0,0,2.62,12h0a1.53,1.53,0,0,0,1.49-1.3A8,8,0,0,1,12,4Z">
    <animateTransform attributeName="transform" type="rotate"
        dur="0.75s" repeatCount="indefinite" values="0 12 12;360 12 12"/>
  </path>
</svg>''';

Widget spinner() => const Xvg.string(
  spinnerSvg,
  width: 32,
  height: 32,
  theme: XvgTheme(currentColor: Color(0xFF1E88E5)),
);
```

需要了解的行为：

* 检测只是简单的文本匹配，不做语义判断。一个静态 SVG 只要含有 `<set>` 标签或
  一条没被引用的 `@keyframes` 规则，仍会被路由到动画引擎（能正确渲染，只是不走
  Rust 路径）。想明确指定路径，请用 `XvgStatic` / `XvgAnimated`。
* 动画文档默认隐式播放（`autoplay: true`，速率 `1.0`），遵循 `TickerMode`（使用
  同一时钟的控件全部被禁用时暂停；单独 `Offstage` 不暂停）与 `timeDilation`，
  有限文档停在最后一帧（`fill="freeze"` 会保留结束状态）。
* 要共享、可跳转的控制，用 `controller`；要由自己的 Flutter `AnimationController`
  驱动，用 `animation`。这两种都用来代替隐式播放；见[动画播放](#动画播放)。
* `onLoaded`、`onEvent`、`quality`、`fps`、`autoplay` 以及 controller /
  animation / 各类动画回调只对动画源有意义；静态源会忽略它们，也不挂任何监听器
  或控制器。
* `colorFilter` 与 `theme` 在两条路径上表现一致。

### 错误与占位

```dart
import 'package:flutter/material.dart';
import 'package:xvg/xvg.dart';

Widget safeIcon(String svg) => Xvg.string(
  svg,
  width: 24,
  height: 24,
  onError: (error, stack) => debugPrint('xvg failed: $error'),
  errorBuilder: (context, error, stack) =>
      const Icon(Icons.broken_image_outlined, size: 24),
);
```

* `errorBuilder` 构建替代内容；`onError` 只负责上报。可以只给其一，也可以都给。
* **静态源、未设任何处理器：** 解析失败会静默渲染一个 `width` x `height` 的空盒子。
  请传 `onError`/`errorBuilder`，避免把损坏的资源误当成“看不见的图标”。
* **静态源、只设 `onError`：** 显示空盒子，`onError` 在帧结束后调用，每次失败的
  源/主题变更只调用一次（重建不会重复）。
* **动画源、未设任何处理器：** 失败经 `FlutterError.reportError` 上报，并显示空盒子。
* `Xvg.asset` / `.network` / `.file`：加载失败会调用 `onError` / `errorBuilder`；
  两者都没给时，原始错误会从 `build` 中重新抛出并到达 `ErrorWidget.builder`。
  `errorBuilder` 收到原始错误与堆栈，与 `Image` 一致。
* 超出当前帧时间预算的静态冷渲染（见[缓存](#缓存与性能)）会先显示一两帧空的
  `width` x `height` 盒子，picture 之后再出现。含 `<image>` 标签的源异步解码，
  期间同样显示空盒子。
* 没有 `placeholder` 参数。自己拉取内容时，按上面的示例用 `FutureBuilder` 包住
  `Xvg.string`；`Xvg.asset/.network/.file` 的加载态就是那个空的指定尺寸盒子，
  所以务必传 `width`/`height` 以免布局跳动。

### 无障碍

xvg 只绘制图片，不添加语义节点。请用 Flutter 自己的组件描述它：

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget labelled(String svg) => Semantics(
  label: 'Payment completed',
  image: true,
  child: Xvg.string(svg, width: 48, height: 48),
);

Widget decorative(String svg) =>
    ExcludeSemantics(child: Xvg.string(svg, width: 16, height: 16));
```

### 缓存与性能

| 缓存 | 使用方 | 键 | 策略 | 可调项 |
| --- | --- | --- | --- | --- |
| `RustXvgPictureCache.instance` | 静态路径 | `(source, currentColor ARGB)` | LRU，200 张 picture | `maximumSize`、`clear()`、`length`、`approximateBytesUsed`、`peek`、`getOrRender`、`getOrRenderAsync`、`onParseMiss` |
| `XvgDocumentCache.instance` | 动画路径 | 源字符串 | 随机淘汰，1000 份文档；含 `<image>` 的文档从不入缓存 | `maximumSize`、`clear()`、`length`、`getOrParse`、`getOrParseAsync`、`prewarm` |
| 源文本 LRU | 仅 `Xvg.asset/.network/.file` | key / URL / 路径 | LRU，100 条 | 内部 |

```dart
import 'package:flutter/foundation.dart';
import 'package:xvg/xvg.dart';

Future<void> tuneCaches(List<String> bigIllustrations) async {
  // 按真实图标集标定缓存上限，不要靠猜。
  RustXvgPictureCache.instance.maximumSize = 500;
  XvgDocumentCache.instance.maximumSize = 2000;

  // 用数据说话：条目数说明不了成本。
  debugPrint(
    '${RustXvgPictureCache.instance.length} pictures, '
    '${RustXvgPictureCache.instance.approximateBytesUsed} bytes',
  );
  RustXvgPictureCache.instance.onParseMiss = (elapsed) =>
      debugPrint('static cache miss took $elapsed');

  // 把动画文档缓存预热到首帧路径之外。失败在这里被忽略，组件稍后构建时
  // 仍会正常报告。
  await XvgDocumentCache.instance.prewarm(bigIllustrations);

  // 预热静态缓存（同步调用，会阻塞当前 isolate）。
  RustXvgPictureCache.instance.getOrRender(bigIllustrations.first);

  // 低内存处理。
  RustXvgPictureCache.instance.clear();
  XvgDocumentCache.instance.clear();
}
```

实用规则：

* **字符串只创建一次。** 缓存查找要对整个源做哈希。`const`、`static final` 或
  字段里的字符串只哈希一次；每帧在 `build()` 里新建的 `String` 每次都要重新哈希，
  而每帧都在变的源（例如插值颜色）每个不同取值都会新增一条缓存。
* **用 `theme` / `colorFilter` 换色，不要改字符串。** 每个 `currentColor` 变体
  占一张缓存 picture（主题色是缓存键的一部分）；`colorFilter` 则复用同一张 picture。
* **静态冷解析在 UI isolate 上同步执行**，每帧限额 8 毫秒（`ColdMountFrameBudget`）：
  超出的挂载显示空的 `width` x `height` 盒子，在后续帧渲染。因此一个从未见过的
  巨大图标网格首帧依然顺滑，但请给组件明确的尺寸，空盒子才不会跳动。缓存命中
  完全不受预算影响。
* **不可信或特别大的 SVG 请放到 UI 线程之外解析。** Rust 解析调用是同步的。动画
  文档可用 `XvgDocumentCache.getOrParseAsync` 与 `prewarm`，它们会把无图片的大源
  交给常驻 worker isolate。
* **大量并发动画图标：** 保留默认的 `XvgAnimationQuality`（并发超过 24 个图标后
  自适应跳帧）或限制 `fps`；必须逐帧精确的主图标用 `XvgAnimationQuality.exact`。
* **ImageProvider 的光栅结果**使用 Flutter 的 `ImageCache`，不走上述缓存。

### 常见坑

* 第一个组件构建前忘记 `await Xvg.ensureInitialized()`。
* 期待 Web 构建。pub 包使用原生 FFI；源码 demo 提供实验性 wasm 构建。
* `colorFilter: ColorFilter.mode(color, BlendMode.srcIn)` 会把多色 SVG 压成单色。
  只想改 `currentColor` 时用 `theme`。
* 没有 `theme` 时 `stroke="currentColor"` 是黑色。设 `theme: XvgTheme(currentColor: …)`
  或用滤镜换色。
* 同时传 `controller` 与 `animation`，或给它们配自定义 `playbackRate`，调试下触发
  `assert`，发布版则属于错误用法。
* 静态 `<image href>` 只支持内嵌 `data:` URI；本地路径、`file://` 与
  `data:image/svg+xml` 会被跳过。
* 本该显示图标的地方是空盒子，通常是静态解析错误被吞掉了：加上 `onError`，或对照
  `doc/animation-engine-features.md` 检查 SVG。
* 不要把加载用的 `FutureBuilder` 的 `future:` 表达式直接写在 `build()` 里，
  那样每次重建都会重新开始加载。
* 调用方持有的 `XvgAnimationController` 要随其所有者一起 dispose。xvg 从不会
  dispose 你传入的控制器或 `Animation`。
* 文件本来就是 asset 却用 `rootBundle.loadString` 去读：直接用 `Xvg.asset`，它
  会缓存文本，并在新 asset 加载期间保留旧图。

## 重新着色

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

const svgSource = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path stroke="currentColor" fill="none" d="M4 12h16"/></svg>';

List<Widget> recolor() => const [
  // 整体染成一种颜色。
  Xvg.string(
    svgSource,
    width: 24,
    height: 24,
    colorFilter: ColorFilter.mode(Color(0xFF1E88E5), BlendMode.srcIn),
  ),
  // 只改变 `currentColor` 关键字；其它填充保持原色。
  Xvg.string(
    svgSource,
    width: 24,
    height: 24,
    theme: XvgTheme(currentColor: Color(0xFF1E88E5)),
  ),
];
```

`colorFilter` 对两条渲染路径都生效。动画 SVG 仅在传入滤镜时才多加一层
`ColorFiltered`。取值相同的 `XvgTheme` 实例相等，所以重建它们不会破坏缓存复用。
源里的 `currentColor` 在两条路径上都通过 `XvgTheme` 控制。

`Xvg.network` 按排序后的 header 值比较，`Xvg.file` 按路径比较。换源时，新内容
加载完成前会一直显示旧 SVG。源加载会区分 assets、bundle、文件与 header 变体，
并合并同一 key 的并发请求。HTTP 连接与响应头等待各有 30 秒超时。

`pixelSnap: XvgPixelSnap.auto` 在合成阶段对齐遮罩/裁剪视口；`always`/`never`
在所有 SVG 组件入口上覆盖该行为（仅平移与正缩放，视觉修正小于 1 个物理像素；
布局、点击与语义保留原位置）。

## 动画播放

`Xvg.string/asset/network/file/memory` 五个入口都接受 `controller`、`animation`、
`animationSpan`、`autoplay`、`playbackRate`、`fps`、`onLoaded`、`onError`、
`errorBuilder`、`onEvent`、`onAnimationStart`、`onAnimationComplete` 与
`onAnimationLoop`，以及 `theme`、`quality`、`colorFilter`。

三选一：隐式播放（默认 `autoplay: true`、`playbackRate: 1.0`）、共享的
`XvgAnimationController`，或 Flutter `Animation<double>`：

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

class ControlledIcon extends StatefulWidget {
  const ControlledIcon(this.svgSource, {super.key});

  final String svgSource;

  @override
  State<ControlledIcon> createState() => _ControlledIconState();
}

class _ControlledIconState extends State<ControlledIcon> {
  final controller = XvgAnimationController(autoplay: false);

  @override
  void dispose() {
    controller.dispose(); // 调用方持有的控制器随所有者一起释放。
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Xvg.string(
      widget.svgSource,
      controller: controller,
      onLoaded: (info) {
        controller.play();
        // 另有：pause()、stop()、reverse()、seek(Duration)、有符号
        // playbackRate、fitDuration(target)，
        controller.setRange(
          Duration.zero,
          info.settleTime,
          mode: XvgRangeMode.pingPong,
        );
      },
    );
  }
}
```

静态源会忽略动画专属参数与回调，包括 `onLoaded` 和 `onEvent`；它们不会挂载
控制器或 animation 监听器。`onError` 与 `errorBuilder` 同时处理静态和动画的
解析失败。静态源的 `onError` 在帧结束后调用，每次失败的源/主题变更一次。
asset/network/file 的加载失败使用已提供的任一处理器；只设回调时显示指定尺寸的
空盒子。两个处理器都没设时，加载失败仍会传播到环境的 `ErrorWidget.builder`。
`errorBuilder` 收到原始错误与堆栈，与 Flutter 的图片组件一致。

示例应用的 **动画控制** 按钮会打开原创 SMIL 演示：播放、跳转、速率、
一次/循环/往返片段、时长适配、有上限的事件日志，以及曲线化的 Flutter 动画驱动。
其中不使用任何第三方 SVG 素材。

用 Flutter `Animation<double>`（包括曲线动画）驱动 SVG：

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget driven(String svgSource, AnimationController myAnimationController) {
  return Xvg.string(
    svgSource,
    animation: myAnimationController,
    animationSpan: const Duration(seconds: 2), // 省略则使用 naturalDuration。
    onEvent: (event) => debugPrint('$event'), // 元素 begin/end/repeat 与循环。
  );
}
```

文档时间为 `animation.value × span`：负时间钳到零；正向超调可以超过 span。
如果既没有显式 span 也没有已知的自然时长，会通过 `onError` / `errorBuilder` /
`FlutterError` 报告失败。`animation` 与 `controller` 互斥；使用 `animation` 时让
`autoplay` 和 `playbackRate` 保持默认。请观察驱动方的 `AnimationStatus` 来获知
开始/完成：该模式下 xvg 既不发这两类事件，也不调用 `onAnimationStart` /
`onAnimationComplete`。`onEvent` 在隐式、controller、animation 三种模式下都有效。
驱动方负责 vsync 与 TickerMode；这类实例绕过共享时钟的并发计数与跳帧（实例及全局 `fps`
被忽略）。大量并发 SVG 时优先用 controller/隐式播放。释放传入的 Flutter
AnimationController 后会保留最后一帧；xvg 会在替换或卸载时移除自己的监听器。

`Xvg.playbackRate` 可以在挂载期间修改，时间线不会跳变。

CSS `@keyframes` 同样会发出 begin/end/repeat 事件，`id` 为动画名；每个元素的每个
动画声明（跨所有属性通道）发一次。事件不带目标元素 id，所以多个元素上的同名
动画各自发出 `id` 相同的独立事件。

不借助组件回调，直接监听任意控制器的事件：

```dart
import 'package:flutter/foundation.dart';
import 'package:xvg/xvg.dart';

void observe(XvgAnimationController controller) {
  controller.addEventListener((event) {
    switch (event) {
      case XvgAnimationLoaded(:final info):
        debugPrint('ready, natural duration ${info.naturalDuration}');
      case XvgAnimationStarted():
        debugPrint('started');
      case XvgAnimationCompleted(:final natural):
        debugPrint('completed (natural: $natural)');
      case XvgAnimationLooped(:final iteration):
        debugPrint('document loop $iteration');
      case XvgAnimationRangeLooped(:final iteration):
        debugPrint('range wrap $iteration');
      case XvgAnimationElementBegin(:final id):
        debugPrint('element $id began');
      case XvgAnimationElementEnd(:final id):
        debugPrint('element $id ended');
      case XvgAnimationElementRepeat(:final id, :final iteration):
        debugPrint('element $id repeat $iteration');
      case XvgAnimationError(:final error):
        debugPrint('failed: $error');
    }
  });
  controller.addCue(const Duration(seconds: 1), () => debugPrint('t = 1 s'));
}
```

### 全局帧率 Xvg.fps

`fps` 类型为 `double?`：null 跟随实时全局 `Xvg.fps.value`，正数限制采样/重绘帧率，
0 冻结在首帧，`double.infinity` 不限速且无视全局。负数和 NaN 在 debug 下触发断言。
实例与全局均为 null 时，播放行为与原先一致；全局 null 或 infinity 表示不限速。
实例与全局变化最迟在下一次 pump/帧生效。

```dart
// 启动时设置全局初始值……
await Xvg.ensureInitialized(fps: 60);

// ……运行时随时修改。业务自行监听低端设备、低内存等信号，再设置全局帧率。
Xvg.fps.value = 10;

// 冻结全部跟随全局的动画，再恢复播放。
Xvg.fps.value = 0;
Xvg.fps.value = null;

// 此实例始终不限速，即使全局已冻结或限速。
Xvg.string(svg, fps: double.infinity);
```

`XvgAnimated.string` 使用相同参数和全局设置。解除冻结后保留原播放意图，
`autoplay: false` 不会被误启动。共享 controller 时，只要还有挂载控件具备播放资格，
就继续播放，冻结控件也跟随共享时间；仅在**全部挂载控件有效 fps 都为 0** 时，
控制器才回到首帧并暂停。正数上限取挂载控件中最宽松的值，与 `quality` 取较大除数。
选定片段也会冻结到文档零时刻，解除冻结后先恢复片段边界再播放。
单独关闭 TickerMode 仍停在当前帧。外部 `animation` 驱动忽略实例及全局 fps，
驱动策略由调用方负责；静态源也忽略。库不读取系统减少动画设置。

## 动画画质

在动画路径上，`XvgAnimationQuality` 可以在大量动画同时运行时（例如滚动的动画图标网格）
用保真度换速度。默认开启自适应跳帧；各选项及其代价见类文档。

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget qualityExamples(String svgSource) {
  // 全进程默认值（组件未传 `quality` 时使用）。
  XvgAnimationQuality.defaultQuality = const XvgAnimationQuality(
    frameSkipThreshold: 8,
    maxFrameDivisor: 3,
  );
  return Column(
    children: [
      Xvg.string(svgSource, quality: const XvgAnimationQuality()),
      // 这个永不降级。
      Xvg.string(svgSource, quality: XvgAnimationQuality.exact),
    ],
  );
}
```

## 仅静态 / 仅动画组件

`XvgStatic` 与 `XvgAnimated` 是 `Xvg` 分发到的两个渲染器，导出给已经明确知道
自己需要哪一个的调用方（例如事先已知全是静态的图标集）。

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget staticOnly(String svg) => XvgStatic(
  svg,
  width: 24,
  height: 24,
  theme: const XvgTheme(currentColor: Color(0xFF424242)),
  errorBuilder: (context, error, stack) => const SizedBox(width: 24, height: 24),
);

Widget animatedOnly(String svg) =>
    XvgAnimated.string(svg, width: 24, height: 24, fps: 30);
```

`XvgStatic` 没有动画或控制器相关参数，其 `alignment` 类型是 `AlignmentGeometry`；
`errorBuilder` 的类型是 `Widget Function(BuildContext, Object, StackTrace)`。
`XvgAnimated.string` 接受与 `Xvg.string` 相同的动画、画质与回调参数。

## 混合格式图片迁移

当某个 URL 可能返回 SVG 或位图时，把 `Image.network(url)` 换成
`Image(image: NetworkXvg(url))`。`AssetXvg`、`FileXvg`、`MemoryXvg` 同样会识别 SVG
字节，并对 PNG/JPEG/GIF/WebP/BMP 等引擎支持的格式（含动画 GIF/WebP）回退到
Flutter 原生解码器。`StringXvg` 仍然只接受 SVG 文本。`Xvg.asset/network/file`
组件保持原有的“只读 SVG 文本”行为。

```dart
import 'package:flutter/widgets.dart';
import 'package:xvg/xvg.dart';

Widget providers(String url) => Column(
  children: [
    Image(image: NetworkXvg(url)),
    Image(image: ResizeImage(NetworkXvg(url), width: 128)),
    Image(image: const StringXvg('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"/>')),
    DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetXvg('assets/background.svg', width: 360),
        ),
      ),
      child: const SizedBox(width: 360, height: 200),
    ),
  ],
);
```

位图解码遵循 `ResizeImage`；`Image.network` 的 `cacheWidth` 和 `cacheHeight`
请用 `ResizeImage.resizeIfNeeded(cacheWidth, cacheHeight, NetworkXvg(url))`
迁移。provider 的 `width`/`height` 只决定 SVG 的光栅分辨率；provider 的
`colorFilter`、`theme` 与 `animationFrameRate` 不影响位图。想给两种格式统一着色，
用 `Image.color` 与 `Image.colorBlendMode`。Flutter 的 `ImageCache` 缓存 provider
的结果；provider 的原始字节不使用组件的文本 LRU。ImageProvider 的光栅图会统一
缩小到每边至多 4096 像素，并调整缩放比例以保持逻辑尺寸。

SVG 动画在没有监听者时暂停，遵循 `timeDilation`，有限文档停在最后一帧。
帧间隔超过四个动画间隔视为暂停，恢复时只推进一个间隔。`XvgAnimationController`
不控制 ImageProvider。不支持 gzip SVG（`svgz`）：gzip 载荷会交给原生解码器，
并保留其错误。

## API 参考

`package:xvg/xvg.dart` 导出的全部符号：

| 符号 | 类别 | 用途 |
| --- | --- | --- |
| `Xvg` | 组件 | 入口组件，负责选渲染器。`Xvg.string` 构造函数；`Xvg.asset`、`Xvg.network`、`Xvg.file`、`Xvg.memory` 静态工厂；`Xvg.ensureInitialized()`。 |
| `XvgStatic` | 组件 | Rust（`usvg`）静态渲染器。参数：`source`、`pixelSnap`、`width`、`height`、`fit`、`alignment`、`colorFilter`、`theme`、`errorBuilder`。 |
| `RustXvgPictureCache` | 类 | 进程级 LRU，缓存录制好的静态 picture。`instance`、`maximumSize`（200）、`onParseMiss`、`getOrRender`、`getOrRenderAsync`、`peek`、`clear`、`length`、`approximateBytesUsed`。 |
| `XvgAnimated` | 组件 | Dart 侧 SMIL / CSS `@keyframes` 渲染器。`XvgAnimated.string`，动画、画质与回调参数同 `Xvg.string`。 |
| `XvgDocumentCache` | 类 | 进程级缓存，缓存已解析的动画文档。`instance`、`maximumSize`（1000）、`getOrParse`、`getOrParseAsync`、`prewarm`、`clear`、`length`。 |
| `XvgTheme` | 类 | `currentColor` 解析（`const XvgTheme({Color currentColor})`，默认黑色）。按值相等。 |
| `XvgAnimationInfo` | 类 | 只读的时长信息：`settleTime`、`loops`、`loopPeriod`、`naturalDuration`。 |
| `XvgAnimationController` | 类 | 共享播放控制：`XvgAnimationController({autoplay, playbackRate})`；`time`、`status`、`info`、`playbackRate`；`play`、`pause`、`stop`、`seek`、`reverse`、`setRange`、`clearRange`、`fitDuration`；`addCue` / `removeCue`；`addEventListener` / `removeEventListener`；`addListener` / `removeListener`；`dispose`。`attach`、`detach`、`setVisible`、`documentLoading`、`documentError`、`driveTo` 是给组件内部用的 `@internal` 接口。 |
| `XvgPlaybackStatus` | 枚举 | `loading`、`playing`、`paused`、`completed`、`error`。 |
| `XvgRangeMode` | 枚举 | `once`、`loop`、`pingPong`（片段边界行为）。 |
| `XvgAnimationEvent` | 密封类 | 下列事件的基类。 |
| `XvgAnimationLoaded`、`XvgAnimationStarted`、`XvgAnimationCompleted`、`XvgAnimationLooped`、`XvgAnimationRangeLooped`、`XvgAnimationElementBegin`、`XvgAnimationElementEnd`、`XvgAnimationElementRepeat`、`XvgAnimationError` | final 类 | 播放与元素事件；按需携带 `info`、`natural`、`iteration`、`id` / `elementId`、`error` / `stack`。 |
| `XvgAnimationQuality` | 类 | 保真/吞吐配置：`adaptiveFrameSkipping`、`frameSkipThreshold`、`maxFrameDivisor`、`offscreenLayerFrameDivisor`、`approximateSimpleMasksAsClip`；预设 `balanced`、`exact`；全局 `defaultQuality`。 |
| `XvgPixelSnap` | 枚举 | `auto`、`always`、`never`：视口对齐物理像素的策略。 |
| `StringXvg`、`AssetXvg`、`NetworkXvg`、`FileXvg`、`MemoryXvg` | `ImageProvider` | 用于 `Image`、`DecorationImage`、`precacheImage`。共有参数 `width`、`height`、`colorFilter`、`theme`、`animationFrameRate`（默认 30）；另有 `source` / `assetName`+`bundle`+`package` / `url`+`headers` / `file` / `bytes`。 |
| `RustLib` | 类 | flutter_rust_bridge 生成的入口，导出供测试使用 `RustLib.initMock()` / `RustLib.dispose()`。启动后端请优先用 `Xvg.ensureInitialized()`。 |

## 注意事项与限制

* **静态 `<image href>`**：只解码内嵌的 `data:` URI。本地路径、UNC 路径与
  `file://` 一律不读取，`data:image/svg+xml` 被跳过。这是相对 `usvg` 默认解析器的
  行为变更。
* **SMIL `begin` 列表**（`0;a.end+0.2s`）在动画路径上受支持。基于事件的 begin
  （`click` 等）不支持。
* **`#rgba`** 颜色（4 位十六进制）在动画路径上受支持。
* **不可信 SVG**：`parse_svg` 是同步调用，会阻塞调用线程，所以请在后台 isolate
  中解析不可信输入。超出大小/复杂度限制的输入会抛出错误而不是崩溃；限制见
  `doc/animation-engine-features.md`。

## 设计

静态解析委托给 `usvg`（`resvg` 所基于的同一个 crate），所以静态特性的覆盖范围跟着一个
成熟、仍在维护的解析器走，不是自己手写的。静态和动画渲染都走
Flutter 自己的 GPU 管线，没有内容在 CPU 上光栅化。

## 状态

持续开发中。完整的验收标准、支持特性矩阵与性能基准历史见仓库中的 `doc/`。

## 参与贡献

欢迎在[仓库](https://github.com/icodejoo/dart-labs/tree/xvg/xvg)提 Issue 与 PR。
