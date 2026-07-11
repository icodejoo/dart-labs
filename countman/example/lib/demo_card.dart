import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Section counter ───────────────────────────────────────────────────────────
// A plain mutable counter (not Flutter state) — safe to call inside build()
// because it never triggers a Flutter rebuild.

class _SectionCounter {
  int _n = 0;
  int next() => ++_n;
}

// InheritedWidget that carries the counter. Uses getInheritedWidgetOfExactType
// (no dependency registration) so DemoSection reading it won't subscribe to
// updates — we just need the current value, not reactive tracking.
class _SectionScope extends InheritedWidget {
  const _SectionScope({required this.counter, required super.child});
  final _SectionCounter counter;

  static _SectionCounter? _read(BuildContext ctx) =>
      ctx.getInheritedWidgetOfExactType<_SectionScope>()?.counter;

  @override
  bool updateShouldNotify(_SectionScope old) => false; // mutable, not diffed
}

/// Wrap a page body with this widget so every [DemoSection] inside gets a
/// sequential section number starting from 1.
///
/// ```dart
/// body: PageSectionCounter(
///   child: KeyedSubtree(key: ValueKey(_resetKey), child: ListView(...)),
/// ),
/// ```
class PageSectionCounter extends StatelessWidget {
  const PageSectionCounter({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      // Fresh counter on every build so numbering resets correctly after
      // the page's KeyedSubtree reset key changes.
      _SectionScope(counter: _SectionCounter(), child: child);
}

// ── _CardLabel — card-level "2.3" label injected by DemoSection ──────────────

class _CardLabel extends InheritedWidget {
  const _CardLabel({required this.label, required super.child});
  final String label; // e.g., "2.3"

  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardLabel>()?.label;

  @override
  bool updateShouldNotify(_CardLabel old) => label != old.label;
}

// ── DemoSection ───────────────────────────────────────────────────────────────

class DemoSection extends StatelessWidget {
  const DemoSection({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;

  static const _cols    = 6;
  static const _spacing = 8.0;
  static const _hPad    = 12.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Advance the page-level section counter to get this section's number.
    // Falls back to 0 when PageSectionCounter is absent (no prefix shown).
    final sectionIdx = _SectionScope._read(context)?.next() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── section header ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(_hPad, 20, _hPad, 8),
          child: Row(
            children: [
              Expanded(child: Divider(color: cs.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sectionIdx > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$sectionIdx',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                    Text(
                      title.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              Expanded(child: Divider(color: cs.outlineVariant)),
            ],
          ),
        ),
        // ── 6-column Wrap grid ──────────────────────────────────────────────
        Builder(builder: (context) {
          final screenW = MediaQuery.of(context).size.width;
          final cardW   = (screenW - _hPad * 2 - _spacing * (_cols - 1)) / _cols;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: _hPad),
            child: Wrap(
              spacing: _spacing,
              runSpacing: _spacing,
              children: [
                for (final (idx, child) in children.indexed)
                  SizedBox(
                    width: cardW,
                    child: _CardLabel(
                      label: sectionIdx > 0
                          ? '$sectionIdx.${idx + 1}'
                          : '${idx + 1}',
                      child: child,
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── DemoCard ──────────────────────────────────────────────────────────────────

class DemoCard extends StatefulWidget {
  const DemoCard({
    required this.title,
    required this.child,
    required this.code,
    this.description = '',
    super.key,
  });

  final String title;
  final String description;
  final Widget child;
  final String code;

  @override
  State<DemoCard> createState() => _DemoCardState();
}

class _DemoCardState extends State<DemoCard> {
  int _replayKey = 0;

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final text  = Theme.of(context).textTheme;
    final label = _CardLabel.of(context); // e.g., "2.3"

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── "2.3" badge ───────────────────────────────────────────
                if (label != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6, top: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: cs.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                // ── title + description ───────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.description.isNotEmpty)
                        Text(
                          widget.description,
                          style: text.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                            fontSize: 10,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                _MiniButton(
                  icon: Icons.replay_rounded,
                  tooltip: 'Reset',
                  onTap: () => setState(() => _replayKey++),
                ),
                _CopyButton(code: widget.code),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
          // ── demo area ────────────────────────────────────────────────────
          SizedBox(
            height: 130,
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: KeyedSubtree(
                  key: ValueKey(_replayKey),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── _MiniButton ───────────────────────────────────────────────────────────────

class _MiniButton extends StatelessWidget {
  const _MiniButton(
      {required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 15, color: color)),
      ),
    );
  }
}

// ── _CopyButton ───────────────────────────────────────────────────────────────

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Copy runnable code',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _copied
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: widget.code));
                if (!mounted) return;
                setState(() => _copied = true);
                Future.delayed(const Duration(seconds: 2), () {
                  if (mounted) setState(() => _copied = false);
                });
              },
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            _copied ? Icons.check_rounded : Icons.content_copy_outlined,
            size: 15,
            color: _copied
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

String runnable(String body, {String extraImports = ''}) => '''
import 'package:flutter/material.dart';
import 'package:countman/countman.dart';
$extraImports
void main() => runApp(const MaterialApp(
  home: Scaffold(body: SafeArea(child: Center(child: _Demo()))),
));

$body
''';
