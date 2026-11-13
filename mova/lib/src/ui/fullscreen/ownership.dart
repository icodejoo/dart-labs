import 'package:flutter/widgets.dart';

import '../../core/api.dart';

// 包内：同一 API 只允许一个内联视图持有全屏路由。
final movaFullscreenRoutes = Expando<Route<void>>();

// 自己的全屏路由不算遮挡；其他页面覆盖仍交给 B13 守卫处理。
bool movaCoveredByFullscreen(IMovaApi api, ModalRoute<dynamic> route) {
  final fullscreen = movaFullscreenRoutes[api];
  return fullscreen != null &&
      fullscreen.isCurrent &&
      identical(fullscreen.navigator, route.navigator);
}
