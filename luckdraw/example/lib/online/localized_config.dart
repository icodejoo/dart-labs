import 'package:flutter/material.dart';
import 'package:luckdraw/capsule.dart';
import 'package:luckdraw/grid.dart';
import 'package:luckdraw/lots.dart';
import 'package:luckdraw/lotto.dart';
import 'package:luckdraw/number_wheel.dart';
import 'package:luckdraw/slot.dart';
import 'package:luckdraw/wheel.dart';

import '../demo_kit/demo_kit.dart';

/// 画布缩放后仍可阅读的基础字号。
const _canvasFontSize = 20.0;

/// 纵向玩法缩放后仍可阅读的字号。
const _tallFontSize = 24.0;

/// 旧画布中装饰编号与奖品名称的分隔符。
const _prizeSeparator = ' · ';

/// 重复奖品名称的英文文案。
const _gift = 'Gift';

/// 重复好运奖品的英文文案。
const _luck = 'Luck';

/// 重复奖励奖品的英文文案。
const _bonus = 'Bonus';

/// 画布开始按钮的英文文案。
const _startEn = 'Start';

/// 画布开始按钮的中文文案。
const _startZh = '开始';

/// 示例画布的中英文词汇；未列出的字母和号码保持原样。
const _canvasWords = {
  '谢谢参与': 'Try again',
  '一等奖': 'Top prize',
  '惊喜礼盒': 'Gift box',
  '好运星': 'Lucky star',
  '幸运好礼': 'Lucky gift',
  '元气礼包': 'Bonus pack',
  _startZh: _startEn,
  '礼盒': _gift,
  '大奖': 'Prize',
  '好礼': _gift,
  '惊喜': 'Wow',
  '幸运': _luck,
  '元气': _bonus,
  '心意': _gift,
  '福气': _luck,
  '宝石': 'Gem',
  '星章': 'Star',
  '礼物': _gift,
  '好运': _luck,
};

/// 保留画布文字样式，只替换文案并保证示例文字不小于十三像素。
List<LuckyText> _texts(List<LuckyText> source, bool chinese,
        {double fontSize = _canvasFontSize}) =>
    [
      for (final text in source)
        text.copyWith(
          text: chinese
              ? text.text.split(_prizeSeparator).last
              : _canvasWords[text.text.split(_prizeSeparator).last] ??
                  text.text,
          fontSize:
              (text.fontSize ?? fontSize).clamp(fontSize, double.infinity),
        ),
    ];

/// 为线上宿主翻译公开配置，独立原生回归入口继续使用原始配置。
T demoConfig<T>(BuildContext context, T source) {
  final locale = DemoLocaleScope.maybeOf(context);
  if (locale == null) return source;
  final chinese = locale.isChinese;
  final Object? translated = switch (source) {
    final WheelConfig value => value.copyWith(
        prizes: [
          for (final prize in value.prizes)
            prize.copyWith(texts: _texts(prize.texts, chinese))
        ],
        buttons: [
          for (final button in value.buttons)
            button.copyWith(texts: _texts(button.texts, chinese))
        ],
      ),
    final GridConfig value => value.copyWith(
        prizes: [
          for (final prize in value.prizes)
            prize.copyWith(texts: _texts(prize.texts, chinese))
        ],
        buttons: [
          for (final button in value.buttons)
            button.copyWith(texts: _texts(button.texts, chinese))
        ],
      ),
    final SlotConfig value => value.copyWith(
        prizes: [
          for (final prize in value.prizes)
            prize.copyWith(texts: _texts(prize.texts, chinese))
        ],
      ),
    final CapsuleConfig value => value.copyWith(
        prizes: [
          for (final prize in value.prizes)
            prize.copyWith(
                texts: _texts(prize.texts, chinese, fontSize: _tallFontSize))
        ],
      ),
    final NumberWheelConfig value => value.copyWith(
        style: value.style
            .copyWith(fontSize: _canvasFontSize, textColor: Colors.white)),
    final LottoConfig value => value.copyWith(
          style: LottoStyle(
        drumColor: value.style.drumColor,
        rimColor: value.style.rimColor,
        slotColor: value.style.slotColor,
        buttonColor: value.style.buttonColor,
        buttonTextColor: value.style.buttonTextColor,
        buttonText: chinese ? _startZh : _startEn,
      )),
    final LotsConfig value => value.copyWith(
        style: const LotsStyle(fontSize: _tallFontSize),
        sticks: [
          for (var i = 0; i < value.sticks.length; i++)
            LotsStick(
              label: chinese ? value.sticks[i].label : 'Fortune ${i + 1}',
              weight: value.sticks[i].weight,
              texts: [
                LuckyText(chinese ? value.sticks[i].label : 'Fortune ${i + 1}')
              ],
            ),
        ],
      ),
    _ => source,
  };
  return translated as T;
}
