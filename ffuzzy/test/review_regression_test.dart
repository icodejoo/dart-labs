import 'dart:io';
import 'dart:ffi';

import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter_test/flutter_test.dart';

const _items = ['alpha', 'beta', 'gamma'];
const _failure = '回调失败';
const _query = 'hello';
const _primary = '原始';
const _alias = '别名';

void main() {
  String libPath() {
    final root = Directory.current.path;
    if (Platform.isWindows) return '$root/ffz.dll';
    if (Platform.isMacOS) return '$root/libffz.dylib';
    return '$root/build_x86_64/libffuzzy.so';
  }

  test('删除回调抛异常时保留原索引', () {
    final c = FuzzyCorpus.strings(_items, libraryPath: libPath());
    addTearDown(c.dispose);
    expect(
        () => c.removeWhere((s) {
              if (s == _items[1]) throw StateError(_failure);
              return true;
            }),
        throwsStateError);
    expect(c.length, _items.length);
    for (final item in _items) {
      expect(c.exact(item).single.raw, item);
    }
  });

  test('刷新源抛异常时保留原索引', () {
    final c = FuzzyCorpus.strings(_items, libraryPath: libPath());
    addTearDown(c.dispose);
    Iterable<String> source() sync* {
      yield 'changed';
      throw StateError(_failure);
    }

    expect(() => c.refresh(source()), throwsStateError);
    expect(c.length, _items.length);
    expect(c.exact(_items.last).single.raw, _items.last);
  });

  test('重建失败后列表与已写入索引一致', () {
    var fail = false;
    final c = FuzzyCorpus<String>(_items, stringOf: (s) {
      if (fail && s == _items[1]) throw StateError(_failure);
      return s;
    }, libraryPath: libPath());
    addTearDown(c.dispose);
    fail = true;
    expect(c.refresh, throwsStateError);
    expect(c.length, 1);
    expect(c.exact(_items.first).single.raw, _items.first);
    expect(c.fuzzy(_items.last), isEmpty);
  });

  test('编辑距离与组合策略遵守高亮选项', () async {
    final c = FuzzyCorpus.strings([_query], libraryPath: libPath());
    addTearDown(c.dispose);
    final indices = List<int>.generate(_query.length, (i) => i);
    for (final strategy in SearchStrategy.values) {
      expect(
          c.search(_query, strategy: strategy, highlight: true).single.indices,
          indices);
      expect(
          (await c.asyncSearch(_query, strategy: strategy, highlight: true))
              .single
              .indices,
          indices);
      expect(c.search(_query, strategy: strategy).single.indices, isEmpty);
    }
    expect(c.dual(_query, highlight: true).approx.single.indices, indices);
    expect((await c.asyncDual(_query, highlight: true)).fuzzy.single.indices,
        indices);
  });

  test('自动编辑距离按码点计数', () {
    expect(autoMaxDistance('😀😀'), 0);
    expect(autoMaxDistance('😀😀😀'), 1);
    expect(autoMaxDistance('😀😀😀😀😀'), 1);
  });

  test('字面量保留反斜杠与自定义键类型', () {
    const literal = r'a\ b';
    const kind = 100000;
    final c = FuzzyCorpus.strings([literal], libraryPath: libPath());
    addTearDown(c.dispose);
    expect(c.exact(literal).single.raw, literal);
    c.addKey('display', [const FuzzyKey(_query, kind: kind)]);
    expect(c.exact(_query).single.matchedKindCode, kind);
  });
  test('stringOf 中销毁后拒绝继续写入原生对象', () {
    var dispose = false;
    late FuzzyCorpus<String> c;
    c = FuzzyCorpus<String>(_items, stringOf: (s) {
      if (dispose) c.dispose();
      return s;
    }, libraryPath: libPath());
    dispose = true;
    expect(() => c.add(_query), throwsStateError);
  });
  test('异步新增在 stringOf 中销毁后拒绝启动工作线程', () async {
    var dispose = false;
    late FuzzyCorpus<String> c;
    c = FuzzyCorpus<String>(_items, stringOf: (s) {
      if (dispose) c.dispose();
      return s;
    }, libraryPath: libPath());
    dispose = true;
    await expectLater(c.asyncAddAll([_query]), throwsStateError);
  });
  test('新增分配失败不提交半条目且索引保持一致', () async {
    final lib = DynamicLibrary.open(libPath());
    final failAfter =
        lib.lookupFunction<Void Function(Int32), void Function(int)>(
            'ffz_ffi_dbg_fail_after');
    for (final keyed in [false, true]) {
      for (var budget = 0; budget < 8; budget++) {
        final c = FuzzyCorpus.strings([], libraryPath: libPath());
        var committed = false;
        failAfter(budget);
        try {
          if (keyed) {
            c.addKey(_primary, [const FuzzyKey(_alias)]);
          } else {
            c.add(_primary);
          }
          committed = true;
        } on FuzzyException {
          // 分配失败应由桥接层明确报告。
        } finally {
          failAfter(-1);
        }
        if (budget == 0) expect(committed, isFalse);
        expect(c.length, committed ? 1 : 0);
        c.add(_query);
        expect(c.exact(_query).single.index, committed ? 1 : 0);
        if (committed && keyed) expect(c.exact(_alias).single.raw, _primary);
        c.dispose();
      }
    }
    final c = FuzzyCorpus.strings(_items, libraryPath: libPath());
    addTearDown(c.dispose);
    failAfter(0);
    final result = c.asyncAddAll([_primary]);
    try {
      await expectLater(result, throwsStateError);
    } finally {
      failAfter(-1);
    }
  });

  test('公共搜索统一拒绝非法距离和超限近似查询', () async {
    final c = FuzzyCorpus.strings([_query], libraryPath: libPath());
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
      await expectLater(
          c.asyncDual(_query, maxDistance: distance), throwsRangeError);
      expect(
          () => c.asyncApprox(_query, maxDistance: distance), throwsRangeError);
    }
    final boundary = '😀' * 64;
    c.add(boundary);
    expect(c.approx(boundary, maxDistance: 0).single.raw, boundary);
    final long = '$boundary😀';
    for (final strategy
        in SearchStrategy.values.where((s) => s != SearchStrategy.fuzzy)) {
      expect(() => c.search(long, strategy: strategy), throwsArgumentError);
      await expectLater(
          c.asyncSearch(long, strategy: strategy), throwsArgumentError);
    }
    expect(() => c.dual(long), throwsArgumentError);
    expect(() => c.approx(long), throwsArgumentError);
    c.add(long);
    expect(c.exact(long).single.raw, long);
  });
}
