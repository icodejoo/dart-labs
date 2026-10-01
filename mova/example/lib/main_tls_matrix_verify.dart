// ignore_for_file: avoid_print, implementation_imports
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// TLS 校验矩阵真机验证：配置 x 证书 x 资源，全部走本机可控 HTTPS 服务。
///
/// 服务见 scratchpad/tls/srv.py（端口 9441 合法 / 9442 过期 / 9443 主机名不符 / 9444 自签，
/// 均经 `adb reverse`）。判据只用事件与服务端日志，输出 `TLSM RES` 行供离线汇总。
/// 跑法：`flutter run --release -d <设备> -t lib/main_tls_matrix_verify.dart`，logcat 取 `TLSM`。
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MovaMpvKernel.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('tls matrix')))));
  Future<void>.delayed(const Duration(seconds: 1), _run);
}

/// 自建根 CA（PEM）。
const String kCaPem = r'''-----BEGIN CERTIFICATE-----
MIIDKTCCAhGgAwIBAgIUQTZNEDkdsRXoVMpgvM0bGq5vKnUwDQYJKoZIhvcNAQEL
BQAwHDEaMBgGA1UEAwwRTW92YSBUZXN0IFJvb3QgQ0EwHhcNMjYxMDAxMDExNzEx
WhcNMzYwOTI4MDExNzExWjAcMRowGAYDVQQDDBFNb3ZhIFRlc3QgUm9vdCBDQTCC
ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKmUnTGdwfh/M0/VPZVaNHvf
huvgakTg62/zWm42E5Y+12BfxTFgx3q5hSxdi7V6zMqzRwU6tDzDNiH8vMKVhiJ9
XlP+11qb63bMuqxKX9/ynVnJRHJRnsGfNYYskRv/jgH59McK+UmOMYqCSyeC4bKj
0IV87I7LKxqxhFOna/C1lbXR6cXvAD+fSnhzUoJP7oFWv5k67w2SxBm3/fJ3euFN
LrLYxyd4EPTwrWc9CKMas8lz0uDQeBQGJkF45b38WxyfVJrh7RHsnFSELNZez6RL
npm692pxSAGDfb1cyuGnsU7iU3rAU2qkuQN6tK+VyG0Nz3GsTdh8rKKv2467vZ0C
AwEAAaNjMGEwHQYDVR0OBBYEFJmSuAtxL5IEL+L9XTWivgD9iVlqMB8GA1UdIwQY
MBaAFJmSuAtxL5IEL+L9XTWivgD9iVlqMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P
AQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQBXC5mSGdcwS8NCwj9p3ASoV+yH
l0ZO9Gn9uXQSZxjNFMKZteqijlbL0nDCNVsciJVYIvhSXLOC+HDCa0Z8B0VYM/pP
r7Vcpr9FyuJVwldawnw1MmVLIraTN9J21vYnMJyKr7sHT/hr/VIsc2vS/RcFD9mf
phMQDgZ19KHOyiQdLLh2MZWUJ/Efte0MiBIMBXzbgdaQP3/49cTlpCxbb3B3myI4
k02YGzL8/YCSrW9jER2JCCZLKtOJmOJjjUb+EdEEnegbZm8kMzt72d2ZjYmzP0t+
wjHLhAWPnV9KLeRBi4RrlX3BYuMesBaML3i+Xbitp3CQhW9YSVbnX2gXxYoY
-----END CERTIFICATE-----
''';

