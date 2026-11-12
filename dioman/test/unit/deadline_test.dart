import 'package:dio/dio.dart';
import 'package:dioman/src/context_state.dart';
import 'package:test/test.dart';

/// 用户取消的原因。
const _userReason = 'user';

/// 验证内核到期与首次取消的状态原语。
void main() {
  test('[DiomanCall.deadline] 截止原语保留首次用户取消', () {
    final state = DiomanContextState(CancelToken());
    state.cancel(_userReason);
    state.expireDeadline();
    expect(state.deadlineExpired, isFalse);
    expect(state.token.cancelError?.error, _userReason);
    state.dispose();
  });
}
