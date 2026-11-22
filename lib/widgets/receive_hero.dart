import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'liquid_glass.dart';

enum ReceiveState { waiting, receiving, sending, off, error }

/// Главная карточка: название устройства и анимация ожидания отправителя.
///
/// Оптимизация: круги рисуются отдельным слоем (RepaintBoundary) и обновляются
/// всего ~15 раз в секунду, остальная карточка не перерисовывается. Анимация
/// останавливается, когда приложение свёрнуто или карточка закрыта другим экраном.
class ReceiveHero extends StatefulWidget {
  final String deviceName;
  final List<String> ips;
  final ReceiveState state;
  final bool isWhite;
  final IconData icon;
  final VoidCallback onTap;
  final ValueChanged<String> onCopyIp;

  const ReceiveHero({
    super.key,
    required this.deviceName,
    required this.ips,
    required this.state,
    required this.isWhite,
    required this.icon,
    required this.onTap,
    required this.onCopyIp,
  });

  @override
  State<ReceiveHero> createState() => _ReceiveHeroState();
}

class _ReceiveHeroState extends State<ReceiveHero> with WidgetsBindingObserver {
  /// Интервал обновления кругов, мс (66 мс ≈ 15 кадров/с).
  static const int _frameMs = 66;

  final ValueNotifier<double> _phase = ValueNotifier<double>(0.0);
  final ValueNotifier<int> _dots = ValueNotifier<int>(1);
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;
  bool _foreground = true;
  bool _tickerOn = true;

  bool get _animated =>
      widget.state == ReceiveState.waiting ||
      widget.state == ReceiveState.receiving ||
      widget.state == ReceiveState.sending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Когда поверх открыт другой экран, Flutter отключает тикеры этого.
    _tickerOn = TickerMode.of(context);
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant ReceiveHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _phase.dispose();
    _dots.dispose();
    super.dispose();
  }

  void _syncTimer() {
    final shouldRun = _animated && _foreground && _tickerOn;
    if (shouldRun && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: _frameMs), (_) => _tick());
    } else if (!shouldRun && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _tick() {
    final ms = _clock.elapsedMilliseconds;
    _phase.value = (ms % 3000) / 3000.0;
    if (widget.state == ReceiveState.waiting) {
      final n = 1 + ((ms ~/ 500) % 3);
      if (_dots.value != n) _dots.value = n;
    }
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
      blur: 14,
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
      onTap: tappable ? widget.onTap : null,
      child: Column(
        children: [
          SizedBox(
            height: 210,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Отдельный слой: перерисовываются только круги.
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _RingsPainter(
                      phase: _phase,
                      color: color,
                      animated: _animated,
                      speed: widget.state == ReceiveState.waiting ? 1 : 2,
                    ),
                  ),
                ),
                GlassCard(
                  isWhite: widget.isWhite,
                  radius: 999,
                  blur: 0,
                  tint: color,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Icon(widget.icon, size: 44, color: color),
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
                  child: ValueListenableBuilder<int>(
                    valueListenable: _dots,
                    builder: (context, n, _) => Text(
                      '.' * n,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
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
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final ValueListenable<double> phase;
  final Color color;
  final bool animated;
  final int speed;

  _RingsPainter({
    required this.phase,
    required this.color,
    required this.animated,
    required this.speed,
  }) : super(repaint: phase);

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

    final t = phase.value;
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
      old.color != color || old.animated != animated || old.speed != speed;
}