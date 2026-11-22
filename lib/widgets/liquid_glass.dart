import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Сила размытия фона за стеклом. Меньше = фон виден чётче, как в iOS.
/// 0.42 — сбалансированно; 0.25 — почти прозрачное; 0.6 — матовое.
const double kGlassBlurScale = 0.42;

// ───────────────────────── Палитра ─────────────────────────

class GlassPalette {
  final bool isWhite;
  const GlassPalette(this.isWhite);

  Color get accent => isWhite ? const Color(0xFF16A34A) : const Color(0xFF5BF277);
  Color get fg => isWhite ? const Color(0xFF0B0B12) : Colors.white;
  Color get subtle => isWhite ? const Color(0x990B0B12) : const Color(0xA6FFFFFF);
  Color get danger => const Color(0xFFFF6B7A);
  Color get success => isWhite ? const Color(0xFF16A34A) : const Color(0xFF5BF277);
}

// ───────────────────────── Фон ─────────────────────────

// ───────────────────────── Фон: зелёные волны ─────────────────────────

class _WavesPainter extends CustomPainter {
  final bool isWhite;

  _WavesPainter(this.isWhite);

  static const List<Offset> _waveA = [
    Offset(1.0068, 0.1893),
    Offset(0.9155, 0.1934),
    Offset(0.8216, 0.2086),
    Offset(0.7512, 0.2302),
    Offset(0.6925, 0.2546),
    Offset(0.6338, 0.2817),
    Offset(0.5751, 0.3169),
    Offset(0.5164, 0.3467),
    Offset(0.446, 0.3765),
    Offset(0.3873, 0.4009),
    Offset(0.2934, 0.4252),
    Offset(0.1761, 0.4523),
    Offset(0.0704, 0.4794),
    Offset(-0.0056, 0.5011),
  ];

  static const List<Offset> _waveB = [
    Offset(-0.0094, 0.3677),
    Offset(0.1174, 0.3548),
    Offset(0.3169, 0.3413),
    Offset(0.4695, 0.3304),
    Offset(0.5516, 0.3142),
    Offset(0.6338, 0.2844),
  ];

  static const List<Offset> _waveC = [
    Offset(1.0058, 0.4078),
    Offset(0.9272, 0.4605),
    Offset(0.8333, 0.5038),
    Offset(0.7394, 0.5336),
  ];

  static const List<Offset> _waveD = [
    Offset(-0.0113, 0.9761),
    Offset(0.1408, 0.9263),
    Offset(0.2347, 0.9144),
    Offset(0.3521, 0.9209),
    Offset(0.4695, 0.9399),
    Offset(0.5634, 0.9491),
    Offset(0.6338, 0.948),
    Offset(0.7277, 0.929),
    Offset(0.8216, 0.9155),
    Offset(0.9272, 0.9101),
    Offset(1.0058, 0.9148),
  ];

  static const List<Offset> _waveE = [
    Offset(0.4577, 1.0076),
    Offset(0.5282, 0.9832),
    Offset(0.5869, 0.9642),
    Offset(0.6338, 0.9491),
  ];