/// 根 CA + 自签证书（PEM）。
const String kCaSelfPem = r'''-----BEGIN CERTIFICATE-----
MIIDKTCCAhGgAwIBAgIUQTZNEDkdsRXoVMpgvM0bGq5vKnUwDQYJKoZIhvcNAQEL
BQAwHDEaMBgGA1UEAwwRTW92YSBUZXN0IFJvb3QgQ0EwHhcNMjYxMDAxMDExNzEx
WhcNMzYwOTI4MDExNzExWjAcMRowGAYDVQQDDBFNb3ZhIFRlc3QgUm9vdCBDQTCC
ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKmUnTGdwfh/M0/VPZVaNHvf
huvgakTg62/zWm42E5Y+12BfxTFgx3q5hSxdi7V6zMqzRwU6tDzDNiH8vMKVhiJ9
XlP+11qb63bMuqxKX9/ynVnJRHJRnsGfNYYskRv/jgH59McK+UmOMYqCSyeC4bKj
0IV87I7LKxqxhFOna/C1lbXR6cXvAD+fSnhzUoJP7oFWv5k67w2SxBm3/fJ3euFN
LrLYxyd4EPTwrWc9CKMas8lz0uDQeBQGJkF45b38WxyfVJrh7RHsnFSELNZez6RL
npm692pxSAGDfb1cyuGnsU7iU3rAU2qkuQN6tK+VyG0Nz3GsTdh8rKKv2467vZ0C
AwEAAaNjMGEwHQYDVR0OBBYEFJmSuAtxL5IEL+L9XTWivgD9iVlqMB8GA1UdIwQY
MBaAFJmSuAtxL5IEL+L9XTWivgD9iVlqMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0P
AQH/BAQDAgEGMA0GCSqGSIb3DQEBCwUAA4IBAQBXC5mSGdcwS8NCwj9p3ASoV+yH
l0ZO9Gn9uXQSZxjNFMKZteqijlbL0nDCNVsciJVYIvhSXLOC+HDCa0Z8B0VYM/pP
r7Vcpr9FyuJVwldawnw1MmVLIraTN9J21vYnMJyKr7sHT/hr/VIsc2vS/RcFD9mf
phMQDgZ19KHOyiQdLLh2MZWUJ/Efte0MiBIMBXzbgdaQP3/49cTlpCxbb3B3myI4
k02YGzL8/YCSrW9jER2JCCZLKtOJmOJjjUb+EdEEnegbZm8kMzt72d2ZjYmzP0t+
wjHLhAWPnV9KLeRBi4RrlX3BYuMesBaML3i+Xbitp3CQhW9YSVbnX2gXxYoY
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIDJzCCAg+gAwIBAgIUPYx3FmcJTBv/yu6NW1MNkhlVji0wDQYJKoZIhvcNAQEL
BQAwFTETMBEGA1UEAwwKc2VsZnNpZ25lZDAeFw0yNjEwMDEwMTE3MjVaFw0zNjA5
MjgwMTE3MjVaMBUxEzARBgNVBAMMCnNlbGZzaWduZWQwggEiMA0GCSqGSIb3DQEB
AQUAA4IBDwAwggEKAoIBAQC6mJEGkzRru7pFFX9M1zXqTKLFkWv2Dtk6xUX++pkr
jF+p7zQTRZ8tB/fhGExiZ9QbPqz6xlKusFSh1HYAn6o7LJ4T32AA45xJVIa+HQan
pNdcTyzQdDwz/vVybYBM7Eos7RK+KPZh8EEF1G61PXlroLo5owbmFhrgtJ3sIU5P
PCHIwpbnINOdH0b1mzp3+Gez+Tv5ppbERhsMFyR3qCjkxHTrm9YnNqGchAndb7w0
ifFA75MDMHQ2BrZTFLMXoCejJHXTO0NHuX3ZjeaFDxfS6lK6UqGXFi3Q1MMTWLe1
2pvaAkgQ33V/S6vseflpFSeBfph3cdNms6gV4ysyMsVnAgMBAAGjbzBtMB0GA1Ud
DgQWBBTpaqUW+pynTZaU+Jc7vtyC+Zd/+zAfBgNVHSMEGDAWgBTpaqUW+pynTZaU
+Jc7vtyC+Zd/+zAPBgNVHRMBAf8EBTADAQH/MBoGA1UdEQQTMBGCCWxvY2FsaG9z
dIcEfwAAATANBgkqhkiG9w0BAQsFAAOCAQEAK7phkMaPZ0wfOAZMvd4RZuEPY6X7
fcduhfaALjL9pWeCxgbpwuwvfu1rj6XE4yO3LDtuEjI/ZwcwW029FkEpZqSfLhxP
HAkvfPXMd1dfOKrbrmAqGeoMMRVHpDMmPH9ydGuCwiqc0taRYynf1+jSc7QRyZTk
JZ5jfPTSS3buaDp489jZvi+m9zGh/SqgEFqBeKrxfB/k5vKvMoUJFcvgHTCCA1+G
VL6zQ5ark+gm88xn7qksGw5P2DVqQFYkx3kiJDiTQai395KcLuPhyAYONvw/Kp2d
iZ8Z55TVh8/lh+FcNqHmLwNFUUdVrWvRk+KpJIIm/aA58sgu6RX4BeyUKA==
-----END CERTIFICATE-----
''';

/// 目标主机名（`--dart-define=HOST=localhost` 可改成主机名，默认直连 IP）。
const String kHost = String.fromEnvironment('HOST', defaultValue: '127.0.0.1');

