import '../core/easing/easing.dart';

/// 上游七个 easing 名称；仅在 compat 中引入此表，例如 `kLuckyCanvasEasingNames['quad']`。
const Map<String, LuckyEasing> kLuckyCanvasEasingNames = {
  'quad': LuckyEasings.quad,
  'cubic': LuckyEasings.cubic,
  'quart': LuckyEasings.quart,
  'quint': LuckyEasings.quint,
  'sine': LuckyEasings.sine,
  'expo': LuckyEasings.expo,
  'circ': LuckyEasings.circ,
};
