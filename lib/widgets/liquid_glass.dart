import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Включить (true) или выключить (false) медленно плывущий фон.
/// Если на слабом телефоне будут тормоза, поставь false.
const bool kAnimatedBackground = true;

// ───────────────────────── Палитра ─────────────────────────

class GlassPalette {
  final bool isWhite;
  const GlassPalette(this.isWhite);

  Color get accent => isWhite ? const Color(0xFF007AFF) : const Color(0xFF64D2FF);
  Color get fg => isWhite ? const Color(0xFF0B0B12) : Colors.white;
  Color get subtle => isWhite ? const Color(0x990B0B12) : const Color(0xA6FFFFFF);
  Color get danger => const Color(0xFFFF6B7A);
  Color get success => const Color(0xFF5BE49B);
}

// ───────────────────────── Фон ─────────────────────────

class _Blob {
  final double x;
  final double y;
  final double r;
  final double speed;
  final double phase;
  final double opacity;
  final Color color;

  const _Blob(this.x, this.y, this.r, this.speed, this.phase, this.opacity, this.color);
}

class _BlobPainter extends CustomPainter {
  final bool isWhite;

  _BlobPainter(this.isWhite, {Listenable? repaint}) : super(repaint: repaint);

  static const List<_Blob> _dark = [
    _Blob(0.15, 0.12, 0.80, 1, 0.00, 0.42, Color(0xFF2BB8FF)),
    _Blob(0.90, 0.35, 0.85, 2, 0.30, 0.38, Color(0xFF7B5CFF)),
    _Blob(0.18, 0.64, 0.75, 1, 0.55, 0.26, Color(0xFF19D3B0)),
    _Blob(0.85, 0.92, 0.80, 3, 0.80, 0.30, Color(0xFFFF4FA3)),
  ];

  static const List<_Blob> _light = [
    _Blob(0.15, 0.12, 0.80, 1, 0.00, 0.75, Color(0xFF7DB7FF)),
    _Blob(0.90, 0.35, 0.85, 2, 0.30, 0.65, Color(0xFFC4B5FF)),
    _Blob(0.18, 0.64, 0.75, 1, 0.55, 0.65, Color(0xFFA8F0D8)),
    _Blob(0.85, 0.92, 0.80, 3, 0.80, 0.70, Color(0xFFFFB3D9)),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Фаза считается по часам, поэтому на всех экранах фон «плывёт» синхронно.
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = (now % 60000) / 60000.0;
    final blobs = isWhite ? _light : _dark;

    for (final b in blobs) {
      final ang = 2 * math.pi * (t * b.speed + b.phase);
      final cx = size.width * (b.x + 0.10 * math.cos(ang));
      final cy = size.height * (b.y + 0.07 * math.sin(ang));
      final radius = size.shortestSide * b.r;
      final center = Offset(cx, cy);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            b.color.withOpacity(b.opacity),
            b.color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.isWhite != isWhite;
}

class LiquidBackground extends StatefulWidget {
  final bool isWhite;
  final Widget child;

  const LiquidBackground({
    super.key,
    required this.isWhite,
    required this.child,
  });

  @override
  State<LiquidBackground> createState() => _LiquidBackgroundState();
}

class _LiquidBackgroundState extends State<LiquidBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 30));
    if (kAnimatedBackground) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.isWhite ? const Color(0xFFEEF2FA) : const Color(0xFF000000);
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _BlobPainter(widget.isWhite, repaint: _c),
              size: Size.infinite,
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

// ───────────────────────── Нажатие с анимацией ─────────────────────────

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;

  const _Pressable({
    required this.child,
    required this.onTap,
    this.pressedScale = 0.96,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────── Стеклянная карточка ─────────────────────────

class _GlassRimPainter extends CustomPainter {
  final double radius;
  final bool isWhite;

  _GlassRimPainter(this.radius, this.isWhite);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius)).deflate(0.6);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withOpacity(isWhite ? 0.95 : 0.55),
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.0),
          Colors.white.withOpacity(isWhite ? 0.55 : 0.30),
        ],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect, rim);

    final highlight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.white.withOpacity(isWhite ? 0.75 : 0.22),
          Colors.white.withOpacity(0.0),
        ],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(1.4), highlight);
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.isWhite != isWhite;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final bool isWhite;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    required this.isWhite,
    this.padding = const EdgeInsets.all(18),
    this.radius = 28,
    this.blur = 26,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Color top = isWhite ? Colors.white.withOpacity(0.62) : Colors.white.withOpacity(0.14);
    Color bottom = isWhite ? Colors.white.withOpacity(0.32) : Colors.white.withOpacity(0.04);
    if (tint != null) {
      top = Color.alphaBlend(tint!.withOpacity(0.32), top);
      bottom = Color.alphaBlend(tint!.withOpacity(0.12), bottom);
    }

    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: child,
    );

    body = CustomPaint(
      foregroundPainter: _GlassRimPainter(radius, isWhite),
      child: body,
    );

    if (blur > 0) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: body,
      );
    }

    Widget card = ClipRRect(borderRadius: borderRadius, child: body);

    if (onTap != null) {
      card = _Pressable(onTap: onTap, pressedScale: 0.985, child: card);
    }
    return card;
  }
}

