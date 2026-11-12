/// 包内播放命令代际，识别意图值未变化的显式播放或暂停。
final Expando<int> _commands = Expando<int>();

/// 返回 [api] 最近的播放命令代际，不扩展公开 API。
int movaPlaybackCommand(Object api) => _commands[api] ?? 0;

/// 记录一次显式播放或暂停，供广告重试识别后来的用户命令。
void movaRecordPlaybackCommand(Object api) {
  _commands[api] = movaPlaybackCommand(api) + 1;
}
