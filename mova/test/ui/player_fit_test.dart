import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/ui/player.dart';

import '../support/fake_api.dart';

/// Number of `setFit` calls recorded by [api].
///
/// [api] 记录到的 `setFit` 调用次数。
int _setFitCalls(FakeMovaApi api) => api.calls.where((c) => c == 'setFit').length;

/// Pumps a [MovaPlayer] for [api] with the given declarative [fit].
///
/// 用给定的声明式 [fit] 为 [api] pump 一个 [MovaPlayer]。
Future<void> _pump(WidgetTester t, FakeMovaApi api, MovaFit? fit) async {
  await t.pumpWidget(MaterialApp(home: MovaPlayer(api: api, fit: fit)));
  await t.pump();
}

void main() {
  testWidgets('mounting with fit applies it exactly once', (t) async {
    final api = FakeMovaApi();
    await _pump(t, api, MovaFit.cover);
    expect(api.lastFit, MovaFit.cover);
    expect(_setFitCalls(api), 1);
    await api.dispose();
  });

  testWidgets('a rebuild with the same fit does not call setFit again', (t) async {
    final api = FakeMovaApi();
    await _pump(t, api, MovaFit.cover);
    await _pump(t, api, MovaFit.cover);
    expect(_setFitCalls(api), 1);
    await api.dispose();
  });

  testWidgets('changing the fit applies the new value', (t) async {
    final api = FakeMovaApi();
    await _pump(t, api, MovaFit.cover);
    await _pump(t, api, MovaFit.fill);
    expect(api.lastFit, MovaFit.fill);
    expect(_setFitCalls(api), 2);
    await api.dispose();
  });

  testWidgets('fit: null never calls setFit', (t) async {
    final api = FakeMovaApi();
    await _pump(t, api, null);
    await _pump(t, api, null);
    expect(_setFitCalls(api), 0);
    await api.dispose();
  });

  testWidgets('swapping in a new api re-applies the same fit to it', (t) async {
    final first = FakeMovaApi();
    final second = FakeMovaApi();
    await _pump(t, first, MovaFit.cover);
    await _pump(t, second, MovaFit.cover);
    expect(second.lastFit, MovaFit.cover);
    expect(_setFitCalls(second), 1);
    await first.dispose();
    await second.dispose();
  });
}
