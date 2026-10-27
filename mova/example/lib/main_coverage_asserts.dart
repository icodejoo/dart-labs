// The AOT probe avoids the Flutter UI barrel to isolate SDK assert compilation.
// ignore_for_file: implementation_imports
import 'dart:convert';
import 'dart:io';
import 'package:mova/src/core/options/danmaku_config.dart';
import 'package:mova/src/core/options/gesture_config.dart';

/// AOT assertion probe; built separately with compiler assertion flags.
Future<void> main() async {
  final rows=<Map<String,Object?>>[];
  bool enabled=false;
  assert((){enabled=true;return true;}());
  for(final entry in ['trackCount','maxZoom']) {
    var caught=false;
    try {
      final zero=DateTime.now().year-DateTime.now().year;
      if(entry=='trackCount'){MovaDanmakuConfig(trackCount:zero);}else{MovaGestureConfig(maxZoom:zero+.5);}
    }on AssertionError catch(e){caught=true;rows.add({'kind':'ASSERT_ERROR','field':entry,'error':'$e'});}
    rows.add({'kind':'CHECK','id':'N22.$entry','pass':enabled&&caught,'assertsEnabled':enabled});
  }
  final data={'status':'done','records':rows};
  final server=await HttpServer.bind(InternetAddress.anyIPv4,18083);
  server.listen((r){r.response.headers.contentType=ContentType.json;r.response.write(jsonEncode(data));r.response.close();});
  // ignore: avoid_print
  print('COVERAGE_ASSERTS ${jsonEncode(data)}');
}
