// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'lib/token_manager.dart';
export 'lib/token_manager.dart';

/// 文件内共用的字面量。
const _literalRefreshToken = "refreshToken";

/// 构造洋葱客户端；调用方负责 dispose 并关闭 Dio。
Dioman createHttp({
  String baseUrl = 'https://api.example.com',
  Duration connectTimeout = const Duration(seconds: 15),
  Duration receiveTimeout = const Duration(seconds: 15),
  required DiomanTokenManager tokenManager,
  void Function(bool loading)? onLoading,
  Future<void> Function()? onSessionExpired,
  bool enableMock = false,
  String? mockUrl,
  int retryMax = 2,
}) {
  return Dioman(
      dio: Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout)),
      plugins: [
        const DiomanRepath(),
        const DiomanFilter(),
        const DiomanCache(),
        const DiomanShare(),
        DiomanRetry(max: retryMax),
        if (enableMock) DiomanMock(mockUrl: mockUrl),
        DiomanLoading(onChanged: onLoading ?? (_) {}),
        DiomanAuth(
            tokenManager: tokenManager,
            isProtected: (request) => !request.path.contains('/auth/'),
            onRefresh: (tokens, _) async {
              final refresh = Dioman(dio: Dio(BaseOptions(baseUrl: baseUrl)));
              try {
                final data = await refresh.post<Map<String, dynamic>>(
                    '/auth/refresh-token',
                    data: {_literalRefreshToken: tokens.refreshToken});
                tokens.setTokens(
                    accessToken: data['accessToken'] as String,
                    refreshToken: data[_literalRefreshToken] as String?);
              } finally {
                refresh.dispose();
                refresh.dio.close(force: true);
              }
            },
            onAccessExpired: (_, __) async => onSessionExpired?.call()),
      ]);
}

/// 普通请求抛出归一化失败；send 可直接读取结果。
Future<void> main() async {
  final api =
      createHttp(tokenManager: InMemoryTokenManager(access: 'demo-access'));
  try {
    final user = await api.get<dynamic>('/users/{id}',
        query: {'id': 42, 'q': ''},
        call: DiomanCall(
            options: {DiomanCache.option: true, DiomanShare.option: true}));
    print(user);
    final result = await api.send<dynamic>('GET', '/public/config',
        call: DiomanCall(
            options: {DiomanAuth.option: false, DiomanLoading.option: false}));
    print('${result.kind.name}: ${result.data}');
  } on DiomanResponse catch (failure) {
    print('${failure.kind.name}: ${failure.message}');
  } finally {
    api.cancelAll();
    api.dispose();
    api.dio.close(force: true);
  }
}
