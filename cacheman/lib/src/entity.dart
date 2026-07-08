import 'dart:convert';

/// The envelope every write is wrapped in (skipped entirely in `raw` mode).
///
/// 每次写入包的信封（`raw` 模式整个跳过）。
class CacheEntity {
  CacheEntity({required this.value, this.expireAt, this.createdAt, this.ttl});

  /// The actual stored value.
  ///
  /// 存储的真实值。
  final dynamic value;

  /// Expiry timestamp, ms since epoch.
  ///
  /// 过期时间戳（毫秒）。
  final int? expireAt;

  /// Creation timestamp — doubles as "this entry was written by this
  /// library" marker, so a lazily-expired-looking foreign entry (e.g. a
  /// coincidentally shaped `{expireAt: ...}` from other code sharing the same
  /// container) is never mistaken for one of ours. Used by sliding renewal.
  ///
  /// 写入时间戳——同时充当"这条数据是本库写的"标记，避免误把外部恰好形如
  /// `{expireAt: ...}` 的数据当成过期条目处理。滑动续期也靠它。
  final int? createdAt;

  /// The original ttl (ms), used by sliding renewal to recompute [expireAt].
  ///
  /// 原始 ttl（毫秒），滑动过期靠它重算 [expireAt]。
  final int? ttl;

  Map<String, dynamic> toJson() => {
        'value': value,
        if (expireAt != null) 'expireAt': expireAt,
        if (createdAt != null) 'createdAt': createdAt,
        if (ttl != null) 'ttl': ttl,
      };

  static CacheEntity fromJson(Map<String, dynamic> json) => CacheEntity(
        value: json['value'],
        expireAt: json['expireAt'] as int?,
        createdAt: json['createdAt'] as int?,
        ttl: json['ttl'] as int?,
      );

  /// A copy with [expireAt] overridden — used by sliding renewal so the
  /// in-memory memo entry is never mutated in place before the backend write
  /// is confirmed (mirrors a fix in the sibling `@codejoo/storage` TS
  /// project: mutating a memo-shared entity before `persist()` succeeds would
  /// let readers observe a "renewed" expiry the backend never actually got).
  ///
  /// 覆盖 [expireAt] 的副本——滑动续期专用，保证落盘确认前绝不原地改动可能
  /// 被 memo 共享着的 entity（对齐姊妹 TS 项目 `@codejoo/storage` 修过的一个
  /// 坑：落盘成功前原地改会让读者看到一个后端其实没拿到的"已续期"过期时间）。
  CacheEntity renewed(int expireAt) => CacheEntity(
        value: value,
        expireAt: expireAt,
        createdAt: createdAt,
        ttl: ttl,
      );
}

/// Default `entity -> string` serializer: plain `jsonEncode`.
///
/// 默认 entity -> 字符串序列化：普通 `jsonEncode`。
String defaultSerialize(CacheEntity entity) => jsonEncode(entity.toJson());

/// Default `string -> entity` deserializer: plain `jsonDecode`.
///
/// 默认字符串 -> entity 反序列化：普通 `jsonDecode`。
CacheEntity defaultDeserialize(String raw) =>
    CacheEntity.fromJson(jsonDecode(raw) as Map<String, dynamic>);
