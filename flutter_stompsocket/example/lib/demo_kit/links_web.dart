import 'dart:js_interop';

/// 浏览器原生打开链接，隔离新窗口的 opener。
@JS('window.open')
external JSAny? _open(JSString url, JSString target, JSString features);

/// 在独立标签页打开外链，返回是否已处理。
Future<bool> openDemoLink(String url) async {
  _open(url.toJS, '_blank'.toJS, 'noopener,noreferrer'.toJS);
  return true;
}
