import 'package:flutter_test/flutter_test.dart';
import 'package:roadsman/roadsman.dart';

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
      // Mirrors the round sequence from casino fixtures/baccarat-regular.json:
      // B, B(banker pair), P, T, P(player pair), B(natural), B, B, P, P, T, B
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

      // Column structure: [B,B] [P,P] [B,B,B] [P,P] [B]
      expect(data.columns, [2, 2, 3, 2, 1]);
      expect(data.leadingTies, 0);

      // Round 4 (T) immediately follows round 3 (P), so it's added to the tieCount of the
      // current column (column 2, which at this point only has round 3's cell).
      final col1FirstCell = data.cells.firstWhere((c) => c.col == 1 && c.row == 0);
      expect(col1FirstCell.tieCount, 1);

      // Round 11 (T) immediately follows round 10 (P), so it's added to the tieCount of the
      // last cell in column 4 (index 3).
      final col3LastCell = data.cells.lastWhere((c) => c.col == 3);
      expect(col3LastCell.tieCount, 1);

      // Round 2's banker-pair marker is kept on the corresponding cell.
      final secondBankerCell = data.cells.firstWhere((c) => c.col == 0 && c.row == 1);
      expect(secondBankerCell.bankerPair, isTrue);

      // Round 6's natural marker is kept.
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
