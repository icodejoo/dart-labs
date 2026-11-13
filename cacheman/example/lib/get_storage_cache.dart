import 'package:cacheman/cacheman.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:get_storage/get_storage.dart';

/// App-owned get_storage adapter; copy this file into a consuming Flutter app.
/// 应用自有的 get_storage 适配器；可复制到使用方 Flutter 项目。
class GetStorageCache extends Cacheman {
  /// Uses the existing container and optional directory; preserves stored keys.
  /// 指定已有容器和可选目录，保留原有存储键。
  GetStorageCache({String container = 'cacheman', String? path, super.options})
    : _name = container,
      _directory = path,
      super.custom();

  /// Storage container name. / 存储容器名。
  final String _name;

  /// Optional storage directory. / 可选存储目录。
  final String? _directory;

  /// Lazy backend handle; same-name GetStorage instances share their first path.
  /// 惰性创建的后端句柄，同名 GetStorage 以首次路径为准。
  late final GetStorage box = GetStorage(_name, _directory);

  /// Initializes Flutter and loads the selected container. / 初始化 Flutter 并加载容器。
  @override
  Future<void> initRaw(CacheContext ctx) async {
    WidgetsFlutterBinding.ensureInitialized();
    await box.initStorage;
  }

  /// Reads from backend memory. / 读取后端内存。
  @override
  Object? getRaw(CacheContext ctx, String storageKey) =>
      box.read<Object?>(storageKey);

  /// Enumerates backend keys. / 枚举后端键。
  @override
  Iterable<String> keysRaw(CacheContext ctx) =>
      box.getKeys<Iterable<dynamic>>().map((key) => key.toString());

  /// Updates memory before returning the save Future. / 返回保存 Future 前更新内存。
  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) =>
      box.write(storageKey, value);

  /// Removes from memory before returning. / 返回前从内存删除。
  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) =>
      box.remove(storageKey);

  /// Clears the backend before returning. / 返回前清空后端。
  @override
  Future<void> clearRaw(CacheContext ctx) => box.erase();

  /// Shares one Hub per underlying box. / 每个底层 box 共用一个 Hub。
  @override
  Object get hubIdentity => box;

  /// Converts get_storage changes into keyed or whole-container notifications.
  /// 将 get_storage 变更转成按键或整库通知。
  @override
  VoidCallback? listenRaw(CacheContext ctx, void Function(String?) onChange) {
    Map<String, dynamic>? last;
    return box.listen(() {
      final changes = box.changes;
      final fresh = !identical(changes, last);
      last = changes;
      final key = fresh && changes.length == 1 ? changes.keys.first : null;
      onChange(
        key != null && key.isEmpty && box.getKeys<Iterable>().isEmpty
            ? null
            : key,
      );
    });
  }

  /// get_storage 2.1.1 notifies synchronously. / get_storage 2.1.1 同步通知。
  @override
  bool get syncNotificationsRaw => true;

  /// Updates memory without requesting a save. / 只更新内存，暂不请求保存。
  @override
  void setDeferredRaw(CacheContext ctx, String storageKey, String value) =>
      box.writeInMemory(storageKey, value);

  /// Requests persistence; get_storage does not expose disk acknowledgement.
  /// 请求保存；get_storage 不提供实际落盘确认。
  @override
  Future<void> flushRaw(CacheContext ctx) => box.save();
}
