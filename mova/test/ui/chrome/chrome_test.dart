import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/options/controls_config.dart';
import 'package:mova/src/core/state/ui_state.dart';
import 'package:mova/src/ui/chrome/chrome.dart';

void main() {
  test(
    'HUD 同步重入只保留最新计时器，销毁后无通知',
    () => fakeAsync((a) {
      final c = MovaChrome();
      var notifications = 0;
      c.addListener(() {
        notifications++;
        if (c.value.hud == MovaHud.seek) c.showHud(MovaHud.volume);
      });
      c.showHud(MovaHud.seek);
      expect(c.value.hud, MovaHud.volume);
      expect(a.nonPeriodicTimerCount, 1);
      c.dispose();
      expect(a.nonPeriodicTimerCount, 0);
      final before = notifications;
      a.elapse(const Duration(seconds: 2));
      expect(notifications, before);
    }),
  );

  test(
    'HUD 重入后微任务销毁不遗留计时器',
    () => fakeAsync((a) {
      final c = MovaChrome();
      c.addListener(() {
        if (c.value.hud == MovaHud.seek) {
          c.showHud(MovaHud.volume);
          scheduleMicrotask(c.dispose);
        }
      });
      c.showHud(MovaHud.seek);
      a.flushMicrotasks();
      expect(a.nonPeriodicTimerCount, 0);
      a.elapse(const Duration(seconds: 2));
    }),
  );
  test(
    '初值与流重放一致',
    () => fakeAsync((a) {
      final c = MovaChrome();
      final states = <MovaUiState>[];
      c.uiStates.listen(states.add);
      a.flushMicrotasks();
      expect(c.value, const MovaUiState());
      expect(c.uiState, c.value);
      expect(states, [const MovaUiState()]);
      c.dispose();
    }),
  );

  test(
    '默认三秒自动隐藏',
    () => fakeAsync((a) {
      final c = MovaChrome()..show();
      a.elapse(const Duration(milliseconds: 2900));
      expect(c.value.controlsVisible, isTrue);
      a.elapse(const Duration(milliseconds: 100));
      expect(c.value.controlsVisible, isFalse);
      c.dispose();
    }),
  );

  test(
    '常显直到再次 show',
    () => fakeAsync((a) {
      final c = MovaChrome()..show(sticky: true);
      a.elapse(const Duration(seconds: 10));
      expect(c.value.controlsVisible, isTrue);
      c.show();
      a.elapse(const Duration(seconds: 3));
      expect(c.value.controlsVisible, isFalse);
      c.dispose();
    }),
  );

  test(
    '重复显示重新计时且同值不通知，隐藏取消计时',
    () => fakeAsync((a) {
      final c = MovaChrome();
      var notifications = 0;
      c.addListener(() => notifications++);
      c.show();
      a.elapse(const Duration(seconds: 2));
      c.show();
      a.elapse(const Duration(milliseconds: 2900));
      expect(c.value.controlsVisible, isTrue);
      expect(notifications, 0);
      a.elapse(const Duration(milliseconds: 100));
      expect(c.value.controlsVisible, isFalse);
      c.show();
      c.hide();
      expect(a.nonPeriodicTimerCount, 0);
      final before = notifications;
      a.elapse(const Duration(seconds: 5));
      expect(notifications, before);
      c.dispose();
    }),
  );

  test(
    '关闭自动隐藏不创建计时器',
    () => fakeAsync((a) {
      final c = MovaChrome();
      movaSetChromeControls(c, const MovaCtrlsConfig(autoHide: false));
      c.show();
      expect(a.nonPeriodicTimerCount, 0);
      a.elapse(const Duration(seconds: 10));
      expect(c.value.controlsVisible, isTrue);
      c.dispose();
    }),
  );

  test(
    'HUD 八百毫秒收起且清空旧文本',
    () => fakeAsync((a) {
      final c = MovaChrome()..showHud(MovaHud.seek, text: '00:20');
      expect(c.value.hud, MovaHud.seek);
      expect(c.value.hudText, '00:20');
      a.elapse(const Duration(milliseconds: 799));
      expect(c.value.hud, MovaHud.seek);
      a.elapse(const Duration(milliseconds: 1));
      expect(c.value.hud, MovaHud.none);
      expect(c.value.hudText, isNull);
      c.showHud(MovaHud.seek, text: 'x');
      c.showHud(MovaHud.volume);
      expect(c.value.hudText, isNull);
      c.dispose();
    }),
  );

  test('拖动结束清空预览', () {
    final c = MovaChrome()
      ..setDragging(true, previewAt: const Duration(seconds: 12));
    expect(c.value.dragging, isTrue);
    expect(c.value.previewAt, const Duration(seconds: 12));
    c.setDragging(false);
    expect(c.value.dragging, isFalse);
    expect(c.value.previewAt, isNull);
    c.dispose();
  });

  test('销毁同步取消计时器且后续动词无效并关闭流', () async {
    final closed = Completer<void>();
    fakeAsync((a) {
      final c = MovaChrome()
        ..show()
        ..showHud(MovaHud.volume);

      var notifications = 0;
      c.addListener(() => notifications++);
      c.uiStates.listen((_) {}, onDone: closed.complete);
      a.flushMicrotasks();
      expect(a.nonPeriodicTimerCount, 2);
      final before = c.value;
      c.dispose();
      expect(a.nonPeriodicTimerCount, 0);
      c.show();
      c.hide();
      c.toggle();
      c.showHud(MovaHud.seek);
      c.setDragging(true);
      a.flushMicrotasks();
      expect(c.value, before);
      expect(notifications, 0);
    });
    await closed.future;
  });
}
