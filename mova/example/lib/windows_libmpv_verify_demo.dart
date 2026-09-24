// Windows 真机播放验证 Demo：验证自建瘦身版 libmpv-2.dll 的四项能力
// （H.264/HEVC 播放、D3D11VA 硬解、外挂 ASS 字幕+DirectWrite 字体回退、
// PNG 截图）。接入方式见 mova/example/pubspec.yaml 的 dependency_overrides
// 和 mova/packages/media_kit_libs_windows_video_slim/。
//
// API 已对照本机 pub cache 里的 media_kit-1.2.6/media_kit_video-2.0.1
// 源码逐条核实（player.stream.log、NativePlayer.setProperty/getProperty/
// command、SubtitleTrack.uri 均为真实存在的公开 API）。
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class WindowsLibmpvVerifyDemo extends StatefulWidget {
  const WindowsLibmpvVerifyDemo({super.key});

  @override
  State<WindowsLibmpvVerifyDemo> createState() =>
      _WindowsLibmpvVerifyDemoState();
}

class _WindowsLibmpvVerifyDemoState extends State<WindowsLibmpvVerifyDemo> {
  late final Player player;
  late final VideoController controller;

  final List<String> _fullLog = [];
  String _filteredLog = '暂无匹配日志（hwdec/d3d11va/directwrite/font/screenshot）';
  String _screenshotPath = '尚未截图';

  @override
  void initState() {
    super.initState();
    // debug 级别日志才能看到 hwdec 协商、字体后端选择的底层细节。
    player = Player(
      configuration: const PlayerConfiguration(logLevel: MPVLogLevel.debug),
    );
    controller = VideoController(player);

    player.stream.log.listen((event) {
      final line = '[${event.level}] ${event.prefix}: ${event.text}';
      _fullLog.add(line);
      // 控制台留全量日志，方便真出问题时翻记录。
      // ignore: avoid_print
      print(line);

      final lower = event.text.toLowerCase();
      if (lower.contains('hwdec') ||
          lower.contains('d3d11va') ||
          lower.contains('directwrite') ||
          lower.contains('font') ||
          lower.contains('screenshot')) {
        setState(() => _filteredLog = line);
      }
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  NativePlayer? get _native =>
      player.platform is NativePlayer ? player.platform as NativePlayer : null;

  Future<void> _loadVideo() async {
    final result = await FilePicker.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path == null) return;

    // hwdec 要在 open 之前设，跟 mpv 命令行用法一致。
    try {
      await _native?.setProperty('hwdec', 'auto');
    } catch (e) {
      // ignore: avoid_print
      print('设置 hwdec 失败: $e');
    }

    await player.open(Media(path));
  }

  Future<void> _loadSubtitle() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ass', 'ssa', 'srt'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    try {
      await player.setSubtitleTrack(SubtitleTrack.uri(path));
    } catch (e) {
      // ignore: avoid_print
      print('加载字幕失败: $e');
    }
  }

  Future<void> _takeScreenshot() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // dart:io 自带的系统临时目录，不用额外引入 path_provider。
    final path = '${Directory.systemTemp.path}\\mova_screenshot_$timestamp.png';

    try {
      await _native?.command(['screenshot-to-file', path]);
      final exists = await File(path).exists();
      setState(() => _screenshotPath = exists ? path : '$path（命令已发但文件未生成）');
    } catch (e) {
      setState(() => _screenshotPath = '截图失败: $e');
    }
  }

  Future<void> _checkHwdecStatus() async {
    try {
      final current = await _native?.getProperty('hwdec-current');
      setState(() => _filteredLog = '当前真实硬解状态 (hwdec-current): $current');
    } catch (e) {
      setState(() => _filteredLog = '查询 hwdec-current 失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Windows 自建 libmpv 真机验证')),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Container(color: Colors.black, child: Video(controller: controller)),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('人工核验清单：', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text(
                    '1. 硬解：播放后打开任务管理器→性能→GPU，看 "Video Decode" 引擎'
                    '是否有波动，同时看右下角日志有没有 "Using hardware decoding (d3d11va)"。\n'
                    '2. 字幕：外挂 ASS 后确认没有豆腐块方框，特效正常渲染。\n'
                    '3. 截图：点击后去下方路径核对 PNG 文件内容正常。',
                    style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                  ),
                  const Divider(height: 24),
                  ElevatedButton.icon(
                    onPressed: _loadVideo,
                    icon: const Icon(Icons.video_file),
                    label: const Text('1. 选取并播放视频'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _loadSubtitle,
                    icon: const Icon(Icons.subtitles),
                    label: const Text('2. 加载外挂字幕 (ass/ssa/srt)'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _takeScreenshot,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('3. 截图 (screenshot-to-file)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _checkHwdecStatus,
                    icon: const Icon(Icons.memory),
                    label: const Text('4. 查询 hwdec-current'),
                  ),
                  const Divider(height: 24),
                  const Text('截图路径：', style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(_screenshotPath, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  const Text('关键日志：', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.grey[200],
                      width: double.infinity,
                      child: SingleChildScrollView(
                        child: Text(_filteredLog, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
