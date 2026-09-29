import 'dart:math';

/// Generates a fresh session id: a pure function, no third-party `uuid`
/// dependency (mirrors this project's sha1→FNV-1a-style "roll our own instead
/// of a new dependency" tradeoff).
///
/// Format is `<microseconds-since-epoch hex>-<8 random hex digits>` — not a
/// UUID, just unique-enough and cheap; hosts that need RFC-4122 compliance
/// can inject their own via [MovaSessionIdFactory].
///
/// 生成一个新的会话 ID：纯函数，不引入第三方 `uuid` 依赖（与本仓库
/// sha1→FNV-1a 式"自实现而非引入新依赖"的取舍一脉相承）。
///
/// 格式为 `<微秒时间戳十六进制>-<8 位随机十六进制>`——不是 UUID，只求"足够唯一
/// 且开销低"；需要 RFC-4122 合规的宿主可经 [MovaSessionIdFactory] 自行注入。
///
/// Example / 示例:
/// ```dart
/// final id = newMovaSessionId();
/// ```
String newMovaSessionId() {
  final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  final rand = Random().nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '$micros-$rand';
}

/// Injectable session-id factory type; see [MovaReportConfig.sessionId].
///
/// 可注入的会话 ID 工厂类型；见 `MovaReportConfig.sessionId`。
typedef MovaSessionIdFactory = String Function();
