// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';

Future<void> main() async {
  final api = Dioman(
      dio: Dio(BaseOptions(baseUrl: 'https://api.example.com')),
      plugins: [
        const DiomanRepath(),
        const DiomanFilter(),
        DiomanMock(routes: {
          'GET:/users/42': (_) => {
                'code': 0,
                'data': {'id': 42}
              },
          'GET:/health': (_) => {'code': 0, 'data': 'ready'},
        }),
      ],
      // 整个逻辑请求（排队、重试、传输）的默认预算。
      deadline: const Duration(seconds: 5));
  try {
    final data =
        await api.get<Map<String, dynamic>>('/users/{id}', query: {'id': 42});
    print(data);
    // decode 仅在成功落定后执行，失败时跳过。
    final id = await api.get<int>('/users/{id}',
        query: {'id': 42}, decode: (d) => (d as Map)['id'] as int);
    print('decoded id: $id');
    final result = await api.send<dynamic>('GET', '/health');
    print(
        '${failureOf(result)?.kind.name}: ${result.status}, code ${result.code}');
  } on DiomanResponse catch (failure) {
    print('${failureOf(failure)?.kind.name}: ${failure.message}');
  } finally {
    await api.dispose();
    api.dio.close(force: true);
  }
}