/// 每个场景重复次数。
const int kReps = 3;

/// 拒绝场景的等待上限（超时即判 TIMEOUT，属 FAIL）。
const Duration kRejectWait = Duration(seconds: 15);

/// 可播场景要求播放到的位置。
const Duration kPlayTo = Duration(seconds: 5);

/// 输出一行。
void _out(String m) => print('TLSM $m');

/// 证书名到端口。
const Map<String, int> kCerts = {'valid': 9441, 'expired': 9442, 'mismatch': 9443, 'selfsigned': 9444};

/// 资源名到路径。
const Map<String, String> kRes = {'a_m4a': 'a.m4a', 'b_hls': 'hls/index.m3u8', 'c_hlsaes': 'enc/index.m3u8'};

/// 单次场景的运行序号。
int _seq = 0;

/// 跑一次场景，输出结果行。
Future<void> _once(String cfg, bool verify, String? ca, String cert, String res, int rep) async {
  final id = ++_seq;
  final events = <MovaReportEvent>[];
  final engine = createMovaEngine(
    audioOnly: true,
    tlsVerify: verify,
    tlsCaFile: ca,
    options: const MovaOpts(report: MovaReportConfig(qoe: true)),
    reporter: MovaCallbackReporter(events.add),
  );
  final t0 = DateTime.now();
  int ms(DateTime d) => d.difference(t0).inMilliseconds;
  int? readyMs, errMs;
  String? errText;
  final samples = <int>[];
  var last = 0;
  final subs = <StreamSubscription<Object?>>[
    engine.events.listen((e) {
      if (e is MovaReady && readyMs == null) readyMs = ms(DateTime.now());
      if (e is MovaErrorEvent && errMs == null) {
        errMs = ms(DateTime.now());
        errText = '${e.error}'.replaceAll('\n', ' ');
      }
    }),
    engine.progress.listen((p) {
      final v = p.position.inMilliseconds;
      if (v > last) {
        last = v;
        samples.add(v);
      }
    }),
  ];
  final beginEpoch = t0.millisecondsSinceEpoch;
  final url = 'https://$kHost:${kCerts[cert]}/r$id/${kRes[res]}';
  String? openErr;
  try {
    await engine.open(MovaSource(url));
  } catch (e) {
    openErr = '$e'.replaceAll('\n', ' ');
    errMs ??= ms(DateTime.now());
  }
  final deadline = t0.add(kRejectWait + const Duration(seconds: 6));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final ff = events.any((e) => e.name == MovaReportName.firstFrame);
    if (ff && last >= kPlayTo.inMilliseconds) break;
    if (errMs != null) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      break;
    }
    if (!ff && DateTime.now().isAfter(t0.add(kRejectWait))) break;
  }
  final endEpoch = DateTime.now().millisecondsSinceEpoch;
  for (final s in subs) {
    await s.cancel();
  }
  await engine.dispose();
  final ffEv = events.where((e) => e.name == MovaReportName.firstFrame);
  final ffMs = ffEv.isEmpty ? null : ms(ffEv.first.at);
  final errReports = events.where((e) => e.name == MovaReportName.error).map((e) => '${e.params}').join('|');
  _out('RES id=$id host=$kHost cfg=$cfg cert=$cert res=$res rep=$rep begin=$beginEpoch end=$endEpoch '
      'ready=$readyMs ff=$ffMs err=$errMs samples=${samples.length} lastPos=$last '
      'openErr=$openErr errText=$errText errRep=$errReports');
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// 主流程。
Future<void> _run() async {
  final dir = Directory.systemTemp.path;
  final caPath = '$dir/mova_tls_ca.pem';
  final caSelfPath = '$dir/mova_tls_ca_self.pem';
  await File(caPath).writeAsString(kCaPem);
  await File(caSelfPath).writeAsString(kCaSelfPem);
  _out('START ca=$caPath');
  final cfgs = <String, (bool, String?)>{
    'off': (false, null),
    'on_noca': (true, null),
    'on_ca': (true, caPath),
    'on_ca_self': (true, caSelfPath),
  };
  for (final c in cfgs.entries) {
    for (final cert in kCerts.keys) {
      for (final res in kRes.keys) {
        for (var r = 1; r <= kReps; r++) {
          await _once(c.key, c.value.$1, c.value.$2, cert, res, r);
        }
      }
    }
  }
  _out('ALL_DONE');
}
