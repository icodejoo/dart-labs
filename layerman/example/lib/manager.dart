import 'package:layerman/layerman.dart';

OverlayManager om = _fresh();

OverlayManager _fresh() => OverlayManager(
      gap: const Duration(milliseconds: 300),
      pauseOnRoutes: const ['/zone'],
    );

OverlayManager createFreshManager() => _fresh();

void Function()? _restartCb;
void registerRestartCallback(void Function() cb) => _restartCb = cb;
void restartApp() => _restartCb?.call();
