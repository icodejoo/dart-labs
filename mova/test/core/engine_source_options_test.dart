import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/kernel/source_options_kernel.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/recovery/fail.dart';

import '../support/fake_kernel.dart';

/// 记录"暂存选项 / open"先后顺序的内核。
class _OptionsKernel extends FakeStatsKernel implements MovaSourceOptionsKernel {
  final List<String> order = [];
  final List<Map<String, String>> staged = [];

  @override
  void stageSourceOptions(Map<String, String> options) {
    staged.add(options);
    order.add('stage');
  }

  @override
  Future<void> open(String uri, {bool play = true}) {
    order.add('open');
    return super.open(uri, play: play);
  }
}

void main() {
  const whep = 'whep+http://h:8889/x/whep';

  test('open：先暂存该源的选项再 open；WHEP 便捷项换算进 demuxer-lavf-o', () async {
    final k = _OptionsKernel();
    final e = MovaEngine(kernel: k);
    addTearDown(e.dispose);
    await e.open(
      const MovaSource(
        whep,
        type: MovaStreamType.live,
        whepMediaTimeout: Duration(seconds: 3),
        mpvOptions: {'cache': 'no'},
      ),
    );
    expect(k.order, ['stage', 'open']);
    expect(k.staged.single, {'cache': 'no', 'demuxer-lavf-o': 'media_timeout=3000000'});
  });

  test('统一超时配置：open 前透传给 mpv，源级显式设置优先', () async {
    final k = _OptionsKernel();
    final e = MovaEngine(
      kernel: k,
      options: const MovaOpts(
        recovery: MovaRecoveryConfig(
          timeouts: MovaTimeouts(network: Duration(seconds: 12), whepHandshake: Duration(seconds: 5)),
        ),
      ),
    );
    addTearDown(e.dispose);
    await e.open(const MovaSource(whep, type: MovaStreamType.live, mpvOptions: {'network-timeout': '30'}));
    expect(k.staged.single, {'network-timeout': '30', 'demuxer-lavf-o': 'handshake_timeout=5000000'});
    await e.open(const MovaSource('https://h/b.mp4'));
    expect(k.staged.last, {'network-timeout': '12'});
  });

  test('换源：下一个源没有选项时暂存空表（内核据此还原，不泄漏）', () async {
    final k = _OptionsKernel();
    final e = MovaEngine(kernel: k);
    addTearDown(e.dispose);
    await e.open(const MovaSource(whep, whepMediaTimeout: Duration(seconds: 3)));
    await e.open(const MovaSource('https://h/b.mp4'));
    expect(k.staged, hasLength(2));
    expect(k.staged.last, isEmpty);
    expect(k.order, ['stage', 'open', 'stage', 'open']);
  });

  test('备选地址按各自的协议取选项：failover 到非 WHEP 地址时不再带 media_timeout', () {
    fakeAsync((async) {
      final k = _OptionsKernel();
      final e = MovaEngine(
        kernel: k,
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true, policy: MovaFailoverOnly()),
          controls: MovaCtrlsConfig(autoHide: false),
        ),
      );
      e.open(
        const MovaSource(
          whep,
          type: MovaStreamType.live,
          alternatives: ['https://h/a.flv'],
          whepMediaTimeout: Duration(seconds: 3),
        ),
      );
      async.flushMicrotasks();
      expect(k.staged.single, {'demuxer-lavf-o': 'media_timeout=3000000'});
      async.elapse(const Duration(seconds: 10)); // 起播超时 -> failover
      async.flushMicrotasks();
      expect(k.openedUris.last, 'https://h/a.flv');
      expect(k.staged.last, isEmpty);
    });
  });

  test('重试重载同一个源时重新暂存同样的选项', () {
    fakeAsync((async) {
      final k = _OptionsKernel();
      final e = MovaEngine(
        kernel: k,
        options: const MovaOpts(
          recovery: MovaRecoveryConfig(startTimeout: Duration(seconds: 10), stallTimeout: Duration(seconds: 10), enabled: true),
          controls: MovaCtrlsConfig(autoHide: false),
        ),
      );
      e.open(const MovaSource(whep, type: MovaStreamType.live, whepMediaTimeout: Duration(seconds: 3)));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 11));
      expect(k.openedUris, hasLength(2));
      expect(k.staged, hasLength(2));
      expect(k.staged.last, {'demuxer-lavf-o': 'media_timeout=3000000'});
    });
  });

  test('内核不具备该能力：open 照常工作', () async {
    final k = FakeKernel();
    final e = MovaEngine(kernel: k);
    addTearDown(e.dispose);
    await e.open(const MovaSource(whep, whepMediaTimeout: Duration(seconds: 3)));
    expect(k.openedUris, [whep]);
  });
}
