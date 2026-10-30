import 'package:dioman/dioman.dart';

/// 示例凭证存储；真实应用应替换成安全存储。
class InMemoryTokenManager implements DiomanTokenManager {
  /// 设置初始凭证；省略访问凭证表示未登录。
  InMemoryTokenManager({String? access, String? refresh})
      : _access = access,
        _refresh = refresh;
  String? _access;
  String? _refresh;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => _refresh;
  /// 写入刷新结果，同时替换刷新凭证。
  @override
  void setTokens({required String accessToken, String? refreshToken}) {
    _access = accessToken;
    _refresh = refreshToken;
  }

  /// 退出当前会话。
  @override
  void clear() {
    _access = null;
    _refresh = null;
  }
}
