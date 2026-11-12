import 'package:flutter/material.dart';

/// 播放器控制界面的图标集合；默认图标与旧界面一致，社交按钮不在本集合中。
/// 通过 MovaPlayerStyle.icons 配置，各节整体替换。
/// 示例：`MovaIcons(pip: Icons.open_in_new)`。
@immutable
class MovaIcons {
  /// 创建图标集合；未指定的字段使用内置 Material 图标。
  const MovaIcons({
    this.pip = Icons.picture_in_picture_alt_rounded,
    this.quality = Icons.high_quality_rounded,
    this.aspectRatio = Icons.aspect_ratio_rounded,
    this.rotate = Icons.screen_rotation_rounded,
    this.enterFullscreen = Icons.fullscreen_rounded,
    this.exitFullscreen = Icons.fullscreen_exit_rounded,
    this.lock = Icons.lock_open_rounded,
    this.unlock = Icons.lock_rounded,
    this.subtitles = Icons.subtitles_rounded,
    this.subtitlesOff = Icons.subtitles_off_rounded,
    this.speed = Icons.speed_rounded,
    this.backToLive = Icons.sync_rounded,
    this.play = Icons.play_circle_filled_rounded,
    this.pause = Icons.pause_circle_filled_rounded,
    this.volumeOff = Icons.volume_off_rounded,
    this.volumeUp = Icons.volume_up_rounded,
    this.brightness = Icons.brightness_6_rounded,
    this.retry = Icons.refresh_rounded,
    this.check = Icons.check_rounded,
    this.closeMini = Icons.close,
  });

  /// 画中画图标。
  final IconData pip;

  /// 清晰度图标。
  final IconData quality;

  /// 画面比例图标。
  final IconData aspectRatio;

  /// 旋转屏幕图标。
  final IconData rotate;

  /// 进入全屏图标。
  final IconData enterFullscreen;

  /// 退出全屏图标。
  final IconData exitFullscreen;

  /// 锁定控制图标。
  final IconData lock;

  /// 解锁控制图标。
  final IconData unlock;

  /// 开启字幕图标。
  final IconData subtitles;

  /// 关闭字幕图标。
  final IconData subtitlesOff;

  /// 播放速度图标。
  final IconData speed;

  /// 回到直播图标。
  final IconData backToLive;

  /// 中央播放图标。
  final IconData play;

  /// 中央暂停图标。
  final IconData pause;

  /// 静音提示图标。
  final IconData volumeOff;

  /// 音量提示图标。
  final IconData volumeUp;

  /// 亮度提示图标。
  final IconData brightness;

  /// 重试图标。
  final IconData retry;

  /// 选中标记图标。
  final IconData check;

  /// 关闭小窗图标。
  final IconData closeMini;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MovaIcons &&
          pip == other.pip &&
          quality == other.quality &&
          aspectRatio == other.aspectRatio &&
          rotate == other.rotate &&
          enterFullscreen == other.enterFullscreen &&
          exitFullscreen == other.exitFullscreen &&
          lock == other.lock &&
          unlock == other.unlock &&
          subtitles == other.subtitles &&
          subtitlesOff == other.subtitlesOff &&
          speed == other.speed &&
          backToLive == other.backToLive &&
          play == other.play &&
          pause == other.pause &&
          volumeOff == other.volumeOff &&
          volumeUp == other.volumeUp &&
          brightness == other.brightness &&
          retry == other.retry &&
          check == other.check &&
          closeMini == other.closeMini;
  @override
  int get hashCode => Object.hashAll([
    pip,
    quality,
    aspectRatio,
    rotate,
    enterFullscreen,
    exitFullscreen,
    lock,
    unlock,
    subtitles,
    subtitlesOff,
    speed,
    backToLive,
    play,
    pause,
    volumeOff,
    volumeUp,
    brightness,
    retry,
    check,
    closeMini,
  ]);
}
