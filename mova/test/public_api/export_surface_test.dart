import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/ads.dart' as ads;
import 'package:mova/extend.dart' as extend;
import 'package:mova/feed.dart' as feed;
import 'package:mova/mini.dart' as mini;
import 'package:mova/mova.dart' as mova;
import 'package:mova/skin.dart' as skin;
import 'package:mova/stt.dart' as stt;

// 固定每条源文件导出及其 show/hide 约束，递归穿过入口和 src 内的转导出。
// 源文件未变时，这一快照保留全部声明（含函数、扩展、别名），而非只抽样类名。
// 不把 import 当作 export；新增入口自身不占快照条目。
List<String> _surface(String entry) {
  final result = <String>{};
  final visiting = <Uri>{};
  final lib = Directory('lib').absolute.uri;
  final directive = RegExp(r"^export\s+'([^']+)'([^;]*);", multiLine: true);

  void visit(Uri file) {
    if (!visiting.add(file)) return;
    for (final match in directive.allMatches(
      File.fromUri(file).readAsStringSync(),
    )) {
      final target = file.resolve(match[1]!);
      final relative = target.toString().substring(lib.toString().length);
      final combinators = match[2]!.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (relative.startsWith('src/')) {
        result.add('$relative${combinators.isEmpty ? '' : ' $combinators'};');
      } else {
        // 当前分入口均无过滤；若以后过滤，须升级快照解析以计算交集。
        expect(combinators, isEmpty, reason: '入口过滤必须显式更新快照解析');
      }
      visit(target);
    }
    visiting.remove(file);
  }

  visit(lib.resolve(entry));
  return result.toList()..sort();
}

List<String> _snapshot(String name) =>
    File('test/public_api/snapshots/$name.txt').readAsLinesSync();

void main() {
  test('主入口保留拆分前全部导出及 show/hide 约束', () {
    expect(_surface('mova.dart'), _snapshot('mova'));
    // 既有类型身份不因经过新入口而改变。
    expect(mova.MovaSkin, skin.MovaSkin);
    expect(mova.MovaAds, ads.MovaAds);
    expect(mova.MovaFeed, feed.MovaFeed);
    expect(mova.MovaMini, mini.MovaMini);
    expect(mova.MovaSession, extend.MovaSession);
  });

  test('五个分入口各自保持模块导出快照并公告内部 helper', () {
    for (final name in ['skin', 'ads', 'feed', 'mini', 'extend']) {
      expect(_surface('$name.dart'), _snapshot(name), reason: name);
    }
    final extension = File('lib/extend.dart').readAsStringSync();
    expect(extension, contains('内部 helper'));
    expect(extension, contains('下个版本'));
    expect(extension, isNot(contains('@Deprecated')));
    final main = File('lib/mova.dart').readAsStringSync();
    for (final name in ['skin', 'ads', 'feed', 'mini', 'extend']) {
      expect(main, contains("export '$name.dart';"));
    }
  });

  test('STT 独立入口与一个版本兼容转导出保持相同契约', () {
    final surface = _surface('stt.dart');
    expect(surface, _snapshot('stt'));
    expect(_surface('mova.dart'), containsAll(surface));
    expect(mova.MovaSttApi, stt.MovaSttApi);
    expect(mova.MovaSttModelProvider, stt.MovaSttModelProvider);
    // 静态检查既有 getter 的返回类型，签名变化必须导致此处编译失败。
    stt.MovaSttApi? readStt(mova.MovaApi api) => api.stt;
    expect(readStt, isA<stt.MovaSttApi? Function(mova.MovaApi)>());
    final main = File('lib/mova.dart').readAsStringSync();
    expect(main, contains("export 'stt.dart';"));
    expect(main, isNot(contains("export 'src/core/stt/")));
    expect(main, contains('仅转导出一个版本'));
    expect(main, isNot(contains('@Deprecated')));
    expect(File('lib/stt.dart').readAsStringSync(), contains('模型下载为实验实现'));
  });
}
