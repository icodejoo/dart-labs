# Cacheman 架构文档

## 项目概述

**cacheman** 是一个轻量级、类型安全的 Flutter/Dart 缓存封装，统一包装 GetStorage（持久化存储），提供 TTL、绝对过期、滑动续期、命名空间、可插拔序列化、可选编码等功能。

## 核心架构

```
应用代码 (get/set/delete)
    ↓
[Cacheman 统一 API]
    ├─ 方法签名一致
    ├─ 类型推导
    └─ 配置合并
    ↓
[存储适配器]
    └─ 持久化: GetStorage
    ↓
[键值格式化]
    ├─ 命名空间处理 (prefix:key)
    ├─ 版本号管理
    └─ 键编码
    ↓
[序列化器]
    ├─ 自定义序列化函数
    ├─ JSON 编解码
    └─ 扩展点
    ↓
[加密编解码]
    ├─ 可选编码器
    ├─ 支持自定义 Codec
    └─ 加解密逻辑
    ↓
[TTL 管理]
    ├─ 过期时间计算
    ├─ 滑动续期
    └─ 自动清理
    ↓
[值存储]
    └─ GetStorage: 文件持久化
    ↓
应用读取到的数据
```

## 主要特性

### 1. **统一存储接口**
- **GetStorage**: 持久化存储，应用重启后仍保留
- 同一 API

### 2. **类型安全**
```dart
class User {
  final int id;
  final String name;
  User({required this.id, required this.name});
}

// 完全类型推导
final cache = Cacheman<User>();
User? user = await cache.get('user-1');
```

### 3. **命名空间**
```dart
// 避免键冲突
final userCache = Cacheman(namespace: 'user:');
final settingCache = Cacheman(namespace: 'settings:');
```

### 4. **TTL 和过期**
```dart
// 设置过期时间
await cache.set('token', 'abc123', 
  ttl: Duration(hours: 1)
);

// 滑动过期（访问时续期）
await cache.set('session', sessionData,
  ttl: Duration(hours: 1),
  sliding: true
);
```

### 5. **可插拔序列化**
```dart
final cache = Cacheman(
  serializer: CustomSerializer()
);
```

### 6. **加密编解码**
```dart
final cache = Cacheman(
  codec: CustomCodec(
    encode: (str) => encrypt(str),
    decode: (encoded) => decrypt(encoded)
  )
);
```

## 文件结构

```
lib/
├── src/
│   ├── cacheman.dart           # Cacheman 核心类
│   ├── adapters/
│   │   ├─ storage_adapter.dart # 存储适配器基类
│   │   └─ get_storage_adapter.dart
│   ├── serialization/
│   │   ├─ serializer.dart      # 序列化器接口
│   │   └─ codec.dart           # 编解码器
│   ├── expiry/
│   │   ├─ expiry_manager.dart  # 过期管理
│   │   └─ ttl.dart             # TTL 计算
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── cacheman.dart               # 主入口
```

## 核心流程

### 初始化
```dart
final cache = Cacheman<Map<String, dynamic>>(
  backend: CachemanBackend.persistent,  // GetStorage
  namespace: 'app:',
  ttl: Duration(days: 1),
  sliding: true,
  serializer: const JsonSerializer(),
  codec: null
);
```

### 数据写入流程

```
应用调用 cache.set(key, value, options)
    ↓
[准备数据]
    ├─ 合并配置
    ├─ 生成键 (namespace + key)
    └─ 计算过期时间
    ↓
[序列化]
    ├─ 调用序列化器
    ├─ 转换为字符串
    └─ 处理嵌套对象
    ↓
[编码]
    ├─ 如果配置了 Codec
    ├─ 执行编码操作
    └─ 返回编码值
    ↓
[构造存储数据]
    ├─ 包含：值、过期时间
    └─ 元数据
    ↓
[存储后端]
    └─ GetStorage: 文件系统
    ↓
[执行写入]
    └─ GetStorage: await box.write(key, data)
    ↓
数据写入完成
```

### 数据读取流程

```
应用调用 cache.get(key, options)
    ↓
[准备键]
    ├─ 生成实际键 (namespace + key)
    └─ 支持缓存查询
    ↓
[检查过期]
    ├─ 读取存储的过期时间
    ├─ 与当前时间比较
    └─ 已过期则删除并返回 null
    ↓
[读取数据]
    └─ GetStorage: box.read(key)
    ↓
[检查滑动过期]
    ├─ 如果启用 sliding 模式
    ├─ 更新过期时间（续期）
    └─ 重新写入存储
    ↓
[解码]
    ├─ 如果配置了 Codec
    ├─ 执行解码操作
    └─ 返回原始数据
    ↓
[反序列化]
    ├─ 调用反序列化器
    ├─ 还原为 Dart 对象
    └─ 返回类型正确的值
    ↓
返回数据给应用
```

## TTL 和滑动过期

```dart
// 场景：用户会话 Token 管理

// 固定过期：设置后 1 小时内必须有新 Token
await cache.set('token', 'abc123',
  ttl: Duration(hours: 1),
  sliding: false
);

// 滑动过期：最后一次访问后 1 小时内自动删除
await cache.set('session', sessionData,
  ttl: Duration(hours: 1),
  sliding: true
);
// 访问时自动续期
User? user = await cache.get('session');
```

## 与其他项目的关系

- **@codejoo/storage** (TypeScript/JavaScript 版本): 类似的功能设计
- 其他 Dart-Labs 子包: 可作为缓存存储层

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- GetStorage: https://pub.dev/packages/get_storage
