import 'package:flutter/widgets.dart';
import 'package:layerman/layerman.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

Layerman om = _fresh();

Layerman _fresh() => Layerman(
      gap: const Duration(milliseconds: 300),
      pauseOnRoutes: const ['/zone'],
    );

Layerman createFreshManager() => _fresh();

void Function()? _restartCb;
void registerRestartCallback(void Function() cb) => _restartCb = cb;
void restartApp() => _restartCb?.call();

/// GlobalKey for the [ShadSonner] inserted in the builder chain.
/// Allows present-callbacks (which have no BuildContext) to show shadcn/ui
/// toasts without needing [ShadSonner.of(context)].
final GlobalKey<ShadSonnerState> shadSonnerKey = GlobalKey<ShadSonnerState>();
