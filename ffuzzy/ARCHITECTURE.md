# FFuzzy 架构文档

## 项目概述

**ffuzzy** 是一个高性能 Flutter 模糊搜索库，通过 dart:ffi 调用编译的 C 引擎，支持模糊匹配、子字符串、前缀、后缀、精确匹配等多种搜索算法，提供多线程、异步过滤、命中高亮、Unicode/CJK 支持等功能。

## 核心架构

```
搜索查询
    ↓
[FFuzzy Dart API]
    ├─ search()
    ├─ filter()
    └─ highlight()
    ↓
[Dart FFI 桥接]
    ├─ 方法映射
    ├─ 数据序列化
    └─ 错误处理
    ↓
[原生 C 引擎]
    ├─ 编译二进制 (so/dylib/dll)
    ├─ 匹配算法
    └─ 多线程处理
    ↓
[匹配算法]
    ├─ Fuzzy 匹配
    ├─ Substring 匹配
    ├─ Prefix 匹配
    ├─ Postfix 匹配
    └─ Exact 匹配
    ↓
[结果处理]
    ├─ 评分排序
    ├─ 命中高亮
    └─ Unicode 处理
    ↓
返回搜索结果
```

## 主要特性

### 1. **多种匹配算法**
```dart
// Fuzzy 匹配 - 灵活的模糊匹配
ffuzzy.search('usr', corpus);  // 匹配 "user", "username", etc.

// Substring 匹配 - 连续子字符串
ffuzzy.search('user', corpus);  // 匹配包含 "user" 的项

// Prefix 匹配 - 前缀匹配
ffuzzy.search('use', corpus);   // 匹配以 "use" 开头的项

// Postfix 匹配 - 后缀匹配
ffuzzy.search('name', corpus);  // 匹配以 "name" 结尾的项

// Exact 匹配 - 精确匹配
ffuzzy.search('user', corpus);  // 精确匹配 "user"
```

### 2. **C 引擎加速**
- 核心算法用 C 实现，编译为原生代码
- 通过 FFI 调用，无 JNI/JIT 开销
- 性能比纯 Dart 实现快 10-100 倍

### 3. **多线程搜索**
```dart
// 在后台线程中运行搜索，不阻塞 UI
final results = await ffuzzy.searchAsync(
  query: 'search term',
  corpus: largeList,
  threads: 4  // 使用 4 个线程
);
```

### 4. **结果评分和排序**
```dart
// 自动按相关性排序
final results = await ffuzzy.search(query, corpus);
// 结果按匹配度从高到低排列
// 精确匹配 > 前缀匹配 > 模糊匹配
```

### 5. **命中高亮**
```dart
final results = await ffuzzy.searchWithHighlight(
  query: 'user',
  corpus: texts
);
// 返回包含高亮标记的结果
// "The <highlight>user</highlight> is here"
```

### 6. **Unicode/CJK 支持**
```dart
// 支持中文、日文、韩文等
ffuzzy.search('用户', chineseList);
ffuzzy.search('ユーザー', japaneseList);

// 支持笔画、拼音等特殊处理（可选）
```

## 文件结构

```
lib/
├── src/
│   ├── ffuzzy.dart             # FFuzzy 主类
│   ├── ffi/
│   │   ├─ bindings.dart        # C 函数绑定
│   │   ├─ library_loader.dart  # 动态库加载
│   │   └─ native_api.dart      # 原生 API 包装
│   ├── search/
│   │   ├─ matcher.dart         # 匹配器基类
│   │   ├─ algorithms.dart      # 匹配算法
│   │   └─ result.dart          # 搜索结果
│   ├── threading/
│   │   └─ thread_pool.dart     # 线程池
│   ├── highlighting/
│   │   └─ highlighter.dart     # 高亮器
│   ├── types.dart              # 类型定义
│   └─ constants.dart           # 常量
├── ios/
├── android/
├── windows/
├── macos/
├── linux/
└── web/
```

## 核心流程

### 初始化

```dart
import 'package:ffuzzy/ffuzzy.dart';

// 创建搜索实例
final ffuzzy = FFuzzy();

// 准备语料库
final corpus = ['user', 'username', 'password', 'email', ...];
```

### 搜索流程

