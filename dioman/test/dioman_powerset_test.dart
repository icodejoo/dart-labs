// Power-set correctness sweep for Dioman.install's 13 plugins.
//
// Unlike dioman_combinations_test.dart's hand-picked pairwise/3-way tests
// (which assert SPECIFIC cross-plugin behavior for the 6 stateful plugins),
// this file asserts the RETURNED VALUE is what it should be — not just
// "didn't throw" — across two sweeps:
//
//   1. Baseline sweep — ALL 2^13-1 = 8191 non-empty combinations of the 13
//      plugins, each firing one plain-success GET (`/base`): status 200;
//      body is the raw envelope, unless DiomanNormalize is present (then
//      unwrapped); server sees `Authorization: Bearer t0` iff DiomanAuth is
//      present. This only exercises the happy path, so it never opens more
//      than one real TCP connection for the whole sweep (see the adapter
//      note below) — safe to run exhaustively.
//
//   2. Exception-path sweep — ALL 8191 combinations again, each additionally
//      running, for the plugins it includes:
//        - retry (`/retry`, iff DiomanRetry): first attempt 500, second
//          (DiomanRetry's own bare-Dio re-issue) 200 → 2 server attempts,
//          final result is the RAW envelope always (the re-issue never
//          reaches DiomanNormalize — a documented trade-off, see
//          retry_plugin.dart's class doc — regardless of whether normalize
//          is in the combination).
//        - cache (`/cache`, iff DiomanCache): two calls to the same path →
//          iff DiomanKey is ALSO present, the second is a real cache hit
//          (1 server attempt total); DiomanCache is a documented no-op
//          without DiomanKey, so without it the second call must NOT hit
//          (2 attempts). A hit's data still gets the mask's normal success
//          shape (unwrapped iff normalize present) — a cache hit's resolve
//          explicitly asks to still run onResponse of later interceptors.
//        - auth (`/auth`, iff DiomanAuth): first attempt 401, second
//          (DiomanAuth's refresh+replay via its own bare Dio) 200 → 2
//          server attempts, the replay carries the REFRESHED token
//          (`Bearer t1`), the token manager's stored token actually changed
//          to `t1`, and — same bare-Dio trade-off as retry — the final
//          result is always the RAW envelope regardless of normalize.
//
//      Why this sweep is PACED (deliberately slow), unlike sweep 1:
//      DiomanRetry's/DiomanAuth's re-issues go through their OWN bare,
//      interceptor-less `Dio()` (see their class docs) — a genuine extra TCP
//      connection per occurrence that can't be avoided from here, on top of
//      the main dio reconnecting after the 500/401 (which must close the
//      connection — see the adapter note below). That's ~2 real connections
//      for every one of the ~4096 masks with retry, and another ~2 for every
//      one of the ~4096 masks with auth: ~16k real connections total. A
//      closed TCP connection's local (client-side) port doesn't become
//      reusable the instant it closes — it sits in TIME_WAIT for ~120s
//      (Windows default) before the OS frees it. Running the loop as fast
//      as possible — even though it's already fully sequential, one mask
//      strictly after the previous — opens far more than the ~14k
//      available ephemeral ports (`netsh int ipv4 show dynamicport tcp`)
//      within that 120s window, so the pool empties before old ports can
//      recycle: sequential ordering alone doesn't bound the RATE. This loop
//      instead adds an explicit delay after every mask that actually opened
//      extra connections, sized to keep the sustained rate comfortably
//      under what TIME_WAIT can recycle — trading wall-clock time (this
//      sweep takes several minutes) for being able to run the real,
//      un-scoped 8191-combination exception-path check at all.
//
// Does not assert deeper interaction behavior (concurrent dedup,
// cancellation, ...) — that's what the targeted pairwise tests in
// dioman_combinations_test.dart are for.
// Failures are collected across each sweep and reported together at the
// end, so one bad combination doesn't hide the rest.
//
// Uses a REAL loopback HttpServer via test_server.dart, per this project's
// convention of exercising the actual dio transport rather than a fake
// adapter. Its handler only sets `Connection: close` on a non-200 response
// (same reasoning as the shared respondJson helper: dio doesn't necessarily
// drain a non-2xx body before it's done with the request, so a kept-alive
// connection could otherwise hand the NEXT, unrelated request leftover
// bytes from this one) — every other response stays keep-alive, so the
// (much more frequent) plain-success sweep reuses one connection instead of
// opening a fresh one per request.
import 'support/fake_cache_persist.dart';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import 'support/test_server.dart';

