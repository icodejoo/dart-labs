import 'session.dart';

/// 播放列表借用的会话登记，不导出；覆盖层在包内查询。
final movaPlaylistSessions = Expando<MovaSession>('movaPlaylistSessions');
