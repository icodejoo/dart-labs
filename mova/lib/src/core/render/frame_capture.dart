import 'dart:typed_data';

/// 可选的当前画面截图能力，不扩充 IMovaApi。
///
/// 宿主在池 bind 后调用 `await (api as IMovaFrameCapture).screenshot()`。
/// 暂停时最多等待 2 秒，按递增间隔重新截图直到取得非空编码图片；
/// 不以首帧信号作为截图成功的判据；返回图片即表示本次画面可截，
/// 返回 null 表示超时、无视频、切源、销毁或截图失败，不能据此宣称就绪。
/// 这不是 Flutter 合成器已经显示纹理的保证，也不会播放或 seek 来催帧。
abstract interface class IMovaFrameCapture {
  /// 获取当前画面；暂停时有界等待可读帧，失败返回 null。
  ///
  /// 示例：`final image = await (api as IMovaFrameCapture).screenshot();`。
  /// 自定义播放器可不实现本能力，宿主先用 `is IMovaFrameCapture` 探测。
  Future<Uint8List?> screenshot();
}