class _MutableTokenManager implements DiomanTokenManager {
  _MutableTokenManager(this._access);
  String? _access;
  @override
  String? get accessToken => _access;
  @override
  String? get refreshToken => 'refresh';
  @override
  bool get canRefresh => true;
  @override
  void clear() => _access = null;
  void set(String? v) => _access = v;
}

const _names = [
  'envs', 'repath', 'filter', 'key', 'cache', 'share', 'mock', //
  'cancel', 'loading', 'auth', 'retry', 'log', 'normalize',
];

bool _hasBit(int mask, int bit) => (mask & (1 << bit)) != 0;
bool _hasKey(int mask) => _hasBit(mask, 3);
bool _hasCache(int mask) => _hasBit(mask, 4);
bool _hasAuth(int mask) => _hasBit(mask, 9);
bool _hasRetry(int mask) => _hasBit(mask, 10);
bool _hasNormalize(int mask) => _hasBit(mask, 12);

/// Installs the subset of the 13 plugins selected by [mask]'s bits (bit i
/// ↔ [_names][i]) — [Dioman.install] slots them into the canonical order
/// regardless of which bits are set. `retry`/`auth` are configured to
/// recover in exactly 1 extra attempt so the exception-path phases below
/// stay deterministic and fast.
DiomanHandle _install(Dio dio, int mask, _MutableTokenManager tm) {
  bool has(int bit) => _hasBit(mask, bit);
  return Dioman.install(
    dio,
    envs: has(0) ? DiomanEnvs(const []) : null,
    repath: has(1) ? DiomanRepath() : null,
    filter: has(2) ? const DiomanFilter() : null,
    key: has(3) ? const DiomanKey() : null,
    cache: has(4) ? DiomanCache(persist: FakeCachePersist(), cachePolicy: DiomanCachePolicy.memo, ) : null,
    share: has(5) ? DiomanShare(policy: DiomanSharePolicy.start) : null,
    mock: has(6) ? DiomanMock(enabled: false) : null,
    cancel: has(7) ? DiomanCancel() : null,
    loading: has(8) ? DiomanLoading(onChanged: (_) {}) : null,
    auth: has(9)
        ? DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async => tm.set('t1'),
            onAccessExpired: (_, __) async {},
          )
        : null,
    retry: has(10) ? DiomanRetry(max: 1, delay: (_, __, ___, ____) => Duration.zero) : null,
    log: has(11) ? DiomanLog(writer: (m, {error}) {}) : null,
    normalize: has(12) ? const DiomanNormalize() : null,
  );
}

String _describe(int mask) => [
      for (var i = 0; i < _names.length; i++)
        if ((mask & (1 << i)) != 0) _names[i],
    ].join('+');

/// True if [data] is the envelope's inner payload (`{'v': 1}`) — the shape
/// DiomanNormalize unwraps a success envelope to.
bool _isUnwrapped(dynamic data) =>
    data is Map && data.length == 1 && data['v'] == 1;

/// True if [data] is the raw, un-normalized success envelope.
bool _isRawEnvelope(dynamic data) =>
    data is Map &&
    data['code'] == 0 &&
    data['message'] == '' &&
    data['data'] is Map &&
    (data['data'] as Map)['v'] == 1;

/// The shape a successful response's `.data` must have for [mask] — raw
/// envelope, or unwrapped if DiomanNormalize is in the combination. Used
/// for the baseline and cache-hit assertions, since both flow through
/// normalize (if installed) exactly like a plain response does.
bool _matchesSuccessShape(int mask, dynamic data) =>
    _hasNormalize(mask) ? _isUnwrapped(data) : _isRawEnvelope(data);

