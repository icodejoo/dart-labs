// ignore_for_file: avoid_relative_lib_imports
// 单元：验收执行器的 testkit 新能力——seed 字节、multipart 构造、same_as 判定、
// 信封转换器（normalize / 只装 auth）与能力集合
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../accept/lib/client.dart';
import '../accept/lib/common.dart';

/// 字节转小写十六进制。
String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 把 [form] 完整写出，返回原始字节。
Future<Uint8List> _drain(FormData form) async {
  final out = BytesBuilder();
  await for (final chunk in form.finalize()) {
    out.add(chunk);
  }
  return out.toBytes();
}

/// [haystack] 中是否连续包含 [needle]。
bool _containsBytes(Uint8List haystack, Uint8List needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// 用 [transformer] 解析一个 HTTP 200 的 JSON 信封。
Future<dynamic> _transform(EnvelopeTransformer transformer, String body) {
  final options = RequestOptions(path: '/t/x');
  return transformer.transformResponse(
      options,
      ResponseBody.fromString(body, 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      }));
}

void main() {
  group('seedBytes（CONTRACT §7 的 32 位线性同余）', () {
    test('与 CONTRACT 自检向量逐字节一致', () {
      expect(_hex(seedBytes(1, 16)), '3c5e81b40c5ec68e04a3406c97d63cfb');
      expect(_hex(seedBytes(0, 8)), '3c47d1aa629f57a3');
      expect(_hex(seedBytes(4294967295, 8)), '3c3022a1b7dfe9b9');
    });

    test('seed=42,size=1024 的首尾 16 字节固定（sha256 前缀由真实场景核对）', () {
      final bytes = seedBytes(42, 1024);
      expect(bytes.length, 1024);
      expect(_hex(bytes.sublist(0, 16)), '401693386006721edffeda7fa4dc9817');
      expect(_hex(bytes.sublist(1008)), 'a41cb284557e4867341381ccfa713623');
    });

    test('size 为 0 返回空，越界 seed 报错', () {
      expect(seedBytes(5, 0), isEmpty);
      expect(() => seedBytes(-1, 1), throwsRangeError);
      expect(() => seedBytes(4294967296, 1), throwsRangeError);
    });
  });

  group('multipart 请求体', () {
    final spec = {
      'fields': {'title': '示例'},
      'files': [
        {'name': 'doc', 'filename': 'a.bin', 'size': 8, 'seed': 7},
        {'name': 'note', 'filename': 'b.bin', 'size': 4, 'seed': 99},
      ],
    };

    test('isMultipartBody 只认单键 multipart 的对象', () {
      expect(isMultipartBody({'multipart': spec}), isTrue);
      expect(isMultipartBody({'multipart': spec, 'x': 1}), isFalse);
      expect(isMultipartBody({'a': 1}), isFalse);
      expect(isMultipartBody('multipart'), isFalse);
      expect(isMultipartBody(null), isFalse);
    });

    test('requestBody：multipart 转 FormData，其余原样', () {
      expect(requestBody({'multipart': spec}), isA<FormData>());
      final json = {'a': 1};
      expect(identical(requestBody(json), json), isTrue);
      expect(requestBody(null), isNull);
    });

    test('先写 fields 再写 files，文件内容取自 seed', () async {
      final form = buildMultipart(spec);
      expect(form.fields.map((e) => e.key), ['title']);
      expect(form.files.map((e) => e.key), ['doc', 'note']);
      expect(form.files.map((e) => e.value.length), [8, 4]);
      expect(form.files.first.value.filename, 'a.bin');
      expect(form.files.first.value.contentType?.mimeType,
          'application/octet-stream');
      final raw = await _drain(form);
      final text = latin1.decode(raw);
      expect(text.indexOf('name="title"') < text.indexOf('name="doc"'), isTrue);
      expect(text.indexOf('name="doc"') < text.indexOf('name="note"'), isTrue);
      expect(_containsBytes(raw, seedBytes(7, 8)), isTrue);
      expect(_containsBytes(raw, seedBytes(99, 4)), isTrue);
    });

    test('fields、files 都可省略；已写出的 FormData 可克隆重放且字节一致', () async {
      expect(buildMultipart({}).files, isEmpty);
      final form = buildMultipart(spec);
      final copy = form.clone();
      final first = await _drain(form);
      expect(form.isFinalized, isTrue);
      final second = await _drain(copy);
      // boundary 每个 FormData 不同，这里只比较内容长度与文件字节。
      expect(second.length, first.length);
      expect(_containsBytes(second, seedBytes(7, 8)), isTrue);
    });
  });

  group('same_as 断言', () {
    Map<String, dynamic> ok(int conn) => {
          'ok': true,
          'data': {
            'meta': {'conn': conn}
          }
        };
    final records = <String, dynamic>{
      'a': ok(3),
      'b': ok(3),
      'c': ok(4),
      'bad': {'ok': false, 'error': 'timeout'},
      'nofield': {'ok': true, 'data': {}},
    };

    test('dottedField 按点分路径取值', () {
      final data = (records['a'] as Map)['data'];
      expect(dottedField(data, 'meta.conn'), 3);
      expect(dottedField(data, 'meta.none'), isNull);
      expect(dottedField(null, 'meta.conn'), isNull);
    });

    test('相等通过', () {
      expect(
          checkSameAs('b', records, {'id': 'a', 'field': 'meta.conn'}), isNull);
    });

    test('不等、缺请求、失败请求、缺字段都判失败', () {
      expect(checkSameAs('c', records, {'id': 'a', 'field': 'meta.conn'}),
          contains('不等'));
      expect(checkSameAs('c', records, {'id': 'zz', 'field': 'meta.conn'}),
          contains('缺少请求结果'));
      expect(checkSameAs('c', records, {'id': 'bad', 'field': 'meta.conn'}),
          contains('双方都成功'));
      expect(checkSameAs('c', records, {'id': 'nofield', 'field': 'meta.conn'}),
          contains('缺失'));
    });
  });

  group('maxReadDelayMs', () {
    test('递归取场景里最大的 read_delay_ms，没有则 0', () {
      expect(maxReadDelayMs([]), 0);
      expect(
          maxReadDelayMs({
            'query': {'delay_ms': 9000}
          }),
          0);
      expect(
          maxReadDelayMs([
            {
              'request': {
                'query': {'read_delay_ms': 5000}
              }
            },
            {
              'sequence': [
                {
                  'request': {
                    'query': {'read_delay_ms': 7000}
                  }
                }
              ]
            }
          ]),
          7000);
    });
  });

  group('EnvelopeTransformer', () {
    const failure500 = '{"code":500,"message":"boom","data":null}';
    const failure401 = '{"code":401,"message":"expired","data":null}';
    const failure403 = '{"code":403,"message":"denied","data":null}';

    test('装了 normalize：任何非零业务码都转成错误', () async {
      final t = EnvelopeTransformer(true);
      await expectLater(
          _transform(t, failure500), throwsA(isA<DioException>()));
      await expectLater(
          _transform(t, failure401), throwsA(isA<DioException>()));
    });

    test('只装 auth：只有业务 401/403 转错误，其余业务码原样作为成功（D21）', () async {
      final t = EnvelopeTransformer(false, authOnly: true);
      final data = await _transform(t, failure500) as Map;
      expect(data['code'], 500);
      await expectLater(
          _transform(t, failure401), throwsA(isA<DioException>()));
      await expectLater(
          _transform(t, failure403), throwsA(isA<DioException>()));
    });

    test('都没装：业务码一律原样', () async {
      final t = EnvelopeTransformer(false);
      expect((await _transform(t, failure500) as Map)['code'], 500);
      expect((await _transform(t, failure401) as Map)['code'], 401);
    });

    test('成功信封（code=0）不受影响', () async {
      final t = EnvelopeTransformer(true, authOnly: true);
      expect((await _transform(t, '{"code":0,"data":{}}') as Map)['code'], 0);
    });
  });

  group('能力集合', () {
    test('插件级仍是 17 个，细分能力单独声明', () {
      expect(capabilities.length, 17);
      expect(subCapabilities,
          {'multipart', 'keep-alive', 'share-retry', 'timeout-send'});
      expect(supportedCapabilities.length, 21);
    });

    test('不声明 mock-in-chain（mock 在传输层）', () {
      expect(supportedCapabilities, isNot(contains('mock-in-chain')));
    });

    test('timeout 允许 send_ms 字段', () {
      expect(pluginFields['timeout'], contains('send_ms'));
    });
  });
}
