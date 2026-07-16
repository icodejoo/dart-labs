import 'package:flutter_test/flutter_test.dart';
import 'package:roadmap/roadmap.dart';

RawResult _r(
  int no,
  String winner, {
  bool bankerPair = false,
  bool playerPair = false,
  bool? natural,
}) => RawResult(no: no, winner: winner, bankerPair: bankerPair, playerPair: playerPair, natural: natural);

void main() {
  group('buildBigRoad', () {
    test('归并连续同一赢家为一列，和局累加到当前格 tieCount', () {
      // 对应 casino fixtures/baccarat-regular.json 的开局序列：
      // B, B(庄对), P, T, P(闲对), B(例牌), B, B, P, P, T, B
      final results = [
        _r(1, 'B'),
        _r(2, 'B', bankerPair: true),
        _r(3, 'P'),
        _r(4, 'T'),
        _r(5, 'P', playerPair: true),
        _r(6, 'B', natural: true),
        _r(7, 'B'),
        _r(8, 'B'),
        _r(9, 'P'),
        _r(10, 'P'),
        _r(11, 'T'),
        _r(12, 'B'),
      ];

      final data = buildBigRoad(results);

      // 列结构：[B,B] [P,P] [B,B,B] [P,P] [B]
      expect(data.columns, [2, 2, 3, 2, 1]);
      expect(data.leadingTies, 0);

      // 局 4（T）紧跟局 3（P）之后，累加到当前列（第 2 列，此时只有局 3 一格）的 tieCount。
      final col1FirstCell = data.cells.firstWhere((c) => c.col == 1 && c.row == 0);
      expect(col1FirstCell.tieCount, 1);

      // 局 11（T）紧跟局 10（P）之后，累加到第 4 列（索引 3）末格的 tieCount。
      final col3LastCell = data.cells.lastWhere((c) => c.col == 3);
      expect(col3LastCell.tieCount, 1);

      // 局 2 的庄对标记保留在对应格子上。
      final secondBankerCell = data.cells.firstWhere((c) => c.col == 0 && c.row == 1);
      expect(secondBankerCell.bankerPair, isTrue);

      // 局 6 的例牌标记保留。
      final naturalCell = data.cells.firstWhere((c) => c.resultNo == 6);
      expect(naturalCell.natural, isTrue);
    });

    test('开局即和局时累加到 leadingTies，不产生格子', () {
      final results = [_r(1, 'T'), _r(2, 'T'), _r(3, 'T'), _r(4, 'B')];
      final data = buildBigRoad(results);

      expect(data.leadingTies, 3);
      expect(data.cells, hasLength(1));
      expect(data.cells.first.tieCount, 3);
      expect(data.columns, [1]);
    });

    test('结果为空时返回空数据', () {
      final data = buildBigRoad(const []);
      expect(data.cells, isEmpty);
      expect(data.columns, isEmpty);
      expect(data.leadingTies, 0);
    });
  });
}
