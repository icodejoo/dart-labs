import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

void main() {
  group('placeOnGrid', () {
    test('单列高度不超过 rows 时不换列', () {
      final placed = placeOnGrid([3], 6);
      expect(placed.map((p) => (p.physCol, p.physRow)), [(0, 0), (0, 1), (0, 2)]);
    });

    test('列高超过 rows 时向右换列（龙尾右弯，停留在底行不回到顶行）', () {
      final placed = placeOnGrid([8], 6);
      // 前 6 格占满第 0 列（row 0..5）；到底后每多一格就向右挪一列，
      // 停留在同一行（row=5），不是回到 row=0 重新往下走——这是"龙尾右弯"的本意。
      expect(placed[5].physCol, 0);
      expect(placed[5].physRow, 5);
      expect(placed[6].physCol, 1);
      expect(placed[6].physRow, 5);
      expect(placed[7].physCol, 2);
      expect(placed[7].physRow, 5);
    });

    test('多列依次从各自 headCol 起摆放', () {
      final placed = placeOnGrid([2, 1, 3], 6);
      // 第一列 2 格：(0,0)(0,1)；第二列 1 格：(1,0)；第三列 3 格：(2,0)(2,1)(2,2)
      expect(placed.map((p) => (p.physCol, p.physRow)), [
        (0, 0),
        (0, 1),
        (1, 0),
        (2, 0),
        (2, 1),
        (2, 2),
      ]);
    });
  });

  group('placeSequential', () {
    test('按列优先顺序摆放扁平索引', () {
      expect((placeSequential(0, 6).physCol, placeSequential(0, 6).physRow), (0, 0));
      expect((placeSequential(5, 6).physCol, placeSequential(5, 6).physRow), (0, 5));
      expect((placeSequential(6, 6).physCol, placeSequential(6, 6).physRow), (1, 0));
    });
  });

  group('roundTo', () {
    test('按指定精度四舍五入', () {
      expect(roundTo(1.00005, 1e-4), closeTo(1.0001, 1e-9));
      expect(roundTo(-2.55555, 1e-3), closeTo(-2.556, 1e-9));
      expect(roundTo(42, 1), 42);
    });
  });

  group('contentSize', () {
    test('空格子列表返回宽度 0', () {
      final size = contentSize(const [], 6, 18);
      expect(size.width, 0);
      expect(size.height, 6 * 18);
    });

    test('按最大物理列计算总宽', () {
      final placed = placeOnGrid([2, 1, 3], 6);
      final size = contentSize(placed, 6, 18);
      expect(size.width, 3 * 18); // 最大 physCol=2 → 3 列
    });
  });
}
