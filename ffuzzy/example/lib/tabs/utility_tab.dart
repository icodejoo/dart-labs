// "工具函数" tab: fuzzyCodepointToUtf16, the only Dart-side utility function
// with no FuzzyCorpus equivalent (highlightHtml is JS-only, no Dart card).
//
// "工具函数" Tab：fuzzyCodepointToUtf16，唯一没有 FuzzyCorpus 对应方法的
// Dart 侧工具函数（highlightHtml 是 JS 专属，没有 Dart 卡片）。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';

class UtilityTab extends StatelessWidget {
  const UtilityTab({super.key});

  @override
  Widget build(BuildContext context) {
    const text = 'a😀b中文';
    const codepoints = [0, 1, 2, 3, 4]; // one entry per rune
    final offsets = fuzzyCodepointToUtf16(text, codepoints);
    return DemoGrid(children: [
      DemoCard(
        id: '6.1',
        title: 'fuzzyCodepointToUtf16',
        code: "fuzzyCodepointToUtf16(\n  '$text', $codepoints)",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('text: $text', style: TextStyle(fontSize: 12)),
            Text('codepoint indices: $codepoints', style: const TextStyle(fontSize: 12)),
            Text('utf16 offsets: $offsets', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            const Text(
              '😀 is astral (2 UTF-16 units), so offsets diverge from '
              'codepoint indices after it.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    ]);
  }
}
