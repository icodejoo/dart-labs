import 'package:flutter/foundation.dart';
import 'package:flutter_stompsocket/flutter_stompsocket.dart';

final stateNotifier = ValueNotifier<StompConnectionState>(StompConnectionState.idle);
final messageLog = ValueNotifier<List<String>>([]);
Stompsocket? activeSocket;

void addLog(String msg) {
  final now = DateTime.now();
  final t =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  messageLog.value = [...messageLog.value, '[$t] $msg'];
}
