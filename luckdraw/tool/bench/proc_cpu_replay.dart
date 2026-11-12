import 'dart:convert';
import 'dart:io';

import 'proc_cpu.dart';

/// 离线重算两份原始快照；[args] 为 before、after 文件及真实秒数。
void main(List<String> args) {
  if (args.length != 3) throw ArgumentError('before after seconds 必填');
  final report = compareProcSnapshots(File(args[0]).readAsStringSync(),
      File(args[1]).readAsStringSync(), double.parse(args[2]));
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}
