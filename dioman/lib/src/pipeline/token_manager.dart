/// 凭证存储契约；鉴权过期与单飞状态由每客户端的 auth 实例管理。
/// 实现者负责持久化；例如登录后调用 `setTokens(accessToken: 'a')`。
abstract interface class DiomanTokenManager {
  /// 当前原始访问凭证，null 或空串表示未登录。
  String? get accessToken;

  /// 当前刷新凭证；是否可刷新由 onRefresh 决定。
  String? get refreshToken;

  /// 写入凭证；省略的 refreshToken 表示清除刷新凭证。
  void setTokens({required String accessToken, String? refreshToken});

  /// 清除当前会话的全部凭证。
  void clear();
}
