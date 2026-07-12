import 'package:flutter/material.dart';
import 'package:countman/countman.dart';

/// Demo page covering every countdown widget and its full API surface:
/// [CountdownBuilder], [CountdownText], [CountdownCard], [CountdownRing],
/// [Countdown] (custom groups), [CountdownController], [CountdownFormat].
class CountdownDemoPage extends StatefulWidget {
  const CountdownDemoPage({super.key});
  @override
  State<CountdownDemoPage> createState() => _CountdownDemoPageState();
}

const _kShort = Duration(seconds: 8); // shows msTenths / onComplete quickly
const _kMed = Duration(seconds: 60);
const _kHour = Duration(hours: 2, minutes: 15, seconds: 30);

class _CountdownDemoPageState extends State<CountdownDemoPage> {
  int _seed = 0;
  final _fastGroup = Countdown(name: 'demo-fast', interval: 100);

  @override
  void initState() {
    super.initState();
    Countman.use(_fastGroup);
  }

  void _restart() => setState(() => _seed++);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final sections = <Widget>[
      _Section('CountdownBuilder — basic', [
        _Tile('builder: auto format', CountdownBuilder(
          duration: _kMed,
          builder: (_, r, __) => Text(CountdownFormat.auto(r), style: _ts),
        )),
        _Tile('builder: progress bar', CountdownBuilder(
          duration: _kMed,
          builder: (_, r, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            Text(CountdownFormat.ms(r), style: _ts),
            const SizedBox(height: 4),
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(
                value: r.inMilliseconds / _kMed.inMilliseconds,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ]),
        )),
      ]),
      _Section('CountdownBuilder — onComplete / plugin (custom group)', [
        _Tile('onComplete (8s)', _DoneBadge(builder: (onComplete) => CountdownBuilder(
          duration: _kShort,
          onComplete: onComplete,
          builder: (_, r, __) => Text(CountdownFormat.msTenths(r), style: _ts),
        ))),
        _Tile('plugin: Countdown(interval:100)', CountdownBuilder(
          duration: _kShort,
          plugin: _fastGroup,
          builder: (_, r, __) => Text(CountdownFormat.msTenths(r), style: _ts),
        )),
      ]),
      _Section('CountdownBuilder — controller', [
        _Tile('pause / resume / reset / cancel', _ControllerDemo(
          builder: (ctrl) => CountdownBuilder(
            duration: _kMed,
            controller: ctrl,
            builder: (_, r, __) => Text(CountdownFormat.ms(r), style: _ts),
          ),
        )),
      ]),
      _Section("CountdownText — `to` input types", [
        _Tile('Duration', CountdownText(to: _kMed, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('DateTime', CountdownText(to: now.add(_kMed), style: CountdownTextStyle(textStyle: _ts))),
        _Tile('int (ms epoch)', CountdownText(
            to: now.add(_kMed).millisecondsSinceEpoch, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('String (ISO-8601)', CountdownText(
            to: now.add(_kMed).toIso8601String(), style: CountdownTextStyle(textStyle: _ts))),
      ]),
      _Section('CountdownText — formatters', [
        _Tile('hms', CountdownText(to: _kHour, formatter: CountdownFormat.hms, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('ms', CountdownText(to: _kMed, formatter: CountdownFormat.ms, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('msTenths', CountdownText(to: _kShort, formatter: CountdownFormat.msTenths, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('auto (≥1h/<10s/else)', CountdownText(to: _kHour, formatter: CountdownFormat.auto, style: CountdownTextStyle(textStyle: _ts))),
        _Tile('custom formatter', CountdownText(
          to: _kMed,
          formatter: (r) => '剩余 ${r.inSeconds} 秒',
          style: CountdownTextStyle(textStyle: _ts),
        )),
      ]),
      _Section('CountdownText — style / controller / onComplete', [
        _Tile('style + textAlign', CountdownText(
          to: _kMed,
          style: const CountdownTextStyle(
            textAlign: TextAlign.center,
            textStyle: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.amber),
          ),
        )),
        _Tile('controller', _ControllerDemo(
          builder: (ctrl) => CountdownText(to: _kMed, controller: ctrl, style: CountdownTextStyle(textStyle: _ts)),
        )),
        _Tile('onComplete (8s)', _DoneBadge(builder: (onComplete) =>
            CountdownText(to: _kShort, onComplete: onComplete, style: CountdownTextStyle(textStyle: _ts)))),
      ]),
      _Section('CountdownCard — layout options', [
        _Tile('default (unit cards)', CountdownCard(to: _kMed), size: const Size(200, 110)),
        _Tile('splitDigits: true', CountdownCard(to: _kMed, style: const CountdownCardStyle(splitDigits: true)), size: const Size(220, 110)),
        _Tile('showHours: true (forced)', CountdownCard(to: _kMed, showHours: true), size: const Size(260, 110)),
        _Tile('showHours: false (forced)', CountdownCard(to: _kHour, showHours: false), size: const Size(200, 110)),
        _Tile('labels: 时/分/秒', CountdownCard(to: _kHour, labels: const ['时', '分', '秒']), size: const Size(260, 110)),
        _Tile('labels: null', CountdownCard(to: _kMed, labels: null), size: const Size(180, 90)),
        _Tile('separator "·" / unitGap 16', CountdownCard(
            to: _kMed, separator: '·', style: const CountdownCardStyle(unitGap: 16)), size: const Size(220, 110)),
        _Tile('digitGap 10 (splitDigits)', CountdownCard(
            to: _kMed, style: const CountdownCardStyle(splitDigits: true, digitGap: 10)), size: const Size(240, 110)),
      ]),
      _Section('CountdownCard — style', [
        _Tile('cardColor / textStyle / labelStyle', CountdownCard(
          to: _kMed,
          style: const CountdownCardStyle(
            cardColor: Color(0xFF1A237E),
            textStyle: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
            labelStyle: TextStyle(fontSize: 10, color: Colors.cyanAccent),
          ),
        ), size: const Size(220, 120)),
        _Tile('separatorStyle', CountdownCard(
          to: _kMed,
          style: const CountdownCardStyle(
            separatorStyle: TextStyle(fontSize: 28, color: Colors.redAccent),
          ),
        ), size: const Size(200, 110)),
        _Tile('cardWidth/Height 40x56, duration 800ms', CountdownCard(
          to: _kMed,
          style: const CountdownCardStyle(cardWidth: 40, cardHeight: 56),
          duration: const Duration(milliseconds: 800),
        ), size: const Size(180, 100)),
        _Tile('repaintBoundary: false', CountdownCard(
            to: _kMed, repaintBoundary: false), size: const Size(200, 110)),
        _Tile('controller', _ControllerDemo(
          builder: (ctrl) => CountdownCard(to: _kMed, controller: ctrl),
          size: const Size(220, 130),
        )),
      ]),
      _Section('CountdownRing', [
        _Tile('default', CountdownRing(to: _kMed), size: const Size(120, 120)),
        _Tile('center: CountdownText', CountdownRing(
          to: _kMed,
          center: CountdownText(to: _kMed, style: CountdownTextStyle(textStyle: _ts)),
        ), size: const Size(120, 120)),
        _Tile('clockwise: false', CountdownRing(to: _kMed, style: const CountdownRingStyle(clockwise: false)), size: const Size(120, 120)),
        _Tile('size/strokeWidth/colors', CountdownRing(
          to: _kMed,
          style: const CountdownRingStyle(
            size: 100,
            strokeWidth: 14,
            color: Colors.deepOrangeAccent,
            trackColor: Color(0xFF3A3A3A),
          ),
        ), size: const Size(130, 130)),
        _Tile('repaintBoundary: false', CountdownRing(
            to: _kMed, repaintBoundary: false), size: const Size(120, 120)),
        _Tile('onComplete (8s) + center', _DoneBadge(builder: (onComplete) => CountdownRing(
          to: _kShort,
          onComplete: onComplete,
          center: CountdownText(to: _kShort, formatter: CountdownFormat.msTenths, style: CountdownTextStyle(textStyle: _ts)),
        )), size: const Size(120, 120)),
        _Tile('controller', _ControllerDemo(
          builder: (ctrl) => CountdownRing(
            to: _kMed,
            controller: ctrl,
            center: CountdownText(to: _kMed, style: CountdownTextStyle(textStyle: _ts)),
          ),
          size: const Size(130, 160),
        )),
      ]),
      _Section('Stress — 12 concurrent (shared defaultCountdown group)', [
        for (var i = 1; i <= 12; i++)
          _Tile('#$i (${_kMed.inSeconds - i}s)', CountdownText(
            to: Duration(seconds: _kMed.inSeconds - i),
            style: CountdownTextStyle(textStyle: _ts),
          )),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Countdown Demo')),
      body: KeyedSubtree(
        key: ValueKey(_seed),
        child: ListView(
          padding: const EdgeInsets.only(bottom: 80),
          children: sections,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _restart,
        icon: const Icon(Icons.refresh),
        label: const Text('restart all'),
      ),
    );
  }
}

const _ts = TextStyle(fontSize: 14, fontWeight: FontWeight.bold);

// ── helpers ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(this.title, this.items);
  final String title;
  final List<_Tile> items;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 0.6)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: items),
          ),
        ],
      );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.child, {this.size = const Size(150, 70)});
  final String label;
  final Widget child;
  final Size size;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9, color: Theme.of(context).colorScheme.outline)),
            ),
            Expanded(child: Center(child: child)),
          ]),
        ),
      );
}

