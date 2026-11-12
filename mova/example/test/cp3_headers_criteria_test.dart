import 'package:flutter_test/flutter_test.dart';
import 'package:mova_example/verify_auto/cp3_headers_criteria.dart';

void main() {
  Map<String, Map<String, Object?>> paths() => {
    'extract': {'pass': true},
    'pool': {'pass': false},
    'pool-ready': {'pass': true},
    'pool-ready-cutover': {'pass': true},
  };

  test('第六轮旧 pool 失败不覆盖新截图能力验收', () {
    expect(cp3HeadersNativePathsPass(paths(), captureReady: true), isTrue);
  });
  test('未启用新截图能力仍执行旧 pool 判据', () {
    expect(cp3HeadersNativePathsPass(paths(), captureReady: false), isFalse);
  });
  for (final key in ['extract', 'pool-ready', 'pool-ready-cutover']) {
    test('$key 失败不能通过', () {
      final sample = paths()..[key] = {'pass': false};
      expect(cp3HeadersNativePathsPass(sample, captureReady: true), isFalse);
    });
    test('$key 缺失不能通过', () {
      final sample = paths()..remove(key);
      expect(cp3HeadersNativePathsPass(sample, captureReady: true), isFalse);
    });
  }

  const uri = 'http://127.0.0.1/index.m3u8?case=quality-0-yes';
  List<Map<String, Object?>> qualities() => [
    {'auto': true},
    {'auto': false, 'uri': uri, 'height': 360},
  ];
  test('auto 与真实变体及选档地址均匹配才通过', () {
    expect(cp3HeadersQualityPass(qualities(), uri, uri), isTrue);
  });
  test('空列表与只有 auto 均失败', () {
    expect(cp3HeadersQualityPass([], uri, uri), isFalse);
    expect(
      cp3HeadersQualityPass(
        [
          {'auto': true},
        ],
        uri,
        uri,
      ),
      isFalse,
    );
  });
  test('变体地址或高度不匹配失败', () {
    final sample = qualities();
    sample[1]['uri'] = '$uri-wrong';
    expect(cp3HeadersQualityPass(sample, uri, uri), isFalse);
    sample[1]['uri'] = uri;
    sample[1]['height'] = 180;
    expect(cp3HeadersQualityPass(sample, uri, uri), isFalse);
  });
  test('选档后地址错误或缺失失败', () {
    expect(cp3HeadersQualityPass(qualities(), uri, '$uri-wrong'), isFalse);
    expect(cp3HeadersQualityPass(qualities(), uri, null), isFalse);
  });
}
