import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:xvg/src/rust/api/svg.dart';
import 'package:xvg/src/rust/frb_generated.native.dart' show RustLibApi;
import 'package:xvg/src/xvg_raster_cache.dart';
import 'package:xvg/xvg.dart';

/// 返回加入畸形命令后的场景。
class _SceneApi implements RustLibApi {
  /// 用接下来要重放的场景替换解析结果。
  _SceneApi(this.scene);

  /// 本轮重放使用的场景。
  final SvgScene scene;

  /// 返回测试组装的场景。
  @override
  SvgScene crateApiSvgParseSvgWithMergePolicy({
    required String data,
    int? currentColor,
    bool allowPathMerge = false,
  }) => scene;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 记录恢复操作，确保重放保留调用者进入前的 Canvas 层。
class _StackCanvas implements ui.Canvas {
  /// 代理真实 Canvas，记录恢复后的层数。
  _StackCanvas(this.canvas);

  /// 实际接收绘制的画布。
  final ui.Canvas canvas;

  /// 每次恢复之后的 Canvas 层数。
  final restoredDepths = <int>[];

  /// 读取真实画布当前层数。
  @override
  int getSaveCount() => canvas.getSaveCount();

  /// 在真实画布保存一层。
  @override
  void save() => canvas.save();

  /// 将透明度层传给真实画布。
  @override
  void saveLayer(ui.Rect? bounds, ui.Paint paint) =>
      canvas.saveLayer(bounds, paint);

  /// 记录恢复操作完成后的层数。
  @override
  void restore() {
    canvas.restore();
    restoredDepths.add(getSaveCount());
  }

  /// 将裁剪传给真实画布。
  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) =>
      canvas.clipPath(path, doAntiAlias: doAntiAlias);

  /// 将路径绘制传给真实画布。
  @override
  void drawPath(ui.Path path, ui.Paint paint) => canvas.drawPath(path, paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 测试视口宽度。
const _width = 20;

/// 测试视口高度。
const _height = 10;

/// 裁剪红色底图的左半，蓝色兄弟在裁剪区域之外。
const _source =
    '''
<svg xmlns="http://www.w3.org/2000/svg" width="$_width" height="$_height">
  <defs><clipPath id="left"><rect width="10" height="10"/></clipPath></defs>
  <g clip-path="url(#left)"><rect width="20" height="10" fill="red"/></g>
  <rect x="17" y="2" width="3" height="6" fill="blue"/>
</svg>
''';

/// 手工注入的无效数组下标。
const _invalidIndex = 99;

/// 构造测试用静态命令。
SvgCommand _command(int kind, [int index = 0]) =>
    SvgCommand(kind: kind, index: index, opacity: .5);

/// 读取中间扫描线指定列的 RGBA。
int _pixel(ByteData bytes, int x) =>
    bytes.getUint32(((_height ~/ 2) * _width + x) * Uint32List.bytesPerElement);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('complex SVG with unknown bounds caches the full viewport', (
    tester,
  ) async {
    await tester.runAsync(RustLib.init);
    final original = parseSvg(
      data:
          '<svg xmlns="http://www.w3.org/2000/svg" width="700" height="120">'
          '${List.filled(100, '<rect x="10" y="10" width="60" height="60" fill="red"/>').join()}'
          '</svg>',
    );
    RustLib.dispose();
    RustLib.initMock(
      api: _SceneApi(
        SvgScene(
          width: original.width,
          height: original.height,
          paths: original.paths,
          images: original.images,
          displayList: original.displayList,
        ),
      ),
    );
    addTearDown(() {
      RustXvgPictureCache.instance.clear();
      RustLib.dispose();
      tester.view.reset();
    });
    const source = 'mocked complex SVG with unknown bounds';
    final info = RustXvgPictureCache.instance.getOrRender(source);
    expect(info.pathCount, greaterThanOrEqualTo(xvgRasterMinPaths));
    expect(info.contentBounds, isNull);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 160);
    await tester.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: StaticXvg(source, pixelSnap: XvgPixelSnap.never),
      ),
    );
    expect(XvgRasterCache.tileCount, 1);
    expect(XvgRasterCache.bytesUsed, 700 * 120 * Uint32List.bytesPerElement);
    expect(debugXvgRasterTilesReady, isTrue);
  });

  test('malformed commands cannot unwind the caller canvas stack', () async {
    await RustLib.init();
    final original = parseSvg(data: _source);
    RustLib.dispose();
    const drawPath = 0;
    const pushOpacity = 2;
    const popOpacity = 3;
    const pushClip = 4;
    const popClip = 5;
    RustLib.initMock(
      api: _SceneApi(
        SvgScene(
          width: original.width,
          height: original.height,
          paths: original.paths,
          images: original.images,
          displayList: SvgDisplayList(
            clips: original.displayList!.clips,
            commands: [
              _command(popOpacity),
              _command(pushClip),
              _command(drawPath, -1),
              _command(popClip, _invalidIndex),
              _command(drawPath),
              _command(pushClip, _invalidIndex),
              _command(drawPath, _invalidIndex),
              _command(popClip, _invalidIndex),
              _command(popClip),
              _command(drawPath, 1),
              _command(pushOpacity),
              _command(pushClip),
              _command(popOpacity),
              _command(drawPath),
            ],
          ),
        ),
      ),
    );
    final cache = RustXvgPictureCache.instance;
    late _StackCanvas audit;
    RustXvgPictureCache.debugWrapRecordingCanvas = (canvas) =>
        audit = _StackCanvas(canvas)..save();
    addTearDown(() {
      RustXvgPictureCache.debugWrapRecordingCanvas = null;
      cache.clear();
      RustLib.dispose();
    });
    final info = cache.getOrRender(_source);
    expect(audit.restoredDepths, everyElement(greaterThanOrEqualTo(2)));
    expect(audit.restoredDepths.last, 2);
    final image = await info.picture.toImage(_width, _height);
    try {
      final pixels = (await image.toByteData())!;
      expect(_pixel(pixels, 5), 0xff0000ff);
      expect(_pixel(pixels, 12), 0);
      expect(_pixel(pixels, 18), 0x0000ffff);
    } finally {
      image.dispose();
      info.picture.dispose();
    }
  });
}
