# Dioman 架构文档

## 项目概述

**dioman** 是一个 Dart HTTP 客户端库，提供组合式、自包含的 Dio 拦截器插件系统。包括认证、缓存、重试、去重、Mock、规范化等插件，并提供正确的安装顺序指导，使开发者可以灵活组合使用。

## 核心架构

```
应用代码 (Dio 请求)
    ↓
[Dioman 拦截器管理器]
    ├─ 插件链式管理
    └─ 自动排序
    ↓
[拦截器插件]
    ├─ Auth Plugin (认证)
    ├─ Cache Plugin (缓存)
    ├─ Retry Plugin (重试)
    ├─ Dedup Plugin (去重)
    ├─ Mock Plugin (Mock)
    └─ Normalize Plugin (规范化)
    ↓
[请求拦截]
    ├─ 修改请求头/体
    ├─ 检查缓存
    └─ 拦截 Mock 请求
    ↓
[Dio HTTP 客户端]
    └─ 发送网络请求
    ↓
[响应处理]
    ├─ 缓存响应
    ├─ 重试逻辑
    └─ 数据规范化
    ↓
返回应用数据
```

## 主要特性

### 1. **认证插件 (Auth)**
```dart
final dio = Dio();
dio.interceptors.add(
  AuthInterceptor(
    getToken: () => tokenManager.getToken(),
    refreshToken: () => tokenManager.refreshToken(),
    tokenHeader: 'Authorization'
  )
);
```
- 自动注入 Token
- Token 过期自动刷新
- 无缝重试

### 2. **缓存插件 (Cache)**
```dart
dio.interceptors.add(
  CacheInterceptor(
    cacheDuration: Duration(hours: 1),
    cacheableStatusCodes: [200, 304]
  )
);
```
- 自动缓存 GET 请求
- 可配置过期时间
- 支持自定义缓存键

### 3. **重试插件 (Retry)**
```dart
dio.interceptors.add(
  RetryInterceptor(
    maxRetries: 3,
    backoffDelay: (retryCount) => 
      Duration(milliseconds: 100 * pow(2, retryCount))
  )
);
```
- 失败自动重试
- 指数退避策略
- 可配置重试次数

### 4. **去重插件 (Dedup)**
```dart
dio.interceptors.add(
  DedupInterceptor()
);
```
- 相同请求自动去重
- 共享响应结果
- 减少网络开销

### 5. **Mock 插件**
```dart
dio.interceptors.add(
  MockInterceptor(
    mockData: {
      '/api/users': {'data': [...]},
      '/api/posts': {'data': [...]}
    }
  )
);
```
- 拦截特定请求
- 返回 Mock 数据
- 开发测试友好

### 6. **规范化插件 (Normalize)**
```dart
dio.interceptors.add(
  NormalizeInterceptor(
    normalizeResponse: (response) {
      // 标准化响应格式
      return response.data['result'];
    }
  )
);
```
- 统一响应格式
- 提取有用数据
- 简化使用

## 文件结构

```
lib/
├── src/
│   ├── dioman.dart             # Dioman 主类
│   ├── interceptors/
│   │   ├─ auth_interceptor.dart
│   │   ├─ cache_interceptor.dart
│   │   ├─ retry_interceptor.dart
│   │   ├─ dedup_interceptor.dart
│   │   ├─ mock_interceptor.dart
│   │   └─ normalize_interceptor.dart
│   ├── cache/
│   │   ├─ cache_manager.dart   # 缓存管理
│   │   └─ cache_strategies.dart# 缓存策略
│   ├── retry/
│   │   ├─ retry_policy.dart    # 重试策略
│   │   └─ backoff.dart         # 退避算法
│   ├── dedup/
│   │   └─ dedup_manager.dart   # 去重管理
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
└── dioman.dart                 # 主入口
```

## 核心流程

### 初始化

