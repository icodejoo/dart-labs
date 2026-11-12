import 'dart:convert';
import 'dart:io';

/// 禁止 Flutter 命令隐式获取依赖。
const String _noPub = '--no-pub';

/// APK 报告文件的严格文件名模式；不把 snapshot/trace 当作最终报告。
final RegExp _reportName = RegExp(r'^apk-code-size-analysis(?:_\d+)?\.json$');

/// APK 构建使用的进程所有权标记键。
const String kApkOwnerProperty = '-XX:HeapDumpPath=luckdraw_treeshake_';

/// 返回非负 [measuredBytes] 的 110% 向上取整预算，避免二进制浮点误差。
///
/// 例如 `apkBudgetBytes(49040) == 53944`；负数抛 [ArgumentError]。
int apkBudgetBytes(int measuredBytes) {
  if (measuredBytes < 0) {
    throw ArgumentError.value(measuredBytes, 'measuredBytes', '字节数不能为负');
  }
  return (measuredBytes * 11 + 9) ~/ 10;
}

/// 返回 [directory] 中隔离 Android 工程的串行命令计划。
///
/// 第二步离线失败后可在线重试一次；最后一步仅构建 arm64 release，
/// 例如 `apkBuildCommands('/tmp/probe').last`，无需连接设备。
List<List<String>> apkBuildCommands(String directory) => [
      [
        'create',
        '--platforms=android',
        '--empty',
        _noPub,
        '--project-name=luckdraw_treeshake_probe',
        directory,
      ],
      ['pub', 'get', '--offline', '--no-example'],
      [
        'build',
        'apk',
        '--release',
        '--analyze-size',
        '--target-platform=android-arm64',
        _noPub,
      ],
    ];

/// 返回替换 Flutter 默认大堆配置后的 Gradle 属性。
///
/// [original] 为模板内容，[owner] 是当前工程唯一的字母数字标记；
/// 返回最多两个 worker、无常驻 daemon、Kotlin 同进程的配置，不修改 SDK 或缓存。
String apkGradleProperties(String original, String owner) {
  if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(owner)) {
    throw ArgumentError.value(owner, 'owner', '必须是字母数字所有权标记');
  }
  const replaced = {
    'org.gradle.jvmargs',
    'org.gradle.daemon',
    'org.gradle.workers.max',
    'kotlin.compiler.execution.strategy',
  };
  final retained = const LineSplitter()
      .convert(original)
      .where((line) => !replaced.contains(line.split('=').first.trim()));
  return '${retained.join('\n')}\n'
      'org.gradle.jvmargs=-Xmx1536m -XX:MaxMetaspaceSize=512m '
      '-XX:ReservedCodeCacheSize=256m $kApkOwnerProperty$owner.hprof\n'
      'org.gradle.daemon=false\norg.gradle.workers.max=2\n'
      'kotlin.compiler.execution.strategy=in-process\n';
}

/// 从命令行判断 Gradle/Kotlin 是否属于 [owner]，不按 java 进程名清理。
///
/// [commandLine] 必须同时含精确 JVM 标记和编译守护进程类名才返回 true。
bool isOwnedApkDaemon(String commandLine, String owner) =>
    RegExp('(?:^|\\s)${RegExp.escape(kApkOwnerProperty)}'
            '${RegExp.escape(owner)}\\.hprof(?=\\s|\$)')
        .hasMatch(commandLine) &&
    (commandLine
            .contains('org.gradle.launcher.daemon.bootstrap.GradleDaemon') ||
        commandLine
            .contains('org.jetbrains.kotlin.daemon.KotlinCompileDaemon'));

/// 从文件路径和版本标记的前后快照中返回唯一新增或改变的 APK 报告。
///
/// [before]/[after] 的值由调用方提供（例如修改时间与文件长度）；零个或
/// 多个候选均显式失败，不读取历史报告。兼容 Windows 与 POSIX 路径。
String discoverApkReport(
    Map<String, String> before, Map<String, String> after) {
  final changed = after.keys
      .where((path) =>
          _reportName.hasMatch(path.replaceAll('\\', '/').split('/').last) &&
          before[path] != after[path])
      .toList()
    ..sort();
  if (changed.length != 1) {
    throw StateError('预期唯一的新 APK 报告，实际 ${changed.length}: $changed');
  }
  return changed.single;
}

/// 读取 [roots] 下的最终报告快照；不跟随符号链接，不接受 snapshot/trace。
Map<String, String> apkReportSnapshot(List<Directory> roots) => {
      for (final root in roots)
        if (root.existsSync())
          for (final file in root
              .listSync(recursive: true, followLinks: false)
              .whereType<File>())
            if (_reportName.hasMatch(file.uri.pathSegments.last))
              file.absolute.path:
                  '${file.statSync().modified.microsecondsSinceEpoch}:${file.lengthSync()}',
    };
