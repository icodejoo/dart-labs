import 'package:flutter/material.dart';
import 'package:mova/mova.dart';

/// Checks constructor assertions on the actual debug VM.
///
/// 在真机 debug VM 检查构造期断言，不以主机单测替代。
void main() {
  var enabled = false;
  assert(() { enabled = true; return true; }());
  var tracks = false;
  var zoom = false;
  try {
    final count = int.parse('0');
    MovaDanmakuConfig(trackCount: count);
  } on AssertionError catch (_) { tracks = true; }
  try {
    final maximum = double.parse('0.5');
    MovaGestureConfig(maxZoom: maximum);
  } on AssertionError catch (_) { zoom = true; }
  // ignore: avoid_print
  print('RERUN_ASSERT enabled=$enabled trackCount=$tracks maxZoom=$zoom');
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(
    'RERUN_ASSERT enabled=$enabled trackCount=$tracks maxZoom=$zoom',
  )))));
}