  Path _path(List<Offset> pts, Size size) {
    Offset pt(int i) {
      final k = math.max(0, math.min(pts.length - 1, i));
      return Offset(pts[k].dx * size.width, pts[k].dy * size.height);
    }

    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pt(i - 1);
      final p1 = pt(i);
      final p2 = pt(i + 1);
      final p3 = pt(i + 2);
      final c1 = p1 + (p2 - p0) / 6;
      final c2 = p2 - (p3 - p1) / 6;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _ambient(Canvas canvas, Size size, double fx, double fy, double fr, Color c, double alpha) {
    final center = Offset(fx * size.width, fy * size.height);
    final r = fr * size.width;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [c.withOpacity(alpha), c.withOpacity(alpha * 0.22), c.withOpacity(0.0)],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  void _wave(Canvas canvas, Size size, List<Offset> pts, List<double> a, {double scale = 1.0}) {
    final rect = Offset.zero & size;
    final path = _path(pts, size);
    final k = isWhite ? 0.85 : 1.0;

    final glow = isWhite ? const Color(0xFF22C55E) : const Color(0xFF1ADC32);
    final mid = isWhite ? const Color(0xFF16A34A) : const Color(0xFF40FF52);
    final core = isWhite ? const Color(0xFF15803D) : const Color(0xFFB8FFBC);

    Shader grad(Color c, double m) {
      double v(double x) => (x * m * k).clamp(0.0, 1.0).toDouble();
      return LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [c.withOpacity(v(a[0])), c.withOpacity(v(a[1])), c.withOpacity(v(a[2]))],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26 * scale
        ..shader = grad(glow, 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9 * scale
        ..shader = grad(glow, 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale
        ..shader = grad(mid, 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * scale
        ..shader = grad(core, 1.0),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = isWhite ? const Color(0xFF22C55E) : const Color(0xFF1FFF3F);
    final soft = isWhite ? 1.3 : 1.0;

    // Мягкое зелёное свечение (стекло «ловит» его сквозь размытие).
    _ambient(canvas, size, 1.00, 0.17, 0.62, g, 0.20 * soft);
    _ambient(canvas, size, 0.00, 0.72, 0.50, g, 0.09 * soft);
    _ambient(canvas, size, 1.00, 0.60, 0.45, g, 0.05 * soft);
    _ambient(canvas, size, 0.78, 0.97, 0.55, g, 0.20 * soft);

    _wave(canvas, size, _waveA, const [0.10, 0.45, 1.0]);
    _wave(canvas, size, _waveB, const [0.10, 0.25, 0.45], scale: 0.8);
    _wave(canvas, size, _waveC, const [0.0, 0.03, 0.08], scale: 0.7);
    _wave(canvas, size, _waveD, const [0.20, 0.80, 1.0]);
    _wave(canvas, size, _waveE, const [0.15, 0.55, 0.95], scale: 0.85);
  }

  @override
  bool shouldRepaint(covariant _WavesPainter oldDelegate) => oldDelegate.isWhite != isWhite;
}

class LiquidBackground extends StatelessWidget {
  final bool isWhite;
  final Widget child;

  const LiquidBackground({
    super.key,
    required this.isWhite,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final base = isWhite ? const Color(0xFFE3EEE6) : const Color(0xFF000000);
    return ColoredBox(
      color: base,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _WavesPainter(isWhite),
              size: Size.infinite,
            ),
          ),
          child,
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

/// Тень вокруг стекла (только снаружи, внутрь стекла не попадает).
class _GlassShadowPainter extends CustomPainter {
  final double radius;
  final bool isWhite;

  _GlassShadowPainter(this.radius, this.isWhite);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 4 || size.height < 4) return;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final outer = Path()
      ..addRect(Rect.fromLTWH(-120, -120, size.width + 240, size.height + 240));
    final hole = Path()..addRRect(rrect);
    final clip = Path.combine(PathOperation.difference, outer, hole);

    final big = size.shortestSide > 80;
    canvas.save();
    canvas.clipPath(clip);

    // Контактная тень: придаёт объём и отделяет стекло от фона.
    canvas.drawRRect(
      rrect.shift(Offset(0, big ? 10 : 6)),
      Paint()
        ..color = (isWhite ? const Color(0xFF0E3B1C) : Colors.black).withOpacity(isWhite ? 0.20 : 0.60)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, big ? 16 : 9),
    );

    // Лёгкое зелёное свечение вокруг стекла на тёмной теме.
    if (!isWhite) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = const Color(0xFF39FF5A).withOpacity(0.07)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, big ? 22 : 12),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassShadowPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.isWhite != isWhite;
}

/// Кромка, блик и «толщина» жидкого стекла.
class _GlassRimPainter extends CustomPainter {
  final double radius;
  final bool isWhite;

  _GlassRimPainter(this.radius, this.isWhite);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 4 || size.height < 4) return;
    final rect = Offset.zero & size;
    final base = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final acc = GlassPalette(isWhite).accent;
    final edgeW = math.min(size.shortestSide * 0.20, 14.0);

    canvas.save();
    canvas.clipRRect(base);

    // 1. Свет вдоль кромки: ощущение толщины и преломления на краю стекла.
    canvas.drawRRect(
      base.deflate(edgeW / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeW
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, edgeW * 0.55)
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(isWhite ? 0.90 : 0.45),
            Colors.white.withOpacity(isWhite ? 0.12 : 0.04),
            Colors.white.withOpacity(isWhite ? 0.12 : 0.04),
            acc.withOpacity(isWhite ? 0.60 : 0.42),
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ).createShader(rect),
    );

    // 2. Мокрый блик сверху.
    final glossH = math.min(size.height * 0.34, 30.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width * 0.07, 2.5, size.width * 0.86, glossH),
        Radius.circular(glossH),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(isWhite ? 0.60 : 0.22),
            Colors.white.withOpacity(0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 2.5, size.width, glossH)),
    );

    // 3. Перелив: мягкий зелёно-салатовый блик, который «подхватывает» цвет фона.
    canvas.drawRRect(
      base,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            acc.withOpacity(isWhite ? 0.14 : 0.16),
            acc.withOpacity(0.0),
            const Color(0xFFC8FFB0).withOpacity(isWhite ? 0.0 : 0.07),
            acc.withOpacity(isWhite ? 0.10 : 0.13),
          ],
          stops: const [0.0, 0.38, 0.68, 1.0],
        ).createShader(rect),
    );
    canvas.restore();

    // 4. Яркая тонкая кромка (зеркальный край стекла).
    canvas.drawRRect(
      base.deflate(0.7),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (isWhite ? Colors.white : const Color(0xFFE4FFE8)).withOpacity(isWhite ? 1.0 : 0.85),
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.0),
            (isWhite ? Colors.white : const Color(0xFF55F06A)).withOpacity(isWhite ? 0.9 : 0.55),
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ).createShader(rect),
    );

    // 5. Тонкий тёмный контур снаружи — чтобы стекло читалось на светлом фоне.
    if (isWhite) {
      canvas.drawRRect(
        base.deflate(0.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = const Color(0xFF0E3B1C).withOpacity(0.12),
      );
    }
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
    this.blur = 10,
    this.tint,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    Color top = isWhite ? Colors.white.withOpacity(0.42) : Colors.white.withOpacity(0.08);
    Color bottom = isWhite ? Colors.white.withOpacity(0.16) : Colors.white.withOpacity(0.025);
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

    final sigma = blur * kGlassBlurScale;
    if (sigma > 0.3) {
      body = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: body,
      );
    }

    Widget card = ClipRRect(borderRadius: borderRadius, child: body);
    card = CustomPaint(
      painter: _GlassShadowPainter(radius, isWhite),
      child: card,
    );

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
          blur: 10,
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
          blur: 0,
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
        blur: 0,
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
        blur: 8,
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
      blur: 8,
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