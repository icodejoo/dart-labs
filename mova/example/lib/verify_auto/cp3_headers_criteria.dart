/// 新截图能力启用后，旧原生截图仅作对照；缺失新样本仍须失败。
bool cp3HeadersNativePathsPass(
  Map<String, Map<String, Object?>> paths, {
  required bool captureReady,
}) {
  final required = captureReady
      ? ['extract', 'pool-ready', 'pool-ready-cutover']
      : ['extract', 'pool'];
  return required.every((key) => paths[key]?['pass'] == true);
}

/// 单变体夹具必须同时得到 auto 和真实档位，并确认选档后的原生地址。
bool cp3HeadersQualityPass(
  List<Map<String, Object?>> qualities,
  String expectedUri,
  String? selectedPath,
) =>
    qualities.length == 2 &&
    qualities[0]['auto'] == true &&
    qualities[1]['auto'] == false &&
    qualities[1]['uri'] == expectedUri &&
    qualities[1]['height'] == 360 &&
    selectedPath == expectedUri;
