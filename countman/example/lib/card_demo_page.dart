import 'package:countman/countman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';
import 'demo_samples.dart';
import 'sample_code.dart';

/// 合并卡片效果矩阵与表盘，解释共享位图缓存。
class CardDemoPage extends StatefulWidget {
  /// 创建渲染器页面。
  const CardDemoPage({super.key});

  /// 创建重播状态。
  @override
  State<CardDemoPage> createState() => _CardDemoPageState();
}

/// 管理渲染器重播及缓存操作反馈。
class _CardDemoPageState extends State<CardDemoPage> {
  /// 演示的重播代次。
  int _generation = 0;

  /// 重新开始所有渲染器。
  void _restart() => setState(() => _generation++);

  /// 释放位图缓存并说明下次绘制行为。
  void _clear() {
    clearDemoBitmapCaches();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            context,
            'Bitmap caches released; rebuilt on demand.',
            '位图缓存已释放；后续按需重建。',
          ),
        ),
      ),
    );
  }

  /// 构建一个本地化的卡片渲染器。
  Widget _card(CountdownType type) => cardSample(
    type,
    tr(context, 'min', '分'),
    tr(context, 'sec', '秒'),
    tr(context, 'Countdown', '倒计时'),
  );

  /// 构建紧凑渲染器网格与全宽缓存说明。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, 'Card & dial', '卡片与表盘'),
    description: tr(
      context,
      'Compare three card transitions and a painted dial. Shared bitmaps are created on demand.',
      '对比三种卡片过渡和自绘表盘；共享位图按需创建。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Choose a renderer', '选择渲染器'),
        code: combineSampleCode(['card', 'dial']),
        child: KeyedSubtree(
          key: ValueKey(_generation),
          child: DemoGrid(
            children: [
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Calendar', '日历翻页'),
                  description: tr(
                    context,
                    'A continuous calendar-style digit transition.',
                    '日历式数字过渡。',
                  ),
                  child: Column(
                    children: [
                      _card(CountdownType.calendar),
                      TextButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(tr(context, 'Replay all', '全部重播')),
                      ),
                    ],
                  ),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Slide', '滑动'),
                  description: tr(
                    context,
                    'Short sliding transitions between second boundaries.',
                    '在秒边界之间完成短滑动过渡。',
                  ),
                  child: _card(CountdownType.slide),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: tr(context, 'Flip', '翻转'),
                  description: tr(
                    context,
                    'Perspective flip, configured through CardCountdownStyle.',
                    '通过 CardCountdownStyle 配置透视翻转。',
                  ),
                  child: _card(CountdownType.flip),
                ),
              ),
              DemoGridItem(
                child: DemoCard(
                  title: 'DialCountdown',
                  description: tr(
                    context,
                    'Cached tick ring with a custom center builder.',
                    '缓存刻度环，中心内容由 builder 构建。',
                  ),
                  child: Center(child: dialSample()),
                ),
              ),
            ],
          ),
        ),
      ),
      DemoSection(
        title: tr(context, 'Shared bitmap caches', '共享位图缓存'),
        code: sampleCode['cache'],
        child: DemoGrid(
          children: [
            DemoGridItem(
              span: 0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoNote(
                    text: tr(
                      context,
                      'clearTickImageCache and clearFaceImageCache release shared bitmaps. They do not repaint or clear glyph caches. The next paint rebuilds what it needs.',
                      'clearTickImageCache 和 clearFaceImageCache 释放共享位图；不会主动重绘，也不清理字形缓存。下次绘制时按需重建。',
                    ),
                  ),
                  const SizedBox(height: DemoTokens.gap),
                  OutlinedButton(
                    onPressed: _clear,
                    child: Text(tr(context, 'Release bitmap caches', '释放位图缓存')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
