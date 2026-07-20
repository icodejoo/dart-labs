import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

RawResult _r(int no, String winner) => RawResult(no: no, winner: winner, bankerPair: false, playerPair: false);

void main() {
  group('deriveRoad', () {
    test('大眼仔（k=1）在第二列第二格才开始起算', () {
      // 列结构 [B] [P] [B] ... 前两列（k=1 至少要 col==1,row==1 或 col==2,row==0）
      // 才会开始产出条目：短序列时 entries 应为空。
      final short = buildBigRoad([_r(1, 'B'), _r(2, 'P')]);
      final derived = deriveRoad(short, 1);
      expect(derived.entries, isEmpty);
    });

    test('列长规律时落红，列长不规律时落蓝', () {
      // 构造：col0=[B,B]（长度2），col1=[P]（长度1），col2=[B]开始...
      // 大眼仔从 col=1,row=... 或 col=2,row=0 起算，比较 (c-1) 与 (c-1-k) 列长。
      final results = [
        _r(1, 'B'),
        _r(2, 'B'), // col0 长度2
        _r(3, 'P'), // col1 长度1
        _r(4, 'B'), // col2 长度1（新列，起算点 c=2,row=0，k=1）
        _r(5, 'P'), // col3 长度1
        _r(6, 'B'), // col4 长度1
      ];
      final bigRoad = buildBigRoad(results);
      final derived = deriveRoad(bigRoad, 1);

      // col2 新列：比较 col1(长度1) 与 col0(长度2) → 不同 → 蓝
      expect(derived.entries.first, DerivedColor.blue);
    });

    test('sourceCellIndex 与 entries 等长，且索引指向大路 cells', () {
      final results = List.generate(10, (i) => _r(i + 1, i.isEven ? 'B' : 'P'));
      final bigRoad = buildBigRoad(results);
      final derived = deriveRoad(bigRoad, 1);
      expect(derived.sourceCellIndex, hasLength(derived.entries.length));
      for (final idx in derived.sourceCellIndex) {
        expect(idx, lessThan(bigRoad.cells.length));
      }
    });
  });

  group('derivedToColumns', () {
    test('连续同色归并成一列，规则与大路一致但无和局', () {
      final cols = derivedToColumns([
        DerivedColor.red,
        DerivedColor.red,
        DerivedColor.blue,
        DerivedColor.blue,
        DerivedColor.blue,
        DerivedColor.red,
      ]);
      expect(cols, [2, 3, 1]);
    });

    test('空输入返回空列表', () {
      expect(derivedToColumns(const []), isEmpty);
    });
  });
}
