/// 浏览器没有原生 IO 异常，网络分类由 Dio 的跨平台类型承担。
bool isDiomanNetworkError(Object? cause) => false;
