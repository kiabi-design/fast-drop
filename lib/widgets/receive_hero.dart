import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

enum ReceiveState { waiting, receiving, sending, off, error }

/// Главная карточка: название устройства и анимация ожидания отправителя.
class ReceiveHero extends StatefulWidget {
  final String deviceName;
  final List<String> ips;
  final ReceiveState state;
  final bool isWhite;
  final bool isIos;
  final VoidCallback onTap;
  final ValueChanged<String> onCopyIp;

  const ReceiveHero({
    super.key,
    required this.deviceName,
    required this.ips,
    required this.state,
    required this.isWhite,
    required this.isIos,
    required this.onTap,
    required this.onCopyIp,
  });

  @override
  State<ReceiveHero> createState() => _ReceiveHeroState();
}

class _ReceiveHeroState extends State<ReceiveHero> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  bool get _animated =>
      widget.state == ReceiveState.waiting ||
      widget.state == ReceiveState.receiving ||
      widget.state == ReceiveState.sending;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
    if (_animated) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant ReceiveHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_animated && !_c.isAnimating) {
      _c.repeat();
    } else if (!_animated && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _stateColor(GlassPalette p) {
    switch (widget.state) {
      case ReceiveState.waiting:
        return p.accent;
      case ReceiveState.receiving:
        return p.success;
      case ReceiveState.sending:
        return p.accent;
      case ReceiveState.off:
        return p.subtle;
      case ReceiveState.error:
        return p.danger;
    }
  }

  String _statusText() {
    switch (widget.state) {
      case ReceiveState.waiting:
        return 'Ожидание отправителя';
      case ReceiveState.receiving:
        return 'Идёт приём файла';
      case ReceiveState.sending:
        return 'Идёт отправка';
      case ReceiveState.off:
        return 'Приём выключен';
      case ReceiveState.error:
        return 'Не удалось включить приём';
    }
  }

  String _hintText() {
    switch (widget.state) {
      case ReceiveState.waiting:
        return 'Другие устройства видят вас в сети';
      case ReceiveState.receiving:
        return 'Не закрывайте приложение';
      case ReceiveState.sending:
        return 'Не закрывайте приложение';
      case ReceiveState.off:
        return 'Нажмите, чтобы включить';
      case ReceiveState.error:
        return 'Нажмите, чтобы повторить';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = GlassPalette(widget.isWhite);
    final color = _stateColor(p);
    final showDots = widget.state == ReceiveState.waiting;
    final tappable = widget.state == ReceiveState.waiting ||
        widget.state == ReceiveState.off ||
        widget.state == ReceiveState.error;

    return GlassCard(
      isWhite: widget.isWhite,
      radius: 36,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
      onTap: tappable ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final dotCount = 1 + ((t * 3).floor() % 3);
          final dots = '.' * dotCount;

          return Column(
            children: [
              SizedBox(
                height: 210,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size.infinite,
                      painter: _RingsPainter(
                        t: t,
                        color: color,
                        animated: _animated,
                        speed: widget.state == ReceiveState.waiting ? 1 : 2,
                      ),
                    ),
                    GlassCard(
                      isWhite: widget.isWhite,
                      radius: 999,
                      blur: 12,
                      tint: color,
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        width: 92,
                        height: 92,
                        child: Icon(
                          widget.isIos ? Icons.phone_iphone_rounded : Icons.phone_android_rounded,
                          size: 44,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.deviceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.fg,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      _statusText(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (showDots)
                    SizedBox(
                      width: 20,
                      child: Text(
                        dots,
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _hintText(),
                textAlign: TextAlign.center,
                style: TextStyle(color: p.subtle, fontSize: 12),
              ),
              if (widget.ips.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: widget.ips.map((ip) {
                    return GlassChip(
                      label: ip,
                      mono: true,
                      isWhite: widget.isWhite,
                      onTap: () => widget.onCopyIp(ip),
                    );
                  }).toList(),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final double t;
  final Color color;
  final bool animated;
  final int speed;

  _RingsPainter({
    required this.t,
    required this.color,
    required this.animated,
    required this.speed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const startR = 50.0;
    final maxR = math.min(size.width, size.height) / 2;

    if (!animated) {
      canvas.drawCircle(
        center,
        startR + 16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color.withOpacity(0.25),
      );
      return;
    }

    for (int i = 0; i < 3; i++) {
      final ph = (t * speed + i / 3.0) % 1.0;
      final r = startR + (maxR - startR) * ph;
      final fade = 1.0 - ph;

      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.fill
          ..color = color.withOpacity(0.07 * fade),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withOpacity(0.5 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter old) =>
      old.t != t || old.color != color || old.animated != animated || old.speed != speed;
}