// A simple in-memory DiomanCachePersist test double, standing in for a real
// durability technology (file/sqlite/Hive/get_storage/...) that dioman
// itself deliberately never ships. Kept as a plain Map so tests can assert
// on its contents directly (a real persist implementation would instead
// round-trip through disk).
import 'package:dioman/dioman.dart';

class FakeCachePersist implements DiomanCachePersist {
  final store = <String, dynamic>{};

  @override
  dynamic read(String key) => store[key];

  @override
  Future<void> write(String key, Map<String, dynamic> value) async {
    store[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    store.remove(key);
  }

  @override
  Future<void> erase() async {
    store.clear();
  }
}
