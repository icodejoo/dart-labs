// Persistent SVG grid for side-by-side screenshot comparison with Chrome.
// Read external SVG files in filename order; no SVG assets are bundled here.
// 常驻 SVG 目测网格，用于与 Chrome 渲染同批文件的截图并排比较。
// 按文件名排序读取外部 SVG；本页不捆绑任何 SVG 素材。
//
// Android reproduction, from benchmark/bench_app (operator commands only):
// Android 复现，在 benchmark/bench_app 下由操作者执行：
//   flutter build apk --profile --target-platform android-arm64 --dart-define=LIB=svg_grid
//   adb -s 7NQBB23606003715 install -r build/app/outputs/flutter-apk/app-profile.apk
// First launch once to create the files directory, then push and relaunch.
// 首次启动需先运行一次，让应用创建 files 目录，然后推送并重新启动。
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
//   adb -s 7NQBB23606003715 push <本地目录>/. /sdcard/Android/data/com.example.bench_app/files/svg_grid
//   adb -s 7NQBB23606003715 shell am force-stop com.example.bench_app
//   adb -s 7NQBB23606003715 shell am start -n com.example.bench_app/.MainActivity
// Wait for SVGGRID ready before capturing; the page never exits itself.
// 等待 SVGGRID ready 后截图；页面不会自动退出。
//   adb exec-out screencap -p > shot.png
// With multiple devices, add -s 7NQBB23606003715 to the screenshot command.
// 多设备时，为截图命令加上 -s 7NQBB23606003715。
// Configure GRID_DIR, GRID_COLS=9, GRID_START=0 and GRID_COUNT=144 at build time.
// 构建时可通过 --dart-define 配置 GRID_DIR、GRID_COLS=9、GRID_START=0、GRID_COUNT=144。

// Direct stdout is consumed by logcat. / 直接输出到 stdout，供 logcat 采集。
// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// Reuse Xvg's dispatch detector so readiness follows the actual renderer.
// 复用 Xvg 的分流检测器，让就绪统计与实际渲染路径一致。
// ignore: implementation_imports
import 'package:xvg/src/animation/animation_detector.dart';
import 'package:xvg/xvg.dart';

const _gridDir = String.fromEnvironment(
  'GRID_DIR',
  defaultValue: '/sdcard/Android/data/com.example.bench_app/files/svg_grid',
);
const _gridCols = int.fromEnvironment('GRID_COLS', defaultValue: 9);
const _gridStart = int.fromEnvironment('GRID_START', defaultValue: 0);
const _gridCount = int.fromEnvironment('GRID_COUNT', defaultValue: 144);
const _background = Color(0xFFFDF8FD);
/// Renders with flutter_svg instead of xvg, for side-by-side checks.
/// 改用 flutter_svg 渲染，用于并排对照。
const _useFlutterSvg =
    String.fromEnvironment('GRID_RENDERER') == 'flutter_svg';

/// Icon size relative to the cell; override to test pixel alignment.
/// 图标占格宽比例；可覆盖，用于测试像素对齐。
final _iconScale = double.parse(
  const String.fromEnvironment('GRID_ICON_SCALE', defaultValue: '0.78'),
);
const _labelSize = 8.0;
const _labelInset = 2.0;
const _logPrefix = 'SVGGRID';
const _errorLabel = Text(
  'ERR',
  style: TextStyle(color: Colors.red, fontSize: _labelSize),
);
final _indexPrefix = RegExp(r'^\d+');

/// Shows one sorted slice without automatic scrolling or process exit.
/// 展示排序后的一段文件，不自动滚动或退出进程。
class SvgGridScreen extends StatefulWidget {
  const SvgGridScreen({super.key});

  @override
  State<SvgGridScreen> createState() => _SvgGridScreenState();
}

