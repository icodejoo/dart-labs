# json_annotation_lenient

**面向 `json_serializable` 的宽松 JSON 转换 —— 对松散的 `int`/`double`/`num`/`bool`/`String`/`DateTime` 值做兼容转换而不是直接抛异常，外加一个开箱即用的 build_runner builder，为缺失字段自动填充按类型区分的默认值。**

[English](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/README.md) · **简体中文**

[![pub.dev](https://img.shields.io/pub/v/json_annotation_lenient.svg)](https://pub.dev/packages/json_annotation_lenient)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)

---

## 为什么选择 json_annotation_lenient？

现实世界的接口很少给出类型完美的 JSON —— 一个 `int` 字段今天是
`"42"`，一个 `bool` 字段是 `1`，一个时间戳今天是字符串，明天又变成了
epoch 数值。官方 `json_serializable` 遇到这些都会直接抛异常。
`json_annotation_lenient` 提供两个相互独立的工具来解决这个问题：

1. **转换器（Converters）** —— 六个 `JsonConverter` 实现，分别兼容
   `int`/`double`/`num`/`bool`/`String`/`DateTime` 常见的非标准形态，
   在值缺失或为 `null` 时兜底为合理的默认值。
2. **build_runner builder** —— `autoDefaultJsonBuilder`，完整替换官方
   `json_serializable` builder。它会给任何没有显式写
   `@JsonKey(defaultValue:)` 的非空字段自动填充按类型区分的默认值；
   并且对标了 `@LenientConverter(...)` 的类，会自动把匹配类型的字段
   改写成走上面的转换器 —— 不用在每个字段上都叠一遍
   `@LenientIntConverter()`/`@LenientDoubleConverter()`/...。

两部分可以独立使用：只用转换器配合官方 builder，或者引入 builder 来
获得自动默认值能力（即使某些类完全不用 `@LenientConverter`）。

---

## 安装

```yaml
dependencies:
  json_annotation_lenient: ^1.1.0
```

即使某个项目只在编译期使用它，`json_annotation_lenient` 也设计成一个**普通**依赖
（而非 `dev_dependencies`）—— `build.yaml` 里的 builder 插件必须能从
依赖方项目的常规依赖图中解析出来。

---

## 使用转换器

```dart
import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation_lenient/json_annotation_lenient.dart';

part 'foo.g.dart';

@JsonSerializable()
class Foo {
  @LenientIntConverter()
  final int count;       // 兼容 42、42.0 或 "42"

  @LenientBoolConverter()
  final bool active;     // 兼容 true、1、"1" 或 "true"

  @LenientDateTimeConverter()
  final DateTime createdAt; // 兼容 ISO 8601、"2024/01/01 10:00:00"，或者一个 epoch 数值

  Foo(this.count, this.active, this.createdAt);
}
```

当 JSON 值缺失或为 `null` 时，每个转换器都会兜底为一个默认值 ——
int/num 是 `0`，double 是 `0.0`，bool 是 `false`，string 是 `''`，
`DateTime` 是 Unix 纪元（类型允许 const 默认值的话可以通过生成的
`@JsonKey(defaultValue: ...)` 覆盖 —— `DateTime` 不行，因为它没有
const 构造函数）。

### `@LenientConverter` —— 给整个类打开宽松转换

与其在每个字段上都叠一个转换器注解，不如直接标记整个类，所有匹配
标量类型的字段都会自动走对应的转换器（需要配合下面的
`autoDefaultJsonBuilder`）：

```dart
@LenientConverter() // int/double/num/bool/String/DateTime 全部启用
@JsonSerializable()
class Foo {
  final int count;       // 走 LenientIntConverter
  final bool active;     // 走 LenientBoolConverter

  @LenientConverter(double: false)
  final double score;    // 不受影响 —— 只对这个字段关闭

  @DisableLenient()
  final int strictId;    // 不受影响 —— 完全退出

  Foo(this.count, this.active, this.score, this.strictId);
}
```

`@LenientConverter(dateTimeUtc: true)`（类级或字段级）控制没有时区信息的
`DateTime` 值该怎么解释 —— 完整规则见 `LenientDateTimeConverter` 的
dartdoc。

---

## 使用 builder

在项目根目录加一个 `build.yaml`，关闭官方 `json_serializable` builder，
换成 `json_annotation_lenient` 提供的替代实现：

```yaml
targets:
  $default:
    builders:
      json_serializable:
        enabled: false
      json_annotation_lenient:auto_default:
        enabled: true
        options:
          explicit_to_json: true
```

`auto_default` builder 本身已经由本包自带的 `build.yaml`（`auto_apply: none`）
声明过了 —— 不要在自己的 `build.yaml` 里再重复声明 `builders:` 段，否则会
注册出第二个同样输出 `.g.dart` 的 builder，`build_runner` 会报
"conflicting outputs" 直接拒绝运行。

然后照常跑 build_runner：

```
dart run build_runner build --delete-conflicting-outputs
```

builder 已经用 `dart_style` 包格式化过每个生成的 `.g.dart` 了，但这是一个独立
发布在 pub.dev 上的包，和你 SDK 自带的 `dart format` 命令用的格式化器不是
同一个版本——两者会不同步（pub.dev 上的 `dart_style` 有时会落后于较新 Dart
SDK 内置的格式化器），导致生成的文件跟你项目里其它代码跑 `dart format .`
的结果对不上。如果你的项目在 CI 或 pre-commit 里强制跑
`dart format --set-exit-if-changed` 检查，生成之后记得再串一次真正的格式化，
跟你 SDK 实际用的格式化器保持一致：

```
dart run build_runner build --delete-conflicting-outputs && dart format .
```

启用这个 builder 之后：

- 没有显式 `@JsonKey(defaultValue:)` 的非空字段，统一按类型兜底默认值
  （`''`、`0`、`0.0`、`false`、`const []`、`const {}`），而不是在
  key 缺失/为 null 时抛异常。
- 类上标了 `@LenientConverter(...)` 的话，匹配类型的字段会被改写成走
  对应的 `Lenient*Converter` —— 不需要逐字段加注解。
- 字段标了 `@DisableLenient()` 的话完全不受以上两条影响（纯官方
  `json_serializable` 行为）。

`json_annotation_lenient:auto_default` 下的 `options` 会原样透传给底层的
`JsonSerializableGenerator`（`explicit_to_json`、`field_rename` 等 ——
和官方 `json_serializable` builder 接受的选项一致），只有下面这个
`lenient:` 段是 builder 自己消费的。

**完全不写 `explicit_to_json` 时默认是 `true`**——嵌套的 `@JsonSerializable`
字段几乎总是需要显式调用 `.toJson()` 才能正确序列化，而官方
`json_serializable` 默认是 `false`，导致每个使用方都得自己手动开一遍。如果
你的项目依赖旧的隐式 `toJson` 行为，自己显式写 `explicit_to_json: false`
即可——不管写成哪个值，显式写的都会被尊重。

### `options.lenient` —— 全局宽松配置，一个注解都不用写

`@LenientConverter` 是按类生效的。如果希望整个项目统一策略，直接在
`build.yaml` 里配一次就行：

```yaml
targets:
  $default:
    builders:
      json_annotation_lenient:auto_default:
        enabled: true
        options:
          explicit_to_json: true
          lenient:
            int:
              enabled: true
              defaultValue: 0
            double:
              enabled: true
              defaultValue: 0.0
            num:
              enabled: false
            bool:
              enabled: true
              defaultValue: false
            string:
              enabled: true
              defaultValue: ""
            dateTime:
              enabled: false
              utc: false
```

六个类型键分别对应六个转换器（`int`、`double`、`num`、`bool`、`string`、
`dateTime`）。所有键 —— 包括 `enabled`、`defaultValue`、`utc` —— 都是可选的：
只有真正写出来的部分才会生效，没写的沿用注解驱动的原有行为。完全没标
`@LenientConverter`/`@DisableLenient` 的类同样会被覆盖，所以"只配 yml、
不写注解"是可行的用法 —— **前提是模型文件本身要 import**
`package:json_annotation_lenient/json_annotation_lenient.dart`。改写会往生成的
part 文件里塞一个裸的 `LenientIntConverter()` 之类的引用，而 part 文件没有
自己的 import、只能继承所在 library 的；没有这行 import 就会报未定义标识符
的编译错误（builder 遇到这种情况也会打一条构建期 warning）。

**`enabled` 的优先级**（从高到低）：

1. 字段自己的 `@LenientConverter(...)` —— yml 永远覆盖不了它。
2. yml 对该类型显式写的 `enabled:` —— 会覆盖类级注解。
3. 类级 `@LenientConverter(...)`。

字段上的 `@DisableLenient()` 依然凌驾于以上三条之上（该字段完全保持官方
`json_serializable` 生成的样子）。

**兜底值的优先级**（从高到低）：

1. 字段的 `@JsonKey(defaultValue: ...)`。
2. yml 里该类型的 `defaultValue:`。
3. 内置类型默认值（`''`、`0`、`0.0`、`false`）。

yml 的 `defaultValue:` 对没走宽松转换的普通字段也生效 —— 配了
`string.defaultValue: "n/a"` 之后，一个非宽松的 `String` 字段会生成
`json['x'] as String? ?? 'n/a'`。

**`dateTime` 的特殊之处**：它支持 `enabled:` 和 `utc:`（后者会覆盖类级的
`@LenientConverter(dateTimeUtc:)`，但覆盖不了字段级的），**不支持**
`defaultValue:` —— `DateTime` 没有 const 构造函数，没法渲染成 Dart 字面量。
`dateTime` 下写了 `defaultValue:` 会被忽略，而不是报错。

整段配置都是宽松解析的：某一项格式不对（结构不对、值类型不对）会被跳过，
不会让整个构建失败。

---

## 已知限制

自动兜底改写只识别 `json_serializable` 对
`bool`/`num`/`int`/`double`/`String`/`DateTime` 标量、`List<T>`/`Set<T>`、
`Map<K, V>` 生成的特定代码形状。以下几种字段形状是故意不改写的——它们
的行为和官方 `json_serializable` 完全一致（缺失/为 null 时依然抛异常），
而不是被静默改坏：

- **嵌套的 `@JsonSerializable` 对象字段**（`final Bar bar;` 生成
  `Bar.fromJson(json['bar'] as Map<String, dynamic>)`）不会自动兜底。
  如果需要，给这个字段单独写 `@JsonKey(defaultValue: ...)`，或者把它
  改成可空。
- **`@JsonKey(fromJson: ..., toJson: ...)`** 自定义函数字段，以及任何
  非本包提供的第三方 `@JsonConverter`，都会原样透传不受影响——改写
  只对明确识别的形状生效，这样才不会生成编译不过的代码。
- **`enum` 字段** 不会被凭空发明一个兜底值——不像标量有
  `0`/`''`/`false` 这种通用意义上"正确"的默认值，枚举没有。缺失/为
  null 的 key 请用 `@JsonKey(defaultValue: MyEnum.foo)`（官方
  `json_serializable` 原生支持，不需要任何宽松逻辑）；值不在枚举范围内
  的情况请用 `@JsonKey(unknownEnumValue: MyEnum.foo)`。

---

## 贡献

欢迎 issue 与 PR。

- 🐛 [提交 issue](https://github.com/icodejoo/dart-labs/issues)
- 🔧 [发起 PR](https://github.com/icodejoo/dart-labs/pulls) —— 提交前请（在
  `json_annotation_lenient/` 下）运行 `dart analyze` 与 `dart test`。

## 许可证

MIT —— 参见 [LICENSE](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)。
