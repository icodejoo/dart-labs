// ignore_for_file: avoid_relative_lib_imports
// test/accept/lib 是仓库内执行器源码，按目标目录使用相对导入。
import '../lib/literals.dart';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import '../lib/common.dart';

/// 首次发送之后的克隆失败原因。
const _cloneFailure = 'multipart replay clone failed';

/// 封装 BrokenReplayForm 测试夹具。
/// 让已发送附件在重试克隆时暴露格式错误，模拟调用方自定义 multipart。
class BrokenReplayForm extends FormData {
  /// 原始请求体的克隆次数；首发也会克隆。
  int _clones = 0;

  /// clone 的测试实现。
  /// 非状态类错误应通过共享结算传给每个调用者。
  @override
  FormData clone() {
    if (_clones++ == 0) return super.clone();
    throw const FormatException(_cloneFailure);
  }
}

/// main 的测试辅助入口。
/// 真实 HTTP/business 双风格确认首发与跟随者都失败、资源释放且没有第二次传输。
Future<void> main() async {
  final session =
      'dioman-share-prepare-${DateTime.now().microsecondsSinceEpoch}-$pid';
  final control = ioClient(netemUrl);
  final server = ioClient(serverUrl);
  final results = <Map<String, dynamic>>[];
  try {
    for (final style in [tkHttp, tkBusiness]) {
      final run = '$session-$style';
      final proxy = await createProbeProxy(control, run);
      final dio = ioClient('http://127.0.0.1:${proxy[tkPort]}');
      final events = <bool>[];
      final api = Dioman(
          dio: dio,
          key: DiomanKeyOptions(builder: (_) => run),
          plugins: [
            const DiomanShare(
                policy: DiomanSharePolicy.retry, retries: 1, methods: {tkPOST}),
            DiomanLoading(onChanged: events.add)
          ]);
      dio.options.headers.addAll({runHeader: run, styleHeader: style});
      try {
        /// 捕获真实失败，避免并发请求产生未处理异常。
        /// attempt 的测试辅助入口。
        Future<FormatException> attempt() async {
          if (serviceBlocked) throw StateError('服务已要求停止验收');
          try {
            await api.post<dynamic>(tkTEcho,
                data: BrokenReplayForm(),
                call: DiomanCall(options: {DiomanShare.option: true}),
                query: {tkKey: run, tkFailTimes: 1, tkDelayMs: 100});
            throw StateError('预期附件克隆失败，实际成功');
          } on FormatException catch (error) {
            return error;
          }
        }

        final first = attempt();
        // 先等服务端已收到首发，再发跟随者，不依赖客户端调度猜测。
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (true) {
          final stats = obj(obj((await server.get<dynamic>('/t/runs/$run',
                  options: Options(headers: {runHeader: run})))
              .data)[tkData]);
          if ((stats[tkTotal] as num? ?? 0) >= 1) break;
          if (DateTime.now().isAfter(deadline)) throw StateError('首发没有真实命中服务');
          await pause(5);
        }
        final errors = await Future.wait([first, attempt()])
            .timeout(const Duration(seconds: 5));
        final stats = obj(obj((await server.get<dynamic>('/t/runs/$run',
                options: Options(headers: {runHeader: run})))
            .data)[tkData]);
        if (errors.any((error) => error.message != _cloneFailure) ||
            stats[tkTotal] != 1 ||
            stats[tkInflight] != 0 ||
            events.where((v) => v).length != events.where((v) => !v).length) {
          throw StateError('share 异常交付或真实传输次数/资源释放不符：$errors/$stats/$events');
        }
        results.add({
          tkRunId: run,
          tkStyle: style,
          tkStatus: tkPassed,
          'errors': errors.map((error) => error.toString()).toList(),
          tkLoading: events,
          tkServer: stats
        });
        stdout.writeln('通过 $run');
      } finally {
        api.dispose();
        dio.close(force: true);
        await deleteProbeProxy(control, proxy, run);
      }
    }
  } finally {
    control.close(force: true);
    server.close(force: true);
    File('coverage/accept/share-prepare-real.json').writeAsStringSync(
        const JsonEncoder.withIndent(tkJsonIndent)
            .convert({tkSession: session, tkResults: results}));
  }
}
