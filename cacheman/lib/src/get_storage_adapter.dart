import 'package:get_storage/get_storage.dart';

import 'interface.dart';

/// Adapts a [GetStorage] container to the internal [Store] contract.
///
/// get_storage's `read`/`write`/`remove` are synchronous against its
/// in-memory map (the disk flush happens in the background, debounced) — so
/// this adapter's [Store] methods are synchronous too, and the flush Future
/// is fire-and-forget with an attached error handler.
///
/// **Real difference from the sibling `@codejoo/storage` TS project**: TS's
/// `force` option retries synchronously (persist throws → purge expired →
/// retry once) because `localStorage.setItem` fails *synchronously* on
/// quota. get_storage's flush failure surfaces *asynchronously*, decoupled
/// from any single `write()` call (it writes the whole current map, not one
/// key) — there's no reliable synchronous failure signal to retry against.
/// [onError] is still called on an eventual flush failure, but there is no
/// purge-and-retry step here.
///
/// 把 [GetStorage] container 适配成内部的 [Store] 契约。
///
/// get_storage 的 `read`/`write`/`remove` 对它自己的内存态是同步的（落盘是
/// 后台防抖异步做的）——所以这个适配器的 [Store] 方法也都是同步的，flush 的
/// Future 是即发即弃、挂了错误处理的。
///
/// **跟姊妹 TS 项目 `@codejoo/storage` 的真实差异**：TS 的 `force` 选项是同步
/// 重试的（persist 抛错 → 清过期 → 重试一次），因为 `localStorage.setItem`
/// 在配额超限时是**同步**失败的。get_storage 的落盘失败是**异步**冒出来的，
/// 且跟某一次具体的 `write()` 调用脱钩（它落盘的是当前整个 map，不是单个
/// key）——没有可靠的同步失败信号可供重试。[onError] 仍会在落盘最终失败时
/// 触发，但这里没有"清过期后重试"这一步。
class GetStorageAdapter implements Store {
  GetStorageAdapter(this._gs, {this.onError});

  final GetStorage _gs;

  /// Called if a background disk flush eventually fails. Not synchronous —
  /// see the class doc.
  ///
  /// 后台落盘最终失败时触发。不是同步的——见类文档。
  final CachemanOnError? onError;

  void _reportOnError(String key, Object error, StackTrace stack) {
    final cb = onError;
    if (cb != null) {
      cb(key, error);
    } else {
      // ignore: avoid_print
      print('[cacheman] background flush failed for "$key": $error');
    }
  }

  @override
  String? get(String key) {
    final v = _gs.read<dynamic>(key);
    if (v == null) return null;
    // 本库只经这个 adapter 写入字符串；若读到非字符串，说明外部代码往同一个
    // container 里塞了别的东西——视为不认识的数据，按缺失处理，不抛异常。
    return v is String ? v : null;
  }

  @override
  void set(String key, String value) {
    _gs.write(key, value).catchError((Object e, StackTrace s) {
      _reportOnError(key, e, s);
    });
  }

  @override
  void remove(String key) {
    _gs.remove(key).catchError((Object e, StackTrace s) {
      _reportOnError(key, e, s);
    });
  }

  @override
  void clear() {
    _gs.erase().catchError((Object e, StackTrace s) {
      _reportOnError('*', e, s);
    });
  }

  @override
  List<String> keys() => _gs.getKeys<Iterable<dynamic>>().map((k) => k.toString()).toList(growable: false);

  @override
  String? key(int index) {
    final ks = keys();
    if (index < 0 || index >= ks.length) return null;
    return ks[index];
  }

  @override
  int get length => keys().length;
}
