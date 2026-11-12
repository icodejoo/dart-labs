# json_annotation_lenient

**给 `json_serializable` 用的宽松 JSON 转换。转换器把类型不对的 `int`/`double`/`num`/`bool`/`String`/`DateTime` 值转成正确的类型，不再抛异常；build_runner builder 则按类型给缺失的字段补默认值。**

[English](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/README.md) · **简体中文**

[![pub.dev](https://img.shields.io/pub/v/json_annotation_lenient.svg)](https://pub.dev/packages/json_annotation_lenient)
[![license](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)

---

## 为什么选择 json_annotation_lenient？

现实中的接口经常返回类型不对的 JSON：`int` 字段给的是 `"42"`，`bool` 字段给的是
`1`，时间戳今天是字符串，明天又变成 epoch 数字。官方 `json_serializable` 碰到这些
都会直接抛异常。`json_annotation_lenient` 提供两个互相独立的工具：

1. **转换器（Converters）**：六个 `JsonConverter` 类，分别能接受 `int`/`double`/
   `num`/`bool`/`String`/`DateTime` 常见的几种非标准写法。值缺失或为 `null` 时，
   返回一个默认值。
2. **build_runner builder**：`autoDefaultJsonBuilder`，用来替换官方的
   `json_serializable` builder。对每个没写 `@JsonKey(defaultValue:)` 的非空字段，
   它会按类型补上默认值。对标了 `@LenientConverter(...)` 的类，它还会把类型匹配
   的字段改写成走上面的转换器，所以不用在每个字段上都写
   `@LenientIntConverter()`/`@LenientDoubleConverter()`/...。

两部分可以单独用：只用转换器、配合官方 builder；或者只引入 builder 来拿自动默认值，
哪怕有些类根本不用 `@LenientConverter`。

---

## 安装

```yaml
dependencies:
  json_annotation_lenient: ^1.1.0
```

请把它加成**普通**依赖，不要放进 `dev_dependencies`，哪怕你的项目只在构建时用到它。
`build.yaml` 里的 builder 插件必须能从项目的常规依赖图里解析到。

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

当 JSON 值缺失或为 `null` 时，每个转换器都会返回一个默认值：int/num 是 `0`，
double 是 `0.0`，bool 是 `false`，string 是 `''`，`DateTime` 是 Unix 纪元。类型允许
const 默认值时，可以用生成的 `@JsonKey(defaultValue: ...)` 改掉默认值；`DateTime`
不行，因为它没有 const 构造函数。

### `@LenientConverter` —— 给整个类打开宽松转换

不用给每个字段都写转换器注解，直接标在类上就行：所有匹配标量类型的字段都会自动
走对应的转换器（需要配合下面的 `autoDefaultJsonBuilder`）：

```dart
@LenientConverter() // int/double/num/bool/String/DateTime 全部启用
@JsonSerializable()
class Foo {
  final int count;       // 走 LenientIntConverter
  final bool active;     // 走 LenientBoolConverter

  @LenientConverter(double: false)
  final double score;    // 不受影响：只对这个字段关闭

  @DisableLenient()
  final int strictId;    // 不受影响：完全退出

  Foo(this.count, this.active, this.score, this.strictId);
}
```

`@LenientConverter(dateTimeUtc: true)`（可写在类上或字段上）决定没有时区信息的
`DateTime` 值怎么解释，完整规则见 `LenientDateTimeConverter` 的 dartdoc。

---

## 使用 builder

在项目根目录加一个 `build.yaml`：关掉官方的 `json_serializable` builder，
换成 `json_annotation_lenient` 提供的替代 builder：

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

`auto_default` builder 已经在本包自带的 `build.yaml` 里声明过了（`auto_apply: none`）。
不要在你自己的 `build.yaml` 里再写 `builders:` 段，否则会注册出第二个 builder，
同样输出 `.g.dart`，`build_runner` 会报 "conflicting outputs" 错误并停止。

然后照常跑 build_runner：

```
dart run build_runner build --delete-conflicting-outputs
```

builder 会用 `dart_style` 包格式化每个生成的 `.g.dart`，也会从 `analysis_options.yaml`
里读你项目配的 `page_width` 和 `trailing_commas`（配了才读；原理和局限见下面
`options.page_width`/`options.trailing_commas` 一节）。即便如此，pub.dev 上的
`dart_style` 是单独发布的包，和你 SDK 里 `dart format` 命令用的格式化器不是同一份，
版本可能对不上，比如 pub.dev 上的发布落后于新版 Dart SDK 内置的格式化器。这时生成
的文件和你项目里其他代码跑 `dart format .` 的结果可能有出入。如果你的 CI 或
pre-commit 会跑 `dart format --set-exit-if-changed`，生成之后请再跑一遍真正的格式化，
让文件和你 SDK 的格式化器一致：

```
dart run build_runner build --delete-conflicting-outputs && dart format .
```

启用这个 builder 之后：

- 没写 `@JsonKey(defaultValue:)` 的非空字段，会按类型补默认值（`''`、`0`、`0.0`、
  `false`、`const []`、`const {}`），key 缺失或为 null 时不再抛异常。
- 类上标了 `@LenientConverter(...)` 时，类型匹配的字段会改写成走对应的
  `Lenient*Converter`，不用逐个字段加注解。
- 字段标了 `@DisableLenient()`，以上两条都不对它生效（完全是官方
  `json_serializable` 的行为）。

`json_annotation_lenient:auto_default` 下的 `options` 会原样传给底层的
`JsonSerializableGenerator`，和官方 `json_serializable` builder 接受的选项一样
（`explicit_to_json`、`field_rename` 等）。只有下面的 `lenient:` 段例外，它由
builder 自己读取。

**不写 `explicit_to_json` 时，默认是 `true`。** 嵌套的 `@JsonSerializable` 字段要
显式调用 `.toJson()` 才能正确序列化，而官方默认是 `false`，每个项目都得自己手动打开。
如果你依赖旧的隐式 `toJson` 行为，自己写 `explicit_to_json: false` 就行。不管写 true
还是 false，显式写的值都会被采用。

### `options.lenient` —— 全局宽松配置，一个注解都不用写

`@LenientConverter` 按类生效。想让整个项目用同一套策略，在 `build.yaml` 里配一次
就行：

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
`dateTime`）。所有键，包括 `enabled`、`defaultValue`、`utc`，都是可选的：只有你写
出来的部分才生效，没写的沿用注解驱动的原有行为。没标 `@LenientConverter` 或
`@DisableLenient` 的类也会被覆盖，所以“只配 yml、不写注解”也能用，**前提是模型文件
本身仍然 import 了** `package:json_annotation_lenient/json_annotation_lenient.dart`。
改写会往生成的 part 文件里写入一个裸的 `LenientIntConverter()` 之类的引用，而 part
文件没有自己的 import，用的是所在 library 的；没有这行 import，生成的代码就会因为
找不到标识符而编译失败（遇到这种情况，builder 也会在构建时打印一条 warning）。

**`enabled` 的优先级**（从高到低）：

1. 字段自己的 `@LenientConverter(...)`：yml 覆盖不了它。
2. yml 里该类型的 `enabled:`：会覆盖类级注解。
3. 类级 `@LenientConverter(...)`。

字段上的 `@DisableLenient()` 仍然比这三条都优先：该字段保持官方 `json_serializable`
生成的样子。

**兜底值的优先级**（从高到低）：

1. 字段的 `@JsonKey(defaultValue: ...)`。
2. yml 里该类型的 `defaultValue:`。
3. 内置类型默认值（`''`、`0`、`0.0`、`false`）。

yml 里的 `defaultValue:` 对没走宽松转换的普通字段也生效。配了
`string.defaultValue: "n/a"` 之后，一个非宽松的 `String` 字段会生成
`json['x'] as String? ?? 'n/a'`。

**`dateTime` 的特殊之处**：它支持 `enabled:` 和 `utc:`（`utc:` 会覆盖类级的
`@LenientConverter(dateTimeUtc:)`，但覆盖不了字段级的），**不支持** `defaultValue:`：
`DateTime` 没有 const 构造函数，生成不出 Dart 字面量。写在 `dateTime` 下的
`defaultValue:` 会被忽略，不会报错。

整段配置都按宽松方式解析：某一项格式不对（结构不对或值类型不对）会被跳过，
不会让构建失败。

### `options.page_width` / `options.trailing_commas` —— 对齐你的格式化配置

`dart_style` 公开的 `DartFormatter` 类是这个 builder（以及任何基于 `PartBuilder`
的生成器）唯一能调用的东西，它完全不读项目的 `analysis_options.yaml`；真正读那个
文件的代码是 `dart_style` 自己 CLI 里的私有实现。所以默认情况下，生成的 `.g.dart`
永远用 `dart_style` 内置的 page width（80）和 trailing comma 策略（`automate`），
不管你项目里怎么配。

为了解决这个问题，builder 做了两件事：

1. 从最近的 `analysis_options.yaml`（从运行 build_runner 的目录往上找）里读
   `formatter: page_width:` / `trailing_commas:`。这是从零写的简化实现，每个文件
   最多跟一层本地（非 `package:`）的 `include:` 路径。如果 `formatter:` 配置在
   `package:` 形式的 include 里（比如团队共享的 lint 包），就读不到。
2. 使用你显式写的值：

   ```yaml
   options:
     page_width: 100
     trailing_commas: preserve # 或 'automate'
   ```

   `options:` 里写的值永远优先于自动探测的结果。可以用它覆盖探测到的值，配置
   放在 `package:` include 里时也靠它解决。

---

## 已知限制

自动补默认值的改写，只认 `json_serializable` 对 `bool`/`num`/`int`/`double`/`String`/
`DateTime` 标量、`List<T>`/`Set<T>`、`Map<K, V>` 生成的那几种代码。下面几种字段是
故意不改的：它们的行为和官方 `json_serializable` 一样（缺失或为 null 时依然抛异常），
不会被悄悄改坏：

- **嵌套的 `@JsonSerializable` 对象字段**（`final Bar bar;` 生成
  `Bar.fromJson(json['bar'] as Map<String, dynamic>)`）不会自动补默认值。需要的话，
  给这个字段单独写 `@JsonKey(defaultValue: ...)`，或者改成可空。
- **`@JsonKey(fromJson: ..., toJson: ...)`** 自定义函数字段，以及不是本包提供的第三方
  `@JsonConverter`，都会原样保留。改写只处理认得的代码形状，这样就不会生成编译不过
  的代码。
- **`enum` 字段** 不会凭空编一个默认值。标量有 `0`/`''`/`false` 这种通用的默认值，
  枚举没有哪个成员能算通用的“正确”默认。key 缺失或为 null 时，用
  `@JsonKey(defaultValue: MyEnum.foo)`（官方 `json_serializable` 本来就支持，不需要
  宽松逻辑）；值不在枚举范围内时，用 `@JsonKey(unknownEnumValue: MyEnum.foo)`。

---

## 贡献

欢迎 issue 与 PR。

- [提交 issue](https://github.com/icodejoo/dart-labs/issues)
- [发起 PR](https://github.com/icodejoo/dart-labs/pulls)：提交前请（在
  `json_annotation_lenient/` 下）运行 `dart analyze` 和 `dart test`。

## 许可证

MIT —— 参见 [LICENSE](https://github.com/icodejoo/dart-labs/blob/main/json_annotation_lenient/LICENSE)。
