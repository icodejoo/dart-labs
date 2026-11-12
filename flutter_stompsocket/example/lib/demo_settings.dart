/// 演示使用的稳定配置，避免页面之间出现不同的默认值。
abstract final class DemoSettings {
  /// 包名称。
  static const project = 'flutter_stompsocket';

  /// 包介绍地址。
  static const pubUrl = 'https://pub.dev/packages/$project';

  /// 仓库内的包目录。
  static const githubUrl =
      'https://github.com/icodejoo/dart-labs/tree/main/$project';

  /// 当前包的英文文档。
  static const readmeUrl =
      'https://github.com/icodejoo/dart-labs/blob/main/$project/README.md';

  /// 打包时直接读取的包配置资源。
  static const packageManifest = '../pubspec.yaml';

  /// 用户自行替换的连接地址，不自动连接公共服务器。
  static const brokerUrl = 'wss://broker.example.com/ws';

  /// 默认接收目的地。
  static const topic = '/topic/demo';

  /// 默认发送目的地。
  static const destination = '/app/message';

  /// 编辑器的初始 JSON。
  static const jsonBody = '{"message":"hello"}';

  /// 缓冲大小，沿用库的默认值。
  static const queueLimit = 100;

  /// 界面保留的最近日志数量。
  static const logLimit = 20;

  /// 演示界面允许同时登记的回调数量。
  static const subscriptionLimit = 8;

  /// 离线预览的连接时间，不代表实际 broker 延迟。
  static const previewDelay = Duration(milliseconds: 500);

  /// 离线预览的重连时间，不代表库的重连间隔。
  static const previewReconnectDelay = Duration(seconds: 2);

  /// 真实连接的超时，避免输入错误地址后无限等待握手。
  static const connectionTimeout = Duration(seconds: 10);

  /// 真实连接的重试间隔，沿用库的默认值。
  static const reconnectDelay = Duration(seconds: 5);
}
