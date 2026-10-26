@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter_test/flutter_test.dart';

// 当前源码测试引擎的地址。
const _engineUrl = String.fromEnvironment('FFUZZY_TEST_ENGINE_URL');
// 测试查询。
const _query = 'hello';
// 原始键文本。
const _primary = '原始';
// 附加键文本。
const _alias = '别名';
// 预期高亮下标。
const _indices = [0, 1, 2, 3, 4];

// 读取当前网页测试引擎。
@JS('_ffzModule')
external _TestEngine get _engine;

// 提供网页测试的分配故障注入接口。
extension type _TestEngine._(JSObject _) implements JSObject {
  // 设置后续分配的成功预算。
  @JS('_ffz_ffi_dbg_fail_after')
  external void failAfter(int count);
}

// 验证搜索、生命周期和失败恢复的回归契约。
void main() {
  test('并发初始化共享一次加载且等待中的销毁不复活', () async {
    final c = FuzzyCorpus.strings([_query]);
    final pending = c.asyncFuzzy(_query);
    final rejected = expectLater(pending, throwsStateError);
    c.dispose();
    final first = ffuzzyInit(webUrl: _engineUrl);
    final second = ffuzzyInit(webUrl: _engineUrl);
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    await rejected;
    expect(() => c.fuzzy(_query), throwsStateError);
  });

  test('非 fuzzy 模式共用别名键与归一化高亮', () {
    final c = FuzzyCorpus.strings([]);
    addTearDown(c.dispose);
    c.addKey('display', [const FuzzyKey('café')]);
    for (final search in [c.substring, c.prefix, c.postfix, c.exact]) {
      final hit = search('cafe', highlight: true).single;
      expect(hit.matchedKey, 1);
      expect(hit.indices, [0, 1, 2, 3]);
    }
  });

  test('组合搜索与近似搜索遵守高亮选项', () async {
    final c = FuzzyCorpus.strings([_query]);
    addTearDown(c.dispose);
    for (final strategy in SearchStrategy.values) {
      expect(
          c.search(_query, strategy: strategy, highlight: true).single.indices,
          _indices);
      expect(
          (await c.asyncSearch(_query, strategy: strategy, highlight: true))
              .single
              .indices,
          _indices);
      expect(c.search(_query, strategy: strategy).single.indices, isEmpty);
    }
    expect(c.dual(_query, highlight: true).approx.single.indices, _indices);
  });
  test('引擎新增失败不提交半条目且保持索引对齐', () {
    for (final keyed in [false, true]) {
      for (var budget = 0; budget < 8; budget++) {
        final c = FuzzyCorpus.strings([]);
        var committed = false;
        _engine.failAfter(budget);
        try {
          if (keyed) {
            c.addKey(_primary, [const FuzzyKey(_alias)]);
          } else {
            c.add(_primary);
          }
          committed = true;
        } on FuzzyException {
          // 桥接层必须报告原生新增失败。
        } finally {
          _engine.failAfter(-1);
        }
        if (budget == 0) expect(committed, isFalse);
        expect(c.length, committed ? 1 : 0);
        c.add(_query);
        expect(c.exact(_query).single.index, committed ? 1 : 0);
        if (committed && keyed) expect(c.exact(_alias).single.raw, _primary);
        c.dispose();
      }
    }
  });

  test('网页公共入口拒绝非法距离和超限查询', () async {
    final c = FuzzyCorpus.strings([_query]);
    addTearDown(c.dispose);
    for (final distance in [-1, 11]) {
      for (final strategy in SearchStrategy.values) {
        expect(
            () => c.search(_query, strategy: strategy, maxDistance: distance),
            throwsRangeError);
        await expectLater(
            c.asyncSearch(_query, strategy: strategy, maxDistance: distance),
            throwsRangeError);
      }
      expect(() => c.approx(_query, maxDistance: distance), throwsRangeError);
      expect(() => c.dual(_query, maxDistance: distance), throwsRangeError);
    }
    final boundary = '😀' * 64;
    c.add(boundary);
    expect(c.approx(boundary, maxDistance: 0).single.raw, boundary);
    final long = '$boundary😀';
    for (final strategy
        in SearchStrategy.values.where((s) => s != SearchStrategy.fuzzy)) {
      expect(() => c.search(long, strategy: strategy), throwsArgumentError);
    }
    expect(() => c.dual(long), throwsArgumentError);
  });
}
