import 'package:flutter_test/flutter_test.dart';
import 'package:fvideo/fvideo.dart';
import 'package:fvideo/fvideo_platform_interface.dart';
import 'package:fvideo/fvideo_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFvideoPlatform
    with MockPlatformInterfaceMixin
    implements FvideoPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FvideoPlatform initialPlatform = FvideoPlatform.instance;

  test('$MethodChannelFvideo is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFvideo>());
  });

  test('getPlatformVersion', () async {
    Fvideo fvideoPlugin = Fvideo();
    MockFvideoPlatform fakePlatform = MockFvideoPlatform();
    FvideoPlatform.instance = fakePlatform;

    expect(await fvideoPlugin.getPlatformVersion(), '42');
  });
}
