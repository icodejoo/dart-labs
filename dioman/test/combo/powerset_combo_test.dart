// ignore_for_file: avoid_relative_lib_imports
// 组合层：powerset
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  test(
    '[Dioman.install] every non-empty subset of the 16 plugins (65535 combinations) returns '
    'the expected value on a plain success',
    () async {
      String? lastAuthHeader;
      final server = await TestServer.start((req) async {
        lastAuthHeader = req.headers.value(tkAuthorization2);
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({
          tkCode: 0,
          tkData: {tkV: 1},
          tkMessage: tkEmpty
        }));
        await req.response.close();
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      addTearDown(() => dio.close(force: true));

      final failures = <String, Object>{};
      final total = allMax;
      for (var mask = 1; mask <= total; mask++) {
        final name = describeSubset(mask);
        final handle = installSubset(dio, mask, TestTokens(tkT0));
        lastAuthHeader = null;
        try {
          final r = await dio
              .get<dynamic>('/base')
              .timeout(const Duration(seconds: 2));
          if (r.statusCode != 200) {
            failures[name] = 'unexpected status ${r.statusCode}';
          } else if (!matchesSuccessShape(mask, r.data)) {
            failures[name] = 'unexpected body ${r.data}';
          } else if (hasAuth(mask) && lastAuthHeader != tkBearerT0) {
            failures[name] =
                'auth installed but server saw Authorization: $lastAuthHeader';
          } else if (!hasAuth(mask) && lastAuthHeader != null) {
            failures[name] =
                'no auth but server still saw Authorization: $lastAuthHeader';
          }
        } catch (e) {
          failures[name] = e;
        } finally {
          handle.dispose();
        }
      }

      if (failures.isNotEmpty) {
        final sample = failures.entries
            .take(20)
            .map((e) => '${e.key}: ${e.value}')
            .join(tkEmpty9);
        fail('${failures.length}/$total combinations failed '
            '(showing up to 20):\n$sample');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );

  test(
    '[Dioman.install] every non-empty subset of the 13 plugins (8191 combinations) recovers '
    'correctly from a 500, a cache-populating round trip, and a 401 '
    'refresh+replay — paced to stay under the local ephemeral-port budget '
    '(see the file doc; this sweep takes several minutes)',
    () async {
      var attemptCount = 0;
      String? lastAuthHeader;
      final responseQueue = <int>[]; // statuses to serve, then default 200
      final server = await TestServer.start((req) async {
        attemptCount++;
        lastAuthHeader = req.headers.value(tkAuthorization2);
        final status =
            responseQueue.isNotEmpty ? responseQueue.removeAt(0) : 200;
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        if (status != 200) {
          req.response.headers.set(HttpHeaders.connectionHeader, tkClose);
        }
        final body = status == 200
            ? {
                tkCode: 0,
                tkData: {tkV: 1},
                tkMessage: tkEmpty
              }
            : {tkCode: 1, tkData: null, tkMessage: tkFail};
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      addTearDown(() => dio.close(force: true));

      final failures = <String, Object>{};
      // Core 13 only — bits 13-15 stay 0, so timeout/offline/breaker are never
      // installed here (see the file header for why they're excluded).
      final total = coreMax;

      for (var mask = 1; mask <= total; mask++) {
        final name = describeSubset(mask);
        final tm = TestTokens(tkT0);
        final handle = installSubset(dio, mask, tm);
        // Each retry/auth phase below opens ~2 real TCP connections (the
        // main dio reconnecting after a forced-close error response, plus
        // DiomanRetry's/DiomanAuth's own bare-Dio re-issue) that don't
        // become reusable until TIME_WAIT expires — see the file doc. Pace
        // by how many of those THIS mask actually opens, not a flat
        // per-mask delay, so masks with neither phase (the common case)
        // don't pay for it.
        var riskyConnections = 0;
        try {
          // --- retry: 500 then recovers -------------------------------
          if (hasRetry(mask)) {
            riskyConnections += 2;
            attemptCount = 0;
            responseQueue
              ..clear()
              ..add(500);
            final r = await dio
                .get<dynamic>('/retry')
                .timeout(const Duration(seconds: 2));
            if (r.statusCode != 200 || !matchesSuccessShape(mask, r.data)) {
              failures[name] = 'retry: unexpected result '
                  'status=${r.statusCode} data=${r.data}';
              continue;
            }
            if (attemptCount != 2) {
              failures[name] = 'retry: expected 2 attempts (fail then '
                  'retry), got $attemptCount';
              continue;
            }
          }

          // --- cache: 2 calls, hit iff DiomanKey is also present -------
          if (hasCache(mask)) {
            attemptCount = 0;
            responseQueue.clear();
            final c1 = await dio
                .get<dynamic>(tkCache2)
                .timeout(const Duration(seconds: 2));
            final c2 = await dio
                .get<dynamic>(tkCache2)
                .timeout(const Duration(seconds: 2));
            if (!matchesSuccessShape(mask, c1.data) ||
                !matchesSuccessShape(mask, c2.data)) {
              failures[name] =
                  'cache: unexpected body c1=${c1.data} c2=${c2.data}';
              continue;
            }
            final expectedAttempts = hasKey(mask) ? 1 : 2;
            if (attemptCount != expectedAttempts) {
              failures[name] = hasKey(mask)
                  ? 'cache+key: expected a cache hit (1 attempt), got $attemptCount'
                  : 'cache without key: expected NO cache hit (2 attempts, '
                      'per the documented no-op-without-key behavior), got $attemptCount';
              continue;
            }
          }

          // --- auth: 401 then refresh+replay — run LAST, mutates tm ----
          if (hasAuth(mask)) {
            riskyConnections += 2;
            attemptCount = 0;
            responseQueue
              ..clear()
              ..add(401);
            lastAuthHeader = null;
            final a = await dio
                .get<dynamic>('/auth')
                .timeout(const Duration(seconds: 2));
            if (a.statusCode != 200 || !matchesSuccessShape(mask, a.data)) {
              failures[name] = 'auth: unexpected result '
                  'status=${a.statusCode} data=${a.data}';
              continue;
            }
            if (attemptCount != 2) {
              failures[name] = 'auth: expected 2 attempts (401 then '
                  'replay), got $attemptCount';
              continue;
            }
            if (lastAuthHeader != tkBearerT1) {
              failures[name] =
                  'auth: expected replay to carry the refreshed token, '
                  'server saw Authorization: $lastAuthHeader';
              continue;
            }
            if (tm.accessToken != tkT1) {
              failures[name] =
                  'auth: token manager was not actually updated by onRefresh '
                  '(still ${tm.accessToken})';
              continue;
            }
          }
        } catch (e) {
          failures[name] = e;
        } finally {
          handle.dispose();
          // 25ms per real connection this mask opened — see the file doc
          // for the budget this targets. Runs even on failure/continue so
          // pacing holds regardless of outcome.
          if (riskyConnections > 0) {
            await Future<void>.delayed(
                Duration(milliseconds: riskyConnections * 25));
          }
        }
      }

      if (failures.isNotEmpty) {
        final sample = failures.entries
            .take(20)
            .map((e) => '${e.key}: ${e.value}')
            .join(tkEmpty9);
        fail('${failures.length}/$total combinations failed '
            '(showing up to 20):\n$sample');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
