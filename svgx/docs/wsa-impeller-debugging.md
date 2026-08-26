# WSA(Windows Subsystem for Android)上"内容全黑"的真实成因

> 从 `CLAUDE.md` 拆出(原"WSA 上'内容全黑'的真实成因"整节)。结论:**与 svgx 无关**,是 Flutter Material `AppBar` + WSA 模拟 GPU 驱动的组合问题。

之前在 WSA(`adb` 地址 `127.0.0.1:58526`,`product:windows_x86_64`)上目视验收 svgx 时,看到画面整片漆黑,一度怀疑是 svgx 自己的渲染管线在 WSA 的虚拟 GPU 上挂了。这一轮做了完整的逐层剥离实验,把触发条件钉死了,记录在此,以后不用再从头怀疑一遍。

## 一、先纠正两个"看起来像 bug、其实是环境假象"的坑

- **`adb exec-out screencap` 在 WSA 上根本拍不到应用画面**。WSA 的应用是 freeform 窗口,由 Windows 宿主侧合成,Android 侧的 display buffer 是空的——试过 `-d 100`/`-d 101`/`-d 129`,全部返回纯黑 2560x1440,和应用实际画的是什么毫无关系。**别再用 screencap 判断 WSA 上的渲染结果**。可靠办法是在 Windows 侧按窗口类名(`com.example.svgx_example`)找到 HWND,用 `PrintWindow(hwnd, hdc, 2)` 抓图。
- **窗口经常处于"有 HWND 但没有 surface"的状态**(`dumpsys window windows` 里 `mViewVisibility=0x4/0x8`、`mHasSurface=false`),这时候截到的是桌面背景,不是"应用渲染成透明/全黑"。截图前必须先确认 Android 侧 `mHasSurface=true`,否则会把"窗口没显示"误读成"渲染失败"。

## 二、Impeller 在 WSA 上的实际后端

logcat 明确:先尝试 Vulkan(`android_context_vk_impeller.cc`),随即回落到 **OpenGLES**(`android_context_gl_impeller.cc`),走的是 `/vendor/lib64/egl/libEGL_emulation.so`(goldfish 模拟驱动,且 `/dev/goldfish_pipe` 缺失,一直刷 `open_verbose: both vsock and goldfish_pipe paths failed`)。也就是说 WSA 上跑的是 **Impeller + 模拟 GLES 驱动**,不是原生 GPU。

**`--no-enable-impeller` / manifest 里的 `io.flutter.embedding.android.EnableImpeller=false` 在 Flutter 3.47 上命令行开关已经失效**——实测加了这条 meta-data 重新打包,logcat 依然是 "Using the Impeller rendering backend (OpenGLES)",画面也没有任何变化。Android 侧的 Skia 后端已经被移除,这条常见的规避手段现在不成立,别再浪费一次编译去试。(注:manifest 的等价开关另有更新,见第六节。)

## 三、逐层剥离的实测结论:触发点是 Material `AppBar`,不是 svgx

全部在 **release 模式**(`flutter build apk --release --target-platform android-x64` + `adb install`)下做,每个变体一张 `PrintWindow` 截图:

| 变体 | 结果 |
|---|---|
| 纯 `Text` / `Container` / `Center` / 真实溢出裁剪的 `SingleChildScrollView` / `Opacity`(saveLayer)/ `ClipRRect` / `RepaintBoundary` | **全部正常渲染** |
| svgx 静态图标 + 动画图标(含 `<image>` 位图、动画 `<mask>`、静态/动画渐变 shader、`<text>`、`<animateMotion>`、`<use>`、`skewX`) | **全部正常渲染** |
| `Scaffold(appBar: AppBar(...), body: ...)` | **AppBar 那一条正常画出来,AppBar 以下整个 body 全黑**——连 `Scaffold.backgroundColor` 显式设成纯绿都不画,body 里只放一个黄底红字的 `Text` 也是黑的 |
| 去掉 `appBar`(其余完全不变) | **立刻全部正常** |
| `AppBar(elevation: 0, scrolledUnderElevation: 0, backgroundColor: 蓝, systemOverlayStyle: light)` | **仍然全黑** → 不是 elevation / surfaceTint 的锅 |
| 不用 AppBar,单独调 `SystemChrome.setSystemUIOverlayStyle(...)` | **正常** → 不是 SystemUiOverlayStyle 的锅 |
| 自制顶栏 `PreferredSize + Container`(同样 56 高) | **正常** → 不是"顶部有一条栏"的锅 |
| 自制顶栏 `PreferredSize + Material(elevation: 4)` | **正常** → 不是 `Material` 本身的锅 |

## 四、结论(明确、不含糊)

