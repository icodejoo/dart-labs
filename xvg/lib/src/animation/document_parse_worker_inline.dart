import 'svg_document_parser.dart';

/// 浏览器没有 Dart isolate；主线程解析，沿用解析器输入限制。
class DocumentParseWorker {
  /// 共享内联解析器。
  static final instance = DocumentParseWorker._();

  /// 创建内联解析器。
  DocumentParseWorker._();

  /// 大文档会占用当前帧，不启用 FRB WorkerPool。
  Future<SvgDocument> parse(String source) =>
      Future.sync(() => parseAnimatedSvgDocument(source));

  /// 浏览器没有后台 worker，释放操作为空。
  Future<void> dispose() async {}
}