void main() {
  test(
    'every non-empty subset of the 13 plugins (8191 combinations) returns '
    'the expected value on a plain success',
    () async {
      String? lastAuthHeader;
      final server = await TestServer.start((req) async {
        lastAuthHeader = req.headers.value('authorization');
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(
            jsonEncode({'code': 0, 'data': {'v': 1}, 'message': ''}));
        await req.response.close();
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      addTearDown(() => dio.close(force: true));

      final failures = <String, Object>{};
      final total = (1 << _names.length) - 1;
      for (var mask = 1; mask <= total; mask++) {
        final name = _describe(mask);
        final handle = _install(dio, mask, _MutableTokenManager('t0'));
        lastAuthHeader = null;
        try {
          final r = await dio
              .get<dynamic>('/base')
              .timeout(const Duration(seconds: 2));
          if (r.statusCode != 200) {
            failures[name] = 'unexpected status ${r.statusCode}';
          } else if (!_matchesSuccessShape(mask, r.data)) {
            failures[name] = 'unexpected body ${r.data}';
          } else if (_hasAuth(mask) && lastAuthHeader != 'Bearer t0') {
            failures[name] =
                'auth installed but server saw Authorization: $lastAuthHeader';
          } else if (!_hasAuth(mask) && lastAuthHeader != null) {
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
            .join('\n');
        fail('${failures.length}/$total combinations failed '
            '(showing up to 20):\n$sample');
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'every non-empty subset of the 13 plugins (8191 combinations) recovers '
    'correctly from a 500, a cache-populating round trip, and a 401 '
    'refresh+replay — paced to stay under the local ephemeral-port budget '
    '(see the file doc; this sweep takes several minutes)',
    () async {
      var attemptCount = 0;
      String? lastAuthHeader;
      final responseQueue = <int>[]; // statuses to serve, then default 200
      final server = await TestServer.start((req) async {
        attemptCount++;
        lastAuthHeader = req.headers.value('authorization');
        final status =
            responseQueue.isNotEmpty ? responseQueue.removeAt(0) : 200;
        req.response.statusCode = status;
        req.response.headers.contentType = ContentType.json;
        if (status != 200) {
          req.response.headers.set(HttpHeaders.connectionHeader, 'close');
        }
        final body = status == 200
            ? {'code': 0, 'data': {'v': 1}, 'message': ''}
            : {'code': 1, 'data': null, 'message': 'fail'};
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      addTearDown(server.close);

      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      addTearDown(() => dio.close(force: true));

      final failures = <String, Object>{};
      final total = (1 << _names.length) - 1;

      for (var mask = 1; mask <= total; mask++) {
        final name = _describe(mask);
        final tm = _MutableTokenManager('t0');
        final handle = _install(dio, mask, tm);
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
          if (_hasRetry(mask)) {
            riskyConnections += 2;
            attemptCount = 0;
            responseQueue
              ..clear()
              ..add(500);
            final r = await dio
                .get<dynamic>('/retry')
                .timeout(const Duration(seconds: 2));
            if (r.statusCode != 200 || !_isRawEnvelope(r.data)) {
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
          if (_hasCache(mask)) {
            attemptCount = 0;
            responseQueue.clear();
            final c1 = await dio
                .get<dynamic>('/cache')
                .timeout(const Duration(seconds: 2));
            final c2 = await dio
                .get<dynamic>('/cache')
                .timeout(const Duration(seconds: 2));
            if (!_matchesSuccessShape(mask, c1.data) ||
                !_matchesSuccessShape(mask, c2.data)) {
              failures[name] =
                  'cache: unexpected body c1=${c1.data} c2=${c2.data}';
              continue;
            }
            final expectedAttempts = _hasKey(mask) ? 1 : 2;
            if (attemptCount != expectedAttempts) {
              failures[name] = _hasKey(mask)
                  ? 'cache+key: expected a cache hit (1 attempt), got $attemptCount'
                  : 'cache without key: expected NO cache hit (2 attempts, '
                      'per the documented no-op-without-key behavior), got $attemptCount';
              continue;
            }
          }

          // --- auth: 401 then refresh+replay — run LAST, mutates tm ----
          if (_hasAuth(mask)) {
            riskyConnections += 2;
            attemptCount = 0;
            responseQueue
              ..clear()
              ..add(401);
            lastAuthHeader = null;
            final a = await dio
                .get<dynamic>('/auth')
                .timeout(const Duration(seconds: 2));
            if (a.statusCode != 200 || !_isRawEnvelope(a.data)) {
              failures[name] = 'auth: unexpected result '
                  'status=${a.statusCode} data=${a.data}';
              continue;
            }
            if (attemptCount != 2) {
              failures[name] = 'auth: expected 2 attempts (401 then '
                  'replay), got $attemptCount';
              continue;
            }
            if (lastAuthHeader != 'Bearer t1') {
              failures[name] =
                  'auth: expected replay to carry the refreshed token, '
                  'server saw Authorization: $lastAuthHeader';
              continue;
            }
            if (tm.accessToken != 't1') {
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
            .join('\n');
        fail('${failures.length}/$total combinations failed '
            '(showing up to 20):\n$sample');
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
