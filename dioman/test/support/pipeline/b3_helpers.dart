import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'fake_clock.dart';
import 'helpers.dart';

/// B3 请求路径。
const b3Path = '/b3';

/// B3 网络路由。
const b3Route = 'GET:$b3Path';

/// 初始凭证。
const b3Old = b3ValueOld;

/// 刷新后的凭证。
const b3Fresh = 'fresh';

/// 凭证头名称。
const b3Header = 'Authorization';

/// 单个虚拟时间单位。
const b3Tick = Duration(seconds: 1);

/// 可观察清理次数的凭证存储。
class TestTokens implements DiomanTokenManager {
  /// 初始化凭证。
  TestTokens([this.accessToken = b3Old]);

  /// 当前凭证。
  @override
  String? accessToken;

  /// 刷新凭证。
  @override
  String? refreshToken;

  /// 清会话次数。
  int clears = 0;

  /// 原子写入两个凭证。
  @override
  void setTokens({required String accessToken, String? refreshToken}) {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  /// 清空存储。
  @override
  void clear() {
    clears++;
    accessToken = null;
    refreshToken = null;
  }
}

/// 清空事件和微任务，使强制异步的 onRefresh 可观察。
Future<void> b3Turn() async {
  await Future<void>(() {});
  await flush();
}

/// 驱动纯假时钟请求直到完成，不依赖真实等待。
Future<T> b3Finish<T>(Future<T> pending, FakeClock clock) async {
  var done = false;
  pending.then<void>((_) {
    done = true;
  }, onError: (Object e, StackTrace s) {
    done = true;
  });
  for (var i = 0; i < 200 && !done; i++) {
    await b3Turn();
    clock.elapse(const Duration(seconds: 3));
  }
  return pending;
}

/// 默认刷新为 fresh 的鉴权配置。
DiomanAuth<Result> b3Auth(
  TestTokens tokens, {
  DiomanAuthRefresh? refresh,
  DiomanAuthNotice? expired,
  DiomanAuthNotice? denied,
  DiomanAuthFailure? failure,
  DiomanAuthReady? ready,
  bool Function(DiomanRequest)? protected,
  DateTime? Function(String)? expiresAt,
}) =>
    DiomanAuth<Result>(
        tokenManager: tokens,
        onRefresh: refresh ?? (tm, r) => tm.setTokens(accessToken: b3Fresh),
        onAccessExpired: expired ?? (tm, r) {},
        onAccessDenied: denied,
        onFailure: failure,
        ready: ready,
        isProtected: protected,
        expiresAt: expiresAt);

/// 原地修改嵌套请求体，检验 I7 真实深克隆。
class B3Transformer extends SyncTransformer {
  /// 修改后沿用 Dio 默认编码。
  @override
  Future<String> transformRequest(RequestOptions options) {
    final data = options.data as Map;
    final item = (data[b3ValueItems] as List).single as Map;
    item[b3ValueN] = (item[b3ValueN] as int) + 1;
    return super.transformRequest(options);
  }
}

/// B3 共用字面量：。
const b3Value = '  ';

/// B3 共用字面量：2。
const b3Value2 = '2';

/// B3 共用字面量：224。
const b3Value224 = '-2';

/// B3 共用字面量：Bad。
const b3ValueBad = 'bad';

/// B3 共用字面量：Code。
const b3ValueCode = 'code';

/// B3 共用字面量：Custom。
const b3ValueCustom = 'custom';

/// B3 共用字面量：Data。
const b3ValueData = 'data';

/// B3 共用字面量：Delay。
const b3ValueDelay = 'delay';

/// B3 共用字面量：Denied。
const b3ValueDenied = 'denied';

/// B3 共用字面量：Due。
const b3ValueDue = 'due';

/// B3 共用字面量：Empty。
const b3ValueEmpty = '';

/// B3 共用字面量：Expired。
const b3ValueExpired = 'expired';

/// B3 共用字面量：Failure。
const b3ValueFailure = 'failure';

/// B3 共用字面量：Future。
const b3ValueFuture = 'future';

/// B3 共用字面量：Gate。
const b3ValueGate = 'gate';

/// B3 共用字面量：Get。
const b3ValueGet = 'GET';

/// B3 共用字面量：Internal。
const b3ValueInternal = 'internal';

/// B3 共用字面量：Invalid。
const b3ValueInvalid = 'invalid';

/// B3 共用字面量：Items。
const b3ValueItems = 'items';

/// B3 共用字面量：Jitter。
const b3ValueJitter = 'jitter';

/// B3 共用字面量：Key。
const b3ValueKey = 'key';

/// B3 共用字面量：N。
const b3ValueN = 'n';

/// B3 共用字面量：Notice。
const b3ValueNotice = 'notice';

/// B3 共用字面量：Null。
const b3ValueNull = 'null';

/// B3 共用字面量：Old。
const b3ValueOld = 'old';

/// B3 共用字面量：Open。
const b3ValueOpen = 'open';

/// B3 共用字面量：Post。
const b3ValuePost = 'post';

/// B3 共用字面量：Post5。
const b3ValuePost5 = 'POST';

/// B3 共用字面量：Protected。
const b3ValueProtected = 'protected';

/// B3 共用字面量：Ready。
const b3ValueReady = 'ready';

/// B3 共用字面量：Refresh。
const b3ValueRefresh = 'refresh';

/// B3 共用字面量：Replay。
const b3ValueReplay = 'replay';

/// B3 共用字面量：Result。
const b3ValueResult = 'result';

/// B3 共用字面量：Should。
const b3ValueShould = 'should';

/// B3 共用字面量：Thu01Jan1970000002Gmt。
const b3ValueThu01Jan1970000002Gmt = 'Thu, 01 Jan 1970 00:00:02 GMT';

/// B3 共用字面量：Trip。
const b3ValueTrip = 'trip';

/// B3 共用字面量：Unauthenticated。
const b3ValueUnauthenticated = 'unauthenticated';

/// B3 共用字面量：Wed31Dec1969235959Gmt。
const b3ValueWed31Dec1969235959Gmt = 'Wed, 31 Dec 1969 23:59:59 GMT';

/// B3 共用字面量：Yes。
const b3ValueYes = 'yes';