/// Wraps [builder]'s widget and shows a check badge once `onComplete` fires.
class _DoneBadge extends StatefulWidget {
  const _DoneBadge({required this.builder});
  final Widget Function(void Function() onComplete) builder;
  @override
  State<_DoneBadge> createState() => _DoneBadgeState();
}

class _DoneBadgeState extends State<_DoneBadge> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
        widget.builder(() => setState(() => _done = true)),
        if (_done)
          const Positioned(
            right: 0,
            top: 0,
            child: Icon(Icons.check_circle, size: 14, color: Colors.greenAccent),
          ),
      ]);
}

/// Wraps [builder]'s widget with pause/resume/reset/cancel buttons bound to
/// a fresh [CountdownController].
class _ControllerDemo extends StatefulWidget {
  const _ControllerDemo({required this.builder, this.size = const Size(150, 100)});
  final Widget Function(CountdownController ctrl) builder;
  final Size size;
  @override
  State<_ControllerDemo> createState() => _ControllerDemoState();
}

class _ControllerDemoState extends State<_ControllerDemo> {
  final _ctrl = CountdownController();
  String _status = 'running';

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.size.width,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          widget.builder(_ctrl),
          const SizedBox(height: 4),
          Wrap(alignment: WrapAlignment.center, spacing: 2, children: [
            _btn('pause', () { _ctrl.pause(); setState(() => _status = 'paused'); }),
            _btn('resume', () { _ctrl.resume(); setState(() => _status = 'running'); }),
            _btn('reset', () { _ctrl.reset(); setState(() => _status = 'reset'); }),
            _btn('cancel', () { _ctrl.cancel(); setState(() => _status = 'cancelled'); }),
          ]),
          Text(_status, style: const TextStyle(fontSize: 8, color: Colors.grey)),
        ]),
      );

  Widget _btn(String label, VoidCallback onTap) => TextButton(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 9)),
      );
}
