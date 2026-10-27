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

// Old names kept for one release so hosts can migrate gradually.
// Only type positions and constructors are covered: static members (enum values)
// are not reachable through a type alias, and renamed members/parameters
// (`setStandby`, `swapTo`, `MovaOpts(swap:/standby:)`) have no alias — see CHANGELOG.
//
// 旧名保留一个版本，方便宿主逐步迁移。只覆盖类型位置与构造器：枚举值等静态成员无法经类型别名访问，
// 改名的成员/参数（`setStandby`、`swapTo`、`MovaOpts(swap:/standby:)`）没有别名——见 CHANGELOG。

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
