import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/kernel/mpv_keyvalue.dart';

/// 把解析结果压成 `k=v` 字符串列表，便于断言。
List<String>? _flat(String s) => parseMpvKeyValueList(s)?.map((e) => '${e.key}=${e.value}').toList();

void main() {
  group('parseMpvKeyValueList', () {
    test('空串是空列表', () => expect(_flat(''), isEmpty));

    test('普通键值按顺序解析', () => expect(_flat('a=1,b=2'), ['a=1', 'b=2']));

    test('%长度% 写法：值里可含逗号、等号，长度按 UTF-8 字节', () {
      expect(_flat('h=%7%a=1,b=2,c=3'), ['h=a=1,b=2', 'c=3']);
      expect(_flat('t=%6%你好,x=1'), ['t=你好', 'x=1']);
    });

    test('引号写法', () {
      expect(_flat('a="x,y",b=\'p q\''), ['a=x,y', 'b=p q']);
    });

    test('括号嵌套整体算一个值', () => expect(_flat('a=[1,2],b={x:1}'), ['a=[1,2]', 'b={x:1}']));

    test('值可为空', () => expect(_flat('a=,b=2'), ['a=', 'b=2']));

    test('非法语法返回 null', () {
      expect(_flat('oops'), isNull);
      expect(_flat('a=1,'), isNull);
      expect(_flat('=1'), isNull);
      expect(_flat('a=%9%xy'), isNull);
      expect(_flat('a="x'), isNull);
      expect(_flat('a=[1'), isNull);
    });
  });

  group('lookupMpvKeyValue', () {
    const printed = 'seg_max_retry=5,strict=experimental,allowed_extensions=ALL,protocol_whitelist=file,crypto,data';

    test('含逗号的值取到下一项之前', () {
      expect(lookupMpvKeyValue(printed, 'protocol_whitelist'), 'file,crypto,data');
      expect(lookupMpvKeyValue(printed, 'strict'), 'experimental');
      expect(lookupMpvKeyValue(printed, 'seg_max_retry'), '5');
    });

    test('键不存在、或只是别的值里的子串，返回 null', () {
      expect(lookupMpvKeyValue(printed, 'media_timeout'), isNull);
      expect(lookupMpvKeyValue('a=x_strict=1', 'strict'), isNull);
      expect(lookupMpvKeyValue('', 'a'), isNull);
    });

    test('带 %长度% 前缀的值按长度取', () {
      expect(lookupMpvKeyValue('a=%3%x,y,b=2', 'a'), 'x,y');
      expect(lookupMpvKeyValue('a=%3%x,y,b=2', 'b'), '2');
    });
  });
}
