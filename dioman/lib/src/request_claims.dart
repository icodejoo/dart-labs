// 内部文件：不从 lib/dioman.dart 导出，仅供 share/auth/retry/cancel 协作。
import 'package:dio/dio.dart';

/// extra 键：一次逻辑请求上的"下游结算认领"登记簿。
const kClaimsKey = 'dioman:claims';

/// extra 键：该请求是 share 的 follower / 落败者，结果由 leader 结算，
/// 不得再自行恢复（重试/刷新重放）。
const kJoinedKey = 'dioman:share:joined';

/// 一次逻辑请求上的"结算认领"登记簿，按插件实例身份登记。
///
/// 会改写请求最终结果的下游插件（auth/retry）在 onRequest 认领，交出结果时
/// 注销；全部注销后才算"结果最终确定"，此时统一触发 [onFinal]（share 用来结算
/// 共享 entry）和 [whenDrained] 登记的回调（cancel 用来结束 token 追踪）。
/// 责任跟着请求走，不依赖插件级计数，插件移除/重绑后不会留下悬空登记。
class RequestClaims {
  final _owners = <Object>{};
  final _drained = <void Function()>[];
  bool _finished = false;

  /// 结果最终确定时的回调，参数二选一；由 share 在创建登记簿时设置。
  /// 返回非 null 表示该请求在 share 仲裁中落败，值是等待胜出结果的 Future
  /// （已绑定本请求），交出结果的一方应改为交付它，见 [loser]。
  Future<Response<dynamic>>? Function(
      Response<dynamic>? response, DioException? error)? onFinal;

  /// 预检：该请求此刻是否已在 share 仲裁中出局（end 被取代、race 已有胜者）。
  /// 返回等待胜出结果的 Future，未出局返回 null；由 share 设置。恢复成功的一方
  /// 在花力气走下游处理之前据此改交付胜出结果。
  Future<Response<dynamic>>? Function()? checkLoser;

  /// 结束时 [onFinal] 判定该请求落败得到的 Future，未落败为 null。
  Future<Response<dynamic>>? loser;

  /// 是否已有认领者尚未交出结果。
  bool get hasOwners => _owners.isNotEmpty;

  /// 是否已经结束（结果已确定，回调已触发）。
  bool get isFinished => _finished;

  /// 登记 [owner] 的结算责任；已结束则忽略。
  void add(Object owner) {
    if (!_finished) _owners.add(owner);
  }

  /// 注销 [owner] 的认领。若它是最后一个认领者，则以 [response]/[error]
  /// 作为最终结果结束。返回是否因此结束。
  bool release(Object owner, {Response<dynamic>? response, DioException? error}) {
    if (!_owners.remove(owner) || _owners.isNotEmpty) return false;
    return _finish(response, error);
  }

  /// 注销 [owner]（可以不是认领者，如 share 自己恢复时）；此后若已无认领者，
  /// 就以 [response]/[error] 结束。已结束则返回 false。
  bool settle(Object owner, {Response<dynamic>? response, DioException? error}) {
    _owners.remove(owner);
    if (_owners.isNotEmpty) return false;
    return _finish(response, error);
  }

  /// 无视剩余认领者，直接以 [response]/[error] 结束（恢复成功后终结链路时用）。
  /// 已结束则返回 false。
  bool finish({Response<dynamic>? response, DioException? error}) {
    _owners.clear();
    return _finish(response, error);
  }

  /// 登记"结束时"回调；已结束则立刻执行。
  void whenDrained(void Function() callback) {
    if (_finished) {
      callback();
    } else {
      _drained.add(callback);
    }
  }

  bool _finish(Response<dynamic>? response, DioException? error) {
    if (_finished) return false;
    _finished = true;
    final fin = onFinal;
    if (fin != null && (response != null || error != null)) {
      loser = fin(response, error);
    }
    for (final cb in _drained) {
      cb();
    }
    _drained.clear();
    return true;
  }
}

/// 取 [opts] 上的登记簿，没有则返回 null。
RequestClaims? claimsOf(RequestOptions opts) {
  final v = opts.extra[kClaimsKey];
  return v is RequestClaims ? v : null;
}

/// 为 [opts] 认领结算责任：登记簿不存在或上一轮已结束时新建一个。
void claimRequest(RequestOptions opts, Object owner) {
  var claims = claimsOf(opts);
  if (claims == null || claims.isFinished) {
    claims = RequestClaims();
    opts.extra[kClaimsKey] = claims;
  }
  claims.add(owner);
}

/// 注销 [owner] 在 [opts] 上的认领，见 [RequestClaims.release]。
void releaseClaim(
  RequestOptions opts,
  Object owner, {
  Response<dynamic>? response,
  DioException? error,
}) {
  claimsOf(opts)?.release(owner, response: response, error: error);
}

/// 注销 [owner] 的认领并交出最终结果，同 [releaseClaim]。若因此结束且该请求在
/// share 仲裁中落败，返回等待胜出结果的 Future（调用方应交付它而不是自己的
/// 结果）；否则返回 null。
Future<Response<dynamic>>? releaseClaimArbitrated(
  RequestOptions opts,
  Object owner, {
  Response<dynamic>? response,
  DioException? error,
}) {
  final claims = claimsOf(opts);
  if (claims == null) return null;
  return claims.release(owner, response: response, error: error)
      ? claims.loser
      : null;
}

/// 复制 [r] 并绑定到 [own]：data 引用不深拷贝，其余字段独立，调用方改自己的
/// Response（如 normalize 替换 data）不会影响别人。
Response<dynamic> copyResponse(Response<dynamic> r, RequestOptions own) =>
    Response<dynamic>(
      data: r.data,
      requestOptions: own,
      statusCode: r.statusCode,
      statusMessage: r.statusMessage,
      isRedirect: r.isRedirect,
      redirects: List.of(r.redirects),
      extra: Map.of(r.extra),
      headers: Headers.fromMap({
        for (final e in r.headers.map.entries) e.key: List<String>.of(e.value),
      }),
    );

/// 复制 [e] 并绑定到 [own]，内含的 response 同样改绑。
DioException copyError(Object e, RequestOptions own) {
  if (e is! DioException) return DioException(requestOptions: own, error: e);
  final resp = e.response;
  return DioException(
    requestOptions: own,
    response: resp == null ? null : copyResponse(resp, own),
    type: e.type,
    error: e.error,
    stackTrace: e.stackTrace,
    message: e.message,
  );
}

/// 该请求是否已被 share 判为 follower / 落败者（结果由 leader 结算）。
bool isJoined(RequestOptions opts) => opts.extra[kJoinedKey] == true;
