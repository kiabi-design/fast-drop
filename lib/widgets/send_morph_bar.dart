import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'liquid_glass.dart';

class MorphMenuItem {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const MorphMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

/// Кнопка, которая по нажатию плавно «перетекает» в стеклянную панель с пунктами
/// (как нижняя панель вкладок в iOS Liquid Glass).
class SendMorphBar extends StatefulWidget {
  final bool expanded;
  final bool enabled;
  final bool active;
  final bool isWhite;
  final String label;
  final IconData icon;
  final List<MorphMenuItem> items;
  final VoidCallback onPressed;
  final VoidCallback onClose;

  const SendMorphBar({
    super.key,
    required this.expanded,
    required this.isWhite,
    required this.label,
    required this.icon,
    required this.items,
    required this.onPressed,
    required this.onClose,
    this.enabled = true,
    this.active = false,
  });

  @override
  State<SendMorphBar> createState() => _SendMorphBarState();
}

class _SendMorphBarState extends State<SendMorphBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _t;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
      reverseDuration: const Duration(milliseconds: 340),
    );
    _t = CurvedAnimation(
      parent: _c,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    if (widget.expanded) _c.value = 1.0;
  }

  @override
  void didUpdateWidget(covariant SendMorphBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expanded != widget.expanded) {
      if (widget.expanded) {
        HapticFeedback.lightImpact();
        _c.forward();
      } else {
        _c.reverse();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _collapsedWidth() {
    final tp = TextPainter(
      text: TextSpan(
        text: widget.label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return 22 * 2 + 19 + 8 + tp.width + 2;
  }

  Widget _collapsedContent(GlassPalette p) {
    final color = widget.active ? p.accent : p.fg;
    return Opacity(
      opacity: widget.enabled ? 1.0 : 0.45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled
            ? () {
                HapticFeedback.selectionClick();
                widget.onPressed();
              }
            : null,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 19, color: color),
              const SizedBox(width: 8),
              Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandedContent() {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in widget.items)
            Expanded(
              child: _MorphItemButton(
                icon: item.icon,
                label: item.label,
                isWhite: widget.isWhite,
                onTap: item.onTap,
              ),
            ),
          SizedBox(
            width: 46,
            child: _MorphCloseButton(
              isWhite: widget.isWhite,
              onTap: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(widget.isWhite);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final cw = math.min(_collapsedWidth(), maxW);

        return AnimatedBuilder(
          animation: _t,
          builder: (context, _) {
            final t = _t.value.clamp(0.0, 1.0).toDouble();
            final width = cw + (maxW - cw) * t;
            final height = 52.0 + (76.0 - 52.0) * t;
            final collapsedOpacity = (1.0 - t * 2.4).clamp(0.0, 1.0).toDouble();
            final expandedOpacity = ((t - 0.4) / 0.6).clamp(0.0, 1.0).toDouble();

            return Center(
              child: SizedBox(
                width: width,
                height: height,
                child: GlassCard(
                  isWhite: widget.isWhite,
                  radius: 999,
                  blur: 10,
                  padding: EdgeInsets.zero,
                  tint: (widget.active && !widget.expanded) ? p.accent : null,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: widget.expanded || collapsedOpacity < 0.5,
                          child: Opacity(
                            opacity: collapsedOpacity,
                            child: _collapsedContent(p),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !widget.expanded || expandedOpacity < 0.5,
                          child: Opacity(
                            opacity: expandedOpacity,
                            child: OverflowBox(
                              minWidth: maxW,
                              maxWidth: maxW,
                              alignment: Alignment.center,
                              child: _expandedContent(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MorphItemButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isWhite;
  final VoidCallback onTap;

  const _MorphItemButton({
    required this.icon,
    required this.label,
    required this.isWhite,
    required this.onTap,
  });

  @override
  State<_MorphItemButton> createState() => _MorphItemButtonState();
}

class _MorphItemButtonState extends State<_MorphItemButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(widget.isWhite);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: _down ? p.fg.withOpacity(widget.isWhite ? 0.10 : 0.18) : Colors.transparent,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 24, color: _down ? p.accent : p.fg),
              const SizedBox(height: 3),
              Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _down ? p.accent : p.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MorphCloseButton extends StatelessWidget {
  final bool isWhite;
  final VoidCallback onTap;

  const _MorphCloseButton({required this.isWhite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Center(
        child: Icon(Icons.close_rounded, size: 22, color: p.subtle),
      ),
    );
  }
}