```dart
final dio = Dio(BaseOptions(
  baseUrl: 'https://api.example.com',
  connectTimeout: Duration(seconds: 10),
  receiveTimeout: Duration(seconds: 10)
));

// 正确安装顺序很重要！
// 1. Auth (最先，为其他插件提供 Token)
dio.interceptors.add(AuthInterceptor(...));

// 2. Cache (缓存检查)
dio.interceptors.add(CacheInterceptor(...));

// 3. Dedup (去重检查)
dio.interceptors.add(DedupInterceptor(...));

// 4. Mock (开发测试)
dio.interceptors.add(MockInterceptor(...));

// 5. Retry (最后，重试整个请求链)
dio.interceptors.add(RetryInterceptor(...));

// 6. Normalize (响应处理)
dio.interceptors.add(NormalizeInterceptor(...));
```

### 请求流程

```
应用调用 dio.get('/api/users')
    ↓
[Auth 拦截]
    ├─ 检查 Token 有效期
    ├─ 如需刷新则刷新
    └─ 注入 Authorization 头
    ↓
[Cache 拦截]
    ├─ 检查缓存是否存在
    ├─ 缓存未过期则返回缓存
    └─ Cache Hit → 返回给应用
    ↓
[Dedup 拦截]
    ├─ 标准化请求 Key
    ├─ 检查是否有相同请求在处理
    └─ 相同请求等待首个完成，共享结果
    ↓
[Mock 拦截]
    ├─ 检查是否在 Mock 列表
    ├─ 匹配则返回 Mock 数据
    └─ Mock Hit → 返回给应用
    ↓
[Dio 网络请求]
    ├─ 发送真实网络请求
    └─ 等待响应
    ↓
[Retry 重试]
    ├─ 请求成功 → 继续
    ├─ 请求失败 → 计算延迟
    ├─ 延迟后重试
    └─ 达到最大重试次数则放弃
    ↓
[Cache 缓存]
    ├─ 缓存成功响应
    └─ 记录时间戳
    ↓
[Normalize 规范化]
    ├─ 提取有用数据
    ├─ 转换格式
    └─ 返回给应用
    ↓
应用接收数据
```

### Auth Token 刷新流程

```
请求发送时 Token 已过期
    ↓
[Auth 拦截器检测]
    ├─ 读取当前 Token
    ├─ 检查过期时间
    └─ 发现已过期
    ↓
[刷新 Token]
    ├─ 调用 refreshToken() 方法
    ├─ 请求新 Token
    └─ 等待结果
    ↓
[更新 Token]
    ├─ 保存新 Token
    └─ 返回到 Token 管理器
    ↓
[重试原请求]
    ├─ 使用新 Token 重新发送
    └─ 继续请求链
```

### 去重机制

```dart
// 用户同时发起三个相同请求
final future1 = dio.get('/api/users');  // 第一个请求
final future2 = dio.get('/api/users');  // 第二个请求
final future3 = dio.get('/api/users');  // 第三个请求

// Dedup 插件处理：
// 1. future1 生成 Key="GET:/api/users"
//    → 没有相同 Key 在处理，发送网络请求
// 2. future2 生成 Key="GET:/api/users"
//    → 检测到已有相同 Key 在处理，等待 future1 结果
// 3. future3 生成 Key="GET:/api/users"
//    → 检测到已有相同 Key 在处理，等待 future1 结果
// 4. 网络请求完成
//    → future1 返回结果
//    → future2 返回相同结果（无网络开销）
//    → future3 返回相同结果（无网络开销）
```

## 插件安装顺序

```
请求方向 (应用 → 网络)

应用
  ↓
[1] Auth 拦截器 - 注入 Token
  ↓
[2] Cache 拦截器 - 缓存检查
  ↓
[3] Dedup 拦截器 - 去重检查
  ↓
[4] Mock 拦截器 - Mock 检查
  ↓
[5] Dio 核心 - 发送网络
  ↓
[6] Retry 拦截器 - 重试处理（响应侧）
  ↓
[7] Normalize 拦截器 - 响应规范化
  ↓
应用

关键点：
- Auth 最先：其他插件可能需要 Token
- Cache/Dedup/Mock 中间：在网络请求前检查
- Retry 靠后：包装整个请求链
- Normalize 最后：最后处理响应格式
```

## 与其他项目的关系

- **@codejoo/axp** (TypeScript 版本): 类似的插件化设计
- **其他 Dart-Labs 子包**: 可作为 HTTP 客户端

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- Dio: https://pub.dev/packages/dio
