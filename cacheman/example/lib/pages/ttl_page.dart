import 'dart:async';
import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../get_storage_cache.dart';
import '../demo_support.dart';

/// 有限计时演示使用的寿命。
const demoLifetime = Duration(seconds: 4);

/// 当前演示的过期策略。
enum ExpiryMode {
  /// 相对毫秒寿命。
  ttl,

  /// 绝对截止时间。
  absolute,

  /// 显式读取续期。
  sliding,
}

/// TTL、绝对过期与滑动续期的入口。
class TtlPage extends StatelessWidget {
  /// 创建过期页面。
  const TtlPage({super.key});

  /// 构建各自拥有计时器和重放生命周期的三张卡片。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.ttl.en, DemoCopy.ttl.zh),
    description: tr(
      context,
      'Each replay writes a fresh 4-second entry. Watching the timer never renews it.',
      '每次重放写入一条 4 秒数据；观察倒计时不会续期。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Watch expiry happen', '观察过期过程'),
        code:
            "cache.write('message', 'Ada', ttl: 4000);\ncache.write('message', 'Ada', expireAt: DateTime.now().add(Duration(seconds: 4)));\n// For sliding renewal, construct with CachemanOptions(sliding: true).\n// Only explicit reads renew; keys() can include expired entries.\ncache.purge();",
        child: DemoGrid(
          children: [
            for (final mode in ExpiryMode.values)
              DemoGridItem(
                child: DemoCard(
                  title: switch (mode) {
                    ExpiryMode.ttl => tr(context, 'Relative TTL', '相对 TTL'),
                    ExpiryMode.absolute => tr(
                      context,
                      'Absolute expiry',
                      '绝对过期',
                    ),
                    ExpiryMode.sliding => tr(
                      context,
                      'Sliding renewal',
                      '滑动续期',
                    ),
                  },
                  description: mode == ExpiryMode.sliding
                      ? tr(
                          context,
                          'Read to renew after at least 10% of the TTL has elapsed.',
                          '寿命经过至少 10% 后，点击读取可续期。',
                        )
                      : tr(
                          context,
                          'Expired entries disappear on read or purge.',
                          '过期项会在读取或 purge 时移除。',
                        ),
                  child: ExpiryDemo(mode: mode),
                ),
              ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'TTL is in milliseconds. An expiry timestamp is not a remaining-duration value. Sliding renewal may extend beyond the initial expireAt.',
          'TTL 单位为毫秒。过期时间戳不是剩余时长；滑动续期可能超过初始 expireAt。',
        ),
      ),
    ],
  );
}

/// 单张过期卡片的独立倒计时主体。
class ExpiryDemo extends StatefulWidget {
  /// 创建指定策略的演示。
  const ExpiryDemo({super.key, required this.mode});

  /// 采用的过期策略。
  final ExpiryMode mode;

  /// 创建计时与读取状态。
  @override
  State<ExpiryDemo> createState() => _ExpiryDemoState();
}

/// 观察底层信封以避免倒计时渲染触发滑动续期。
class _ExpiryDemoState extends State<ExpiryDemo> {
  /// 本卡片独有的缓存实例。
  GetStorageCache? _cache;

  /// 有限寿命的刷新计时器。
  Timer? _timer;

  /// 最近显式读取的结果。
  String? _value;

  /// 是否已经执行过读取。
  bool _hasRead = false;

  /// 是否初始化失败。
  bool _failed = false;

  /// 初始化一次并写入待观察条目。
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 创建独立作用域并启动仅用于渲染的时钟。
  Future<void> _initialize() async {
    try {
      final scope = 'expiry-${widget.mode.name}';
      final cache = await demoCache(
        scope,
        options: CachemanOptions(
          namespace: scope,
          sliding: widget.mode == ExpiryMode.sliding,
        ),
      );
      if (!mounted) return;
      if (widget.mode == ExpiryMode.absolute) {
        cache.write(
          demoKey,
          demoValue,
          expireAt: DateTime.now().add(demoLifetime),
        );
      } else {
        cache.write(demoKey, demoValue, ttl: demoLifetime.inMilliseconds);
      }
      setState(() => _cache = cache);
      _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        setState(() {});
        if (_remaining == 0) _timer?.cancel();
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 直接读取过期元数据，保持观察无续期副作用。
  int get _remaining {
    final cache = _cache;
    if (cache == null) return 0;
    final raw = cache.box.read<String>(cache.storageKey(demoKey));
    if (raw == null) return 0;
    final expiry = defaultDeserialize(raw).expireAt!;
    return (expiry - DateTime.now().millisecondsSinceEpoch).clamp(
      0,
      demoLifetime.inMilliseconds,
    );
  }

  /// 显式读取才触发库的续期或懒删除行为。
  void _read() => setState(() {
    _value = _cache!.read<String>(demoKey);
    _hasRead = true;
  });

  /// 主动删除过期条目并显示实际枚举结果。
  void _purge() => setState(() {
    _cache!.purge();
  });

  /// 停止计时并保存本卡片的待落盘数据。
  @override
  void dispose() {
    _timer?.cancel();
    _cache?.flush();
    super.dispose();
  }

  /// 构建实时剩余时间、显式读取和清理操作。
  @override
  Widget build(BuildContext context) {
    final cache = _cache;
    if (_failed) {
      return Text(
        tr(
          context,
          DemoCopy.initializationFailed.en,
          DemoCopy.initializationFailed.zh,
        ),
      );
    }
    if (cache == null) {
      return Text(
        tr(context, DemoCopy.initializing.en, DemoCopy.initializing.zh),
      );
    }
    final remaining = _remaining;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          remaining > 0
              ? tr(
                  context,
                  'Remaining: ${(remaining / 1000).toStringAsFixed(1)} s',
                  '剩余：${(remaining / 1000).toStringAsFixed(1)} 秒',
                )
              : tr(context, 'Expired', '已过期'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: DemoTokens.smallGap),
        Wrap(
          spacing: DemoTokens.smallGap,
          runSpacing: DemoTokens.smallGap,
          children: [
            FilledButton.tonal(
              onPressed: _read,
              child: Text(tr(context, DemoCopy.read.en, DemoCopy.read.zh)),
            ),
            OutlinedButton(
              onPressed: _purge,
              child: Text(tr(context, 'Purge', '清理过期')),
            ),
          ],
        ),
        Text(
          tr(context, 'Stored keys: ${cache.length}', '存储键数：${cache.length}'),
        ),
        if (_hasRead) Text(tr(context, 'Read result: $_value', '读取结果：$_value')),
      ],
    );
  }
}
