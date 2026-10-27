import 'package:mova/src/core/kernel/player_mute.dart';

import 'fake_kernel.dart';

/// A fake kernel recording player-local warm-up mute.
///
/// 记录播放器预热静音的假内核。
class FakeWarmMuteKernel extends FakeKeepAliveKernel implements MovaPlayerMute {
  /// Whether warm-up currently owns mute.
  ///
  /// 当前是否持有预热静音。
  bool warmMuted = false;

  /// Whether releasing mute succeeds; false simulates a property write failure.
  ///
  /// 释放静音是否成功；false 模拟属性写入失败。
  bool releaseResult = true;

  /// Records acquisition/release without touching the volume implementation.
  ///
  /// 记录静音获取或释放，不触碰音量实现。
  @override
  Future<bool> setWarmMute(bool on) async {
    calls.add('warmMute:$on');
    if (!on && !releaseResult) return false;
    warmMuted = on;
    return true;
  }
}
