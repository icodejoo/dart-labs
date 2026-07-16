/// 数据 Store（实时刷新）。
///
/// 管理当前靴的局结果，对外提供 [RoadmapStore.setResults] / [RoadmapStore.append] /
/// [RoadmapStore.patch] 三种更新路径。只有 append 触发动画语义；setResults 和
/// patch 直接刷新。同一微任务内的多次 append 合并为一次通知（防推送风暴）。
/// 移植自 `src/core/store.ts`。
library;

import 'dart:async';

import 'emitter.dart';
import 'types.dart';

/// 更新类型。
enum UpdateKind {
  /// 全量替换（轮询/重连对账）。
  full,

  /// 追加一局（推送正常路径，唯一触发动画的入口）。
  append,

  /// 修正历史某局。
  patch,
}

/// Store 变更事件载荷。
class ChangeEvent {
  /// 更新类型。
  final UpdateKind kind;

  /// 当前完整结果列表（只读快照）。
  final List<RawResult> results;

  /// append 时为新追加的那一局，其他类型为 null。
  final RawResult? appended;

  const ChangeEvent({required this.kind, required this.results, this.appended});
}

/// 乱序/跳号回调（由外部拉全量后 [RoadmapStore.setResults] 对账）。
typedef OutOfSyncCallback = void Function(int expected, int actual);

/// 数据 Store。
class RoadmapStore {
  List<RawResult> _results = [];
  final _emitter = Emitter<ChangeEvent>();
  final OutOfSyncCallback? _onOutOfSync;

  bool _pendingFlush = false;
  RawResult? _pendingLastAppended;

  RoadmapStore({OutOfSyncCallback? onOutOfSync}) : _onOutOfSync = onOutOfSync;

  /// 全量替换结果（轮询/重连对账）。不播动画，直接刷新。
  void setResults(List<RawResult> results) {
    _results = List.of(results);
    _emitter.emit(ChangeEvent(kind: UpdateKind.full, results: List.of(_results)));
  }

  /// 追加一局（推送正常路径，唯一触发插入动画的入口）。
  ///
  /// 要求 `result.no == last.no + 1`，否则不入库并调用 [OutOfSyncCallback]。
  /// 同一微任务内多次 append 合并为一次通知。
  void append(RawResult result) {
    final last = _results.isNotEmpty ? _results.last : null;
    final expected = last != null ? last.no + 1 : 1;
    if (result.no != expected) {
      _onOutOfSync?.call(expected, result.no);
      return;
    }
    _results = [..._results, result];
    _scheduleFlush(result);
  }

  /// 修正历史某局（不播动画）。
  void patch(int no, RawResult result) {
    final idx = _results.indexWhere((r) => r.no == no);
    if (idx == -1) return;
    _results = [..._results.sublist(0, idx), result, ..._results.sublist(idx + 1)];
    _emitter.emit(ChangeEvent(kind: UpdateKind.patch, results: List.of(_results)));
  }

  /// 获取当前结果列表的只读快照。
  List<RawResult> getResults() => List.unmodifiable(_results);

  /// 订阅数据变更，返回取消订阅函数。
  void Function() subscribe(Listener<ChangeEvent> cb) => _emitter.on(cb);

  /// 安排微任务冲刷（已安排则跳过，下一微任务只执行一次）。
  void _scheduleFlush(RawResult appended) {
    _pendingLastAppended = appended;
    if (_pendingFlush) return;
    _pendingFlush = true;
    scheduleMicrotask(() {
      _pendingFlush = false;
      final last = _pendingLastAppended;
      _pendingLastAppended = null;
      _emitter.emit(ChangeEvent(kind: UpdateKind.append, results: List.of(_results), appended: last));
    });
  }
}

/// 创建数据 Store 实例。
///
/// ```dart
/// final store = createStore(onOutOfSync: (exp, act) => print('out of sync $exp $act'));
/// store.subscribe((e) { if (e.kind == UpdateKind.append) playAnimation(e.appended!); });
/// store.setResults(shoe.results);
/// ```
RoadmapStore createStore({OutOfSyncCallback? onOutOfSync}) => RoadmapStore(onOutOfSync: onOutOfSync);
