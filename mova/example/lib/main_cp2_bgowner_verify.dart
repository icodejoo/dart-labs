// 未上机：CP2 独立验证页。
import 'verify_auto/cp2_harness.dart';
import 'verify_auto/cp2_bgowner_auto.dart';
import 'verify_auto/auto_kit.dart';
void main() {
  cp2BgownerViewOnly=coverageOnlyOverride=='view';
  cp2Main('bgowner', runBgowner);
}
