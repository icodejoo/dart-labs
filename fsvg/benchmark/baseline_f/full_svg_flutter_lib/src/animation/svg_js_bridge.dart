// No-op stub of the original SVG JS bridge.
//
// The upstream SvgJsBridge embedded a QuickJS runtime (quickjs_engine, a
// native plugin) to execute inline <script> blocks in JS-driven SVGs
// (e.g. SVGator JS exports). This fork drops that native dependency: we
// only need SMIL / CSS animation, and those never touch this bridge —
// it's constructed solely when a document has inline <script> elements.
//
// The class keeps the same public API so the rest of the renderer compiles
// and runs unchanged; every member is inert. A JS-driven SVG therefore
// renders as its static markup with no script side effects (acceptable:
// this build intentionally has no JS engine).
//
// 原 SVG JS 桥的空实现。上游用 QuickJS（quickjs_engine 原生插件）执行
// 内联 <script> 的 JS 型 SVG；本 fork 去掉该原生依赖——我们只要 SMIL/CSS
// 动画，这条路不经过本桥（它只在文档含内联 <script> 时才被创建）。
// 保留同名公开 API 让渲染器照常编译运行，方法全部空转；JS 型 SVG 会按
// 静态标记渲染、不执行脚本（本构建刻意不带 JS 引擎，符合预期）。

import 'dart:async';

import 'svg_dom.dart';

/// Inert replacement for the QuickJS-backed JS bridge (JS execution removed).
///
/// QuickJS 版 JS 桥的惰性替身（已移除 JS 执行能力）。
class SvgJsBridge {
  /// Mirrors the original constructor signature; all inputs are ignored.
  ///
  /// 与原构造函数签名一致；所有入参被忽略。
  SvgJsBridge({
    required SvgDocument document,
    required void Function() markNeedsRepaint,
    required void Function(
      String elementId,
      String eventType,
      void Function() callback,
    )
    addEventHandler,
  });

  /// Resolves immediately — there are no external scripts to load.
  ///
  /// 立即完成——没有需要加载的外部脚本。
  Future<void> get externalScriptsLoaded => Future<void>.value();

  /// No-op: inline scripts are not executed. / 空转：不执行内联脚本。
  void executeScript(String code) {}

  /// No-op: nothing to finalize. / 空转：无需收尾。
  void onInlinesDone() {}

  /// No-op: no load events are fired. / 空转：不派发 load 事件。
  void fireLoadEvents() {}

  /// No-op: inline event handlers are not run. / 空转：不运行内联事件处理器。
  void dispatchInlineHandler(String elementId, String handlerCode) {}

  /// Always returns null — no JS evaluator is available.
  ///
  /// 始终返回 null——没有可用的 JS 求值器。
  String? evaluateForDebug(String code) => null;

  /// No-op: nothing to release. / 空转：无资源需要释放。
  void dispose() {}
}
