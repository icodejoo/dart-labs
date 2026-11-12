// 未上机。池只建固定数量引擎；无画面的 feed 压力阶段用 audioOnly。
import 'package:mova/mova.dart';
import 'package:flutter/material.dart';
import 'cp1_harness.dart';

class _Reject extends MovaHook {
  String mode = 'allow';
  @override
  Future<bool> beforeOpen(MovaSource s) async {
    if (mode == 'throw') {
      throw StateError('CP1 host open rejection');
    }
    return mode != 'reject';
  }
}

Future<void> runPool(Cp1Harness h) async {
  for (final mode in ['reject', 'throw']) {
    for (var run = 0; run < h.runs; run++) {
      final hook = _Reject();
      var requestedIndex = 0;
      final pool = MovaFeedEnginePool(
        size: 1,
        engineFactory: () => createMovaEngine(interceptors: [hook]),
        onChanged: h.refresh,
      );
      h.customSurface = Builder(
        builder: (context) {
          final slot = pool.slotFor(requestedIndex);
          return slot?.ready == true
              ? MovaPlayer(api: slot!.api)
              : const ColoredBox(
                  key: ValueKey('cp1-pool-placeholder'),
                  color: Colors.black,
                );
        },
      );
      // Mount before binding: even rejected/retried engines have a real surface.
      final first = pool.bind(0, h.source('a'), autoPlay: true);
      await h.until(() => pool.slotFor(0) != null);
      await h.mount(pool.slotFor(0)!.api);
      await first;
      await h.until(() => h.api!.state.rendered);
      final before = await h.native();
      hook.mode = mode;
      requestedIndex = 1;
      h.refresh();
      await h.frame();
      final next = h.source('b');
      var threw = false;
      try {
        await pool.bind(1, next, autoPlay: true);
      } catch (_) {
        threw = true;
      }
      await h.frame();
      final hidden =
          pool.slotFor(1)?.ready != true &&
          h.elements().any(
            (e) => e.widget.key == const ValueKey('cp1-pool-placeholder'),
          );
      hook.mode = 'allow';
      await pool.bind(1, next, autoPlay: true);
      final slot = pool.slotFor(1);
      h.refresh();
      await h.frame();
      await h.until(() async => (await h.native())['path'] == next.uri);
      final after = await h.native();
      h.check(
        '$mode.$run',
        {
          'before': before,
          'after': after,
          'expectedPath': next.uri,
          'hiddenOnReject': hidden,
          'threw': threw,
          'ready': slot?.ready,
        },
        pass:
            hidden &&
            slot?.ready == true &&
            after['path'] == next.uri &&
            (mode == 'throw' ? threw : !threw),
      );
      await pool.dispose();
      h.customSurface = null;
      await h.release(disposeEngine: false);
    }
  }
  for (var run = 0; run < 3; run++) {
    final pool = MovaFeedEnginePool(
      size: 3,
      engineFactory: () => createMovaEngine(audioOnly: true),
    );
    final feed = MovaFeed(
      pool: pool,
      loader: (i) async =>
          i < 1000 ? MovaFeedItem(source: h.source('a')) : null,
    );
    final samples = <Map<String, Object?>>[];
    var maxCache = 0;
    for (var index = 0; index < 1000; index++) {
      await feed.activate(index);
      if (feed.cachedItemCount > maxCache) {
        maxCache = feed.cachedItemCount;
      }
      if ((index + 1) % 100 == 0) {
        final id = 'pss.$run.${index + 1}';
        await h.hostSample(id, 'meminfo');
        samples.add({
          'index': index + 1,
          'cacheCount': feed.cachedItemCount,
          'pending': feed.pendingItemCount,
          'engineCount': pool.engineCount,
          ...h.hostData[id]!,
        });
      }
    }
    final valid =
        samples.length == 10 && samples.every((s) => s['pssKb'] is int);
    final ys = valid
        ? samples.map((s) => (s['pssKb'] as int).toDouble()).toList()
        : <double>[];
    final slope = valid
        ? List.generate(
                10,
                (i) => (i - 4.5) * (ys[i] - ys.reduce((a, b) => a + b) / 10),
              ).reduce((a, b) => a + b) /
              82.5
        : null;
    final monotonic =
        valid && List.generate(9, (i) => ys[i + 1] > ys[i]).every((v) => v);
    h.check(
      'feed.$run',
      {
        'items': 1000,
        'maxCache': maxCache,
        'cacheBound': 7,
        'samples': samples,
        'pssSlopeKbPer100Items': slope,
        'strictlyIncreasing': monotonic,
        'adjacentDeltasKb': valid
            ? List.generate(9, (i) => ys[i + 1] - ys[i])
            : null,
        'slopeCriterion':
            '!(strictlyIncreasing && OLS_slope_Kb_per_100_items>0)',
        'criterion': 'maxCache<=7 && !(strictlyIncreasing && OLS_slope>0)',
      },
      pass: valid && maxCache <= 7 && !monotonic,
      missing: valid ? null : '缺每 100 条 dumpsys meminfo PSS',
    );
    feed.dispose();
    await pool.dispose();
  }
}
