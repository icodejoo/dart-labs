// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova_example/main_coverage_api.dart' as c;
import 'package:mova_example/verify_auto/s00e_contract.dart' as contract;
import 's00d_widgets_test.dart' as d;

void main() {
  test('contract receipt producer is explicit about an older product snapshot', () async {
    c.records.clear(); await contract.run();
    final rows = c.records.where((r) => r['kind'] == 'CHECK').toList();
    expect(rows.map((r) => r['id']).toSet(), contract.ids.toSet());
    final unavailable = rows.every((r) => (r['numbers'] as Map)['apiUnavailable'] == true);
    for (final row in rows) {
      print('MATRIX_RECORD ${jsonEncode(row)}');
      expect(row['numbers'], isA<Map>());
      expect(row['pass'], unavailable ? isNull : isTrue, reason: '${row['id']}');
    }
  });
  testWidgets('new contract default UI respects probe optout and terminal error copy', (t) async {
    final available = contract.read(const MovaAbrOpts(), 'probeVariants') != null;
    if (!available) {
      for (final id in ['CONTRACT.probe.uiOff','CONTRACT.error.overlay.nonterminal','CONTRACT.error.overlay.terminal']) {
        print('MATRIX_RECORD ${jsonEncode({'kind':'CHECK','id':id,'numbers':{'apiUnavailable':true},'pass':null})}');
      }
      return;
    }
    final abr = Function.apply(MovaAbrOpts.new, [], {#probeVariants:false}) as MovaAbrOpts;
    final strings = Function.apply(MovaStrs.new, [], {#playbackError:'S00E friendly error'}) as MovaStrs;
    final fetch = contract.Fetch(), k = contract.Kernel();
    final a = (await t.runAsync(() async => Mova(kernel:k,fetcher:fetch,options:MovaOpts(abr:abr,strings:strings))))!;
    try {
      await t.pumpWidget(MaterialApp(home:MovaView(source:const MovaSource('https://s00e.invalid/master.m3u8'),
        movaFactory:(_) => a)));
      await d.drain(t); k.land(); await d.drain(t);
      final requests = fetch.requests.length, qualities = a.state.qualities.length;
      await a.loadQualities(); await d.drain(t);
      d.measured('CONTRACT.probe.uiOff',[requests,qualities,a.state.qualities.isNotEmpty],[0,0,true]);
      k.output.add(const MovaLogLine(prefix:'vd',level:'error',text:'S00E raw diagnostic'));
      k.emitError('S00E raw diagnostic'); await d.drain(t);
      d.measured('CONTRACT.error.overlay.nonterminal',[a.state.error == null,
        find.text('S00E friendly error').evaluate().length,find.textContaining('S00E raw diagnostic').evaluate().length],[true,0,0]);
      k.emitEndFile(MovaEndFileReason.error); await d.drain(t);
      d.measured('CONTRACT.error.overlay.terminal',[a.state.error != null,
        find.text('S00E friendly error').evaluate().length,find.textContaining('S00E raw diagnostic').evaluate().length],[true,1,0]);
    } finally { await d.unmount(t); await d.dispose(t,a); }
  });
}