```
应用调用 ffuzzy.search(query, corpus)
    ↓
[Dart API 层]
    ├─ 验证输入
    ├─ 准备搜索配置
    └─ 转换参数格式
    ↓
[FFI 桥接]
    ├─ 将 Dart 数据序列化
    ├─ 调用 C 函数
    ├─ void* pointer = search_fuzzy(query, corpus)
    └─ 等待 C 函数返回
    ↓
[C 引擎]
    ├─ 加载动态库
    ├─ 编译的 C 代码执行
    └─ 原生性能，无 JIT 开销
    ↓
[匹配算法]
    ├─ 对每个语料项执行匹配
    ├─ 计算匹配得分
    └─ 记录匹配位置
    ↓
[多线程处理]
    ├─ 分片语料库
    ├─ 分配给多个线程
    ├─ 并行处理，最后合并
    └─ 大规模搜索时优势明显
    ↓
[结果处理]
    ├─ 返回 C 侧结果
    ├─ 按得分排序
    └─ Dart 侧反序列化
    ↓
[可选高亮]
    ├─ 如果请求高亮
    ├─ 标记匹配位置
    └─ 返回高亮文本
    ↓
返回搜索结果给应用
```

### 异步搜索

```dart
// 不阻塞 UI 的异步搜索
final results = await ffuzzy.searchAsync(
  query: 'search term',
  corpus: hugeList,  // 百万级数据
  threads: 4
);

// 或使用 Stream 获得实时进度
final stream = ffuzzy.searchStream(
  query: 'search term',
  corpus: hugeList
);

stream.listen((result) {
  print('Found: ${result.text}, Score: ${result.score}');
});
```

## FFI 架构详解

### C 函数签名

```c
// C 侧接口
typedef struct {
  char* text;
  float score;
  int* positions;  // 匹配位置数组
  int positions_len;
} FFuzzyResult;

FFuzzyResult* ffuzzy_search_fuzzy(
  const char* query,
  const char** corpus,
  int corpus_len,
  int num_threads
);

void ffuzzy_free_results(FFuzzyResult* results, int len);
```

### Dart 侧绑定

```dart
// Dart FFI 绑定
class FFuzzyNative {
  final DynamicLibrary nativeLib;
  
  late final Pointer<NativeFunction<
    Pointer<FFuzzyResultNative> Function(
      Pointer<Utf8> query,
      Pointer<Pointer<Utf8>> corpus,
      Int32 corpusLen,
      Int32 numThreads
    )
  >> _searchFuzzy;
  
  FFuzzyNative() : nativeLib = _loadLibrary() {
    _searchFuzzy = nativeLib
      .lookup<NativeFunction<...>>('ffuzzy_search_fuzzy')
      .asFunction();
  }
  
  List<FFuzzyResult> searchFuzzy(
    String query,
    List<String> corpus, {
    int numThreads = 1
  }) {
    // 调用 C 函数
    final result = _searchFuzzy(
      query.toNativeUtf8().cast(),
      corpus.map((s) => s.toNativeUtf8()).toList().cast(),
      corpus.length,
      numThreads
    );
    
    // 反序列化结果
    // ...
  }
}
```

## 性能考量

### 1. **C 引擎优势**
- Fuzzy 匹配的字符串操作用 C 实现，无解释开销
- 循环紧凑，缓存友好

### 2. **多线程扩展**
- 大规模语料库可用多线程加速
- 线程数 = CPU 核心数时性能最优

### 3. **内存管理**
- C 侧分配内存，Dart 侧负责及时释放
- 避免内存泄漏

### 4. **与 Isolate 搭配**
```dart
// 在 Isolate 中运行搜索，不阻塞 UI
final results = await compute(
  _search,
  SearchParams(query: 'term', corpus: list)
);
```

## 与其他项目的关系

- 其他 Dart-Labs 子包: 可作为搜索/过滤能力
- GetX 应用: 搜索结果可存储在 Rx

## 跨平台支持

- **iOS/macOS**: 编译为 `.dylib`
- **Android**: 编译为 `.so`
- **Windows**: 编译为 `.dll`
- **Linux**: 编译为 `.so`
- **Web**: WASM 版本（asm.js fallback）

## 参考

- [README.md](./README.md)
- [源代码](./lib)
- [Dart FFI 文档](https://dart.dev/guides/libraries/c-interop)
