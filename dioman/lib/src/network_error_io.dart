import 'dart:io';

/// 精确识别原生网络原因，避免把程序异常归为网络失败。
bool isDiomanNetworkError(Object? cause) =>
    cause is SocketException || cause is HttpException || cause is TlsException;