// ───────────────────────── Кнопки ─────────────────────────

class GlassButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isWhite;
  final bool active;
  final bool danger;
  final bool expand;
  final VoidCallback? onPressed;

  const GlassButton({
    super.key,
    required this.label,
    required this.isWhite,
    required this.onPressed,
    this.icon,
    this.active = false,
    this.danger = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    final Color? tint = danger ? p.danger : (active ? p.accent : null);
    final Color textColor = danger ? p.danger : (active ? p.accent : p.fg);

    return Opacity(
      opacity: onPressed == null ? 0.45 : 1.0,
      child: _Pressable(
        onTap: onPressed,
        child: GlassCard(
          isWhite: isWhite,
          radius: 999,
          blur: 18,
          tint: tint,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 19, color: textColor),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final bool isWhite;
  final bool danger;
  final double size;
  final VoidCallback? onTap;

  const GlassIconButton({
    super.key,
    required this.icon,
    required this.isWhite,
    required this.onTap,
    this.danger = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: _Pressable(
        onTap: onTap,
        child: GlassCard(
          isWhite: isWhite,
          radius: 999,
          blur: 16,
          tint: danger ? p.danger : null,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.46, color: danger ? p.danger : p.fg),
          ),
        ),
      ),
    );
  }
}

class GlassChip extends StatelessWidget {
  final String label;
  final bool isWhite;
  final bool selected;
  final bool mono;
  final IconData? icon;
  final VoidCallback? onTap;

  const GlassChip({
    super.key,
    required this.label,
    required this.isWhite,
    required this.onTap,
    this.selected = false,
    this.mono = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    final color = selected ? p.accent : p.fg;
    return _Pressable(
      onTap: onTap,
      child: GlassCard(
        isWhite: isWhite,
        radius: 999,
        blur: 10,
        tint: selected ? p.accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlassChoiceTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isWhite;
  final VoidCallback onTap;

  const GlassChoiceTile({
    super.key,
    required this.label,
    required this.icon,
    required this.isWhite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    return _Pressable(
      onTap: onTap,
      child: GlassCard(
        isWhite: isWhite,
        radius: 28,
        blur: 16,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 96,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: p.accent),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: p.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Поле ввода ─────────────────────────

class GlassTextField extends StatelessWidget {
  final TextEditingController controller;
  final bool isWhite;
  final FocusNode? focusNode;
  final String? label;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final int maxLines;
  final bool autofocus;
  final bool mono;

  const GlassTextField({
    super.key,
    required this.controller,
    required this.isWhite,
    this.focusNode,
    this.label,
    this.hint,
    this.keyboardType,
    this.onSubmitted,
    this.suffix,
    this.maxLines = 1,
    this.autofocus = false,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    return GlassCard(
      isWhite: isWhite,
      radius: maxLines > 1 ? 24 : 999,
      blur: 18,
      padding: EdgeInsets.only(left: 20, right: suffix == null ? 20 : 6, top: 4, bottom: 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        maxLines: maxLines,
        keyboardType: keyboardType ?? (maxLines > 1 ? TextInputType.multiline : null),
        textInputAction: maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
        onSubmitted: onSubmitted,
        cursorColor: p.accent,
        style: TextStyle(
          color: p.fg,
          fontSize: 16,
          fontFamily: mono ? 'monospace' : null,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: p.subtle),
          hintStyle: TextStyle(color: p.subtle),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

// ───────────────────────── Прогресс и подписи ─────────────────────────

class GlassProgressBar extends StatelessWidget {
  final double value;
  final bool isWhite;
  final Color? color;
  final double height;

  const GlassProgressBar({
    super.key,
    required this.value,
    required this.isWhite,
    this.color,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(isWhite);
    final c = color ?? p.accent;
    final v = value.clamp(0.0, 1.0).toDouble();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fillWidth = constraints.maxWidth * v;
        return Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(height),
            color: p.fg.withOpacity(0.10),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: fillWidth,
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height),
                gradient: LinearGradient(
                  colors: [c.withOpacity(0.55), c],
                ),
                boxShadow: [
                  BoxShadow(color: c.withOpacity(0.55), blurRadius: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class GlassLabel extends StatelessWidget {
  final String text;
  final bool isWhite;

  const GlassLabel(this.text, {super.key, required this.isWhite});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: GlassPalette(isWhite).subtle,
      ),
    );
  }
}