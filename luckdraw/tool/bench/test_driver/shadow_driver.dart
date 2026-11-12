import 'dart:convert';
import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver_extended.dart';

/// 保存真机截图和 ROI；SHADOW_OUTPUT 必须是本轮独立目录，防止覆盖旧证据。
Future<void> main() async {
  final output = Directory(Platform.environment['SHADOW_OUTPUT'] ??
      '../../docs/device/shadow_capture');
  await output.create(recursive: true);
  final driver = await FlutterDriver.connect();
  if (driver is! VMServiceFlutterDriver) {
    await driver.close();
    throw StateError('阴影对照只接受安卓 VM 驱动');
  }
  late final bool impellerEnabled;
  try {
    final response = await driver.serviceClient.callServiceExtension(
        'ext.ui.window.impellerEnabled',
        isolateId: driver.appIsolate.id);
    final enabled = response.json?['enabled'];
    if (enabled is! bool) throw StateError('未收到引擎实际渲染后端状态');
    impellerEnabled = enabled;
  } on Object {
    await driver.close();
    rethrow;
  }
  await integrationDriver(
      driver: driver,
      onScreenshot: (name, bytes, [arguments]) async {
        if (bytes.length < 1000) return false;
        final file = File('${output.path}/$name.png');
        if (await file.exists()) throw StateError('拒绝覆盖本轮截图: ${file.path}');
        await file.writeAsBytes(bytes, flush: true);
        return true;
      },
      responseDataCallback: (data) async {
        if (data == null) throw StateError('未收到阴影场景元数据');
        final metadata = Map<String, dynamic>.of(data)..remove('screenshots');
        final requested = metadata['backend_requested'];
        if ((requested != 'skia' && requested != 'impeller') ||
            (requested == 'impeller') != impellerEnabled) {
          throw StateError('请求后端与引擎实际状态不一致: $requested/$impellerEnabled');
        }
        metadata['impeller_enabled'] = impellerEnabled;
        metadata['backend_verified_by'] = 'ext.ui.window.impellerEnabled';
        metadata['recorded_at'] = DateTime.now().toUtc().toIso8601String();
        await File('${output.path}/metadata.json').writeAsString(
            '${const JsonEncoder.withIndent('  ').convert(metadata)}\n');
      });
}