class _SvgGridScreenState extends State<SvgGridScreen> {
  List<File> _files = const [];
  final _finished = <int>{};
  final _errors = <int>{};
  bool _listed = false;
  bool _directoryError = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  Future<void> _loadDirectory() async {
    try {
      if (_gridCols <= 0 || _gridStart < 0 || _gridCount < 0) {
        throw ArgumentError('GRID_COLS > 0, GRID_START >= 0, GRID_COUNT >= 0');
      }
      // Also creates the app's external files directory on the first launch.
      // 首次启动也会创建应用的外部 files 目录。
      final directory = await Directory(_gridDir).create(recursive: true);
      final files = await directory
          .list(followLinks: false)
          .where((entry) => entry is File && entry.path.endsWith('.svg'))
          .cast<File>()
          .toList();
      files.sort((a, b) => _fileName(a).compareTo(_fileName(b)));
      if (!mounted) return;
      setState(() {
        _files = files.skip(_gridStart).take(_gridCount).toList();
        _listed = true;
      });
      // Keep the selected static pictures cached until all cells are built.
      // 保留本批静态 picture，避免全部格子构建前发生缓存淘汰。
      final cache = RustXvgPictureCache.instance;
      if (cache.maximumSize < _files.length) {
        cache.maximumSize = _files.length;
      }
    } catch (error) {
      if (!mounted) return;
      print('$_logPrefix error index=-1 name=$_gridDir error=$error');
      setState(() {
        _directoryError = true;
        _listed = true;
        _errors.add(-1);
      });
    }
    _reportReady();
  }

  void _complete(int position, Object? error) {
    if (!mounted) return;
    if (error != null && _errors.add(position)) {
      final file = _files[position];
      print(
        '$_logPrefix error index=${_fileIndex(file, position)} '
        'name=${_fileName(file)} error=$error',
      );
    }
    _finished.add(position);
    _reportReady();
  }

  void _reportReady() {
    if (!_listed || _ready || _finished.length != _files.length) return;
    _ready = true;
    // Print after a frame containing the final loaded/error cell is painted.
    // 在最后一个加载成功或失败的格子完成绘制后打印。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        print(
          '$_logPrefix ready count=${_files.length} errors=${_errors.length}',
        );
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        child: _directoryError
            ? const Center(child: _errorLabel)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = constraints.maxWidth / _gridCols;
                  // Eagerly mount every cell, including those below the fold.
                  // 一次挂载全部格子，包括首屏下方内容，默认停在顶部。
                  return SingleChildScrollView(
                    child: Wrap(
                      children: [
                        for (var i = 0; i < _files.length; i++)
                          _SvgGridCell(
                            file: _files[i],
                            index: _fileIndex(_files[i], i),
                            width: cellWidth,
                            onComplete: (error) => _complete(i, error),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

String _fileName(File file) => file.uri.pathSegments.last;

String _fileIndex(File file, int position) =>
    _indexPrefix.stringMatch(_fileName(file)) ?? '${_gridStart + position}';

class _SvgGridCell extends StatefulWidget {
  const _SvgGridCell({
    required this.file,
    required this.index,
    required this.width,
    required this.onComplete,
  });

  final File file;
  final String index;
  final double width;
  final ValueChanged<Object?> onComplete;

  @override
  State<_SvgGridCell> createState() => _SvgGridCellState();
}

class _SvgGridCellState extends State<_SvgGridCell> {
  String? _source;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final source = await widget.file.readAsString();
      final animated = AnimationDetector.hasAnimations(source);
      if (_useFlutterSvg) {
        // flutter_svg has no load callback here; report after the first frame.
        // flutter_svg 此处无加载回调；首帧后上报。
        if (!mounted) return;
        setState(() => _source = source);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete(null);
        });
        return;
      }
      // Static Xvg has no onLoaded; await parsing and embedded image decoding.
      // 静态 Xvg 没有 onLoaded；先等待解析及内嵌图片解码完成。
      if (!animated) {
        await RustXvgPictureCache.instance.getOrRenderAsync(source);
      }
      if (!mounted) return;
      setState(() => _source = source);
      if (!animated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onComplete(null);
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _failed = true);
      widget.onComplete(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final iconWidth = widget.width * _iconScale;
    return SizedBox.square(
      dimension: widget.width,
      child: Stack(
        children: [
          Center(
            child: _failed
                ? _errorLabel
                : source == null
                ? const SizedBox.shrink()
                : _useFlutterSvg
                ? SvgPicture.string(source, width: iconWidth, height: iconWidth)
                : Xvg.string(
                    source,
                    width: iconWidth,
                    height: iconWidth,
                    onLoaded: (_) => widget.onComplete(null),
                    onError: (error, _) => widget.onComplete(error),
                    errorBuilder: (_, _, _) => _errorLabel,
                  ),
          ),
          Positioned(
            top: _labelInset,
            left: _labelInset,
            child: Text(
              widget.index,
              style: const TextStyle(
                fontSize: _labelSize,
                color: Color(0xFFBBBBBB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
