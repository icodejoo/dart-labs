import 'package:flutter/material.dart';
import 'package:luckdraw/compat.dart';
import 'package:luckdraw/wheel.dart';

import '../demo_shell.dart';
import '../online/localized_config.dart';

/// lucky-canvas JSON 迁移示例；例如 `const CompatPage()`。
class CompatPage extends StatefulWidget {
  /// 创建迁移页。
  const CompatPage({super.key});

  /// 创建状态。
  @override
  State<CompatPage> createState() => _CompatPageState();
}

/// 严格模式转换一次并展示告警。
class _CompatPageState extends State<CompatPage> {
  /// 页面控制器。
  final WheelController _controller = WheelController();

  /// 转换后的配置及告警。
  final _converted = wheelFromLuckyCanvasConfig(<String, dynamic>{
    'width': demoSide,
    'height': demoSide,
    'defaultStyle': {'fontStyle': 'Microsoft YaHei'},
    'blocks': [
      {'padding': '14px', 'background': '#617df2'},
      {'padding': '3px', 'background': '#ffd68b'},
      {'padding': '3px', 'background': '#fffbf2'},
    ],
    'prizes': [
      {
        'background': '#e9e8fe',
        'fonts': [
          {
            'text': '谢谢参与',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
      {
        'background': '#b8c5f2',
        'fonts': [
          {
            'text': '一等奖',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
      {
        'background': '#e9e8fe',
        'fonts': [
          {
            'text': '惊喜礼盒',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
      {
        'background': '#b8c5f2',
        'fonts': [
          {
            'text': '好运星',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
      {
        'background': '#e9e8fe',
        'fonts': [
          {
            'text': '幸运好礼',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
      {
        'background': '#b8c5f2',
        'fonts': [
          {
            'text': '元气礼包',
            'top': '12%',
            'fontColor': '#25345b',
            'fontSize': '14px'
          }
        ]
      },
    ],
    'buttons': [
      {'radius': '34%', 'background': '#ffd68b'},
      {
        'radius': '30%',
        'pointer': true,
        'background': '#4059c7',
        'fonts': [
          {
            'text': '开始',
            'fontColor': '#ffffff',
            'fontSize': '18px',
            'top': '-10px'
          }
        ]
      }
    ],
  }, options: LuckyCanvasCompatOptions.strictUpstream());

  /// 结算文本。
  String _result = '';

  /// 以显式转换函数迁移，不依赖内部源码入口。
  @override
  Widget build(BuildContext context) => DemoShell(
      title: 'compat 迁移',
      phase: _controller.phase,
      result: '$_result\n${_converted.warnings.join('\n')}',
      reset: () {
        _controller.reset();
        setState(() => _result = '');
      },
      start: () {
        _controller.play();
      },
      serverResult: () {
        _controller.stop(demoTarget);
      },
      game: LuckyWheel(
          config: demoConfig(context, _converted.config),
          controller: _controller,
          width: _converted.width,
          height: _converted.height,
          onStart: () {
            _controller.play();
          },
          onEnd: (result) => setState(() => _result = '奖品：${result.index}')));

  /// 释放页面控制器。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
