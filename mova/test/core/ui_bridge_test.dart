import 'package:fake_async/fake_async.dart';
import 'package:mova/src/core/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/cutover/cutover.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/mova.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/state/ui_bridge.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/testing/hooks.dart';
import 'package:mova/src/ui/chrome/chrome.dart';

import '../support/fake_bridge_api.dart';
import '../support/fake_kernel.dart';

class _Sink implements IMovaUiSink {
  final calls = <String>[];
  @override
  void legacyShow({required bool sticky}) => calls.add('show:$sticky');
  @override
  void legacyHide() => calls.add('hide');
  @override
  void legacyHud(MovaHud hud, String? text) => calls.add('hud:$hud:$text');
  @override
  void legacyDragging(bool dragging, Duration? previewAt) =>
      calls.add('drag:$dragging:${previewAt?.inSeconds}');
}

Mova _mova() =>
    Mova(kernel: FakeKernel(), fetcher: const MovaTestHttpFetch());
Future<void> _flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  for (final proxy in [false, true]) {
    test(
      '末次解绑${proxy ? "代理" : "播放器"}镜像继续 HUD 与控制条剩余期限',
      () => fakeAsync((a) {
        final IMovaApi e = proxy
            ? MovaCutover(movaFactory: _mova)
            : _mova();
        final c = MovaChrome();
        movaBindChrome(c, e);
        a.flushMicrotasks();
        c.show();
        c.showHud(MovaHud.seek, text: '00:10');
        a.elapse(const Duration(milliseconds: 400));
        movaUnbindChrome(c);
        c.dispose();
        a.elapse(const Duration(milliseconds: 399));
        expect(e.uiState.hud, MovaHud.seek);
        a.elapse(const Duration(milliseconds: 1));
        expect(e.uiState.hud, MovaHud.none);
        expect(e.uiState.hudText, isNull);
        a.elapse(const Duration(milliseconds: 2199));
        expect(e.uiState.controlsVisible, isTrue);
        a.elapse(const Duration(milliseconds: 1));
        expect(e.uiState.controlsVisible, isFalse);
        e.dispose();
        a.flushMicrotasks();
      }),
    );
  }
  for (final sticky in [false, true]) {
    test(
      '末次解绑清理拖动预览并${sticky ? "保留常显" : "恢复隐藏"}',
      () => fakeAsync((a) {
        final e = _mova();
        final c = MovaChrome();
        movaBindChrome(c, e);
        c.show(sticky: sticky);
        c.setDragging(true, previewAt: const Duration(seconds: 10));
        movaUnbindChrome(c);
        expect(c.value.dragging, isFalse);
        expect(c.value.previewAt, isNull);
        expect(e.uiState.dragging, isFalse);
        expect(e.uiState.previewAt, isNull);
        c.dispose();
        a.elapse(const Duration(seconds: 3));
        expect(e.uiState.controlsVisible, sticky);
        e.showControls();
        a.elapse(const Duration(seconds: 3));
        expect(e.uiState.controlsVisible, isFalse);
        e.dispose();
        a.flushMicrotasks();
      }),
    );
  }
  test(
    '非末次解绑不接管其他视图的计时',
    () => fakeAsync((a) {
      final e = _mova();
      final one = MovaChrome(), two = MovaChrome();
      movaBindChrome(one, e);
      movaBindChrome(two, e);
      one.show();
      two.show(sticky: true);
      movaUnbindChrome(one);
      one.dispose();
      a.elapse(const Duration(seconds: 4));
      expect(two.value.controlsVisible, isTrue);
      expect(e.uiState.controlsVisible, isTrue);
      movaUnbindChrome(two);
      two.dispose();
      a.elapse(const Duration(seconds: 4));
      expect(e.uiState.controlsVisible, isTrue);
      e.dispose();
      a.flushMicrotasks();
    }),
  );
  test(
    '末次断开后恢复旧自动隐藏且断开幂等',
    () => fakeAsync((a) {
      final e = _mova();
      final sink = _Sink();
      final link = e.linkUi(sink);
      link.mirror(const MovaUiState(controlsVisible: false));
      expect(e.uiState.controlsVisible, isFalse);
      link.unlink();
      link.unlink();
      e.showControls();
      expect(e.uiState.controlsVisible, isTrue);
      a.elapse(const Duration(seconds: 3));
      expect(e.uiState.controlsVisible, isFalse);
      expect(sink.calls, isEmpty);
      e.dispose();
      a.flushMicrotasks();
    }),
  );

  test(
    '四个旧动词仅广播而不修改镜像和计时',
    () => fakeAsync((a) {
      final e = _mova();
      final one = _Sink(), two = _Sink();
      e.linkUi(one);
      e.linkUi(two);
      final before = e.uiState;
      e.showControls(sticky: true);
      e.hideControls();
      e.showHud(MovaHud.volume, text: 'x');
      e.setDragging(true, previewAt: const Duration(seconds: 3));
      expect(one.calls, [
        'show:true',
        'hide',
        'hud:MovaHud.volume:x',
        'drag:true:3',
      ]);
      expect(two.calls, one.calls);
      expect(e.uiState, before);
      expect(a.nonPeriodicTimerCount, 0);
      a.elapse(const Duration(seconds: 4));
      expect(one.calls, hasLength(4));
      expect(e.uiState, before);
      e.dispose();
      a.flushMicrotasks();
    }),
  );

  test('镜像给旧读者且同值不重复发', () async {
    final e = _mova();
    final link = e.linkUi(_Sink());
    final seen = <MovaUiState>[];
    final sub = e.uiStates.listen(seen.add);
    await _flush();
    seen.clear();
    const next = MovaUiState(controlsVisible: false, hud: MovaHud.volume);
    link.mirror(next);
    link.mirror(next);
    await _flush();
    expect(e.uiState, next);
    expect(seen, [next]);
    await sub.cancel();
    await e.dispose();
  });

  test(
    '连接时就绪事件照发但播放器不操作 UI',
    () => fakeAsync((a) {
      final e = _mova();
      final sink = _Sink();
      e.linkUi(sink);
      final events = <MovaEvent>[];
      e.events.listen(events.add);
      expect(e.uiReady, isFalse);
      e.open(const MovaSource('https://host/a.mp4'));
      a.flushMicrotasks();
      expect(e.uiReady, isTrue);
      expect(events.whereType<MovaReady>(), hasLength(1));
      expect(sink.calls, isEmpty);
      a.elapse(const Duration(seconds: 4));
      expect(e.uiState, const MovaUiState());
      e.dispose();
      a.flushMicrotasks();
    }),
  );

  test(
    '首个连接同步取消旧 HUD 和自动隐藏计时',
    () => fakeAsync((a) {
      final e = _mova()
        ..showControls()
        ..showHud(MovaHud.seek);
      expect(a.nonPeriodicTimerCount, 2);
      final sink = _Sink();
      e.linkUi(sink);
      expect(a.nonPeriodicTimerCount, 0);
      final before = e.uiState;
      a.elapse(const Duration(seconds: 5));
      expect(e.uiState, before);
      expect(sink.calls, isEmpty);
      e.dispose();
      a.flushMicrotasks();
    }),
  );

  test('销毁关闭连接且之后不回调视图', () async {
    final e = _mova();
    final sink = _Sink();
    final link = e.linkUi(sink);
    e.hideControls();
    expect(sink.calls, ['hide']);
    await e.dispose();
    e.showControls();
    e.hideControls();
    e.showHud(MovaHud.seek);
    e.setDragging(true);
    link.mirror(const MovaUiState(controlsVisible: false));
    link.unlink();
    e.linkUi(sink).mirror(const MovaUiState(controlsVisible: false));
    expect(e.uiReady, isFalse);
    expect(e.uiState, const MovaUiState());
    expect(sink.calls, ['hide']);
  });

  test('代理连接时屏蔽内部 UI 且旧动词不穿透', () async {
    final inner = FakeBridgeApi();
    final proxy = MovaCutover(movaFactory: () => inner);
    final sink = _Sink();
    proxy.linkUi(sink);
    inner.pushUi(const MovaUiState(controlsVisible: false));
    await _flush();
    expect(proxy.uiState.controlsVisible, isTrue);
    proxy.showControls(sticky: true);
    proxy.hideControls();
    proxy.showHud(MovaHud.volume, text: 'x');
    proxy.setDragging(true, previewAt: const Duration(seconds: 3));
    expect(sink.calls, [
      'show:true',
      'hide',
      'hud:MovaHud.volume:x',
      'drag:true:3',
    ]);
    expect(inner.calls, isEmpty);
    await proxy.dispose();
  });

  test('代理换指保留镜像，末次断开对齐新播放器', () async {
    final made = <FakeBridgeApi>[];
    final proxy = MovaCutover(
      movaFactory: () {
        final f = FakeBridgeApi(
          options: const MovaOpts(cutover: MovaCutoverOpts(enabled: true)),
        );
        made.add(f);
        return f;
      },
    );
    expect(proxy.uiReady, isFalse);
    made.first.ready = true;
    expect(proxy.uiReady, isTrue);
    final link = proxy.linkUi(_Sink());
    link.mirror(const MovaUiState(controlsVisible: false));
    await proxy.prepare(
      const MovaSource('https://host/b.mp4'),
      cue: const MovaWarmCue(
        remaining: Duration(seconds: 1),
        total: Duration(seconds: 10),
      ),
    );
    await _flush();
    const tick = MovaProg(
      position: Duration(seconds: 5),
      buffer: Duration(seconds: 6),
    );
    made[1].pushProgress(tick);
    await _flush();
    made[1].pushProgress(tick);
    await _flush();
    expect(await proxy.commit(), isTrue);
    made[1].pushUi(const MovaUiState());
    await _flush();
    expect(proxy.uiReady, isFalse);
    expect(proxy.state.renderEpoch, 1);
    expect(proxy.uiState.controlsVisible, isFalse);
    link.unlink();
    expect(proxy.uiState, made[1].uiState);
    await proxy.dispose();
  });
}