**WSA 上看到的"svgx 内容全黑",不是 svgx 的 bug,svgx 的静态路径和动画引擎在 WSA + Impeller(GLES 模拟驱动)下渲染完全正常。**真正的触发点是 Flutter 自己的 Material `AppBar`:只要 `Scaffold` 挂了 `AppBar`,在 WSA 这套模拟 GLES 驱动上,AppBar 以下的整块画面就不会被合成出来(呈现为窗口的透明底色,看上去就是全黑);把 `AppBar` 拿掉,同一个页面、同一批 svgx 组件立刻全部正常显示。这是 **Flutter 引擎 + WSA 模拟 GPU 驱动**这一层的问题,与本库无关。

## 五、上游 issue 状态:**没有找到精确匹配**

搜过 flutter/flutter 的 Impeller 黑屏系列(#160866、#155973、#154103、#164717、#154531、#160948、#159851、#165298)以及 WSA 相关(#137905),**没有任何一条描述"AppBar 导致其余画面全黑"或 WSA 上的这个具体现象**。WSA 本身微软已于 2025 年 3 月停止支持,上游也基本不会再有人报这个平台的问题。

最接近的类比仍然是 [flutter/flutter#164735](https://github.com/flutter/flutter/issues/164735)("Black screen with Impeller enabled",无 GPU passthrough 的 macOS 虚拟机里 Impeller 拿不到真实 GPU 而黑屏,且 3.39+ 之后再也没有关掉 Impeller 的开关)——**架构上同类(虚拟化 GPU + 无法关闭的 Impeller),但不是同一个 bug**,如实记录为"最接近的先例",不要当成已确认的根因引用。

## 六、追加实测:`EnableImpeller=false` manifest 开关仍然有效(2026-08-26 起,确认延续到 Flutter 3.47)

命令行 `--no-enable-impeller` 已经失效,但 **`AndroidManifest.xml` 里的等价 meta-data 开关目前(Flutter 3.47)仍然生效**,亲自实测两轮确认(先用纯 `Scaffold+AppBar+Text` 验证,再用真实 `SvgX.string`(含动画描边 + 静态渐变)+ `AppBar` 组合验证,WSA 上都恢复正常显示):

```xml
<!-- example/android/app/src/main/AndroidManifest.xml, <application> 标签内 -->
<meta-data
    android:name="io.flutter.embedding.android.EnableImpeller"
    android:value="false" />
```

跑起来后 logcat 会打印一条明确的弃用警告(`[Action Required]: Impeller opt-out deprecated ... These options are going to go away in an upcoming Flutter release`)——**这条开关官方标注为即将移除,不是长期方案**,只在需要给 WSA 做目视验证时临时加,验证完就撤掉,**不要留在实际 example app / 发布配置里**:

- 真机完全不需要它(真机上 `AppBar`+Impeller 从未出过问题,详见上文"逐层剥离"实测)。
- 一旦某个未来 Flutter 版本真的把这个开关删掉,留着它反而会变成一处随时会失效的技术债。

## 七、精确根因定位:AppBar 内部无条件的 `ClipRect(clipBehavior: Clip.hardEdge)`

之前"elevation:0 仍然全黑"这个实测排除了 `PhysicalModel`/阴影合成这个方向。读 `packages/flutter/lib/src/material/app_bar.dart` 源码定位到真正的触发点:`AppBar.build()` 里有一段**不受 `elevation`/`shape` 影响、永远存在**的包裹:

```dart
Widget appBar = ClipRect(
  clipBehavior: widget.clipBehavior ?? Clip.hardEdge,
  child: CustomSingleChildLayout(...),
);
```

`RenderClipRect.paint()` 在 `clipBehavior != Clip.none` 时会调用 `context.pushClipRect(...)`,强制 `needsCompositing = true`,往合成层树里挂一个 `ClipRectLayer`。这是链路里唯一"任何 AppBar 都会触发、且和 elevation 无关"的合成层来源,和已经实测的"哪怕 `elevation:0` 依然全黑"完全吻合。同一份 `Material` 组件在 `elevation:0` 时源码明确标注走 fast path、**不会** `Canvas.saveLayer`(`material.dart` 里有对应注释),所以之前"AppBar 默认阴影触发 saveLayer"这个猜测方向已被推翻。

**实测验证**:`AppBar(clipBehavior: Clip.none)` 在 WSA 上亲自跑通两轮(先纯 `Text`,再 `SvgX.string` 真实内容),body 立刻恢复正常显示,Impeller **全程保持启用,未降级**。这比"整体关闭 Impeller"精准得多。

## 八、两套修复方案(互补;方案 B 是当前实际生效的默认行为,方案 A 仅留档未应用到代码)

用户已明确决策:**方案 B(原生运行时检测)作为默认行为落地**,`example` app 的 `AppBar` **不**加 `clipBehavior: Clip.none`——理由是方案 B 覆盖面更广(不管哪个 widget 触发都能兜住),方案 A 只对显式加了参数的那一个 AppBar 实例生效,容易漏加。方案 A 的调研结论仍然完整记录在这里,作为"如果以后想换更精准、零原生代码的修法"的参考,**但当前代码库里没有任何地方实际使用 `Clip.none`**。

### 方案 A(仅记录,未应用):`AppBar(clipBehavior: Clip.none)`

- 零原生代码,Impeller 不降级,只对显式加了这个参数的 AppBar 实例生效。
- **适用边界(源码级调研结论,`packages/flutter/lib/src/material/app_bar.dart`)**:这个 `ClipRect` 从 Flutter 早期版本起就是专门为 `SliverAppBar`+`flexibleSpace` 的"滚动收缩/展开大标题栏"场景设计的——`_ToolbarContainerLayout` 让工具栏内容永远按完整 `toolbarHeight` 布局,当外层滚动把实际分配高度压缩到小于 `toolbarHeight` 时,`ClipRect` 负责把多出来的部分裁掉(视觉效果是"工具栏内容向上滚出视野"),不裁就会溢出画到 body 上。**固定高度、不带 `flexibleSpace`、不在 `SliverAppBar`/`CustomScrollView` 里用的静态 AppBar(svgx example app 正是这种用法),外层分配高度恒等于 `toolbarHeight`,这个裁剪约束条件根本不会触发,`Clip.none` 理论上没有任何视觉差异**,如果以后要用,可以放心加。`AppBar(bottom: TabBar(...))` 这类 `bottom` 区域本来就在这段 `ClipRect` 包裹范围之外,不受 `clipBehavior` 影响。
- **不安全的场景**:`SliverAppBar` + `flexibleSpace`(可折叠大图标题栏那类特效)——`Clip.none` 会让收缩动画过程中溢出的内容真实画到 body 上,是实打实的视觉 bug,不要对这类 AppBar 用这个 workaround。

### 方案 B(当前默认生效):原生运行时检测 + 动态关闭 Impeller

- 文件:`example/android/app/src/main/kotlin/com/example/svgx_example/MainActivity.kt`,override `FlutterActivity.getFlutterShellArgs()`,用 `Build.FINGERPRINT`/`MODEL`/`PRODUCT`/`MANUFACTURER`/`BRAND`/`DEVICE`/`HARDWARE` 做保守指纹匹配(WSA 专属特征 + 常见模拟器特征),命中时追加 `--enable-impeller=false`;真机指纹不匹配,行为完全不变。
- **技术依据**(已读源码确认,不是猜测):`FlutterActivity.getFlutterShellArgs()` 是官方公开的可 override 扩展点,其返回值最终传入 `FlutterLoader.ensureInitializationComplete(context, dartVmArgs)`——`FlutterLoader.java` 源码注释明确写着 manifest metadata 先应用、**之后被 command-line/shell args 覆盖**,所以这条路径的优先级高于(且不需要碰)`AndroidManifest.xml` 的 `EnableImpeller` 项。
- 这段代码会被编译进**所有构建变体**(debug/profile/release),检测逻辑在正式产物里同样生效。
- **这是覆盖"未知触发点"的安全网**:如果以后某个 AppBar 忘了加 `clipBehavior: Clip.none`,或者别的 Material widget 也用了类似的无条件 `ClipRect(hardEdge)` 触发同样的问题,这套方案依然能兜住(代价是 WSA/模拟器上 Impeller 整体降级为 Skia legacy,真机完全不受影响)。
- **未做的验证**:检测逻辑目前只在 WSA 上验证过命中,没有在接入的真机上验证过"确实不会误判",如实标注为遗留验证项,建议真机重新连接后跑一次确认指纹不匹配、Impeller 未被关闭。

## 九、以后在 WSA 上做目视验证的实操建议

1. **不要用 `adb screencap`**,用 Windows 侧的 `PrintWindow` 抓 WSA 窗口;截图前先用 `dumpsys window windows` 确认 `mHasSurface=true`。
2. **需要用到 `Scaffold(appBar: AppBar(...))` 的页面**,验证前临时在 `AndroidManifest.xml` 加上面那条 `EnableImpeller=false` meta-data,验证完记得撤掉;也可以选择直接把测试页面的 `AppBar` 换成 `appBar: null` + `PreferredSize/Container` 自制顶栏,两种规避手段都实测有效,看哪种对当次验证更省事。
3. WSA 只适合当"能不能跑起来"的冒烟环境。**性能基准和最终目视验收要以真机为准**,WSA 的模拟 GLES 驱动既不代表真实 GPU 性能,也会制造上面这种假故障。
