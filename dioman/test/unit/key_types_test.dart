import 'dart:convert';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// 本文件共用的测试值。
const _diomanLiteral0 = '1';

/// 本文件共用的测试值。
const _diomanLiteral1 = 'nested';

/// 固定测试载荷。
const _payload = 'payload';

/// 自动键的类型隔离与字节无损事实。
void main() {
  test('[DiomanKeyService.build] 深模式与快速模式均隔离四种 responseType', () {
    for (final fast in [false, true]) {
      final service = DiomanKeyService(DiomanKeyOptions(fastMode: fast));
      final keys = <String?>{
        for (final type in ResponseType.values)
          service.build(RequestOptions(responseType: type))
      };
      expect(keys.length, ResponseType.values.length);
      for (final type in ResponseType.values) {
        expect(service.build(RequestOptions(responseType: type), _payload),
            _payload);
      }
    }
  });
  test('[DiomanKeyService.build] Map 键带类型、嵌套排序稳定且不丢混合键', () {
    const service = DiomanKeyService(DiomanKeyOptions());
    final mixed = <Object?, Object?>{
      1: _payload,
      _diomanLiteral0: true,
      null: false,
      true: 2
    };
    final encoded = service.build(RequestOptions(data: mixed))!;
    final fields = jsonDecode(encoded) as List;
    final body = jsonDecode((fields[2] as Map)['map'] as String) as Map;
    expect(
        body.keys, containsAll(['number:1', 'string:1', 'null:', 'bool:true']));
    expect(body.length, 4);
    expect(
        service.build(RequestOptions(data: {1: _payload})),
        isNot(
            service.build(RequestOptions(data: {_diomanLiteral0: _payload}))));
    expect(service.build(RequestOptions(data: {Object(): 1})), isNull);
    final nested = RequestOptions(data: {_diomanLiteral1: mixed});
    expect(
        service.build(nested),
        service.build(RequestOptions(data: {
          _diomanLiteral1: Map.fromEntries(mixed.entries.toList().reversed)
        })));
  });
  test('[DiomanKeyService.build] B8 字节体保留长度、哈希和完整 base64', () {
    const bytes = [1, 2, 3];
    final fields = jsonDecode(const DiomanKeyService(DiomanKeyOptions())
        .build(RequestOptions(data: bytes))!) as List;
    expect((fields[2] as Map)['bytes'], [3, 1456420779, base64Encode(bytes)]);
  });
}
