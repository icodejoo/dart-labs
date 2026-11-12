import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Transparent transport observer: the real plugin still receives every call
/// and delivers every reply. No mock handler or replacement VideoController.
final videoCalls = <Map<String, Object?>>[];

class S00eBinding extends WidgetsFlutterBinding {
  static WidgetsBinding ensureTracing() {
    // Coverage suite and standalone API entry both call this before runApp.
    // Reuse an existing binding; never replace a live ServicesBinding.
    try { return WidgetsBinding.instance; }
    on Object { return S00eBinding(); }
  }
  @override
  BinaryMessenger createBinaryMessenger() => TraceMessenger(super.createBinaryMessenger());
}

class TraceMessenger implements BinaryMessenger {
  TraceMessenger(this.inner);
  final BinaryMessenger inner;
  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    Map<String, Object?>? row;
    if (channel == 'com.alexmercerind/media_kit_video' && message != null) {
      final call = const StandardMethodCodec().decodeMethodCall(message);
      if (call.method == 'VideoOutputManager.Create' || call.method == 'VideoOutputManager.Dispose') {
        row = {'method': call.method, 'arguments': call.arguments, 'replied': false};
        videoCalls.add(row);
      }
    }
    final response = await inner.send(channel, message);
    if (row != null) {
      try {
        if (response == null) { row['replyError'] = 'missing plugin'; }
        else { const StandardMethodCodec().decodeEnvelope(response); row['replied'] = true; }
      } on Object catch (error) { row['replyError'] = '$error'; }
    }
    return response;
  }
  @override
  Future<void> handlePlatformMessage(String channel, ByteData? data, PlatformMessageResponseCallback? callback) async {
    ServicesBinding.instance.channelBuffers.push(channel, data, callback ?? (_) {});
  }
  @override
  void setMessageHandler(String channel, Future<ByteData?>? Function(ByteData?)? handler) => inner.setMessageHandler(channel, handler);
}
