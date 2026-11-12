import '../context.dart';

/// source 默认安全方法白名单。
const sourceSafeMethods = {'GET', 'HEAD'};

/// mock 探测期间绕过共享和缓存；只在当前 next 调用期间置位。
final sourceProbe = StateKey<bool>('mock probe');
