import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:countman/countman.dart';

import 'support/manual_clock.dart';

// CountdownFormat.template：创建时解析一次，逐 tick 只做拼接。

/// 以 Duration 构造 TimeParts，省去手写换算。
TimeParts _parts(Duration d) => TimeParts.of(d);

void main() {
  const sample = Duration(days: 1, hours: 2, minutes: 3, seconds: 4, milliseconds: 56);

  group('CountdownFormat.template 记号', () {
    test('典型模板：{d}天 {HH}:{mm}:{ss}', () {
      final f = CountdownFormat.template('{d}天 {HH}:{mm}:{ss}');
      expect(f(_parts(sample)), '1天 02:03:04');
    });

    test('{d} 不补零；{H}/{HH} 为 0–23 的小时，不补零/补零', () {
      expect(CountdownFormat.template('{d}')(_parts(const Duration(days: 12))), '12');
      expect(CountdownFormat.template('{H}')(_parts(const Duration(hours: 5))), '5');
      expect(CountdownFormat.template('{HH}')(_parts(const Duration(hours: 5))), '05');
      // 超过一天后 {H} 仍是 0–23。
      expect(CountdownFormat.template('{H}')(_parts(const Duration(hours: 26))), '2');
    });

    test('{TH} 总小时、{TM} 总分钟可超过进制上限', () {
      final p = _parts(sample); // 1 天 2 小时 3 分
      expect(CountdownFormat.template('{TH}')(p), '26');
      expect(CountdownFormat.template('{TM}')(p), '1563');
      expect(CountdownFormat.template('{TH}h{mm}m')(p), '26h03m');
    });

    test('{m}/{mm} 与 {s}/{ss}', () {
      final p = _parts(const Duration(minutes: 7, seconds: 5));
      expect(CountdownFormat.template('{m}:{s}')(p), '7:5');
      expect(CountdownFormat.template('{mm}:{ss}')(p), '07:05');
    });

    test('{S} 十分之一秒、{SSS} 毫秒（补零到三位）', () {
      final p = _parts(const Duration(seconds: 1, milliseconds: 350));
      expect(CountdownFormat.template('{s}.{S}')(p), '1.3');
      expect(CountdownFormat.template('{ss}.{SSS}')(p), '01.350');
      expect(CountdownFormat.template('{SSS}')(_parts(const Duration(milliseconds: 7))), '007');
    });

    test('相邻记号、重复记号', () {
      final p = _parts(const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(CountdownFormat.template('{HH}{mm}{ss}')(p), '010203');
      expect(CountdownFormat.template('{s}-{s}-{ss}')(p), '3-3-03');
    });

    test('其他文字原样输出，包括中文、符号与空白', () {
      final f = CountdownFormat.template('剩余 {m} 分 {s} 秒！ ({TM} min)');
      expect(f(_parts(const Duration(minutes: 5, seconds: 9))), '剩余 5 分 9 秒！ (5 min)');
    });

    test('空模板与纯文字模板', () {
      expect(CountdownFormat.template('')(_parts(sample)), '');
      expect(CountdownFormat.template('已结束')(_parts(Duration.zero)), '已结束');
    });
  });

  group('未知与不完整的记号原样保留', () {
    test('未知记号、大小写不符、空记号', () {
      final p = _parts(const Duration(minutes: 1, seconds: 2));
      expect(CountdownFormat.template('{x}')(p), '{x}');
      expect(CountdownFormat.template('{hh}:{ss}')(p), '{hh}:02'); // 小写 hh 不是记号
      expect(CountdownFormat.template('{}')(p), '{}');
      expect(CountdownFormat.template('{ss }')(p), '{ss }');
      expect(CountdownFormat.template('{mmm}')(p), '{mmm}');
    });

    test('没有闭合的 { 与孤立的 }', () {
      final p = _parts(const Duration(seconds: 9));
      expect(CountdownFormat.template('{ss')(p), '{ss');
      expect(CountdownFormat.template('ss}')(p), 'ss}');
      expect(CountdownFormat.template('{{ss}}')(p), '{09}');
      expect(CountdownFormat.template('a{b{ss}')(p), 'a{b09');
    });
  });

  group('只解析一次', () {
    test('创建时解析一次，同一 formatter 反复调用不再解析', () {
      final before = CountdownFormat.debugTemplateParseCount;
      final f = CountdownFormat.template('{d}天 {HH}:{mm}:{ss}');
      expect(CountdownFormat.debugTemplateParseCount, before + 1);
      for (var i = 0; i < 5; i++) {
        f(_parts(Duration(seconds: i)));
      }
      expect(CountdownFormat.debugTemplateParseCount, before + 1);
    });

    test('同一个 formatter 对不同 TimeParts 给出各自的结果', () {
      final f = CountdownFormat.template('{mm}:{ss}');
      expect(f(_parts(const Duration(seconds: 61))), '01:01');
      expect(f(_parts(const Duration(seconds: 5))), '00:05');
      expect(f(_parts(const Duration(minutes: 90))), '30:00');
    });

    test('formatter 读取的是传入 TimeParts 的当前值（就地复用也正确）', () {
      final f = CountdownFormat.template('{s}');
      final shared = TimeParts.zero();
      shared.setMicros(const Duration(seconds: 3).inMicroseconds, null);
      expect(f(shared), '3');
      shared.setMicros(const Duration(seconds: 4).inMicroseconds, null);
      expect(f(shared), '4');
    });
  });

  group('组件集成', () {
    testWidgets('TextCountdown 使用模板格式化', (t) async {
      installManualClock();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TextCountdown(
            to: const Duration(days: 2, hours: 3, minutes: 4, seconds: 5),
            formatter: CountdownFormat.template('{d}天 {HH}:{mm}:{ss}'),
          ),
        ),
      ));
      await t.pump();
      expect(find.text('2天 03:04:05'), findsOneWidget);
      Countman.destroy();
    });
  });
}
