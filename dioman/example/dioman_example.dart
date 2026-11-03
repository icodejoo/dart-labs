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
      ]);
  try {
    final data =
        await api.get<Map<String, dynamic>>('/users/{id}', query: {'id': 42});
    print(data);
    final result = await api.send<dynamic>('GET', '/health');
    print(
        '${failureOf(result)?.kind.name}: ${result.status}, code ${result.code}');
  } on DiomanResponse catch (failure) {
    print('${failureOf(failure)?.kind.name}: ${failure.message}');
  } finally {
    api.dispose();
    api.dio.close(force: true);
  }
}
