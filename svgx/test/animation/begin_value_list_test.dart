import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';

// The benchmark corpus is not a package dependency.
// benchmark 语料不是依赖包，只能通过相对路径导入。
// ignore: avoid_relative_lib_imports
import '../../benchmark/bench_app/lib/anim_icons_real.dart';
import 'pixel_test_utils.dart';

Duration sec(num t) => Duration(microseconds: (t * 1000000).round());
List<SmilTimeline> tracks(SvgNode n) => [
  ...n.animations,
  ...n.transformAnimations,
  ...n.colorAnimations,
  ...n.pathAnimations,
  ...n.motionAnimations,
  ...n.listAnimations,
  for (final c in n.children) ...tracks(c),
];
List<SmilAnimation> parse(String body) =>
    tracks(parsePixelDoc('<g>$body</g>').root).cast<SmilAnimation>();
String anim(
  String begin, {
  String id = '',
  String attrs = '',
  num duration = 1,
}) =>
    '<animate id="$id" attributeName="opacity" values="0;10" dur="${duration}s" begin="$begin" $attrs/>';
void main() {
  test('seeded loops keep ticking and follow their periods through one hour', () {
    for (final body in [
      anim('0;b.end', id: 'a') + anim('a.end', id: 'b'),
      anim('1s;a.begin+6s', id: 'a'),
    ]) {
      final doc = parsePixelDoc('<g>$body</g>');
      final all = tracks(doc.root).cast<SmilAnimation>();
      expect(doc.hasIndefiniteLoop, isTrue);
      for (final seconds in [1, 5, 30, 120, 600, 3600]) {
        final t = seconds + .25;
        final phase = all.length == 2 ? t % 2 : (t - 1) % 6;
        final expansion = Stopwatch()..start();
        final sample = all.first.sample(sec(t));
        expansion.stop();
        if (seconds == 3600) {
          debugPrint(
            'hour jump from 600s: ${expansion.elapsedMicroseconds} us',
          );
        }
        expect(sample, phase < 1 ? closeTo(phase * 10, .00001) : isNull);
        expect(
          all.first.sample(sec(t + .25)),
          phase + .25 < 1 ? closeTo((phase + .25) * 10, .00001) : isNull,
        );
        if (all.length == 1) {
          // 6 秒周期大部分时间为空隙；同时检查邻近的下一次活动期。
          final nextStart = 1 + ((seconds - 1) / 6).ceil() * 6;
          expect(all.first.sample(sec(nextStart + .25)), closeTo(2.5, .00001));
          expect(all.first.sample(sec(nextStart + .75)), closeTo(7.5, .00001));
        }
      }
      final watch = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        for (final a in all) {
          a.sample(sec(3600.25));
        }
      }
      debugPrint(
        'hour loop: intervals=${all.map((a) => a.intervals!.length).toList()}, warm us/frame=${watch.elapsedMicroseconds / 10000}',
      );
    }
  });
  test('a causal negative end-offset ring keeps producing intervals', () {
    final doc = parsePixelDoc(
      '<g>${anim('0;b.end-0.2s', id: 'a')}'
      '${anim('a.end+0.2s', id: 'b')}</g>',
    );
    final all = tracks(doc.root).cast<SmilAnimation>();
    expect(doc.hasIndefiniteLoop, isTrue);
    for (final t in [1, 5, 30, 120, 600, 3600]) {
      final phase = (t + .5) % 2;
      expect(all.first.sample(sec(t + .5)), phase < 1 ? 5 : isNull);
    }
  });
  test('3-dots-bounce 1.05 second cycle survives one hour', () {
    final doc = parsePixelDoc(
      '<g>${anim('0;c.end+0.25s', id: 'a', duration: .6)}'
      '${anim('a.begin+0.1s', id: 'b', duration: .6)}'
      '${anim('a.begin+0.2s', id: 'c', duration: .6)}</g>',
    );
    final all = tracks(doc.root).cast<SmilAnimation>();
    expect(doc.hasIndefiniteLoop, isTrue);
    for (final second in [1, 5, 30, 120, 600, 3600]) {
      final phase = (second * 1000000 % 1050000) / 1000000;
      final expansion = Stopwatch()..start();
      final sample = all[0].sample(sec(second));
      expansion.stop();
      if (second == 3600) {
        debugPrint(
          'spinner jump from 600s: ${expansion.elapsedMicroseconds} us',
        );
      }
      expect(sample, phase < .6 ? closeTo(phase / .6 * 10, .0001) : isNull);
      final start = (second / 1.05).floor() * 1.05;
      expect(all[0].sample(sec(start + .3)), closeTo(5, .0001));
      expect(all[1].sample(sec(start + .4)), closeTo(5, .0001));
      expect(all[2].sample(sec(start + .5)), closeTo(5, .0001));
    }
    final watch = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      for (final a in all) {
        a.sample(sec(3600));
      }
    }
    debugPrint(
      'spinner hour: intervals=${all.map((a) => a.intervals!.length).toList()}, warm us/frame=${watch.elapsedMicroseconds / 10000}',
    );
  });
  test('hard cap flags the whole dependency component after hours', () {
    final all = parse(anim('0;a.end', id: 'a') + anim('a.begin+0.1s', id: 'b'));
    expect(all.first.sample(sec(3600.5)), 5);
    expect(all.every((a) => !a.instancesTruncated), isTrue);
    all.first.sample(sec(25000));
    expect(all.every((a) => a.instancesTruncated), isTrue);
    expect(all.first.intervals, hasLength(20000));
    expect(all.every((a) => a.intervals!.length <= 20000), isTrue);
  });
  test('end notification at simultaneous restart is not lost', () {
    final all = parse(
      anim('0;1s', id: 'a') + anim('a.end;indefinite', id: 'b'),
    );
    expect(all[1].sample(sec(1.5)), 5);
    expect(all[1].sample(sec(2.5)), 5);
  });
  test('past intervals are discarded before restart and freeze', () {
    final never = parse(anim('-1s;2s', attrs: 'restart="never"')).single;
    expect(never.sample(sec(2.5)), 5);
    final freeze = parse(anim('-3s;2s', attrs: 'fill="freeze"')).single;
    expect(freeze.sample(sec(0)), isNull);
    expect(freeze.sample(sec(1)), isNull);
    expect(freeze.sample(sec(2.5)), 5);
  });
  test('past restart truncations retract their begin-dependent instances', () {
    final all = parse(
      anim('-0.8s;-0.2s', id: 'a') + anim('a.begin+10s;indefinite', id: 'b'),
    );
    expect(all[0].intervals, hasLength(1));
    expect(all[0].intervals!.single.begin, sec(-.2));
    expect(all[1].intervals, hasLength(1));
    expect(all[1].intervals!.single.begin, sec(9.8));
  });
  test('negative cycle does not spend its interval budget in the past', () {
    final a = parse(anim('0;a.begin-6s', id: 'a')).single;
    expect(a.intervals!.first.begin, Duration.zero);
    expect(a.sample(sec(.5)), 5);
  });
  test('an explicit end entirely before begin creates no interval', () {
    final a = parse(anim('2s;4s', attrs: 'end="1s"')).single;
    expect(a.intervals, isEmpty);
    expect(a.sample(sec(2.5)), isNull);
  });
  for (final dense in [false, true]) {
    test(
      'global work budget bounds ${dense ? "60 dense" : "100 mixed ring"} dependencies',
      () {
        final n = dense ? 60 : 100;
        final body = List.generate(n, (i) {
          final refs = dense
              ? [
                  for (var j = 0; j < n; j++)
                    if (j != i) 'a$j.end${j.isEven ? '-0.3s' : '+0.1s'}',
                ].join(';')
              : 'a${(i + 1) % n}.end-0.3s;a${(i + 7) % n}.begin+0.1s';
          return anim(
            '0;$refs',
            id: 'a$i',
            duration: dense ? 0.5 + i / 100 : 1,
          );
        }).join();
        final watch = Stopwatch()..start();
        final all = parse(body);
        watch.stop();
        debugPrint(
          'pathological dense=$dense: ${watch.elapsedMicroseconds / 1000} ms',
        );
        expect(watch.elapsedMilliseconds, lessThan(2000));
        expect(all.every((a) => a.instancesTruncated), isTrue);
        expect(all.every((a) => a.intervals!.length <= 20000), isTrue);
        expect(
          all.expand((a) => a.intervals!).every((i) => i.end > Duration.zero),
          isTrue,
        );
      },
    );
  }
  test('two intervals remove and freeze', () {
    for (final freeze in [false, true]) {
      final a = parse(anim('0;2s', attrs: freeze ? 'fill="freeze"' : ''))
          .single;
      expect(a.sample(sec(.5)), 5);
      expect(a.sample(sec(1.5)), freeze ? 10 : null);
      expect(a.sample(sec(2.5)), 5);
      expect(a.sample(sec(3.5)), freeze ? 10 : null);
    }
  });
  test('restart always, whenNotActive, never', () {
    for (final mode in ['always', 'whenNotActive', 'never']) {
      final a = parse(anim('0;0.5s;2s', attrs: 'restart="$mode"')).single;
      expect(a.sample(sec(.75)), mode == 'always' ? 2.5 : 7.5);
      expect(a.sample(sec(1.25)), mode == 'always' ? 7.5 : null);
      expect(a.sample(sec(2.5)), mode == 'never' ? null : 5);
    }
  });
  test('seeded mutual end dependencies repeat at hand calculated times', () {
    final a = parse(anim('0;b.end', id: 'a') + anim('a.end+0.2s', id: 'b'));
    // a: [0,1), [2.2,3.2), [4.4,5.4); b: [1.2,2.2), [3.4,4.4).
    expect(a[0].sample(sec(.5)), 5);
    expect(a[1].sample(sec(1.7)), 5);
    expect(a[0].sample(sec(2.7)), 5);
    expect(a[1].sample(sec(3.9)), 5);
    expect(a[0].sample(sec(4.9)), 5);
    expect(a[0].sample(sec(1.1)), isNull);
  });
  test('single syncbase consumes every end of a list target', () {
    final a = parse(anim('0;2s', id: 'a') + anim('a.end+0.2s', id: 'b'));
    expect(a[1].sample(sec(1.7)), 5);
    expect(a[1].sample(sec(3.7)), 5);
    expect(a[1].sample(sec(2.7)), isNull);
  });
  for (final begin in [
    'indefinite;1s',
    'click;id.repeat(2);1s',
    ' 1s ; ; +3s ; ',
  ]) {
    test('list ignores never/event/empty entries: $begin', () {
      final a = parse(anim(begin)).single;
      expect(a.sample(sec(.5)), isNull);
      expect(a.sample(sec(1.5)), 5);
    });
  }
  test('negative begin and syncbase offsets', () {
    final a = parse(anim('-1s;+2s', id: 'a') + anim('a.begin-0.5s;indefinite'));
    expect(a[0].sample(sec(-.5)), isNull);
    expect(a[1].sample(sec(-1)), isNull);
    expect(a[1].sample(sec(2)), 5);
  });
  test('truncated restart end propagates instead of natural end', () {
    final a = parse(anim('0;0.5s', id: 'a') + anim('a.end;indefinite'));
    expect(a[1].sample(sec(.75)), 2.5);
    expect(a[1].sample(sec(1.75)), 2.5);
  });
  test(
    'end, min, max constrain each interval and freeze its terminal value',
    () {
      final a = parse(anim('0;2s', attrs: 'end="0.5s;2.75s" fill="freeze"'))
          .single;
      expect(a.sample(sec(1)), 5);
      expect(a.sample(sec(3)), 7.5);
      final b = parse(anim('0;2s', attrs: 'max="0.25s" fill="freeze"')).single;
      expect(b.sample(sec(1)), 2.5);
      final c = parse(
        anim('0;0.75s;2s', attrs: 'min="1.5s" restart="whenNotActive"'),
      ).single;
      expect(c.sample(sec(1.25)), 10);
      expect(c.sample(sec(2.5)), 5);
    },
  );
  test(
    'lazy expansion passes the former 64-instance boundary under two seconds',
    () {
      final watch = Stopwatch()..start();
      final a = parse(anim('0;a.end', id: 'a')).single;
      expect(a.sample(sec(63.5)), 5);
      expect(a.sample(sec(120.5)), 5);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    },
  );
  test('time horizon does not saturate into a fabricated final begin', () {
    final a = parse(anim('10000001s;2s')).single;
    expect(a.sample(sec(2.5)), 5);
    expect(a.sample(sec(10000000)), isNull);
  });
  test('invalid list items never fabricate a zero begin', () {
    final a = parse(anim('1junk;id.end+garbage;2s')).single;
    expect(a.sample(sec(.5)), isNull);
    expect(a.sample(sec(2.5)), 5);
  });
  test(
    'repeat fractional endpoint and indefinite repeat constrained by max',
    () {
      final a = parse(anim('0;4s', attrs: 'repeatCount="2.5" fill="freeze"'))
          .single;
      expect(a.sample(sec(1.5)), 5);
      expect(a.sample(sec(3)), 5);
      expect(a.sample(sec(4.25)), 2.5);
      final b = parse(
        anim('0;4s', attrs: 'repeatCount="indefinite" max="2s" fill="freeze"'),
      ).single;
      expect(b.sample(sec(3)), 10);
    },
  );
  test('zero cycles settle and causal negative-offset cycles parse under two seconds', () {
    final watch = Stopwatch()..start();
    final zero = parse(anim('0;a.begin', id: 'a')).single;
    expect(zero.intervals, hasLength(1));
    expect(zero.sample(sec(.5)), 5);
    final negative = parse(
      anim('0;b.end-0.2s', id: 'a') + anim('a.end+0.2s', id: 'b'),
    );
    expect(negative[0].intervals!.length, greaterThanOrEqualTo(1));
    expect(negative[0].sample(sec(2.5)), 5);
    expect(negative[1].sample(sec(3.7)), 5);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });
  test('no-list tracks retain legacy timing without interval objects', () {
    final a = parse(anim('click') + anim('a.end', id: 'a'));
    expect(a[0].sample(sec(.5)), 5);
    expect(a[0].intervals, isNull);
    expect(a[1].begin, kSmilNeverBegins);
    expect(a[1].intervals, isNull);
  });
  test(
    'interval accounting includes last accepted end and bounded diagnostics',
    () {
      final doc = parsePixelDoc('<g>${anim('0;2s')}</g>');
      expect(doc.totalDuration, sec(3));
      final a = parse(anim('0;a.end', id: 'a')).single;
      expect(a.sample(sec(120.5)), 5);
      expect(a.instancesTruncated, isFalse);
      expect(a.intervalEnd, greaterThan(sec(120)));
    },
  );
  test('set without duration keeps its value across list instances', () {
    final doc = parsePixelDoc(
      '<rect><set attributeName="opacity" to="0.5" begin="1s;3s"/></rect>',
    );
    final a = tracks(doc.root).single as SmilAnimation;
    expect(a.sample(sec(.5)), isNull);
    expect(a.sample(sec(1.5)), .5);
    expect(a.sample(sec(3.5)), .5);
    expect(doc.totalDuration, sec(3));
    expect(doc.hasIndefiniteLoop, isFalse);
  });
  test('real Iconify seeded cycles still animate beyond first round', () {
    // Select zero-seeded syncbase cycles by SVG semantics, independent of Dart
    // source quoting, corpus indices and generated IDs. The official corpus
    // retains the rotate and opacity cycles whose later-round phases we check.
    // 按 SVG 的零时刻种子 + syncbase 循环语义选择，不依赖 Dart 源码引号、
    // 语料索引或生成的 ID；官方语料仍保留此处验证后续轮次相位的旋转和透明度循环。
    final svgs = animIconsReal.where((s) => s.contains('begin="0;')).toList();
    expect(svgs.length, greaterThanOrEqualTo(2));
    for (final svg in svgs) {
      final doc = parseAnimatedSvgDocument(svg);
      for (final t in [.5, 1.5, 3.5, 6.5]) {
        paintAt(doc, sec(t));
      }
      final all = tracks(doc.root);
      final first = all.firstWhere((a) => a.beginSpec.entries != null);
      if (first is SmilTransformAnimation) {
        expect(first.sample(sec(3.5))![0], closeTo(-45, .0001));
        expect(first.sample(sec(6.5))![0], closeTo(-45, .0001));
      } else {
        final opacity = first as SmilAnimation;
        expect(opacity.sample(sec(3.5)), closeTo(.5, .0001));
        expect(opacity.sample(sec(5.5)), closeTo(.75, .0001));
      }
    }
  });
}
