import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
import 'digit_test_page.dart';
import 'perf_page.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Countman Demo',
        theme: ThemeData.dark(useMaterial3: true),
        initialRoute: '/digit',
        routes: {
          '/':      (_) => const DemoPage(),
          '/perf':  (_) => const PerfPage(),
          '/digit': (_) => const DigitTestPage(),
        },
      );
}

// ── page ──────────────────────────────────────────────────────────────────────

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});
  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _ctrl = CounterController(initialValue: 0);
  double _t = 0;

  void _toggle() {
    setState(() => _t = _t == 0 ? 999999999 : 0);
    _ctrl.animateTo(_t);
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final ts = const TextStyle(fontSize: 11, fontWeight: FontWeight.bold);

    final sections = <_Section>[
      _Section('CountupPlus — Transitions', [
        _c('roll',       CountupPlus(value: _t, textStyle: ts, duration: 10000.ms)),
        _c('fade',       CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.fade)),
        _c('scale',      CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.scale)),
        _c('fadeScale',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.fadeScale)),
        _c('rotate',     CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.rotate)),
        _c('flip',       CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.flip)),
        _c('blur',       CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, transitionType: CounterTransitionType.blur)),
      ]),
      _Section('CountupPlus — Flip Direction', [
        _c('↑ up',    CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, flipDirection: AxisDirection.up)),
        _c('↓ down',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, flipDirection: AxisDirection.down)),
        _c('← left',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, flipDirection: AxisDirection.left)),
        _c('→ right', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, flipDirection: AxisDirection.right)),
      ]),
      _Section('CountupPlus — Stagger', [
        _c('rightToLeft (ones先)', CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, staggerDelay: 80.ms, staggerDirection: StaggerDirection.rightToLeft)),
        _c('leftToRight (高位先)', CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, staggerDelay: 80.ms, staggerDirection: StaggerDirection.leftToRight)),
      ]),
      _Section('CountupPlus — Curve & Duration', [
        _c('easeOut 600ms',     CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,  curve: Curves.easeOut)),
        _c('easeInOut 1200ms',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, curve: Curves.easeInOut)),
        _c('bounceOut 1500ms',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, curve: Curves.bounceOut)),
        _c('elasticOut 1500ms', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, curve: Curves.elasticOut)),
        _c('speedMultiplier 2×',CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, speedMultiplier: 2.0)),
        _c('startDelay 600ms',  CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,  startDelay: 10000.ms)),
        _c('reverseCurve easeIn', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            curve: Curves.easeOut, reverseCurve: Curves.easeIn, reverseDuration: 10000.ms)),
      ]),
      _Section('CountupPlus — Format', [
        _c('fractionDigits: 2', CountupPlus(value: _t / 100, textStyle: ts,
            duration: 10000.ms, fractionDigits: 2, decimalSeparator: '.')),
        _c('thousandSeparator', CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, thousandSeparator: ',')),
        _c('wholeDigits: 6',    CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, wholeDigits: 6)),
        _c('hideLeadingZeroes: false', CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, wholeDigits: 6, hideLeadingZeroes: false)),
        _c('compact K/M/B',     CountupPlus(value: _t * 1000, textStyle: ts,
            duration: 10000.ms, compactNotation: true)),
        _c('compact fraction:2',CountupPlus(value: _t * 1000, textStyle: ts,
            duration: 10000.ms, compactNotation: true, compactFractionDigits: 2)),
        _c('custom abbr 千/万',  CountupPlus(value: _t * 1000, textStyle: ts,
            duration: 10000.ms, compactNotation: true,
            compactAbbreviations: {1e3: '千', 1e6: '百万'})),
        _c('minValue/maxValue', CountupPlus(value: _t, textStyle: ts,
            duration: 10000.ms, minValue: 5000, maxValue: 10000)),
      ]),
      _Section('CountupPlus — Prefix / Suffix / Sign', [
        _c('prefix ¥ suffix 元',CountupPlus(value: _t, textStyle: ts, duration: 10000.ms, prefix: '¥', suffix: '元')),
        _c('infix (after sign)',CountupPlus(value: -_t, textStyle: ts, duration: 10000.ms, infix: r'$')),
        _c('showPositiveSign',  CountupPlus(value: _t, duration: 10000.ms, showPositiveSign: true,
            textStyle: ts.copyWith(color: Colors.greenAccent))),
        _c('prefixWidget',      CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            prefixWidget: const Icon(Icons.currency_yen, size: 20, color: Colors.amber))),
        _c('suffixWidget',      CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            suffixWidget: const Text(' pt', style: TextStyle(fontSize: 12, color: Colors.grey)))),
        _c('separatorStyle',    CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            thousandSeparator: ',',
            separatorStyle: const TextStyle(fontSize: 16, color: Colors.grey))),
      ]),
      _Section('CountupPlus — Color', [
        _c('increasingColor ↑', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            increasingColor: Colors.greenAccent, decreasingColor: Colors.redAccent)),
        _c('decreasingColor ↓', CountupPlus(
            value: _t == 0 ? 999999999 : 0,
            initialValue: _t == 9999 ? 9999 : 100,
            textStyle: ts, duration: 10000.ms,
            increasingColor: Colors.greenAccent, decreasingColor: Colors.redAccent)),
      ]),
      _Section('CountupPlus — Custom Builders', [
        _c('digitBuilder rainbow', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            digitBuilder: (_, digit, style) {
              const c = [Colors.red, Colors.orange, Colors.yellow, Colors.green,
                Colors.blue, Colors.indigo, Colors.purple, Colors.pink, Colors.teal, Colors.cyan];
              return Text('$digit', textAlign: TextAlign.center,
                  style: style.copyWith(color: c[digit % c.length]));
            })),
        _c('digitTransitionBuilder', CountupPlus(value: _t, textStyle: ts, duration: 10000.ms,
            digitTransitionBuilder: (_, cur, nxt, p, sz) => Stack(alignment: Alignment.center, children: [
              Transform.scale(scale: 1 - p, child: Opacity(opacity: 1 - p, child: cur)),
              Transform.scale(scale: p,     child: Opacity(opacity: p,     child: nxt)),
            ]))),
        _c('digitWrapperBuilder', CountupPlus(value: _t, duration: 10000.ms,
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            digitWrapperBuilder: (_, idx, child) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(3)),
              child: child))),
      ]),
      _Section('CountupPlus — Numeral Systems', [
        _c('latin',        CountupPlus(value: _t % 1000, textStyle: ts, duration: 10000.ms, numeralSystem: NumeralSystem.latin)),
        _c('easternArabic',CountupPlus(value: _t % 1000, textStyle: ts, duration: 10000.ms, numeralSystem: NumeralSystem.easternArabic)),
        _c('persian',      CountupPlus(value: _t % 1000, textStyle: ts, duration: 10000.ms, numeralSystem: NumeralSystem.persian)),
        _c('devanagari',   CountupPlus(value: _t % 1000, textStyle: ts, duration: 10000.ms, numeralSystem: NumeralSystem.devanagari)),
        _c('bengali',      CountupPlus(value: _t % 1000, textStyle: ts, duration: 10000.ms, numeralSystem: NumeralSystem.bengali)),
        _c('numeralMapper 罗马', CountupPlus(value: _t % 10, textStyle: ts, duration: 10000.ms,
            numeralMapper: (d) => ['Ⅰ','Ⅱ','Ⅲ','Ⅳ','Ⅴ','Ⅵ','Ⅶ','Ⅷ','Ⅸ','Ⅹ'][d])),
      ]),
      _Section('CountupPlus — Locale Factories', [
        _c('USD',CountupPlus.usd(value: _t, textStyle: ts, duration: 10000.ms)),
        _c('CNY',CountupPlus.cny(value: _t, textStyle: ts, duration: 10000.ms)),
        _c('INR',CountupPlus.inr(value: _t * 10, textStyle: ts, duration: 10000.ms)),
      ]),
      _Section('CountupPlus — Controller', [
        _c('CounterController', CountupPlus(controller: _ctrl,
            thousandSeparator: ',', textStyle: ts, duration: 10000.ms)),
      ]),
      _Section('CountupText', [
        _c('default',           CountupText(to: _t, duration: 10000.ms, style: ts)),
        _c('prefix/suffix',     CountupText(to: _t, prefix: '¥ ', suffix: '元', style: ts, duration: 10000.ms)),
        _c('prefixWidget',      CountupText(to: _t, prefixWidget: const Icon(Icons.star, color: Colors.amber, size: 22),
            suffix: ' pts', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), duration: 10000.ms)),
        _c('formatter 千分位',  CountupText(to: _t, duration: 10000.ms, style: ts,
            formatter: (v) { final s=v.toInt().toString(); final b=StringBuffer();
              for(var i=0;i<s.length;i++){if(i>0&&(s.length-i)%3==0)b.write(',');b.write(s[i]);}
              return b.toString(); })),
        _c('bounceOut',         CountupText(to: _t, curve: Curves.bounceOut, duration: 10000.ms, style: ts)),
        _c('elasticOut',        CountupText(to: _t, curve: Curves.elasticOut, duration: 10000.ms, style: ts)),
        _c('from: 5000',        CountupText(from: 5000, to: _t, duration: 10000.ms, style: ts)),
        _c('duration 300ms',    CountupText(to: _t, duration: 300.ms, style: ts)),
      ]),
      _Section('CountupBuilder', [
        _c('color by progress', CountupBuilder(to: _t, duration: 10000.ms,
            builder: (_, v) { final t=(v/_t).clamp(0.0,1.0); return Text(v.toInt().toString(),
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color.lerp(Colors.red,Colors.green,t))); })),
        _c('decimal .2f',       CountupBuilder(to: _t, duration: 10000.ms,
            builder: (_, v) => Text(v.toStringAsFixed(2),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
        _c('progress bar',      CountupBuilder(to: _t, duration: 10000.ms,
            builder: (_, v) => Column(mainAxisSize: MainAxisSize.min, children: [
              Text(v.toInt().toString(), style: ts),
              const SizedBox(height: 2),
              LinearProgressIndicator(value: (v/_t).clamp(0.0,1.0),
                  minHeight: 3, borderRadius: BorderRadius.circular(2)),
            ]))),
      ]),
      _Section('CountupOdometer', [
        _c('default',       CountupOdometer(to: _t, duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts)),
        _c('prefix ¥',      CountupOdometer(to: _t, prefix: '¥', duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts)),
        _c('suffix 元',     CountupOdometer(to: _t, suffix: '元', duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts)),
        _c('prefixWidget',  CountupOdometer(to: _t, duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts,
            prefixWidget: const Icon(Icons.monetization_on, size: 20, color: Colors.amber))),
        _c('groupSeparator',CountupOdometer(to: _t, duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts,
            groupSeparator: Text(',', style: ts))),
        _c('bounceOut',     CountupOdometer(to: _t, curve: Curves.bounceOut, duration: 10000.ms, letterWidth: 20, verticalOffset: 24, numberTextStyle: ts)),
        _c('递减无补零',     CountupOdometer(from: _t==0?999999999:0, to: _t==0?999999999:0,
            duration: 10000.ms, letterWidth: 20, verticalOffset: 24,
            numberTextStyle: ts.copyWith(color: Colors.redAccent))),
      ]),
      _Section('Stress — 20 并发 (shared ticker)', [
        for (var i = 1; i <= 20; i++)
          _c('#$i', CountupPlus(
              value: _t * i / 20,
              duration: Duration(milliseconds: 400 + i * 40),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              transitionType: CounterTransitionType.values[i % CounterTransitionType.values.length])),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Countman Demo')),
      body: CustomScrollView(
        slivers: [
          for (final s in sections) ...[
            SliverToBoxAdapter(child: _SectionHeader(s.title)),
            SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _DemoCard(item: s.items[i]),
                childCount: s.items.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisExtent: 32,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggle,
        icon: const Icon(Icons.refresh),
        label: Text('→ ${_t == 0 ? '999,999,999' : '0'}'),
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

class _Section { const _Section(this.title, this.items); final String title; final List<_Item> items; }
class _Item    { const _Item(this.label, this.child);    final String label; final Widget child; }

_Item _c(String label, Widget child) => _Item(label, child);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Text(title,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.8)),
      );
}

class _DemoCard extends StatelessWidget {
  const _DemoCard({required this.item});
  final _Item item;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Row(children: [
          const SizedBox(width: 8),
          Expanded(
            child: Text(item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
          ),
          Expanded(flex: 2, child: Center(child: item.child)),
          const SizedBox(width: 8),
        ]),
      );
}

extension on int { Duration get ms => Duration(milliseconds: this); }



