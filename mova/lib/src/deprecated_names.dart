import 'core/ad/ads.dart';
import 'core/cutover/cutover_engine.dart';
import 'core/cutover/ctl.dart';
import 'core/feed/feed.dart';
import 'core/keep_alive/keep_alive.dart';
import 'core/events/events.dart';
import 'core/options/cutover_config.dart';
import 'core/options/keep_alive_config.dart';
import 'core/playlist/playlist.dart';
import 'ui/mini/mini.dart';

// 旧类型名均以 @Deprecated 别名保留一个版本，构造器和当前 Dart 支持的枚举值可经别名访问。
// 工厂已统一使用 MovaEngineFactory，无需另建 Swap/Controller 工厂名。
// 改名的方法/具名参数（setStandby、swapTo、MovaOpts(swap:/standby:)）没有桥接。
// 小窗宿主 ctl 与广告覆盖层 controller 的成员兼容入口定义在各自组件中。

/// Old name of [MovaAds] / [MovaAds] 的旧名。
@Deprecated('Use MovaAds')
typedef MovaAdController = MovaAds;

/// Old name of [MovaFeed] / [MovaFeed] 的旧名。
@Deprecated('Use MovaFeed')
typedef MovaFeedController = MovaFeed;

/// Old name of [MovaPlaylist] / [MovaPlaylist] 的旧名。
@Deprecated('Use MovaPlaylist')
typedef MovaPlaylistController = MovaPlaylist;

/// Old name of [MovaMini] / [MovaMini] 的旧名。
@Deprecated('Use MovaMini')
typedef MovaMiniController = MovaMini;

/// Old name of [MovaCutoverEngine] / [MovaCutoverEngine] 的旧名。
@Deprecated('Use MovaCutoverEngine')
typedef MovaSwapEngine = MovaCutoverEngine;

/// Old name of [MovaCutover] / [MovaCutover] 的旧名。
@Deprecated('Use MovaCutover')
typedef MovaSwapController = MovaCutover;

/// Old name of [MovaCutoverConfig] / [MovaCutoverConfig] 的旧名。
@Deprecated('Use MovaCutoverConfig')
typedef MovaSwapConfig = MovaCutoverConfig;

/// Old name of [MovaCutoverChange] / [MovaCutoverChange] 的旧名。
@Deprecated('Use MovaCutoverChange')
typedef MovaSwapChange = MovaCutoverChange;

/// Old name of [MovaCutoverPhase] / [MovaCutoverPhase] 的旧名。
@Deprecated('Use MovaCutoverPhase')
typedef MovaSwapPhase = MovaCutoverPhase;

/// Old name of [MovaKeepAlive] / [MovaKeepAlive] 的旧名。
@Deprecated('Use MovaKeepAlive')
typedef MovaStandbyController = MovaKeepAlive;

/// Old name of [MovaKeepAliveConfig] / [MovaKeepAliveConfig] 的旧名。
@Deprecated('Use MovaKeepAliveConfig')
typedef MovaStandbyConfig = MovaKeepAliveConfig;

/// Old name of [MovaKeepAlivePhase] / [MovaKeepAlivePhase] 的旧名。
@Deprecated('Use MovaKeepAlivePhase')
typedef MovaStandbyPhase = MovaKeepAlivePhase;

/// Old name of [MovaKeepAliveMode] / [MovaKeepAliveMode] 的旧名。
@Deprecated('Use MovaKeepAliveMode')
typedef MovaStandbyMode = MovaKeepAliveMode;

/// Old name of [MovaKeepAliveReason] / [MovaKeepAliveReason] 的旧名。
@Deprecated('Use MovaKeepAliveReason')
typedef MovaStandbyReason = MovaKeepAliveReason;

/// Old name of [MovaKeepAliveChange] / [MovaKeepAliveChange] 的旧名。
@Deprecated('Use MovaKeepAliveChange')
typedef MovaStandbyChange = MovaKeepAliveChange;

/// Old name of [MovaKeepAliveResume] / [MovaKeepAliveResume] 的旧名。
@Deprecated('Use MovaKeepAliveResume')
typedef MovaStandbyResume = MovaKeepAliveResume;

/// Old name of [MovaSilentKeepAlive] / [MovaSilentKeepAlive] 的旧名。
@Deprecated('Use MovaSilentKeepAlive')
typedef MovaSilentStandby = MovaSilentKeepAlive;
